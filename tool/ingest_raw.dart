// Developer utility: convert a raw, chat-exported SMS blob into a Pattern Lab
// dataset (JSON array of {address, body}).
//
// Many real datasets arrive as a single lump of text copied out of a chat app,
// with timestamp markers like "[6/29/26 11:55 PM] name:" sprinkled in and each
// SMS beginning with a known prefix (e.g. "Dear"). This tool strips the
// markers and splits the blob back into individual messages.
//
// Usage:
//   dart run tool/ingest_raw.dart <raw.txt> [options]
//     --address=<id>     Sender id to tag every message with   (default: CBE)
//     --split-on=<word>  Token that begins each message         (default: Dear)
//     --out=<path>       Write JSON here (default: stdout)
//
// Example:
//   dart run tool/ingest_raw.dart example/cbe_raw.txt \
//     --address=CBE --out=example/cbe_sms.json

import 'dart:convert';
import 'dart:io';

void main(List<String> argv) {
  if (argv.isEmpty || argv.first.startsWith('--')) {
    stderr.writeln('Usage: dart run tool/ingest_raw.dart <raw.txt> '
        '[--address=CBE] [--split-on=Dear] [--out=path]');
    exitCode = 64;
    return;
  }

  final inputPath = argv.first;
  var address = 'CBE';
  var splitOn = 'Dear';
  String? out;
  for (final a in argv.skip(1)) {
    final eq = a.indexOf('=');
    final key = eq == -1 ? a.substring(2) : a.substring(2, eq);
    final val = eq == -1 ? '' : a.substring(eq + 1);
    switch (key) {
      case 'address':
        address = val;
        break;
      case 'split-on':
        splitOn = val;
        break;
      case 'out':
        out = val;
        break;
    }
  }

  var text = File(inputPath).readAsStringSync();

  // 1. Strip chat timestamp markers: "[6/29/26 11:55 PM] <name>: "
  text = text.replaceAll(
      RegExp(r'\[\d{1,2}/\d{1,2}/\d{2,4}[^\]]*\]\s*[^:]*:\s*'), ' ');

  // 2. Flatten newlines so messages broken across lines rejoin.
  text = text.replaceAll(RegExp(r'\s*\n\s*'), ' ');

  // 3. Split right before each occurrence of the message-start token.
  final marker = RegExp('(?=${RegExp.escape(splitOn)}\\b)');
  final messages = text
      .split(marker)
      .map((s) => s.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((s) => s.isNotEmpty && s.startsWith(splitOn))
      .map((body) => {'address': address, 'body': body})
      .toList();

  final json = const JsonEncoder.withIndent('  ').convert(messages);
  if (out == null) {
    stdout.writeln(json);
  } else {
    File(out).writeAsStringSync('$json\n');
    stdout.writeln('Wrote ${messages.length} messages to $out');
  }
}
