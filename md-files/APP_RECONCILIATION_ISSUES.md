# App reconciliation issues (findings, not fixes)

This document catalogues behaviors in the **Totals app** (`totals/app/lib`, git rev
`85694be`) that cause a "successfully parsed" transaction to silently corrupt the
running totals — the reason a full history can show, e.g., ~700k income and ~600k
expense but a ~7k "current balance". These are **documented here, deliberately not
fixed**: the lab's job is to measure and point; changing production parsing/totals is
a separate, app-side decision.

Each finding names the concrete code, the corruption it produces, and the
**`successUnits` health signal** in the enrichment export that predicts it (so you can
rank which patterns to look at first). Health signals come from `ExtractionHealth`
(`lib/models/extraction_health.dart`) and the per-unit `health` rates emitted by
`EnrichmentExport`.

> Note on the headline number: income/expense and "current balance" are **not designed
> to reconcile**. Income/expense are all-time cumulative sums over a *filtered* set;
> "current balance" is a point-in-time snapshot read from the latest SMS's balance-after
> (or a stored account balance). The issues below are the ways a *matched* transaction
> makes even the individual figures wrong.

---

## 1. `type` not exactly `CREDIT`/`DEBIT` → excluded from both sums, still moves balance

- **Where:** `totals/app/lib/utils/pattern_parser.dart:34` (`extracted['type'] = pattern.type`
  verbatim) and `:89-95` (only normalized to uppercase when a named `type` group exists).
  Totals only aggregates `t.type == "CREDIT"` / `"DEBIT"` (exact) in
  `totals/app/lib/providers/transaction_provider.dart:519,525,575,580`.
- **Corruption:** a pattern whose stored `type` isn't exactly `"CREDIT"`/`"DEBIT"` (lower-case,
  a synonym, empty, or a `type` group that doesn't normalize) produces transactions counted
  in **neither** income nor expense — yet their `currentBalance` still drives the balance
  snapshot. Net silently diverges from balance.
- **Health signal:** low **`typeValidRate`** (weight 30 in `healthScore`). A success family
  with `typeValidRate < 1.0` is a direct suspect.

## 2. Self-transfer legs that escape pairing → double-counted as income AND expense

- **Where:** `totals/app/lib/services/telebirr_bank_transfer_service.dart:40-99` pairs a
  telebirr CREDIT with a bank DEBIT only if the telebirr leg has a non-empty `creditor`, the
  creditor contains a recognized bank token, both `time`s parse, `|Δtime| ≤ 10 min`, and
  amounts match within `0.01`. Matched pairs are flagged `from self`/`to self` and removed
  from the sums via `_isSelfTransfer` → `skip` (`transaction_provider.dart:309-312,573-574`).
- **Corruption:** if any condition fails, both legs stay in the sums — the same money inflates
  income by the credit and expense by the debit simultaneously. This is the prime suspect for
  the inflated gross totals. It is especially bad on **bulk import**, because the parser sets
  `time` to `DateTime.now()` when no message date is supplied
  (`pattern_parser.dart:138-142`), making the 10-minute window meaningless for historical SMS.
- **Health signal:** low **`counterpartyRate`** (weight 20). A pattern that never captures a
  creditor/receiver/sender guarantees pairing fails for all its messages → systematic
  double-counting.

## 3. Missing / synthesized reference → no dedup key → duplicate transactions on re-import

- **Where:** dedup is by `reference` uniqueness at insert
  (`totals/app/lib/repositories/transaction_repository.dart`, `saveTransaction`); the parser
  synthesizes `"${bankId}_${date}"` when `refRequired == false` and no reference was captured
  (`pattern_parser.dart:160-164`).
- **Corruption:** synthesized/absent references are weak dedup keys; re-parsing the same inbox
  (or overlapping exports) can insert duplicates, inflating income and expense.
- **Health signal:** low **`reference.realRate`** / high **`reference.synthesizedRate`**
  (weight 12).

## 4. Null balance on the latest transaction → stale/incorrect displayed balance

- **Where:** the displayed balance for a single-account bank comes from
  `latestParsedBalanceAfter` (`totals/app/lib/utils/account_balance_resolver.dart:8-71`), which
  skips transactions whose `currentBalance` is null/unparseable and falls back to
  `account.balance`.
