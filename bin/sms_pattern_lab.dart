import 'dart:convert';
import 'dart:io';

import 'package:sms_pattern_lab/analysis/analysis_pipeline.dart';
import 'package:sms_pattern_lab/baseline/baseline_diff.dart';
import 'package:sms_pattern_lab/baseline/baseline_history.dart';
import 'package:sms_pattern_lab/baseline/logic_fidelity.dart';
import 'package:sms_pattern_lab/baseline/parser_baseline.dart';
import 'package:sms_pattern_lab/corpus/corpus.dart';
import 'package:sms_pattern_lab/export/enrichment_export.dart';
import 'package:sms_pattern_lab/models/data_quality.dart';
import 'package:sms_pattern_lab/models/coverage_report.dart';
import 'package:sms_pattern_lab/models/sms_message.dart';
import 'package:sms_pattern_lab/models/template_family.dart';
import 'package:sms_pattern_lab/parser_adapter/totals_parser_adapter.dart';
import 'package:sms_pattern_lab/reports/html_report.dart';
import 'package:sms_pattern_lab/reports/markdown_report.dart';
import 'package:sms_pattern_lab/similarity/levenshtein_grouper.dart';
import 'package:sms_pattern_lab/similarity/semantic_verb_grouper.dart';
import 'package:sms_pattern_lab/similarity/similarity_grouper.dart';
import 'package:sms_pattern_lab/sources/adb_sms_source.dart';
import 'package:sms_pattern_lab/utils/dataset_loader.dart';

const _version = '1.0.0';

void main(List<String> argv) {
  final args = _Args.parse(argv);
  final command = args.command;

  try {
    switch (command) {
      case 'analyze':
        _runAnalyze(args, writeReport: true);
        break;
      case 'report':
        _runAnalyze(args, writeReport: true, quiet: false, reportOnly: true);
        break;
      case 'stats':
        _runStats(args);
        break;
      case 'templates':
        _runTemplates(args);
        break;
      case 'discover':
        _runDiscover(args);
        break;
      case 'pull':
        _runPull(args);
        break;
      case 'devices':
        _runDevices(args);
        break;
      case 'baseline':
        _runBaseline(args);
        break;
      case 'diff':
        _runDiff(args);
        break;
      case 'history':
        _runHistory(args);
        break;
      case 'corpus':
        _runCorpus(args);
        break;
      case 'export':
        _runExport(args);
        break;
      case 'compare':
        _runCompare();
        break;
      case 'help':
      case null:
        _printUsage();
        break;
      case 'version':
        stdout.writeln('sms-pattern-lab $_version');
        break;
      default:
        stderr.writeln('Unknown command: $command\n');
        _printUsage();
        exitCode = 64; // EX_USAGE
    }
  } on _CliError catch (e) {
    stderr.writeln('Error: ${e.message}');
    exitCode = 1;
  }
}

// --- commands --------------------------------------------------------------

AnalysisResult _analyze(_Args args) {
  final adapter = _resolveAdapter(args);
  final messages = _loadMessages(args);
  final baseline = adapter.baseline(sourceLabel: _snapshotProvenance());
  stdout.writeln('Parser: ${adapter.name} '
      '(${adapter.bankCount} banks, ${adapter.patternCount} patterns'
      '${adapter.invalidPatternCount > 0 ? ', ${adapter.invalidPatternCount} invalid' : ''})');
  stdout.writeln('Baseline: ${baseline.signature}'
      '${baseline.sourceLabel == null ? '' : ' (${baseline.sourceLabel})'}');
  stdout.writeln('');

  final pipeline = AnalysisPipeline(adapter: adapter, grouper: _grouper(args));
  return pipeline.run(messages);
}

/// Selects the similarity grouper from `--group=` (default: identity = V1).
SimilarityGrouper _grouper(_Args args) {
  switch (args.grouping) {
    case 'verb':
    case 'semantic':
      return SemanticVerbGrouper();
    case 'levenshtein':
    case 'lev':
      // Verb buckets refined by wording similarity (V2 step 2).
      return SemanticVerbGrouper(
          within: LevenshteinGrouper(threshold: args.similarity));
    case 'identity':
      return IdentityGrouper();
    default:
      stderr.writeln(
          'Warning: unknown --group=${args.grouping}; using identity.');
      return IdentityGrouper();
  }
}

/// `export` — emit the privacy-safe enrichment artifact (normalized text +
/// action verb + shape profile per gap category) for a maintainer to collect
/// across contributors. Writes JSON to --out; `--preview` also prints a
/// human-readable summary so a contributor can review before sending.
void _runExport(_Args args) {
  // One quality tally owned end-to-end (load → parse → normalize → export), so
  // the exported artifact carries an honest account of its own completeness.
  final quality = DataQuality();
  final adapter = _resolveAdapter(args);
  final messages = _loadMessages(args, quality: quality);

  final baseline = adapter.baseline(sourceLabel: _snapshotProvenance());
  // Same content hash the `corpus` command emits — the like-for-like key.
  final datasetId = Corpus.merge([messages]).datasetId;

  stdout.writeln('Parser: ${adapter.name} '
      '(${adapter.bankCount} banks, ${adapter.patternCount} patterns)');
  stdout.writeln('Baseline: ${baseline.signature}'
      '${baseline.sourceLabel == null ? '' : ' (${baseline.sourceLabel})'}');
  stdout.writeln('Dataset id: $datasetId');

  final grouping = args.grouping;
  final result = AnalysisPipeline(adapter: adapter, grouper: _grouper(args))
      .run(messages, quality: quality);

  final doc = EnrichmentExport.build(
    result.coverage,
    parserName: result.parserName,
    baselineSignature: baseline.signature,
    baselineSource: baseline.sourceLabel,
    datasetId: datasetId,
    generatedAt: DateTime.now().toIso8601String(),
    grouping: grouping,
    similarity:
        (grouping == 'levenshtein' || grouping == 'lev') ? args.similarity : null,
    quality: quality,
  );

  if (args.preview) {
    stdout.writeln('');
    stdout.write(EnrichmentExport.preview(doc));
  }

  final outPath = args.out ?? 'build/enrichment_export.json';
  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(doc)}\n');
  final categories = (doc['metadata'] as Map)['categories'];
  stdout.writeln('\n📦 Enrichment export → $outPath '
      '($categories categor${categories == 1 ? 'y' : 'ies'}, no raw values; '
      'quality: ${quality.summary()}).');
}

