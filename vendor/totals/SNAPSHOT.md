# Vendored Totals parser definitions

These are **snapshots** of Totals' parser data, copied so SMS Pattern Lab is
self-contained and can run without a Totals checkout next to it.

| File | Source in Totals |
|---|---|
| `banks.json` | `app/assets/banks.json` |
| `sms_patterns.json` | `app/assets/sms_patterns.json` |

- Snapshot taken from Totals git rev: **85694be**
- Date: 2026-06-30

## Refreshing

When Totals' patterns change, re-sync from a checkout:

```bash
dart run tool/vendor_patterns.dart --from=/path/to/totals/app
```

This overwrites the files above. Review the diff before committing so you can
see exactly which patterns changed between snapshots.
