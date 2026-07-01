# Enrichment fields — `actionVerb` + `shapeProfile` (plan)

> Status: **planned**. Two additive per-template annotations that make internal
> grouping cheaper/more deterministic and give devs regex-ready, privacy-safe
> structure. Neither replaces the normalized text; both sit beside it.
> See action_words.txt, FIELD_SHAPES.md, INSIGHTS.md, ROADMAP_NOTES §3/§6.1.

Each template/family carries three things:
- **normalizedText** — the skeleton (`Dear <NAME> transferred <AMOUNT> to <NAME>`)
- **actionVerb** — `null` | one word from `action_words.txt` (semantic label; a
  *tag*, never stripped — the verb stays in the text)
- **shapeProfile** — per-placeholder generalized regex (value grammar, no values)

Produced by an **annotation step after normalization** (an `Annotator`), then
consumed downstream.

## Internal workings (efficiency)
- **Semantic grouping (V3):** key families by `actionVerb` (+ direction:
  credited/received/deposited → *incoming*; debited/paid/transferred/withdrawn →
  *outgoing*). A cheap, deterministic O(n) lookup that does most of what TF-IDF
  would, so cosine becomes a fallback, not the workhorse.
- **Family labels (V4):** the verb → a human name ("Outgoing transfers") for free.
- **Noise filter:** `actionVerb != null` is a strong transactional signal — backs
  `TransactionHeuristic` (keep reconciled with the app's `_looksLikeTransactionMessage`).
- **Regex suggestion (V5):** `shapeProfile` → capture-group bodies; `actionVerb`
  → the literal anchor + CREDIT/DEBIT type. Together they nearly compose a
  candidate `SmsPattern` — the human just validates.
- **Self-improving lexicon:** a transactional-looking template with
  `actionVerb == null` is a candidate **new action word** to add to the list —
  the tool surfaces its own vocabulary gaps.

## DX — understand structure + enrich corpus
- **Reports:** show `actionVerb` + `shapeProfile` per family, so a dev grasps
  "outgoing transfer; amount is `\d{1,3}(,\d{3})*\.\d{2}`" without reading raw text.
- **Privacy-safe export unit:** `{ normalizedText, actionVerb, shapeProfile,
  count, bank, matched }` — no raw values. Reviewable via `--preview`, then sent.
- **Corpus richness:** verb + shape make contributions from many devs/banks
  **comparable and dedupable at the semantic level** — the maintainer sees the
  true distribution of formats *per action type* and exactly which verbs/shapes
  are unsupported, all without any real SMS leaving a device.
- **Interactive filter (V5 HTML):** slice gaps by `actionVerb`/direction
  ("show outgoing-debit gaps only").

## Caveats (carry these)
- `actionVerb` is a **tag, not a strip** — it must remain in the template.
- `shapeProfile` must be **aggregated/generalized** (never a per-message
  fingerprint → re-identification); pair export with sender-side `--preview`.
- **Multi-verb** message → pick a primary (first-match or direction priority);
  `null` is a *signal*, not a failure.
- Both are **evidence, not verdicts** — the dev authors and validates the regex.

## Lives in
`Annotator` (post-normalization) → consumed by `SimilarityGrouper` (grouping +
labels), reports, the export command, and the V5 suggestion engine.
