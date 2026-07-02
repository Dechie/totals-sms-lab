import '../models/bank.dart';
import '../models/sms_pattern.dart';

/// Why the accept-gate rejected a regex match (mirrors the skip branches in
/// Totals' `PatternParser.extractTransactionDetails`).
enum RejectReason { none, amountMissing, balanceMissing, refMissing, accountMissing }

/// The privacy-safe outcome of running the app's field extraction + accept-gate
/// against one regex match. Carries **presence flags only** — never a raw value
/// (amount, name, account digits, reference) — so it can flow into the export
/// without leaking anything the normalizer would have masked.
class ExtractionOutcome {
  /// True iff the app's parser would have RETURNED this as a transaction
  /// (passed every skip check in pattern_parser.dart:170-190).
  final bool accepted;
  final RejectReason reason;

  /// Final `type` is exactly `CREDIT` or `DEBIT` — the only values the app's
  /// income/expense sums recognize. When false the transaction silently drops
  /// out of BOTH totals while still moving the balance snapshot.
  final bool typeValid;

  /// Amount extracted and parseable (the gate floor — `accepted` implies this).
  final bool amountParsed;

  /// The regex declared a `balance` group.
  final bool balanceExpected;

  /// The `balance` group captured a non-null value (what the gate checks).
  final bool balanceCaptured;

  /// The captured balance parses as a number (health signal, not gated).
  final bool balanceParsed;

  /// A counterparty landed on the transaction (sender/source/agent/payer/from,
  /// or a creditor/receiver group, or the CREDIT body-fallback). Absence is what
  /// makes self-transfer pairing fail → double-counting.
  final bool counterpartyCaptured;

  /// A real reference was captured from a group.
  final bool referenceReal;

  /// The reference was synthesized (`refRequired == false` + no group value) —
  /// no natural dedup key, a re-import can duplicate the transaction.
  final bool referenceSynthesized;

  /// The regex declared an `account` group.
  final bool accountExpected;

  /// The `account` group captured a value (post-masking).
  final bool accountCaptured;

  /// The pattern is declared to carry fees (`hasFees`).
  final bool feesExpected;

  /// A serviceCharge or vat value was extracted.
  final bool feesCaptured;

  const ExtractionOutcome({
    required this.accepted,
    required this.reason,
    required this.typeValid,
    required this.amountParsed,
    required this.balanceExpected,
    required this.balanceCaptured,
    required this.balanceParsed,
    required this.counterpartyCaptured,
    required this.referenceReal,
    required this.referenceSynthesized,
    required this.accountExpected,
    required this.accountCaptured,
    required this.feesExpected,
    required this.feesCaptured,
  });

  /// A total failure to extract anything (used when extraction throws).
  static const ExtractionOutcome failed = ExtractionOutcome(
    accepted: false,
    reason: RejectReason.amountMissing,
    typeValid: false,
    amountParsed: false,
    balanceExpected: false,
    balanceCaptured: false,
    balanceParsed: false,
    counterpartyCaptured: false,
    referenceReal: false,
    referenceSynthesized: false,
    accountExpected: false,
    accountCaptured: false,
    feesExpected: false,
    feesCaptured: false,
  );
}

/// A pure, synchronous mirror of Totals'
/// `PatternParser.extractTransactionDetails` + `_cleanNumber` + `_normalizeType`
/// (totals/app/lib/utils/pattern_parser.dart). The app method is `async` only
/// because it fetches banks from a DB for account masking; the lab already holds
/// every [Bank], so the resolved bank is passed in and this stays sync.
///
/// It records ONLY whether each field extracted (presence flags), never the
/// value, and replicates the accept-gate so the lab can distinguish "regex
/// matched" from "the app would produce a usable transaction".
///
/// ⚠ Kept in sync with the vendored snapshot via the `extractTransactionDetails`
/// / `cleanNumber` fidelity probes (lib/baseline/logic_fidelity.dart). If those
/// probes drift, revisit this port.
class FieldExtractor {
  static const _counterpartyGroups = ['sender', 'source', 'agent', 'payer', 'from'];

  static ExtractionOutcome extract({
    required RegExpMatch match,
    required String body,
    required SmsPattern pattern,
    required Bank? bank,
    DateTime? messageDate,
  }) {
    try {
      return _extract(match, body, pattern, bank, messageDate);
    } catch (_) {
      // Mirror the app's per-pattern try/catch: a throw is a non-match.
      return ExtractionOutcome.failed;
    }
  }

