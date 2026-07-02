import '../models/coverage_report.dart';
import '../models/data_quality.dart';
import '../models/extraction_health.dart';
import '../models/success_family.dart';
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
///
/// Shape (schema v4): a leading `metadata` object — everything about the run
/// (baseline signature, dataset id, parse success/failure counts, coverage, the
/// category counts, a reconciliation-health rollup, and the data-quality
/// ledger) — followed by two bodies: `unmatchedUnits` (the parser GAPS, exactly
/// the old v3 `units`) and `successUnits` (successfully-matched families, each
/// scored by extraction health). Read the header first; it says how much to
/// trust the body.
class EnrichmentExport {
  /// v2 added baseline/dataset/quality; v3 nested it all under `metadata` and
  /// added explicit parse success/failure + category counts; v4 renamed `units`
  /// → `unmatchedUnits`, added the scored `successUnits` list, and split the
  /// message tally into regexMatched / appAccepted / appRejected.
  static const version = 4;

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

    final unmatchedUnits = <Map<String, dynamic>>[];
    for (final f in [...report.attributedFamilies, ...report.candidateFamilies]) {
      final unit = _tryUnit(f, q);
      if (unit != null) unmatchedUnits.add(unit);
    }

    final successUnits = <Map<String, dynamic>>[];
    for (final f in report.successFamilies) {
      final unit = _trySuccessUnit(f, q);
      if (unit != null) successUnits.add(unit);
    }

    final metadata = <String, dynamic>{
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
      // Parse success/failure. `parsed`/`parsedPercent` stay = regex-matched for
      // back-compat with v3 consumers; `appAccepted` is the stricter "the app
      // would produce a usable transaction" count, and `appRejected` is the
      // silent-drop tier (regex matched but the accept-gate dropped it).
      'messages': {
        'total': report.total,
        'parsed': report.matched,
        'regexMatched': report.regexMatched,
        'appAccepted': report.appAccepted,
        'appRejected': report.regexMatched - report.appAccepted,
        'unparsed': report.unmatched, // no pattern matched (the gaps)
        'parsedPercent':
            double.parse(report.overallCoveragePercent.toStringAsFixed(2)),
        'parseErrors': q.parseErrors, // messages the parser threw on
      },
      // Distinct categories: unmatched gaps vs successfully-matched families.
      'categories': unmatchedUnits.length,
      'successCategories': successUnits.length,
      'coverage': _coverage(report),
      'reconciliation': _reconciliation(report),
      'quality': q.toJson(),
    };

