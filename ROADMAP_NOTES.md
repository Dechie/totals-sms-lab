# ROADMAP_NOTES.md — implementation guide for V2 / V3 / V4

> **Read this before implementing any roadmap version.** It records the design
> decisions baked into V1, the exact seams to plug into, the invariants you must
> not break, and the refactors each version needs — with file/line references.
> It exists so we never re-derive this from scratch, and so V2/V3/V4 land
> consistently with the architecture instead of fighting it.
>
> Keep it current: when you implement a version, update its section from "plan"
> to "done" and note anything that turned out differently.

**North star (founding insights).** See [`INSIGHTS.md`](INSIGHTS.md) for the
canonical statements. In short: (1) **discovery at scale** — surface formats the
parser *never covered*, from thousands of real messages, not just drift; and
(2) **actionable patterns, not numbers** — the deliverable is generic message
shapes grouped into **discrete categories, each a confident regex target**;
clustering exists to produce those categories. Weigh every roadmap item by
"does this help hand developers confident, regex-ready categories from real data
at scale?" Drift detection is the *trust layer*, not the point.

---

## 0. Invariants (do not break these)

These are load-bearing promises the tool makes. Every version must preserve them
unless this doc is updated with an explicit, justified exception.

1. **Zero third-party runtime dependencies.** `pubspec.yaml` has an empty
   `dependencies:` block on purpose. V2 (Levenshtein) and V3 (TF-IDF/cosine) are
   pure-Dart and must stay dependency-free. Only `dev_dependencies` (test, lints)
   may grow.
2. **Fully offline.** No network calls, no CDN, no fetched assets. The HTML
   report asserts this in a test (see V4 · interactive HTML).
3. **Deterministic output.** No `Date.now()`/`Random` inside analysis logic
   (timestamps are fine in the CLI layer for ledgers). Same inputs ⇒ identical
   output — this is what makes coverage trends and baseline signatures meaningful.
4. **Fidelity to the production parser.** The match/no-match verdict must equal
   Totals' runtime decision. The mirrored rules are documented in
   `REFERENCE.md → Fidelity to the production parser` and implemented in
   `lib/parser_adapter/totals_parser_adapter.dart` + `lib/models/sms_pattern.dart`
   (regex flags `caseSensitive:false, multiLine:true, dotAll:true`; sender
   normalization; body trim). If Totals' `PatternParser` changes, update these.
5. **The lab never mutates the production app.** It only reads vendored
   snapshots / device inbox. No write path into Totals.

---

## 1. Architecture map (where things plug in)

```
dataset/adb ─▶ ParserAdapter.parseAll ─▶ CoverageAnalyzer ─▶ SimilarityGrouper ─▶ reports
                    │                          │                    │
              (fidelity seam)          (per-bank coverage)   (V2/V3 plug in HERE)
```

Key seams and the files that own them:

| Seam | File | Role | Touched by |
|---|---|---|---|
| `ParserAdapter` (abstract) | `lib/parser_adapter/parser_adapter.dart` | host-parser contract | V4 plugins |
| `TotalsParserAdapter` | `lib/parser_adapter/totals_parser_adapter.dart` | Totals impl + vendoring | V4 plugins |
| `Normalizer` | `lib/normalizer/normalizer.dart` | body → placeholder template | V2/V3 input, V4 regex-gen |
| `ExactClusterer` | `lib/clustering/exact_clusterer.dart` | O(n) exact grouping | V2 (runs before similarity) |
| `SimilarityGrouper` (abstract) | `lib/similarity/similarity_grouper.dart` | cluster → family grouping | **V2 / V3** |
| `TemplateCluster` | `lib/models/template_cluster.dart` | the unit clustered today | V2 (→ families) |
| `CoverageReport` | `lib/models/coverage_report.dart` | report data model | V2 (family-aware) |
| `AnalysisPipeline` | `lib/analysis/analysis_pipeline.dart` | orchestration | V2 (consume grouper return) |
| reports | `lib/reports/{markdown,html,svg_charts}.dart` | render | V2 families, V4 interactive |
| `ParserBaseline` / `fnv1a64` | `lib/baseline/parser_baseline.dart` | signature/fingerprint | V4 historical compare |
| `BaselineHistory` | `lib/baseline/baseline_history.dart` | baseline ledger | V3 trend, V4 regression |

---

## 2. Two cross-cutting promotions (do these at the start of the version that needs them)

