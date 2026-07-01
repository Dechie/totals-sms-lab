import 'package:sms_pattern_lab/normalizer/normalizer.dart';
import 'package:test/test.dart';

void main() {
  final n = Normalizer();

  test('captures the raw span each placeholder replaced, keyed by field', () {
    final r = n.normalizeWithSpans(
        'Dear Mr Dechasa transferred ETB 500 to account 100234567890 on 2024-01-31');
    expect(r.spans['AMOUNT'], contains('ETB 500'));
    expect(r.spans['ACCOUNT'], contains('100234567890'));
    expect(r.spans['DATE'], contains('2024-01-31'));
    // Greeting name is stripped and captured (privacy) — never left in text.
    expect(r.spans['NAME'], contains('Mr Dechasa'));
  });

  test('template is byte-identical to normalize()', () {
    const body =
        'Dear Customer your Account 1****6843 has been credited with ETB 5,000.00';
    expect(n.normalizeWithSpans(body).template, equals(n.normalize(body)));
  });

  test('greeting name never survives into the template', () {
    final t = n.normalize(
        'Dear Dechasa Teshome Gemechu You have successfully transferred ETB420.00');
    expect(t, isNot(contains('Dechasa')));
    expect(t, isNot(contains('Teshome')));
    expect(t, startsWith('Dear <NAME>'));
  });

  test('no-placeholder body yields an empty span map', () {
    final r = n.normalizeWithSpans('Thank you for banking with us');
    expect(r.spans, isEmpty);
  });
}
