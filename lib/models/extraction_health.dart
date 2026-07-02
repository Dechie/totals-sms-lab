import '../parser_adapter/field_extractor.dart';

/// Aggregated field-extraction health for a family of *successfully matched*
/// messages (a `successUnit` in the export). Holds **counts only** — never raw
/// values — so it is privacy-safe to export, and merges by field-wise addition
/// so families combine exactly.
///
/// The [healthScore] is weighted by **totals-impact**: the three fields whose
/// absence directly breaks the app's income/expense/balance reconciliation
/// (valid CREDIT/DEBIT type, a captured+parseable balance, a captured
/// counterparty) carry the most weight. See APP_RECONCILIATION_ISSUES.md for
/// how each signal maps to a concrete downstream corruption.
class ExtractionHealth {
  // --- score weights (sum to 100), tunable in one place ---
  static const int wType = 30; // wrong/absent type ⇒ excluded from both sums
  static const int wBalance = 25; // absent balance ⇒ stale balance snapshot
  static const int wCounterparty = 20; // absent ⇒ self-transfer pairing fails
  static const int wReference = 12; // synthesized/absent ⇒ no dedup key
  static const int wAccount = 8; // absent ⇒ drop risk (expected-aware)
  static const int wFees = 5; // uncaptured fees (expected-aware)

  final int members;
  final int appAccepted;
  final int typeValid;
  final int amountParsed;
  final int balanceExpected;
  final int balanceCaptured;
  final int balanceParsed;
  final int counterparty;
  final int refReal;
  final int refSynthesized;
  final int accountExpected;
  final int accountCaptured;
  final int feesExpected;
  final int feesCaptured;

  /// Winning-pattern descriptions across members → count (for reporting the
  /// modal pattern behind a family). Pattern metadata, not PII.
  final Map<String, int> patternDescriptions;

  const ExtractionHealth({
    required this.members,
    required this.appAccepted,
    required this.typeValid,
    required this.amountParsed,
    required this.balanceExpected,
    required this.balanceCaptured,
    required this.balanceParsed,
    required this.counterparty,
    required this.refReal,
    required this.refSynthesized,
    required this.accountExpected,
    required this.accountCaptured,
    required this.feesExpected,
    required this.feesCaptured,
    this.patternDescriptions = const {},
  });

  static const ExtractionHealth empty = ExtractionHealth(
    members: 0,
    appAccepted: 0,
    typeValid: 0,
    amountParsed: 0,
    balanceExpected: 0,
    balanceCaptured: 0,
    balanceParsed: 0,
    counterparty: 0,
    refReal: 0,
    refSynthesized: 0,
    accountExpected: 0,
    accountCaptured: 0,
    feesExpected: 0,
    feesCaptured: 0,
  );

  /// A single message's contribution.
  factory ExtractionHealth.fromOutcome(ExtractionOutcome o,
      {String? patternDescription}) {
    int b(bool v) => v ? 1 : 0;
    return ExtractionHealth(
      members: 1,
      appAccepted: b(o.accepted),
      typeValid: b(o.typeValid),
      amountParsed: b(o.amountParsed),
      balanceExpected: b(o.balanceExpected),
      balanceCaptured: b(o.balanceCaptured),
      balanceParsed: b(o.balanceParsed),
      counterparty: b(o.counterpartyCaptured),
      refReal: b(o.referenceReal),
      refSynthesized: b(o.referenceSynthesized),
      accountExpected: b(o.accountExpected),
      accountCaptured: b(o.accountCaptured),
      feesExpected: b(o.feesExpected),
      feesCaptured: b(o.feesCaptured),
      patternDescriptions: (patternDescription != null &&
              patternDescription.isNotEmpty)
          ? {patternDescription: 1}
          : const {},
    );
  }

  ExtractionHealth merge(ExtractionHealth o) {
    final descs = <String, int>{...patternDescriptions};
    o.patternDescriptions.forEach((k, v) => descs[k] = (descs[k] ?? 0) + v);
    return ExtractionHealth(
      members: members + o.members,
      appAccepted: appAccepted + o.appAccepted,
      typeValid: typeValid + o.typeValid,
      amountParsed: amountParsed + o.amountParsed,
      balanceExpected: balanceExpected + o.balanceExpected,
      balanceCaptured: balanceCaptured + o.balanceCaptured,
      balanceParsed: balanceParsed + o.balanceParsed,
      counterparty: counterparty + o.counterparty,
      refReal: refReal + o.refReal,
      refSynthesized: refSynthesized + o.refSynthesized,
      accountExpected: accountExpected + o.accountExpected,
      accountCaptured: accountCaptured + o.accountCaptured,
      feesExpected: feesExpected + o.feesExpected,
      feesCaptured: feesCaptured + o.feesCaptured,
      patternDescriptions: descs,
    );
  }

  double _rate(int n) => members == 0 ? 0.0 : n / members;

  double get appAcceptedRate => _rate(appAccepted);
  double get typeValidRate => _rate(typeValid);
  double get amountRate => _rate(amountParsed);
  double get balanceExpectedRate => _rate(balanceExpected);
  double get balanceCapturedRate => _rate(balanceCaptured);
  double get balanceParsedRate => _rate(balanceParsed);
  double get counterpartyRate => _rate(counterparty);
  double get referenceRealRate => _rate(refReal);
  double get referenceSynthesizedRate => _rate(refSynthesized);
  double get accountExpectedRate => _rate(accountExpected);
  double get accountCapturedRate => _rate(accountCaptured);
  double get feesExpectedRate => _rate(feesExpected);
  double get feesCapturedRate => _rate(feesCaptured);

  /// Account/fees are scored **expected-aware** — a pattern that legitimately
  /// has no account/fee field is not penalized. Type/balance/counterparty/ref
  /// are scored **impact-honest** — their absence IS a totals risk, so it costs.
  double get _accountGoodRate =>
      members == 0 ? 0.0 : (members - accountExpected + accountCaptured) / members;
  double get _feesGoodRate =>
      members == 0 ? 0.0 : (members - feesExpected + feesCaptured) / members;

  /// 0..100. Rejected families (nothing the app would accept) collapse to 0 so
  /// they sort to the bottom of the success list.
  int get healthScore {
    final raw = wType * typeValidRate +
        wBalance * balanceParsedRate +
        wCounterparty * counterpartyRate +
        wReference * referenceRealRate +
        wAccount * _accountGoodRate +
        wFees * _feesGoodRate;
    return (appAcceptedRate * raw).round();
  }

  /// The most common winning-pattern description behind this family.
  String? get topPatternDescription {
    if (patternDescriptions.isEmpty) return null;
    return patternDescriptions.entries
        .reduce((a, b) => b.value > a.value ? b : a)
        .key;
  }

  /// Privacy-safe per-field rate view for the export.
  Map<String, dynamic> toRatesJson() => {
        'appAcceptedRate': _round(appAcceptedRate),
        'typeValidRate': _round(typeValidRate),
        'amountRate': _round(amountRate),
        'balance': {
          'expectedRate': _round(balanceExpectedRate),
          'capturedRate': _round(balanceCapturedRate),
          'parseRate': _round(balanceParsedRate),
        },
        'counterpartyRate': _round(counterpartyRate),
        'reference': {
          'realRate': _round(referenceRealRate),
          'synthesizedRate': _round(referenceSynthesizedRate),
        },
        'accountCapturedRate': _round(accountCapturedRate),
        'feesExpectedRate': _round(feesExpectedRate),
        'feesCapturedRate': _round(feesCapturedRate),
      };

  static double _round(double v) => (v * 10000).round() / 10000;
}
