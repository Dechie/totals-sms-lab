import 'extraction_health.dart';
import 'template_family.dart';

/// A family of *successfully matched* messages, paired with its aggregated
/// [ExtractionHealth]. Composition (not subclassing) so [TemplateFamily] keeps
/// its existing "unmatched gap" semantics everywhere else.
///
/// The [shape] carries the privacy-safe template + shape profile + occurrence
/// count + bank (reused from the same clustering machinery as unmatched units);
/// [health] carries the field-presence rates and the totals-impact score.
class SuccessFamily {
  final TemplateFamily shape;
  final ExtractionHealth health;

  const SuccessFamily(this.shape, this.health);

  /// Fold the extraction health of every member cluster of [family].
  factory SuccessFamily.fromFamily(TemplateFamily family) {
    var h = ExtractionHealth.empty;
    for (final c in family.members) {
      if (c.health != null) h = h.merge(c.health!);
    }
    return SuccessFamily(family, h);
  }

  String get template => shape.template;
  int get count => shape.totalOccurrences;
  String? get likelyBankName => shape.likelyBankName;
  int? get likelyBankId => shape.likelyBankId;

  int get healthScore => health.healthScore;

  /// True only when EVERY member message would pass the app's accept-gate.
  /// A regex-matched-but-app-rejected family has this false and score ~0.
  bool get appAccepted =>
      health.members > 0 && health.appAccepted == health.members;

  /// Modal winning-pattern description behind this family (pattern metadata).
  String? get patternDescription => health.topPatternDescription;
}
