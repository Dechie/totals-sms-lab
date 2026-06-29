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

  const ParseResult({
    required this.message,
    required this.matched,
    this.bankId,
    this.bankName,
    this.transactionType,
    this.matchedPatternDescription,
  });

  /// True when we couldn't even attribute the message to a bank.
  bool get isUnattributed => bankId == null;
}
