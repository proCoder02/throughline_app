/// A single payment transaction extracted from a shared UPI receipt
/// (GPay/PhonePe/Paytm) -- see chat_global_image's TRANSACTION section on
/// the backend and POST /transactions (ConversationService.saveTransaction).
class Transaction {
  final int? id;
  final double amount;
  final String? payee;
  final String? category;
  // Which UPI app processed the payment -- a separate dimension from
  // category (what it was for), see transactions table's own comment in
  // the backend's schema.sql.
  final String? paymentMethod;
  // What was actually bought ("Power bank"), distinct from payee ("Blinkit")
  // and category ("Shopping") -- often comes from the user's own
  // description rather than the receipt itself, since most UPI payment
  // confirmations show no line items. See schema.sql's own comment.
  final String? item;

  const Transaction({
    this.id,
    required this.amount,
    this.payee,
    this.category,
    this.paymentMethod,
    this.item,
  });

  /// From chat_global_image's response `transaction` object -- backend-read
  /// values, before the user has had a chance to edit them in the confirm
  /// card. No `id` yet (not saved).
  factory Transaction.fromExtraction(Map<String, dynamic> json) => Transaction(
        amount: (json['amount'] as num).toDouble(),
        payee: json['payee'] as String?,
        category: json['category'] as String?,
        paymentMethod: json['payment_method'] as String?,
        item: json['item'] as String?,
      );

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json['id'] as int?,
        amount: (json['amount'] as num).toDouble(),
        payee: json['payee'] as String?,
        category: json['category'] as String?,
        paymentMethod: json['payment_method'] as String?,
        item: json['item'] as String?,
      );

  Transaction copyWith({
    double? amount,
    String? payee,
    String? category,
    String? paymentMethod,
    String? item,
  }) =>
      Transaction(
        id: id,
        amount: amount ?? this.amount,
        payee: payee ?? this.payee,
        category: category ?? this.category,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        item: item ?? this.item,
      );
}