The whole roadmap hinges on promoting two things from "label/summary" to
"first-class data". Both are additive. Doing each at the *start* of its version
avoids reworking reports twice.

### A. `TemplateCluster` → `TemplateFamily`  — ✅ DONE (V2 step 0)
Shipped: the grouper returns `List<TemplateFamily>`, the analyzer consumes it and
builds `CoverageReport.attributedFamilies`/`candidateFamilies`, reports render
families. `IdentityGrouper` (1 family/cluster) keeps V1 output identical.
(Historical context: the pipeline used to *discard* the grouper's return, and
similarity could only *tag* a cluster; both are now resolved.)

### B. Baseline history → **coverage** history  (needed first in **V4**)
`BaselineHistory` records parser *baselines* (signature, counts, rev), not
*coverage results*. Trend (V4) and regression/compare (V5) need a parallel store.
See "Coverage history" below.

---

## 3. V2 — Similarity engines: implement & plug in (action-verb → Levenshtein → TF-IDF/cosine)

**Scope:** implement the grouping engines behind the `SimilarityGrouper` seam,
producing `TemplateFamily` objects. V2's bar is **correctness + integration** —
engines working end-to-end and grouping templates into families. *Tuning* on real
data, fuzzy-grouping polish, dashboards and bank-specific reports are **V3**;
polished semantic families and trends are **V4**.

**Sequencing (locked):** lead with the cheapest, most deterministic method and
only escalate for what it misses. Algorithm 1 (exact normalization + hashing)
already shipped in V1.
1. **Action-verb grouping — PRIMARY.** An `Annotator` tags each template with an
   `actionVerb` from `action_words.txt` (`null` if none) — see
   ENRICHMENT_FIELDS.md. Group by verb + direction (credited/received/deposited →
   *incoming*; debited/paid/transferred/withdrawn → *outgoing*). Deterministic,
   O(n) lookup, zero training — does most of the semantic work *and* labels the
   family for free. This supersedes the older "Levenshtein first" plan.
2. **Levenshtein — near-identical wording.** Within a verb bucket, merge "typo"
   variants ("Transferred …" vs "Transfer of …") by edit-distance ratio.
3. **TF-IDF + cosine — FALLBACK.** Only for synonyms the lexicon + Levenshtein
   miss. Statistically weak on tiny corpora, so intentionally last, not the
   workhorse.

Also carry the enrichment fields (`actionVerb`, `shapeProfile`) on the family —
they feed grouping, labels, export, and the V5 regex suggester
(ENRICHMENT_FIELDS.md / FIELD_SHAPES.md).

**Why it matters for the founding insight:** large-scale discovery only pays off
if the long tail of never-covered variants collapses into a short, rankable list
of *distinct* gaps — otherwise "read thousands of messages" just produces
thousands of rows. Family-merging is what makes discovery output actionable.

### Why the ground is ready
- `SimilarityGrouper` seam + `IdentityGrouper` no-op already exist.
- Similarity runs on **normalized** templates (variable noise already removed) —
  far cheaper and more accurate than raw-text distance.
- `ExactClusterer` runs first, so similarity operates on *distinct templates* k,
  not n messages. Levenshtein at O(k²·L) is fine because normalization keeps k
  small. (If k ever gets large per bank, block by bank first — banks don't share
  families.)

### Required refactor (the prerequisite) — ✅ SHIPPED (V2 step 0)
This refactor is **done**: `TemplateFamily` exists (`lib/models/template_family.dart`),
the grouper returns families, `CoverageAnalyzer` builds them (per-bank for
attributed; separately for candidates), `CoverageReport` exposes
`attributedFamilies`/`candidateFamilies`, and console/Markdown/HTML render
families with dormant multi-member drill-down. `IdentityGrouper` is still the
default so V1 output is byte-identical. **Next: the `Annotator` + action-verb
grouper (step 1).** The original checklist, for reference:
1. **Introduce `TemplateFamily`** (suggested shape):
   ```dart
   class TemplateFamily {
     final String label;                 // e.g. "Outgoing transfers"
     final TemplateCluster representative;// highest-occurrence member
     final List<TemplateCluster> members;
     int get totalOccurrences => members.fold(0, (s, c) => s + c.occurrences);
     // priority should derive from totalOccurrences (see TemplateCluster.priority thresholds)
   }
   ```
