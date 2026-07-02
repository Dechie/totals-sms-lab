# Vendored Totals parser definitions

These are **snapshots** of Totals' parser data, copied so SMS Pattern Lab is
self-contained and can run without a Totals checkout next to it.

| File | Source in Totals |
|---|---|
| `banks.json` | `app/assets/banks.json` |
| `sms_patterns.json` | `app/assets/sms_patterns.json` |
| `fidelity.json` | hash of the parsing-*logic* source regions the lab mirrors (for `diff`'s logic-drift guard) |

- Snapshot taken from Totals git rev: **85694be**
- Date: 2026-06-30
- Fidelity signature: `5e0eeeb5387a73fb` — now also covers the app's
  `extractTransactionDetails` (field extraction + accept-gate) and `_cleanNumber`
  source regions, which `FieldExtractor` mirrors to score successful parses.
  If either drifts, `diff` flags it and `lib/parser_adapter/field_extractor.dart`
  must be re-checked against `app/lib/utils/pattern_parser.dart`.

## Refreshing

When Totals' patterns change, re-sync from a checkout:

```bash
dart run tool/vendor_patterns.dart --from=/path/to/totals/app
```

This overwrites the files above. Review the diff before committing so you can
see exactly which patterns changed between snapshots.
