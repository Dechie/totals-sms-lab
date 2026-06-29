/// A single inbound SMS record from a dataset.
///
/// The input dataset is a JSON array of objects. Only [body] is strictly
/// required; [address] (the sender id, e.g. "CBE", "127") lets the parser
/// adapter scope candidate patterns to a bank.
class SmsMessage {
  /// Sender address / id as it appears on the device (e.g. "CBE", "DashenBank").
  final String? address;

  /// The raw SMS text.
  final String body;

  /// Optional epoch-millis timestamp; used by trend analysis (V3+).
  final int? dateMillis;

  const SmsMessage({
    required this.body,
    this.address,
    this.dateMillis,
  });

  factory SmsMessage.fromJson(Map<String, dynamic> json) {
    // Accept a few common field spellings so real exports drop in cleanly.
    final body = (json['body'] ?? json['message'] ?? json['text'] ?? '')
        .toString();
    final address =
        (json['address'] ?? json['sender'] ?? json['from'])?.toString();
    final rawDate = json['date'] ?? json['dateMillis'] ?? json['timestamp'];
    return SmsMessage(
      body: body,
      address: address,
      dateMillis: rawDate is int
          ? rawDate
          : (rawDate is String ? int.tryParse(rawDate) : null),
    );
  }

  Map<String, dynamic> toJson() => {
        'address': address,
        'body': body,
        'date': dateMillis,
      };
}
