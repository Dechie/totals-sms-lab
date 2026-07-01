import 'package:sms_pattern_lab/models/template_cluster.dart';
import 'package:sms_pattern_lab/models/template_family.dart';
import 'package:sms_pattern_lab/similarity/similarity_grouper.dart';
import 'package:test/test.dart';

TemplateCluster c(String template, int occ, {int? bankId, List<String>? ex}) =>
    TemplateCluster(
        template: template, occurrences: occ, likelyBankId: bankId, examples: ex);

void main() {
  group('TemplateFamily', () {
    test('single member behaves like the underlying cluster', () {
      final f = TemplateFamily([c('A <AMOUNT> B credited to account', 4)]);
      expect(f.memberCount, equals(1));
      expect(f.totalOccurrences, equals(4));
      expect(f.template, equals('A <AMOUNT> B credited to account'));
      expect(f.variantTemplates, isEmpty);
    });

    test('aggregates occurrences and picks highest-occurrence representative',
        () {
      final f = TemplateFamily([
        c('minor variant', 3),
        c('the common one', 10),
        c('another', 2),
      ]);
      expect(f.representative.template, equals('the common one'));
      expect(f.totalOccurrences, equals(15));
      expect(f.memberCount, equals(3));
      expect(f.variantTemplates, containsAll(['minor variant', 'another']));
    });

    test('priority buckets on the family total, not a single member', () {
      // Five ×1 fragments individually rank "Very Low"; as a family (×5) → "Low".
      final fragments = [for (var i = 0; i < 5; i++) c('shape v$i', 1)];
      final f = TemplateFamily(fragments);
      expect(f.totalOccurrences, equals(5));
      expect(f.priority, equals('Low'));
      expect(fragments.first.priority, equals('Very Low'));
    });

    test('merges examples across members (deduped, capped)', () {
      final f = TemplateFamily([
        c('x', 2, ex: ['e1', 'e2']),
        c('y', 1, ex: ['e2', 'e3']),
      ]);
      expect(f.examples(), equals(['e1', 'e2', 'e3'])); // e2 deduped
    });
  });

  group('IdentityGrouper', () {
    test('produces exactly one family per cluster (V1 behavior)', () {
      final clusters = [c('a', 1), c('b', 2), c('c', 3)];
      final families = IdentityGrouper().group(clusters);
      expect(families, hasLength(3));
      expect(families.every((f) => f.memberCount == 1), isTrue);
    });
  });
}