/// Load the dataset for an analysis command from either `--adb` (live device)
/// or a dataset file argument.
List<SmsMessage> _loadMessages(_Args args, {DataQuality? quality}) {
  if (args.adb) {
    final messages = _pullFromDevice(args);
    if (messages.isEmpty) {
      throw _CliError('No SMS pulled from device'
          '${args.all ? '' : ' for senders [${args.senderFilter().join(', ')}]'}'
          '. Try --all, check the device, or run `devices`.');
    }
    stdout.writeln('Pulled ${messages.length} message(s) from device via adb');
    return messages;
  }

  final datasetPath = args.positional.isNotEmpty ? args.positional.first : null;
  if (datasetPath == null) {
    throw _CliError('Provide a dataset file, or use --adb to pull from a '
        'connected device. Usage: sms-pattern-lab ${args.command} '
        '<dataset.json>');
  }
  final messages = DatasetLoader.load(datasetPath, quality: quality);
  if (messages.isEmpty) {
    throw _CliError('Dataset "$datasetPath" contained no usable messages.');
  }
  final skipped = quality == null
      ? 0
      : quality.datasetMalformed + quality.datasetEmptyBodies;
  stdout.writeln('Loaded ${messages.length} message(s) from $datasetPath'
      '${skipped > 0 ? ' ($skipped record(s) skipped as malformed/empty)' : ''}');
  return messages;
}

List<SmsMessage> _pullFromDevice(_Args args) {
  final source =
      AdbSmsSource(adbPath: args.adbPath, deviceSerial: args.device);
  try {
    return source.fetch(
        senderFilter: args.all ? const [] : args.senderFilter());
  } on AdbException catch (e) {
    throw _CliError(e.message);
  }
}

void _runAnalyze(_Args args,
    {bool writeReport = false, bool quiet = false, bool reportOnly = false}) {
  final result = _analyze(args);
  if (!reportOnly) _printCoverageConsole(result.coverage, includeNoise: args.noFilter);

  if (writeReport) {
    // --html (or an --out ending in .html) writes the self-contained HTML
    // report; otherwise the default Markdown report.
    final wantsHtml =
        args.html || (args.out?.toLowerCase().endsWith('.html') ?? false);
    if (wantsHtml) {
      final html = HtmlReport(
        result.coverage,
        parserName: result.parserName,
        topClusters: args.top,
        includeNoise: args.noFilter,
      ).render();
      final outPath = args.out ?? 'build/coverage.report.html';
      _writeFile(outPath, html);
      stdout.writeln('\n📊 HTML report written to $outPath');
      stdout.writeln('   Open it in a browser (it is fully self-contained).');
    } else {
      final md = MarkdownReport(
        result.coverage,
        parserName: result.parserName,
        topClusters: args.top,
        includeNoise: args.noFilter,
      ).render();
      final outPath = args.out ?? 'build/coverage.report.md';
      _writeFile(outPath, md);
      stdout.writeln('\n📝 Markdown report written to $outPath');
    }
  }

  _enforceMinCoverage(args, result.coverage.overallCoveragePercent);
}

/// CI gate: fail (exit 4) when overall coverage is below `--min-coverage`.
/// Pairs with `diff`'s drift exit (3) so a pipeline can gate on both staleness
/// and a coverage floor.
void _enforceMinCoverage(_Args args, double coverage) {
  final min = args.minCoverage;
  if (min == null) return;
  if (coverage + 1e-9 < min) {
    stdout.writeln('\n✗ Coverage ${coverage.toStringAsFixed(1)}% is below the '
        '--min-coverage threshold of ${min.toStringAsFixed(1)}%.');
    exitCode = 4;
  } else {
    stdout.writeln('\n✓ Coverage ${coverage.toStringAsFixed(1)}% meets the '
        '--min-coverage threshold of ${min.toStringAsFixed(1)}%.');
  }
}

void _writeFile(String path, String contents) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}

/// Breadth-first discovery: unlike `analyze`/`pull` (which target CBE by
/// default), `discover` looks at **every sender** and leads with candidate new
/// formats — the founding use case ("what am I missing, including banks I don't
/// parse?"). Source is a dataset file, or `--adb` to pull the whole inbox.
void _runDiscover(_Args args) {
  final adapter = _resolveAdapter(args);

  final List<SmsMessage> messages;
  if (args.adb) {
    final source =
        AdbSmsSource(adbPath: args.adbPath, deviceSerial: args.device);
    try {
      // Breadth-first: all senders unless the user explicitly scoped with --bank.
      messages = source.fetch(senderFilter: args.banks);
    } on AdbException catch (e) {
      throw _CliError(e.message);
    }
    if (messages.isEmpty) throw _CliError('No SMS pulled from device.');
    stdout.writeln('Pulled ${messages.length} message(s) from device '
        '(all senders)');
  } else if (args.positional.isNotEmpty) {
    messages = DatasetLoader.load(args.positional.first);
    stdout.writeln('Loaded ${messages.length} message(s) from '
        '${args.positional.first}');
  } else {
    throw _CliError('discover needs a dataset file or --adb. '
        'Usage: sms-pattern-lab discover <dataset.json> | --adb');
  }
  stdout.writeln('');

  final result =
      AnalysisPipeline(adapter: adapter, grouper: _grouper(args)).run(messages);
  _printDiscoveryConsole(result.coverage, args, includeNoise: args.noFilter);
  _enforceMinCoverage(args, result.coverage.overallCoveragePercent);
}

