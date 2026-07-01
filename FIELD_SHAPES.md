# Field Shapes — plan (short)

> Status: **planned**. Emit, alongside each normalized template, a per-field
> *shape profile* (quasi-regex) so a maintainer can author capture-groups
> **without ever seeing the real value**. Privacy + regex-readiness in one move.
> See INSIGHTS.md (actionable patterns) and ROADMAP_NOTES §6.1 (regex suggestion).

## Idea
For every placeholder the normalizer inserts (`<AMOUNT>`, `<NAME>`, …), also
record what the stripped span *looked like* — as a generalized character-class +
quantifier, not the value. Ship it beside the template.

## Data shape (per template/family)
```jsonc
{ "template": "Dear <NAME> transferred <AMOUNT> to <NAME>",
  "fields": {
    "AMOUNT": { "regex": "\\d{1,3}(,\\d{3})*\\.\\d{2}", "samples": 42 },
    "NAME":   { "regex": "[A-Z][a-z]+( [A-Z][a-z]+){1,2}", "samples": 42 } } }
```

## How it's built
1. Normalizer emits each match's **span + a shape descriptor** (digit runs →
   `\d{n}`, separators, casing runs, length), not just the replacement.
2. **Aggregate across ALL occurrences** in the family → union the descriptors
   into one generalized regex (min/max counts → ranges, separators seen ∪).
3. Optionally emit a candidate capture-group; feeds the V5 suggestion engine.

## Caveats (the important part)
- **Generalize/union, never fingerprint.** One message's exact shape can
  re-identify (a unique-length ref, a 3-word name). Always aggregate and widen
  to ranges; if a field has too few samples to generalize, emit a coarse class
  (e.g. `.+?`) rather than an exact one.
- **The shape is only as right as the strip.** If normalization mis-identified
  a field (unseen format), the profile describes the *wrong* span. So this does
  **not** replace review — pair export with sender-side `--preview` (they can
  see their raw data); keep raw examples for *local* analysis only.
- **Fields vary — union, don't take the first sample.** Amounts appear with and
  without thousands separators / decimals; the profile must cover the spread.
- **Deterministic + locale-free** derivation (no `,`/`.` ambiguity by locale).
- **It's evidence, not a verdict.** The human writes and validates the regex;
  the profile just removes the guesswork about field format.

## Non-goals
Not the final regex (that's V5), not per-message data, not ML.
