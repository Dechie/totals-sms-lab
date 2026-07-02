import 'dart:convert';

import 'package:sms_pattern_lab/analysis/analysis_pipeline.dart';
import 'package:sms_pattern_lab/export/enrichment_export.dart';
import 'package:sms_pattern_lab/models/coverage_report.dart';
import 'package:sms_pattern_lab/models/data_quality.dart';
import 'package:sms_pattern_lab/models/extraction_health.dart';
import 'package:sms_pattern_lab/models/success_family.dart';
import 'package:sms_pattern_lab/models/template_cluster.dart';
import 'package:sms_pattern_lab/models/template_family.dart';
import 'package:sms_pattern_lab/parser_adapter/totals_parser_adapter.dart';
import 'package:sms_pattern_lab/similarity/semantic_verb_grouper.dart';
import 'package:sms_pattern_lab/utils/dataset_loader.dart';
import 'package:test/test.dart';

CoverageReport reportWith({
  List<TemplateFamily> attributed = const [],
  List<TemplateFamily> candidate = const [],
  List<SuccessFamily> success = const [],
  int appAccepted = 0,
}) =>
    CoverageReport(
      total: 10,
      matched: 6,
      unattributed: 0,
      parsers: const [],
      unmatchedClusters: const [],
      attributedFamilies: attributed,
      candidateFamilies: candidate,
      successFamilies: success,
      appAccepted: appAccepted,
    );

/// A perfectly-healthy success family (every totals-critical field captured).
SuccessFamily healthySuccessFamily() {
  final cluster = TemplateCluster(
    template: 'credited <AMOUNT>',
    occurrences: 2,
    likelyBankName: 'CBE',
    fieldSpans: {
      'AMOUNT': ['100', '200']
    },
    health: const ExtractionHealth(
      members: 2,
      appAccepted: 2,
      typeValid: 2,
      amountParsed: 2,
      balanceExpected: 2,
      balanceCaptured: 2,
      balanceParsed: 2,
      counterparty: 2,
      refReal: 2,
      refSynthesized: 0,
      accountExpected: 0,
      accountCaptured: 0,
      feesExpected: 0,
      feesCaptured: 0,
      patternDescriptions: {'CBE Credit': 2},
    ),
  );
  return SuccessFamily.fromFamily(TemplateFamily([cluster]));
}

