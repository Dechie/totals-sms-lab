# Founding insights

The *why* behind SMS Pattern Lab. README is the pitch; REFERENCE is the manual;
ROADMAP_NOTES is the build plan. **This file is the source of truth for the
product's reason to exist** — every feature should trace back to one of these
insights, and anything that doesn't reinforce them is probably scope creep.

There are two. They compound: the first decides *what to find*, the second
decides *what to hand the developer once found*.

---

## Insight 1 — Discovery at scale (find what was never covered)

**Statement.** The lab's primary job is to surface SMS formats the parser
**never covered** — discovered by reading *thousands* of real messages no human
can audit by hand — not merely to catch formats that *break later* when a bank
changes wording (drift).

**Why.** A parser is only written against the formats a developer happened to
notice. A single bank emits dozens of variants (payroll, POS, transfers, fees,
reversals, service charges, reversinstructions…), and nobody can eyeball
thousands of messages to find them all. The unknown-unknowns — including formats
from **banks you have no parser for at all** — are where coverage silently leaks.
Drift detection is the *trust layer* that keeps findings honest over time; it is
not the point.

**What it demands of the design.**
- Read whole datasets, at scale, from real sources — device inbox / `failed_parses`
  (`tool/ingest_db.dart`), and aggregation across devices/time (`corpus`).
- Treat **unattributed** messages (unrecognized sender) as first-class — those
  are the deepest unknowns (`CoverageReport.candidateNewFormats`).
- Default to **breadth** for discovery (`discover` looks at every sender), not a
  single targeted bank.
- Don't drown the signal: filter non-transaction noise out of the candidate
  stream (`TransactionHeuristic`).

---

## Insight 2 — Actionable patterns, not just numbers (regex-ready categories)

**Statement.** When the lab reports what the parser misses — whether failed
parses or formats with no regex at all — the deliverable must be **an explicit
presentation of the generic message patterns**, grouped into **discrete,
coherent categories**, such that *each category is something a developer can
translate into one regex with a good level of confidence*. A coverage number
(*x of y*) is a side effect, **not** the product.

**Why.** "78% covered, 240 unmatched" tells a developer nothing actionable. What
moves the work forward is: *"here is one generic shape — `Transferred <AMOUNT>
from <ACCOUNT> to <ACCOUNT> (<NAME>)… total <AMOUNT>, balance <AMOUNT>` — seen
312 times across these examples; write one regex for it."* The value is the
**category and its skeleton**, ready to become a capture-group regex. This is
the entire reason clustering exists: collapse thousands of raw messages into a
short list of distinct shapes, each a confident regex target.

**What it demands of the design.**
- **Normalization** must turn raw messages into a *generic skeleton* with
  placeholders that map cleanly onto regex capture groups — including the
  **variable free-text fields** (person names, merchant names), or those fields
  fragment one logical category into many.
- **Clustering must produce coherent categories**, not raw exact-string buckets:
  near-identical wording and semantically-equivalent phrasings belong to **one**
  category (this is the whole point of V2 Levenshtein + V3 TF-IDF/cosine and the
  `TemplateFamily` model — see ROADMAP_NOTES §2A, §3).
- Each category should carry **enough evidence for confident regex authoring**:
  the skeleton, a representative spread of real examples (not just one or two),
  the field shapes, occurrence count, and ideally a **confidence/homogeneity**
  signal ("a single regex would cover all N members").
- The natural endpoint is a **suggested regex per category** (ROADMAP_NOTES
  §6.1), validated by matching it back against the category's members.
- Patterns are the **headline**; coverage % is context. Output should lead with
  the categories to work on (as `discover` does), not bury them under a metric.

---

## Supporting principles (means, not ends)

These exist to serve the two insights, not for their own sake:

- **Trust** — every measurement is anchored to a versioned, drift-checked
  baseline (data *and* logic), so findings mean "relative to *this* parser
  build" and don't go stale (`baseline`/`diff`/`fidelity.json`).
- **Offline, zero-dependency, deterministic** — reproducible output, easy
  contribution, no production coupling.
- **Fidelity** — the lab's match/no-match verdict equals the app's, so "missing"
  means genuinely missing (REFERENCE → Fidelity).

---

## How to use this file

When adding a feature, ask: *which insight does this advance, and does it move us
toward handing developers confident, regex-ready categories from real data at
scale?* If the answer is "it just adds another number" or "it only helps the
drift case," reconsider. Update this file if the mission itself changes — not for
mere implementation detail (that's ROADMAP_NOTES).
