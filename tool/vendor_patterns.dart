// Developer utility: refresh the vendored Totals parser snapshot
// (vendor/totals/{banks,sms_patterns}.json) from a Totals checkout, plus a
// logic-fidelity signature (vendor/totals/fidelity.json).
//
// Usage:
//   dart run tool/vendor_patterns.dart --from=/path/to/totals/app
//
// The --from path is the Totals *app* directory (the one containing
// assets/banks.json). Defaults to ../totals/app relative to this tool.

import 'dart:convert';
import 'dart:io';

import 'package:sms_pattern_lab/baseline/logic_fidelity.dart';

void main(List<String> argv) {
  var from = '../totals/app';
  for (final a in argv) {
    if (a.startsWith('--from=')) from = a.substring('--from='.length);
  }

  final files = {
    'banks.json': 'assets/banks.json',
    'sms_patterns.json': 'assets/sms_patterns.json',
  };

  final destDir = Directory('vendor/totals')..createSync(recursive: true);
  var copied = 0;
  files.forEach((destName, srcRel) {
    final src = File('$from/$srcRel');
    if (!src.existsSync()) {
      stderr.writeln('! Missing source: ${src.path}');
      return;
    }
    final dest = File('${destDir.path}/$destName');
    src.copySync(dest.path);
    stdout.writeln('✓ ${src.path}  →  ${dest.path}');
    copied++;
  });

  if (copied == 0) {
    stderr.writeln('Nothing copied. Check --from=<totals/app> path.');
    exitCode = 1;
    return;
  }

  // Snapshot the parsing-logic signature too, so `diff` can warn on LOGIC drift
  // (regex flags, cleanSmsText, sender normalization, the transaction heuristic)
  // — not just pattern-DATA drift.
  final fidelity = LogicFidelity.fromAppDir(from);
  if (fidelity == null) {
    stderr.writeln('! Could not read app source under $from/lib — '
        'skipped fidelity.json (logic-drift guard will be unavailable).');
  } else {
    File('${destDir.path}/fidelity.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
              'signature': fidelity.signature,
              'probes': fidelity.probeHashes,
            })}\n');
    stdout.writeln('✓ logic fidelity signature → '
        '${destDir.path}/fidelity.json  (${fidelity.signature})');
    if (!fidelity.allFound) {
      stderr.writeln('! Some fidelity probes did not match — the app source may '
          'have moved; review lib/baseline/logic_fidelity.dart.');
    }
  }

  stdout.writeln('\nDone. Review `git diff vendor/totals/` before committing, '
      'then update vendor/totals/SNAPSHOT.md with the new Totals revision.');
}
