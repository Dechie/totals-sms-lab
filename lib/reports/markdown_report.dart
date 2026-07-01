import '../models/coverage_report.dart';
import '../models/template_family.dart';

/// Renders a [CoverageReport] into a developer-facing Markdown document:
/// overall coverage, a per-parser health dashboard, and a prioritized list of
/// unmatched template clusters.
class MarkdownReport {
  final CoverageReport report;
  final String parserName;
  final int topClusters;

  /// When true, non-transaction "noise" clusters are also shown as candidate
  /// new formats (the `--no-filter` view). Default hides them.
  final bool includeNoise;

  const MarkdownReport(
    this.report, {
    this.parserName = 'Parser',
    this.topClusters = 25,
    this.includeNoise = false,
  });

  String render() {
    final b = StringBuffer();
    _header(b);
    _summary(b);
    _parserDashboard(b);
    _candidateNewFormats(b);
    _unmatchedClusters(b);
    _footer(b);
    return b.toString();
  }

  void _header(StringBuffer b) {
    b.writeln('# SMS Pattern Lab — Coverage Report');
    b.writeln();
    b.writeln('_Parser framework: **$parserName**_');
    b.writeln();
  }

  void _summary(StringBuffer b) {
    b.writeln('## Summary');
    b.writeln();
    b.writeln('| Metric | Value |');
    b.writeln('|---|---|');
    b.writeln('| Total messages | ${report.total} |');
    b.writeln('| Matched | ${report.matched} |');
    b.writeln('| Unmatched | ${report.unmatched} |');
    b.writeln('| Unattributed (no bank) | ${report.unattributed} |');
    b.writeln(
        '| **Overall coverage** | **${_pct(report.overallCoveragePercent)}** |');
    b.writeln('| Distinct unmatched templates | '
        '${report.unmatchedClusters.length} |');
    b.writeln('| Candidate new formats (unknown sender) | '
        '${report.candidateFamilies.length} |');
    if (report.noiseClusters.isNotEmpty) {
      b.writeln('| Noise clusters (filtered) | '
          '${report.noiseClusters.length} |');
    }
    b.writeln();
  }

  /// Discovery-first section: formats from senders no parser recognizes — likely
  /// whole banks/formats with no parser yet. Listed before the per-bank gaps
  /// because these are the "unknown unknowns" the tool exists to surface.
  void _candidateNewFormats(StringBuffer b) {
    final families = [
      ...report.candidateFamilies,
      if (includeNoise)
        for (final c in report.noiseClusters) TemplateFamily([c]),
    ];
    if (families.isEmpty) return;

    b.writeln('## Candidate New Formats (unrecognized sender)');
    b.writeln();
    b.writeln('These messages matched **no** parser and came from a sender no '
        'bank is configured for — strong candidates for a format (or an entire '
        'bank) you have no parser for yet.');
    if (!includeNoise && report.noiseClusters.isNotEmpty) {
      b.writeln();
      b.writeln('_(${report.noiseClusters.length} non-transaction cluster(s) '
          'filtered out as noise — run with `--no-filter` to include them.)_');
    }
    b.writeln();
    final shown = families.take(topClusters).toList();
    if (families.length > shown.length) {
      b.writeln('_Showing top ${shown.length} of ${families.length}._');
      b.writeln();
    }
    var i = 1;
    for (final f in shown) {
      _family(b, i++, f);
    }
  }

  void _parserDashboard(StringBuffer b) {
    b.writeln('## Parser Health Dashboard');
    b.writeln();
    if (report.parsers.isEmpty) {
      b.writeln('_No attributable messages in dataset._');
      b.writeln();
      return;
    }

    b.writeln('| Parser | Coverage | Matched | Unmatched | Total |');
    b.writeln('|---|---:|---:|---:|---:|');
    for (final p in report.parsers) {
      b.writeln('| ${p.bankName} | ${_pct(p.coveragePercent)} | '
          '${p.matched} | ${p.unmatched} | ${p.total} |');
    }
    b.writeln();

    // Per-parser detail with the single biggest missing template.
    for (final p in report.parsers) {
      if (p.unmatched == 0) continue;
      b.writeln('### ${p.bankName}');
      b.writeln();
      b.writeln('- **Coverage:** ${_pct(p.coveragePercent)}');
      final largest = p.largestMissingTemplate;
      if (largest != null) {
        b.writeln('- **Largest missing template:** '
            '`${_inline(largest.template)}`');
        b.writeln('- **Occurrences:** ${largest.occurrences}');
        b.writeln('- **Priority:** ${largest.priority}');
      }
      b.writeln();
    }
  }

  void _unmatchedClusters(StringBuffer b) {
    b.writeln('## Unmatched Pattern Reports (known banks)');
    b.writeln();
    // Attributed gaps only — unknown-sender clusters get their own section.
    final families = report.attributedFamilies;
    if (families.isEmpty) {
      b.writeln('🎉 No unmatched messages from recognized banks — every '
          'configured parser is fully covered for this dataset.');
      b.writeln();
      return;
    }

    final shown = families.take(topClusters).toList();
    if (families.length > shown.length) {
      b.writeln('_Showing top ${shown.length} of ${families.length} '
          'unmatched template families (ranked by priority)._');
      b.writeln();
    }

    var i = 1;
    for (final f in shown) {
      _family(b, i++, f);
    }
  }

  void _family(StringBuffer b, int index, TemplateFamily f) {
    final occ = f.totalOccurrences;
    final variants = f.memberCount > 1 ? ' · ${f.memberCount} variants' : '';
    b.writeln('### $index. ${f.priority} — $occ occurrence'
        '${occ == 1 ? '' : 's'}$variants');
    b.writeln();
    b.writeln('- **Likely parser:** ${f.likelyBankName ?? 'Unknown'}');
    b.writeln('- **Regex-readiness:** ${f.regexReadiness}');
    if (f.label != null) b.writeln('- **Family:** ${f.label}');
    b.writeln('- **Template:** `${_inline(f.template)}`');
    if (f.memberCount > 1) {
      b.writeln('- **Variants (same category, one regex should cover all):**');
      for (final v in f.variantTemplates) {
        b.writeln('  - `${_inline(v)}`');
      }
    }
    final examples = f.examples();
    if (examples.isNotEmpty) {
      b.writeln('- **Examples:**');
      for (final ex in examples) {
        b.writeln('  - `${_inline(ex)}`');
      }
    }
    b.writeln();
  }

  void _footer(StringBuffer b) {
    b.writeln('---');
    b.writeln();
    b.writeln('_Generated by SMS Pattern Lab — a standalone parser diagnostics '
        'and pattern discovery tool. No production code was modified._');
  }

  String _pct(double v) => '${v.toStringAsFixed(1)}%';

  /// Make a string safe for an inline code span (strip backticks/newlines).
  String _inline(String s) =>
      s.replaceAll('`', '‘').replaceAll(RegExp(r'\s+'), ' ').trim();
}
