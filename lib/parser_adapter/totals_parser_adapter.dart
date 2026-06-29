import 'dart:convert';
import 'dart:io';

import '../baseline/parser_baseline.dart';
import '../models/bank.dart';
import '../models/parse_result.dart';
import '../models/sms_message.dart';
import '../models/sms_pattern.dart';
import 'parser_adapter.dart';

/// Adapter that reproduces Totals' parsing decision using its own data files:
///   * `banks.json`       — maps sender codes -> bank
///   * `sms_patterns.json`— regexes per bank
///
/// It mirrors the production matching strategy: resolve the sender to a bank,
/// then try that bank's patterns (case-insensitive, dotAll). A message is
/// "matched" when any candidate pattern's regex matches the body. When the
/// sender can't be resolved, every pattern is tried so we can still attribute
/// the most likely bank for a match.
class TotalsParserAdapter implements ParserAdapter {
  final List<Bank> _banks;
  final List<SmsPattern> _patterns;
  final Map<int, Bank> _banksById;
  final Map<int, List<SmsPattern>> _patternsByBank;

  TotalsParserAdapter._(this._banks, this._patterns)
      : _banksById = {for (final b in _banks) b.id: b},
        _patternsByBank = _groupByBank(_patterns);

  @override
  String get name => 'Totals Parser Framework';

  int get bankCount => _banks.length;
  int get patternCount => _patterns.length;
  int get invalidPatternCount =>
      _patterns.where((p) => !p.isValid).length;

  /// The loaded patterns (read-only) — used to build a [ParserBaseline].
  List<SmsPattern> get patterns => List.unmodifiable(_patterns);

  /// The loaded banks (read-only).
  List<Bank> get banks => List.unmodifiable(_banks);

  /// Display name for a bank id without falling back to "Unknown".
  String? bankShortName(int bankId) {
    final b = _banksById[bankId];
    return b?.shortName ?? b?.name;
  }

  /// The parser definitions as a [ParserBaseline] — the frame of reference a
  /// coverage run is measured against.
  ParserBaseline baseline({String? sourceLabel}) => ParserBaseline.from(
        _patterns,
        bankCount: _banks.length,
        sourceLabel: sourceLabel,
      );

  /// Load from explicit file paths.
  factory TotalsParserAdapter.fromFiles({
    required String banksPath,
    required String patternsPath,
  }) {
    final banks = _readBanks(banksPath);
    final patterns = _readPatterns(patternsPath);
    return TotalsParserAdapter._(banks, patterns);
  }

  /// Load from the snapshot vendored inside this tool
  /// (`vendor/totals/{banks,sms_patterns}.json`).
  ///
  /// The tool is designed to be self-contained, so this is the default source.
  /// Paths are probed relative to both the running script and the current
  /// directory so it works whether invoked via `dart run` from the package
  /// root or as an activated executable.
  static TotalsParserAdapter? vendored() {
    for (final root in _vendorRootCandidates()) {
      final banks = File('$root/banks.json');
      final patterns = File('$root/sms_patterns.json');
      if (banks.existsSync() && patterns.existsSync()) {
        return TotalsParserAdapter.fromFiles(
          banksPath: banks.path,
          patternsPath: patterns.path,
        );
      }
    }
    return null;
  }

  /// The resolved `vendor/totals` directory, or null if not found.
  static String? vendoredDir() {
    for (final root in _vendorRootCandidates()) {
      if (File('$root/sms_patterns.json').existsSync()) return root;
    }
    return null;
  }

  static Iterable<String> _vendorRootCandidates() sync* {
    // Relative to the package root inferred from Platform.script (bin/..).
    try {
      final script = Platform.script;
      if (script.scheme == 'file') {
        yield script.resolve('../vendor/totals').toFilePath();
        yield script.resolve('../../vendor/totals').toFilePath();
      }
    } catch (_) {/* Platform.script may be unavailable in some hosts */}
    // Relative to the current working directory.
    yield '${Directory.current.path}/vendor/totals';
  }

