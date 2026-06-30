import 'package:sms_pattern_lab/normalizer/normalizer.dart';
import 'package:test/test.dart';

void main() {
  final n = Normalizer();

  test('collapses amounts and accounts into placeholders', () {
    final a =
        n.normalize('Transferred ETB 500 to account 100234567890 on success');
    final b = n.normalize(
        'Transferred ETB 1,250.75 to account 999888777666 on success');
    expect(a, equals(b));
    expect(a, contains('<AMOUNT>'));
    expect(a, contains('<ACCOUNT>'));
  });

  test('two messages that differ only in variable data share a template', () {
    final t1 = n.normalize(
        'Account 1*****3456 has been credited with ETB 5,000.00 Balance is ETB 12,340.55');
    final t2 = n.normalize(
        'Account 2*****9999 has been credited with ETB 10.00 Balance is ETB 1.00');
    expect(t1, equals(t2));
  });

  test('normalizes dates, times, cards and phones', () {
    final out = n.normalize(
        'POS ETB 350.00 at 2024-06-10 13:45 Card ****4321 from 0912345678');
    expect(out, contains('<DATE>'));
    expect(out, contains('<TIME>'));
    expect(out, contains('<CARD>'));
    expect(out, contains('<AMOUNT>'));
  });

  test('whitespace is collapsed', () {
    expect(n.normalize('a    b\n\tc'), equals('a b c'));
  });

  test('abstracts parenthesized counterparty names (so they stop fragmenting)',
      () {
    final a = n.normalize(
        'transferred ETB 420.00 to account 1**6548 (Abdurezak Mehabuba Bushira).');
    final b = n.normalize(
        'transferred ETB 170.00 to account 1**0315 (Tirhas Getachew Chaka).');
    expect(a, equals(b));
    expect(a, contains('(<NAME>)'));
  });

  test('does NOT mistake (15%) / (5%) for a name', () {
    final out = n.normalize('VAT(15%) and Disaster Recovery(5%) applied');
    expect(out, isNot(contains('<NAME>')));
  });

  test('abstracts recipient names between to/from and "on"', () {
    final a = n.normalize('You have transfered ETB 255.00 to Demis Zeleke on 2026-06-15');
    final b = n.normalize('You have transfered ETB 290.00 to Getu Gizaw on 2026-06-02');
    expect(a, equals(b));
    expect(a, contains('to <NAME> on'));
  });

  test('abstracts merchant in POS messages', () {
    final a = n.normalize('POS Purchase of ETB 350.00 at SUPERMARKET on 2024-06-10');
    final b = n.normalize('POS Purchase of ETB 1,299.99 at ELECTRONICS on 2024-06-11');
    expect(a, equals(b));
    expect(a, contains('<MERCHANT>'));
  });
}
