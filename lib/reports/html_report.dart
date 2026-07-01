import '../models/coverage_report.dart';
import '../models/template_family.dart';
import 'svg_charts.dart';

/// Renders a [CoverageReport] into a **single, self-contained HTML file**:
/// embedded CSS, inline SVG charts, no external assets, no CDN, no JavaScript.
/// It opens correctly offline and is byte-stable across runs (no timestamps).
class HtmlReport {
  final CoverageReport report;
  final String parserName;
  final int topClusters;

  /// When true, non-transaction "noise" clusters are also shown as candidate
  /// new formats (the `--no-filter` view). Default hides them.
  final bool includeNoise;

  const HtmlReport(
    this.report, {
    this.parserName = 'Parser',
    this.topClusters = 25,
    this.includeNoise = false,
  });

  String render() {
    final b = StringBuffer();
    b.writeln('<!DOCTYPE html>');
    b.writeln('<html lang="en"><head>');
    b.writeln('<meta charset="utf-8">');
    b.writeln('<meta name="viewport" content="width=device-width, '
        'initial-scale=1">');
    b.writeln('<title>SMS Pattern Lab — Coverage Report</title>');
    b.writeln('<style>${_css()}</style>');
    b.writeln('</head><body>');
    b.writeln('<main>');
    _header(b);
    _summary(b);
    _parserDashboard(b);
    _candidateNewFormats(b);
    _clusters(b);
    _footer(b);
    b.writeln('</main>');
    b.writeln('</body></html>');
    return b.toString();
  }

  void _header(StringBuffer b) {
    b.writeln('<header>');
    b.writeln('<h1>SMS Pattern Lab</h1>');
    b.writeln('<p class="sub">Coverage report · parser framework: '
        '<strong>${_esc(parserName)}</strong></p>');
    b.writeln('</header>');
  }

  void _summary(StringBuffer b) {
    final cov = report.overallCoveragePercent;
    b.writeln('<section class="grid summary">');
    b.writeln('<div class="donut card">${SvgCharts.donut(cov)}</div>');
    b.writeln('<div class="cards">');
    _stat(b, 'Total messages', '${report.total}');
    _stat(b, 'Matched', '${report.matched}', color: '#16a34a');
    _stat(b, 'Unmatched', '${report.unmatched}', color: '#dc2626');
    _stat(b, 'Unattributed', '${report.unattributed}');
    _stat(b, 'Distinct unmatched templates',
        '${report.unmatchedClusters.length}');
    _stat(b, 'Candidate new formats',
        '${report.candidateFamilies.length}',
        color: report.candidateFamilies.isEmpty ? null : '#ea580c');
    if (report.noiseClusters.isNotEmpty) {
      _stat(b, 'Noise (filtered)', '${report.noiseClusters.length}');
    }
    b.writeln('</div>');
    b.writeln('</section>');
  }

  void _stat(StringBuffer b, String label, String value, {String? color}) {
    final style = color == null ? '' : ' style="color:$color"';
    b.writeln('<div class="card stat">'
        '<div class="value"$style>${_esc(value)}</div>'
        '<div class="label">${_esc(label)}</div></div>');
  }

  void _parserDashboard(StringBuffer b) {
    b.writeln('<section>');
    b.writeln('<h2>Parser health</h2>');
    if (report.parsers.isEmpty) {
      b.writeln('<p class="muted">No attributable messages in dataset.</p>');
      b.writeln('</section>');
      return;
    }

    // Coverage bar chart.
    final bars = [
      for (final p in report.parsers)
        BarDatum(
          p.bankName,
          p.coveragePercent,
          SvgCharts.coverageColor(p.coveragePercent),
          valueLabel: '${p.coveragePercent.toStringAsFixed(1)}% '
              '(${p.matched}/${p.total})',
        )
    ];
    b.writeln('<div class="card chart">${SvgCharts.horizontalBars(bars)}</div>');

    // Detail table.
    b.writeln('<table>');
    b.writeln('<thead><tr><th>Parser</th><th>Coverage</th><th>Matched</th>'
        '<th>Unmatched</th><th>Total</th><th>Largest missing template</th>'
        '</tr></thead><tbody>');
    for (final p in report.parsers) {
      final largest = p.largestMissingTemplate;
      final missing = largest == null
          ? '<span class="muted">—</span>'
          : '<code>${_esc(_truncate(largest.template, 80))}</code>'
              ' <span class="muted">×${largest.occurrences}</span>';
      b.writeln('<tr>'
          '<td>${_esc(p.bankName)}</td>'
          '<td><span class="pill" style="background:'
          '${SvgCharts.coverageColor(p.coveragePercent)}">'
          '${p.coveragePercent.toStringAsFixed(1)}%</span></td>'
          '<td>${p.matched}</td><td>${p.unmatched}</td><td>${p.total}</td>'
          '<td>$missing</td>'
          '</tr>');
    }
    b.writeln('</tbody></table>');
    b.writeln('</section>');
  }

