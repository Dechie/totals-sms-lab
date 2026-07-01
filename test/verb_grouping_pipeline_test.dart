import 'package:sms_pattern_lab/analysis/analysis_pipeline.dart';
import 'package:sms_pattern_lab/models/template_family.dart';
import 'package:sms_pattern_lab/parser_adapter/totals_parser_adapter.dart';
import 'package:sms_pattern_lab/similarity/semantic_verb_grouper.dart';
import 'package:sms_pattern_lab/similarity/similarity_grouper.dart';
import 'package:sms_pattern_lab/utils/dataset_loader.dart';
import 'package:test/test.dart';

void main() {
  final adapter = TotalsParserAdapter.autodiscover();
  final messages = DatasetLoader.load('example/cbe_sms.json');

  List<TemplateFamily> attributedWith(SimilarityGrouper g) =>
      AnalysisPipeline(adapter: adapter!, grouper: g)
          .run(messages)
          .coverage
          .attributedFamilies;

  test('verb grouping labels CBE families and preserves coverage', () {
    if (adapter == null) return; // covered by pipeline_test assertion
    final result = AnalysisPipeline(
            adapter: adapter, grouper: SemanticVerbGrouper())
        .run(messages);

    // Coverage is a property of the parser, not the grouper — unchanged.
    expect(result.coverage.total, equals(messages.length));

    final families = result.coverage.attributedFamilies;
    final labels = families.map((f) => f.label).whereType<String>().toSet();
    // The two big CBE gaps carry their action verbs.
    expect(labels, contains('Outgoing transfers'));
    expect(labels, contains('Outgoing debits'));
  });

  test('grouping only partitions — occurrences are neither created nor lost',
      () {
    if (adapter == null) return;
    final identity = attributedWith(IdentityGrouper());
    final verb = attributedWith(SemanticVerbGrouper());

    int members(List<TemplateFamily> fs) =>
        fs.fold(0, (s, f) => s + f.memberCount);
    int occ(List<TemplateFamily> fs) =>
        fs.fold(0, (s, f) => s + f.totalOccurrences);

    // Same clusters, same total occurrences — verb grouping never exceeds the
    // identity family count (it only merges), and never drops a member.
    expect(members(verb), equals(members(identity)));
    expect(occ(verb), equals(occ(identity)));
    expect(verb.length, lessThanOrEqualTo(identity.length));
  });

  test('identity grouping (V1 default) attaches no labels', () {
    if (adapter == null) return;
    final identity = attributedWith(IdentityGrouper());
    expect(identity.every((f) => f.label == null), isTrue);
  });
}
