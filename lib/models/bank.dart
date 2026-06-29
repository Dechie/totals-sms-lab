/// A financial institution definition, mirroring Totals' `banks.json`.
class Bank {
  final int id;
  final String name;
  final String shortName;

  /// Sender ids/codes this bank uses (e.g. ["CBE"], ["127"]).
  final List<String> codes;

  const Bank({
    required this.id,
    required this.name,
    required this.shortName,
    required this.codes,
  });

  factory Bank.fromJson(Map<String, dynamic> json) {
    final codes = (json['codes'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    return Bank(
      id: json['id'] as int,
      name: (json['name'] ?? '').toString(),
      shortName: (json['shortName'] ?? json['name'] ?? '').toString(),
      codes: codes,
    );
  }
}
