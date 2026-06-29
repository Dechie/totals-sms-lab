import '../models/parse_result.dart';
import '../models/sms_message.dart';

/// The generic contract every host-project adapter implements.
///
/// Pattern Lab is deliberately ignorant of *how* a project parses SMS. An
/// adapter's only job is to answer, for each message: was it matched, and by
/// which bank/parser? Swap this interface to point the lab at any other
/// regex-based SMS parsing project.
abstract class ParserAdapter {
  /// Human-readable name of the host parser framework (for reports).
  String get name;

  /// Run the host parser over a single message.
  ParseResult parse(SmsMessage message);

  /// Run the host parser over a whole dataset.
  List<ParseResult> parseAll(Iterable<SmsMessage> messages) =>
      messages.map(parse).toList();

  /// Display name for a bank id (used when attributing unmatched clusters).
  String bankNameFor(int? bankId);
}
