/// Replaces variable information in an SMS with stable placeholders so that
/// thousands of unique messages collapse into a handful of templates.
///
/// Ordering matters: more specific patterns (references, card/account numbers,
/// dates, times) run before generic number/amount patterns, otherwise a bare
/// `\d+` would swallow the digits those patterns rely on.
class Normalizer {
  /// Each rule is `(placeholder, regex)`. Applied in order; earlier, more
  /// specific rules claim text before greedier numeric rules can.
  static final List<_Rule> _rules = [
    // URLs first — receipt links carry per-transaction tokens that would
    // otherwise fragment templates (e.g. .../v2-hfHCxz...., ?id=FT26...).
    _Rule('<URL>',
        RegExp(r'https?://\S+', caseSensitive: false)),

    // Explicit reference ids embedded in URLs/params we've already stripped,
    // plus any stray "id=XXXX" / "Receipt/XXXX" left in plain text.
    _Rule('<REFERENCE>',
        RegExp(r'(?<=(?:id=|Receipt/|BranchReceipt/))[A-Z0-9&]{4,}',
            caseSensitive: false)),

    // Dates: 2024-01-31, 31/01/2024, 31-Jan-2024.
    _Rule('<DATE>', RegExp(r'\b\d{4}[/-]\d{1,2}[/-]\d{1,2}\b')),
    _Rule('<DATE>', RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b')),
    _Rule(
        '<DATE>',
        RegExp(
            r'\b\d{1,2}[ -](?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[ -]\d{2,4}\b',
            caseSensitive: false)),

    // Times: 13:45, 13:45:09, optional AM/PM.
    _Rule('<TIME>',
        RegExp(r'\b\d{1,2}:\d{2}(?::\d{2})?\s?(?:AM|PM)?\b',
            caseSensitive: false)),

    // Masked account numbers (leading digit + stars), e.g. 1****6843, 1**6843.
    _Rule('<ACCOUNT>', RegExp(r'\b\d\*+\d+\b')),

    // Masked card numbers (leading stars), e.g. ****4321. No leading \b so the
    // run of asterisks is captured.
    _Rule('<CARD>', RegExp(r'\*{2,}\d{2,4}\b')),

    // Phone numbers: +2519..., 09xxxxxxxx, 2519xxxxxxxx. Before bare-account so
    // a 10-digit 09... isn't mistaken for an account.
    _Rule('<PHONE>', RegExp(r'\b(?:\+?251|0)?9\d{8}\b')),

    // Monetary amounts: ETB 1,234.56 / ETB500.00 / Br 500 / 1,234.56 ETB.
    // MUST run before the generic reference rule below, otherwise a no-space
    // amount like "ETB500" looks like a mixed letter+digit reference code.
    _Rule(
        '<AMOUNT>',
        RegExp(r'(?:ETB|Br|USD|\$)\s?\d[\d,]*(?:\.\d+)?',
            caseSensitive: false)),
    _Rule('<AMOUNT>',
        RegExp(r'\b\d[\d,]*\.\d{2}\s?(?:ETB|Br)\b', caseSensitive: false)),

    // Generic transaction/reference codes: mixed letter+digit tokens (>=5),
    // e.g. FT26174513JK, DSH889900, CGH7782211. The two lookaheads require at
    // least one letter and one digit, excluding pure-number/pure-word tokens.
    _Rule(
        '<REFERENCE>',
        RegExp(r'\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]{5,}\b',
            caseSensitive: false)),

    // Bare (unmasked) account numbers: 10–16 digit runs.
    _Rule('<ACCOUNT>', RegExp(r'\b\d{10,16}\b')),

    // Any remaining standalone number (counts, residual ids, bare balances).
    _Rule('<NUM>', RegExp(r'\b\d[\d,]*(?:\.\d+)?\b')),
  ];

  /// Returns the normalized template for [body].
  String normalize(String body) {
    var text = body;
    for (final rule in _rules) {
      text = text.replaceAll(rule.regex, rule.placeholder);
    }
    return _collapseWhitespace(text);
  }

  String _collapseWhitespace(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _Rule {
  final String placeholder;
  final RegExp regex;
  const _Rule(this.placeholder, this.regex);
}
