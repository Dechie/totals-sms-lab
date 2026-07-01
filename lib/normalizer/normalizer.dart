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

    // Free-text entity fields — abstract them so a category isn't fragmented by
    // a person/merchant name, and so the skeleton maps cleanly onto a capture
    // group (see INSIGHTS.md — "actionable patterns").
    //
    // Greeting name: "Dear <Name…>" / "Dear Mr <Name>" / "Dear Customer". This
    // is usually the *account holder's own name* — the main re-identification
    // risk in an exported skeleton — so strip it first. Match a greedy run of
    // Title-case words (optionally a title) right after "Dear"; it stops at the
    // first lower-case word ("have"/"your"/"account") or punctuation. Erring
    // toward over-stripping a capitalized sentence word is privacy-safe.
    _Rule(
        '<NAME>',
        RegExp(
            r"(?<=\bDear\s)(?:(?:Mr|Mrs|Ms|Dr)\.?\s+)?[A-Z][A-Za-z'.-]*(?:\s+[A-Z][A-Za-z'.-]*)*")),

    // Parenthesized counterparty names, e.g. "(Abdurezak Mehabuba Bushira)".
    // Letters/spaces/punctuation only, so "(15%)" / "(5%)" (VAT etc.) are safe.
    _Rule('(<NAME>)', RegExp(r"\([A-Z][A-Za-z .'-]+\)")),
    // Recipient/sender names: "... to Demis Zeleke on ..." / "from Foo Bar on".
    // Title-cased run anchored between to/from and " on" (won't touch
    // "to account ..." since "account" is lower-case).
    _Rule('<NAME>',
        RegExp(r"(?<=\b(?:to|from)\s)[A-Z][a-z]+(?:\s+[A-Z][A-Za-z.'-]+){1,3}(?=\s+on\b)")),
    // Merchant in POS messages: "... at SUPERMARKET on ...".
    _Rule('<MERCHANT>',
        RegExp(r"(?<=\bat\s)[A-Za-z][A-Za-z0-9 &'.-]*?(?=\s+on\b)")),

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

  /// Bodies longer than this are truncated before normalization. Real SMS are
  /// ~a few hundred chars; a multi-KB body is either concatenated junk or a
  /// crafted input that could make a regex pathological. The transaction text
  /// is virtually always in the head, so truncating loses little and bounds the
  /// work per message. Marked as `truncated` on the result.
  static const _maxBodyLen = 8000;

  /// Returns the normalized template for [body].
  String normalize(String body) => normalizeWithSpans(body).template;

  /// Like [normalize], but also returns the raw text each placeholder replaced,
  /// grouped by field name (`AMOUNT`, `NAME`, …). These spans are what the
  /// `ShapeProfiler` generalizes into a privacy-safe per-field regex
  /// (FIELD_SHAPES.md). The [NormalizationResult.template] is byte-identical to
  /// [normalize]'s output, so coverage/clustering are unaffected.
  ///
  /// Rules run in order and each match is replaced by a placeholder before the
  /// next rule runs, so every raw span is captured exactly once, by the rule
  /// that claimed it (later rules only see placeholders, never raw values).
  NormalizationResult normalizeWithSpans(String body) {
    final spans = <String, List<String>>{};
    var truncated = false;
    var degraded = false;

    var text = body;
    if (text.length > _maxBodyLen) {
      text = text.substring(0, _maxBodyLen);
      truncated = true;
    }

    for (final rule in _rules) {
      // Isolate each rule: a single pathological input must not lose the work
      // of the other rules (or crash the run). A failed rule leaves its target
      // un-stripped, so the result is marked degraded — callers that care about
      // anonymization (export) redact it rather than risk leaking a raw value.
      try {
        text = text.replaceAllMapped(rule.regex, (m) {
          (spans[rule.field] ??= <String>[]).add(m[0]!);
          return rule.placeholder;
        });
      } catch (_) {
        degraded = true;
      }
    }
    return NormalizationResult(_collapseWhitespace(text), spans,
        degraded: degraded, truncated: truncated);
  }

  String _collapseWhitespace(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// A normalized template plus the raw spans each placeholder replaced (keyed by
/// field name, no angle brackets). The spans are for *local* shape analysis
/// only — never exported (they can carry real names/values); the exported
/// artifact is the generalized regex the `ShapeProfiler` derives from them.
class NormalizationResult {
  final String template;
  final Map<String, List<String>> spans;

  /// A normalization rule failed on this body — anonymization is not guaranteed,
  /// so the template must not be trusted or exported verbatim.
  final bool degraded;

  /// The body was truncated to a safe length before normalization.
  final bool truncated;

  const NormalizationResult(this.template, this.spans,
      {this.degraded = false, this.truncated = false});
}

class _Rule {
  final String placeholder;
  final RegExp regex;

  /// Field name extracted from the placeholder (`(<NAME>)` → `NAME`).
  final String field;

  _Rule(this.placeholder, this.regex)
      : field = RegExp(r'<([A-Z]+)>').firstMatch(placeholder)!.group(1)!;
}
