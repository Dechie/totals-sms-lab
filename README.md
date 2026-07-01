# SMS Pattern Lab

### Code coverage — but for your SMS parser's regex rules.

**SMS Pattern Lab helps maintainers discover parser gaps, measure parser
coverage, and prioritize regex improvements using real-world SMS datasets.**

> Unit tests tell you your code *works*. Coverage tools tell you which code
> *isn't exercised*. **SMS Pattern Lab tells you which of your parser's regex
> rules aren't covering real-world SMS** — and exactly which one to write next.

This matters most for the gaps **you never knew were there.** A parser is only
written against the SMS formats a developer happened to notice — but a single
bank emits dozens of variants (payroll, POS, transfers, fees, reversals,
service charges…), and **no one can eyeball thousands of real messages** to find
them all. Pattern Lab reads the entire dataset for you and surfaces the formats
your regexes never accounted for in the first place — not only the ones that
break later when a bank changes its wording. It turns "unknown unknowns" into a
ranked, countable to-do list.

And every number it reports is anchored to a **versioned baseline** of your
parser and **checked for drift**, so "94% coverage" always means *"against
parser revision X"* — a metric you can trust release over release, not a
snapshot that silently goes stale.

The tool runs entirely **offline**, has **zero third-party runtime
dependencies**, and never touches your production app.

> **Standalone.** It needs no particular folder layout and no Totals checkout to
> run — it ships with a vendored snapshot of the parser definitions. References
> to **Totals** (an Ethiopian banking SMS app) describe the *example* parser it
> targets, not a dependency.

---

## Who it's for

Maintainers and contributors of **regex-based SMS parsers** who need to keep
coverage high — both for the formats they **never accounted for** and for those
that **change as banks update their SMS** — without manually reading through
thousands of messages to find what's missing or broken.

## The workflow

```text
   ┌─────────────────────────────────────────────┐
   │                                               │
   ▼                                               │
Run Pattern Lab on real SMS                        │
   │                                               │
   ▼                                               │
See which formats your regexes miss (ranked)       │
   │                                               │
   ▼                                               │
Write the highest-impact regex                     │
   │                                               │
   ▼                                               │
Coverage goes up ───────────────────────────────► repeat
```

## Parser lifecycle — why every feature exists

Each capability maps to one step of the maintenance loop the tool is built around:

```text
Bank changes its SMS wording
   │
   ▼
Coverage drops                      ← measured by `analyze` (per bank)
   │
   ▼
Lab identifies the missing template ← clustering + prioritized report
   │
   ▼
Developer writes a regex
   │
   ▼
Coverage restored                   ← re-run `analyze`, confirm it climbs
   │
   ▼
Baseline updated                    ← `diff --refresh` re-syncs + logs history
```

The **very first run is pure discovery** — it surfaces every format your regexes
never covered, before any bank ever changes a thing. The loop above then applies
the same way whether a gap was newly introduced or simply never handled.

## Quickstart

```bash
dart pub get

# Analyze a dataset (uses the vendored parser snapshot)
dart run sms_pattern_lab analyze example/cbe_sms.json

# Discovery-first: every sender, led by formats you have no parser for yet
dart run sms_pattern_lab discover --adb

# Pull real SMS from a connected test phone and analyze in one step
dart run sms_pattern_lab pull --analyze

# Is the baseline still in sync with the live app? (data + logic; CI-gateable)
dart run sms_pattern_lab diff --from=../totals/app
```

`analyze` prints per-bank coverage and the ranked list of missing templates,
and writes a Markdown or self-contained HTML report. Full command and option
reference is in [REFERENCE.md](REFERENCE.md).

## What it does — and deliberately doesn't

**It does:** discover unseen SMS templates · measure coverage overall and **per
bank parser** · rank gaps by impact · anchor every measurement to a versioned,
drift-checked baseline · run fully offline with reproducible output.

**It does *not*:** replace regex parsing · use machine learning · modify the
app's runtime behavior · auto-rewrite developer-authored regexes. It augments
the parser workflow; it doesn't try to be magic.

## Learn more

- **[REFERENCE.md](REFERENCE.md)** — full handbook: architecture, every command
  and option, the adb bridge, reports, and the baseline & drift system.
- **[ROADMAP_NOTES.md](ROADMAP_NOTES.md)** — design seams, invariants, and the
  plan for V2/V3/V4. Read this before implementing new versions.

**Status — V1 shipped:** coverage analysis, candidate-new-format discovery
(unrecognized-sender clusters) + a breadth-first `discover` command, noise
filtering, Markdown + offline HTML reports, live `adb` pull + on-device DB
ingestion (`failed_parses` + live patterns), corpus aggregation, versioned
baseline with **data + logic** drift detection, history ledger, and CI gates
(drift exit code + `--min-coverage`). Roadmap: **V2 similarity
engines** (Levenshtein + TF-IDF + cosine, plugged in) → V3 tuning on real data +
fuzzy grouping + bank reports → V4 semantic families + trends → V5 regex
suggestions, interactive reports, and multi-project plugins.

---

## In short

Regex parsers remain the most reliable way to read structured banking SMS. The
hard part is no longer *writing* regexes — it's knowing **which formats are
still unsupported, which bank parsers are falling behind, and whether last
wee`k's "gap" was already fixed.** SMS Pattern Lab answers all three: it measures
coverage against real SMS, ranks the gaps, and keeps every number honest with a
versioned, drift-checked baseline.

Think of it as **code coverage for SMS parser rules** — turning parser
maintenance from a reactive, manual chore into a continuous, measurable
engineering 
































































































|3EEEEEEEEEEEEEEEEEEEEEEEEEEEEE2process.
EC 


ERRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR