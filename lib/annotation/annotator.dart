import '../models/template_cluster.dart';
import 'action_lexicon.dart';

/// The action-verb tag a template earned: the canonical [verb] lemma and its
/// [direction]. `Annotation.none` means no lexicon word matched — a *signal*
/// (a transactional-looking template with no verb is a candidate new action
/// word), not a failure.
class Annotation {
  final String? verb;
  final TxDirection? direction;
  const Annotation(this.verb, this.direction);
  static const none = Annotation(null, null);

  bool get isEmpty => verb == null;
}

/// Post-normalization enrichment (V2 step 1). Scans a normalized template for
/// action words from the [ActionLexicon] and tags it with a canonical verb +
/// direction. Deterministic, O(tokens) lookup, zero training — it does most of
/// the semantic grouping work that TF-IDF would, far more cheaply, and hands
/// `SemanticVerbGrouper` a ready-made grouping key + family label.
///
/// See ROADMAP_NOTES §3, ENRICHMENT_FIELDS.md. The verb is a *tag, not a strip*.
class Annotator {
  final ActionLexicon lexicon;

  Annotator({ActionLexicon? lexicon})
      : lexicon = lexicon ?? ActionLexicon.defaultLexicon;

  /// Splits into lower-cased word tokens. Placeholders like `<AMOUNT>` never
  /// match lexicon words, so they're harmlessly ignored.
  static final RegExp _token = RegExp(r'[a-z]+');

  /// The primary action verb for [template].
  ///
  /// When several verbs appear, a **directional** verb (incoming/outgoing) wins
  /// over a neutral/status word — so "successfully transferred" tags as
  /// *transfer* (outgoing), not *success*. Within the same tier the
  /// earliest-position match wins (first-match), keeping it deterministic.
  Annotation annotate(String template) {
    final lower = template.toLowerCase();
    ActionWord? directional;
    ActionWord? neutral;
    for (final m in _token.allMatches(lower)) {
      final word = lexicon.forForm(m.group(0)!);
      if (word == null) continue;
      if (word.direction == TxDirection.neutral) {
        neutral ??= word;
      } else {
        directional ??= word;
        break; // earliest directional verb wins outright
      }
    }
    final chosen = directional ?? neutral;
    return chosen == null
        ? Annotation.none
        : Annotation(chosen.lemma, chosen.direction);
  }

  /// Tags [cluster] in place (mutates [TemplateCluster.actionVerb]/`direction`)
  /// and returns it, so callers can `clusters.forEach(annotator.tag)`.
  TemplateCluster tag(TemplateCluster cluster) {
    final a = annotate(cluster.template);
    cluster.actionVerb = a.verb;
    cluster.direction = a.direction;
    return cluster;
  }
}
