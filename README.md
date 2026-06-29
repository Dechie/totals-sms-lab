# SMS Pattern Lab

### A Standalone Parser Diagnostics and Pattern Discovery Tool

## Contents

- [Introduction](#introduction)
- [Why this exists](#why-this-exists)
- [What it does (and doesn't)](#what-it-does-and-doesnt)
- [How it fits in](#how-it-fits-in)
- [Install & run](#install--run)
- [How to use](#how-to-use)
- [Getting live data from a test phone (adb)](#getting-live-data-from-a-test-phone-adb)
- [Baseline & drift monitoring](#baseline--drift-monitoring)
- [The analysis pipeline](#the-analysis-pipeline)
- [Coverage & the parser health dashboard](#coverage--the-parser-health-dashboard)
- [Project structure](#project-structure)
- [Roadmap](#roadmap)
- [Benefits](#benefits)
- [In short](#in-short)

---

## Introduction

SMS Pattern Lab is a standalone Dart CLI built to become part of the developer
workflow for SMS parsing projects such as **Totals**.

> **This is a standalone project.** It does not need Totals — or any particular
> folder layout — to be present. It ships with a vendored snapshot of Totals'
> parser definitions (see [Install & run](#install--run)), so it runs on its own
> wherever you clone it. References to Totals throughout this README describe the
> *example* parser it targets, not a required dependency on your machine.

**Its purpose is not to parse SMS messages. Its purpose is to help developers
continuously improve their parsers** — by automatically discovering new SMS
templates, measuring parser coverage, and identifying which individual bank
parsers need attention.

Rather than replacing regex-based parsing, SMS Pattern Lab makes maintaining
regex parsers significantly easier: it transforms parser maintenance from a
manual, reactive task into a **measurable, data-driven workflow**.

Crucially, every measurement is anchored to a **versioned baseline** of the
app's actual parser definitions, and the tool **detects when that baseline
drifts** from the live code. That is what makes the numbers trustworthy: when
the team ships a regex for a new format, the lab notices, the snapshot is
refreshed, and the format stops being reported as "missing" — so the tool never
keeps flagging a gap the team already closed. Coverage becomes a metric you can
track release over release, not a one-off snapshot that silently goes stale.

The tool runs entirely offline, has **zero third-party runtime dependencies**,
and stays completely independent from the production application.

---

## Why this exists

Regex remains one of the most effective techniques for parsing banking SMS,
because transaction notifications follow structured templates. But maintenance
gets harder as support grows:

- Banks periodically change SMS wording.
- New banks introduce previously unseen templates.
- Existing banks add new notification formats.
- Contributors manually inspect thousands of messages to find missing patterns.
- It's hard to measure how complete each parser actually is.
- **Coverage findings go stale.** The parser changes daily; any report not tied
  to a specific version of the code keeps flagging gaps that were already fixed
  — eroding trust in the numbers and wasting effort on non-problems.

In Totals, each financial institution has its own parser. As those parsers grow
independently, **knowing which parser needs work becomes as important as writing
the regex itself** — and knowing it *against the exact version of the parser
running today* is what keeps that answer honest.

SMS Pattern Lab answers both. It measures coverage per bank parser, and it
anchors every measurement to a **versioned, drift-checked baseline** of the
app's parser definitions — so a coverage number always means "relative to *this*
build," staleness is detected automatically (and can fail CI), and the history
of how coverage moved is recorded release over release. The result is a metric
the dev team can actually rely on, and a clear, ranked answer to "which regex
should we write next?"

---

## What it does (and doesn't)

**Objectives**

- Discover previously unseen SMS templates.
- Measure overall parser coverage **and coverage per individual bank parser**.
- Prioritize regex development by impact.
- Reduce manual inspection and speed up contributor onboarding.
- Provide measurable, reproducible parser-quality metrics.

**Non-goals** — it intentionally does *not*:

- Replace regex parsing.
- Modify application runtime behavior.
- Automatically rewrite developer-authored regexes.

It augments the existing parser development workflow; it does not replace it.

---

## How it fits in

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

---

## Install & run

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

## How to use

The fastest path is to point the lab at the phone you're testing Totals on and
let it pull, analyze, and report in one step:

```bash
sms-pattern-lab devices            # list attached phones
sms-pattern-lab pull --analyze     # pull CBE SMS from the phone + analyze in one go
sms-pattern-lab pull --out=x.json  # save a dataset for repeat runs
sms-pattern-lab analyze --adb      # fetch live + analyze in-memory (no file)
```

Already have an exported dataset? Skip the device entirely and analyze the file:

```bash
sms-pattern-lab analyze example/cbe_sms.json
sms-pattern-lab analyze example/cbe_sms.json --html   # self-contained HTML report
sms-pattern-lab templates example/cbe_sms.json --top=50
sms-pattern-lab stats example/cbe_sms.json --json
```

`analyze` prints a coverage summary and writes a Markdown report; `templates`
lists the prioritized unmatched clusters; `stats` gives the raw counts. See the
[adb section below](#getting-live-data-from-a-test-phone-adb) for live-pull
details.

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

### Commands

| Command | Description |
|---|---|
| `analyze [dataset]` | Run the full pipeline; print coverage + write a Markdown report |
| `report  [dataset]` | Generate the Markdown coverage report file |
| `stats   [dataset]` | Print dataset-level statistics (`--json` for machine output) |
| `templates [dataset]` | List prioritized unmatched template clusters (`--top=N`) |
| `pull` | Pull SMS from a connected device (adb) into a dataset |
| `devices` | List attached adb devices |
| `baseline` | Show the parser baseline reports are measured against (`--record` to log it) |
| `diff` | Check the vendored baseline against the live app (drift detection) |
| `history` | Show the recorded baseline-signature history ledger |
| `compare` | *(Roadmap V4)* historical coverage comparison / regression detection |

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
| `--banks=<path>` | vendored snapshot | Path to `banks.json` |
| `--patterns=<path>` | vendored snapshot | Path to `sms_patterns.json` |
| `--out=<path>` | report/dataset default | Output path (report file, or dataset for `pull`) |
| `--top=<n>` | `25` | Max clusters to show/emit |
| `--json` | off | Machine-readable output for `stats` / `templates` |

## Getting live data from a test phone (adb)

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

Under the hood this runs `adb shell content query --uri content://sms/inbox`
and parses the rows (the parser tolerates commas and newlines in message
bodies). Requires Android **platform-tools** (`adb`) on your PATH and USB
debugging enabled on the device.

> Privacy: pulled messages are written only to the local dataset file you
> choose and analyzed offline. Nothing leaves your machine.

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

```bash
sms-pattern-lab diff --from=../totals/app --refresh   # re-vendor + re-sync
```

Because the signature is a deterministic content hash (order-independent), two
runs with the same patterns always produce the same baseline id, and any real
regex change flips it — which is what makes "relative to baseline X" precise.

> Scope: `diff` tracks the parser **data** (patterns + banks). Changes to the
> parsing *logic* in Dart (regex flags, sender normalization, text cleaning) are
> mirrored deliberately and documented under
> [Fidelity to the production parser](#fidelity-to-the-production-parser).

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

## The analysis pipeline

1. **SMS collection** — exported / anonymized / test datasets. No production
   access required.
2. **Existing parser execution** — the `parser_adapter` runs the host parser
   over every message, tagging each as *matched / unmatched* and (when matched)
   the responsible parser and transaction type.
3. **Normalization** — variable data is replaced with placeholders
   (`<AMOUNT>`, `<DATE>`, `<TIME>`, `<ACCOUNT>`, `<CARD>`, `<PHONE>`,
   `<REFERENCE>`, `<URL>`, `<NUM>`), collapsing thousands of unique messages
   into a handful of templates.
4. **Exact template discovery** — normalized messages are grouped by exact
   template (Algorithm 1: normalization + hashing — O(n), deterministic, no
   training).
5. **Similarity analysis** *(roadmap)* — merge template *families* that differ
   only in wording, via Levenshtein distance (V2) and TF-IDF + cosine
   similarity (V3).

### Why classical algorithms?

The goal is **discovering parser gaps**, not classifying transactions. Classical
text algorithms give deterministic, reproducible output with no labeled data, no
model training, and no inference engine — which keeps community contribution
easy. ML is deliberately excluded from the initial design and reserved as an
optional future enhancement.

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

It **intentionally differs** in two ways, because the lab measures *parser
capability*, not a particular device's runtime state:

- It does **not** skip messages for banks without a registered account (the app
  returns `unregisteredBank` and stops; the lab still evaluates them).
- It counts duplicate messages — duplication is signal: a template seen 300
  times is a higher-priority gap than one seen once.

One caveat: at runtime Totals loads patterns from its local database (seeded
from the bundled asset, and potentially updated remotely). The lab measures the
**vendored snapshot** — the source-of-truth regexes you'd actually edit — so a
device running remotely-updated patterns could differ. Use
[`diff`](#baseline--drift-monitoring) to detect when the snapshot has fallen
behind the live app, and `--refresh` to re-sync.

---

## Coverage & the parser health dashboard

Rather than reporting only overall coverage, the lab evaluates **each parser
individually**, so effort can be focused where it matters. Every parser gets a
health summary with its coverage and its single largest missing template, and
each unmatched cluster is reported with occurrence count, representative
examples, likely originating bank, and a priority ranking.

### Real run — CBE (58 real messages)

```
Overall coverage: 75.9% (44/58)

Parser coverage (worst first):
  CBE                            75.9%  (44/58)

Top missing templates:
  [Low] x5  CBE
      Dear ... A debit transaction of <AMOUNT>. has occurred on your account
      <ACCOUNT>. Service charge of <AMOUNT> ... with total of <AMOUNT> .Your
      current balance is <AMOUNT>. Thanks for Banking with CBE. <URL>
```

That one cluster says: *the "A debit transaction of … has occurred" format is
unsupported and showed up 5 times — write a regex for it first.* That's the
entire point of the tool.

---

## Project structure

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
  vendor/totals/                vendored snapshot of banks + sms_patterns
  baseline_history.json         committed ledger of baseline signatures over time
  tool/
    ingest_raw.dart             raw chat-export → dataset converter
    vendor_patterns.dart        refresh the vendored snapshot from Totals
  test/                         unit + end-to-end tests
  example/                      sample + real datasets
```

---

## Roadmap

- **V1 (this release — shipped)**
  - ✅ SMS loading, normalization, exact template grouping (Algorithm 1)
  - ✅ Per-parser coverage statistics and prioritized unmatched-template reports
  - ✅ Markdown **and self-contained HTML reports** (inline SVG charts, fully offline)
  - ✅ Live device pull over **adb** (`pull` / `--adb`)
  - ✅ **Versioned baseline with drift detection** (`baseline` / `diff`)
  - ✅ **Baseline history ledger** (`history`, `baseline --record`)
- **V2** — Levenshtein similarity, fuzzy template grouping, parser health
  dashboards, bank-specific reports.
- **V3** — TF-IDF vectorization, cosine similarity, semantic template families,
  trend analysis over time.
- **V4** — regex suggestion engine, *interactive* HTML reports (filtering /
  drill-down on top of V1's static report), CI integration, parser regression
  detection, historical coverage comparison, plugin architecture for multiple
  SMS parsing projects.

---

## Benefits

**For developers** — less manual inspection, faster regex development, easier
onboarding, clear visibility into parser quality, objective prioritization.

**For maintainers** — measurable parser health, coverage tracking over time,
faster adaptation to changing bank formats, more confidence before releases.

**For the project** — independent maintenance, no runtime impact, no production
dependencies, reusable across any regex-based SMS parsing application.

---

## In short

Regex-based parsers remain the most reliable solution for structured banking
SMS. The real challenge is no longer *writing* regexes — it's discovering which
message formats are still unsupported and which bank parsers need improvement.

SMS Pattern Lab analyzes SMS datasets after the existing parser has run, groups
unmatched templates with deterministic text-analysis algorithms, measures
coverage across individual bank parsers, and generates actionable reports that
guide regex development. It runs entirely offline, introduces no production
dependencies, requires no ML models, and is reusable by any project built around
regex-based SMS parsing.

It turns parser maintenance from a reactive, manual task into a continuous,
measurable engineering process.
