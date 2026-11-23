import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models/transaction.dart';
import '../../services/api_client.dart';
import '../../services/conversation_service.dart';
import '../../services/local_cache.dart';

/// Money the user promised in a conversation ("Send Ravi 500 for the
/// tickets"), from GET /pay/owed.
class OwedItem {
  final int taskId;
  final String text;
  final double? amount;
  final String? person;
  final String? reason;
  final String? due;
  final String? sourceTitle;
  final String? suggestedVpa;
  final String? suggestedName;

  const OwedItem({
    required this.taskId,
    required this.text,
    this.amount,
    this.person,
    this.reason,
    this.due,
    this.sourceTitle,
    this.suggestedVpa,
    this.suggestedName,
  });

  factory OwedItem.fromJson(Map<String, dynamic> j) {
    final s = j['suggestion'] as Map<String, dynamic>?;
    return OwedItem(
      taskId: j['task_id'] as int,
      text: j['text'] as String? ?? '',
      amount: (j['amount'] as num?)?.toDouble(),
      person: j['person'] as String?,
      reason: j['reason'] as String?,
      due: j['due'] as String?,
      sourceTitle: j['source_title'] as String?,
      suggestedVpa: s?['vpa'] as String?,
      suggestedName: s?['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'text': text,
        'amount': amount,
        'person': person,
        'reason': reason,
        'due': due,
        'source_title': sourceTitle,
        'suggestion': suggestedVpa == null ? null : {'vpa': suggestedVpa, 'name': suggestedName},
      };

  /// "Ravi · tickets" -- who and what, for one-line display.
  String get title {
    final who = person ?? 'Someone';
    return reason == null ? who : '$who · $reason';
  }
}

/// Someone you've paid before, from GET /pay/recent.
class RecentPayee {
  final String vpa;
  final String name;
  final double lastAmount;
  final String? lastNote;

  const RecentPayee({required this.vpa, required this.name, required this.lastAmount, this.lastNote});

  factory RecentPayee.fromJson(Map<String, dynamic> j) => RecentPayee(
        vpa: j['vpa'] as String,
        name: j['name'] as String? ?? j['vpa'] as String,
        lastAmount: (j['last_amount'] as num?)?.toDouble() ?? 0,
        lastNote: j['last_note'] as String?,
      );

  Map<String, dynamic> toJson() => {'vpa': vpa, 'name': name, 'last_amount': lastAmount, 'last_note': lastNote};
}

/// What Throughline knows about a UPI ID before paying it (GET /pay/payee).
class PayeeMemory {
  final String? label;
  final int timesPaid;
  final double? usualAmount;
  final double? lastAmount;
  final DateTime? lastAt;
  final String? lastNote;
  final List<String> recentNotes;
  final bool newPayee;
  final List<String> warnings;

  const PayeeMemory({
    this.label,
    this.timesPaid = 0,
    this.usualAmount,
    this.lastAmount,
    this.lastAt,
    this.lastNote,
    this.recentNotes = const [],
    this.newPayee = true,
    this.warnings = const [],
  });

  factory PayeeMemory.fromJson(Map<String, dynamic> j) {
    final last = j['last'] as Map<String, dynamic>?;
    return PayeeMemory(
      label: j['label'] as String?,
      timesPaid: j['times_paid'] as int? ?? 0,
      usualAmount: (j['usual_amount'] as num?)?.toDouble(),
      lastAmount: (last?['amount'] as num?)?.toDouble(),
      lastAt: last?['at'] == null ? null : DateTime.tryParse(last!['at'] as String)?.toLocal(),
      lastNote: last?['note'] as String?,
      recentNotes: (j['recent_notes'] as List?)?.cast<String>() ?? const [],
      newPayee: j['new_payee'] as bool? ?? true,
      warnings: (j['warnings'] as List?)?.cast<String>() ?? const [],
    );
  }
}

class PaySnapshot {
  final List<OwedItem> owed;
  final List<RecentPayee> recent;
  const PaySnapshot(this.owed, this.recent);
  static const empty = PaySnapshot([], []);
}

/// Pay memory endpoints (server: pay/ package). Every call degrades quietly:
/// if the server doesn't have them yet, Pay works exactly as before.
class PayApi {
  PayApi._();
  static final PayApi instance = PayApi._();

  Dio get _dio => ApiClient.instance.dio;

  /// Last-known "You owe" + recent payees, for an instant first paint.
  PaySnapshot cached() {
    try {
      final raw = LocalCache.instance.getPaySnapshot();
      if (raw == null) return PaySnapshot.empty;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return PaySnapshot(
        (j['owed'] as List).map((e) => OwedItem.fromJson(e as Map<String, dynamic>)).toList(),
        (j['recent'] as List).map((e) => RecentPayee.fromJson(e as Map<String, dynamic>)).toList(),
      );
    } catch (_) {
      return PaySnapshot.empty;
    }
  }

  Future<PaySnapshot> refresh() async {
    final results = await Future.wait([_dio.get('/pay/owed'), _dio.get('/pay/recent')]);
    final owed = ((results[0].data as Map)['items'] as List)
        .map((e) => OwedItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final recent = ((results[1].data as Map)['payees'] as List)
        .map((e) => RecentPayee.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    try {
      await LocalCache.instance.setPaySnapshot(jsonEncode({
        'owed': owed.map((o) => o.toJson()).toList(),
        'recent': recent.map((r) => r.toJson()).toList(),
      }));
    } catch (_) {}
    return PaySnapshot(owed, recent);
  }

  Future<void> dismiss(int taskId) => _dio.post('/pay/owed/$taskId/dismiss');

  Future<PayeeMemory?> payee(String vpa, {String? shownName}) async {
    try {
      final r = await _dio.get('/pay/payee', queryParameters: {'vpa': vpa, if (shownName != null) 'name': shownName});
      return PayeeMemory.fromJson(Map<String, dynamic>.from(r.data as Map));
    } catch (_) {
      return null; // no memory shown; paying still works
    }
  }

  Future<void> setLabel(String vpa, String label) => _dio.put('/pay/payee', data: {'vpa': vpa, 'label': label});

  /// Saves a payment the user confirmed. Returns the promise it closed, if
  /// any. Falls back to the original POST /transactions when the server
  /// doesn't have /pay/record (older server) -- the payment is never lost.
  Future<String?> record({
    required String vpa,
    required String payeeName,
    required double amount,
    required String app,
    String? note,
    int? taskId,
  }) async {
    try {
      final r = await _dio.post('/pay/record', data: {
        'vpa': vpa,
        'payee_name': payeeName,
        'amount': amount,
        'app': app,
        if (note != null) 'note': note,
        if (taskId != null) 'task_id': taskId,
      });
      final closed = (r.data as Map)['closed_task'] as Map?;
      return closed?['text'] as String?;
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
      await ConversationService().saveTransaction(
        null,
        Transaction(amount: amount, payee: payeeName, paymentMethod: app, item: note),
      );
      return null;
    }
  }
}