    return {
      'metadata': metadata,
      'unmatchedUnits': unmatchedUnits,
      'successUnits': successUnits,
    };
  }

  /// Rollup of how usable the successfully-matched transactions are — the lens
  /// on the app's income/expense/balance reconciliation. All shares are
  /// marginal (over matched messages) and computed from privacy-safe counts.
  static Map<String, dynamic> _reconciliation(CoverageReport report) {
    var agg = ExtractionHealth.empty;
    var scoreWeighted = 0;
    var scoreWeight = 0;
    var lowHealth = 0;
    for (final f in report.successFamilies) {
      agg = agg.merge(f.health);
      scoreWeighted += f.healthScore * f.count;
      scoreWeight += f.count;
      if (f.appAccepted && f.healthScore < 50) lowHealth++;
    }
    return {
      'meanHealthScore': scoreWeight == 0 ? 0 : (scoreWeighted / scoreWeight).round(),
      // The three totals-breaking risks, as a share of matched messages.
      'typeValidShare': _pct(agg.typeValidRate),
      'balanceCapturedShare': _pct(agg.balanceCapturedRate),
      'counterpartyShare': _pct(agg.counterpartyRate),
      'appAcceptedShare': _pct(agg.appAcceptedRate),
      'lowHealthFamilies': lowHealth, // accepted families scoring < 50
    };
  }

  static double _pct(double rate) => double.parse((rate * 100).toStringAsFixed(2));

  /// Per-bank coverage snapshot — mirrors the V4 coverage-history schema so an
  /// export doubles as a coverage record tied to (baselineSignature, datasetId).
  static Map<String, dynamic> _coverage(CoverageReport r) => {
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

  /// Build one privacy-safe `successUnit`: the anonymized shape of a
  /// successfully-matched family plus its extraction-health rates and score.
  /// Same degraded-redaction contract as [_tryUnit] for text/shape; the numeric
  /// health fields carry no raw values, so they survive redaction.
  static Map<String, dynamic>? _trySuccessUnit(SuccessFamily f, DataQuality q) {
    try {
      final health = f.health;
      final base = <String, dynamic>{
        'count': f.count,
        'bank': f.likelyBankName,
        'matched': true,
        'patternDescription': f.patternDescription,
        'appAccepted': f.appAccepted,
        'healthScore': f.healthScore,
        'health': health.toRatesJson(),
      };

      // Degraded source → keep the count + health signal, drop untrusted content.
      if (f.shape.members.any((m) => m.degraded)) {
        q.unitsRedacted++;
        return {
          'redacted': true,
          'reason': 'normalization degraded — content withheld',
          'normalizedText': null,
          'actionVerb': null,
          'direction': null,
          'shapeProfile': const {},
          ...base,
        };
      }

      Map<String, dynamic> shape;
      try {
        shape = {
          for (final e in f.shape.shapeProfile().entries) e.key: e.value.toJson(),
        };
      } catch (_) {
        q.fieldShapeFallbacks++;
        shape = const {};
      }

      q.unitsExported++;
      return {
        'normalizedText': f.shape.template,
        'actionVerb': f.shape.actionVerb,
        'direction': f.shape.direction?.name,
        'shapeProfile': shape,
        ...base,
      };
    } catch (_) {
      q.unitErrors++;
      return null;
    }
  }

  /// A short human summary for `--preview`, so a contributor can review exactly
  /// what would be shared before it leaves their device.
  static String preview(Map<String, dynamic> doc) {
    final meta = doc['metadata'] as Map<String, dynamic>;
    final units = (doc['unmatchedUnits'] as List).cast<Map<String, dynamic>>();
    final successUnits =
        (doc['successUnits'] as List? ?? const []).cast<Map<String, dynamic>>();
    final msgs = meta['messages'] as Map<String, dynamic>;
    final b = StringBuffer()
      ..writeln('Enrichment export preview — parser "${meta['parser']}".')
      ..writeln('Regex-matched ${msgs['regexMatched']}/${msgs['total']} '
          '(${msgs['parsedPercent']}%); app-accepted ${msgs['appAccepted']}, '
          'app-rejected ${msgs['appRejected']}; '
          '${msgs['unparsed']} unparsed → ${meta['categories']} gap categor'
          '${meta['categories'] == 1 ? 'y' : 'ies'}, '
          '${meta['successCategories']} success categor'
          '${meta['successCategories'] == 1 ? 'y' : 'ies'}.')
      ..writeln('Baseline ${meta['baselineSignature']} · '
          'dataset ${meta['datasetId']}')
      ..writeln('Data quality: ${_qualitySummary(meta)}')
      ..writeln('Only the fields below are shared; no raw values or bodies.\n')
      ..writeln('── Unmatched gaps ──');
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

    if (successUnits.isNotEmpty) {
      final recon = meta['reconciliation'] as Map<String, dynamic>? ?? const {};
      b
        ..writeln('── Successful parses (extraction health, worst first) ──')
        ..writeln('mean health ${recon['meanHealthScore']}/100 · '
            'type-valid ${recon['typeValidShare']}% · '
            'balance ${recon['balanceCapturedShare']}% · '
            'counterparty ${recon['counterpartyShare']}% · '
            '${recon['lowHealthFamilies']} family(ies) < 50\n');
      for (final u in successUnits) {
        final h = (u['health'] as Map).cast<String, dynamic>();
        final accepted = u['appAccepted'] == true ? 'accepted' : 'REJECTED';
        b.writeln('• [score ${u['healthScore']}/100 · $accepted] ×${u['count']}'
            '${u['bank'] == null ? '' : ' · ${u['bank']}'}'
            '${u['patternDescription'] == null ? '' : ' · ${u['patternDescription']}'}');
        if (u['normalizedText'] != null) b.writeln('    ${u['normalizedText']}');
        b.writeln('    type ${_p(h['typeValidRate'])} · '
            'bal ${_p((h['balance'] as Map)['parseRate'])} · '
            'party ${_p(h['counterpartyRate'])} · '
            'ref ${_p((h['reference'] as Map)['realRate'])}');
        b.writeln('');
      }
    }
    return b.toString();
  }

  static String _p(Object? rate) =>
      '${(((rate as num?) ?? 0) * 100).round()}%';

  static String _qualitySummary(Map<String, dynamic> meta) {
    final q = meta['quality'] as Map<String, dynamic>;
    if (q['clean'] == true) return 'clean (no anomalies)';
    final parts = <String>[];
    q.forEach((k, v) {
      if (k != 'clean' && v is int && v > 0) parts.add('$k=$v');
    });
    return parts.join(', ');
  }
}