/// Discovery-first console: candidate new formats lead, then coverage.
void _printDiscoveryConsole(CoverageReport r, _Args args,
    {bool includeNoise = false}) {
  final candidates = [
    ...r.candidateFamilies,
    if (includeNoise)
      for (final c in r.noiseClusters) TemplateFamily([c]),
  ];

  stdout.writeln('═══ Candidate new formats (unrecognized senders) ═══');
  if (candidates.isEmpty) {
    stdout.writeln('  none — every unmatched message is attributable to a '
        'known bank.');
  } else {
    stdout.writeln('${candidates.length} distinct format(s) from senders no '
        'parser recognizes — likely banks/formats with no parser yet:');
    var i = 1;
    for (final f in candidates.take(args.top)) {
      stdout.writeln('  $i. [${f.priority} · regex:${f.regexReadiness}] '
          'x${f.totalOccurrences}'
          '${f.memberCount > 1 ? ' · ${f.memberCount} variants' : ''}');
      stdout.writeln('     ${f.template}');
      i++;
    }
    if (candidates.length > args.top) {
      stdout.writeln('  … ${candidates.length - args.top} more (--top=N).');
    }
  }
  if (!includeNoise && r.noiseClusters.isNotEmpty) {
    stdout.writeln('  (${r.noiseClusters.length} non-transaction cluster(s) '
        'hidden as noise — --no-filter to show)');
  }
  stdout.writeln('');
  stdout.writeln('═══ Coverage (known banks) ═══');
  stdout.writeln('Overall: ${r.overallCoveragePercent.toStringAsFixed(1)}% '
      '(${r.matched}/${r.total})');
  for (final p in r.parsers) {
    stdout.writeln('  ${_pad(p.bankName, 28)} '
        '${p.coveragePercent.toStringAsFixed(1).padLeft(6)}%  '
        '(${p.matched}/${p.total})');
  }
}

void _runStats(_Args args) {
  final result = _analyze(args);
  final s = result.statistics;

  if (args.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert({
      'total': s.totalMessages,
      'matched': s.matched,
      'unmatched': s.unmatched,
      'unattributed': s.unattributed,
      'matchRate': s.matchRate,
      'byTransactionType': s.byTransactionType,
      'byBank': s.byBank,
    }));
    return;
  }

  stdout.writeln('Dataset Statistics');
  stdout.writeln('==================');
  stdout.writeln('Total messages : ${s.totalMessages}');
  stdout.writeln('Matched        : ${s.matched} '
      '(${s.matchRate.toStringAsFixed(1)}%)');
  stdout.writeln('Unmatched      : ${s.unmatched}');
  stdout.writeln('Unattributed   : ${s.unattributed}');
  stdout.writeln('');
  stdout.writeln('By bank:');
  _printCountMap(s.byBank);
  stdout.writeln('');
  stdout.writeln('Matched by transaction type:');
  _printCountMap(s.byTransactionType);
}

void _runTemplates(_Args args) {
  final result = _analyze(args);
  final clusters = result.coverage.unmatchedClusters;
  if (clusters.isEmpty) {
    stdout.writeln('No unmatched templates — full coverage for this dataset.');
    return;
  }

  if (args.json) {
    stdout.writeln(const JsonEncoder.withIndent('  ').convert([
      for (final c in clusters.take(args.top))
        {
          'template': c.template,
          'occurrences': c.occurrences,
          'priority': c.priority,
          'likelyBank': c.likelyBankName,
          'examples': c.examples,
        }
    ]));
    return;
  }

  stdout.writeln('Unmatched Templates (top ${args.top})');
  stdout.writeln('=' * 40);
  var i = 1;
  for (final c in clusters.take(args.top)) {
    stdout.writeln('${i++}. [${c.priority}] x${c.occurrences}  '
        '(${c.likelyBankName ?? 'Unknown'})');
    stdout.writeln('   ${c.template}');
  }
  if (clusters.length > args.top) {
    stdout.writeln('\n... ${clusters.length - args.top} more '
        '(raise with --top=N).');
  }
}

void _runPull(_Args args) {
  final messages = _pullFromDevice(args);
  final outPath = args.out ?? 'build/device_sms.json';
  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert([for (final m in messages) m.toJson()])}\n');
  stdout.writeln('Pulled ${messages.length} message(s) from device '
      '${args.all ? '(all senders)' : 'for [${args.senderFilter().join(', ')}]'}');
  stdout.writeln('Wrote dataset to $outPath');

  if (args.analyzeAfter) {
    stdout.writeln('');
    final adapter = _resolveAdapter(args);
    final result =
        AnalysisPipeline(adapter: adapter, grouper: _grouper(args)).run(messages);
    _printCoverageConsole(result.coverage, includeNoise: args.noFilter);
  } else {
    stdout.writeln('Next: sms-pattern-lab analyze $outPath');
  }
}

void _runDevices(_Args args) {
  final source = AdbSmsSource(adbPath: args.adbPath);
  try {
    final devices = source.devices();
    if (devices.isEmpty) {
      stdout.writeln('No devices attached (is USB debugging enabled?).');
      return;
    }
    stdout.writeln('Attached devices:');
    for (final d in devices) {
      stdout.writeln('  $d');
    }
  } on AdbException catch (e) {
    throw _CliError(e.message);
  }
}

