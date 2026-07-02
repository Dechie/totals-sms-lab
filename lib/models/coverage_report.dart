import 'success_family.dart';
import 'template_cluster.dart';
import 'template_family.dart';

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

  /// Unmatched clusters from senders no bank parser recognizes **that look like
  /// transactions** — the deepest discovery signal: formats (and likely whole
  /// banks) you have **no parser for yet**. The noise filter (default on)
  /// excludes non-transaction unattributed messages, which land in
  /// [noiseClusters] instead.
  final List<TemplateCluster> candidateNewFormats;

  /// Unattributed clusters that do NOT look like transactions (OTPs, promos,
  /// system notices). Kept out of [candidateNewFormats] by default; shown only
  /// with `--no-filter`. Coverage still counts these messages.
  final List<TemplateCluster> noiseClusters;

  /// Attributed gaps grouped into families (the grouper's output over
  /// [attributedClusters]). V1's IdentityGrouper = one family per cluster.
  final List<TemplateFamily> attributedFamilies;

  /// Candidate-new-format clusters grouped into families.
  final List<TemplateFamily> candidateFamilies;

  /// Successfully-matched messages grouped into families, each scored by
  /// extraction health. This is the "parsed, but is it usable?" signal — a
  /// family with a low [SuccessFamily.healthScore] produces transactions that
  /// silently break the app's income/expense/balance reconciliation.
  final List<SuccessFamily> successFamilies;

  /// Messages whose regex matched AND passed the app's accept-gate (a usable
  /// transaction). Always ≤ [matched] (= regex-matched). The gap between them
  /// is the silent-drop tier surfaced in the export.
  final int appAccepted;

  const CoverageReport({
    required this.total,
    required this.matched,
    required this.unattributed,
    required this.parsers,
    required this.unmatchedClusters,
    this.candidateNewFormats = const [],
    this.noiseClusters = const [],
    this.attributedFamilies = const [],
    this.candidateFamilies = const [],
    this.successFamilies = const [],
    this.appAccepted = 0,
  });

  int get unmatched => total - matched;

  /// Alias for [matched]: messages a regex claimed (regardless of whether the
  /// extracted fields were usable). Contrast with [appAccepted].
  int get regexMatched => matched;

  double get overallCoveragePercent =>
      total == 0 ? 0.0 : (matched / total) * 100.0;

  /// Unmatched clusters that ARE attributable to a known bank — the
  /// "improve an existing parser" gaps, as opposed to candidate new formats.
  List<TemplateCluster> get attributedClusters =>
      unmatchedClusters.where((c) => c.likelyBankId != null).toList();

  /// Every unattributed cluster (candidates + noise), regardless of filtering.
  List<TemplateCluster> get unknownSenderClusters =>
      [...candidateNewFormats, ...noiseClusters];
}
