# SMS Pattern Lab — Reference

The complete handbook: architecture, usage, and the baseline/drift system. For
the pitch and quickstart see [README.md](../README.md); for *why the tool exists*
see [INSIGHTS.md](INSIGHTS.md); for the plan to build V2+ see
[ROADMAP_NOTES.md](ROADMAP_NOTES.md).

> **Codebase note:** The Totals codebase used by this lab has diverged from
> `upstream/main`. Our work targets `upstream/playstore-version`, not `main`.
> We did not realise this at first — the upstream's default branch is
> `playstore-version`, not `main`, so we spent time developing against a
> branch that was ~160 commits behind. By the time we noticed, our feature
> work was done on the old base and had to be selectively merged forward.
>
> Key differences between the two branches:
> - Common ancestor is `a4df19`; `playstore-version` is ~160 commits ahead.
> - `playstore-version` has a different SMS architecture: `FallbackSmsParser`,
>   `bank_sender_matcher`, `sms_transaction_source`, and the `pattern_parser`
>   returns `Map<String, dynamic>?` (not `Transaction?` like our branch).
> - DB schema is at v27 (v28 after our migration), with extra tables for
>   profiles, shared expenses, sync, loans/debts, budgets, etc.
> - Patterns in `sms_patterns.json` now include `fieldMapping` per pattern
>   (maps regex capture groups to output fields like `amount`, `balance`,
>   `reference`, etc.) and a `hasFees` boolean to flag patterns with service
>   charges.
> - Three correctness fixes were applied during the merge: (1) CBE false
>   positive — generic "CBE credit, no ref" moved after all specific CBE
>   patterns; (2) weak dedup keys — synthesized reference now includes
>   type/amount/account in addition to bank+date; (3) stale balance —
>   `latestParsedBalanceAfter` derives balance from `amount + totalFee` when
>   `currentBalance` is null.
>
> If you are editing patterns, make sure they include the `fieldMapping`
> object expected by the playstore-version `PatternParser`; patterns from
> the old `main` branch lack this and will fail to extract fields correctly.

## Contents

