# Parser fidelity — are "unmatched" units real app gaps, or lab artifacts?

This document answers one recurring question: **when the lab reports a message as
`unmatched`, is that a genuine gap in the Totals app's parser, or an artifact of the
lab reimplementing the parser incorrectly / against a stale ruleset?**

**Verdict: genuine app gaps.** The lab is a faithful mirror of the app's match
pipeline, and where it *does* diverge it is strictly *more lenient* than the app —
so the unmatched set is a **lower bound** on the app's real gaps, never an inflation
of them. There is no stage at which the lab reports `unmatched` for a message the app
would actually parse.

> **Living doc.** Last verified against Totals git rev `85694be` (vendored snapshot
> dated 2026-06-30), audited 2026-07-03. If any of the source locations below change,
> re-run the checks in *"How to re-verify"* and update the table. The lab's own
> `diff` logic-drift guard (`lib/baseline/logic_fidelity.dart`, signature in
> `vendor/totals/SNAPSHOT.md`) is the automated tripwire for the port drifting.

---

## The two things a "tool artifact" could be

1. **Stale snapshot** — the vendored `sms_patterns.json` / `banks.json` being older
   than the app's live assets, so the lab tests against a ruleset the app has moved
   past.
2. **Fidelity drift** — the lab's reimplemented match logic (preprocessing, regex
   flags, bank resolution, pattern scoping, accept-gate) diverging from the real
   `PatternParser` / `SmsService`.

Both were checked stage by stage.

## Stage-by-stage audit

Every stage of the match pipeline is either **identical** to the app or makes the
lab **more lenient** (a better chance to match than the app gives). Neither can
produce a false `unmatched`.

| Stage | Real app | Lab | Verdict |
|---|---|---|---|
| **Snapshot** | `app/assets/{sms_patterns,banks}.json` @ rev `85694be` | vendored copy is **byte-identical** to *both* `totals/` and `totals-v41/` assets, same rev | **not stale** |
| **Preprocessing** | `cleanSmsText()` = `return text.trim();` — extra normalization is commented out (`sms_config_service.dart:37`) | `message.body.trim()` (`totals_parser_adapter.dart` `parse()`) | **identical** |
| **Regex flags** | `RegExp(regex, caseSensitive:false, multiLine:true, dotAll:true)` (`pattern_parser.dart:20`) | same flags in `SmsPattern.regExp` (`sms_pattern.dart:57`) | **identical** |
| **Bank resolution** | `_normalizeSenderToken` = `toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'),'')`; `_addressMatchesCode` = `normalizedAddress.contains(normalizedCode)`; first match wins (`sms_service.dart:315,319,326`) | `_bankForSender` + `_normalizeSenderToken` — **char-for-char the same** logic (`totals_parser_adapter.dart`) | **identical** |
| **Pattern scoping** | `patterns.where((p) => p.bankId == bank.id)` (`sms_service.dart:787`) | `_candidatesFor` → `_patternsByBank[bank.id]` (`totals_parser_adapter.dart`) | **identical** |
| **Null-bank sender** | `getRelevantBank` → null ⇒ `ParseStatus.noBank`, **tries no patterns** (`sms_service.dart:765`) | falls back to trying **all** patterns | lab **more lenient** |
| **Unregistered account** | no registered account for the bank ⇒ `ParseStatus.unregisteredBank`, **skips parsing** (`sms_service.dart:778`) | gate not modelled — parses regardless | lab **more lenient** |

### Why the two "more lenient" rows can't create false gaps

- **Null-bank:** for a `bank: null` message the lab tries the *entire* ruleset. If
  nothing matched (i.e. it landed in `unmatched`), then the app — which tries
  *nothing* for a null-bank sender — cannot possibly parse it either. So **every
  `bank: null` unmatched unit is a guaranteed real gap.**
- **Unregistered account:** the app skips whole banks the user hasn't registered, so
  the app parses *fewer* messages than the lab shows as `success`. This makes the
  lab's coverage number **optimistic**, never pessimistic.

## The critical semantic distinction: `unmatched` ≠ extraction failure

- **`unmatched`** = **no pattern's regex fired**. This is a *missing pattern* — a real
  coverage gap.
- **matched-but-rejected** = a regex fired, but the app's accept-gate dropped the
  extraction (e.g. amount missing, like the Telebirr Reversal bug). In the lab these
  land in **`successUnits` with `appAccepted: false`** — **not** in `unmatched`
  (`totals_parser_adapter.dart` `parse()` returns `firstMatchedButRejected` with
  `matched: true`; gate mirrored in `field_extractor.dart` accept-gate).

So extraction/accept-gate bugs never pollute the unmatched pile. As of the
2026-07-03 export there was exactly **one** matched-but-rejected family (the Reversal,
since fixed).

## Residual caveats (honest edges, not tool bugs)

1. **Mis-registered patterns show as unmatched-with-a-bank.** If a message's correct
   pattern is registered under a different `bankId` than its sender resolves to, both
   app *and* lab scope past it and miss. That is a genuine app defect (wrong
   registration), correctly surfaced — just a different root cause than "no pattern
   exists."
2. **Bank iteration order.** The app iterates banks in DB/config order, the lab in
   `banks.json` order. If one sender address matched *two* banks' codes, first-match
   could differ. In practice the codes are distinct enough that no collision occurs,
   but a future ambiguous code could expose this.
3. **Optimism, not pessimism.** Because of the unregistered-account gate, a specific
   user's real-device coverage can be *lower* than the export's pattern-set coverage.
   The export measures "does a pattern exist and match," not "will this user's app
   record it."

## How to re-verify (when facts may have changed)

Re-run these if the app is bumped past rev `85694be` or the lab's port is touched:

```bash
# 1. Snapshot still in sync with the app assets?
cmp sms_pattern_lab/vendor/totals/sms_patterns.json totals/app/assets/sms_patterns.json
cmp sms_pattern_lab/vendor/totals/banks.json        totals/app/assets/banks.json
git -C totals rev-parse --short HEAD          # compare to SNAPSHOT.md rev

# 2. Preprocessing still just trim()?
grep -A6 'String cleanSmsText' totals/app/lib/services/sms_config_service.dart

# 3. Regex flags unchanged in app AND lab?
grep -n 'caseSensitive\|multiLine\|dotAll' totals/app/lib/utils/pattern_parser.dart
grep -n 'caseSensitive\|multiLine\|dotAll' sms_pattern_lab/lib/models/sms_pattern.dart

# 4. Bank resolution + scoping unchanged?
grep -n '_normalizeSenderToken\|_addressMatchesCode\|bankId == bank.id' totals/app/lib/services/sms_service.dart

# 5. Automated drift tripwire (compares mirrored logic-source hashes):
dart run bin/sms_pattern_lab.dart diff --from=/path/to/totals/app   # non-zero exit on drift
```

If (2) stops being a bare `trim()`, or (3)/(4) diverge between app and lab, the
"identical" rows above are no longer safe — the port must be re-checked against
`totals/app/lib/utils/pattern_parser.dart` and `sms_service.dart`, and this verdict
revisited.
