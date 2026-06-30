/// Decides whether an SMS *looks like a financial transaction*, used to filter
/// non-transaction noise (OTPs, promos, verification codes, system notices) out
/// of discovery.
///
/// This is a faithful mirror of Totals' `SmsService._looksLikeTransactionMessage`
/// — the same heuristic the app uses to decide whether to record a `failed_parse`.
/// Mirroring it means the lab's filtered universe matches the app's: a message
/// the app wouldn't even consider a parse candidate isn't treated as a coverage
/// gap here either.
///
/// If the app's heuristic changes, update this in lockstep (see
/// REFERENCE.md → Fidelity to the production parser).
class TransactionHeuristic {
  static const List<String> _transactionKeywords = [
    'debited', 'credited', 'deposit', 'withdraw', 'withdrawal', 'transfer',
    'transferred', 'payment', 'paid', 'purchase', 'received', 'sent', 'spent',
    'cash out', 'cashout', 'atm', 'trx', 'txn', 'transaction',
  ];

  static const List<String> _supportingKeywords = [
    'balance', 'amount', 'amt', 'available balance', 'ref', 'reference',
    'account', 'ac', 'a/c', 'card', 'merchant', 'pos', 'wallet', 'etb',
    'birr', 'br',
  ];

  static final RegExp _monetary = RegExp(
    r'(?:etb|birr|br)\s*\d|\d[\d,]*(?:\.\d{1,2})?\s*(?:etb|birr|br)',
    caseSensitive: false,
  );

  /// True when [body] reads like a transaction: a transaction keyword plus
  /// either a supporting keyword or a monetary amount.
  static bool looksLikeTransaction(String body) {
    final normalized =
        body.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return false;

    final hasTransactionKeyword = _containsAny(normalized, _transactionKeywords);
    final hasSupportingKeyword = _containsAny(normalized, _supportingKeywords);
    final hasMonetaryAmount = _monetary.hasMatch(body);

    return hasTransactionKeyword &&
        (hasSupportingKeyword || hasMonetaryAmount);
  }

  static bool _containsAny(String text, List<String> values) {
    for (final value in values) {
      if (text.contains(value)) return true;
    }
    return false;
  }
}
