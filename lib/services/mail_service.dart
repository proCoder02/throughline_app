import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_client.dart';

/// Linked mailboxes (read-only) for the global chat -- Outlook (Microsoft
/// Graph) and Gmail (Gmail API). The mail access itself happens
/// server-side through the chat's outlook_*/gmail_* agent tools; this is
/// only connect/status/disconnect plus opening a cited email. When a
/// provider's flag is off server-side, its status() reports enabled:false
/// and its other calls 404, same contract as CommerceService.
enum MailProvider {
  outlook(
    label: 'Outlook',
    blurb: 'Connect your Outlook or Microsoft 365 mailbox, then ask about your email right in chat.',
    signedOutReason: 'Microsoft signed this connection out (a password change or expired sign-in does this).',
    // Opens the Outlook app itself (no documented per-message deep link).
    appUri: 'ms-outlook://emails',
    revokeLinks: {
      'Personal account': 'https://account.live.com/consent/Manage',
      'Work or school account': 'https://myapps.microsoft.com',
    },
  ),
  gmail(
    label: 'Gmail',
    blurb: 'Connect your Gmail, then ask about your email right in chat.',
    signedOutReason:
        'Google signed this connection out (it does this weekly while our Google access is still being verified, or after a password change).',
    // Gmail's iOS app scheme; on Android the Gmail app claims the
    // mail.google.com link itself (step 1 of MailStatus.openEmail).
    appUri: 'googlegmail://',
    revokeLinks: {'Google account connections': 'https://myaccount.google.com/connections'},
  );

  const MailProvider({
    required this.label,
    required this.blurb,
    required this.signedOutReason,
    required this.appUri,
    required this.revokeLinks,
  });

  final String label;
  final String blurb;
  final String signedOutReason;
  final String appUri;
  final Map<String, String> revokeLinks;

  /// Sources saved before Gmail existed carry no provider -- they were Outlook.
  static MailProvider of(Object? key) => key == 'gmail' ? MailProvider.gmail : MailProvider.outlook;
}

class MailService {
  final MailProvider provider;
  MailService(this.provider);

  final _api = ApiClient.instance;
  String get _base => '/integrations/${provider.name}';

  /// {enabled, accounts: [{id, email, connected_at, needs_reconnect}],
  /// (gmail) weekly_reconnect, plus single-account legacy fields}
  Future<Map<String, dynamic>> status() async {
    final r = await _api.dio.get('$_base/status');
    return Map<String, dynamic>.from(r.data);
  }

  /// Opens the provider's sign-in screen in the system browser. Fetches the
  /// authorize URL over an authenticated Dio request first (connect_url) --
  /// a system browser can't carry this app's Bearer token. The backend
  /// marks the attempt as the 'app' client, so its callback page says to
  /// come back here; MailStatus picks up the result when the app resumes.
  /// Signing in with a different account ADDS a mailbox; [loginHint] (an
  /// already-linked address) reconnects that one.
  Future<void> connect({String? loginHint}) async {
    final r = await _api.dio.get('$_base/connect_url',
        queryParameters: {if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint});
    await launchUrl(Uri.parse(r.data['url'] as String), mode: LaunchMode.externalApplication);
  }

  /// One mailbox, or (null) every linked mailbox for this provider.
  Future<void> disconnect({int? accountId}) =>
      _api.dio.post('$_base/disconnect', data: {if (accountId != null) 'account_id': accountId});
}

enum OpenedEmail { exact, appInbox, browser, failed }

/// App-wide linked-mailbox status, shared by Settings and the global chat
/// (suggestion chips, "Checking your inbox…") -- one ValueNotifier per
/// provider rather than per-screen fetches, so connecting/disconnecting in
/// Settings updates the chat too. Same idea as the web client's lib/mail.js.
class MailStatus {
  MailStatus._();

  /// Per provider; a null value = not loaded yet.
  static final Map<MailProvider, ValueNotifier<Map<String, dynamic>?>> notifiers = {
    for (final p in MailProvider.values) p: ValueNotifier<Map<String, dynamic>?>(null),
  };

  /// Fires when any provider's status changes.
  static final Listenable any = Listenable.merge(notifiers.values.toList());

