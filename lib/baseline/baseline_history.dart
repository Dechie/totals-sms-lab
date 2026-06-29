import 'dart:convert';
import 'dart:io';

/// One recorded baseline in the history ledger.
class BaselineRecord {
  final String signature;
  final String recordedAt; // ISO-8601
  final int patternCount;
  final int bankCount;
  final String? totalsRev;
  final String? source;
  final String? note;
  final Map<String, int> patternsPerBank;

  const BaselineRecord({
    required this.signature,
    required this.recordedAt,
    required this.patternCount,
    required this.bankCount,
    this.totalsRev,
    this.source,
    this.note,
    this.patternsPerBank = const {},
  });

  factory BaselineRecord.fromJson(Map<String, dynamic> j) => BaselineRecord(
        signature: j['signature'] as String,
        recordedAt: j['recordedAt'] as String,
        patternCount: (j['patternCount'] ?? 0) as int,
        bankCount: (j['bankCount'] ?? 0) as int,
        totalsRev: j['totalsRev'] as String?,
        source: j['source'] as String?,
        note: j['note'] as String?,
        patternsPerBank: (j['patternsPerBank'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt())) ??
            const {},
      );

  Map<String, dynamic> toJson() => {
        'signature': signature,
        'recordedAt': recordedAt,
        'patternCount': patternCount,
        'bankCount': bankCount,
        if (totalsRev != null) 'totalsRev': totalsRev,
        if (source != null) 'source': source,
        if (note != null) 'note': note,
        'patternsPerBank': patternsPerBank,
      };
}

/// An append-only ledger of baseline signatures, persisted to a single JSON
/// file that lives in (and is committed to) the repo — a tiny "database" of how
/// the parser baseline evolved over time. Each [record] appends a new entry
/// only when the signature actually changed, so the file captures *transitions*
/// rather than every run.
class BaselineHistory {
  static const int currentVersion = 1;

  final List<BaselineRecord> entries;

  BaselineHistory({List<BaselineRecord>? entries})
      : entries = entries ?? <BaselineRecord>[];

  /// The signature of the most recently recorded baseline, if any.
  String? get currentSignature =>
      entries.isEmpty ? null : entries.last.signature;

  bool get isEmpty => entries.isEmpty;

  /// Append [record] if its signature differs from the current head.
  /// Returns true if it was appended, false if it was already current.
  bool record(BaselineRecord record) {
    if (currentSignature == record.signature) return false;
    entries.add(record);
    return true;
  }

  // --- persistence ---------------------------------------------------------

  static BaselineHistory load(String path) {
    final file = File(path);
    if (!file.existsSync()) return BaselineHistory();
    final raw = file.readAsStringSync().trim();
    if (raw.isEmpty) return BaselineHistory();
    final decoded = jsonDecode(raw);
    final list = (decoded is Map ? decoded['entries'] : decoded) as List? ?? [];
    return BaselineHistory(
      entries: list
          .whereType<Map>()
          .map((e) => BaselineRecord.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  void save(String path) {
    final json = const JsonEncoder.withIndent('  ').convert({
      'version': currentVersion,
      'current': currentSignature,
      'count': entries.length,
      'entries': [for (final e in entries) e.toJson()],
    });
    File(path).writeAsStringSync('$json\n');
  }
}