  /// Discovery-first: formats from unrecognized senders (likely whole banks
  /// with no parser yet) — the "unknown unknowns" the tool exists to surface.
  void _candidateNewFormats(StringBuffer b) {
    final families = [
      ...report.candidateFamilies,
      if (includeNoise)
        for (final c in report.noiseClusters) TemplateFamily([c]),
    ];
    if (families.isEmpty) return;
    b.writeln('<section>');
    b.writeln('<h2>Candidate new formats <span class="muted">'
        '(unrecognized sender)</span></h2>');
    b.writeln('<p class="muted">Matched no parser and came from a sender no '
        'bank is configured for — strong candidates for a format (or an entire '
        'bank) with no parser yet.'
        '${!includeNoise && report.noiseClusters.isNotEmpty ? ' '
            '${report.noiseClusters.length} non-transaction cluster(s) filtered '
            'as noise — use --no-filter to include.' : ''}</p>');
    final shown = families.take(topClusters).toList();
    if (families.length > shown.length) {
      b.writeln('<p class="muted">Showing top ${shown.length} of '
          '${families.length}.</p>');
    }
    var i = 1;
    for (final f in shown) {
      _family(b, i++, f);
    }
    b.writeln('</section>');
  }

  void _clusters(StringBuffer b) {
    b.writeln('<section>');
    b.writeln('<h2>Unmatched pattern reports <span class="muted">'
        '(known banks)</span></h2>');
    final families = report.attributedFamilies;
    if (families.isEmpty) {
      b.writeln('<p class="ok">🎉 No unmatched messages from recognized banks '
          '— every configured parser is fully covered for this dataset.</p>');
      b.writeln('</section>');
      return;
    }

    final shown = families.take(topClusters).toList();
    if (families.length > shown.length) {
      b.writeln('<p class="muted">Showing top ${shown.length} of '
          '${families.length} unmatched families (ranked by priority).</p>');
    }

    var i = 1;
    for (final f in shown) {
      _family(b, i++, f);
    }
    b.writeln('</section>');
  }

  void _family(StringBuffer b, int index, TemplateFamily f) {
    b.writeln('<article class="cluster">');
    b.writeln('<div class="cluster-head">');
    b.writeln('<span class="badge" style="background:'
        '${SvgCharts.priorityColor(f.priority)}">${_esc(f.priority)}</span>');
    b.writeln('<span class="count">×${f.totalOccurrences}</span>');
    b.writeln('<span class="badge" style="background:'
        '${_readinessColor(f.regexReadiness)}" title="how anchorable this '
        'skeleton is for one regex">regex: ${_esc(f.regexReadiness)}</span>');
    if (f.memberCount > 1) {
      b.writeln('<span class="muted">${f.memberCount} variants</span>');
    }
    b.writeln('<span class="muted">'
        '${_esc(f.likelyBankName ?? 'Unknown parser')}'
        '${f.label == null ? '' : ' · ${_esc(f.label!)}'}'
        '</span>');
    b.writeln('</div>');
    b.writeln('<pre class="template">${_esc(f.template)}</pre>');
    if (f.memberCount > 1) {
      b.writeln('<details><summary>${f.variantTemplates.length} variant(s) '
          '— one regex should cover all</summary>');
      for (final v in f.variantTemplates) {
        b.writeln('<pre class="example">${_esc(v)}</pre>');
      }
      b.writeln('</details>');
    }
    final examples = f.examples();
    if (examples.isNotEmpty) {
      b.writeln('<details><summary>${examples.length} example'
          '${examples.length == 1 ? '' : 's'}</summary>');
      for (final ex in examples) {
        b.writeln('<pre class="example">${_esc(ex)}</pre>');
      }
      b.writeln('</details>');
    }
    b.writeln('</article>');
  }