2. **Change the grouper contract** to return families:
   `List<TemplateFamily> group(List<TemplateCluster> clusters)`. `IdentityGrouper`
   becomes "one family per cluster" (preserves V1 output).
3. **Pipeline must consume the return** (fix the ignored-return seam) and carry
   families into `CoverageReport` (add `List<TemplateFamily> families` or replace
   `unmatchedClusters`; keep a flat accessor for back-compat if convenient).
4. **Reports render families** with drill-down to member templates. Console: show
   family + member count. Markdown/HTML: family header, expandable members
   (HTML `<details>` already used for examples — reuse the pattern).
5. **Priority must aggregate** over family occurrences (today it's per-cluster:
   `TemplateCluster.priority`). The recipient-name-varying CBE transfer templates
   are the canonical case that under-ranks today — verify they collapse.

### Algorithm notes — action-verb lexicon (primary)
- New `Annotator` (post-normalization): scan the (lower-cased) template against
  `action_words.txt`; set `actionVerb` = the primary match (first-match, or a
  direction/priority order when several appear), else `null`. It's a **tag, not a
  strip** — the verb stays in the template.
- `SemanticVerbGrouper` (a `SimilarityGrouper`): within a bank, bucket clusters by
  `actionVerb` (and direction). O(n), deterministic, zero training; the verb also
  supplies the family `label`.
- `actionVerb == null` on a transactional-looking template ⇒ candidate **new
  action word** — surface it (self-improving lexicon).

### Algorithm notes — Levenshtein
- Standard two-row DP, pure Dart. Normalize by max length → similarity ratio;
  merge when `ratio ≥ threshold` (start ~0.9, expose as `--similarity=`).
- Runs **within a verb bucket** to merge near-identical wording.
- Cluster greedily: sort templates by occurrence desc; each becomes a family seed;
  fold in any unseeded template within threshold. Deterministic given the sort.
- **Block by `likelyBankId`** before pairwise — never merge across banks.

### Algorithm notes — TF-IDF + cosine (fallback)
- A `SimilarityGrouper` impl. Compose *after* the lexicon + Levenshtein (only for
  synonyms they miss). Same `TemplateFamily` contract.
- Tokenize normalized templates (split on non-word; drop placeholders or treat
  them as stop-tokens), build term-frequency vectors, idf over the template
  corpus, cosine similarity, merge ≥ threshold. All pure-Dart vector math,
  deterministic.
- **Caveat — why it's the fallback, not the workhorse:** the corpus is tiny (a
  handful of templates per bank), so TF-IDF is statistically weak. The
  `action_words.txt` lexicon does the reliable semantic grouping deterministically;
  TF-IDF only mops up synonyms the lexicon misses. Tune it in V3 (thresholds,
  tokenization); keep it conservative.

### Tests
- `Annotator`: tags the right `actionVerb` (and `null`) across the lexicon;
  picks a sensible primary when several verbs appear.
- Pure functions: Levenshtein distance/ratio; TF-IDF + cosine on known vectors.
- Grouper merges `Transferred <AMOUNT>` / `Transfer of <AMOUNT>` (same verb
  bucket); does NOT merge different verbs/unrelated templates; never across banks.
- Pipeline/report family-aware snapshot on `example/cbe_sms.json` (the transfer
  family should collapse the current `×1` fragments).

### Gotchas
- Don't merge on raw bodies — always the normalized template.
- Keep IdentityGrouper as the default until the engines are proven, so V1
  behavior is the fallback.
- V2 is "engines integrated," **not** "engines tuned" — resist perfecting
  thresholds here; that's V3, against real datasets.
- Apply families to **both** unmatched streams — attributed *and*
  `unknownSenderClusters` (the candidate-new-format discovery stream).

---

## 4. V3 — Tune on real data + grouping UX

The engines exist (V2); now make their output *good*. **No new algorithms** —
V3 is quality and presentation.

- **Tune against real datasets** — thresholds (`--similarity`), tokenization, the
  synonym list. Use `adb`-pulled corpora; verify families merge what they should
  and split what they shouldn't (precision/recall by eye on real banks).
- **Fuzzy template grouping** — the polished UX over V2's raw merging: stable
  family labels, sensible representatives, member drill-down in reports.
- **Parser health dashboards** — per-bank health built on *family-level* coverage
  (worst-covered banks, biggest missing families, trend arrow once V4 lands).
- **Bank-specific reports** — emit a focused report per bank parser.

