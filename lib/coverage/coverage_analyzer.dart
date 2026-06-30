import '../models/coverage_report.dart';
import '../models/parse_result.dart';
import '../models/template_cluster.dart';
import '../parser_adapter/parser_adapter.dart';
import '../clustering/exact_clusterer.dart';
import '../filtering/transaction_heuristic.dart';

/// Computes overall and per-parser coverage, and attaches each bank's missing
/// templates so the report can point straight at the highest-impact gaps.
class CoverageAnalyzer {
  final ParserAdapter adapter;
  final ExactClusterer clusterer;

  CoverageAnalyzer({required this.adapter, ExactClusterer? clusterer})
      : clusterer = clusterer ?? ExactClusterer();

  CoverageReport analyze(List<ParseResult> results) {
    final total = results.length;
    final matched = results.where((r) => r.matched).length;
    final unattributed =
        results.where((r) => !r.matched && r.isUnattributed).length;

    // Cluster unmatched messages once; reuse for both global and per-bank.
    final clusters = clusterer.clusterUnmatched(results);

    // Per-bank tallies.
    final totalsByBank = <int, int>{};
    final matchedByBank = <int, int>{};
    final namesByBank = <int, String>{};
    for (final r in results) {
      final id = r.bankId;
      if (id == null) continue;
      totalsByBank[id] = (totalsByBank[id] ?? 0) + 1;
      if (r.matched) matchedByBank[id] = (matchedByBank[id] ?? 0) + 1;
      if (r.bankName != null) namesByBank[id] = r.bankName!;
    }

    // Bucket clusters under their likely bank.
    final clustersByBank = <int, List<TemplateCluster>>{};
    for (final c in clusters) {
      final id = c.likelyBankId;
      if (id == null) continue;
      clustersByBank.putIfAbsent(id, () => []).add(c);
    }

    final parsers = totalsByBank.keys.map((id) {
      return ParserCoverage(
        bankId: id,
        bankName: namesByBank[id] ?? adapter.bankNameFor(id),
        total: totalsByBank[id]!,
        matched: matchedByBank[id] ?? 0,
        missingTemplates: clustersByBank[id] ?? const [],
      );
    }).toList()
      ..sort((a, b) {
        // Worst coverage first, but banks with zero unmatched sink to bottom.
        final byCov = a.coveragePercent.compareTo(b.coveragePercent);
        return byCov != 0 ? byCov : b.unmatched.compareTo(a.unmatched);
      });

    // Discovery signal: unmatched clusters from senders no parser recognizes
    // (already priority-sorted, since `clusters` is). Split into transaction-
    // like *candidates* and non-transaction *noise* (OTPs/promos/notices) so
    // the candidate stream stays clean. This classification does NOT affect
    // coverage — every message is still counted above.
    final unattributedClusters =
        clusters.where((c) => c.likelyBankId == null);
    final candidateNewFormats = <TemplateCluster>[];
    final noiseClusters = <TemplateCluster>[];
    for (final c in unattributedClusters) {
      (_looksTransactional(c) ? candidateNewFormats : noiseClusters).add(c);
    }

    return CoverageReport(
      total: total,
      matched: matched,
      unattributed: unattributed,
      parsers: parsers,
      unmatchedClusters: clusters,
      candidateNewFormats: candidateNewFormats,
      noiseClusters: noiseClusters,
    );
  }

  /// Classify a cluster as transaction-like using a representative raw example
  /// (retains amounts/keywords that normalization would mask). Mirrors the
  /// app's `_looksLikeTransactionMessage` via [TransactionHeuristic].
  static bool _looksTransactional(TemplateCluster c) {
    final sample = c.examples.isNotEmpty ? c.examples.first : c.template;
    return TransactionHeuristic.looksLikeTransaction(sample);
  }
}
