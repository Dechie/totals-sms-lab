/// A regex pattern definition, mirroring Totals' `sms_patterns.json`.
///
/// Pattern Lab only ever *reads* these — it never rewrites them. The compiled
/// [regExp] is cached lazily so the adapter can evaluate a whole dataset
/// without recompiling per message.
class SmsPattern {
  final int bankId;
  final String senderId;
  final String regex;
  final String type; // CREDIT or DEBIT
  final String description;

  RegExp? _compiled;
  bool _compileFailed = false;

  SmsPattern({
    required this.bankId,
    required this.senderId,
    required this.regex,
    required this.type,
    this.description = '',
  });

  factory SmsPattern.fromJson(Map<String, dynamic> json) => SmsPattern(
        bankId: json['bankId'] as int,
        senderId: (json['senderId'] ?? '').toString(),
        regex: (json['regex'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
      );

  /// Compiled regex, or `null` if the source regex is invalid.
  ///
  /// Flags mirror Totals' `PatternParser.extractTransactionDetails` exactly —
  /// `caseSensitive: false, multiLine: true, dotAll: true` — so the lab's
  /// match/no-match verdict matches the production parser. `multiLine` matters:
  /// several patterns anchor with `^`/`$`.
  RegExp? get regExp {
    if (_compiled != null || _compileFailed) return _compiled;
    try {
      _compiled =
          RegExp(regex, caseSensitive: false, multiLine: true, dotAll: true);
    } catch (_) {
      _compileFailed = true;
    }
    return _compiled;
  }

  bool get isValid => regExp != null;
}