  /// Resolve the default adapter: explicit paths win, then the vendored
  /// snapshot, then a best-effort autodiscovery of a sibling Totals checkout.
  static TotalsParserAdapter resolveDefault({
    String? banksPath,
    String? patternsPath,
  }) {
    if (banksPath != null && patternsPath != null) {
      return TotalsParserAdapter.fromFiles(
        banksPath: banksPath,
        patternsPath: patternsPath,
      );
    }
    if (banksPath != null || patternsPath != null) {
      throw ArgumentError(
          'Provide both --banks and --patterns, or neither.');
    }
    return vendored() ??
        autodiscover() ??
        (throw StateError(
            'No parser definitions found. Expected a vendored snapshot at '
            'vendor/totals/, a sibling Totals checkout, or explicit '
            '--banks/--patterns paths.'));
  }

  /// Try to locate the Totals assets relative to a starting directory by
  /// walking up and probing `**/app/assets/{banks,sms_patterns}.json`.
  static TotalsParserAdapter? autodiscover({String? from}) {
    var dir = Directory(from ?? Directory.current.path).absolute;
    for (var i = 0; i < 6; i++) {
      for (final base in [
        'totals/app/assets',
        'app/assets',
        'assets',
      ]) {
        final banks = File('${dir.path}/$base/banks.json');
        final patterns = File('${dir.path}/$base/sms_patterns.json');
        if (banks.existsSync() && patterns.existsSync()) {
          return TotalsParserAdapter.fromFiles(
            banksPath: banks.path,
            patternsPath: patterns.path,
          );
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  @override
  ParseResult parse(SmsMessage message) {
    // Mirror Totals' `cleanSmsText` (which is `text.trim()`) before matching.
    final body = message.body.trim();
    final candidates = _candidatesFor(message);
    for (final p in candidates) {
      final re = p.regExp;
      if (re == null) continue;
      if (re.hasMatch(body)) {
        final bank = _banksById[p.bankId];
        return ParseResult(
          message: message,
          matched: true,
          bankId: p.bankId,
          bankName: bank?.shortName ?? bank?.name,
          transactionType: p.type,
          matchedPatternDescription: p.description,
        );
      }
    }
    // Unmatched: still try to attribute a bank from the sender.
    final bank = _bankForSender(message.address);
    return ParseResult(
      message: message,
      matched: false,
      bankId: bank?.id,
      bankName: bank?.shortName ?? bank?.name,
    );
  }

  @override
  List<ParseResult> parseAll(Iterable<SmsMessage> messages) =>
      messages.map(parse).toList();

  @override
  String bankNameFor(int? bankId) {
    if (bankId == null) return 'Unknown';
    final bank = _banksById[bankId];
    return bank?.shortName ?? bank?.name ?? 'Bank #$bankId';
  }

  // --- internals ---------------------------------------------------------

  /// Candidate patterns to try, scoped to the sender's bank when known,
  /// otherwise the full set (so unknown senders can still be attributed).
  List<SmsPattern> _candidatesFor(SmsMessage message) {
    final bank = _bankForSender(message.address);
    if (bank != null) {
      final scoped = _patternsByBank[bank.id];
      if (scoped != null && scoped.isNotEmpty) return scoped;
    }
    return _patterns;
  }

  /// Resolve a sender address to a bank, replicating Totals' `getRelevantBank`
  /// + `_normalizeSenderToken`: lowercase, strip everything but [a-z0-9], then
  /// substring-match the normalized address against each normalized bank code.
  Bank? _bankForSender(String? address) {
    if (address == null) return null;
    final norm = _normalizeSenderToken(address);
    if (norm.isEmpty) return null;
    for (final b in _banks) {
      for (final code in b.codes) {
        final nc = _normalizeSenderToken(code);
        if (nc.isNotEmpty && norm.contains(nc)) return b;
      }
    }
    return null;
  }

  static String _normalizeSenderToken(String value) =>
      value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  static Map<int, List<SmsPattern>> _groupByBank(List<SmsPattern> patterns) {
    final map = <int, List<SmsPattern>>{};
    for (final p in patterns) {
      map.putIfAbsent(p.bankId, () => []).add(p);
    }
    return map;
  }

  static List<Bank> _readBanks(String path) {
    final decoded = jsonDecode(File(path).readAsStringSync());
    final list = decoded is Map ? decoded['banks'] : decoded;
    return (list as List)
        .whereType<Map>()
        .map((e) => Bank.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  static List<SmsPattern> _readPatterns(String path) {
    final decoded = jsonDecode(File(path).readAsStringSync());
    final list = decoded is Map ? decoded['patterns'] : decoded;
    return (list as List)
        .whereType<Map>()
        .map((e) => SmsPattern.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}
