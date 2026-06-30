import 'dart:io';

import 'package:sms_pattern_lab/baseline/logic_fidelity.dart';
import 'package:test/test.dart';

/// Write a minimal fake app source tree containing the probe anchors.
Directory _fakeApp({String cleanReturn = 'return text.trim();'}) {
  final dir = Directory.systemTemp.createTempSync('spl_fidelity');
  File('${dir.path}/lib/utils/pattern_parser.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
class PatternParser {
  static void x() {
    RegExp(pattern.regex, caseSensitive: false, multiLine: true, dotAll: true);
  }
}
''');
  File('${dir.path}/lib/services/sms_config_service.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
class SmsConfigService {
  String cleanSmsText(String text) {
    $cleanReturn
  }
}
''');
  File('${dir.path}/lib/services/sms_service.dart')
    ..createSync(recursive: true)
    ..writeAsStringSync('''
class SmsService {
  static String _normalizeSenderToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
  static bool _addressMatchesCode(String a, String c) {
    return a.contains(c);
  }
  static bool _looksLikeTransactionMessage(String messageBody) {
    return messageBody.contains('debited');
  }
}
''');
  return dir;
}

void main() {
  test('computes a signature with all probes found', () {
    final dir = _fakeApp();
    try {
      final r = LogicFidelity.fromAppDir(dir.path)!;
      expect(r.allFound, isTrue);
      expect(r.signature, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(r.probeHashes.keys,
          containsAll(['regexFlags', 'cleanSmsText', 'looksLikeTransaction']));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('detects and pinpoints a logic change', () {
    final a = _fakeApp();
    final b = _fakeApp(cleanReturn: 'return text.trim().toLowerCase();');
    try {
      final ra = LogicFidelity.fromAppDir(a.path)!;
      final rb = LogicFidelity.fromAppDir(b.path)!;
      expect(rb.signature, isNot(equals(ra.signature)));
      expect(rb.driftedAgainst(ra.probeHashes), equals(['cleanSmsText']));
    } finally {
      a.deleteSync(recursive: true);
      b.deleteSync(recursive: true);
    }
  });

  test('a missing anchor is flagged (not silently ignored)', () {
    final dir = Directory.systemTemp.createTempSync('spl_fidelity_empty');
    File('${dir.path}/lib/utils/pattern_parser.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('class X {}'); // no anchors
    try {
      final r = LogicFidelity.fromAppDir(dir.path)!;
      expect(r.allFound, isFalse);
      expect(r.probeHashes['regexFlags'], equals(kMissingProbe));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('returns null when no probe files exist (not an app dir)', () {
    final dir = Directory.systemTemp.createTempSync('spl_notapp');
    try {
      expect(LogicFidelity.fromAppDir(dir.path), isNull);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