---

## 5. V4 — Semantic families & trends

**(a) Polished semantic families.** Promote V2's TF-IDF/cosine output into named,
curated families ("Outgoing transfers", "Salary credits") with good labels — the
user-facing payoff of the cosine engine, once V3 has tuned it.

**(b) Trend analysis over time.** Track coverage across runs (the regression/
compare foundation for V5). `BaselineHistory` records parser *baselines*, not
*coverage results* — add a parallel store.

### Coverage history (the prerequisite for trend) — schema
`BaselineHistory` is NOT enough. Add a coverage-results ledger, e.g.
`coverage_history.json`, append-only, one record per analyzed run:
```jsonc
{
  "version": 1,
  "entries": [
    {
      "recordedAt": "2026-07-04T...",
      "baselineSignature": "95cc048f21a46e2f", // ties result to a parser version
      "datasetId": "<hash or label>",          // see "dataset identity" below
      "messageCount": 58,
      "overallCoverage": 75.9,
      "perBank": { "CBE": 75.9 },
      "topGaps": [ { "template": "...", "occurrences": 5, "bank": "CBE" } ]
    }
  ]
}
```
- **Dataset identity is essential.** Coverage can move because the *data* changed
  (each `adb pull` differs), not the parser. Define `datasetId` = a stable hash of
  the sorted message bodies (reuse `fnv1a64`), plus an optional human label. Only
  compare runs with the same `datasetId` for true parser-trend; otherwise label
  the comparison as "different data."
- A `trend` command reads this ledger and shows coverage over time for a fixed
  dataset, annotated with the baseline signature at each point (so you can see
  "coverage rose when baseline X→Y shipped").

### Tests
- TF-IDF/cosine pure functions (known vectors).
- Coverage-history append/dedup/roundtrip (mirror `baseline_history_test.dart`).
- `datasetId` stability (reordered messages → same id) and sensitivity (changed
  message → different id).

---

## 6. V5 — Productionization (regex suggestion, interactive HTML, CI, regression, compare, plugins)

### 6.1 Regex suggestion engine  (biggest payoff; depends on V2 engines + V3 tuning)
The `Normalizer` is almost the **inverse** of a regex generator: its placeholders
map to named capture groups.
- Build a placeholder→group table, e.g. `<AMOUNT>` → `(?<amount>[\d,.]+)`,
  `<ACCOUNT>` → `(?<account>[\d*]+)`, `<DATE>` → `(?<date>...)`, etc. (mirror the
  groups Totals' `PatternParser` actually reads: amount, balance, account,
  reference, type, time, serviceCharge, vat).
- Generation = take a family's representative normalized template, `RegExp.escape`
  the literal text between placeholders, substitute capture groups, allow flexible
  whitespace (`\s+`). Emit a candidate `SmsPattern` JSON ready to paste into
  Totals.
- **Suggest one regex per family, not per template** — that's why this depends on
  V2/V3. Validate the suggestion by running it back through the adapter over the
  family's members (it should now match them). Never auto-write into Totals
  (Invariant 5) — output a snippet + a "would now match N messages" check.

### 6.2 Interactive HTML reports — ⚠ breaks a current promise
- Today the HTML report is **script-free** and a test enforces it:
  `test/html_report_test.dart` → `expect(html, isNot(contains('<script')))` and
  `isNot(contains('cdn'))`; README sells "no JavaScript."
- Interactivity (filter/sort/drill-down) needs an **inline** `<script>` + embedded
  JSON. That keeps *self-contained* and *offline* (Invariants 1–2) but ends the
  *no-JS* claim. When you do this:
  - Relax the test to "no **external** script/resource" (assert no `src=`/`href=`
    to network, no `cdn`), instead of "no `<script>` at all".
  - Update REFERENCE.md wording (the "no JavaScript" line in the HTML reports
    section).
  - Keep a `--static` flag to emit the current no-JS report for environments that
    forbid inline scripts.

### 6.3 CI integration — partially shipped
- ✅ `diff` exits **3** on drift; ✅ `analyze --min-coverage=N` exits **4** below
  threshold (added in V1 prep). Exit codes documented in CLI help.
- Remaining: a `--json` output for `analyze` (machine-readable coverage for CI
  dashboards), and optionally per-bank thresholds. Keep the exit-code convention
  (0 ok · 1 error · 3 drift · 4 below-coverage; pick new codes for new gates).

