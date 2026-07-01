import 'dart:io';

import 'package:sms_pattern_lab/annotation/action_lexicon.dart';
import 'package:sms_pattern_lab/annotation/annotator.dart';
import 'package:sms_pattern_lab/models/template_cluster.dart';
import 'package:test/test.dart';

void main() {
  final a = Annotator();

  group('Annotator — verb + direction', () {
    test('tags a directional verb and normalizes wording variants to a lemma',
        () {
      // Both surface forms collapse to the same canonical lemma "transfer".
      expect(a.annotate('You transferred <AMOUNT> to <NAME>').verb,
          equals('transfer'));
      expect(a.annotate('Transfer of <AMOUNT> to <NAME>').verb,
          equals('transfer'));
    });

    test('assigns money direction from the lexicon', () {
      expect(a.annotate('credited with <AMOUNT>').direction,
          equals(TxDirection.incoming));
      expect(a.annotate('debited with <AMOUNT>').direction,
          equals(TxDirection.outgoing));
      expect(a.annotate('Account received <AMOUNT>').direction,
          equals(TxDirection.incoming));
      expect(a.annotate('withdrawn <AMOUNT> from ATM').direction,
          equals(TxDirection.outgoing));
    });

    test('null verb on a template with no lexicon word (a signal, not failure)',
        () {
      final ann = a.annotate('Your OTP is <NUM> valid for <NUM> minutes');
      expect(ann.verb, isNull);
      expect(ann.direction, isNull);
      expect(ann.isEmpty, isTrue);
    });

    test('a directional verb wins over a leading status word', () {
      // "successfully" (neutral) precedes "transferred" (outgoing) in the text,
      // but the directional verb is the primary tag.
      final ann = a.annotate('You have successfully transferred <AMOUNT>');
      expect(ann.verb, equals('transfer'));
      expect(ann.direction, equals(TxDirection.outgoing));
    });

    test('earliest directional verb wins when several appear', () {
      final ann = a.annotate('debited then charged <AMOUNT>');
      expect(ann.verb, equals('debit'));
    });

    test('falls back to a neutral verb when no directional verb is present', () {
      final ann = a.annotate('Transaction confirmed');
      expect(ann.direction, equals(TxDirection.neutral));
      expect(ann.verb, isNotNull);
    });

    test('placeholders never match lexicon words', () {
      // "<SENT>" would be a false positive if we matched inside placeholders.
      expect(a.annotate('<AMOUNT> <ACCOUNT> <DATE>').verb, isNull);
    });

    test('tag() mutates the cluster in place', () {
      final c = TemplateCluster(
          template: 'credited with <AMOUNT>', occurrences: 3);
      a.tag(c);
      expect(c.actionVerb, equals('credit'));
      expect(c.direction, equals(TxDirection.incoming));
    });
  });

  group('ActionLexicon', () {
    test('stays in sync with action_words.txt (every word is covered)', () {
      final file = File('action_words.txt');
      expect(file.existsSync(), isTrue,
          reason: 'run from the package root');
      final known = ActionLexicon.defaultLexicon.forms.toSet();
      final missing = file
          .readAsLinesSync()
          .map((l) => l.trim().toLowerCase())
          .where((l) => l.isNotEmpty)
          .where((w) => !known.contains(w))
          .toList();
      expect(missing, isEmpty,
          reason: 'action_words.txt entries not in the lexicon: $missing');
    });
  });
}
