/// The generalized shape of one field: a privacy-safe regex describing the
/// *grammar* of the values a placeholder stripped, plus how many samples backed
/// it. Never the values themselves (FIELD_SHAPES.md).
class FieldShape {
  final String regex;
  final int samples;
  const FieldShape(this.regex, this.samples);

  Map<String, dynamic> toJson() => {'regex': regex, 'samples': samples};

  @override
  String toString() => '$regex (×$samples)';

  @override
  bool operator ==(Object other) =>
      other is FieldShape && other.regex == regex && other.samples == samples;

  @override
  int get hashCode => Object.hash(regex, samples);
}

/// Turns the raw spans a placeholder replaced into a generalized, privacy-safe
/// regex (FIELD_SHAPES.md). Deterministic and locale-free.
///
/// Strategy: run-length-encode each sample into character-class runs
/// (`\d`, `[A-Za-z]`, or a literal separator), then **union across samples**:
///   * samples that share a run *structure* collapse into one regex with
///     `{min,max}` quantifiers,
///   * a few distinct structures become an alternation `(?:a|b)`,
///   * too many structures — or too few samples to safely generalize — degrade
///     to a coarse class `[…]{min,max}` / `[…]+`, never an exact fingerprint.
class ShapeProfiler {
  /// Below this many *distinct* sample values, emit a coarse class rather than
  /// an exact shape — one specimen's exact grammar can re-identify.
  static const minSamplesToGeneralize = 3;

  /// Above this many distinct run-structures, an alternation is noise; fall
  /// back to a coarse class.
  static const maxAlternatives = 4;

  /// Samples longer than this are truncated before shape derivation, to bound
  /// the work on a pathological value. The grammar of the head is representative
  /// enough for a coarse class.
  static const maxSampleLen = 512;

  /// Profile every field in [spansByField]; fields with no spans are skipped.
  static Map<String, FieldShape> profileAll(
      Map<String, List<String>> spansByField) {
    final out = <String, FieldShape>{};
    // Sorted keys → deterministic output ordering.
    final keys = spansByField.keys.toList()..sort();
    for (final field in keys) {
      final samples = spansByField[field]!;
      if (samples.isEmpty) continue;
      out[field] = profile(samples);
    }
    return out;
  }

  /// Generalize a single field's raw [samples] into a [FieldShape].
  ///
  /// Total by contract: any unexpected input degrades to a coarse `.+` (with the
  /// real sample count) rather than throwing or emitting a misleading exact
  /// shape — an honest "some value here, structure unknown".
  static FieldShape profile(List<String> rawSamples) {
    try {
      return _profile(rawSamples);
    } catch (_) {
      return FieldShape('.+', rawSamples.length);
    }
  }

  static FieldShape _profile(List<String> rawSamples) {
    final n = rawSamples.length;
    // Bound work on pathological values.
    final samples = [
      for (final s in rawSamples)
        s.length > maxSampleLen ? s.substring(0, maxSampleLen) : s
    ];
    final distinct = samples.toSet();

    // Too few distinct values to generalize safely → coarse "one or more".
    if (distinct.length < minSamplesToGeneralize) {
      return FieldShape(_coarseClass(samples, quantifier: '+'), n);
    }

    // Group distinct samples by run-structure signature.
    final byStructure = <String, List<List<_Run>>>{};
    for (final s in distinct) {
      final runs = _encode(s);
      (byStructure[_signature(runs)] ??= []).add(runs);
    }

    if (byStructure.length > maxAlternatives) {
      return FieldShape(_coarseRange(samples), n);
    }

    final alternatives = byStructure.values.map(_generalizeGroup).toList()
      ..sort();
    final regex =
        alternatives.length == 1 ? alternatives.first : '(?:${alternatives.join('|')})';
    return FieldShape(regex, n);
  }

  // --- run-length encoding ---------------------------------------------------

  static List<_Run> _encode(String s) {
    final runs = <_Run>[];
    for (final unit in s.runes) {
      final ch = String.fromCharCode(unit);
      final cls = _classOf(unit);
      final litChar = cls == _Class.literal ? ch : null;
      if (runs.isNotEmpty &&
          runs.last.cls == cls &&
          runs.last.literal == litChar) {
        runs.last.len++;
      } else {
        runs.add(_Run(cls, litChar));
      }
    }
    return runs;
  }

  static _Class _classOf(int unit) {
    if (unit >= 0x30 && unit <= 0x39) return _Class.digit;
    if ((unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A)) {
      return _Class.letter;
    }
    return _Class.literal;
  }

  static String _signature(List<_Run> runs) =>
      runs.map((r) => r.cls == _Class.literal ? 'L${r.literal}' : r.cls.name)
          .join('|');

  /// Union same-structure samples: per run position, min/max length → quantifier.
  static String _generalizeGroup(List<List<_Run>> group) {
    final width = group.first.length;
    final buf = StringBuffer();
    for (var i = 0; i < width; i++) {
      var min = group.first[i].len, max = min;
      for (final runs in group) {
        final l = runs[i].len;
        if (l < min) min = l;
        if (l > max) max = l;
      }
      buf.write(_token(group.first[i], min, max));
    }
    return buf.toString();
  }

  static String _token(_Run run, int min, int max) {
    final base = switch (run.cls) {
      _Class.digit => r'\d',
      _Class.letter => '[A-Za-z]',
      _Class.literal => _escape(run.literal!),
    };
    return '$base${_quantifier(min, max)}';
  }

  static String _quantifier(int min, int max) {
    if (min == 1 && max == 1) return '';
    if (min == max) return '{$min}';
    return '{$min,$max}';
  }

  // --- coarse fallbacks ------------------------------------------------------

  /// `[classes]<quantifier>` — a class union of everything seen, no structure.
  static String _coarseClass(Iterable<String> samples, {required String quantifier}) =>
      '${_classUnion(samples)}$quantifier';

  /// `[classes]{minLen,maxLen}` — class union bounded by observed total lengths.
  static String _coarseRange(List<String> samples) {
    var min = samples.first.length, max = min;
    for (final s in samples) {
      if (s.length < min) min = s.length;
      if (s.length > max) max = s.length;
    }
    return '${_classUnion(samples)}${_quantifier(min, max)}';
  }

  static String _classUnion(Iterable<String> samples) {
    var hasDigit = false, hasLetter = false;
    final literals = <String>{};
    for (final s in samples) {
      for (final unit in s.runes) {
        switch (_classOf(unit)) {
          case _Class.digit:
            hasDigit = true;
          case _Class.letter:
            hasLetter = true;
          case _Class.literal:
            literals.add(String.fromCharCode(unit));
        }
      }
    }
    final parts = <String>[
      if (hasDigit) r'\d',
      if (hasLetter) 'A-Za-z',
      ...(literals.toList()..sort()).map(_escapeInClass),
    ];
    return '[${parts.join()}]';
  }

  // --- escaping --------------------------------------------------------------

  static const _reserved = r'\^$.|?*+()[]{}/';

  static String _escape(String c) => _reserved.contains(c) ? '\\$c' : c;

  static String _escapeInClass(String c) {
    // Inside a character class, only these are special.
    if (r'\^]-'.contains(c)) return '\\$c';
    return c;
  }
}

enum _Class { digit, letter, literal }

class _Run {
  final _Class cls;
  final String? literal; // set iff cls == literal
  int len = 1;
  _Run(this.cls, this.literal);
}
