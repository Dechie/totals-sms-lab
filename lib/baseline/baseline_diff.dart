import 'parser_baseline.dart';

/// A pattern present in the source but not the baseline (or vice-versa).
class PatternDelta {
  final int bankId;
  final String description;
  final String regex;
  const PatternDelta(this.bankId, this.description, this.regex);
}

/// A pattern whose regex changed under the same logical identity.
class PatternEdit {
  final int bankId;
  final String description;
  final List<String> oldRegexes;
  final List<String> newRegexes;
  const PatternEdit(
      this.bankId, this.description, this.oldRegexes, this.newRegexes);
}

/// The difference between a `current` baseline (what the lab measured against)
/// and a `source` baseline (the live app's definitions).
///
/// "Added" patterns are the important ones for the drift problem: they are
/// formats the app *now* handles, so coverage reports built on the old baseline
/// would still wrongly list them as missing until the snapshot is refreshed.
class BaselineDiff {
  final List<PatternDelta> added;
  final List<PatternDelta> removed;
  final List<PatternEdit> changed;

  const BaselineDiff({
    required this.added,
    required this.removed,
    required this.changed,
  });

  bool get isDirty =>
      added.isNotEmpty || removed.isNotEmpty || changed.isNotEmpty;

  int get totalChanges => added.length + removed.length + changed.length;

  static BaselineDiff compare(ParserBaseline current, ParserBaseline source) {
    final cur = _groupByKey(current);
    final src = _groupByKey(source);
    final keys = {...cur.keys, ...src.keys};

    final added = <PatternDelta>[];
    final removed = <PatternDelta>[];
    final changed = <PatternEdit>[];

    for (final key in keys) {
      final c = cur[key];
      final s = src[key];

      if (c == null) {
        // Entire logical pattern is new in source.
        for (final p in s!) {
          added.add(PatternDelta(p.bankId, p.description, p.regex));
        }
      } else if (s == null) {
        for (final p in c) {
          removed.add(PatternDelta(p.bankId, p.description, p.regex));
        }
      } else {
        final curRegexes = c.map((p) => p.regex).toSet();
        final srcRegexes = s.map((p) => p.regex).toSet();
        final newRegexes = srcRegexes.difference(curRegexes).toList();
        final goneRegexes = curRegexes.difference(srcRegexes).toList();
        if (newRegexes.isEmpty && goneRegexes.isEmpty) continue; // identical
        changed.add(PatternEdit(
          c.first.bankId,
          c.first.description,
          goneRegexes,
          newRegexes,
        ));
      }
    }

    int byBank(a, b) => a.bankId.compareTo(b.bankId);
    added.sort(byBank);
    removed.sort(byBank);
    changed.sort((a, b) => a.bankId.compareTo(b.bankId));

    return BaselineDiff(added: added, removed: removed, changed: changed);
  }

  static Map<String, List<PatternFingerprint>> _groupByKey(ParserBaseline b) {
    final map = <String, List<PatternFingerprint>>{};
    for (final p in b.patterns) {
      map.putIfAbsent(p.key, () => []).add(p);
    }
    return map;
  }
}
