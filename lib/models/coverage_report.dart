import 'template_cluster.dart';

/// Coverage figures for a single bank/parser.
class ParserCoverage {
  final int bankId;
  final String bankName;
  final int total;
  final int matched;

  /// Unmatched clusters attributed to this bank, pre-sorted by priority.
  final List<TemplateCluster> missingTemplates;

  const ParserCoverage({
    required this.bankId,
    required this.bankName,
    required this.total,
    required this.matched,
    this.missingTemplates = const [],
  });

  int get unmatched => total - matched;

  /// Coverage as a 0..100 percentage. Banks with no messages report 100
  /// (nothing to cover) so they don't pollute the "needs attention" list.
  double get coveragePercent =>
      total == 0 ? 100.0 : (matched / total) * 100.0;

  /// The single biggest missing template for this bank, if any.
  TemplateCluster? get largestMissingTemplate =>
      missingTemplates.isEmpty ? null : missingTemplates.first;
}

/// The full result of a coverage analysis across the dataset.
class CoverageReport {
  final int total;
  final int matched;
  final int unattributed;

  /// Per-bank coverage, sorted worst-coverage-first.
  final List<ParserCoverage> parsers;

  /// All unmatched clusters across every bank, sorted by priority.
  final List<TemplateCluster> unmatchedClusters;

  const CoverageReport({
    required this.total,
    required this.matched,
    required this.unattributed,
    required this.parsers,
    required this.unmatchedClusters,
  });

  int get unmatched => total - matched;

  double get overallCoveragePercent =>
      total == 0 ? 0.0 : (matched / total) * 100.0;
}
