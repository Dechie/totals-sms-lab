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

  /// Cluster the unmatched subset of [results].
  List<TemplateCluster> clusterUnmatched(Iterable<ParseResult> results) {
    final unmatched = results.where((r) => !r.matched);

    final byTemplate = <String, _Bucket>{};
    for (final r in unmatched) {
      final norm = _normalizer.normalizeWithSpans(r.message.body);
      final bucket =
          byTemplate.putIfAbsent(norm.template, () => _Bucket(norm.template));
      bucket.add(r, norm.spans, maxExamples);
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

  _Bucket(this.template);

  void add(ParseResult r, Map<String, List<String>> spans, int maxExamples) {
    count++;
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
    return TemplateCluster(
      template: template,
      occurrences: count,
      examples: List.unmodifiable(examples),
      likelyBankId: likelyBankId,
      likelyBankName: likelyBankId == null ? null : bankNames[likelyBankId],
      fieldSpans: fieldSpans,
    );
  }
}