void _runBaseline(_Args args) {
  final adapter = _resolveAdapter(args);
  final baseline = adapter.baseline(sourceLabel: _snapshotProvenance());

  stdout.writeln('Baseline — the frame of reference for coverage reports');
  stdout.writeln('=' * 54);
  if (baseline.sourceLabel != null) {
    stdout.writeln('Source     : ${baseline.sourceLabel}');
  }
  stdout.writeln('Signature  : ${baseline.signature}');
  stdout.writeln('Patterns   : ${baseline.patternCount} '
      '(${adapter.invalidPatternCount} invalid)');
  stdout.writeln('Banks      : ${baseline.bankCount}');
  stdout.writeln('');
  stdout.writeln('Patterns per bank:');
  final perBank = baseline.patternsPerBank().entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in perBank) {
    final name = adapter.bankShortName(e.key) ?? 'Bank #${e.key}';
    stdout.writeln('  ${_pad(name, 28)} ${e.value}');
  }
  stdout.writeln('');
  stdout.writeln('Coverage reports are measured *relative to* this baseline. '
      'Run `diff` to check it against the live app.');

  if (args.record) {
    stdout.writeln('');
    _recordBaseline(adapter, args, note: args.note);
  } else {
    stdout.writeln('Tip: `baseline --record` appends this to the history '
        'ledger (${_relativeHistoryPath(args)}).');
  }
}

/// Append the adapter's current baseline to the history ledger (dedup against
/// the current head). Used by `baseline --record` and after `diff --refresh`.
void _recordBaseline(TotalsParserAdapter adapter, _Args args,
    {String? note}) {
  final path = _historyPath(args);
  final history = BaselineHistory.load(path);
  final record = _currentRecord(adapter, note: note);
  final appended = history.record(record);
  if (!appended) {
    stdout.writeln('History unchanged — baseline ${record.signature} is '
        'already the current head (${history.entries.length} record(s)).');
    return;
  }
  history.save(path);
  stdout.writeln('📌 Recorded baseline ${record.signature} to '
      '${_relativeHistoryPath(args)} '
      '(now ${history.entries.length} record(s)).');
}

BaselineRecord _currentRecord(TotalsParserAdapter adapter, {String? note}) {
  final b = adapter.baseline(sourceLabel: _snapshotProvenance());
  final perBank = <String, int>{};
  b.patternsPerBank().forEach((id, count) {
    perBank[adapter.bankShortName(id) ?? 'Bank #$id'] = count;
  });
  final rev = RegExp(r'rev ([0-9a-f]+)').firstMatch(b.sourceLabel ?? '')?.group(1);
  return BaselineRecord(
    signature: b.signature,
    recordedAt: DateTime.now().toIso8601String(),
    patternCount: b.patternCount,
    bankCount: b.bankCount,
    totalsRev: rev,
    source: b.sourceLabel,
    note: note,
    patternsPerBank: perBank,
  );
}

void _runHistory(_Args args) {
  final path = _historyPath(args);
  final history = BaselineHistory.load(path);
  if (history.isEmpty) {
    stdout.writeln('No baseline history yet at ${_relativeHistoryPath(args)}.');
    stdout.writeln('Record the current baseline with: '
        'sms-pattern-lab baseline --record');
    return;
  }

  stdout.writeln('Baseline history — ${_relativeHistoryPath(args)} '
      '(${history.entries.length} record(s))');
  stdout.writeln('=' * 72);
  stdout.writeln('${_pad('#', 3)}${_pad('Date', 20)}'
      '${_pad('Signature', 19)}${_pad('Patterns', 10)}${_pad('Δ', 6)}Note');
  var prev = 0;
  for (var i = 0; i < history.entries.length; i++) {
    final e = history.entries[i];
    final delta = i == 0 ? 0 : e.patternCount - prev;
    final deltaStr = i == 0
        ? '—'
        : (delta > 0 ? '+$delta' : (delta == 0 ? '0' : '$delta'));
    final date = e.recordedAt.length >= 10 ? e.recordedAt.substring(0, 10) : e.recordedAt;
    stdout.writeln('${_pad('${i + 1}', 3)}${_pad(date, 20)}'
        '${_pad(e.signature, 19)}${_pad('${e.patternCount}', 10)}'
        '${_pad(deltaStr, 6)}${e.note ?? ''}');
    prev = e.patternCount;
  }
  stdout.writeln('');
  stdout.writeln('current: ${history.currentSignature}');
}