  static ExtractionOutcome _extract(
    RegExpMatch match,
    String body,
    SmsPattern pattern,
    Bank? bank,
    DateTime? messageDate,
  ) {
    final groups = match.groupNames.toSet();
    String? group(String name) =>
        groups.contains(name) ? match.namedGroup(name) : null;

    // --- amount (gate floor) ---
    final bool amountParsed = groups.contains('amount') &&
        double.tryParse(_cleanNumber(match.namedGroup('amount')) ?? '') != null;

    // --- balance ---
    final bool balanceExpected = groups.contains('balance');
    final String? balanceClean =
        balanceExpected ? _cleanNumber(match.namedGroup('balance')) : null;
    final bool balanceCaptured = balanceClean != null;
    final bool balanceParsed =
        balanceCaptured && double.tryParse(balanceClean) != null;

    // --- account (with bank masking) ---
    final bool accountExpected = groups.contains('account');
    final String? accountNumber =
        accountExpected ? _maskAccount(match.namedGroup('account'), bank) : null;
    final bool accountCaptured = accountNumber != null;

    // --- reference (real vs synthesized) ---
    final String? refGroup = group('reference');
    final bool referenceReal = refGroup != null && refGroup.isNotEmpty;
    final bool referenceSynthesized = !referenceReal && pattern.refRequired == false;
    // Effective reference the gate sees (group value, or synthesized placeholder).
    final bool hasEffectiveReference = referenceReal || referenceSynthesized;

    // --- type ---
    String finalType = pattern.type;
    if (groups.contains('type')) {
      final normalized = _normalizeType(match.namedGroup('type'));
      if (normalized != null) finalType = normalized;
    }
    final bool typeValid = finalType == 'CREDIT' || finalType == 'DEBIT';

    // --- counterparty (drives self-transfer pairing downstream) ---
    bool counterparty = _firstNonEmpty(match, _counterpartyGroups) != null;
    final String? creditor = group('creditor');
    final String? receiver = group('receiver');
    if ((creditor != null && creditor.trim().isNotEmpty) ||
        (receiver != null && receiver.trim().isNotEmpty)) {
      counterparty = true;
    }
    if (!counterparty && finalType.toUpperCase().contains('CREDIT')) {
      final fallback = _fallbackCounterparty(body);
      if (fallback != null && fallback.trim().isNotEmpty) counterparty = true;
    }

    // --- fees ---
    final bool feesExpected = pattern.hasFees == true;
    final bool feesCaptured =
        _optionalAmount(match, const ['serviceCharge', 'ServiceCharge', 'servicecharge', 'service_charge']) != null ||
            _optionalAmount(match, const ['vat', 'VAT']) != null;

    // --- accept-gate (pattern_parser.dart:166-190) ---
    final requiresReference = pattern.refRequired == true;
    final requiresAccount = pattern.hasAccount == true && accountExpected;

    RejectReason reason = RejectReason.none;
    if (!amountParsed) {
      reason = RejectReason.amountMissing;
    } else if (balanceExpected && !balanceCaptured) {
      reason = RejectReason.balanceMissing;
    } else if (requiresReference && !hasEffectiveReference) {
      reason = RejectReason.refMissing;
    } else if (requiresAccount && !accountCaptured) {
      reason = RejectReason.accountMissing;
    }

    return ExtractionOutcome(
      accepted: reason == RejectReason.none,
      reason: reason,
      typeValid: typeValid,
      amountParsed: amountParsed,
      balanceExpected: balanceExpected,
      balanceCaptured: balanceCaptured,
      balanceParsed: balanceParsed,
      counterpartyCaptured: counterparty,
      referenceReal: referenceReal,
      referenceSynthesized: referenceSynthesized,
      accountExpected: accountExpected,
      accountCaptured: accountCaptured,
      feesExpected: feesExpected,
      feesCaptured: feesCaptured,
    );
  }

  // --- helpers, ported verbatim in behavior from pattern_parser.dart ---

  static String? _maskAccount(String? raw, Bank? bank) {
    if (raw == null) return null;
    if (bank?.uniformMasking == true && bank?.maskPattern != null) {
      final mask = bank!.maskPattern!;
      return raw.length >= mask ? raw.substring(raw.length - mask) : raw;
    }
    return raw;
  }

  static String? _firstNonEmpty(RegExpMatch match, List<String> names) {
    final present = match.groupNames.toSet();
    for (final name in names) {
      if (!present.contains(name)) continue;
      final v = match.namedGroup(name);
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  static String? _optionalAmount(RegExpMatch match, List<String> names) {
    final present = match.groupNames.toSet();
    for (final name in names) {
      if (!present.contains(name)) continue;
      final cleaned = _cleanNumber(match.namedGroup(name));
      final value = cleaned == null ? null : double.tryParse(cleaned);
      if (value != null) return cleaned;
      return null;
    }
    return null;
  }

  static String? _fallbackCounterparty(String body) {
    final patterns = [
      RegExp(r'from\s+(.+?)\s+(?:to|on|at|ref|reference|transaction|balance)',
          caseSensitive: false),
      RegExp(r'by\s+(.+?)\s+(?:on|through|ref|reference|transaction|balance)',
          caseSensitive: false),
      RegExp(r'with\s+agent\s+(.+?)\s+(?:on|at|ref|reference|transaction|balance)',
          caseSensitive: false),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(body);
      if (m == null) continue;
      final v = m.group(1)?.trim();
      if (v == null || v.isEmpty) continue;
      final lower = v.toLowerCase();
      if (lower.contains('your account')) continue;
      if (lower.contains('your telebirr')) continue;
      if (lower.contains('your mpesa')) continue;
      return v;
    }
    return null;
  }

  static String? _cleanNumber(String? input) {
    if (input == null) return null;
    String cleaned = input.replaceAll(',', '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9.]$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\.+$'), '');
    return cleaned;
  }

  static String? _normalizeType(String? rawType) {
    if (rawType == null) return null;
    final lower = rawType.toLowerCase();
    if (lower.contains('debit')) return 'DEBIT';
    if (lower.contains('credit')) return 'CREDIT';
    return null;
  }
}
