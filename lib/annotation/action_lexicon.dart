import '../models/template_cluster.dart' show TxDirection;

/// One entry in the action-verb lexicon: a canonical [lemma], the set of
/// surface [forms] that map to it, and the transaction [direction] it implies.
///
/// The lemma is what grouping keys on, so wording variants of the same action
/// ("transfer"/"transferred"/"transfer of") collapse into one family without
/// needing Levenshtein (that's V2 step 2, for wording the lexicon *doesn't*
/// normalize). The direction supplies incoming/outgoing family labels for free.
class ActionWord {
  final String lemma;
  final TxDirection direction;
  final List<String> forms;
  const ActionWord(this.lemma, this.direction, this.forms);
}

/// The curated action-verb lexicon (V2 step 1, PRIMARY grouper input).
///
/// This is the *structured* companion to the flat `action_words.txt` vocabulary
/// at the repo root: every word in that file is a [ActionWord.forms] entry here,
/// organized into canonical lemmas with a direction. `test/action_lexicon_test`
/// asserts the two stay in sync, so `action_words.txt` remains the human-facing,
/// self-improving list while grouping runs off this deterministic, offline map
/// (Invariant 1/3 — zero-dep, no I/O in analysis logic).
///
/// Directions follow ROADMAP_NOTES §3 / ENRICHMENT_FIELDS.md:
///   * incoming — money in (credited/received/deposited/refunded)
///   * outgoing — money out (debited/transferred/paid/withdrawn)
///   * neutral  — status or ambiguous verbs (confirmed/successful/transaction);
///     never used to imply a money direction, only to tag + label.
class ActionLexicon {
  final List<ActionWord> words;

  /// form → ActionWord, lower-cased. Built once for O(1) token lookup.
  final Map<String, ActionWord> _byForm;

  ActionLexicon(this.words)
      : _byForm = {
          for (final w in words)
            for (final f in w.forms) f.toLowerCase(): w,
        };

  /// The default lexicon. Mirror any edit here into `action_words.txt`.
  static final ActionLexicon defaultLexicon = ActionLexicon(const [
    // --- incoming (money in) -------------------------------------------------
    ActionWord('credit', TxDirection.incoming, ['credit', 'credited']),
    ActionWord('receive', TxDirection.incoming, ['receive', 'received']),
    ActionWord('deposit', TxDirection.incoming, ['deposit', 'deposited']),
    ActionWord('refund', TxDirection.incoming, ['refund', 'refunded']),
    ActionWord('disburse', TxDirection.incoming,
        ['disburse', 'disbursed', 'disbursement']),
    ActionWord('collect', TxDirection.incoming, ['collect', 'collected']),
    ActionWord('redeem', TxDirection.incoming, ['redeem', 'redeemed']),
    ActionWord('earn', TxDirection.incoming, ['earn', 'earned']),
    ActionWord('return', TxDirection.incoming, ['return', 'returned']),
    ActionWord('reverse', TxDirection.incoming,
        ['reverse', 'reversed', 'reversal']),

    // --- outgoing (money out) ------------------------------------------------
    ActionWord('debit', TxDirection.outgoing, ['debit', 'debited']),
    ActionWord('transfer', TxDirection.outgoing,
        ['transfer', 'transferred', 'transfered']),
    ActionWord('send', TxDirection.outgoing, ['send', 'sent']),
    ActionWord('withdraw', TxDirection.outgoing,
        ['withdraw', 'withdrawn', 'withdrew', 'withdrawal']),
    ActionWord('pay', TxDirection.outgoing, ['pay', 'paid', 'payment']),
    ActionWord('purchase', TxDirection.outgoing, ['purchase', 'purchased']),
    ActionWord('spend', TxDirection.outgoing, ['spend', 'spent']),
    ActionWord('charge', TxDirection.outgoing, ['charge', 'charged']),
    ActionWord('deduct', TxDirection.outgoing,
        ['deduct', 'deducted', 'deduction']),
    ActionWord('recharge', TxDirection.outgoing, ['recharge', 'recharged']),
    ActionWord('topup', TxDirection.outgoing, ['topup', 'topped']),
    ActionWord('bill', TxDirection.outgoing, ['bill', 'billed']),
    ActionWord('settle', TxDirection.outgoing,
        ['settle', 'settled', 'settlement']),
    ActionWord('remit', TxDirection.outgoing,
        ['remit', 'remitted', 'remittance']),
    ActionWord('cash', TxDirection.outgoing, ['cashed', 'cashout']),

    // --- neutral (status / ambiguous) ---------------------------------------
    ActionWord('load', TxDirection.neutral, ['load', 'loaded']),
    ActionWord('convert', TxDirection.neutral, ['convert', 'converted']),
    ActionWord('exchange', TxDirection.neutral, ['exchange', 'exchanged']),
    ActionWord('process', TxDirection.neutral, ['processed']),
    ActionWord('post', TxDirection.neutral, ['posted']),
    ActionWord('complete', TxDirection.neutral, ['completed']),
    ActionWord('occur', TxDirection.neutral, ['occurred']),
    ActionWord('confirm', TxDirection.neutral, ['confirmed']),
    ActionWord('approve', TxDirection.neutral, ['approved']),
    ActionWord('decline', TxDirection.neutral, ['declined']),
    ActionWord('reject', TxDirection.neutral, ['rejected']),
    ActionWord('cancel', TxDirection.neutral, ['cancelled']),
    ActionWord('fail', TxDirection.neutral, ['failed']),
    ActionWord('transaction', TxDirection.neutral, ['transaction']),
    ActionWord('success', TxDirection.neutral, ['successful', 'successfully']),
    ActionWord('pending', TxDirection.neutral, ['pending']),
  ]);

  /// The [ActionWord] a single lower-cased token belongs to, or `null`.
  ActionWord? forForm(String token) => _byForm[token.toLowerCase()];

  /// All recognized surface forms (lower-cased) — for the sync test / reports.
  Iterable<String> get forms => _byForm.keys;
}
