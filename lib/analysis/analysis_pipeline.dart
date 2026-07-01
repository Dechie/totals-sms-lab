import '../clustering/exact_clusterer.dart';
import '../coverage/coverage_analyzer.dart';
import '../models/coverage_report.dart';
import '../models/data_quality.dart';
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

  /// Name of the host parser framework (from the adapter), so reports are not
  /// coupled to a specific project name. See ROADMAP_NOTES.md (V5 plugins).
  final String parserName;

  /// What went wrong or degraded during the run (0s on a clean run). Lets the
  /// export be honest about its own completeness.
  final DataQuality quality;

  const AnalysisResult({
    required this.parseResults,
    required this.coverage,
    required this.statistics,
    required this.parserName,
    required this.quality,
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
    // The grouper is consumed inside the analyzer, which builds the family-aware
    // CoverageReport (V2 step 0). Swap in a Levenshtein/TF-IDF grouper here.
    _coverage = CoverageAnalyzer(
      adapter: adapter,
      clusterer: this.clusterer,
      grouper: this.grouper,
    );
  }

  AnalysisResult run(List<SmsMessage> messages, {DataQuality? quality}) {
    final q = quality ?? DataQuality();
    q.messagesLoaded = messages.length;

    // Every message is parsed and counted — coverage reflects the whole
    // dataset. Non-transaction *noise* is separated downstream (in the
    // CoverageReport's candidate vs noise split), not dropped here.
    //
    // Parse each message in isolation: a host-parser regex that throws on one
    // pathological body must not sink the whole run. A failed parse is counted
    // as unmatched (honest denominator) — never dropped, never fabricated as a
    // match.
    final parseResults = <ParseResult>[];
    for (final m in messages) {
      try {
        parseResults.add(adapter.parse(m));
      } catch (_) {
        q.parseErrors++;
        parseResults.add(ParseResult(message: m, matched: false));
      }
    }

    final coverage = _coverage.analyze(parseResults, quality: q);
    final stats = DatasetStatistics.from(parseResults);
    return AnalysisResult(
      parseResults: parseResults,
      coverage: coverage,
      statistics: stats,
      parserName: adapter.name,
      quality: q,
    );
  }
}
