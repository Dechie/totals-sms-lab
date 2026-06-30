import 'package:sms_pattern_lab/models/template_cluster.dart';
import 'package:test/test.dart';

TemplateCluster c(String template) =>
    TemplateCluster(template: template, occurrences: 1);

void main() {
  test('High when there is a strong field and plenty of literal anchors', () {
    final t = c('Account <ACCOUNT> has been credited with <AMOUNT>. '
        'Your current balance is <AMOUNT>. Thanks for Banking.');
    expect(t.hasStrongField, isTrue);
    expect(t.regexReadiness, equals('High'));
  });

  test('Low when the skeleton is mostly placeholders (nothing to anchor on)',
      () {
    final t = c('<NUM> <NUM> <AMOUNT> <NUM>');
    expect(t.regexReadiness, equals('Low'));
  });

  test('Medium when anchors are modest but a strong field is present', () {
    final t = c('received <AMOUNT> from sender today'); // 4 anchors + strong
    expect(t.hasStrongField, isTrue);
    expect(t.regexReadiness, equals('Medium'));
  });
}