- **Corruption:** if the most recent transaction has a null balance, the shown balance is stale
  — it reflects an older SMS, not the latest movement.
- **Health signal:** low **`balance.capturedRate`** / **`balance.parseRate`** (weight 25).

## 5. Dropped-from-sums-but-in-balance transactions (structural asymmetry)

- **Where:** `validTransactions` drops rows with `bankId == null`, no registered account, or an
  `accountNumber` that matches no registered account (except the single-account legacy fallback)
  — `totals/app/lib/providers/transaction_provider.dart:405-445`. Separately, self-transfers and
  `uncategorized`-category rows are excluded from the sums via `skip` (`:517-518,573-574`) but
  the SMS balance-after that produced the displayed balance already reflects them.
- **Corruption:** money that is in the balance snapshot but excluded from the sums (or vice
  versa) — a by-design divergence between the two figures.
- **Health signal:** low **`accountCapturedRate`** flags patterns whose rows risk being dropped;
  `appAccepted:false` units (the `appRejected` tier) are matched messages that never become
  transactions at all.

## 6. Structure: the `totalBalance` ternary hides three distinct balance strategies

- **Where:** `totals/app/lib/providers/transaction_provider.dart:592-600`.

  ```dart
  final isCashBank = bankId == CashConstants.bankId;
  final hasSingleNonCashAccount = !isCashBank && accounts.length == 1;
  final totalBalance = isCashBank
      ? accounts.fold(0.0, (sum, a) => sum + a.balance) + cashBalance
      : hasSingleNonCashAccount
          ? resolvedAccountBalances[accountBalanceResolverKey(accounts.first)]
              ?? accounts.first.balance
          : accounts.fold(0.0, (sum, a) => sum + a.balance);
  ```

- **Why it matters (not a bug, but it hides the bugs):** this one expression sources the displayed
  balance **three different ways** — (a) cash: stored balances **plus a signed `cashBalance` delta**,
  (b) single non-cash account: the **latest parsed SMS balance-after snapshot** (falling back to the
  stored balance), (c) multiple non-cash accounts: a **sum of stored balances**. Those are three
  different definitions of "balance", and the fact that only case (b) is a point-in-time snapshot
  (never `income − expense`) is the crux of findings #4 and #5 — but it is invisible inside a nested
  ternary. Anyone auditing why the balance doesn't reconcile has to mentally unwind the ternary first.

- **Suggested refactor:** extract a named function with one early-return per strategy, each labelled.
  No behavior change — purely readability + a cleaner seam for fixing #4/#5 later:

  ```dart
  double _resolveBankBalance({
    required int bankId,
    required List<Account> accounts,
    required double cashBalance,
    required Map<String, double> resolvedAccountBalances,
  }) {
    final storedSum = accounts.fold<double>(0.0, (sum, a) => sum + a.balance);

    // Cash: stored balances plus the signed delta accumulated from cash txns.
    if (bankId == CashConstants.bankId) return storedSum + cashBalance;

    // Single non-cash account: the latest parsed SMS balance-after (a snapshot),
    // falling back to the stored account balance. NOTE: this is a snapshot, not
    // income − expense — see findings #4/#5.
    if (accounts.length == 1) {
      final key = accountBalanceResolverKey(accounts.first);
      return resolvedAccountBalances[key] ?? accounts.first.balance;
    }

    // Multiple non-cash accounts: sum of stored balances.
    return storedSum;
  }
  ```

  Then `final totalBalance = _resolveBankBalance(...)`. Naming each branch makes the
  snapshot-vs-sum divergence explicit at the call site.

- **Health signal:** none directly (this is app-side structure). But every finding above is easier
  to verify once each balance strategy is named and isolated.

---

## How to use this with the export

Run `sms-pattern-lab export ... --preview` and read the **Successful parses** section (sorted
worst-health first) plus the `metadata.reconciliation` rollup:

- `typeValidShare`, `balanceCapturedShare`, `counterpartyShare` — the fraction of matched
  messages that carry each totals-critical field. Anything well under 100% is corruption
  headroom.
- `appRejected` (in `metadata.messages`) — matched-but-dropped messages: parser thinks it
  handled them; the app produces nothing.
- `lowHealthFamilies` — count of accepted families scoring `< 50`; start there.

The export tells you *which patterns/banks* to prioritize; the file:line refs above tell you
*where in the app* the fix would live if/when you decide to make it.
