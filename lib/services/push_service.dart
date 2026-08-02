import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../firebase_options.dart';
import 'api_client.dart';

const _kIncomingCallChannel = AndroidNotificationChannel(
  'incoming_call_channel',
  'Incoming calls',
  description: 'Rings for incoming voice calls',
  importance: Importance.max,
  sound: RawResourceAndroidNotificationSound('incoming_call_ringtone'),
  playSound: true,
  enableVibration: true,
);

const _kPendingCallStorageKey = 'pending_incoming_call';

/// A background isolate (killed-app case) can't touch the running app's
/// providers directly -- persist the call data here, then HomeShell reads
/// and clears it on the next normal startup, regardless of whether that
/// startup was triggered by the full-screen-intent notification, a manual
/// tap, or just the user opening the app after noticing it.
Future<void> _savePendingIncomingCall(Map<String, dynamic> data) async {
  try {
    await const FlutterSecureStorage().write(key: _kPendingCallStorageKey, value: jsonEncode(data));
  } catch (_) {
    // Best-effort -- worst case the call just doesn't auto-show once opened.
  }
}

Future<Map<String, dynamic>?> consumePendingIncomingCall() async {
  const storage = FlutterSecureStorage();
  try {
    final raw = await storage.read(key: _kPendingCallStorageKey);
    if (raw == null) return null;
    await storage.delete(key: _kPendingCallStorageKey);
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<void> _showIncomingCallNotification(RemoteMessage message) async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
  await plugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_kIncomingCallChannel);

  final callerName = message.data['caller_name'] ?? 'Someone';
  await plugin.show(
    // Stable id: a second incoming_call push (e.g. a retry) replaces the
    // same notification instead of stacking duplicates.
    'incoming_call'.hashCode,
    'Incoming call',
    '$callerName is calling...',
    NotificationDetails(
      android: AndroidNotificationDetails(
        _kIncomingCallChannel.id,
        _kIncomingCallChannel.name,
        channelDescription: _kIncomingCallChannel.description,
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        sound: _kIncomingCallChannel.sound,
        playSound: true,
        ongoing: true,
        autoCancel: true,
      ),
    ),
  );
}

/// Top-level, not a method -- FCM requires the background handler to be a
/// top-level or static function annotated with vm:entry-point so it can run
/// in its own isolate while the app is killed. incoming_call gets a custom
/// full-screen-intent notification (see above); every other type is left to
/// the OS's automatic display of the push's own `notification` payload.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] == 'incoming_call') {
    await _savePendingIncomingCall(message.data);
    await _showIncomingCallNotification(message);
  }
}

/// Mirrors the backend's four send_fcm_to_user event types: incoming_call,
/// task_created, reminder_email_sent, friend_mood_update (see
/// FLUTTER_UPDATE_mood_emoji_and_fcm.md in the backend repo). Fails open
/// everywhere -- a missing/misconfigured Firebase project must never crash
/// the app or block any other feature, exactly like the backend silently
/// no-ops without FIREBASE_CREDENTIALS_PATH set.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _initialized = false;
  bool _listenersAttached = false;
  String? _currentToken;

  /// Set by whoever owns navigation/call state (home_shell.dart) before
  /// calling registerDevice(). Called for a tap on a background/killed-state
  /// notification, or -- for incoming_call specifically -- also while the
  /// app is already in the foreground, since a ringing call is worth acting
  /// on immediately rather than waiting for a tap.
  void Function(Map<String, dynamic> data)? onMessageTapped;
  void Function(Map<String, dynamic> data)? onIncomingCallForeground;

  bool get _isConfigured => DefaultFirebaseOptions.currentPlatform.apiKey != kFirebasePlaceholderMarker;

  /// Call once, early in main() before runApp(). Safe to call even with no
  /// Firebase project set up yet -- see _isConfigured above.
  Future<void> init() async {
    if (!_isConfigured) {
      debugPrint('[push] firebase_options.dart is still a placeholder -- push notifications disabled until '
          'you run `flutterfire configure`. Nothing else is affected.');
      return;
    }
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      // Created once, persists forever at the OS level -- doing this on
      // every normal launch guarantees it exists before any background
      // isolate (app killed) ever needs to use it.
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_kIncomingCallChannel);
      _initialized = true;
    } catch (e) {
      debugPrint('[push] Firebase.initializeApp failed, push notifications disabled: $e');
    }
  }

  /// Call after login (and again once bootstrap confirms an existing
  /// session) -- requests permission, gets this device's FCM token, and
  /// registers it with the backend. Safe to call more than once: the
  /// backend registration is an upsert, and listener attachment is guarded
  /// so it only happens once per app run.
  Future<void> registerDevice() async {
    if (!_initialized) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      debugPrint('[push] notification permission status: ${settings.authorizationStatus}');
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[push] notification permission denied by user');
        return;
      }

      _attachListenersOnce();

      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('[push] FCM token: $token');
      if (token != null) await _sendTokenToBackend(token);

      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null && initial.data.isNotEmpty) onMessageTapped?.call(initial.data);
    } catch (e) {
      debugPrint('[push] registerDevice failed: $e');
    }
  }

  void _attachListenersOnce() {
    if (_listenersAttached) return;
    _listenersAttached = true;

    FirebaseMessaging.instance.onTokenRefresh.listen(_sendTokenToBackend);

    // Foreground: only incoming_call gets special handling (populate the
    // same overlay the WS path drives) -- the other three types are
    // already covered by the live /ws/notify connection while the app is
    // in foreground, so acting on them here too would double-count badges.
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[push] foreground message received: type=${msg.data['type']} data=${msg.data} '
          'notif=${msg.notification?.title}/${msg.notification?.body}');
      if (msg.data['type'] == 'incoming_call') onIncomingCallForeground?.call(msg.data);
    });

    // Tapped from background or a killed-state cold start -- the WS
    // connection wasn't there to handle it, so this is the only signal.
    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      if (msg.data.isNotEmpty) onMessageTapped?.call(msg.data);
    });
  }

  Future<void> _sendTokenToBackend(String token) async {
    _currentToken = token;
    try {
      await ApiClient.instance.dio.post('/devices/register', data: {
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (e) {
      debugPrint('[push] device registration failed: $e');
    }
  }

  /// Call on logout so this device stops getting pushed to for the account
  /// it just left.
  Future<void> unregisterDevice() async {
    final token = _currentToken;
    if (token == null) return;
    _currentToken = null;
    try {
      await ApiClient.instance.dio.post('/devices/unregister', data: {'token': token});
    } catch (_) {
      // Best-effort -- the token row just goes stale server-side otherwise.
    }
  }
}
