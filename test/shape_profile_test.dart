import 'package:sms_pattern_lab/annotation/shape_profile.dart';
import 'package:test/test.dart';

void main() {
  group('ShapeProfiler.profile', () {
    test('unions same-structure samples into one quantified regex', () {
      // All plain digit runs of length 3..4 → one \d{3,4}.
      final s = ShapeProfiler.profile(['500', '250', '1000']);
      expect(s.regex, equals(r'\d{3,4}'));
      expect(s.samples, equals(3));
    });

    test('preserves internal separators as literals', () {
      final s = ShapeProfiler.profile(['1,234.56', '2,000.00', '9,999.99']);
      expect(s.regex, equals(r'\d,\d{3}\.\d{2}'));
    });

    test('generalizes masked account shapes', () {
      final s = ShapeProfiler.profile(['1****6843', '1**6843', '2***0315']);
      expect(s.regex, equals(r'\d\*{2,4}\d{4}'));
    });

    test('emits an alternation for a few distinct structures', () {
      final s = ShapeProfiler.profile(['500', '12,000.00', '9.99']);
      // 3 distinct structures ≤ maxAlternatives → alternation, sorted.
      expect(s.regex, startsWith('(?:'));
      expect(s.regex, contains('|'));
      expect(s.samples, equals(3));
    });

    test('too few distinct samples → coarse class (never a fingerprint)', () {
      final s = ShapeProfiler.profile(['FT26174513JK']);
      expect(s.regex, endsWith('+'));
      expect(s.regex, startsWith('['));
      // The raw value never appears in the shape.
      expect(s.regex, isNot(contains('FT26174513JK')));
      expect(s.samples, equals(1));
    });

    test('too many distinct structures → coarse bounded class', () {
      final s = ShapeProfiler.profile(
          ['a1', 'bb22', 'c3c3', 'd-4', 'e.5.', 'ffff']);
      expect(s.regex, startsWith('['));
      expect(s.regex, matches(RegExp(r'\{\d+,\d+\}$'))); // bounded quantifier
    });

    test('never emits raw digits or letters from the values', () {
      final s = ShapeProfiler.profile(['1,234.56', '7,654.32', '1,111.11']);
      for (final bad in ['234', '654', '111', '1,234.56']) {
        expect(s.regex, isNot(contains(bad)));
      }
    });

    test('profileAll skips empty fields and orders keys deterministically', () {
      final out = ShapeProfiler.profileAll({
        'NUM': ['1', '2', '3'],
        'AMOUNT': ['10', '20', '30'],
        'EMPTY': <String>[],
      });
      expect(out.keys.toList(), equals(['AMOUNT', 'NUM']));
    });
  });
}