void _runDiff(_Args args) {
  final adapter = _resolveAdapter(args);
  final current = adapter.baseline(sourceLabel: _snapshotProvenance());

  final source = _loadSourceBaseline(args);
  final diff = BaselineDiff.compare(current, source.baseline);

  stdout.writeln('Baseline drift check');
  stdout.writeln('=' * 54);
  stdout.writeln('Vendored baseline : ${current.patternCount} patterns, '
      '${current.bankCount} banks · sig ${current.signature}');
  stdout.writeln('Live source       : ${source.baseline.patternCount} '
      'patterns, ${source.baseline.bankCount} banks · '
      'sig ${source.baseline.signature}');
  stdout.writeln('   from: ${source.label}');
  stdout.writeln('');

  // Logic drift (regex flags, cleanSmsText, sender normalization, heuristic) —
  // only checkable when --from points at app source.
  final logicDrift = _printLogicFidelity(source.appDir);
  if (logicDrift) stdout.writeln('');

  if (!diff.isDirty) {
    if (logicDrift) {
      stdout.writeln('Patterns are in sync, but the parser LOGIC drifted '
          '(above). Re-verify the adapter mirrors it, then re-run '
          'vendor_patterns to update the fidelity snapshot.');
      exitCode = 3;
    } else {
      stdout.writeln('✓ Up to date — the vendored baseline matches the live '
          'app. Coverage reports reflect current parser logic.');
    }
    return;
  }

  if (diff.added.isNotEmpty) {
    stdout.writeln('+ ${diff.added.length} new pattern(s) in the app '
        '(coverage reports built on the old baseline would still flag these '
        'formats as missing):');
    for (final p in diff.added) {
      stdout.writeln('   [${adapter.bankShortName(p.bankId) ?? p.bankId}] '
          '${p.description.isEmpty ? '(no description)' : p.description}');
      stdout.writeln('       ${_truncate(p.regex, 88)}');
    }
    stdout.writeln('');
  }
  if (diff.changed.isNotEmpty) {
    stdout.writeln('~ ${diff.changed.length} changed pattern(s):');
    for (final e in diff.changed) {
      stdout.writeln('   [${adapter.bankShortName(e.bankId) ?? e.bankId}] '
          '${e.description.isEmpty ? '(no description)' : e.description}');
    }
    stdout.writeln('');
  }
  if (diff.removed.isNotEmpty) {
    stdout.writeln('- ${diff.removed.length} pattern(s) removed from the app:');
    for (final p in diff.removed) {
      stdout.writeln('   [${adapter.bankShortName(p.bankId) ?? p.bankId}] '
          '${p.description.isEmpty ? '(no description)' : p.description}');
    }
    stdout.writeln('');
  }

  if (args.refresh) {
    _refreshSnapshot(source.appDir);
    stdout.writeln('↻ Snapshot refreshed from ${source.appDir}.');
    // The vendored files changed on disk; load the fresh baseline and record
    // the transition in the history ledger.
    final refreshed = TotalsParserAdapter.vendored();
    if (refreshed != null) {
      _recordBaseline(refreshed, args,
          note: args.note ?? 'refreshed from ${source.appDir}');
    }
    stdout.writeln('Re-run your coverage report to reflect the new baseline.');
  } else {
    stdout.writeln('⚠ Baseline is STALE (${diff.totalChanges} change'
        '${diff.totalChanges == 1 ? '' : 's'}). Refresh with:');
    stdout.writeln('    sms-pattern-lab diff --from=${args.from ?? '../totals/app'} --refresh');
    stdout.writeln('  or: dart run tool/vendor_patterns.dart '
        '--from=${args.from ?? '../totals/app'}');
    exitCode = 3; // drift → non-zero, so CI / git hooks can gate on it
  }
}

/// Resolve the history ledger path: `--history` override, else
/// `<packageRoot>/baseline_history.json`.
String _historyPath(_Args args) =>
    args.history ?? '${_packageRoot()}/baseline_history.json';

String _relativeHistoryPath(_Args args) {
  final p = _historyPath(args);
  final cwd = Directory.current.path;
  return p.startsWith('$cwd/') ? p.substring(cwd.length + 1) : p;
}

/// Find the package root (the dir containing pubspec.yaml) by walking up from
/// the running script, then the current directory. Falls back to cwd.
String _packageRoot() {
  final starts = <String>[];
  try {
    if (Platform.script.scheme == 'file') {
      starts.add(File(Platform.script.toFilePath()).parent.path);
    }
  } catch (_) {/* ignore */}
  starts.add(Directory.current.path);

  for (final start in starts) {
    var dir = Directory(start);
    for (var i = 0; i < 6; i++) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  return Directory.current.path;
}

/// Compare the live app's parsing-LOGIC signature against the vendored
/// `fidelity.json`. Returns true if it drifted. Prints a status line either way
/// (or nothing if the app source isn't available, e.g. `--against` a file).
bool _printLogicFidelity(String appDir) {
  final live = LogicFidelity.fromAppDir(appDir);
  if (live == null) return false; // no app source → can't check
  final vendorDir = TotalsParserAdapter.vendoredDir();
  final f = vendorDir == null ? null : File('$vendorDir/fidelity.json');
  if (f == null || !f.existsSync()) {
    stdout.writeln('Parser logic      : no fidelity snapshot yet — run '
        '`dart run tool/vendor_patterns.dart` to capture one.');
    return false;
  }
  final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final expectedSig = (json['signature'] ?? '').toString();
  final expectedProbes = (json['probes'] as Map?)
          ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
      const <String, String>{};
  if (expectedSig == live.signature) {
    stdout.writeln('Parser logic      : ✓ in sync · sig ${live.signature}');
    return false;
  }
  stdout.writeln('⚠ Parser LOGIC drifted — vendored $expectedSig vs live '
      '${live.signature}');
  final drifted = live.driftedAgainst(expectedProbes);
  stdout.writeln('  changed: ${drifted.join(', ')}');
  stdout.writeln('  The lab mirrors this logic by hand (REFERENCE → Fidelity). '
      'Re-verify the adapter still matches, then re-run vendor_patterns.');
  return true;
}

/// Read provenance (rev/date) from the vendored SNAPSHOT.md, if present.
String? _snapshotProvenance() {
  final dir = TotalsParserAdapter.vendoredDir();
  if (dir == null) return null;
  final f = File('$dir/SNAPSHOT.md');
  if (!f.existsSync()) return 'vendored snapshot';
  final text = f.readAsStringSync();
  final rev = RegExp(r'git rev:\s*\*\*([0-9a-f]+)\*\*').firstMatch(text)?.group(1);
  final date = RegExp(r'Date:\s*([0-9-]+)').firstMatch(text)?.group(1);
  final bits = [
    'vendored snapshot',
    if (rev != null) 'Totals rev $rev',
    if (date != null) date,
  ];
  return bits.join(' · ');
}

class _SourceBaseline {
  final ParserBaseline baseline;
  final String label;
  final String appDir;
  _SourceBaseline(this.baseline, this.label, this.appDir);
}

/// Load the "live" baseline to diff against, from `--from=<totals/app>` (default
/// ../totals/app) or `--against=<sms_patterns.json>` (banks optional).
_SourceBaseline _loadSourceBaseline(_Args args) {
  String banksPath;
  String patternsPath;
  String appDir;

  if (args.against != null) {
    patternsPath = args.against!;
    // Reuse vendored banks for naming/count when only patterns are given.
    final vendor = TotalsParserAdapter.vendoredDir();
    banksPath = vendor == null ? args.against! : '$vendor/banks.json';
    appDir = File(patternsPath).parent.path;
  } else {
    appDir = args.from ?? '../totals/app';
    banksPath = '$appDir/assets/banks.json';
    patternsPath = '$appDir/assets/sms_patterns.json';
  }

  if (!File(patternsPath).existsSync()) {
    throw _CliError('Live source not found at "$patternsPath". '
        'Pass --from=<path/to/totals/app> or --against=<sms_patterns.json>.');
  }

  final adapter = TotalsParserAdapter.fromFiles(
    banksPath: File(banksPath).existsSync() ? banksPath : patternsPath,
    patternsPath: patternsPath,
  );
  return _SourceBaseline(
    adapter.baseline(sourceLabel: appDir),
    patternsPath,
    appDir,
  );
}

void _refreshSnapshot(String appDir) {
  final vendor = TotalsParserAdapter.vendoredDir() ?? 'vendor/totals';
  Directory(vendor).createSync(recursive: true);
  for (final name in ['banks.json', 'sms_patterns.json']) {
    final src = File('$appDir/assets/$name');
    if (src.existsSync()) src.copySync('$vendor/$name');
  }
  // Refresh the logic-fidelity snapshot too, so the next `diff` is in sync on
  // both data and logic.
  final fidelity = LogicFidelity.fromAppDir(appDir);
  if (fidelity != null) {
    File('$vendor/fidelity.json').writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({
              'signature': fidelity.signature,
              'probes': fidelity.probeHashes,
            })}\n');
  }
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 1)}…';

