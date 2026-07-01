# Algorithms (V2) — skeletal

> Starter notes for V2's grouping. Thin on purpose — flesh out during V2. See
> ROADMAP_NOTES §3 (plan), ENRICHMENT_FIELDS.md (`actionVerb`/`shapeProfile`),
> action_words.txt (lexicon), INSIGHTS.md (why). All stages work on **normalized
> templates**, not raw bodies, and group **within a bank** (never across).

**Pipeline:** normalize → hash (exact) → **action-verb bucket** → Levenshtein
(typos) → TF-IDF + cosine (fallback).

- **Normalization** *(V1)* — values → placeholders (`<AMOUNT>`, `<NAME>`, …).
- **Hashing / exact clustering** *(V1)* — identical templates grouped by string key. O(n).
- **Action-verb grouping** *(V2 — PRIMARY)* — an `Annotator` tags each template
  with an `actionVerb` from action_words.txt (`null` if none); bucket by verb +
  direction (incoming/outgoing). Deterministic, O(n) lookup, zero training — does
  most of the semantic work cheaply and labels the family for free. `null` on a
  transactional-looking template = candidate new action word.
- **Levenshtein** *(V2)* — merge near-identical wording *within a verb bucket*
  ("Transferred" vs "Transfer of"); edit-distance ratio ≥ threshold. Two-row DP.
- **TF-IDF + cosine** *(V2 — FALLBACK)* — only for synonyms the lexicon +
  Levenshtein miss; weighted token vectors, cosine ≥ threshold. Weak on tiny
  corpora, so intentionally last, not the workhorse.

**Enrichment** — beside the template carry `actionVerb` (semantic label, a tag —
never stripped) and `shapeProfile` (per-field quasi-regex, privacy-safe). Feed
grouping, family labels, export, and the V5 regex suggester.

**Thresholds** — Levenshtein ~0.9, cosine TBD (tune in V3); expose `--similarity`. Block by bank.
**Complexity** — over *k distinct templates* (small): verb bucket O(k); Levenshtein O(k²·L); TF-IDF O(k²·dims).
**Why not ML (for now)** — deterministic, reproducible, zero-dep, no training/labels; classical + a curated lexicon suffice. Revisit only if they plateau (evidence here first).
