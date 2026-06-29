import 'dart:io';

import 'package:sms_pattern_lab/baseline/baseline_history.dart';
import 'package:test/test.dart';

BaselineRecord _rec(String sig, int count, {String? note}) => BaselineRecord(
      signature: sig,
      recordedAt: '2026-06-30T00:00:00.000',
      patternCount: count,
      bankCount: 10,
      note: note,
    );

void main() {
  test('record appends only when the signature changes', () {
    final h = BaselineHistory();
    expect(h.record(_rec('aaa', 95)), isTrue);
    expect(h.record(_rec('aaa', 95)), isFalse); // same head → no append
    expect(h.record(_rec('bbb', 96)), isTrue);
    expect(h.entries, hasLength(2));
    expect(h.currentSignature, equals('bbb'));
  });

  test('persists and reloads as JSON (roundtrip)', () {
    final dir = Directory.systemTemp.createTempSync('spl_hist');
    final path = '${dir.path}/history.json';
    try {
      final h = BaselineHistory()
        ..record(_rec('aaa', 95, note: 'first'))
        ..record(_rec('bbb', 96, note: 'second'));
      h.save(path);

      final reloaded = BaselineHistory.load(path);
      expect(reloaded.entries, hasLength(2));
      expect(reloaded.currentSignature, equals('bbb'));
      expect(reloaded.entries.first.note, equals('first'));
      expect(reloaded.entries.last.patternCount, equals(96));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('loading a missing file yields an empty ledger', () {
    final h = BaselineHistory.load('/nonexistent/path/history.json');
    expect(h.isEmpty, isTrue);
    expect(h.currentSignature, isNull);
  });
}
