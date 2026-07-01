import 'dart:convert';
import 'dart:io';

import '../models/data_quality.dart';
import '../models/sms_message.dart';

/// Loads an SMS dataset from a JSON file.
///
/// Accepted shapes:
///   * a top-level array: `[ {"address": "...", "body": "..."}, ... ]`
///   * an object with a `messages` (or `sms`) array
///   * NDJSON: one JSON object per line
///
/// Resilient by design: a single malformed record never sinks the whole file.
/// Real device exports are messy; we keep every record we can turn into a
/// message and tally the rest into [DataQuality] rather than throwing.
class DatasetLoader {
  static List<SmsMessage> load(String path, {DataQuality? quality}) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('Dataset not found', path);
    }
    final raw = file.readAsStringSync().trim();
    if (raw.isEmpty) return const [];

    // Prefer a single well-formed JSON document (array or {messages:[...]}).
    List<dynamic>? records;
    try {
      records = _extractList(jsonDecode(raw));
    } on FormatException {
      records = null; // fall through to NDJSON
    }

    // NDJSON fallback: parse line-by-line, skipping unparseable lines.
    if (records == null) {
      records = <dynamic>[];
      for (final line in raw.split('\n')) {
        final t = line.trim();
        if (t.isEmpty) continue;
        try {
          records.add(jsonDecode(t));
        } on FormatException {
          quality?.datasetMalformed++;
        }
      }
    }

    final out = <SmsMessage>[];
    for (final rec in records) {
      if (rec is! Map) {
        quality?.datasetMalformed++;
        continue;
      }
      SmsMessage m;
      try {
        m = SmsMessage.fromJson(rec.cast<String, dynamic>());
      } catch (_) {
        quality?.datasetMalformed++;
        continue;
      }
      if (m.body.trim().isEmpty) {
        quality?.datasetEmptyBodies++;
        continue;
      }
      out.add(m);
    }
    if (quality != null) quality.messagesLoaded += out.length;
    return out;
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
