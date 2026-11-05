import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../main.dart' show navigatorKey;
import '../theme.dart';
import 'api_client.dart';

/// Consent notices the backend tracks per user and version (see the
/// server's legal/__init__.py): the recording notice, shown once before the
/// first Listen or call, and the Terms/Privacy agreement. Lives here rather
/// than in each screen so ListenProvider/CallProvider can ask it directly --
/// every way of starting a recording goes through those two.
class ConsentService {
  ConsentService._();
  static final ConsentService instance = ConsentService._();

  Map<String, dynamic>? _status;
  int? _statusUserId;

  /// Per account: drop the cached answers when the signed-in user changes.
  void reset() {
    _status = null;
    _statusUserId = null;
  }

  Future<Map<String, dynamic>> status({int? userId, bool force = false}) async {
    if (!force && _status != null && (userId == null || userId == _statusUserId)) return _status!;
    final r = await ApiClient.instance.dio.get('/consents');
    _status = Map<String, dynamic>.from(r.data as Map);
    _statusUserId = userId;
    return _status!;
  }

  Future<void> accept(String kind) async {
    final r = await ApiClient.instance.dio.post('/consents', data: {'kind': kind});
    final data = Map<String, dynamic>.from(r.data as Map)..remove('ok');
    _status = data;
  }

  bool _needed(Map<String, dynamic>? s, String kind) {
    final entry = s?[kind];
    return entry is! Map || entry['needed'] == true;
  }

  Future<bool> termsNeeded({int? userId}) async {
    try {
      return _needed(await status(userId: userId, force: true), 'terms');
    } catch (_) {
      return false; // offline: don't block the app over this
    }
  }

  /// True once the user has accepted the current recording notice
  /// (immediately if they already had), false if they cancel. If the status
  /// can't be loaded the notice is shown anyway -- never skipped silently.
  Future<bool> ensureRecordingNotice() async {
    var needed = true;
    try {
      needed = _needed(await status(), 'recording_notice');
    } catch (_) {}
    if (!needed) return true;
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _RecordingNoticeDialog(),
    );
    return accepted == true;
  }
}

Future<void> openLegalPage(String path) async {
  await launchUrl(Uri.parse('${ApiConfig.baseUrl}$path'), mode: LaunchMode.externalApplication);
}

class _RecordingNoticeDialog extends StatefulWidget {
  const _RecordingNoticeDialog();

  @override
  State<_RecordingNoticeDialog> createState() => _RecordingNoticeDialogState();
}

class _RecordingNoticeDialogState extends State<_RecordingNoticeDialog> {
  bool _checked = false;
  bool _saving = false;
  String? _error;

  Future<void> _continue() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ConsentService.instance.accept('recording_notice');
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save that. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final soft = TextStyle(color: AppColors.dmTextSoft, height: 1.4);
    Widget bullet(String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('•  ', style: soft),
            Expanded(child: Text(text, style: soft)),
          ]),
        );
    return AlertDialog(
      backgroundColor: AppColors.dmBubbleIn,
      title: Row(children: [
        Icon(Icons.mic_none, color: AppColors.dmAccent),
        const SizedBox(width: 8),
        Text('Before you record', style: TextStyle(color: AppColors.dmText)),
      ]),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(
            "Throughline turns what's said into a transcript and notes in your account. That includes other "
            "people's voices -- on calls, everyone on the call.",
            style: soft,
          ),
          bullet('Tell people before you record them, and get their consent wherever the law requires it.'),
          bullet("Don't record anyone secretly or where they expect privacy."),
          bullet("Audio is deleted once it's transcribed; the transcript stays until you delete it."),
          TextButton(
            onPressed: () => openLegalPage('/privacy'),
            style: TextButton.styleFrom(foregroundColor: AppColors.dmAccent, padding: EdgeInsets.zero),
            child: const Text('How recordings are handled'),
          ),
          CheckboxListTile(
            value: _checked,
            onChanged: _saving ? null : (v) => setState(() => _checked = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.dmAccent,
            title: Text("I'll tell people before I record them.",
                style: TextStyle(color: AppColors.dmText, fontWeight: FontWeight.w600)),
          ),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_checked && !_saving) ? _continue : null,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.dmAccent, foregroundColor: Colors.white),
          child: Text(_saving ? 'Saving…' : 'Continue'),
        ),
      ],
    );
  }
}

/// One-time Terms/Privacy agreement for accounts that haven't accepted the
/// current version (e.g. created before it existed). No dismiss: agree or
/// log out.
class TermsAgreementDialog extends StatefulWidget {
  const TermsAgreementDialog({super.key, required this.onLogout});
  final Future<void> Function() onLogout;

  @override
  State<TermsAgreementDialog> createState() => _TermsAgreementDialogState();
}

class _TermsAgreementDialogState extends State<TermsAgreementDialog> {
  bool _checked = false;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: AppColors.dmBubbleIn,
        title: Text('Our Terms and Privacy Policy', style: TextStyle(color: AppColors.dmText)),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              'Please review how Throughline handles your data and the rules for using it -- including telling '
              'people before you record them.',
              style: TextStyle(color: AppColors.dmTextSoft, height: 1.4),
            ),
            Wrap(spacing: 4, children: [
              TextButton(
                onPressed: () => openLegalPage('/terms'),
                style: TextButton.styleFrom(foregroundColor: AppColors.dmAccent),
                child: const Text('Terms of Service'),
              ),
              TextButton(
                onPressed: () => openLegalPage('/privacy'),
                style: TextButton.styleFrom(foregroundColor: AppColors.dmAccent),
                child: const Text('Privacy Policy'),
              ),
            ]),
            CheckboxListTile(
              value: _checked,
              onChanged: _saving ? null : (v) => setState(() => _checked = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.dmAccent,
              title: Text('I agree to the Terms of Service and Privacy Policy.',
                  style: TextStyle(color: AppColors.dmText, fontWeight: FontWeight.w600)),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () async {
                    Navigator.of(context).pop();
                    await widget.onLogout();
                  },
            child: const Text('Log out'),
          ),
          ElevatedButton(
            onPressed: (_checked && !_saving)
                ? () async {
                    setState(() {
                      _saving = true;
                      _error = null;
                    });
                    try {
                      await ConsentService.instance.accept('terms');
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          _saving = false;
                          _error = 'Could not save that. Check your connection and try again.';
                        });
                      }
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dmAccent, foregroundColor: Colors.white),
            child: Text(_saving ? 'Saving…' : 'Agree'),
          ),
        ],
      ),
    );
  }
}
