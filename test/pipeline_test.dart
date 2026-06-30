import 'dart:io';

import 'package:sms_pattern_lab/analysis/analysis_pipeline.dart';
import 'package:sms_pattern_lab/parser_adapter/totals_parser_adapter.dart';
import 'package:sms_pattern_lab/utils/dataset_loader.dart';
import 'package:test/test.dart';

void main() {
  // Resolve Totals assets relative to this package (../totals/app/assets).
  final adapter = TotalsParserAdapter.autodiscover();

  test('Totals assets are discoverable from the repo', () {
    expect(adapter, isNotNull,
        reason: 'Expected to find ../totals/app/assets/{banks,sms_patterns}.json');
    expect(adapter!.bankCount, greaterThan(0));
    expect(adapter.patternCount, greaterThan(0));
  });

  test('pipeline runs end-to-end on the sample dataset', () {
    if (adapter == null) return; // covered by the assertion above
    final sample = File('example/sample_sms.json');
    expect(sample.existsSync(), isTrue);

    final messages = DatasetLoader.load(sample.path);
    expect(messages, isNotEmpty);

    final result = AnalysisPipeline(adapter: adapter).run(messages);

    // Coverage counts EVERY message (noise is separated downstream, not dropped).
    expect(result.coverage.total, equals(messages.length));
    expect(result.coverage.matched + result.coverage.unmatched,
        equals(messages.length));

    // The deliberate "Salary credited" Dashen messages should be unmatched and
    // collapse into a single template cluster with >1 occurrence.
    final salaryCluster = result.coverage.unmatchedClusters
        .where((c) => c.template.toLowerCase().contains('salary'))
        .toList();
    expect(salaryCluster, isNotEmpty,
        reason: 'Expected an unmatched Salary template family');
    expect(salaryCluster.first.occurrences, greaterThan(1));
  });

  test('coverage percentage is within 0..100', () {
    if (adapter == null) return;
    final messages = DatasetLoader.load('example/sample_sms.json');
    final result = AnalysisPipeline(adapter: adapter).run(messages);
    expect(result.coverage.overallCoveragePercent, inInclusiveRange(0, 100));
  });

  test('unknown-sender transaction → candidate; non-transaction → noise; '
      'coverage counts both', () {
    if (adapter == null) return;
    // sample_sms.json has two unknown-sender messages: a "Hibret Bank" receipt
    // (transaction) and a "verification code" (noise).
    final messages = DatasetLoader.load('example/sample_sms.json');
    final cov = AnalysisPipeline(adapter: adapter).run(messages).coverage;

    bool isOtp(c) => c.template.toLowerCase().contains('verification code');
    bool isReceipt(c) => c.template.toLowerCase().contains('received');

    // The transaction from an unrecognized sender is a candidate (not noise).
    expect(cov.candidateNewFormats.any(isReceipt), isTrue);
    expect(cov.candidateNewFormats.every((c) => c.likelyBankId == null), isTrue);

    // The verification code is classified as noise, kept out of candidates...
    expect(cov.candidateNewFormats.any(isOtp), isFalse);
    expect(cov.noiseClusters.any(isOtp), isTrue);

    // ...but coverage still counted it (it's in the full unmatched set), and
    // candidates + noise partition the unattributed clusters.
    expect(cov.unmatchedClusters.any(isOtp), isTrue);
    expect(cov.attributedClusters.length +
            cov.candidateNewFormats.length +
            cov.noiseClusters.length,
        equals(cov.unmatchedClusters.length));
  });
}
