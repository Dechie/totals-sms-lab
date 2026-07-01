import '../models/coverage_report.dart';
import '../models/template_family.dart';

/// Builds the **privacy-safe enrichment export** — the artifact a maintainer
/// asks contributors to send back so a corpus can be assembled without any real
/// SMS leaving a device (INSIGHTS.md, ENRICHMENT_FIELDS.md).
///
/// Each unit describes one discovered gap category by its *shape*, never its
/// values:
///   * `normalizedText` — the anonymized skeleton (names/amounts already
///     replaced by placeholders during normalization),
///   * `actionVerb` + `direction` — the semantic tag (V2 step 1),
///   * `shapeProfile` — per-field generalized regex (V2 shape profiling),
///   * `count` — how many messages back the category (impact),
///   * `bank` — attributed bank name, or null for an unrecognized sender,
///   * `matched` — whether the host parser already covers it (always false
///     here: only *unmatched* families are exported — they are the gaps).
///
/// Raw field values and raw message bodies are **never** included. Contributors
/// should still eyeball the output (`--preview`) before sending, since a shape
/// is only as trustworthy as the normalization that produced it.
class EnrichmentExport {
  static const version = 1;

  /// Assemble the export document from an analyzed [report].
  static Map<String, dynamic> build(CoverageReport report,
      {required String parserName}) {
    final units = <Map<String, dynamic>>[
      for (final f in report.attributedFamilies) _unit(f),
      for (final f in report.candidateFamilies) _unit(f),
    ];
    return {
      'version': version,
      'parser': parserName,
      'unitCount': units.length,
      'units': units,
    };
  }

  static Map<String, dynamic> _unit(TemplateFamily f) => {
        'normalizedText': f.template,
        'actionVerb': f.actionVerb,
        'direction': f.direction?.name,
        'shapeProfile': {
          for (final e in f.shapeProfile().entries) e.key: e.value.toJson(),
        },
        'count': f.totalOccurrences,
        'bank': f.likelyBankName,
        'matched': false,
      };

  /// A short human summary for `--preview`, so a contributor can review exactly
  /// what would be shared before it leaves their device.
  static String preview(Map<String, dynamic> doc) {
    final units = (doc['units'] as List).cast<Map<String, dynamic>>();
    final b = StringBuffer()
      ..writeln('Enrichment export preview — ${units.length} unit(s), '
          'parser "${doc['parser']}".')
      ..writeln('Only the fields below are shared; no raw values or bodies.\n');
    for (final u in units) {
      final verb = u['actionVerb'] == null
          ? 'no-verb'
          : '${u['actionVerb']} (${u['direction']})';
      b.writeln('• [$verb] ×${u['count']}'
          '${u['bank'] == null ? ' · new sender' : ' · ${u['bank']}'}');
      b.writeln('    ${u['normalizedText']}');
      final shapes = (u['shapeProfile'] as Map).cast<String, dynamic>();
      for (final field in shapes.keys) {
        final s = (shapes[field] as Map).cast<String, dynamic>();
        b.writeln('    <$field> ~ ${s['regex']}  (×${s['samples']})');
      }
      b.writeln('');
    }
    return b.toString();
  }
}
