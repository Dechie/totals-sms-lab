import 'package:sms_pattern_lab/sources/adb_sms_source.dart';
import 'package:test/test.dart';

void main() {
  group('AdbSmsSource.parseContentQuery', () {
    test('parses simple rows', () {
      const out = '''
Row: 0 address=CBE, date=1719000000000, body=Dear Mr Dechasa your Account 1****6843 has been credited with ETB 201.15.
Row: 1 address=127, date=1719000100000, body=You have received ETB 200.00 from 0912345678.
''';
      final msgs = AdbSmsSource.parseContentQuery(out);
      expect(msgs, hasLength(2));
      expect(msgs[0].address, equals('CBE'));
      expect(msgs[0].dateMillis, equals(1719000000000));
      expect(msgs[0].body, contains('credited with ETB 201.15'));
      expect(msgs[1].address, equals('127'));
    });

    test('body containing commas is captured whole (body is last column)', () {
      const out =
          'Row: 0 address=CBE, date=1, body=transferred ETB 420.61, total of ETB420.61, balance is ETB14,679.67';
      final msgs = AdbSmsSource.parseContentQuery(out);
      expect(msgs, hasLength(1));
      expect(msgs[0].body, contains('balance is ETB14,679.67'));
      expect(msgs[0].body, startsWith('transferred ETB 420.61'));
    });

    test('handles null address', () {
      const out = 'Row: 0 address=null, date=1, body=System message';
      final msgs = AdbSmsSource.parseContentQuery(out);
      expect(msgs.single.address, isNull);
      expect(msgs.single.body, equals('System message'));
    });

    test('skips empty bodies and blank output', () {
      expect(AdbSmsSource.parseContentQuery(''), isEmpty);
      expect(AdbSmsSource.parseContentQuery('No result found.'), isEmpty);
    });
  });
}
