import '../models/parse_result.dart';

/// Lightweight, dataset-level aggregates surfaced by the `stats` command.
class DatasetStatistics {
  final int totalMessages;
  final int matched;
  final int unmatched;
  final int unattributed;

  /// Matched-message counts per transaction type (CREDIT/DEBIT/...).
  final Map<String, int> byTransactionType;

  /// Message counts per attributed bank name.
  final Map<String, int> byBank;

  const DatasetStatistics({
    required this.totalMessages,
    required this.matched,
    required this.unmatched,
    required this.unattributed,
    required this.byTransactionType,
    required this.byBank,
  });

  double get matchRate =>
      totalMessages == 0 ? 0 : (matched / totalMessages) * 100.0;

  factory DatasetStatistics.from(List<ParseResult> results) {
    final byType = <String, int>{};
    final byBank = <String, int>{};
    var matched = 0;
    var unattributed = 0;

    for (final r in results) {
      final bankName = r.bankName ?? 'Unknown';
      byBank[bankName] = (byBank[bankName] ?? 0) + 1;
      if (r.matched) {
        matched++;
        final t = r.transactionType ?? 'UNKNOWN';
        byType[t] = (byType[t] ?? 0) + 1;
      } else if (r.isUnattributed) {
        unattributed++;
      }
    }

    return DatasetStatistics(
      totalMessages: results.length,
      matched: matched,
      unmatched: results.length - matched,
      unattributed: unattributed,
      byTransactionType: byType,
      byBank: byBank,
    );
  }
}
