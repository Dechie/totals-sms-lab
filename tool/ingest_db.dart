// Developer utility: pull Totals' on-device SQLite DB and turn it into lab
// inputs — **without any change to the Totals app**.
//
// On a debuggable build (debug / `flutter run`), `adb run-as <pkg>` can read the
// app's private `databases/totals.db`. We copy it out (binary-clean, via
// `exec-out`) and read it with the `sqlite3` CLI. Both `adb` and `sqlite3` are
// external tools — not Dart dependencies — so the lab stays zero-dep and offline.
//
// It produces two things:
//   * failed_parses  -> a dataset JSON ([{address, body, date}]).  This is the
//     app's *curated* discovery signal: messages it saw, judged transaction-like
//     (the app's `_looksLikeTransactionMessage` filter), and failed to parse.
//     Richer and less noisy than re-deriving from the raw inbox.
//   * sms_patterns   -> (optional) a live `sms_patterns.json` baseline — the
//     patterns ACTUALLY running on the device (the app loads patterns from this
//     table, not the bundled asset), for true-fidelity analyze/diff.
//
// Usage:
//   dart run tool/ingest_db.dart [path/to/totals.db] [options]
//     (omit the path to pull from a connected device via adb run-as)
//   --package=<pkg>        app id            (default com.example.offline_gateway)
//   --device=<serial>      target a specific adb device
//   --adb-path=<path>      adb executable    (default: adb)
//   --sqlite-path=<path>   sqlite3 executable (default: sqlite3)
//   --db=<path>            where to store/read the db (default build/totals.db)
//   --out=<path>           failed_parses dataset out (default build/failed_parses.json)
//   --patterns-out=<path>  also dump the live sms_patterns.json here (optional)
//
// Example:
//   dart run tool/ingest_db.dart --package=com.example.offline_gateway.test \
//     --out=example/device_failed.json --patterns-out=build/live_patterns.json
//   dart run sms_pattern_lab analyze example/device_failed.json
//   dart run sms_pattern_lab diff --against=build/live_patterns.json

import 'dart:convert';
import 'dart:io';

void main(List<String> argv) {
  String? dbArg;
  var package = 'com.example.offline_gateway';
  String? device;
  var adb = 'adb';
  var sqlite = 'sqlite3';
  var dbPath = 'build/totals.db';
  var out = 'build/failed_parses.json';
  String? patternsOut;

  for (final a in argv) {
    if (!a.startsWith('--')) {
      dbArg = a;
      continue;
    }
    final eq = a.indexOf('=');
    final key = eq == -1 ? a.substring(2) : a.substring(2, eq);
    final val = eq == -1 ? '' : a.substring(eq + 1);
    switch (key) {
      case 'package':
        package = val;
        break;
      case 'device':
        device = val;
        break;
      case 'adb-path':
        adb = val;
        break;
      case 'sqlite-path':
        sqlite = val;
        break;
      case 'db':
        dbPath = val;
        break;
      case 'out':
        out = val;
        break;
      case 'patterns-out':
        patternsOut = val;
        break;
      default:
        stderr.writeln('Warning: ignoring unknown option --$key');
    }
  }

  _ensureSqlite(sqlite);

  // 1. Obtain the db file: use a provided path, else pull from the device.
  if (dbArg != null) {
    if (!File(dbArg).existsSync()) {
      _fail('Database not found: $dbArg');
    }
    dbPath = dbArg;
    stdout.writeln('Reading existing db: $dbPath');
  } else {
    _pullDb(adb: adb, package: package, device: device, dbPath: dbPath);
  }

  // 2. Dump failed_parses → dataset.
  final fpJson = _query(
    sqlite,
    dbPath,
    'SELECT coalesce(json_group_array(json_object('
    "'address', address, 'body', body, 'date', timestamp)), '[]') "
    'FROM failed_parses;',
    table: 'failed_parses',
  );
  _writeFile(out, _pretty(fpJson));
  stdout.writeln('✓ failed_parses → $out  (${_count(fpJson)} message(s))');
  stdout.writeln('  Next: dart run sms_pattern_lab analyze $out');

  // 3. Optionally dump the live sms_patterns table → a baseline file.
  if (patternsOut != null) {
    final pJson = _query(
      sqlite,
      dbPath,
      "SELECT json_object('patterns', coalesce(json_group_array(json_object("
      "'bankId', bankId, 'senderId', senderId, 'regex', regex, "
      "'type', type, 'description', description)), json_array())) "
      'FROM sms_patterns;',
      table: 'sms_patterns',
    );
    _writeFile(patternsOut, _pretty(pJson));
    final n = (jsonDecode(pJson)['patterns'] as List).length;
    stdout.writeln('✓ live sms_patterns → $patternsOut  ($n pattern(s))');
    stdout.writeln('  Use: dart run sms_pattern_lab diff --against=$patternsOut');
  }
}

