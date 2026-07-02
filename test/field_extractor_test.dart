import 'package:sms_pattern_lab/models/bank.dart';
import 'package:sms_pattern_lab/models/sms_pattern.dart';
import 'package:sms_pattern_lab/parser_adapter/field_extractor.dart';
import 'package:test/test.dart';

/// Compile [regex], match it against [body], and run the field extractor +
/// accept-gate exactly as the adapter would.
ExtractionOutcome run(
  String regex,
  String body, {
  String type = 'CREDIT',
  bool? refRequired,
  bool? hasAccount,
  bool? hasFees,
  Bank? bank,
}) {
  final p = SmsPattern(
    bankId: 1,
    senderId: 'X',
    regex: regex,
    type: type,
    refRequired: refRequired,
    hasAccount: hasAccount,
    hasFees: hasFees,
  );
  final m = p.regExp!.firstMatch(body);
  expect(m, isNotNull, reason: 'regex should match the sample body');
  return FieldExtractor.extract(match: m!, body: body, pattern: p, bank: bank);
}

void main() {
  group('accept-gate (mirrors pattern_parser.dart:170-190)', () {
    test('accepts a complete CREDIT with amount, balance, reference', () {
      final o = run(
        r'credited\s+ETB\s+(?<amount>[\d,.]+).*?Balance is ETB\s+(?<balance>[\d,.]+).*?ref\s+(?<reference>\w+)',
        'Account credited ETB 1,000.00 on x. Balance is ETB 2,000.00. ref AB12',
        refRequired: true,
      );
      expect(o.accepted, isTrue);
      expect(o.reason, RejectReason.none);
      expect(o.typeValid, isTrue);
      expect(o.amountParsed, isTrue);
      expect(o.balanceExpected, isTrue);
      expect(o.balanceCaptured, isTrue);
      expect(o.balanceParsed, isTrue);
      expect(o.referenceReal, isTrue);
    });

    test('rejects when no amount is captured', () {
      final o = run(r'hello (?<foo>\w+)', 'hello world');
      expect(o.accepted, isFalse);
      expect(o.reason, RejectReason.amountMissing);
      expect(o.amountParsed, isFalse);
    });

    test('rejects when a balance group is present but did not capture', () {
      final o = run(r'amt (?<amount>\d+)(?: bal (?<balance>\d+))?', 'amt 100');
      expect(o.balanceExpected, isTrue);
      expect(o.balanceCaptured, isFalse);
      expect(o.accepted, isFalse);
      expect(o.reason, RejectReason.balanceMissing);
    });

    test('rejects when refRequired but no reference captured or synthesized', () {
      final o = run(r'amt (?<amount>\d+)', 'amt 100', refRequired: true);
      expect(o.referenceReal, isFalse);
      expect(o.referenceSynthesized, isFalse);
      expect(o.accepted, isFalse);
      expect(o.reason, RejectReason.refMissing);
    });

    test('rejects when hasAccount but the account group did not capture', () {
      final o = run(
        r'amt (?<amount>\d+)(?: acct (?<account>\d+))?',
        'amt 100',
        hasAccount: true,
      );
      expect(o.accountExpected, isTrue);
      expect(o.accountCaptured, isFalse);
      expect(o.accepted, isFalse);
      expect(o.reason, RejectReason.accountMissing);
    });
  });

  group('field signals', () {
    test('synthesizes a reference when refRequired is false', () {
      final o = run(r'amt (?<amount>\d+)', 'amt 100', refRequired: false);
      expect(o.accepted, isTrue);
      expect(o.referenceReal, isFalse);
      expect(o.referenceSynthesized, isTrue);
    });

    test('typeValid is false for a non-CREDIT/DEBIT pattern type', () {
      // The corruption vector: matched + accepted, but excluded from both sums.
      final o = run(r'amt (?<amount>\d+)', 'amt 100', type: 'credit');
      expect(o.accepted, isTrue);
      expect(o.typeValid, isFalse);
    });

    test('a type group is normalized to uppercase CREDIT/DEBIT', () {
      final o = run(
        r'(?<type>debit|credit)ed (?<amount>\d+)',
        'credited 100',
        type: 'IGNORED',
      );
      expect(o.typeValid, isTrue);
    });

    test('counterparty from a named group is detected', () {
      final o = run(r'(?<amount>\d+) from (?<sender>\w+)', '100 from Abebe');
      expect(o.counterpartyCaptured, isTrue);
    });

    test('counterparty falls back to the body for CREDIT', () {
      final o = run(
        r'received (?<amount>\d+)',
        'received 100 from Abebe Kebede on 2024',
        type: 'CREDIT',
      );
      expect(o.counterpartyCaptured, isTrue);
    });

    test('feesCaptured reflects extracted serviceCharge/vat', () {
      final captured = run(
        r'debited (?<amount>\d+).*?charge (?<serviceCharge>\d+)',
        'debited 100 charge 5',
        type: 'DEBIT',
        hasFees: true,
      );
      expect(captured.feesExpected, isTrue);
      expect(captured.feesCaptured, isTrue);

      final missing = run(r'debited (?<amount>\d+)', 'debited 100',
          type: 'DEBIT', hasFees: true);
      expect(missing.feesExpected, isTrue);
      expect(missing.feesCaptured, isFalse);
    });
  });

  group('_cleanNumber parity', () {
    test('comma-grouped amount parses', () {
      final o = run(r'(?<amount>[\d,.]+)', '1,234.56');
      expect(o.amountParsed, isTrue);
    });

    test('trailing dot is stripped and still parses', () {
      final o = run(r'(?<amount>[\d.]+)', '100.');
      expect(o.amountParsed, isTrue);
    });

    test('a short account (shorter than mask) is still captured', () {
      final bank = Bank(
        id: 1,
        name: 'CBE',
        shortName: 'CBE',
        codes: const ['CBE'],
        maskPattern: 4,
        uniformMasking: true,
      );
      final o = run(
        r'amt (?<amount>\d+) acct (?<account>\d+)',
        'amt 100 acct 12',
        hasAccount: true,
        bank: bank,
      );
      expect(o.accountCaptured, isTrue);
      expect(o.accepted, isTrue);
    });
  });
}
