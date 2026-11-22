import 'package:flutter_test/flutter_test.dart';
import 'package:throughline/features/pay/upi_link.dart';

void main() {
  group('UpiLink.tryParse', () {
    test('parses a personal QR', () {
      final l = UpiLink.tryParse('upi://pay?pa=ram.kumar@okhdfcbank&pn=Ram%20Kumar')!;
      expect(l.payeeVpa, 'ram.kumar@okhdfcbank');
      expect(l.payeeName, 'Ram Kumar');
      expect(l.fixedAmount, isNull);
      expect(l.isMerchant, isFalse);
    });

    test('accepts uppercase scheme and unescaped spaces', () {
      final l = UpiLink.tryParse('UPI://PAY?pa=shop@ybl&pn=Sharma General Store&mc=5411')!;
      expect(l.payeeName, 'Sharma General Store');
      expect(l.isMerchant, isTrue);
    });

    test('rejects non-UPI and payee-less codes', () {
      expect(UpiLink.tryParse('https://example.com'), isNull);
      expect(UpiLink.tryParse('upi://pay?pn=NoPayee'), isNull);
      expect(UpiLink.tryParse('upi://pay?pa=not-a-vpa'), isNull);
      expect(UpiLink.tryParse('upi://mandate?pa=a@b'), isNull);
      expect(UpiLink.tryParse(null), isNull);
    });

    test('reads a fixed amount, ignores zero', () {
      expect(UpiLink.tryParse('upi://pay?pa=a@ybl&am=150.50')!.fixedAmount, 150.5);
      expect(UpiLink.tryParse('upi://pay?pa=a@ybl&am=0')!.fixedAmount, isNull);
    });
  });

  group('UpiLink.build', () {
    test('adds amount, currency and note', () {
      final l = UpiLink.tryParse('upi://pay?pa=a@ybl&pn=A%20B')!;
      expect(
        l.build(amount: 99, note: 'tea time').toString(),
        'upi://pay?pa=a@ybl&pn=A%20B&am=99.00&cu=INR&tn=tea%20time',
      );
    });

    test('keeps merchant params byte-identical and the fixed amount', () {
      const raw = 'upi://pay?pa=m@axis&pn=Shop&mc=5411&tr=TXN123&am=250.00&cu=INR&sign=AbC%2B%3D';
      final l = UpiLink.tryParse(raw)!;
      expect(l.build(amount: 1).toString(), raw);
    });

    test('replaces an empty amount and switches app scheme', () {
      final l = UpiLink.tryParse('upi://pay?pa=a@ybl&am=')!;
      expect(
        l.build(scheme: 'tez://upi/pay', amount: 10).toString(),
        'tez://upi/pay?pa=a@ybl&am=10.00&cu=INR',
      );
    });

    test('re-encodes unescaped values', () {
      final l = UpiLink.tryParse('upi://pay?pa=a@ybl&pn=Ram Kumar')!;
      expect(l.build(amount: 5).toString(), 'upi://pay?pa=a@ybl&pn=Ram%20Kumar&am=5.00&cu=INR');
    });
  });
}
