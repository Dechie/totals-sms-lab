import 'package:sms_pattern_lab/models/template_cluster.dart';
import 'package:sms_pattern_lab/models/template_family.dart';
import 'package:sms_pattern_lab/similarity/semantic_verb_grouper.dart';
import 'package:test/test.dart';

TemplateCluster c(String template, int occ, {int? bankId}) =>
    TemplateCluster(template: template, occurrences: occ, likelyBankId: bankId);

TemplateFamily familyWith(List<TemplateFamily> fs, String needle) =>
    fs.firstWhere((f) => f.template.contains(needle));

void main() {
  final grouper = SemanticVerbGrouper();

  test('merges wording variants of the same verb into one family', () {
    final families = grouper.group([
      c('Transferred <AMOUNT> to <NAME>', 5, bankId: 1),
      c('Transfer of <AMOUNT> to <NAME>', 3, bankId: 1),
    ]);
    expect(families, hasLength(1));
    final f = families.single;
    expect(f.memberCount, equals(2));
    expect(f.totalOccurrences, equals(8));
    expect(f.actionVerb, equals('transfer'));
    expect(f.direction, equals(TxDirection.outgoing));
    expect(f.label, equals('Outgoing transfers'));
  });

  test('does NOT merge different verbs', () {
    final families = grouper.group([
      c('Transferred <AMOUNT>', 5, bankId: 1),
      c('credited with <AMOUNT>', 4, bankId: 1),
    ]);
    expect(families, hasLength(2));
    expect(families.map((f) => f.actionVerb).toSet(),
        equals({'transfer', 'credit'}));
  });

  test('never merges across banks even for the same verb', () {
    final families = grouper.group([
      c('Transferred <AMOUNT>', 5, bankId: 1),
      c('Transferred <AMOUNT>', 2, bankId: 2),
    ]);
    expect(families, hasLength(2));
    expect(families.every((f) => f.memberCount == 1), isTrue);
  });

  test('null-verb clusters stay singletons (never lumped together)', () {
    final families = grouper.group([
      c('Your OTP is <NUM>', 3, bankId: 1),
      c('Verification code <NUM>', 2, bankId: 1),
    ]);
    expect(families, hasLength(2));
    expect(families.every((f) => f.memberCount == 1), isTrue);
    expect(families.every((f) => f.actionVerb == null), isTrue);
    expect(families.every((f) => f.label == null), isTrue);
  });

  test('labels incoming and neutral families', () {
    final fs = grouper.group([
      c('credited with <AMOUNT>', 4, bankId: 1),
      c('Transaction has occurred', 2, bankId: 1),
    ]);
    expect(familyWith(fs, 'credited').label, equals('Incoming credits'));
    // "occurred"/"transaction" are neutral → capitalized noun, no direction word.
    final neutral = familyWith(fs, 'Transaction');
    expect(neutral.direction, equals(TxDirection.neutral));
    expect(neutral.label, isNot(startsWith('Outgoing')));
    expect(neutral.label, isNot(startsWith('Incoming')));
  });

  test('partitions clusters — no occurrences created or lost', () {
    final clusters = [
      c('Transferred <AMOUNT>', 5, bankId: 1),
      c('Transfer of <AMOUNT>', 3, bankId: 1),
      c('credited <AMOUNT>', 4, bankId: 1),
      c('Your OTP is <NUM>', 2, bankId: 1),
    ];
    final total = clusters.fold<int>(0, (s, x) => s + x.occurrences);
    final families = grouper.group(clusters);
    final memberCount =
        families.fold<int>(0, (s, f) => s + f.memberCount);
    final famTotal =
        families.fold<int>(0, (s, f) => s + f.totalOccurrences);
    expect(memberCount, equals(clusters.length));
    expect(famTotal, equals(total));
  });
}
