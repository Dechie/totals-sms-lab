import 'template_cluster.dart';

/// A group of exact-template [TemplateCluster]s that are the *same logical
/// message shape* — e.g. "outgoing transfer" — even if their wording differs
/// slightly. This is the discrete, regex-targetable **category** the tool
/// exists to produce (see INSIGHTS.md — "actionable patterns").
///
/// V1's clustering is exact, so a family often has a single member. V2's
/// Levenshtein/TF-IDF groupers merge near-identical and semantically-similar
/// clusters into multi-member families; the reports and priority already speak
/// in families so nothing downstream changes when that lands.
class TemplateFamily {
  /// Member clusters, sorted highest-occurrence first (representative = first).
  final List<TemplateCluster> members;

  /// Optional human label ("Outgoing transfers"); V4 assigns these.
  final String? label;

  TemplateFamily(List<TemplateCluster> members, {this.label})
      : assert(members.isNotEmpty),
        members = _sorted(members);

  static List<TemplateCluster> _sorted(List<TemplateCluster> m) =>
      [...m]..sort((a, b) => b.occurrences.compareTo(a.occurrences));

  /// The canonical member — the shape a developer writes the regex against.
  TemplateCluster get representative => members.first;

  int get memberCount => members.length;

  /// Total occurrences across the family — what its priority is judged on.
  int get totalOccurrences =>
      members.fold(0, (sum, c) => sum + c.occurrences);

  String get template => representative.template;

  int? get likelyBankId => representative.likelyBankId;
  String? get likelyBankName => representative.likelyBankName;

  /// Canonical action verb + direction the family was grouped on (from the
  /// representative; all members of a verb bucket share these). `null` for
  /// families that carry no action word (IdentityGrouper, or untagged shapes).
  String? get actionVerb => representative.actionVerb;
  TxDirection? get direction => representative.direction;

  /// Regex-readiness of the shape a dev would author (the representative).
  String get regexReadiness => representative.regexReadiness;

  /// Priority buckets on the *family* total, so a shape fragmented across many
  /// low-count variants still ranks by its true impact.
  String get priority => TemplateCluster.priorityFor(totalOccurrences);
  int get priorityRank => TemplateCluster.priorityRankFor(priority);

  /// Representative examples across members (deduped, capped) so authoring sees
  /// the spread of real values within the category.
  List<String> examples({int max = 6}) {
    final seen = <String>{};
    final out = <String>[];
    for (final m in members) {
      for (final ex in m.examples) {
        if (seen.add(ex)) {
          out.add(ex);
          if (out.length >= max) return out;
        }
      }
    }
    return out;
  }

  /// The other member templates (excluding the representative) — the "variants"
  /// shown as drill-down when a family has more than one member.
  List<String> get variantTemplates =>
      [for (final m in members.skip(1)) m.template];
}
