/// Parsing and rebuilding of UPI payment links (`upi://pay?pa=...&pn=...`),
/// the format every Indian UPI QR code encodes (NPCI "UPI Linking
/// Specification"). Pure Dart, no Flutter imports, so it's unit-testable --
/// see test/pay/upi_link_test.dart.
///
/// The original query parameters are kept in their scanned order and raw
/// encoding wherever possible: merchant QRs can carry `mc`, `tr`, `mode`,
/// `orgid` and a `sign` over the values, and changing any of them makes the
/// payer's UPI app reject the payment. We only ever *add* `am` (amount),
/// `cu` (currency) and `tn` (note) when the QR didn't already have them.
class UpiLink {
  /// Raw `key=value` pairs exactly as scanned (value still percent-encoded).
  final List<MapEntry<String, String>> _rawParams;

  UpiLink._(this._rawParams);

  /// Returns null for anything that isn't a usable UPI pay link -- other QR
  /// codes (URLs, Meet cards, Wi-Fi), or a UPI link with no valid payee.
  static UpiLink? tryParse(String? text) {
    if (text == null) return null;
    final trimmed = text.trim();
    final q = trimmed.indexOf('?');
    if (q <= 0) return null;
    final base = trimmed.substring(0, q).toLowerCase();
    if (base != 'upi://pay' && base != 'upi://pay/') return null;

    final params = <MapEntry<String, String>>[];
    for (final part in trimmed.substring(q + 1).split('&')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      params.add(MapEntry(part.substring(0, eq).toLowerCase(), part.substring(eq + 1)));
    }
    final link = UpiLink._(params);
    if (!_isValidVpa(link.payeeVpa)) return null;
    return link;
  }

  static bool _isValidVpa(String? vpa) =>
      vpa != null && RegExp(r'^[A-Za-z0-9.\-_]{1,256}@[A-Za-z0-9.\-_]{2,64}$').hasMatch(vpa);

  static String _decode(String raw) {
    try {
      return Uri.decodeQueryComponent(raw);
    } catch (_) {
      return raw;
    }
  }

  String? _get(String key) {
    for (final p in _rawParams) {
      if (p.key == key) {
        final v = _decode(p.value).trim();
        return v.isEmpty ? null : v;
      }
    }
    return null;
  }

  /// The payee's UPI ID, e.g. `shop@okaxis`.
  String? get payeeVpa => _get('pa');

  /// The payee's display name, if the QR has one.
  String? get payeeName => _get('pn');

  /// A note the QR already carries (`tn`).
  String? get note => _get('tn');

  /// Merchant category code. Present on merchant QRs, absent (or `0000`)
  /// on personal ones.
  String? get merchantCode => _get('mc');

  /// True for business/merchant QRs. Intent payments to personal UPI IDs
  /// are often declined by UPI apps, so the UI warns about those.
  bool get isMerchant {
    final mc = merchantCode;
    return mc != null && mc != '0000';
  }

  /// The amount fixed by the QR (dynamic merchant QRs), or null when the
  /// payer has to enter it.
  double? get fixedAmount {
    final am = _get('am');
    if (am == null) return null;
    final v = double.tryParse(am);
    return (v != null && v > 0) ? v : null;
  }

  /// Best label for the payee: name if present, otherwise the UPI ID.
  String get displayName => payeeName ?? payeeVpa!;

  /// Builds the link to launch, with the amount (and optionally a note)
  /// added. [scheme] picks the target: `upi://pay` (system chooser) or an
  /// app-specific prefix like `tez://upi/pay` -- see UpiApp.
  ///
  /// [amount] is ignored when the QR already fixes one.
  Uri build({String scheme = 'upi://pay', required double amount, String? note}) {
    final params = <String>[];
    var hasAm = false, hasCu = false, hasTn = false;
    for (final p in _rawParams) {
      if (p.key == 'am') {
        if (fixedAmount == null) continue; // empty/zero am: replaced below
        hasAm = true;
      }
      if (p.key == 'cu') hasCu = true;
      if (p.key == 'tn') {
        if (note != null && note.trim().isNotEmpty && this.note == null) continue;
        hasTn = true;
      }
      params.add('${p.key}=${_safe(p.value)}');
    }
    if (!hasAm) params.add('am=${amount.toStringAsFixed(2)}');
    if (!hasCu) params.add('cu=INR');
    if (!hasTn && note != null && note.trim().isNotEmpty) {
      params.add('tn=${Uri.encodeComponent(note.trim())}');
    }
    return Uri.parse('$scheme?${params.join('&')}');
  }

  /// Keeps an already-valid raw value untouched (so signed merchant params
  /// stay byte-identical); re-encodes values the QR printed unescaped,
  /// e.g. `pn=Ram Kumar` with a literal space.
  static String _safe(String raw) {
    if (RegExp(r"^[A-Za-z0-9\-._~%!$'()*+,;:@/]*$").hasMatch(raw)) return raw;
    return Uri.encodeComponent(_decode(raw));
  }
}
