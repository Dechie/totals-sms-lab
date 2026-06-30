import 'package:sms_pattern_lab/corpus/corpus.dart';
import 'package:sms_pattern_lab/models/sms_message.dart';
import 'package:test/test.dart';

SmsMessage m(String address, String body) =>
    SmsMessage(address: address, body: body);

void main() {
  test('dedups identical (address, body) across sources', () {
    final a = [m('CBE', 'debited ETB 10'), m('CBE', 'credited ETB 5')];
    final b = [m('CBE', 'debited ETB 10'), m('127', 'received ETB 9')];
    final r = Corpus.merge([a, b]);

    expect(r.totalInput, equals(4));
    expect(r.uniqueCount, equals(3));
    expect(r.duplicatesRemoved, equals(1));
    expect(r.perSourceCounts, equals([2, 2]));
  });

  test('same address+body but... different address is NOT a duplicate', () {
    final r = Corpus.merge([
      [m('CBE', 'x')],
      [m('BOA', 'x')],
    ]);
    expect(r.uniqueCount, equals(2));
  });

  test('datasetId is order-independent and content-sensitive', () {
    final a = [m('CBE', 'debited ETB 10')];
    final b = [m('127', 'received ETB 9')];

    final ab = Corpus.merge([a, b]).datasetId;
    final ba = Corpus.merge([b, a]).datasetId; // reordered sources
    expect(ab, equals(ba), reason: 'order must not change the id');

    final changed = Corpus.merge([
      [m('CBE', 'debited ETB 11')], // one digit different
      b,
    ]).datasetId;
    expect(changed, isNot(equals(ab)));
    expect(ab, matches(RegExp(r'^[0-9a-f]{16}$')));
  });
}
