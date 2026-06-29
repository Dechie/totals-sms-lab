/// A group of unmatched messages that share the same normalized template.
///
/// Produced by the clustering stage. Priority is a derived heuristic used to
/// rank where regex effort should go first.
class TemplateCluster {
  /// The normalized template string (variable data replaced by placeholders).
  final String template;

  /// Representative raw examples (kept small for readable reports).
  final List<String> examples;

  /// How many unmatched messages fell into this cluster.
  int occurrences;

  /// Most likely originating bank id (mode of the cluster), if attributable.
  final int? likelyBankId;

  /// Most likely originating bank name, if attributable.
  final String? likelyBankName;

  /// Optional similarity-group label (assigned by V2/V3 stages).
  String? similarityGroup;

  TemplateCluster({
    required this.template,
    required this.occurrences,
    List<String>? examples,
    this.likelyBankId,
    this.likelyBankName,
    this.similarityGroup,
  }) : examples = examples ?? <String>[];

  /// Priority bucket derived from occurrence count.
  /// Frequent unmatched templates are the cheapest, highest-impact wins.
  String get priority {
    if (occurrences >= 500) return 'Very High';
    if (occurrences >= 100) return 'High';
    if (occurrences >= 20) return 'Medium';
    if (occurrences >= 5) return 'Low';
    return 'Very Low';
  }

  /// Numeric rank for sorting (higher = more urgent).
  int get priorityRank {
    switch (priority) {
      case 'Very High':
        return 5;
      case 'High':
        return 4;
      case 'Medium':
        return 3;
      case 'Low':
        return 2;
      default:
        return 1;
    }
  }
}
