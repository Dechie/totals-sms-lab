import 'dart:convert';

import 'package:sms_pattern_lab/analysis/analysis_pipeline.dart';
import 'package:sms_pattern_lab/export/enrichment_export.dart';
import 'package:sms_pattern_lab/models/template_cluster.dart';
import 'package:sms_pattern_lab/models/template_family.dart';
import 'package:sms_pattern_lab/parser_adapter/totals_parser_adapter.dart';
import 'package:sms_pattern_lab/similarity/semantic_verb_grouper.dart';
import 'package:sms_pattern_lab/utils/dataset_loader.dart';
import 'package:test/test.dart';

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
      // 3 samples (100, 200, 5000) → digit run 3..4.
      expect(shape.regex, equals(r'\d{3,4}'));
      expect(shape.samples, equals(3));
    });
  });

  group('EnrichmentExport (privacy-safe artifact)', () {
    final adapter = TotalsParserAdapter.autodiscover();

    test('builds units with the documented fields and never leaks raw values',
        () {
      if (adapter == null) return; // covered by pipeline_test
      final messages = DatasetLoader.load('example/cbe_sms.json');
      final report = AnalysisPipeline(
              adapter: adapter, grouper: SemanticVerbGrouper())
          .run(messages)
          .coverage;

      final doc =
          EnrichmentExport.build(report, parserName: adapter.name);
      final units = (doc['units'] as List).cast<Map<String, dynamic>>();

      expect(doc['version'], equals(EnrichmentExport.version));
      expect(units, isNotEmpty);
      expect(doc['unitCount'], equals(units.length));

      for (final u in units) {
        expect(u.keys,
            containsAll(['normalizedText', 'actionVerb', 'shapeProfile',
              'count', 'bank', 'matched']));
        expect(u['normalizedText'], isA<String>());
        expect(u['shapeProfile'], isA<Map>());
        expect(u['matched'], isFalse); // only gaps are exported
      }

      // The account holder's name and raw values from the dataset must not
      // appear anywhere in the serialized export.
      final serialized = jsonEncode(doc);
      for (final leak in [
        'Dechasa', 'Teshome', 'Gemechu', 'Abdurezak', 'Tirhas', // names
        '6843', '420.00', 'hfHCxz', // account tail, amount, receipt token
      ]) {
        expect(serialized, isNot(contains(leak)),
            reason: 'raw value "$leak" leaked into the export');
      }
    });
  });
}
