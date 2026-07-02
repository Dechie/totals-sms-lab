/// A financial institution definition, mirroring Totals' `banks.json`.
class Bank {
  final int id;
  final String name;
  final String shortName;

  /// Sender ids/codes this bank uses (e.g. ["CBE"], ["127"]).
  final List<String> codes;

  /// How many trailing account digits the app keeps when `uniformMasking` is
  /// on. Mirrors Totals' `Bank.maskPattern`; used to replicate the parser's
  /// account extraction so the accept-gate's account check matches production.
  final int? maskPattern;

  /// Whether the app extracts the last `maskPattern` digits of the raw account
  /// (true) or keeps it verbatim (false/null). Mirrors Totals' `uniformMasking`.
  final bool? uniformMasking;

  const Bank({
    required this.id,
    required this.name,
    required this.shortName,
    required this.codes,
    this.maskPattern,
    this.uniformMasking,
  });

  factory Bank.fromJson(Map<String, dynamic> json) {
    final codes = (json['codes'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    return Bank(
      id: json['id'] as int,
      name: (json['name'] ?? '').toString(),
      shortName: (json['shortName'] ?? json['name'] ?? '').toString(),
      codes: codes,
      maskPattern: (json['maskPattern'] as num?)?.toInt(),
      uniformMasking: json['uniformMasking'] as bool?,
    );
  }
}
