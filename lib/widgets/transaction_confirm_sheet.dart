import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../theme.dart';

/// Shown right after a receipt share produces a Transaction (see
/// GlobalChatBody's post-_sendImage hook) -- lets the user fix a misread
/// amount/payee/category before it's actually saved via
/// ConversationService.saveTransaction, same showModalBottomSheet pattern
/// as _showDescribeImageSheet in global_chat_body.dart. Returns the
/// (possibly edited) Transaction on Save, or null on Discard.
Future<Transaction?> showTransactionConfirmSheet(BuildContext context, Transaction transaction) {
  final amountController = TextEditingController(text: transaction.amount.toStringAsFixed(2));
  final itemController = TextEditingController(text: transaction.item ?? '');
  final payeeController = TextEditingController(text: transaction.payee ?? '');
  final categoryController = TextEditingController(text: transaction.category ?? '');
  final paymentMethodController = TextEditingController(text: transaction.paymentMethod ?? '');

  return showModalBottomSheet<Transaction>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.dmAccent, size: 20),
                  const SizedBox(width: 8),
                  Text('Save this payment?',
                      style: appHeadlineFont(color: AppColors.dmText, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Check the amount before it\'s saved to your spending.',
                style: TextStyle(fontSize: 12.5, color: AppColors.dmTextSoft),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: 'Rs ',
                  filled: true,
                  fillColor: AppColors.dmBubbleIn,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: itemController,
                decoration: InputDecoration(
                  labelText: 'What for (optional)',
                  hintText: 'e.g. Power bank',
                  filled: true,
                  fillColor: AppColors.dmBubbleIn,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: payeeController,
                decoration: InputDecoration(
                  labelText: 'Paid to',
                  filled: true,
                  fillColor: AppColors.dmBubbleIn,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: categoryController,
                decoration: InputDecoration(
                  labelText: 'Category',
                  filled: true,
                  fillColor: AppColors.dmBubbleIn,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: paymentMethodController,
                decoration: InputDecoration(
                  labelText: 'Paid via',
                  filled: true,
                  fillColor: AppColors.dmBubbleIn,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('Discard'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final amount = double.tryParse(amountController.text.trim());
                        if (amount == null) return;
                        Navigator.of(sheetContext).pop(Transaction(
                          amount: amount,
                          item: itemController.text.trim().isEmpty ? null : itemController.text.trim(),
                          payee: payeeController.text.trim().isEmpty ? null : payeeController.text.trim(),
                          category:
                              categoryController.text.trim().isEmpty ? null : categoryController.text.trim(),
                          paymentMethod: paymentMethodController.text.trim().isEmpty
                              ? null
                              : paymentMethodController.text.trim(),
                        ));
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
