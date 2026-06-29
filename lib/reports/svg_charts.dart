import 'dart:math' as math;

/// One bar in a [SvgCharts.horizontalBars] chart.
class BarDatum {
  final String label;
  final double value; // 0..100
  final String color; // hex, e.g. '#16a34a'
  final String? valueLabel; // overrides the right-hand text

  const BarDatum(this.label, this.value, this.color, {this.valueLabel});
}

/// Hand-built, dependency-free SVG charts.
///
/// Everything is emitted as plain SVG markup so reports stay self-contained and
/// fully offline — no charting library, no CDN, no canvas/raster step. Output
/// is deterministic (no randomness, no timestamps), which keeps reports
/// diffable across runs.
class SvgCharts {
  /// Horizontal bar chart, one row per [bars] entry. Values are clamped 0..100.
  static String horizontalBars(
    List<BarDatum> bars, {
    int width = 720,
    int labelWidth = 160,
    int rowHeight = 30,
    int barHeight = 16,
  }) {
    if (bars.isEmpty) {
      return _wrap(width, 40, '<text x="0" y="24" '
          'font-size="13" fill="#6b7280">No data</text>');
    }
    const pad = 8;
    final trackX = labelWidth + 8;
    final trackW = width - trackX - 64; // room for the value label
    final height = bars.length * rowHeight + pad * 2;

    final b = StringBuffer();
    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final v = bar.value.clamp(0, 100).toDouble();
      final cy = pad + i * rowHeight + rowHeight / 2;
      final barY = cy - barHeight / 2;
      final fillW = trackW * v / 100.0;
      final valueText = bar.valueLabel ?? '${v.toStringAsFixed(1)}%';

      // Label (truncated by the viewport; kept simple).
      b.writeln('<text x="0" y="${cy + 4}" font-size="13" fill="#111827">'
          '${_esc(bar.label)}</text>');
      // Track.
      b.writeln('<rect x="$trackX" y="${barY.toStringAsFixed(1)}" '
          'width="$trackW" height="$barHeight" rx="4" fill="#e5e7eb"/>');
      // Value.
      b.writeln('<rect x="$trackX" y="${barY.toStringAsFixed(1)}" '
          'width="${fillW.toStringAsFixed(1)}" height="$barHeight" rx="4" '
          'fill="${bar.color}"/>');
      // Value label.
      b.writeln('<text x="${(trackX + trackW + 6)}" y="${cy + 4}" '
          'font-size="12" fill="#374151">${_esc(valueText)}</text>');
    }
    return _wrap(width, height, b.toString());
  }

  /// A donut gauge for a single 0..100 [percent], with the figure in the middle.
  static String donut(double percent,
      {int size = 168, double stroke = 16, String? color}) {
    final p = percent.clamp(0, 100).toDouble();
    final c = color ?? coverageColor(p);
    final r = (size - stroke) / 2;
    final cx = size / 2;
    final circ = 2 * math.pi * r;
    final dash = circ * p / 100.0;
    final gap = circ - dash;

    final b = StringBuffer();
    // Rotate -90deg so the arc starts at 12 o'clock.
    b.writeln('<g transform="rotate(-90 $cx $cx)">');
    b.writeln('<circle cx="$cx" cy="$cx" r="${r.toStringAsFixed(1)}" '
        'fill="none" stroke="#e5e7eb" stroke-width="$stroke"/>');
    b.writeln('<circle cx="$cx" cy="$cx" r="${r.toStringAsFixed(1)}" '
        'fill="none" stroke="$c" stroke-width="$stroke" stroke-linecap="round" '
        'stroke-dasharray="${dash.toStringAsFixed(2)} ${gap.toStringAsFixed(2)}"/>');
    b.writeln('</g>');
    b.writeln('<text x="$cx" y="${cx - 2}" text-anchor="middle" '
        'font-size="30" font-weight="700" fill="#111827">'
        '${p.toStringAsFixed(1)}%</text>');
    b.writeln('<text x="$cx" y="${cx + 22}" text-anchor="middle" '
        'font-size="12" fill="#6b7280">coverage</text>');
    return _wrap(size, size, b.toString());
  }

  /// Coverage → health color (green ≥95, amber ≥80, red below).
  static String coverageColor(double pct) {
    if (pct >= 95) return '#16a34a';
    if (pct >= 80) return '#d97706';
    return '#dc2626';
  }

  /// Priority → color, matching the report's badges.
  static String priorityColor(String priority) {
    switch (priority) {
      case 'Very High':
        return '#dc2626';
      case 'High':
        return '#ea580c';
      case 'Medium':
        return '#d97706';
      case 'Low':
        return '#65a30d';
      default:
        return '#94a3b8';
    }
  }

  static String _wrap(num w, num h, String body) =>
      '<svg viewBox="0 0 $w $h" width="$w" height="$h" '
      'xmlns="http://www.w3.org/2000/svg" '
      'font-family="system-ui, sans-serif" role="img">\n$body</svg>';

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