void _runCorpus(_Args args) {
  if (args.positional.length < 2) {
    throw _CliError('corpus needs at least two dataset files to merge.\n'
        'Usage: sms-pattern-lab corpus a.json b.json [...] [--out=corpus.json]');
  }
  final quality = DataQuality();
  final sources = [
    for (final p in args.positional) DatasetLoader.load(p, quality: quality)
  ];
  final result = Corpus.merge(sources);

  // Stamp the corpus with the parser baseline it's meant to be analyzed
  // against (best-effort — the corpus itself is parser-agnostic), so a merged
  // corpus, its datasetId, and later exports/coverage all share the same
  // baseline + dataset keys. This is the corpus↔baseline↔drift tie-in.
  String? baselineSignature;
  String? baselineSource;
  try {
    final b = _resolveAdapter(args).baseline(sourceLabel: _snapshotProvenance());
    baselineSignature = b.signature;
    baselineSource = b.sourceLabel;
  } catch (_) {/* no parser definitions available; signature stays null */}

  final outPath = args.out ?? 'build/corpus.json';
  _writeFile(
      outPath,
      '${const JsonEncoder.withIndent('  ').convert({
            'version': 1,
            'datasetId': result.datasetId,
            if (baselineSignature != null) 'baselineSignature': baselineSignature,
            if (baselineSource != null) 'baselineSource': baselineSource,
            'sourceCount': args.positional.length,
            'totalInput': result.totalInput,
            'unique': result.uniqueCount,
            'duplicatesRemoved': result.duplicatesRemoved,
            'messages': [for (final m in result.messages) m.toJson()],
          })}\n');

  stdout.writeln('Merged ${args.positional.length} source(s):');
  for (var i = 0; i < args.positional.length; i++) {
    stdout.writeln('  ${_pad(args.positional[i], 44)} '
        '${result.perSourceCounts[i]}');
  }
  stdout.writeln('');
  stdout.writeln('Total in  : ${result.totalInput}');
  stdout.writeln('Unique    : ${result.uniqueCount} '
      '(${result.duplicatesRemoved} duplicate(s) removed)');
  if (quality.datasetMalformed + quality.datasetEmptyBodies > 0) {
    stdout.writeln('Skipped   : ${quality.datasetMalformed} malformed, '
        '${quality.datasetEmptyBodies} empty');
  }
  stdout.writeln('Dataset id: ${result.datasetId}');
  if (baselineSignature != null) {
    stdout.writeln('Baseline  : $baselineSignature');
  }
  stdout.writeln('Wrote corpus → $outPath');

  if (args.analyzeAfter) {
    stdout.writeln('');
    final adapter = _resolveAdapter(args);
    final cov = AnalysisPipeline(adapter: adapter).run(result.messages).coverage;
    _printCoverageConsole(cov, includeNoise: args.noFilter);
  } else {
    stdout.writeln('Next: sms-pattern-lab analyze $outPath');
  }
}

void _runCompare() {
  stdout.writeln('`compare` is reserved for the Version 5 roadmap '
      '(historical coverage comparison / regression detection).');
  stdout.writeln('It is not implemented in this release.');
}

// --- console rendering -----------------------------------------------------

