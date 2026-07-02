import 'package:sms_pattern_lab/models/extraction_health.dart';
import 'package:sms_pattern_lab/models/success_family.dart';
import 'package:sms_pattern_lab/models/template_cluster.dart';
import 'package:sms_pattern_lab/models/template_family.dart';
import 'package:sms_pattern_lab/parser_adapter/field_extractor.dart';
import 'package:test/test.dart';

ExtractionHealth health({
  required int members,
  int? appAccepted,
  int? typeValid,
  int balanceExpected = 0,
  int balanceCaptured = 0,
  int? balanceParsed,
  int? counterparty,
  int? refReal,
  int refSynthesized = 0,
  int accountExpected = 0,
  int accountCaptured = 0,
  int feesExpected = 0,
  int feesCaptured = 0,
  Map<String, int> patternDescriptions = const {},
}) =>
    ExtractionHealth(
      members: members,
      appAccepted: appAccepted ?? members,
      typeValid: typeValid ?? members,
      amountParsed: members,
      balanceExpected: balanceExpected,
      balanceCaptured: balanceCaptured,
      balanceParsed: balanceParsed ?? balanceCaptured,
      counterparty: counterparty ?? members,
      refReal: refReal ?? members,
      refSynthesized: refSynthesized,
      accountExpected: accountExpected,
      accountCaptured: accountCaptured,
      feesExpected: feesExpected,
      feesCaptured: feesCaptured,
      patternDescriptions: patternDescriptions,
    );

void main() {
  group('healthScore (totals-impact weighted)', () {
    test('a fully-captured accepted family scores 100', () {
      final h = health(
        members: 4,
        balanceExpected: 4,
        balanceCaptured: 4,
        balanceParsed: 4,
      );
      expect(h.healthScore, equals(100));
    });

    test('a rejected family (nothing accepted) scores 0', () {
      final h = health(members: 4, appAccepted: 0);
      expect(h.healthScore, equals(0));
    });

    test('a balance-less pattern caps at 75', () {
      // type(30)+counterparty(20)+ref(12)+account(8)+fees(5) = 75; balance = 0.
      final h = health(members: 4); // no balance group at all
      expect(h.healthScore, equals(75));
    });

    test('an expected-but-uncaptured account loses its 8 points', () {
      final h = health(
        members: 4,
        balanceExpected: 4,
        balanceCaptured: 4,
        accountExpected: 4,
        accountCaptured: 0,
      );
      // 100 - 8 (account) = 92.
      expect(h.healthScore, equals(92));
    });

    test('a wrong-type family loses its 30 points', () {
      final h = health(
        members: 4,
        typeValid: 0,
        balanceExpected: 4,
        balanceCaptured: 4,
      );
      expect(h.healthScore, equals(70));
    });
  });

  group('merge', () {
    test('sums counts and merges pattern descriptions', () {
      final a = health(members: 2, patternDescriptions: const {'P': 2});
      final b = health(members: 3, patternDescriptions: const {'P': 1, 'Q': 3});
      final m = a.merge(b);
      expect(m.members, equals(5));
      expect(m.typeValid, equals(5));
      expect(m.patternDescriptions, equals({'P': 3, 'Q': 3}));
    });

    test('fromOutcome counts a single message', () {
      const accepted = ExtractionOutcome(
        accepted: true,
        reason: RejectReason.none,
        typeValid: true,
        amountParsed: true,
        balanceExpected: false,
        balanceCaptured: false,
        balanceParsed: false,
        counterpartyCaptured: true,
        referenceReal: true,
        referenceSynthesized: false,
        accountExpected: false,
        accountCaptured: false,
        feesExpected: false,
        feesCaptured: false,
      );
      final h = ExtractionHealth.fromOutcome(accepted, patternDescription: 'P');
      expect(h.members, equals(1));
      expect(h.appAccepted, equals(1));
      expect(h.typeValid, equals(1));
      expect(h.patternDescriptions, equals({'P': 1}));
    });
  });

  group('SuccessFamily.fromFamily', () {
    TemplateCluster clusterWith(ExtractionHealth h, {int occurrences = 1}) =>
        TemplateCluster(
          template: 'credited <AMOUNT>',
          occurrences: occurrences,
          likelyBankName: 'CBE',
          health: h,
        );

    test('folds member cluster health and reports appAccepted only if all pass', () {
      final family = TemplateFamily([
        clusterWith(health(members: 2), occurrences: 2),
        clusterWith(health(members: 1, appAccepted: 0), occurrences: 1),
      ]);
      final sf = SuccessFamily.fromFamily(family);
      expect(sf.count, equals(3));
      expect(sf.health.members, equals(3));
      expect(sf.appAccepted, isFalse); // one member was rejected
    });

    test('appAccepted is true when every member passed', () {
      final sf = SuccessFamily.fromFamily(
        TemplateFamily([clusterWith(health(members: 3), occurrences: 3)]),
      );
      expect(sf.appAccepted, isTrue);
      expect(sf.likelyBankName, equals('CBE'));
    });
  });
}