void _pullDb({
  required String adb,
  required String package,
  String? device,
  required String dbPath,
}) {
  _ensureAdb(adb);
  Directory(File(dbPath).parent.path).createSync(recursive: true);

  // Pull the main db plus WAL/SHM sidecars (SQLite is in WAL mode; recent rows
  // live in -wal). exec-out keeps the byte stream intact.
  var pulledMain = false;
  for (final suffix in ['', '-wal', '-shm']) {
    final args = <String>[
      if (device != null) ...['-s', device],
      'exec-out',
      'run-as',
      package,
      'cat',
      'databases/totals.db$suffix',
    ];
    // stdoutEncoding: null → capture raw bytes, not a (corrupting) String.
    final res = Process.runSync(adb, args, stdoutEncoding: null);
    final bytes = (res.stdout as List).cast<int>();
    if (res.exitCode == 0 && bytes.isNotEmpty) {
      File('$dbPath$suffix').writeAsBytesSync(bytes);
      if (suffix.isEmpty) pulledMain = true;
    } else if (suffix.isEmpty) {
      final err = (res.stderr is List)
          ? utf8.decode((res.stderr as List).cast<int>(), allowMalformed: true)
          : '${res.stderr}';
      _fail('Could not read databases/totals.db via run-as for "$package".\n'
          '${err.trim()}\n'
          'Is the app a DEBUGGABLE build and the package id correct? '
          '(adb shell pm list packages | grep offline_gateway)');
    }
  }
  if (pulledMain) {
    stdout.writeln('Pulled totals.db from device → $dbPath');
  }
}

/// Run a single-value sqlite3 query and return stdout (trimmed).
String _query(String sqlite, String dbPath, String sql, {required String table}) {
  final res = Process.runSync(sqlite, [dbPath, sql]);
  if (res.exitCode != 0) {
    final err = '${res.stderr}'.trim();
    if (err.contains('no such table')) {
      _fail('Table "$table" not found in $dbPath — is this the Totals db?');
    }
    _fail('sqlite3 failed: $err');
  }
  final outStr = '${res.stdout}'.trim();
  return outStr.isEmpty ? (table == 'sms_patterns' ? '{"patterns":[]}' : '[]')
      : outStr;
}

String _pretty(String json) =>
    '${const JsonEncoder.withIndent('  ').convert(jsonDecode(json))}\n';

int _count(String jsonArray) => (jsonDecode(jsonArray) as List).length;

void _writeFile(String path, String contents) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(contents);
}

void _ensureAdb(String adb) {
  try {
    if (Process.runSync(adb, const ['version']).exitCode != 0) {
      _fail('"$adb" is not working. Install Android platform-tools.');
    }
  } on ProcessException {
    _fail('Could not run "$adb". Install Android platform-tools / pass --adb-path.');
  }
}

void _ensureSqlite(String sqlite) {
  try {
    if (Process.runSync(sqlite, const ['--version']).exitCode != 0) {
      _fail('"$sqlite" is not working. Install the sqlite3 CLI.');
    }
  } on ProcessException {
    _fail('Could not run "$sqlite". Install the sqlite3 CLI / pass --sqlite-path.');
  }
}

Never _fail(String message) {
  stderr.writeln('Error: $message');
  exit(1);
}
