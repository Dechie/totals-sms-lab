import '../models/coverage_report.dart';
import '../models/data_quality.dart';
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
/// The document is stamped with the **parser `baselineSignature`** (which parser
/// version the gaps were measured against — the drift/regression key) and a
/// **`datasetId`** (the corpus content hash — the like-for-like key), so a pile
/// of contributor exports can be grouped, compared, and fed into coverage
/// history. It also carries a `coverage` snapshot and a `quality` block so a
/// partial run is never mistaken for a complete one.
///
/// Robust by contract: one bad family never sinks the export. A family whose
/// normalization was degraded is **redacted** (its count survives, its untrusted
/// text/shape do not); a family that fails to serialize is dropped and counted.
/// Raw values and raw bodies are never included.
class EnrichmentExport {
  /// Bumped to 2 when the document gained baseline/dataset/quality metadata.
  static const version = 2;

  static Map<String, dynamic> build(
    CoverageReport report, {
    required String parserName,
    required String baselineSignature,
    String? baselineSource,
    required String datasetId,
    String? generatedAt,
    String grouping = 'identity',
    double? similarity,
    DataQuality? quality,
  }) {
    final q = quality ?? DataQuality();

    final units = <Map<String, dynamic>>[];
    for (final f in [...report.attributedFamilies, ...report.candidateFamilies]) {
      final unit = _tryUnit(f, q);
      if (unit != null) units.add(unit);
    }

    return {
      'version': version,
      if (generatedAt != null) 'generatedAt': generatedAt,
      'parser': parserName,
      // Drift key: which parser version these gaps were measured against.
      'baselineSignature': baselineSignature,
      if (baselineSource != null) 'baselineSource': baselineSource,
      // Corpus key: content hash of the dataset, for like-for-like comparison.
      'datasetId': datasetId,
      'grouping': grouping,
      if (similarity != null) 'similarity': similarity,
      'coverage': _coverage(report),
      'quality': q.toJson(),
      'unitCount': units.length,
      'units': units,
    };
  }

  /// Coverage snapshot — mirrors the V4 coverage-history schema so an export
  /// doubles as a coverage record tied to (baselineSignature, datasetId).
  static Map<String, dynamic> _coverage(CoverageReport r) => {
        'total': r.total,
        'matched': r.matched,
        'unmatched': r.unmatched,
        'overallPercent':
            double.parse(r.overallCoveragePercent.toStringAsFixed(2)),
        'perBank': {
          for (final p in r.parsers)
            p.bankName: double.parse(p.coveragePercent.toStringAsFixed(2)),
        },
      };

  static Map<String, dynamic>? _tryUnit(TemplateFamily f, DataQuality q) {
    try {
      // Degraded source → keep the count signal, drop the untrusted content.
      if (f.members.any((m) => m.degraded)) {
        q.unitsRedacted++;
        return {
          'redacted': true,
          'reason': 'normalization degraded — content withheld',
          'normalizedText': null,
          'actionVerb': null,
          'direction': null,
          'shapeProfile': const {},
          'count': f.totalOccurrences,
          'bank': f.likelyBankName,
          'matched': false,
        };
      }

      Map<String, dynamic> shape;
      try {
        shape = {
          for (final e in f.shapeProfile().entries) e.key: e.value.toJson(),
        };
      } catch (_) {
        q.fieldShapeFallbacks++;
        shape = const {};
      }

      q.unitsExported++;
      return {
        'normalizedText': f.template,
        'actionVerb': f.actionVerb,
        'direction': f.direction?.name,
        'shapeProfile': shape,
        'count': f.totalOccurrences,
        'bank': f.likelyBankName,
        'matched': false,
      };
    } catch (_) {
      // A family we couldn't turn into a unit at all — drop it, but count it so
      // the total is honest.
      q.unitErrors++;
      return null;
    }
  }

  /// A short human summary for `--preview`, so a contributor can review exactly
  /// what would be shared before it leaves their device.
  static String preview(Map<String, dynamic> doc) {
    final units = (doc['units'] as List).cast<Map<String, dynamic>>();
    final cov = doc['coverage'] as Map<String, dynamic>;
    final b = StringBuffer()
      ..writeln('Enrichment export preview — ${units.length} unit(s), '
          'parser "${doc['parser']}".')
      ..writeln('Baseline ${doc['baselineSignature']} · '
          'dataset ${doc['datasetId']} · '
          'coverage ${cov['overallPercent']}%')
      ..writeln('Data quality: ${_qualitySummary(doc)}')
      ..writeln('Only the fields below are shared; no raw values or bodies.\n');
    for (final u in units) {
      if (u['redacted'] == true) {
        b.writeln('• [REDACTED — ${u['reason']}] ×${u['count']}'
            '${u['bank'] == null ? '' : ' · ${u['bank']}'}\n');
        continue;
      }
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

  static String _qualitySummary(Map<String, dynamic> doc) {
    final q = doc['quality'] as Map<String, dynamic>;
    if (q['clean'] == true) return 'clean (no anomalies)';
    final parts = <String>[];
    q.forEach((k, v) {
      if (k != 'clean' && v is int && v > 0) parts.add('$k=$v');
    });
    return parts.join(', ');
  }
}
