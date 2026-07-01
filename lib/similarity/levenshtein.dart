import 'dart:math' as math;

/// Levenshtein edit distance between [a] and [b] — the minimum number of single
/// character insertions, deletions, or substitutions to turn one into the
/// other. Pure Dart, two-row dynamic programming: O(a·b) time, O(min) space.
/// Deterministic (Invariant 3), zero-dependency (Invariant 1).
int levenshteinDistance(String a, String b) {
  if (identical(a, b) || a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Iterate over the shorter string's length for the row width.
  if (a.length < b.length) {
    final t = a;
    a = b;
    b = t;
  }

  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= b.length; j++) {
      final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = math.min(
        math.min(curr[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// Similarity in `[0, 1]`: `1 - distance / maxLength`. `1.0` when both strings
/// are equal (including both empty). This is the ratio the grouper thresholds
/// on (start ~0.9, tuned in V3) so it's independent of absolute length.
double similarityRatio(String a, String b) {
  final maxLen = math.max(a.length, b.length);
  if (maxLen == 0) return 1.0;
  return 1.0 - levenshteinDistance(a, b) / maxLen;
}
