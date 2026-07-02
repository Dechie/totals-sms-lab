import '../parser_adapter/field_extractor.dart';
import 'sms_message.dart';

/// The outcome of running the host parser framework against one [SmsMessage].
///
/// This is the contract between the `parser_adapter` layer and the rest of the
/// lab: the adapter decides *matched vs unmatched* and *who matched*, and the
/// lab analyses those results without re-implementing parsing logic.
class ParseResult {
  final SmsMessage message;

  /// Whether any parser claimed the message.
  final bool matched;

  /// Id of the bank/parser responsible (matched), or the bank the sender
  /// resolved to (unmatched but attributable), or `null` if unknown.
  final int? bankId;

  /// Human-readable parser/bank name for reporting.
  final String? bankName;

  /// Transaction type when matched (e.g. CREDIT/DEBIT).
  final String? transactionType;

  /// Description of the winning pattern, when matched.
  final String? matchedPatternDescription;

  /// Field-level extraction outcome + accept-gate verdict, set only when a
  /// regex [matched]. `null` for unmatched messages. This is what lets the lab
  /// tell "regex matched" apart from "the app would produce a usable
  /// transaction" — see [appAccepted].
  final ExtractionOutcome? extraction;

  const ParseResult({
    required this.message,
    required this.matched,
    this.bankId,
    this.bankName,
    this.transactionType,
    this.matchedPatternDescription,
    this.extraction,
  });

  /// True when we couldn't even attribute the message to a bank.
  bool get isUnattributed => bankId == null;

  /// True when a regex matched AND the app's accept-gate would have returned a
  /// transaction (amount parsed, balance/reference/account present as required).
  bool get appAccepted => extraction?.accepted ?? false;
}
