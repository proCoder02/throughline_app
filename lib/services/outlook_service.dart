import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

/// Outlook mail (read-only Microsoft Graph) -- connect/status/disconnect for
/// the Settings screen. The mail access itself happens server-side through
/// the global chat's outlook_* agent tools, so there's nothing else to call
/// from here. When OUTLOOK_ENABLED is off server-side, status() reports
/// enabled:false and the other calls 404, same contract as CommerceService.
class OutlookService {
  final _api = ApiClient.instance;

  /// {enabled, connected, needs_reconnect, email, connected_at}
  Future<Map<String, dynamic>> status() async {
    final r = await _api.dio.get('/integrations/outlook/status');
    return Map<String, dynamic>.from(r.data);
  }

  /// Opens Microsoft's sign-in screen in the system browser. Fetches the
  /// authorize URL over an authenticated Dio request first (connect_url) --
  /// same reason as CommerceService.connect: a system browser can't carry
  /// this app's Bearer token. The backend marks this attempt as the 'app'
  /// client, so its callback page says to come back here; OutlookStatus
  /// picks up the result when the app resumes.
  Future<void> connect() async {
    final r = await _api.dio.get('/integrations/outlook/connect_url');
    final url = Uri.parse(r.data['url'] as String);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> disconnect() {
    return _api.dio.post('/integrations/outlook/disconnect', data: {});
  }
}

enum OpenedEmail { exact, appInbox, browser, failed }

/// App-wide Outlook link status, shared by Settings and the global chat
/// (suggestion chips, "Checking your inbox…") -- one ValueNotifier rather
/// than per-screen fetches, so connecting/disconnecting in Settings updates
/// the chat too. Same idea as the web client's lib/outlook.js store.
class OutlookStatus {
  OutlookStatus._();

  /// null = not loaded yet.
  static final ValueNotifier<Map<String, dynamic>?> notifier = ValueNotifier(null);
  static final _service = OutlookService();
  static Future<void>? _inflight;

  static Future<void> refresh() {
    return _inflight ??= _service.status().then((s) {
      notifier.value = s;
    }).catchError((_) {
      notifier.value ??= {'enabled': false};
    }).whenComplete(() => _inflight = null);
  }

  /// Loads once if nothing is known yet; otherwise a no-op.
  static Future<void> ensureLoaded() => notifier.value == null ? refresh() : Future.value();

  /// Connected and usable for chat right now.
  static bool ready(Map<String, dynamic>? s) =>
      s?['enabled'] == true && s?['connected'] == true && s?['needs_reconnect'] != true;

  // Mirrors outlook/adapter.py's _MAIL_INTENT_RE -- only picks the waiting
  // label, never whether the backend actually uses mail.
  static final _mailIntent = RegExp(r'\b(?:inbox|outlook|e-?mails?|mails?|unread)\b', caseSensitive: false);

  static String? pendingLabel(String text) =>
      ready(notifier.value) && _mailIntent.hasMatch(text) ? 'Checking your inbox…' : null;

  static const examplePrompts = [
    'Summarize my unread emails',
    'Anything urgent in my inbox today?',
    'What did I get emailed about this week?',
  ];

  /// Opens an email from a mail source, preferring the Outlook app over
  /// the browser. Outlook mobile has no documented deep link to a single
  /// message by its Graph id, so this tries, in order:
  ///  1. the message's webLink with a non-browser handler -- lands on that
  ///     exact email whenever the installed Outlook app claims the link;
  ///  2. the Outlook app itself (ms-outlook://emails) -- right app, but the
  ///     caller should say which email to look for (returns
  ///     [OpenedEmail.appInbox]);
  ///  3. the webLink in the browser, when Outlook isn't installed.
  static Future<OpenedEmail> openEmail(String? webLink) async {
    final link = webLink == null ? null : Uri.tryParse(webLink);
    if (link != null && link.hasScheme) {
      try {
        if (await launchUrl(link, mode: LaunchMode.externalNonBrowserApplication)) return OpenedEmail.exact;
      } catch (_) {}
    }
    try {
      if (await launchUrl(Uri.parse('ms-outlook://emails'), mode: LaunchMode.externalApplication)) {
        return OpenedEmail.appInbox;
      }
    } catch (_) {}
    if (link != null && link.hasScheme) {
      try {
        if (await launchUrl(link, mode: LaunchMode.externalApplication)) return OpenedEmail.browser;
      } catch (_) {}
    }
    return OpenedEmail.failed;
  }

  /// Where a user fully revokes the app on Microsoft's side -- Disconnect
  /// only deletes our saved sign-in.
  static const revokeLinks = {
    'Personal account': 'https://account.live.com/consent/Manage',
    'Work or school account': 'https://myapps.microsoft.com',
  };
}
