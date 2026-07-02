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

  /// When true, the app's accept-gate REJECTS a match that produced no
  /// `reference`; when false, the app synthesizes a placeholder reference.
  /// Mirrors Totals' `SmsPattern.refRequired`. Needed to replicate the gate.
  final bool? refRequired;

  /// When true (and the regex has an `account` group), the gate rejects a match
  /// with no extracted account. Mirrors Totals' `SmsPattern.hasAccount`.
  final bool? hasAccount;

  /// Whether the pattern is expected to carry fee fields (serviceCharge/vat).
  /// Read for extraction-health reporting only; not part of the accept-gate.
  final bool? hasFees;

  RegExp? _compiled;
  bool _compileFailed = false;

  SmsPattern({
    required this.bankId,
    required this.senderId,
    required this.regex,
    required this.type,
    this.description = '',
    this.refRequired,
    this.hasAccount,
    this.hasFees,
  });

  factory SmsPattern.fromJson(Map<String, dynamic> json) => SmsPattern(
        bankId: json['bankId'] as int,
        senderId: (json['senderId'] ?? '').toString(),
        regex: (json['regex'] ?? '').toString(),
        type: (json['type'] ?? '').toString(),
        description: (json['description'] ?? '').toString(),
        refRequired: json['refRequired'] as bool?,
        hasAccount: json['hasAccount'] as bool?,
        hasFees: json['hasFees'] as bool?,
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
