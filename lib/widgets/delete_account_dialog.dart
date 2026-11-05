import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/consent_service.dart' show openLegalPage;
import '../theme.dart';

/// Settings → Delete account: password + typing DELETE, then the server
/// removes the account and its data (POST /account/delete). Returns true
/// when the account was deleted -- the caller then signs out.
Future<bool> showDeleteAccountDialog(BuildContext context) async {
  final deleted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DeleteAccountDialog(),
  );
  return deleted == true;
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password.');
      return;
    }
    if (_confirm.text.trim() != 'DELETE') {
      setState(() => _error = 'Type DELETE (in capitals) to confirm.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ApiClient.instance.dio.post('/account/delete', data: {'password': _password.text, 'confirm': 'DELETE'});
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map && data['error'] is String
          ? data['error'] as String
          : 'Could not delete your account. Check your connection and try again.';
      if (mounted) {
        setState(() {
          _busy = false;
          _error = msg;
        });
      }
    }
  }

  InputDecoration _decoration(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.dmTextSoft),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        suffixIcon: suffix,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.dmBubbleIn,
      title: Text('Delete your account?', style: TextStyle(color: AppColors.dmText)),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(
            "This permanently deletes your account and everything stored with it -- recordings' transcripts, notes, "
            "tasks, chats, messages, files and connected accounts. It can't be undone.",
            style: TextStyle(color: AppColors.dmTextSoft, height: 1.4),
          ),
          TextButton(
            onPressed: () => openLegalPage('/account/delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.dmAccent, padding: EdgeInsets.zero),
            child: const Text('What gets deleted'),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _password,
            obscureText: _obscure,
            enabled: !_busy,
            autofillHints: const [AutofillHints.password],
            style: TextStyle(color: AppColors.dmText),
            decoration: _decoration(
              'Your password',
              suffix: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            enabled: !_busy,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            style: TextStyle(color: AppColors.dmText),
            decoration: _decoration('Type DELETE to confirm'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy ? null : _delete,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
          child: Text(_busy ? 'Deleting…' : 'Delete permanently'),
        ),
      ],
    );
  }
}
