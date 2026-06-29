import 'package:sms_pattern_lab/baseline/baseline_diff.dart';
import 'package:sms_pattern_lab/baseline/parser_baseline.dart';
import 'package:sms_pattern_lab/models/sms_pattern.dart';
import 'package:test/test.dart';

SmsPattern _p(int bankId, String desc, String regex, [String type = 'DEBIT']) =>
    SmsPattern(
        bankId: bankId,
        senderId: 'X',
        regex: regex,
        type: type,
        description: desc);

ParserBaseline _baseline(List<SmsPattern> patterns) =>
    ParserBaseline.from(patterns, bankCount: 2);

void main() {
  group('fnv1a64', () {
    test('is deterministic and a positive 16-char hex string', () {
      final a = fnv1a64('hello world');
      final b = fnv1a64('hello world');
      expect(a, equals(b));
      expect(a, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('differs for different input', () {
      expect(fnv1a64('a'), isNot(equals(fnv1a64('b'))));
    });
  });

  group('ParserBaseline.signature', () {
    test('is independent of pattern ordering', () {
      final p1 = _p(1, 'credit', r'credited with ETB (?<amount>\d+)');
      final p2 = _p(2, 'debit', r'debited with ETB (?<amount>\d+)');
      expect(_baseline([p1, p2]).signature,
          equals(_baseline([p2, p1]).signature));
    });

    test('changes when a regex changes', () {
      final base = _baseline([_p(1, 'credit', r'credited (?<amount>\d+)')]);
      final edited = _baseline([_p(1, 'credit', r'credited ETB (?<amount>\d+)')]);
      expect(base.signature, isNot(equals(edited.signature)));
    });

    test('counts patterns per bank', () {
      final b = _baseline([
        _p(1, 'a', 'x'),
        _p(1, 'b', 'y'),
        _p(2, 'c', 'z'),
      ]);
      expect(b.patternsPerBank(), equals({1: 2, 2: 1}));
    });
  });

  group('BaselineDiff', () {
    test('detects an added pattern (the app gained a regex)', () {
      final current = _baseline([_p(1, 'credit', 'A')]);
      final source = _baseline([_p(1, 'credit', 'A'), _p(1, 'new debit', 'B')]);
      final diff = BaselineDiff.compare(current, source);
      expect(diff.isDirty, isTrue);
      expect(diff.added, hasLength(1));
      expect(diff.added.single.description, equals('new debit'));
      expect(diff.removed, isEmpty);
      expect(diff.changed, isEmpty);
    });

    test('detects a removed pattern', () {
      final current = _baseline([_p(1, 'credit', 'A'), _p(1, 'old', 'B')]);
      final source = _baseline([_p(1, 'credit', 'A')]);
      final diff = BaselineDiff.compare(current, source);
      expect(diff.removed, hasLength(1));
      expect(diff.removed.single.description, equals('old'));
    });

    test('detects a changed regex under the same identity', () {
      final current = _baseline([_p(1, 'credit', 'OLD')]);
      final source = _baseline([_p(1, 'credit', 'NEW')]);
      final diff = BaselineDiff.compare(current, source);
      expect(diff.added, isEmpty);
      expect(diff.removed, isEmpty);
      expect(diff.changed, hasLength(1));
      expect(diff.changed.single.oldRegexes, equals(['OLD']));
      expect(diff.changed.single.newRegexes, equals(['NEW']));
    });

    test('identical baselines are not dirty', () {
      final a = _baseline([_p(1, 'credit', 'A'), _p(2, 'debit', 'B')]);
      final b = _baseline([_p(2, 'debit', 'B'), _p(1, 'credit', 'A')]);
      expect(BaselineDiff.compare(a, b).isDirty, isFalse);
    });
  });
}