void main() {
  group('family-level shape profile (union over members)', () {
    test('covers the spread of values across all member clusters', () {
      final f = TemplateFamily([
        TemplateCluster(
            template: 'credited <AMOUNT>',
            occurrences: 2,
            fieldSpans: {
              'AMOUNT': ['100', '200']
            }),
        TemplateCluster(
            template: 'credited <AMOUNT>',
            occurrences: 1,
            fieldSpans: {
              'AMOUNT': ['5000']
            }),
      ]);
      final shape = f.shapeProfile()['AMOUNT']!;
      expect(shape.regex, equals(r'\d{3,4}'));
      expect(shape.samples, equals(3));
    });
  });

  group('EnrichmentExport metadata (baseline + dataset + coverage)', () {
    test('stamps baselineSignature, datasetId, coverage and quality', () {
      final f = TemplateFamily([
        TemplateCluster(
            template: 'credited <AMOUNT>',
            occurrences: 3,
            likelyBankName: 'CBE',
            fieldSpans: {
              'AMOUNT': ['100', '200', '300']
            }),
      ]);
      final doc = EnrichmentExport.build(
        reportWith(attributed: [f]),
        parserName: 'Test Parser',
        baselineSignature: 'abc123def456abcd',
        baselineSource: 'vendored snapshot',
        datasetId: '0011223344556677',
        grouping: 'verb',
      );

      final meta = doc['metadata'] as Map;
      expect(meta['version'], equals(EnrichmentExport.version));
      expect(meta['baselineSignature'], equals('abc123def456abcd'));
      expect(meta['datasetId'], equals('0011223344556677'));
      expect(meta['grouping'], equals('verb'));
      expect((meta['coverage'] as Map)['overallPercent'], equals(60.0));
      expect((meta['quality'] as Map)['clean'], isTrue);
      expect(meta['categories'], equals(1));

      // Parse success/failure — "x of y".
      final msgs = meta['messages'] as Map;
      expect(msgs['total'], equals(10));
      expect(msgs['parsed'], equals(6));
      expect(msgs['unparsed'], equals(4));
      expect(msgs['parsedPercent'], equals(60.0));
      expect(msgs['parseErrors'], equals(0));

      // v4: metadata, then the two body lists, in order.
      expect(doc.keys.toList(),
          equals(['metadata', 'unmatchedUnits', 'successUnits']));
    });

    test('v4 scores successUnits and splits the message tally', () {
      final doc = EnrichmentExport.build(
        reportWith(success: [healthySuccessFamily()], appAccepted: 2),
        parserName: 'Test Parser',
        baselineSignature: 'sig',
        datasetId: 'ds',
      );

      final meta = doc['metadata'] as Map;
      final msgs = meta['messages'] as Map;
      expect(msgs['regexMatched'], equals(6));
      expect(msgs['appAccepted'], equals(2));
      expect(msgs['appRejected'], equals(4)); // regexMatched - appAccepted
      expect(meta['successCategories'], equals(1));

      final success = (doc['successUnits'] as List).cast<Map>();
      expect(success, hasLength(1));
      final u = success.first;
      expect(u['matched'], isTrue);
      expect(u['appAccepted'], isTrue);
      expect(u['bank'], equals('CBE'));
      expect(u['patternDescription'], equals('CBE Credit'));
      expect(u['healthScore'], equals(100)); // every field captured
      expect((u['health'] as Map)['typeValidRate'], equals(1.0));

      final recon = meta['reconciliation'] as Map;
      expect(recon['typeValidShare'], equals(100.0));
      expect(recon['counterpartyShare'], equals(100.0));
      expect(recon['meanHealthScore'], equals(100));
      expect(recon['lowHealthFamilies'], equals(0));
    });

    test('redacts degraded families — count survives, content withheld', () {
      final degraded = TemplateFamily([
        TemplateCluster(
            template: 'Dear RAWNAME credited <AMOUNT>',
            occurrences: 4,
            likelyBankName: 'CBE',
            degraded: true,
            fieldSpans: {
              'AMOUNT': ['1', '2', '3']
            }),
      ]);
      final q = DataQuality();
      final doc = EnrichmentExport.build(
        reportWith(attributed: [degraded]),
        parserName: 'Test',
        baselineSignature: 'sig',
        datasetId: 'ds',
        quality: q,
      );
      final unit = (doc['unmatchedUnits'] as List).first as Map;
      expect(unit['redacted'], isTrue);
      expect(unit['normalizedText'], isNull); // untrusted content withheld
      expect(unit['count'], equals(4)); // ...but the impact signal survives
      expect(unit['bank'], equals('CBE'));
      expect(q.unitsRedacted, equals(1));
      // The raw name never reaches the serialized artifact.
      expect(jsonEncode(doc), isNot(contains('RAWNAME')));
    });
  });

  group('EnrichmentExport on real data (privacy)', () {
    final adapter = TotalsParserAdapter.autodiscover();

    test('never leaks raw values into the serialized export', () {
      if (adapter == null) return;
      final quality = DataQuality();
      final messages =
          DatasetLoader.load('example/cbe_sms.json', quality: quality);
      final result = AnalysisPipeline(
              adapter: adapter, grouper: SemanticVerbGrouper())
          .run(messages, quality: quality);

      final doc = EnrichmentExport.build(
        result.coverage,
        parserName: adapter.name,
        baselineSignature: adapter.baseline().signature,
        datasetId: 'testds',
        quality: quality,
      );

      final serialized = jsonEncode(doc);
      for (final leak in [
        'Dechasa', 'Teshome', 'Gemechu', 'Abdurezak', 'Tirhas',
        '6843', '420.00', 'hfHCxz',
      ]) {
        expect(serialized, isNot(contains(leak)),
            reason: 'raw value "$leak" leaked into the export');
      }
      for (final u in (doc['unmatchedUnits'] as List).cast<Map>()) {
        expect(u['matched'], isFalse);
      }
      // successUnits carry health, never raw values, and are all regex-matched.
      for (final u in (doc['successUnits'] as List).cast<Map>()) {
        expect(u['matched'], isTrue);
        expect(u['healthScore'], isA<int>());
        expect(u['health'], isA<Map>());
      }
    });
  });
}