- [Architecture](#architecture)
  - [How it fits in](#how-it-fits-in)
  - [The analysis pipeline](#the-analysis-pipeline)
  - [Fidelity to the production parser](#fidelity-to-the-production-parser)
  - [Project structure](#project-structure)
- [Usage](#usage)
  - [Install & run](#install--run)
  - [Commands](#commands)
  - [Options](#options)
  - [Reports: Markdown or self-contained HTML](#reports-markdown-or-self-contained-html)
  - [Getting live data from a test phone (adb)](#getting-live-data-from-a-test-phone-adb)
  - [Dataset format](#dataset-format)
- [Baseline & drift monitoring](#baseline--drift-monitoring)
- [Coverage & the parser health dashboard](#coverage--the-parser-health-dashboard)
  - [Candidate new formats — discovery-first](#candidate-new-formats--discovery-first)
  - [Noise filtering](#noise-filtering)
- [Benefits](#benefits)
- [Roadmap](#roadmap)

---

## Architecture

### How it fits in

SMS Pattern Lab is a **developer utility**, not part of the production app. It
operates *after* the parser has run — its responsibility begins where parsing
ends.

```text
SMS Dataset
      │
      ▼
Totals Parser Framework         ← via the parser_adapter layer
      │
      ├──────────────┐
      ▼              ▼
  Matched        Unmatched
      │              │
      └──────┬───────┘
             ▼
      SMS Pattern Lab
             │
   Normalization → Template Discovery → Coverage Analysis
             │
             ▼
      Developer Reports  →  Regex Improvements
```

No runtime dependencies are introduced into the Flutter application. The
`parser_adapter` layer is the only project-specific piece; point it at a
different regex-based parser and the rest of the lab is reusable as-is.

### The analysis pipeline

1. **SMS collection** — exported / anonymized / test datasets. No production
   access required.
2. **Existing parser execution** — the `parser_adapter` runs the host parser
   over every message, tagging each as *matched / unmatched* and (when matched)
   the responsible parser and transaction type.
3. **Normalization** — variable data is replaced with placeholders
   (`<AMOUNT>`, `<DATE>`, `<TIME>`, `<ACCOUNT>`, `<CARD>`, `<PHONE>`,
   `<REFERENCE>`, `<URL>`, `<NUM>`, plus free-text **`<NAME>`** and
   **`<MERCHANT>`**), collapsing thousands of unique messages into a handful of
   templates. Abstracting the free-text fields matters twice over: it stops one
   logical category fragmenting by recipient/merchant name, and it leaves a
   skeleton whose placeholders map cleanly onto regex capture groups.
4. **Exact template discovery** — normalized messages are grouped by exact
   template (Algorithm 1: normalization + hashing — O(n), deterministic, no
   training). Unmatched clusters split into two discovery streams: those
   **attributable to a known bank** (improve that parser) and those from a
   **sender no parser recognizes** — *candidate new formats*, surfaced
   separately because they're the deepest "unknown unknowns" (see below).
5. **Similarity analysis** *(roadmap)* — merge template *families* that differ
   only in wording, via Levenshtein distance (V2) and TF-IDF + cosine
   similarity (V3).

**Why classical algorithms?** The goal is **discovering parser gaps**, not
classifying transactions. Classical text algorithms give deterministic,
reproducible output with no labeled data, no model training, and no inference
engine — which keeps community contribution easy. ML is deliberately excluded
from the initial design and reserved as an optional future enhancement.

### Fidelity to the production parser

Stage 2's match/no-match verdict is meant to equal what Totals decides at
runtime, so coverage numbers are trustworthy. The adapter therefore replicates
the production parser exactly where it counts:

- **Regex flags** — `caseSensitive: false, multiLine: true, dotAll: true`,
  matching `PatternParser` (several patterns rely on `^`/`$`, so `multiLine`
  is not optional).
- **A message is "matched"** when any of its bank's patterns matches — the same
  definition as the app, which scopes patterns by `bankId` and treats a regex
  hit as a parse.
- **Sender → bank** uses Totals' `_normalizeSenderToken` (lowercase, strip
  non-alphanumerics, substring match), and the body is trimmed before matching
  (Totals' `cleanSmsText`).

It **intentionally differs** in two ways — both because the lab's job is
*discovery*, measuring parser *capability* against real data rather than
mirroring one device's runtime state:

- It does **not** skip messages for banks without a registered account (the app
  returns `unregisteredBank` and stops). The lab still evaluates them — a format
  from a bank you don't yet support is exactly the kind of gap you want to find.
- It counts duplicate messages — duplication is signal: a template seen 300
  times is a higher-priority gap than one seen once.

One caveat: at runtime Totals loads patterns from its local database (seeded
from the bundled asset, and potentially updated remotely). The lab measures the
**vendored snapshot** — the source-of-truth regexes you'd actually edit — so a
device running remotely-updated patterns could differ. Use
[`diff`](#baseline--drift-monitoring) to detect when the snapshot has fallen
behind the live app, and `--refresh` to re-sync. To measure against the patterns
*actually running on a device*, pull the live `sms_patterns` table with
[`tool/ingest_db.dart`](#pull-from-the-apps-database-failed-parses--live-patterns)
and pass it via `--against` / `--patterns`.

### Project structure

```text
sms_pattern_lab/
  bin/sms_pattern_lab.dart      CLI entry point
  lib/
    analysis/                   pipeline orchestration
    baseline/                   parser baseline fingerprint + drift diff
    clustering/                 exact template discovery (Algorithm 1)
    coverage/                   overall + per-parser coverage
    normalizer/                 variable → placeholder replacement
    parser_adapter/             generic adapter + Totals implementation
    reports/                    Markdown + self-contained HTML reports, SVG charts
    similarity/                 template-family grouping (V2/V3 roadmap)
    sources/                    runtime data sources (adb device pull)
    statistics/                 dataset-level aggregates
    models/                     data models
    utils/                      dataset loading
  vendor/totals/                vendored snapshot of banks + sms_patterns + fidelity.json
  baseline_history.json         committed ledger of baseline signatures over time
  ROADMAP_NOTES.md              implementation guide for V2/V3/V4 (read before building)
  tool/
    ingest_raw.dart             raw chat-export → dataset converter
    vendor_patterns.dart        refresh the vendored snapshot from Totals
  test/                         unit + end-to-end tests
  example/                      sample + real datasets
```

---

## Usage

### Install & run

Requires the Dart SDK (>= 3.2.6). From this directory:

```bash
dart pub get

# Analyze a dataset (uses the vendored Totals parser snapshot — see below)
dart run sms_pattern_lab analyze example/cbe_sms.json

# Or, after `dart pub global activate --source path .`:
sms-pattern-lab analyze example/cbe_sms.json
```

The tool is **self-contained**: a snapshot of Totals' `banks.json` and
`sms_patterns.json` is vendored under [`vendor/totals/`](vendor/totals/), so it
works out of the box — there is no assumption about where (or whether) a Totals
checkout exists on your machine.

If you *do* maintain the Totals patterns and want to refresh the snapshot, point
the helper at wherever your Totals app directory lives (the one containing
`assets/banks.json`):

```bash
dart run tool/vendor_patterns.dart --from=/absolute/or/relative/path/to/totals/app
```

You can also target any other regex-based parser at analysis time with explicit
`--banks=<path> --patterns=<path>` flags — nothing is hard-wired to a fixed
location.

### Commands

| Command | Description |
|---|---|
| `analyze [dataset]` | Run the full pipeline; print coverage + write a Markdown report |
| `report  [dataset]` | Generate the Markdown coverage report file |
| `stats   [dataset]` | Print dataset-level statistics (`--json` for machine output) |
| `templates [dataset]` | List prioritized unmatched template clusters (`--top=N`) |
| `discover [dataset]` | Breadth-first discovery (all senders), led by candidate new formats; `--adb` pulls the whole inbox |
| `pull` | Pull SMS from a connected device (adb) into a dataset |
| `devices` | List attached adb devices |
| `baseline` | Show the parser baseline reports are measured against (`--record` to log it) |
| `diff` | Check the vendored baseline against the live app (drift detection) |
| `history` | Show the recorded baseline-signature history ledger |
| `corpus <a> <b> …` | Merge + dedup several datasets into one, with a stable dataset id |
| `compare` | *(Roadmap V5)* historical coverage comparison / regression detection |

For `analyze`/`report`/`stats`/`templates`, pass a dataset file **or** use
`--adb` to pull live from a connected device instead.

### Options

| Option | Default | Meaning |
|---|---|---|
| `--adb` | off | Pull SMS live from a connected device instead of reading a file |
| `--all` | off | With `--adb`/`pull`: keep every sender (default: CBE only) |
| `--device=<serial>` | first device | Target a specific adb device (see `devices`) |
| `--adb-path=<path>` | `adb` | Path to the adb executable |
| `--analyze` | off | With `pull`: analyze immediately after pulling |
| `--html` | off | Write a self-contained HTML report (charts, fully offline) |
| `--from=<path>` | `../totals/app` | `diff`: the live Totals app directory to compare against |
| `--against=<path>` | — | `diff`: a specific `sms_patterns.json` to compare against |
| `--refresh` | off | `diff`: re-vendor the snapshot from the live source after diffing |
| `--record` | off | `baseline`: append the current baseline to the history ledger |
| `--note=<text>` | — | `baseline`/`diff`: note stored with the recorded entry |
| `--history=<path>` | `baseline_history.json` | History ledger file location |
| `--no-filter` | off | Show non-transaction "noise" clusters among candidate new formats too; default hides them (coverage is unaffected either way) — see [Noise filtering](#noise-filtering) |
| `--min-coverage=<n>` | — | `analyze`: exit non-zero (4) if coverage < n% — a CI gate |
| `--banks=<path>` | vendored snapshot | Path to `banks.json` |
| `--patterns=<path>` | vendored snapshot | Path to `sms_patterns.json` |
| `--out=<path>` | report/dataset default | Output path (report file, or dataset for `pull`) |
| `--top=<n>` | `25` | Max clusters to show/emit |
| `--json` | off | Machine-readable output for `stats` / `templates` |

> Exit codes: `0` ok · `1` error · `3` baseline drift (`diff`) · `4` below
> `--min-coverage` (`analyze`). The last two make the tool a CI gate.

### Reports: Markdown or self-contained HTML

By default `analyze`/`report` write a **Markdown** report. Add `--html` (or give
an `--out` path ending in `.html`) to write a **self-contained HTML report**
instead — a single file with embedded CSS and inline SVG charts (a coverage
donut and a per-parser bar chart):

```bash
sms-pattern-lab analyze example/cbe_sms.json --html
#   → build/coverage.report.html   (open in any browser)

sms-pattern-lab analyze --adb --html --out=reports/today.html
```

The HTML report is **fully offline**: no JavaScript, no CDN, no fetched assets
or fonts — it renders identically with no network. That keeps it shareable and
true to the tool's zero-dependency, offline design.

### Getting live data from a test phone (adb)

The point of the tool is to diagnose the parser against **real** messages. The
runtime bridge is `adb`: while Totals runs on a USB-debugging device, the lab
reads the same system SMS inbox the app reads — no change to Totals required.

```bash
# 1. Confirm the phone is connected
sms-pattern-lab devices

# 2. Pull CBE messages straight into a coverage run
sms-pattern-lab pull --analyze

# Or save a dataset to disk for repeated runs / sharing
sms-pattern-lab pull --out=example/device_cbe.json
sms-pattern-lab analyze example/device_cbe.json

# Pull everything (all senders), not just CBE
sms-pattern-lab pull --all --out=example/device_all.json
```

> **For discovery, prefer breadth.** `pull`/`analyze` default to CBE for
> *targeted* runs against one bank (`--all` widens them). To find formats — and
> whole banks — you have **no parser for yet**, use the **`discover`** command:
> it looks at **every sender by default** and leads with
> [Candidate new formats](#candidate-new-formats--discovery-first):
>
> ```bash
> sms-pattern-lab discover --adb              # pull whole inbox, discovery-first
> sms-pattern-lab discover build/corpus.json  # or a merged corpus / dump
> ```

Under the hood this runs `adb shell content query --uri content://sms/inbox`
and parses the rows (the parser tolerates commas and newlines in message
bodies). Requires Android **platform-tools** (`adb`) on your PATH and USB
debugging enabled on the device.

> Privacy: pulled messages are written only to the local dataset file you
> choose and analyzed offline. Nothing leaves your machine.

### Pull from the app's database (failed parses + live patterns)

The richest source needs **no change to the app**. On a *debuggable* build
(debug / `flutter run`), `adb run-as` can read Totals' private SQLite db, which
holds two things the lab wants:

- **`failed_parses`** — every SMS the app saw, judged transaction-like (its
  `_looksLikeTransactionMessage` filter), and failed to parse. This is the app's
  **curated, pre-filtered discovery signal** — richer and less noisy than
  re-deriving from the raw inbox.
- **`sms_patterns`** — the patterns *actually running* on the device (the app
  loads patterns from this table, not the bundled asset), so you can analyze and
  `diff` against true runtime fidelity.

`tool/ingest_db.dart` pulls the db (via `adb run-as`, binary-clean) and reads it
with the `sqlite3` CLI — both external tools, not Dart dependencies, so the lab
stays zero-dep and offline:

```bash
# confirm the installed id (a build type may add the ".test" suffix)
adb shell pm list packages | grep offline_gateway

# pull failed_parses → a dataset, and the live patterns → a baseline file
dart run tool/ingest_db.dart \
  --package=com.example.offline_gateway \
  --out=example/device_failed.json \
  --patterns-out=build/live_patterns.json

# analyze the curated failures, and check the live patterns against the snapshot
dart run sms_pattern_lab analyze example/device_failed.json
dart run sms_pattern_lab diff --against=build/live_patterns.json
```

Already have a `.db` (e.g. pulled by hand)? Pass it as a path to skip adb:
`dart run tool/ingest_db.dart path/to/totals.db --out=...`.

### Aggregating a corpus (discovery at scale)

Discovery is only as good as the dataset's breadth — "thousands of messages"
realistically means combining pulls/exports from **many devices, contributors,
and points in time**. `corpus` merges several datasets into one, deduplicating by
`(address, body)` (the same key the app uses), and stamps a **stable dataset id**
(an order-independent content hash) so you can compare like-for-like later:

```bash
sms-pattern-lab corpus \
  exports/device_a.json exports/device_b.json example/device_failed.json \
  --out=build/corpus.json
#   Total in  : 128
#   Unique    : 68 (60 duplicate(s) removed)
#   Dataset id: 0e1ba10e3f7adde4

sms-pattern-lab analyze build/corpus.json
# or analyze straight away:
sms-pattern-lab corpus a.json b.json --analyze
```

The dataset id is the basis for the V4/V5 trend & regression work (compare runs
only when the data is the same).

> Requires a **debuggable** build (debug builds are; a release/Play build blocks
> `run-as`). SQLite is in WAL mode, so the tool pulls the `-wal`/`-shm` sidecars
> alongside for a consistent snapshot.

### Dataset format

A JSON array of objects (a top-level array, an object with a `messages` array,
or NDJSON). Only `body` is required; `address` lets the adapter scope patterns
to a bank:

```json
[
  { "address": "CBE", "body": "Dear Mr Dechasa your Account 1****6843 has been credited with ETB 201.15. ..." }
]
```

Raw, chat-exported blobs (many messages lumped together, with timestamp markers)
can be converted with the bundled ingest tool:

```bash
dart run tool/ingest_raw.dart raw.txt --address=CBE --out=example/cbe_sms.json
```

---

## Baseline & drift monitoring

Coverage and "missing pattern" findings are only meaningful **relative to a
known set of parser definitions**. That reference is the **baseline**: the
vendored snapshot of Totals' patterns the lab measured against. Every coverage
run stamps the baseline it used:

```
Parser: Totals Parser Framework (10 banks, 95 patterns)
Baseline: 95cc048f21a46e2f (vendored snapshot · Totals rev 85694be · 2026-06-30)
```

Inspect the frame of reference directly:

```bash
sms-pattern-lab baseline
#   Signature  : 95cc048f21a46e2f
#   Patterns   : 95 (0 invalid)
#   Banks      : 10
#   Patterns per bank: CBE 14, Telebirr 27, ...
```

### The drift problem

The app's regexes change over time. If the lab keeps using an old snapshot, it
will keep reporting "you miss pattern X" even after the app shipped a regex for
X yesterday. `diff` catches exactly that — it compares the vendored baseline
against the live app and reports what changed:

```bash
sms-pattern-lab diff --from=../totals/app
```

```
+ 1 new pattern(s) in the app (coverage reports built on the old baseline
  would still flag these formats as missing):
   [CBE] CBE debit transaction occurred
       A debit transaction of ETB (?<amount>[\d,.]+) has occurred
⚠ Baseline is STALE (1 change). Refresh with:
    sms-pattern-lab diff --from=../totals/app --refresh
```

`diff` **exits non-zero (3) on drift**, so it works as a git pre-commit hook or
CI gate: fail the build whenever the app's patterns move ahead of the lab's
snapshot. Refresh, and the next coverage run reflects the new regexes — the
formats the app now handles drop off the "missing" list automatically.

Pair it with a coverage floor — `analyze --min-coverage=90` **exits 4** when
coverage drops below the threshold:

```bash
sms-pattern-lab diff --from=../totals/app          # exit 3 if baseline is stale
sms-pattern-lab analyze data.json --min-coverage=90 # exit 4 if coverage < 90%
```

```bash
sms-pattern-lab diff --from=../totals/app --refresh   # re-vendor + re-sync
```

Because the signature is a deterministic content hash (order-independent), two
runs with the same patterns always produce the same baseline id, and any real
regex change flips it — which is what makes "relative to baseline X" precise.

### Logic-drift guard

`diff` also checks parser **logic**, not just pattern data. The lab mirrors a
handful of app rules by hand (regex flags, `cleanSmsText`, sender normalization,
the transaction heuristic — see [Fidelity](#fidelity-to-the-production-parser)).
A snapshot of those exact source regions is hashed into
`vendor/totals/fidelity.json`. When `diff --from=<app dir>` runs, it re-hashes
the live source and **warns (exit 3) if the logic drifted**, naming which rule
changed:

```
⚠ Parser LOGIC drifted — vendored 5b5d5252f59126a3 vs live ed740b6546e5bb6e
  changed: cleanSmsText
```

This catches the dangerous case the data `diff` can't: a Dart-side change that
silently makes the lab's verdict diverge from the app's. `--refresh` (and
`tool/vendor_patterns.dart`) update the logic snapshot alongside the patterns.
The check needs app *source* (so it runs with `--from=<app dir>`, not
`--against=<patterns.json>`).

### History ledger

Baseline signatures are logged over time to **`baseline_history.json`** — a
single, human-readable JSON file committed to the repo that acts as a tiny
database of how the parser baseline evolved. It is **append-only and
deduplicated**: a new entry is added only when the signature actually changes,
so the file records *transitions*, not every run.

```bash
sms-pattern-lab baseline --record --note="added Telebirr top-up patterns"
sms-pattern-lab history
```

```
Baseline history — baseline_history.json (2 record(s))
========================================================================
#  Date                Signature          Patterns  Δ     Note
1  2026-06-30          95cc048f21a46e2f   95        —     initial vendored snapshot
2  2026-07-04          9f41b9d565279b12   96        +1    added CBE debit-occurred
current: 9f41b9d565279b12
```

`diff --refresh` records the new baseline automatically, so every snapshot
refresh leaves a dated, signed entry in the ledger. Each record stores the
signature, timestamp, pattern/bank counts, per-bank breakdown, the Totals
revision (when known), and your note — enough to answer "when did coverage
shift, and against which version of the parser?" and the foundation for the V4
historical-coverage `compare`.

---

## Coverage & the parser health dashboard

Rather than reporting only overall coverage, the lab evaluates **each parser
individually**, so effort can be focused where it matters. Every parser gets a
health summary with its coverage and its single largest missing template, and
each unmatched cluster is reported with occurrence count, representative
examples, likely originating bank, a priority ranking, and a **regex-readiness**
signal.

**Regex-readiness** (`High` / `Medium` / `Low`) is a heuristic on the template's
*anchor density* — how confidently you could turn that skeleton into one regex.
A shape with a strong field (`<AMOUNT>`/`<ACCOUNT>`/`<REFERENCE>`) and plenty of
literal anchor words ("Account … credited with … balance …") scores High; a
shape that's mostly placeholders (`<NUM> <NUM> <AMOUNT>`) scores Low because
there's little to anchor on. It answers the "good level of success confidence"
half of the actionable-patterns insight: which categories are clean, safe wins.

### Candidate new formats — discovery-first

Unmatched clusters are split into two streams, because they call for different
work:

- **Unmatched, known bank** → *improve an existing parser*. Reported under
  "Unmatched Pattern Reports (known banks)", attributed to the bank.
- **Unmatched, unrecognized sender** → *a format (or whole bank) you have no
  parser for yet*. Reported separately under **"Candidate New Formats"** and
  counted in every report's summary.

The second stream is the founding use case: formats nobody wrote a regex for,
discovered by reading the whole dataset instead of eyeballing thousands of
messages. They're surfaced as their own section (CLI, Markdown, and HTML) rather
than buried as "Unknown" rows, and `--all` (see the adb section) is what lets
them appear at all. Programmatically they're `CoverageReport.unknownSenderClusters`
(vs `attributedClusters`).

### Noise filtering

Not every unmatched SMS is a parser gap — OTPs, promos, and system notices are
just noise, and they pollute the candidate-new-formats stream (where non-bank
senders land). By **default the lab classifies each unattributed cluster** with a
transaction heuristic (a transaction keyword plus a supporting keyword or a
monetary amount): transaction-like clusters become **candidate new formats**,
the rest become **noise** and are hidden (with a count) from the candidates.

Scope matters: the filter affects **only the candidate-new-formats stream**, not
coverage. **Every message is still counted** — a non-transaction SMS from a
*known* bank stays a normal (low-priority) gap, and overall coverage is unchanged.

The heuristic **mirrors the app's own `_looksLikeTransactionMessage`**
([Fidelity](#fidelity-to-the-production-parser)), so "candidate" means what Totals
would consider a transaction — and it's why a pulled `failed_parses` dataset is
already clean (the app applied the same filter at capture time).

Use `--no-filter` for **deep discovery**: it shows noise clusters among the
candidates too, surfacing even transaction formats the heuristic might miss (at
the cost of OTP/promo noise).

### Real run — CBE (58 real messages)

```
Overall coverage: 75.9% (44/58)

Parser coverage (worst first):
  CBE                            75.9%  (44/58)

Top missing templates (known banks):
  [Low] x5  CBE
      Dear ... A debit transaction of <AMOUNT>. has occurred on your account
      <ACCOUNT>. Service charge of <AMOUNT> ... with total of <AMOUNT> .Your
      current balance is <AMOUNT>. Thanks for Banking with CBE. <URL>
```

That one cluster says: *the "A debit transaction of … has occurred" format is
unsupported and showed up 5 times — write a regex for it first.* That's the
entire point of the tool.

---

## Benefits

**For developers** — less manual inspection, faster regex development, easier
onboarding, clear visibility into parser quality, objective prioritization.

**For maintainers** — measurable parser health, coverage tracking over time,
faster adaptation to changing bank formats, more confidence before releases.

**For the project** — independent maintenance, no runtime impact, no production
dependencies, reusable across any regex-based SMS parsing application.

---

## Roadmap

> **Implementing V2+? Read [`ROADMAP_NOTES.md`](ROADMAP_NOTES.md) first.** It
> records the V1 design seams, invariants, and the exact refactors each version
> needs (e.g. the `TemplateFamily` and coverage-history prerequisites), so future
> work lands with the architecture instead of fighting it.

- **V1 (this release — shipped)**
  - ✅ SMS loading, normalization, exact template grouping (Algorithm 1)
  - ✅ Per-parser coverage statistics and prioritized unmatched-template reports
  - ✅ **Candidate-new-format discovery** — unmatched clusters from unrecognized
    senders surfaced as a first-class stream (formats/banks with no parser yet)
  - ✅ Markdown **and self-contained HTML reports** (inline SVG charts, fully offline)
  - ✅ Live device pull over **adb** (`pull` / `--adb`)
  - ✅ **Versioned baseline with drift detection** (`baseline` / `diff`)
  - ✅ **Baseline history ledger** (`history`, `baseline --record`)
  - ✅ CI gates: drift exit code + `--min-coverage`
- **V2 — Similarity engines.** Implement the three classical algorithms and
  plug them into the pipeline behind the `SimilarityGrouper` seam (with the
  `TemplateFamily` model): **Levenshtein distance**, **TF-IDF vectorization**,
  and **cosine similarity**. Goal: all three working and integrated end-to-end,
  grouping near-identical *and* semantically-related templates into families.
  Correctness and integration first — tuning comes next.
- **V3 — Tuning & grouping UX.** Improve the algorithms against real test
  datasets (thresholds, tokenization); fuzzy template grouping; parser health
  dashboards; bank-specific reports.
- **V4 — Semantic families & trends.** Polished semantic template families (on
  the V2 TF-IDF/cosine engine); trend analysis over time (coverage history).
- **V5 — Productionization.** Regex suggestion engine, *interactive* HTML
  reports (filtering / drill-down on top of V1's static report), CI integration,
  parser regression detection, historical coverage comparison, and a plugin
  architecture for multiple SMS parsing projects.
