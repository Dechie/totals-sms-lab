/// A group of unmatched messages that share the same normalized template.
///
/// Produced by the clustering stage. Priority is a derived heuristic used to
/// rank where regex effort should go first.
///
/// ⚑ V2: this flat cluster is the unit V2 will merge into `TemplateFamily`
/// objects (aggregating occurrences/examples). See ROADMAP_NOTES.md before
/// extending — `similarityGroup` is only a placeholder label until then.
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

  // --- regex-readiness ------------------------------------------------------
  //
  // How confidently can a developer turn THIS template into one regex? The
  // signal is anchor density: literal words give a regex something stable to
  // match on, and a strong field (<AMOUNT>/<ACCOUNT>/<REFERENCE>) confirms it's
  // a real transaction shape. A template that is mostly placeholders (e.g.
  // "<NUM> <NUM> <AMOUNT>") is ambiguous and hard to anchor. Heuristic, and
  // independent of clustering — it judges the skeleton itself.
  // See INSIGHTS.md — "actionable patterns / good level of success confidence".

  /// Count of literal anchor words (alphabetic tokens, not placeholders).
  int get _literalAnchorWords =>
      RegExp(r'\b[A-Za-z]{2,}\b').allMatches(_withoutPlaceholders).length;

  String get _withoutPlaceholders =>
      template.replaceAll(RegExp(r'<[A-Z]+>'), ' ');

  /// Whether the template carries a strong transaction field.
  bool get hasStrongField =>
      template.contains('<AMOUNT>') ||
      template.contains('<ACCOUNT>') ||
      template.contains('<REFERENCE>');

  /// `High` / `Medium` / `Low` — how anchorable this skeleton is for a regex.
  String get regexReadiness {
    final anchors = _literalAnchorWords;
    if (hasStrongField && anchors >= 6) return 'High';
    if ((hasStrongField && anchors >= 3) || anchors >= 8) return 'Medium';
    return 'Low';
  }
}