### 6.4 Parser regression detection
- Definition: coverage **dropped** at baseline B vs baseline A **on the same
  dataset**. Needs (a) the coverage-history store (§5) and (b) `datasetId`
  matching. The baseline `signature` is the key that ties a coverage result to a
  parser version.
- Note: `diff` now also flags **logic** drift (regex flags, cleanSmsText, sender
  normalization, heuristic) via `vendor/totals/fidelity.json` (§8), so a Dart-side
  change is caught directly — not only as a downstream coverage drop. Coverage-
  history still matters for quantifying the *impact* of a regression.

### 6.5 Historical coverage comparison (the V5 `compare` command)
- Builds on `BaselineHistory` + the new coverage-history.
- For **pattern-level** "what changed between two historical points," the current
  ledger stores only **counts**, not per-pattern fingerprints. To diff arbitrary
  historical baselines, extend `BaselineRecord` to optionally store the
  lightweight fingerprint list `[(bankId, description, regexHash)]` (regexHash via
  `fnv1a64`, not the full regex — keeps the file small). Then `compare A B` can
  reuse `BaselineDiff` logic across history, not just vs the live app.

### 6.6 Plugin architecture (multiple parser projects)
- The `ParserAdapter` interface is the seam; the core (clustering/coverage/reports)
  is already adapter-agnostic. ✅ Reports now take `parserName` from
  `adapter.name` (V1 prep) instead of a hardcoded string.
- Remaining Totals-coupling to generalize, all in the CLI/vendoring layer:
  - sender filter default `['CBE']` — `bin/sms_pattern_lab.dart` `senderFilter()`.
  - vendored path `vendor/totals` and provenance parsing (`_snapshotProvenance`)
    are Totals-specific.
  - per-project config (name, vendor dir, default sender filter, provenance) →
    introduce an adapter registry / config file (e.g. `lab.config.json`) selecting
    the active adapter. Each adapter ships its own vendored snapshot dir.

---

## 7. Suggested ordering (cheapest path)

1. ✅ **V2 step 0 (DONE):** introduced `TemplateFamily`, fixed the ignored grouper
   return, made `CoverageReport` + reports family-aware (IdentityGrouper = one
   family per cluster, output unchanged). Applied to both unmatched streams.
2. **V2 step 1 (NEXT):** `Annotator` (tag `actionVerb` from `action_words.txt`) +
   `SemanticVerbGrouper` (bucket by verb + direction, sets family label) + tests.
   The primary, deterministic grouper.
3. **V2 step 2:** Levenshtein grouper (merge near-identical wording *within* a
   verb bucket) + `--similarity` flag + tests.
4. **V2 step 3:** TF-IDF + cosine grouper as fallback, composed last. Goal:
   integrated and producing families (correctness, not tuning).
5. **V3:** tune thresholds/tokenization/synonyms on real `adb` corpora; fuzzy
   grouping UX; parser health dashboards; bank-specific reports.
6. **V4:** polished semantic families; coverage-history store + `datasetId`;
   `trend` command.
7. **V5:** regex suggestion (needs families + `shapeProfile`) → `compare` (needs
   coverage history + fingerprints) → interactive HTML (relax the no-JS test) →
   plugin config.

Each step is additive and independently shippable. Update this file as you go.

---

## 8. Done-in-V1 prep (so you don't redo it)
- ✅ `parserName` decoupled from a hardcoded literal → flows from `adapter.name`
  (`AnalysisResult.parserName`, used by both reports).
- ✅ `analyze --min-coverage=N` CI gate (exit 4).
- ✅ Exit-code convention documented in CLI help (0/1/3/4).
- ✅ Seam pointer comments added in `analysis_pipeline.dart`,
  `similarity_grouper.dart`, `template_cluster.dart`, `baseline_history.dart`.
- ✅ **Candidate-new-formats discovery:** unmatched clusters from unrecognized
  senders are surfaced as a first-class stream (`CoverageReport.unknownSenderClusters`
  vs `attributedClusters`) in the CLI/Markdown/HTML reports — see §9.
