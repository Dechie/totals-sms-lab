# Algorithms (V2) — skeletal

> Starter notes for the V2 similarity engines. Deliberately thin — flesh out with
> real formulas, thresholds, and benchmarks while building V2. See ROADMAP_NOTES §3
> (plan) and INSIGHTS.md (why: discrete, regex-ready categories). All stages work
> on **normalized templates**, not raw bodies.

**Pipeline:** normalize → hash (exact) → Levenshtein (near-identical) → TF-IDF + cosine (semantic).

- **Normalization** *(V1)* — replace variable data with placeholders (`<AMOUNT>`, `<NAME>`, …); collapses thousands of messages into a few skeletons.
- **Hashing / exact clustering** *(V1)* — group identical templates via a string-keyed map. O(n), deterministic.
- **Levenshtein** *(V2)* — edit distance → similarity ratio (1 − dist/maxLen); merge ≥ threshold. Catches typos / minor wording ("Transferred" vs "Transfer of"). Two-row DP, pure Dart.
- **TF-IDF** *(V2)* — tokenize templates; term-freq × inverse-doc-freq over the corpus → a weighted vector per template.
- **Cosine similarity** *(V2)* — angle between two TF-IDF vectors (dot / (‖a‖·‖b‖)), 0..1; merge ≥ threshold. Catches synonyms Levenshtein misses ("credited" / "deposited").

**Thresholds** — Levenshtein ~0.9, cosine TBD (tuned on real corpora in V3); expose via `--similarity`. Always block by `likelyBankId` first — never merge across banks.

**Complexity** — over *k distinct templates* (small after normalization), not n messages: Levenshtein O(k²·L), TF-IDF O(k·tokens), cosine O(k²·dims).

**Why not ML (for now)** — deterministic, reproducible, zero-dependency, no labeled data or training, easy to contribute to. The goal is *discovering* gaps, not classifying; classical methods suffice. Revisit only if they plateau (evidence here first).
