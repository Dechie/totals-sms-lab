import 'dart:io';

import 'parser_baseline.dart' show fnv1a64;

/// One piece of app *logic* the lab mirrors by hand, located by file + an
/// extractor. If the extracted source changes (or the anchor disappears), the
/// lab's hand-written mirror may no longer match the app — so coverage could be
/// silently wrong. [LogicFidelity] hashes these into a signature `diff` can
/// watch, complementing the data-only baseline `diff`.
class FidelityProbe {
  final String name;

  /// Path relative to the app directory (e.g. `lib/services/sms_service.dart`).
  final String relativePath;

  /// Pulls the relevant snippet out of the file's source, or null if not found
  /// (a missing anchor is itself drift — the code was renamed/removed).
  final String? Function(String source) extract;

  const FidelityProbe(this.name, this.relativePath, this.extract);
}

/// Marker hash for a probe whose anchor wasn't found (renamed/removed = drift).
const String kMissingProbe = 'MISSING';

/// Result of computing the logic signature.
class LogicFidelityResult {
  /// Aggregate signature over all probe hashes.
  final String signature;

  /// Per-probe hash (`kMissingProbe` when the anchor wasn't found).
  final Map<String, String> probeHashes;

  const LogicFidelityResult(this.signature, this.probeHashes);

  bool get allFound => probeHashes.values.every((h) => h != kMissingProbe);

  /// Names of probes whose hash differs from [other] (the drifted logic).
  List<String> driftedAgainst(Map<String, String> other) => [
        for (final e in probeHashes.entries)
          if (other[e.key] != e.value) e.key
      ];
}

class LogicFidelity {
  /// The mirrored logic. Each probe targets the exact rule documented in
  /// REFERENCE.md → "Fidelity to the production parser".
  static final List<FidelityProbe> probes = [
    // 1. Regex compile flags (caseSensitive/multiLine/dotAll).
    FidelityProbe('regexFlags', 'lib/utils/pattern_parser.dart', (src) {
      final m =
          RegExp(r'RegExp\(\s*pattern\.regex\s*,([^)]*)\)').firstMatch(src);
      return m?.group(1);
    }),
    // 2. SMS text cleaning before matching.
    FidelityProbe('cleanSmsText', 'lib/services/sms_config_service.dart',
        (src) => _function(src, 'cleanSmsText(String text)')),
    // 3. Sender-token normalization.
    FidelityProbe('normalizeSenderToken', 'lib/services/sms_service.dart',
        (src) => _function(src, '_normalizeSenderToken(String value)')),
    // 4. Sender→bank matching.
    FidelityProbe('addressMatchesCode', 'lib/services/sms_service.dart',
        (src) => _function(src, '_addressMatchesCode(')),
    // 5. The transaction noise heuristic.
    FidelityProbe(
        'looksLikeTransaction',
        'lib/services/sms_service.dart',
        (src) =>
            _function(src, '_looksLikeTransactionMessage(String messageBody)')),
    // 6. Field extraction + the accept-gate (mirrored in FieldExtractor).
    FidelityProbe('extractTransactionDetails', 'lib/utils/pattern_parser.dart',
        (src) => _function(src, 'extractTransactionDetails(')),
    // 7. Numeric cleaning applied to amount/balance/fees before parsing.
    FidelityProbe('cleanNumber', 'lib/utils/pattern_parser.dart',
        (src) => _function(src, '_cleanNumber(String? input)')),
  ];

  /// Compute the logic signature from a Totals app directory, or null if the
  /// source isn't available there (e.g. only a patterns file was given).
  static LogicFidelityResult? fromAppDir(String appDir) {
    final cache = <String, String?>{};
    final probeHashes = <String, String>{};
    var anyFilePresent = false;

    for (final probe in probes) {
      final path = '$appDir/${probe.relativePath}';
      final src = cache.putIfAbsent(path, () {
        final f = File(path);
        return f.existsSync() ? f.readAsStringSync() : null;
      });
      if (src != null) anyFilePresent = true;
      final snippet = src == null ? null : probe.extract(src);
      probeHashes[probe.name] =
          snippet == null ? kMissingProbe : fnv1a64(_normalize(snippet));
    }

    // If not a single probe file was present, this isn't an app dir at all.
    if (!anyFilePresent) return null;

    final combined = (probeHashes.entries
            .map((e) => '${e.key}=${e.value}')
            .toList()
          ..sort())
        .join(' ');
    return LogicFidelityResult(fnv1a64(combined), probeHashes);
  }

  /// Extract a function body by brace-matching from [anchor] to its close.
  /// Robust to nested braces and reformatting (whitespace is normalized later).
  static String? _function(String source, String anchor) {
    final start = source.indexOf(anchor);
    if (start == -1) return null;
    final open = source.indexOf('{', start);
    if (open == -1) return null;
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      final ch = source[i];
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) return source.substring(open, i + 1);
      }
    }
    return null; // unbalanced — treat as not found
  }

  static String _normalize(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();
}
