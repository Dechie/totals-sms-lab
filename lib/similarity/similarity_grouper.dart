import '../models/template_cluster.dart';
import '../models/template_family.dart';

/// Groups exact [TemplateCluster]s into broader [TemplateFamily]s (e.g.
/// "Outgoing Transfers") whose members are the same logical shape despite
/// wording differences.
///
/// ⚑ V2/V3 implementers: read ROADMAP_NOTES.md / ALGORITHMS.md before adding a
/// grouper. The contract returns *families*: to merge, put related clusters in
/// the same `TemplateFamily`. Always block by `likelyBankId` — never merge
/// clusters from different banks.
///
/// Roadmap:
///   * V2 — Levenshtein distance to merge near-identical templates.
///   * V3 — TF-IDF + cosine similarity for semantic families.
abstract class SimilarityGrouper {
  /// Partition [clusters] into families. Every cluster ends up in exactly one.
  List<TemplateFamily> group(List<TemplateCluster> clusters);
}

/// V1/default: every cluster is its own family. No merging, fully
/// deterministic, zero cost — preserves pre-V2 behavior.
class IdentityGrouper implements SimilarityGrouper {
  @override
  List<TemplateFamily> group(List<TemplateCluster> clusters) =>
      [for (final c in clusters) TemplateFamily([c])];
}