void _printCoverageConsole(CoverageReport r, {bool includeNoise = false}) {
  stdout.writeln('Overall coverage: '
      '${r.overallCoveragePercent.toStringAsFixed(1)}% '
      '(${r.matched}/${r.total})');
  stdout.writeln('');
  stdout.writeln('Parser coverage (worst first):');
  for (final p in r.parsers) {
    stdout.writeln('  ${_pad(p.bankName, 28)} '
        '${p.coveragePercent.toStringAsFixed(1).padLeft(6)}%  '
        '(${p.matched}/${p.total})');
  }

  final attributed = r.attributedFamilies;
  if (attributed.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('Top missing templates (known banks):');
    for (final f in attributed.take(5)) {
      stdout.writeln('  [${f.priority} · regex:${f.regexReadiness}] '
          'x${f.totalOccurrences}  ${f.likelyBankName ?? 'Unknown'}'
          '${f.memberCount > 1 ? ' · ${f.memberCount} variants' : ''}');
      stdout.writeln('      ${f.template}');
    }
  }

  // Discovery signal: formats from senders no parser recognizes.
  final candidates = [
    ...r.candidateFamilies,
    if (includeNoise)
      for (final c in r.noiseClusters) TemplateFamily([c]),
  ];
  if (candidates.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('⚑ Candidate new formats (unrecognized sender) — '
        '${candidates.length} distinct:');
    for (final f in candidates.take(5)) {
      stdout.writeln('  [${f.priority} · regex:${f.regexReadiness}] '
          'x${f.totalOccurrences}'
          '${f.memberCount > 1 ? ' · ${f.memberCount} variants' : ''}');
      stdout.writeln('      ${f.template}');
    }
    stdout.writeln('  → likely a format/bank with no parser yet. '
        '(Pull with --all to surface more.)');
  }
  if (!includeNoise && r.noiseClusters.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('  (${r.noiseClusters.length} non-transaction cluster(s) '
        'hidden as noise — --no-filter to show)');
  }
}

void _printCountMap(Map<String, int> map) {
  final entries = map.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (entries.isEmpty) {
    stdout.writeln('  (none)');
    return;
  }
  for (final e in entries) {
    stdout.writeln('  ${_pad(e.key, 28)} ${e.value}');
  }
}

String _pad(String s, int width) =>
    s.length >= width ? s : s + ' ' * (width - s.length);

// --- adapter resolution ----------------------------------------------------

TotalsParserAdapter _resolveAdapter(_Args args) {
  try {
    return TotalsParserAdapter.resolveDefault(
      banksPath: args.banksPath,
      patternsPath: args.patternsPath,
    );
  } on ArgumentError catch (e) {
    throw _CliError(e.message.toString());
  } on StateError catch (e) {
    throw _CliError(e.message);
  }
}

// --- usage -----------------------------------------------------------------

void _printUsage() {
  stdout.writeln('''
SMS Pattern Lab v$_version — parser diagnostics & pattern discovery

USAGE
  sms-pattern-lab <command> [dataset.json] [options]

COMMANDS
  analyze [dataset]    Run the full pipeline; print coverage + write a report
  report  [dataset]    Generate the Markdown coverage report file
  stats   [dataset]    Print dataset-level statistics
  templates [dataset]  List prioritized unmatched template clusters
  discover [dataset]   Breadth-first discovery (ALL senders); leads with
                       candidate new formats. Use --adb to pull the whole inbox
  pull                 Pull SMS from a connected device (adb) into a dataset
  devices              List attached adb devices
  baseline             Show the parser baseline reports are measured against
                       (add --record to append it to the history ledger)
  diff                 Check the vendored baseline against the live app (drift)
  history              Show the recorded baseline-signature history
  corpus <a> <b>...     Merge + dedup several datasets into one (with a dataset id)
  export [dataset]     Emit the privacy-safe enrichment artifact (normalized
                       text + action verb + shape profile per gap; no raw
                       values) for contributors to share. Add --preview to review
  compare              (Roadmap V5) historical coverage comparison
  help                 Show this help
  version              Print version

  For analyze/report/stats/templates, pass a dataset file OR use --adb to pull
  live from a connected device instead.

OPTIONS
  --adb                Pull SMS live from a connected device instead of a file
  --all                With --adb/pull: keep all senders (default: CBE only)
  --device=<serial>    Target a specific adb device (see `devices`)
  --adb-path=<path>    Path to the adb executable      (default: adb on PATH)
  --analyze            With `pull`: analyze immediately after pulling
  --banks=<path>       Path to banks.json    (default: vendored snapshot)
  --patterns=<path>    Path to sms_patterns.json (default: vendored snapshot)
  --html               Write a self-contained HTML report (charts, offline)
  --from=<path>        `diff`: live Totals app dir   (default: ../totals/app)
  --against=<path>     `diff`: a specific sms_patterns.json to compare against
  --refresh            `diff`: re-vendor the snapshot from the live source
  --record             `baseline`: append the current baseline to history
  --note=<text>        `baseline`/`diff`: note stored with the recorded entry
  --history=<path>     History ledger file (default: baseline_history.json)
  --no-filter          Keep non-transaction messages (OTPs, promos, notices);
                       default drops them as noise before analysis
  --min-coverage=<n>   `analyze`: exit non-zero (4) if coverage < n% (CI gate)
  --group=<mode>       Family grouping: identity (default, 1/cluster) | verb
                       (action-verb + direction, e.g. "Outgoing transfers") |
                       levenshtein (verb buckets refined by wording similarity)
  --similarity=<r>     levenshtein merge threshold, 0..1  (default: 0.9)
  --preview            `export`: also print a human-readable summary of exactly
                       what would be shared, before it leaves the device
  --out=<path>         Output path (report, dataset for `pull`, or export JSON)
  --top=<n>            Max clusters to show/emit  (default: 25)
  --json               Emit machine-readable JSON (stats/templates)

EXIT CODES
  0 ok · 1 error · 3 baseline drift (`diff`) · 4 below --min-coverage (`analyze`)

EXAMPLES
  sms-pattern-lab analyze example/cbe_sms.json
  sms-pattern-lab discover --adb              # all senders, discovery-first
  sms-pattern-lab analyze example/cbe_sms.json --html        # HTML report
  sms-pattern-lab analyze example/cbe_sms.json --group=verb  # semantic families
  sms-pattern-lab export example/cbe_sms.json --preview      # privacy-safe share
  sms-pattern-lab pull --analyze              # pull CBE SMS from phone + analyze
  sms-pattern-lab pull --all --out=all.json   # dump every SMS to a dataset
  sms-pattern-lab analyze --adb --html        # fetch live, write HTML report
  sms-pattern-lab devices                     # which phones are connected?
  sms-pattern-lab baseline --record           # frame of reference + log it
  sms-pattern-lab diff --from=../totals/app   # is the baseline stale?
  sms-pattern-lab history                     # how the baseline evolved
''');
}

