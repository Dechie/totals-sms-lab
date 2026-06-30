import '../models/template_cluster.dart';

/// Groups exact clusters into broader *template families* (e.g. "Outgoing
/// Transfers") whose members differ only in wording.
///
/// ⚑ V2/V3 implementers: read ROADMAP_NOTES.md before changing this contract.
/// Today `group()` only *tags* clusters (sets `similarityGroup`). Merging into
/// families requires a `TemplateFamily` type and a pipeline/report change —
/// the notes spell out the exact shape.
///
/// Roadmap:
///   * V2 — Levenshtein distance to merge near-identical templates.
///   * V3 — TF-IDF + cosine similarity for semantic families.
///
/// V1 ships the interface and an identity grouper so the pipeline and reports
/// already speak in terms of families; the smarter groupers slot in behind
/// this same contract without touching callers.
abstract class SimilarityGrouper {
  /// Assigns a `similarityGroup` label to each cluster (mutating in place is
  /// avoided; returns the same list for chaining).
  List<TemplateCluster> group(List<TemplateCluster> clusters);
}

/// V1 default: every cluster is its own family. No merging, fully
/// deterministic, zero cost.
class IdentityGrouper implements SimilarityGrouper {
  @override
  List<TemplateCluster> group(List<TemplateCluster> clusters) => clusters;
}
