import 'package:sms_pattern_lab/models/template_cluster.dart';
import 'package:sms_pattern_lab/models/template_family.dart';
import 'package:sms_pattern_lab/similarity/levenshtein_grouper.dart';
import 'package:sms_pattern_lab/similarity/semantic_verb_grouper.dart';
import 'package:test/test.dart';

TemplateCluster c(String template, int occ, {int? bankId}) =>
    TemplateCluster(template: template, occurrences: occ, likelyBankId: bankId);

int members(List<TemplateFamily> fs) => fs.fold(0, (s, f) => s + f.memberCount);

void main() {
  group('LevenshteinGrouper (standalone)', () {
    final g = LevenshteinGrouper(); // threshold 0.9

    test('merges near-identical wording, keeps distinct shapes apart', () {
      final fs = g.group([
        c('Account credited with <AMOUNT> balance <AMOUNT>', 5, bankId: 1),
        c('Account credited with <AMOUNT> balances <AMOUNT>', 3, bankId: 1),
        c('Your verification code is <NUM> do not share it', 4, bankId: 1),
      ]);
      expect(fs, hasLength(2));
      // The two near-identical templates merge; the OTP stays separate.
      final merged = fs.firstWhere((f) => f.memberCount > 1);
      expect(merged.memberCount, equals(2));
      expect(merged.representative.occurrences, equals(5)); // highest-occ seed
      expect(members(fs), equals(3)); // partition — nothing lost
    });

    test('never merges across banks even for identical templates', () {
      final fs = g.group([
        c('Account credited with <AMOUNT>', 5, bankId: 1),
        c('Account credited with <AMOUNT>', 2, bankId: 2),
      ]);
      expect(fs, hasLength(2));
      expect(fs.every((f) => f.memberCount == 1), isTrue);
    });

    test('threshold governs merging (1.0 requires exact wording)', () {
      final clusters = [
        c('Account credited with <AMOUNT> balance <AMOUNT>', 5, bankId: 1),
        c('Account credited with <AMOUNT> balances <AMOUNT>', 3, bankId: 1),
      ];
      expect(LevenshteinGrouper(threshold: 1.0).group(clusters), hasLength(2));
      expect(LevenshteinGrouper(threshold: 0.9).group(clusters), hasLength(1));
    });

    test('is deterministic regardless of input order', () {
      final a = c('Account credited with <AMOUNT> balance <AMOUNT>', 5,
          bankId: 1);
      final b = c('Account credited with <AMOUNT> balances <AMOUNT>', 3,
          bankId: 1);
      final one = g.group([a, b]);
      final two = g.group([b, a]);
      expect(one.single.representative.template,
          equals(two.single.representative.template));
    });
  });

  group('SemanticVerbGrouper + LevenshteinGrouper (V2 step 2 composite)', () {
    final composite =
        SemanticVerbGrouper(within: LevenshteinGrouper(threshold: 0.9));

    final near1 =
        c('You transferred <AMOUNT> to <NAME> successfully', 5, bankId: 1);
    final near2 =
        c('You transferred <AMOUNT> to <NAME> successfuly', 3, bankId: 1);
    final farTransfer = c(
        'Transfer of <AMOUNT> was declined by the recipient bank, please '
        'contact support',
        2,
        bankId: 1);

    test('refines a verb bucket: near-identical merge, far wording splits', () {
      final fs = composite.group([near1, near2, farTransfer]);
      // Same verb bucket ("transfer") → two wording sub-families.
      expect(fs, hasLength(2));
      expect(fs.every((f) => f.label == 'Outgoing transfers'), isTrue);
      expect(fs.map((f) => f.memberCount).toList()..sort(), equals([1, 2]));
      expect(members(fs), equals(3));
    });

    test('coarser verb-only grouping keeps the whole bucket as one family', () {
      final fs = SemanticVerbGrouper().group([near1, near2, farTransfer]);
      expect(fs, hasLength(1));
      expect(fs.single.memberCount, equals(3));
      expect(fs.single.label, equals('Outgoing transfers'));
    });

    test('still never merges different verbs', () {
      final fs = composite.group([
        near1,
        c('Account credited with <AMOUNT>', 4, bankId: 1),
      ]);
      expect(fs, hasLength(2));
      expect(fs.map((f) => f.actionVerb).toSet(),
          equals({'transfer', 'credit'}));
    });
  });
}
