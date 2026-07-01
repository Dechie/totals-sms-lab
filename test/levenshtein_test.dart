import 'package:sms_pattern_lab/similarity/levenshtein.dart';
import 'package:test/test.dart';

void main() {
  group('levenshteinDistance', () {
    test('known vectors', () {
      expect(levenshteinDistance('kitten', 'sitting'), equals(3));
      expect(levenshteinDistance('flaw', 'lawn'), equals(2));
      expect(levenshteinDistance('', 'abc'), equals(3));
      expect(levenshteinDistance('abc', ''), equals(3));
      expect(levenshteinDistance('same', 'same'), equals(0));
    });

    test('symmetric in its arguments', () {
      expect(levenshteinDistance('Transferred', 'Transfered'),
          equals(levenshteinDistance('Transfered', 'Transferred')));
      // one deletion
      expect(levenshteinDistance('Transferred', 'Transfered'), equals(1));
    });
  });

  group('similarityRatio', () {
    test('1.0 for equal strings (including both empty)', () {
      expect(similarityRatio('abc', 'abc'), equals(1.0));
      expect(similarityRatio('', ''), equals(1.0));
    });

    test('scales by max length, in [0,1]', () {
      // 1 edit over max length 11 → ~0.909.
      expect(similarityRatio('Transferred', 'Transfered'),
          closeTo(1 - 1 / 11, 1e-9));
      expect(similarityRatio('abc', 'xyz'), equals(0.0));
      expect(similarityRatio('a', ''), equals(0.0));
    });
  });
}
