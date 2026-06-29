import '../clustering/exact_clusterer.dart';
import '../coverage/coverage_analyzer.dart';
import '../models/coverage_report.dart';
import '../models/parse_result.dart';
import '../models/sms_message.dart';
import '../parser_adapter/parser_adapter.dart';
import '../similarity/similarity_grouper.dart';
import '../statistics/statistics.dart';

/// The end-to-end result of one analysis run.
class AnalysisResult {
  final List<ParseResult> parseResults;
  final CoverageReport coverage;
  final DatasetStatistics statistics;

  const AnalysisResult({
    required this.parseResults,
    required this.coverage,
    required this.statistics,
  });
}

/// Orchestrates the analysis stages described in the design:
///   2. existing parser execution (via [ParserAdapter])
///   3. normalization + 4. exact template discovery (via [ExactClusterer])
///   5. similarity grouping (via [SimilarityGrouper], identity in V1)
///   then coverage + statistics.
class AnalysisPipeline {
  final ParserAdapter adapter;
  final ExactClusterer clusterer;
  final SimilarityGrouper grouper;
  late final CoverageAnalyzer _coverage;

  AnalysisPipeline({
    required this.adapter,
    ExactClusterer? clusterer,
    SimilarityGrouper? grouper,
  })  : clusterer = clusterer ?? ExactClusterer(),
        grouper = grouper ?? IdentityGrouper() {
    _coverage = CoverageAnalyzer(adapter: adapter, clusterer: this.clusterer);
  }

  AnalysisResult run(List<SmsMessage> messages) {
    final parseResults = adapter.parseAll(messages);
    final coverage = _coverage.analyze(parseResults);
    grouper.group(coverage.unmatchedClusters);
    final stats = DatasetStatistics.from(parseResults);
    return AnalysisResult(
      parseResults: parseResults,
      coverage: coverage,
      statistics: stats,
    );
  }
}
