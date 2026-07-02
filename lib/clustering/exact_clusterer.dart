import '../models/data_quality.dart';
import '../models/extraction_health.dart';
import '../models/parse_result.dart';
import '../models/template_cluster.dart';
import '../normalizer/normalizer.dart';

/// Stage 4 — Exact Template Discovery.
///
/// Groups unmatched messages by their *normalized* template. This is the O(n)
/// hashing backbone of the discovery pipeline (Algorithm 1): deterministic,
/// fast, zero training. Similarity merging (V2/V3) layers on top of these
/// exact clusters.
class ExactClusterer {
  final Normalizer _normalizer;
  final int maxExamples;

  // Keep a few real examples per category so a developer can see the *range*
  // of values a field takes when authoring the regex (character classes,
  // optional segments) — not just one specimen.
  ExactClusterer({Normalizer? normalizer, this.maxExamples = 5})
      : _normalizer = normalizer ?? Normalizer();

  /// Cluster the unmatched subset of [results] — the parser GAPS.
  List<TemplateCluster> clusterUnmatched(Iterable<ParseResult> results,
          {DataQuality? quality}) =>
      _cluster(results, (r) => !r.matched, quality: quality);

  /// Cluster the matched subset of [results] — the successful parses. Each
  /// cluster carries an [ExtractionHealth] folded from its members' extraction
  /// outcomes, so the export can score how usable the produced transactions are.
  List<TemplateCluster> clusterMatched(Iterable<ParseResult> results,
          {DataQuality? quality}) =>
      _cluster(results, (r) => r.matched, quality: quality);

  /// Cluster the [keep]-selected subset of [results] by normalized template.
  ///
  /// Resilient: a message the normalizer can't handle is skipped (and tallied
  /// in [quality]) rather than crashing the run or fabricating a template — we
  /// never invent shape data. Degraded (partially-anonymized) normalizations
  /// still cluster but mark the cluster so export can redact it.
  List<TemplateCluster> _cluster(
      Iterable<ParseResult> results, bool Function(ParseResult) keep,
      {DataQuality? quality}) {
    final selected = results.where(keep);

    final byTemplate = <String, _Bucket>{};
    for (final r in selected) {
      NormalizationResult norm;
      try {
        norm = _normalizer.normalizeWithSpans(r.message.body);
      } catch (_) {
        // Normalizer is designed not to throw; this is a last-resort backstop.
        quality?.clusteringSkipped++;
        continue;
      }
      if (norm.degraded) quality?.normalizationDegraded++;
      if (norm.truncated) quality?.normalizationTruncated++;
      final bucket =
          byTemplate.putIfAbsent(norm.template, () => _Bucket(norm.template));
      bucket.add(r, norm.spans, maxExamples, degraded: norm.degraded);
    }

    final clusters = byTemplate.values
        .map((b) => b.toCluster())
        .toList()
      ..sort((a, b) {
        final byPriority = b.priorityRank.compareTo(a.priorityRank);
        return byPriority != 0
            ? byPriority
            : b.occurrences.compareTo(a.occurrences);
      });
    return clusters;
  }
}

class _Bucket {
  final String template;
  int count = 0;
  final List<String> examples = [];
  final Map<int, int> bankVotes = {}; // bankId -> count
  final Map<int, String> bankNames = {};

  // Raw stripped spans per field, capped so a huge cluster can't grow unbounded
  // (a few hundred samples is far more than enough to generalize a shape).
  static const _maxSpansPerField = 500;
  final Map<String, List<String>> fieldSpans = {};
  bool degraded = false;

  // Extraction-health tallies — populated only for matched results (whose
  // ParseResult carries an `extraction`). Counts only; never raw values.
  int hMembers = 0,
      hAccepted = 0,
      hTypeValid = 0,
      hAmount = 0,
      hBalExpected = 0,
      hBalCaptured = 0,
      hBalParsed = 0,
      hCounterparty = 0,
      hRefReal = 0,
      hRefSynth = 0,
      hAcctExpected = 0,
      hAcctCaptured = 0,
      hFeesExpected = 0,
      hFeesCaptured = 0;
  final Map<String, int> hPatternDescs = {};

  _Bucket(this.template);

  void add(ParseResult r, Map<String, List<String>> spans, int maxExamples,
      {bool degraded = false}) {
    count++;
    if (degraded) this.degraded = true;
    if (examples.length < maxExamples) {
      examples.add(r.message.body.trim());
    }
    spans.forEach((field, values) {
      final acc = fieldSpans.putIfAbsent(field, () => <String>[]);
      for (final v in values) {
        if (acc.length >= _maxSpansPerField) break;
        acc.add(v);
      }
    });
    final id = r.bankId;
    if (id != null) {
      bankVotes[id] = (bankVotes[id] ?? 0) + 1;
      if (r.bankName != null) bankNames[id] = r.bankName!;
    }

    final ex = r.extraction;
    if (ex != null) {
      hMembers++;
      if (ex.accepted) hAccepted++;
      if (ex.typeValid) hTypeValid++;
      if (ex.amountParsed) hAmount++;
      if (ex.balanceExpected) hBalExpected++;
      if (ex.balanceCaptured) hBalCaptured++;
      if (ex.balanceParsed) hBalParsed++;
      if (ex.counterpartyCaptured) hCounterparty++;
      if (ex.referenceReal) hRefReal++;
      if (ex.referenceSynthesized) hRefSynth++;
      if (ex.accountExpected) hAcctExpected++;
      if (ex.accountCaptured) hAcctCaptured++;
      if (ex.feesExpected) hFeesExpected++;
      if (ex.feesCaptured) hFeesCaptured++;
      final d = r.matchedPatternDescription;
      if (d != null && d.isNotEmpty) hPatternDescs[d] = (hPatternDescs[d] ?? 0) + 1;
    }
  }

  TemplateCluster toCluster() {
    int? likelyBankId;
    var best = -1;
    bankVotes.forEach((id, votes) {
      if (votes > best) {
        best = votes;
        likelyBankId = id;
      }
    });
    final health = hMembers == 0
        ? null
        : ExtractionHealth(
            members: hMembers,
            appAccepted: hAccepted,
            typeValid: hTypeValid,
            amountParsed: hAmount,
            balanceExpected: hBalExpected,
            balanceCaptured: hBalCaptured,
            balanceParsed: hBalParsed,
            counterparty: hCounterparty,
            refReal: hRefReal,
            refSynthesized: hRefSynth,
            accountExpected: hAcctExpected,
            accountCaptured: hAcctCaptured,
            feesExpected: hFeesExpected,
            feesCaptured: hFeesCaptured,
            patternDescriptions: Map.unmodifiable(hPatternDescs),
          );
    return TemplateCluster(
      template: template,
      occurrences: count,
      examples: List.unmodifiable(examples),
      likelyBankId: likelyBankId,
      likelyBankName: likelyBankId == null ? null : bankNames[likelyBankId],
      fieldSpans: fieldSpans,
      degraded: degraded,
      health: health,
    );
  }
}