- ✅ **DB ingestion (`tool/ingest_db.dart`):** pulls the app's on-device SQLite db
  via `adb run-as` (no app changes; debuggable builds) and dumps, via the
  `sqlite3` CLI:
  - `failed_parses` → a dataset — the app's **curated, pre-filtered** discovery
    signal (already gated by the app's `_looksLikeTransactionMessage`).
  - `sms_patterns` → a **live** baseline for `--against` / `--patterns`, closing
    the vendored-vs-runtime fidelity gap (round-trip preserves the signature).
- ✅ **Actionable-pattern improvements (Insight 2, the parts addressable without
  V2/V5):**
  - Normalizer abstracts **free-text fields** (`<NAME>` parenthesized + recipient
    `to/from … on`; `<MERCHANT>` `at … on`) — stops categories fragmenting by
    name and makes the skeleton map onto capture groups. (The CBE transfer
    category went from 3 fragments → 1.)
  - **Regex-readiness** signal (`High/Medium/Low`) on each cluster
    (`TemplateCluster.regexReadiness`, anchor-density heuristic), surfaced in
    console + Markdown + HTML — the "good level of confidence" half of Insight 2.
  - Wider example spread (`maxExamples` 3 → 5) for field-range evidence.
  - *Still owned by V2/V5:* coherent cross-wording **families** (Levenshtein/
    TF-IDF) and **suggested regex per category**.
- ✅ **Breadth-first `discover` command:** looks at **every sender** by default
  (vs `pull`/`analyze`'s targeted CBE default) and leads its output with
  candidate new formats — the founding "what am I missing, including banks I
  don't parse?" workflow, without changing the existing targeted defaults.
- ✅ **Logic-fidelity guard (`LogicFidelity`, `vendor/totals/fidelity.json`):**
  `diff --from=<app dir>` hashes the exact app source regions the lab mirrors
  (regex flags, `cleanSmsText`, sender normalization, the transaction heuristic)
  and warns (exit 3), naming the changed rule, when the parser **logic** drifts —
  not just the pattern data. Snapshot refreshed by `vendor_patterns` / `--refresh`.
- ✅ **Noise filter (`TransactionHeuristic`, `--no-filter`):** unattributed
  clusters are split into transaction-like *candidates* vs *noise*
  (OTPs/promos/notices); noise is hidden from the candidate-new-formats stream by
  default (`CoverageReport.candidateNewFormats` vs `noiseClusters`). Mirrors the
  app's `_looksLikeTransactionMessage`. **Scope:** candidate stream only —
  coverage still counts every message. `lib/filtering/transaction_heuristic.dart`.

---

## 9. Discovery-first roadmap themes (the founding insight)

The tool exists to find formats nobody wrote a regex for, at a scale you can't
audit by hand. Beyond V2/V3's family-merging (which makes discovery output
*rankable*), these themes deepen discovery itself:

### 9.1 Candidate-new-format → candidate-*bank* grouping  (✅ stream shipped; deepen later)
V1 surfaces unknown-sender clusters as "candidate new formats" already. Next
steps once V2 families exist: group those unknown clusters **by sender address**
into "here's a bank you don't parse, with N formats and M messages," and feed
them into the V5 regex-suggestion engine (a new bank = a new `Bank` entry + a
first regex). Don't let the unknown stream stay a flat list forever.

### 9.2 Corpus / multi-dataset aggregation  (✅ basic merge shipped; deepen later)
Discovery is only as good as the dataset's breadth — "thousands of messages"
realistically means **aggregating across devices/contributors/time**.
- ✅ **Shipped:** the `corpus` command (`lib/corpus/corpus.dart`) merges many
  datasets into one, dedups by `(address, body)`, and stamps a stable
  **`datasetId`** (`fnv1a64` over sorted keys) — coverage now reflects the union
  of what's been seen, not one phone.
- **Deepen later:** persistent corpus store (append new pulls over time, track
  growth), per-source provenance in the output, and wiring `datasetId` into the
  V4 coverage-history (§5) so trend/regression compare like-for-like.

### 9.3 Discovery metrics alongside coverage
Coverage % is a quality/drift metric. Discovery also wants: **distinct unseen
formats**, **how much unmatched volume the top-N templates cover** (a few
templates usually explain most misses), and **# candidate new banks**. The data
exists (`unknownSenderClusters`, cluster occurrences); surface these as headline
numbers, not just coverage.

### 9.4 Classical-at-scale is a deliberate choice
Large-scale discovery is exactly where someone reaches for embeddings/LLMs. The
no-ML invariant (§0) is intentional even here: deterministic, reproducible,
contributor-friendly, offline. Revisit only if classical similarity (V2/V3)
demonstrably plateaus on real corpora — and document the evidence here first.
