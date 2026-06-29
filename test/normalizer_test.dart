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
}