  void _footer(StringBuffer b) {
    b.writeln('<footer>Generated by SMS Pattern Lab — a standalone parser '
        'diagnostics and pattern discovery tool. Self-contained, offline, no '
        'production code modified.</footer>');
  }

  /// Color for the regex-readiness badge (green high → grey low).
  String _readinessColor(String readiness) {
    switch (readiness) {
      case 'High':
        return '#16a34a';
      case 'Medium':
        return '#d97706';
      default:
        return '#94a3b8';
    }
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 1)}…';

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _css() => '''
    :root { --bg:#f8fafc; --card:#fff; --line:#e5e7eb; --ink:#111827;
            --muted:#6b7280; }
    * { box-sizing: border-box; }
    body { margin:0; background:var(--bg); color:var(--ink);
           font:15px/1.5 system-ui, -apple-system, Segoe UI, Roboto, sans-serif; }
    main { max-width: 920px; margin: 0 auto; padding: 32px 20px 64px; }
    header h1 { margin:0; font-size:26px; }
    .sub { color:var(--muted); margin:4px 0 0; }
    h2 { margin:36px 0 12px; font-size:19px; }
    .card { background:var(--card); border:1px solid var(--line);
            border-radius:12px; padding:16px; }
    .summary { display:grid; grid-template-columns: 200px 1fr; gap:16px;
               align-items:center; margin-top:20px; }
    .donut { display:flex; justify-content:center; }
    .cards { display:grid; grid-template-columns: repeat(auto-fit,minmax(140px,1fr));
             gap:12px; }
    .stat .value { font-size:24px; font-weight:700; }
    .stat .label { color:var(--muted); font-size:12px; margin-top:2px; }
    .chart { overflow-x:auto; margin-bottom:16px; }
    table { width:100%; border-collapse:collapse; background:var(--card);
            border:1px solid var(--line); border-radius:12px; overflow:hidden; }
    th, td { text-align:left; padding:10px 12px; border-bottom:1px solid var(--line);
             font-size:14px; vertical-align:top; }
    th { background:#f1f5f9; font-size:12px; text-transform:uppercase;
         letter-spacing:.04em; color:#475569; }
    tr:last-child td { border-bottom:none; }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
           font-size:12.5px; background:#f1f5f9; padding:1px 5px; border-radius:5px; }
    .pill, .badge { color:#fff; font-weight:600; font-size:12px;
                    padding:2px 8px; border-radius:999px; display:inline-block; }
    .cluster { background:var(--card); border:1px solid var(--line);
               border-radius:12px; padding:14px 16px; margin:12px 0; }
    .cluster-head { display:flex; gap:10px; align-items:center; margin-bottom:8px; }
    .count { font-weight:700; }
    .template { margin:0; padding:10px 12px; background:#0f172a; color:#e2e8f0;
                border-radius:8px; white-space:pre-wrap; word-break:break-word;
                font: 12.5px/1.5 ui-monospace, Menlo, monospace; }
    .example { margin:8px 0 0; padding:8px 10px; background:#f1f5f9;
               border-radius:8px; white-space:pre-wrap; word-break:break-word;
               font: 12px/1.5 ui-monospace, Menlo, monospace; }
    details summary { cursor:pointer; color:var(--muted); margin-top:8px;
                      font-size:13px; }
    .muted { color:var(--muted); } .ok { color:#16a34a; }
    footer { margin-top:40px; color:var(--muted); font-size:12px;
             border-top:1px solid var(--line); padding-top:16px; }
''';
}
