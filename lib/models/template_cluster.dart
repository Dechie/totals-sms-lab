import '../annotation/shape_profile.dart';

/// Transaction direction inferred from a template's action verb.
///
/// `incoming` (money in: credited/received/deposited), `outgoing` (money out:
/// debited/transferred/paid/withdrawn), or `neutral` (status/ambiguous verbs
/// like confirmed/successful/transaction). Set by the `Annotator` and used by
/// `SemanticVerbGrouper` to bucket and label families (ENRICHMENT_FIELDS.md).
enum TxDirection { incoming, outgoing, neutral }

/// A group of unmatched messages that share the same normalized template.
///
/// Produced by the clustering stage. Priority is a derived heuristic used to
/// rank where regex effort should go first.
///
/// ⚑ V2: this flat cluster is the unit V2 merges into `TemplateFamily`
/// objects (aggregating occurrences/examples). The `Annotator` tags each
/// cluster with an [actionVerb] + [direction] (V2 step 1) that the
/// `SemanticVerbGrouper` groups on. See ROADMAP_NOTES.md before extending.
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

  /// Canonical action-verb lemma tagged by the `Annotator` (e.g. "transfer"
  /// for "transferred"/"transfer of"), or `null` if no lexicon word matched.
  /// It is a *tag*, never stripped — the verb stays in [template].
  String? actionVerb;

  /// Transaction direction derived from [actionVerb]. `null` iff [actionVerb]
  /// is `null`.
  TxDirection? direction;

  /// Raw values each placeholder replaced, keyed by field name (`AMOUNT`, …),
  /// aggregated across this cluster's messages. **Local-only** — these can hold
  /// real names/amounts, so they are never exported; the `ShapeProfiler`
  /// generalizes them into a privacy-safe regex (see [shapeProfile]).
  final Map<String, List<String>> fieldSpans;

  TemplateCluster({
    required this.template,
    required this.occurrences,
    List<String>? examples,
    this.likelyBankId,
    this.likelyBankName,
    this.similarityGroup,
    this.actionVerb,
    this.direction,
    Map<String, List<String>>? fieldSpans,
  })  : examples = examples ?? <String>[],
        fieldSpans = fieldSpans ?? const {};

  /// Priority bucket derived from occurrence count.
  /// Frequent unmatched templates are the cheapest, highest-impact wins.
  /// Shared with [TemplateFamily] (which buckets on *total* family occurrences).
  static String priorityFor(int occurrences) {
    if (occurrences >= 500) return 'Very High';
    if (occurrences >= 100) return 'High';
    if (occurrences >= 20) return 'Medium';
    if (occurrences >= 5) return 'Low';
    return 'Very Low';
  }

  /// Numeric rank for sorting (higher = more urgent).
  static int priorityRankFor(String priority) {
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

  String get priority => priorityFor(occurrences);

  int get priorityRank => priorityRankFor(priority);

  /// Privacy-safe per-field shape (generalized regex) derived from [fieldSpans].
  /// Empty when no spans were captured (e.g. a template with no placeholders).
  Map<String, FieldShape> get shapeProfile =>
      ShapeProfiler.profileAll(fieldSpans);

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
