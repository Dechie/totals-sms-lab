import 'package:sms_pattern_lab/filtering/transaction_heuristic.dart';
import 'package:test/test.dart';

void main() {
  bool t(String s) => TransactionHeuristic.looksLikeTransaction(s);

  test('accepts real transaction messages', () {
    expect(t('Your account was debited with ETB 500.00. Balance ETB 1,000.'),
        isTrue);
    expect(t('You have received ETB 1,200.00 to account 5****8821. Ref HB9921.'),
        isTrue);
    expect(t('POS purchase of ETB 350 at MERCHANT.'), isTrue);
  });

  test('rejects non-transaction noise', () {
    expect(t('Your verification code is 884512. Do not share it with anyone.'),
        isFalse);
    expect(t('Welcome to our app! Enjoy 20% off this weekend.'), isFalse);
    expect(t(''), isFalse);
  });

  test('requires a transaction keyword AND (supporting keyword OR amount)', () {
    // transaction keyword but no support/amount → rejected
    expect(t('Your transfer is being processed.'), isFalse);
    // transaction keyword + amount → accepted
    expect(t('transferred ETB 200'), isTrue);
    // transaction keyword + supporting keyword (balance) → accepted
    expect(t('Amount credited; new balance available.'), isTrue);
  });
}
