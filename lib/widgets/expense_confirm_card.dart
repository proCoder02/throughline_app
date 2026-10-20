import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../services/conversation_service.dart';
import '../theme.dart';
import 'transaction_confirm_sheet.dart';

/// The "review before saving" card a global-chat reply carries as
/// ChatMessage.actionCard when the user states a spend in conversation
/// rather than sharing a receipt (see app.py's log_expense tool /
/// _tool_log_expense) -- nothing is written to `transactions` until the
/// user confirms here, same recommend-then-act shape as EmailDraftCard.
class ExpenseConfirmCard extends StatefulWidget {
  final Map<String, dynamic> card;

  const ExpenseConfirmCard({super.key, required this.card});

  @override
  State<ExpenseConfirmCard> createState() => _ExpenseConfirmCardState();
}

enum _DraftState { pending, busy, saved, dismissed, error }

class _ExpenseConfirmCardState extends State<ExpenseConfirmCard> {
  final _service = ConversationService();
  late _DraftState _state;
  String? _errorText;
  bool _wasDuplicate = false;

  @override
  void initState() {
    super.initState();
    // widget.card is the SAME Map instance held in GlobalChatBodyState's
    // _messages list, which survives ListView.builder disposing/rebuilding
    // this widget on scroll -- so a resolution recorded into it directly
    // (see _save/_discard below) is still there when this State is
    // recreated fresh, instead of always resetting to pending.
    _state = switch (widget.card['_resolvedStatus']) {
      'saved' => _DraftState.saved,
      'dismissed' => _DraftState.dismissed,
      _ => _DraftState.pending,
    };
    _wasDuplicate = widget.card['_wasDuplicate'] == true;
  }

  Transaction get _transaction => Transaction.fromExtraction(widget.card);

  Future<void> _save() async {
    final edited = await showTransactionConfirmSheet(context, _transaction);
    if (edited == null) return;
    setState(() => _state = _DraftState.busy);
    try {
      final duplicate = await _service.saveTransaction(null, edited);
      if (!mounted) return;
      widget.card['_resolvedStatus'] = 'saved';
      widget.card['_wasDuplicate'] = duplicate;
      setState(() {
        _state = _DraftState.saved;
        _wasDuplicate = duplicate;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _DraftState.error;
        _errorText = 'Could not save this expense.';
      });
    }
  }

  void _discard() {
    widget.card['_resolvedStatus'] = 'dismissed';
    setState(() => _state = _DraftState.dismissed);
  }

  Widget _card({required List<Widget> children}) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: isAppDarkMode ? 0.18 : 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.dmBubbleBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
      );

  @override
  Widget build(BuildContext context) {
    if (_state == _DraftState.saved) {
      return _card(children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _wasDuplicate ? 'Already logged -- looks like a duplicate.' : 'Expense saved.',
              style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft),
            ),
          ),
        ]),
      ]);
    }
    if (_state == _DraftState.dismissed) {
      return _card(children: [
        Text('Discarded.', style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft)),
      ]);
    }
    if (_state == _DraftState.error) {
      return _card(children: [
        Text(_errorText ?? 'Something went wrong.', style: TextStyle(fontSize: 13.5, color: AppColors.dmTextSoft)),
      ]);
    }

    final amount = (widget.card['amount'] as num?)?.toDouble() ?? 0;
    final item = widget.card['item'] as String?;
    final payee = widget.card['payee'] as String?;
    final category = widget.card['category'] as String?;
    final paymentMethod = widget.card['payment_method'] as String?;
    final busy = _state == _DraftState.busy;

    final subtitleParts = [
      if (item != null) item,
      if (payee != null) 'to $payee',
      if (category != null) '($category)',
      if (paymentMethod != null) 'via $paymentMethod',
    ];

    return _card(children: [
      Row(children: [
        const Icon(Icons.payments_outlined, size: 18, color: AppColors.dmAccent),
        const SizedBox(width: 8),
        Expanded(child: Text('Rs ${amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
      ]),
      if (subtitleParts.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(subtitleParts.join(' '), style: TextStyle(fontSize: 13, color: AppColors.dmTextSoft)),
      ],
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: busy ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 15),
              label: const Text('Save'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : _discard,
              child: const Text('Discard'),
            ),
          ),
        ],
      ),
    ]);
  }
}
