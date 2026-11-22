import 'dart:io' show Platform;

/// A UPI app the payment can be handed to. Each one registers its own URL
/// scheme that accepts the same `?pa=...&am=...` query as `upi://pay`; the
/// schemes must also be declared in AndroidManifest.xml `<queries>` and iOS
/// Info.plist `LSApplicationQueriesSchemes`.
class UpiApp {
  final String name;

  /// Prefix the UpiLink query is appended to.
  final String scheme;

  const UpiApp(this.name, this.scheme);

  static const gpay = UpiApp('Google Pay', 'tez://upi/pay');
  static const phonepe = UpiApp('PhonePe', 'phonepe://pay');
  static const paytm = UpiApp('Paytm', 'paytmmp://pay');

  /// Generic `upi://pay`: Android shows its chooser with every installed UPI
  /// app (BHIM, bank apps, ...). iOS has no such chooser, so it's Android-only.
  static const other = UpiApp('Other UPI app', 'upi://pay');

  static List<UpiApp> get forPlatform =>
      [gpay, phonepe, paytm, if (Platform.isAndroid) other];
}
