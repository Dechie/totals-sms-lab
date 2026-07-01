import '../models/template_cluster.dart';
import '../models/template_family.dart';
import 'levenshtein.dart';
import 'similarity_grouper.dart';

/// V2 step 2. Merges near-identical *wording* — "typo" variants and small
/// phrasings the exact clusterer split ("Transferred …" vs "Transfered …") —
/// by edit-distance ratio. Runs on normalized templates, not raw bodies.
///
/// Designed to run **within a verb bucket** (see `SemanticVerbGrouper.within`),
/// where the candidate set is tiny and already semantically coherent, so the
/// O(k²·L) pairwise cost is negligible. It also works standalone.
///
/// Greedy and deterministic (ROADMAP_NOTES §3):
///   * sort templates by occurrence desc (ties broken by template, so the seed
///     order never depends on input order),
///   * each unseeded template starts a family (the seed),
///   * fold any later template into the first seed within [threshold].
///
/// **Blocks by `likelyBankId`** — never merges clusters from different banks.
class LevenshteinGrouper implements SimilarityGrouper {
  /// Merge when `similarityRatio >= threshold`. Start ~0.9; tuned in V3 and
  /// overridable via `--similarity=`.
  final double threshold;

  LevenshteinGrouper({this.threshold = 0.9});

  @override
  List<TemplateFamily> group(List<TemplateCluster> clusters) {
    final byBank = <int?, List<TemplateCluster>>{};
    for (final c in clusters) {
      byBank.putIfAbsent(c.likelyBankId, () => []).add(c);
    }
    final families = <TemplateFamily>[];
    for (final group in byBank.values) {
      families.addAll(_greedy(group));
    }
    return families;
  }

  List<TemplateFamily> _greedy(List<TemplateCluster> clusters) {
    final sorted = [...clusters]..sort((a, b) {
        final byOcc = b.occurrences.compareTo(a.occurrences);
        return byOcc != 0 ? byOcc : a.template.compareTo(b.template);
      });

    final seeds = <List<TemplateCluster>>[];
    for (final c in sorted) {
      var placed = false;
      for (final seed in seeds) {
        if (similarityRatio(c.template, seed.first.template) >= threshold) {
          seed.add(c);
          placed = true;
          break;
        }
      }
      if (!placed) seeds.add([c]);
    }
    return [for (final s in seeds) TemplateFamily(s)];
  }
}
