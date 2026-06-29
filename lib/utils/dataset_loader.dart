import 'dart:convert';
import 'dart:io';

import '../models/sms_message.dart';

/// Loads an SMS dataset from a JSON file.
///
/// Accepted shapes:
///   * a top-level array: `[ {"address": "...", "body": "..."}, ... ]`
///   * an object with a `messages` (or `sms`) array
///   * NDJSON: one JSON object per line
class DatasetLoader {
  static List<SmsMessage> load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Dataset not found', path);
    }
    final raw = file.readAsStringSync().trim();
    if (raw.isEmpty) return const [];

    // Try standard JSON first.
    try {
      final decoded = jsonDecode(raw);
      final list = _extractList(decoded);
      return list
          .whereType<Map>()
          .map((e) => SmsMessage.fromJson(e.cast<String, dynamic>()))
          .where((m) => m.body.trim().isNotEmpty)
          .toList();
    } on FormatException {
      // Fall back to NDJSON.
      return raw
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => jsonDecode(l))
          .whereType<Map>()
          .map((e) => SmsMessage.fromJson(e.cast<String, dynamic>()))
          .where((m) => m.body.trim().isNotEmpty)
          .toList();
    }
  }

  static List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in ['messages', 'sms', 'data', 'items']) {
        final v = decoded[key];
        if (v is List) return v;
      }
    }
    throw const FormatException('Unrecognized dataset shape');
  }
}