  static final Map<MailProvider, Future<void>> _inflight = {};

  static Future<void> refresh([MailProvider? only]) {
    final targets = only == null ? MailProvider.values : [only];
    return Future.wait(targets.map((p) => _inflight[p] ??= MailService(p).status().then((s) {
          notifiers[p]!.value = s;
        }).catchError((_) {
          notifiers[p]!.value ??= {'enabled': false};
        }).whenComplete(() => _inflight.remove(p))));
  }

  /// Loads once if nothing is known yet; otherwise a no-op.
  static Future<void> ensureLoaded() =>
      notifiers.values.any((n) => n.value == null) ? refresh() : Future.value();

  static Map<String, dynamic>? of(MailProvider p) => notifiers[p]!.value;

  /// A provider status's linked mailboxes ({id, email, connected_at,
  /// needs_reconnect}) -- tolerates a backend that predates multi-account.
  static List<Map<String, dynamic>> accounts(Map<String, dynamic>? s) {
    if (s?['enabled'] != true) return const [];
    final list = s?['accounts'];
    if (list is List) return list.whereType<Map>().map((a) => Map<String, dynamic>.from(a)).toList();
    return s?['connected'] == true
        ? [{'id': null, 'email': s?['email'], 'connected_at': s?['connected_at'], 'needs_reconnect': s?['needs_reconnect'] == true}]
        : const [];
  }

  /// At least one of this provider's mailboxes is usable for chat right now.
  static bool ready(Map<String, dynamic>? s) => accounts(s).any((a) => a['needs_reconnect'] != true);

  static bool anyReady() => MailProvider.values.any((p) => ready(of(p)));

  /// Linked mailboxes across providers -- source tiles name the mailbox an
  /// email came from only when there's more than one.
  static int linkedCount() => MailProvider.values.fold(0, (n, p) => n + accounts(of(p)).length);

  // Mirrors mail_common._MAIL_INTENT_RE -- only picks the waiting label,
  // never whether the backend actually uses mail.
  static final _mailIntent = RegExp(r'\b(?:inbox|outlook|gmail|e-?mails?|mails?|unread)\b', caseSensitive: false);

  static String? pendingLabel(String text) =>
      anyReady() && _mailIntent.hasMatch(text) ? 'Checking your inbox…' : null;

  // Gmail links saved by the first release used /mail/u/?authuser=<addr>#all/<id>,
  // whose authuser redirect can drop the #fragment -- rewrite them to the
  // /mail/u/<addr>/#all/<id> form new replies already carry.
  static final _oldGmailLink = RegExp(r'^https://mail\.google\.com/mail/u/\?authuser=([^#]+)#all/(.+)$');

  static String _fixOldGmailLink(String link) {
    final m = _oldGmailLink.firstMatch(link);
    return m == null ? link : 'https://mail.google.com/mail/u/${Uri.decodeComponent(m.group(1)!)}/#all/${m.group(2)}';
  }

  static const examplePrompts = [
    'Summarize my unread emails',
    'Anything urgent in my inbox today?',
    'What did I get emailed about this week?',
  ];

  /// Opens a cited email, preferring the provider's app over the browser.
  /// Neither Outlook nor Gmail documents a deep link to one message by its
  /// API id, so this tries, in order:
  ///  1. the message's web link with a non-browser handler -- lands on that
  ///     exact email whenever the installed app claims the link;
  ///  2. the provider's app itself -- right app, but the caller should say
  ///     which email to look for ([OpenedEmail.appInbox]);
  ///  3. the web link in the browser, when the app isn't installed.
  static Future<OpenedEmail> openEmail(MailProvider provider, String? webLink) async {
    final link = webLink == null ? null : Uri.tryParse(_fixOldGmailLink(webLink));
    if (link != null && link.hasScheme) {
      try {
        if (await launchUrl(link, mode: LaunchMode.externalNonBrowserApplication)) return OpenedEmail.exact;
      } catch (_) {}
    }
    try {
      if (await launchUrl(Uri.parse(provider.appUri), mode: LaunchMode.externalApplication)) {
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
}