// --- minimal arg parsing (zero dependencies) -------------------------------

class _Args {
  final String? command;
  final List<String> positional;
  final String? banksPath;
  final String? patternsPath;
  final String? out;
  final int top;
  final bool json;
  final bool adb;
  final bool all;
  final bool analyzeAfter;
  final bool html;
  final bool refresh;
  final bool record;
  final bool noFilter;
  final bool preview;
  final String? note;
  final String? history;
  final String? device;
  final String adbPath;
  final String? from;
  final String? against;
  final double? minCoverage;

  /// Similarity grouper to use: `identity` (V1 default, 1 family/cluster),
  /// `verb` (V2 step 1 SemanticVerbGrouper), or `levenshtein` (V2 step 2: verb
  /// buckets refined by wording). See ROADMAP_NOTES §3.
  final String grouping;

  /// Levenshtein merge threshold for `--group=levenshtein` (0..1, default 0.9).
  final double similarity;

  /// Sender codes to keep when pulling from a device. CBE-only for now, per the
  /// current focus; override with --bank=CODE (repeatable) or --all.
  final List<String> banks;

  _Args({
    required this.command,
    required this.positional,
    required this.banksPath,
    required this.patternsPath,
    required this.out,
    required this.top,
    required this.json,
    required this.adb,
    required this.all,
    required this.analyzeAfter,
    required this.html,
    required this.refresh,
    required this.record,
    required this.noFilter,
    required this.preview,
    required this.note,
    required this.history,
    required this.device,
    required this.adbPath,
    required this.from,
    required this.against,
    required this.minCoverage,
    required this.grouping,
    required this.similarity,
    required this.banks,
  });

  List<String> senderFilter() => banks.isEmpty ? const ['CBE'] : banks;

  static _Args parse(List<String> argv) {
    String? command;
    final positional = <String>[];
    String? banksPath;
    String? patterns;
    String? out;
    var top = 25;
    var json = false;
    var adb = false;
    var all = false;
    var analyzeAfter = false;
    var html = false;
    var refresh = false;
    var record = false;
    var noFilter = false;
    var preview = false;
    String? note;
    String? history;
    String? device;
    var adbPath = 'adb';
    String? from;
    String? against;
    double? minCoverage;
    var grouping = 'identity';
    var similarity = 0.9;
    final bankCodes = <String>[];

    for (final arg in argv) {
      if (arg.startsWith('--')) {
        final eq = arg.indexOf('=');
        final key = eq == -1 ? arg.substring(2) : arg.substring(2, eq);
        final value = eq == -1 ? null : arg.substring(eq + 1);
        switch (key) {
          case 'banks':
            banksPath = value;
            break;
          case 'patterns':
            patterns = value;
            break;
          case 'out':
            out = value;
            break;
          case 'top':
            top = int.tryParse(value ?? '') ?? top;
            break;
          case 'json':
            json = true;
            break;
          case 'adb':
            adb = true;
            break;
          case 'all':
            all = true;
            break;
          case 'analyze':
            analyzeAfter = true;
            break;
          case 'html':
            html = true;
            break;
          case 'refresh':
            refresh = true;
            break;
          case 'no-filter':
            noFilter = true;
            break;
          case 'preview':
            preview = true;
            break;
          case 'record':
            record = true;
            break;
          case 'note':
            note = value;
            break;
          case 'history':
            history = value;
            break;
          case 'from':
            from = value;
            break;
          case 'against':
            against = value;
            break;
          case 'min-coverage':
            minCoverage = double.tryParse(value ?? '');
            break;
          case 'group':
            if (value != null) grouping = value.toLowerCase();
            break;
          case 'similarity':
            similarity = double.tryParse(value ?? '') ?? similarity;
            break;
          case 'device':
            device = value;
            break;
          case 'adb-path':
            if (value != null) adbPath = value;
            break;
          case 'bank':
            if (value != null) bankCodes.add(value);
            break;
          case 'help':
            command = 'help';
            break;
          default:
            stderr.writeln('Warning: ignoring unknown option --$key');
        }
      } else if (command == null) {
        command = arg;
      } else {
        positional.add(arg);
      }
    }

    return _Args(
      command: command,
      positional: positional,
      banksPath: banksPath,
      patternsPath: patterns,
      out: out,
      top: top,
      json: json,
      adb: adb,
      all: all,
      analyzeAfter: analyzeAfter,
      html: html,
      refresh: refresh,
      record: record,
      noFilter: noFilter,
      preview: preview,
      note: note,
      history: history,
      device: device,
      adbPath: adbPath,
      from: from,
      against: against,
      minCoverage: minCoverage,
      grouping: grouping,
      similarity: similarity,
      banks: bankCodes,
    );
  }
}

class _CliError implements Exception {
  final String message;
  _CliError(this.message);
}
