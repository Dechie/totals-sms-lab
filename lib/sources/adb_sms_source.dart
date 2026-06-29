import 'dart:io';

import '../models/sms_message.dart';

/// Pulls SMS directly from a connected Android device over `adb`, reading the
/// system SMS inbox via `content query --uri content://sms/inbox`.
///
/// This is the runtime bridge to a phone running Totals in a test session: the
/// app reads the same inbox, so analysing it tells you exactly which messages
/// the parser would (or wouldn't) handle on that device — with no change to the
/// Totals app itself.
///
/// The fragile part of `content query` is that a row's `body` may contain
/// commas and newlines. We sidestep that by requesting `body` LAST in the
/// projection and treating everything after `body=` (up to the next `Row:`
/// marker) as the message text. [parseContentQuery] is pure and unit-tested so
/// this parsing logic is verifiable without a device attached.
class AdbSmsSource {
  /// adb executable (allow override for non-PATH installs).
  final String adbPath;

  /// Optional device serial (`adb -s <serial>`), for when several are attached.
  final String? deviceSerial;

  const AdbSmsSource({this.adbPath = 'adb', this.deviceSerial});

  /// Run adb and return the parsed inbox.
  ///
  /// [senderFilter], when non-empty, keeps only messages whose address matches
  /// one of the given sender codes (case-insensitive). Pass bank codes here to
  /// scope the pull (e.g. `['CBE']`).
  List<SmsMessage> fetch({Iterable<String> senderFilter = const []}) {
    _ensureAdbAvailable();

    final args = <String>[
      if (deviceSerial != null) ...['-s', deviceSerial!],
      'shell',
      'content',
      'query',
      '--uri',
      'content://sms/inbox',
      '--projection',
      'address:date:body',
    ];

    final result = Process.runSync(adbPath, args);
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      throw AdbException(
          'adb query failed (exit ${result.exitCode})${err.isEmpty ? '' : ': $err'}');
    }

    final messages = parseContentQuery(result.stdout as String);
    if (senderFilter.isEmpty) return messages;

    final codes = senderFilter.map((c) => c.toLowerCase()).toSet();
    return messages
        .where((m) =>
            m.address != null && codes.contains(m.address!.toLowerCase()))
        .toList();
  }

  /// List attached device serials (handy for `--device` discovery / errors).
  List<String> devices() {
    final result = Process.runSync(adbPath, const ['devices']);
    if (result.exitCode != 0) return const [];
    return (result.stdout as String)
        .split('\n')
        .skip(1) // header: "List of devices attached"
        .map((l) => l.trim())
        .where((l) => l.endsWith('device'))
        .map((l) => l.split(RegExp(r'\s+')).first)
        .toList();
  }

  void _ensureAdbAvailable() {
    try {
      final r = Process.runSync(adbPath, const ['version']);
      if (r.exitCode != 0) throw const AdbException('adb is not working');
    } on ProcessException {
      throw AdbException(
          'Could not run "$adbPath". Install Android platform-tools and ensure '
          'adb is on your PATH (or pass --adb-path).');
    }
  }

  // --- pure parsing (unit-tested) ------------------------------------------

  /// Parse the textual output of
  /// `content query --uri content://sms/inbox --projection address:date:body`.
  ///
  /// Rows look like:
  ///   Row: 0 address=CBE, date=1719000000000, body=Dear Mr Dechasa ...
  ///   Row: 1 address=127, date=1719000100000, body=You have received ...
  static List<SmsMessage> parseContentQuery(String output) {
    final messages = <SmsMessage>[];
    // Split into rows: each begins with "Row: <n> ". Keep body's internal
    // newlines intact by splitting on the Row marker rather than on '\n'.
    final rowMarker = RegExp(r'Row:\s*\d+\s');
    final rows = output
        .split(rowMarker)
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty);

    for (final row in rows) {
      final address = _field(row, 'address');
      final dateStr = _field(row, 'date');
      final body = _trailingBody(row);
      if (body == null || body.isEmpty) continue;
      messages.add(SmsMessage(
        address: (address == null || address == 'null') ? null : address,
        body: body,
        dateMillis: dateStr == null ? null : int.tryParse(dateStr),
      ));
    }
    return messages;
  }

  /// Extract a non-final field value: text after `key=` up to the next `, key2=`.
  static String? _field(String row, String key) {
    final m = RegExp('$key=').firstMatch(row);
    if (m == null) return null;
    final rest = row.substring(m.end);
    // Stop at the next ", <ident>=" which marks the following column.
    final next = RegExp(r', [a-z_]+=').firstMatch(rest);
    return (next == null ? rest : rest.substring(0, next.start)).trim();
  }

  /// Everything after the final `body=` is the message (handles commas/newlines).
  static String? _trailingBody(String row) {
    final idx = row.lastIndexOf('body=');
    if (idx == -1) return null;
    return row.substring(idx + 'body='.length).trim();
  }
}

class AdbException implements Exception {
  final String message;
  const AdbException(this.message);
  @override
  String toString() => 'AdbException: $message';
}
