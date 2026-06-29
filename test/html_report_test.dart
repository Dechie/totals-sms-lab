import 'package:sms_pattern_lab/analysis/analysis_pipeline.dart';
import 'package:sms_pattern_lab/parser_adapter/totals_parser_adapter.dart';
import 'package:sms_pattern_lab/reports/html_report.dart';
import 'package:sms_pattern_lab/utils/dataset_loader.dart';
import 'package:test/test.dart';

void main() {
  final adapter = TotalsParserAdapter.vendored() ??
      TotalsParserAdapter.autodiscover();

  test('renders a self-contained HTML document', () {
    if (adapter == null) return;
    final messages = DatasetLoader.load('example/cbe_sms.json');
    final result = AnalysisPipeline(adapter: adapter).run(messages);
    final html =
        HtmlReport(result.coverage, parserName: 'Totals').render();

    expect(html, startsWith('<!DOCTYPE html>'));
    expect(html, contains('<svg')); // inline charts
    expect(html, contains('</html>'));
  });

  test('is fully offline: no fetched resources or scripts', () {
    if (adapter == null) return;
    final messages = DatasetLoader.load('example/cbe_sms.json');
    final result = AnalysisPipeline(adapter: adapter).run(messages);
    final html =
        HtmlReport(result.coverage, parserName: 'Totals').render();

    expect(html, isNot(contains('<script')));
    expect(html.toLowerCase(), isNot(contains('cdn')));
    // No fetched stylesheets/images/iframes.
    expect(RegExp(r'<(link|img|iframe)\b', caseSensitive: false).hasMatch(html),
        isFalse);
    expect(html, isNot(contains('url('))); // no CSS-fetched assets
  });

  test('escapes placeholder angle brackets so templates render as text', () {
    if (adapter == null) return;
    final messages = DatasetLoader.load('example/cbe_sms.json');
    final result = AnalysisPipeline(adapter: adapter).run(messages);
    final html =
        HtmlReport(result.coverage, parserName: 'Totals').render();

    // Templates contain <AMOUNT> etc.; they must be escaped, never literal.
    expect(html, contains('&lt;AMOUNT&gt;'));
  });
}
