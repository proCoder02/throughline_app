import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';
import 'api_client.dart';

/// Bridges to the native Android ConnectionService integration (see
/// android/app/.../MainActivity.kt, CallConnectionService.kt,
/// MyFirebaseMessagingReceiver.kt): incoming_call/call_ended pushes are now
/// intercepted natively while the app is backgrounded/killed, showing the
/// OS's own instant ringing UI instead of waiting for the whole Flutter
/// engine to cold-boot. This channel is how Dart (a) keeps a native-owned
/// copy of the auth token in sync, so a native Decline can call the backend
/// without needing Flutter running at all, and (b) picks up "the user just
/// answered via the native screen" once its own engine is ready.
const _kCallChannel = MethodChannel('com.nodexdata.speechtotext/call');

/// Top-level, not a method -- FCM requires the background handler to be a
/// top-level or static function annotated with vm:entry-point so it can run
/// in its own isolate while the app is killed. incoming_call/call_ended no
/// longer reach here at all while backgrounded/killed (the native receiver
/// intercepts them first, see MyFirebaseMessagingReceiver.kt); every other
/// push type is left entirely to the OS's automatic display of its own
/// `notification` payload. Kept registered (rather than removed) since
/// FirebaseMessaging.onBackgroundMessage still expects a handler to exist.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

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
  Future<void>? _initFuture;

  /// Set by whoever owns navigation/call state (home_shell.dart) before
  /// calling registerDevice(). Called for a tap on a background/killed-state
  /// notification, or -- for incoming_call specifically -- also while the
  /// app is already in the foreground, since a ringing call is worth acting
  /// on immediately rather than waiting for a tap.
  void Function(Map<String, dynamic> data)? onMessageTapped;
  void Function(Map<String, dynamic> data)? onIncomingCallForeground;

  /// Fed by MainActivity.kt's capturePendingCallAnswer() when the user
  /// answers a call on the native ringing screen WHILE the Flutter engine is
  /// already running (app was backgrounded, not killed) -- delivered via
  /// onNewIntent rather than a fresh configureFlutterEngine, so it reaches
  /// Dart as a push through this handler rather than the one-time
  /// consumePendingCallAnswer() pull done at HomeShell startup, which never
  /// runs again for an engine that was already alive.
  void Function(Map<String, dynamic> data)? onCallAnsweredNatively;

  /// Fed by MyFirebaseMessagingReceiver.kt the instant it intercepts an
  /// incoming_call push and starts the native ring (not just once answered)
  /// -- lets NotifyProvider suppress its own WS/FCM-driven ringing screen for
  /// that call_id from the very start, rather than briefly showing one and
  /// racing to clear it when the user answers natively. The engine can be
  /// alive-but-backgrounded at that point (not killed), with its own WS
  /// socket about to independently receive the very same incoming_call.
  void Function(int callId)? onNativeRingStarted;

  bool _callChannelHandlerAttached = false;

  /// Call once, as early as possible (before any call could plausibly come
  /// in) -- sets up the Dart side of the bidirectional call channel so a
  /// native answer on an already-running engine has somewhere to land.
  void listenForNativeCallAnswers() {
    if (!Platform.isAndroid || _callChannelHandlerAttached) return;
    _callChannelHandlerAttached = true;
    _kCallChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'callAnswered':
          onCallAnsweredNatively?.call(Map<String, dynamic>.from(call.arguments as Map));
          break;
        case 'nativeRingStarted':
          final data = Map<String, dynamic>.from(call.arguments as Map);
          final callId = int.tryParse(data['call_id']?.toString() ?? '');
          if (callId != null) onNativeRingStarted?.call(callId);
          break;
      }
    });
  }

  bool get _isConfigured => DefaultFirebaseOptions.currentPlatform.apiKey != kFirebasePlaceholderMarker;

  /// Call once, right after runApp() -- deliberately NOT awaited there and
  /// NOT called before runApp(). Firebase.initializeApp() touches native/
  /// network-adjacent APIs and can take real time on a cold start; blocking
  /// the first frame on it is exactly the kind of wait the app's startup
  /// rule (cached-data-first, network after) forbids. registerDevice()
  /// below awaits _initFuture itself, so it's still safe to call as soon as
  /// a user authenticates even if this hasn't resolved yet.
  Future<void> init() {
    return _initFuture = _doInit();
  }

  Future<void> _doInit() async {
    if (!_isConfigured) {
      debugPrint('[push] firebase_options.dart is still a placeholder -- push notifications disabled until '
          'you run `flutterfire configure`. Nothing else is affected.');
      return;
    }
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
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
    if (_initFuture != null) await _initFuture;
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
    // same overlay the live WS path drives) -- the other three types are
    // already covered by the live /ws/notify connection while the app is in
    // foreground, so acting on them here too would double-count badges.
    // call_ended needs nothing here anymore: the native receiver only ever
    // intercepts it while backgrounded (see MyFirebaseMessagingReceiver.kt),
    // so while foregrounded this message is left to flow through the
    // existing NotifyProvider/live-socket handling exactly as it always did.
    FirebaseMessaging.onMessage.listen((msg) {
      debugPrint('[push] foreground message received: type=${msg.data['type']} data=${msg.data} '
          'notif=${msg.notification?.title}/${msg.notification?.body}');
      if (msg.data['type'] == 'incoming_call') {
        onIncomingCallForeground?.call(msg.data);
      }
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

/// Keeps the native-side token store (NativeAuthStore.kt) in sync -- called
/// from api_client.dart whenever the token is saved/cleared. Android-only;
/// no-ops harmlessly on other platforms (the channel simply won't be
/// implemented there, and Telecom/ConnectionService is Android-specific
/// anyway).
Future<void> cacheTokenForNative(String token, String baseUrl) async {
  if (!Platform.isAndroid) return;
  try {
    await _kCallChannel.invokeMethod('cacheTokenForNative', {'token': token, 'baseUrl': baseUrl});
  } catch (_) {
    // Best-effort -- worst case a native Decline falls back to the
    // backend's own ring-timeout worker instead of being instant.
  }
}

Future<void> clearTokenForNative() async {
  if (!Platform.isAndroid) return;
  try {
    await _kCallChannel.invokeMethod('clearTokenForNative');
  } catch (_) {
    // Best-effort.
  }
}

/// Checks whether this cold start was launched by the user answering a call
/// on the native ringing screen (see CallConnection.kt's onAnswer(), which
/// launches MainActivity with call data as Intent extras). Replaces the old
/// consumePendingIncomingCall() (SecureStorage-based) -- read-once-and-clear,
/// same as before, just sourced from the launching Intent instead.
Future<Map<String, dynamic>?> consumePendingCallAnswer() async {
  if (!Platform.isAndroid) return null;
  try {
    final result = await _kCallChannel.invokeMethod('getPendingCallAnswer');
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  } catch (_) {
    return null;
  }
}

/// Tells the native side a call_id is fully resolved (declined/answered/
/// ended) even when that resolution happened entirely on the Dart side --
/// e.g. the app was foregrounded when the call arrived, so
/// MyFirebaseMessagingReceiver.kt never intercepted it and NativeAuthStore's
/// "finished calls" guard (see CallConnection.kt) never got marked from
/// there. Without this, a call resolved in-app while foregrounded, followed
/// by the app losing foreground before FCM's at-least-once delivery
/// redelivers the same incoming_call push, rings again natively for a call
/// that's long over. Call from every place a call_id gets resolved in Dart:
/// CallProvider.declineCall/joinCall and NotifyProvider's call_ended
/// handler.
Future<void> markCallFinishedNative(int callId) async {
  if (!Platform.isAndroid) return;
  try {
    await _kCallChannel.invokeMethod('markCallFinished', {'call_id': callId.toString()});
  } catch (_) {
    // Best-effort -- worst case a stale FCM redelivery rings once more.
  }
}

/// Dismisses the native Telecom ringing screen for a call_id if one is
/// currently showing. NotifyProvider's WS 'call_ended' handling only ever
/// cleared its own Dart-side incomingCall state, which is a no-op if what's
/// actually on screen is the native ConnectionService ringing UI (the call
/// arrived while backgrounded, so MyFirebaseMessagingReceiver.kt intercepted
/// it and rang natively) -- that screen has no idea the call just ended
/// unless told directly. Safe to call even when nothing is ringing
/// natively (no-ops if there's no active connection for this call_id).
Future<void> dismissNativeRinging(int callId) async {
  if (!Platform.isAndroid) return;
  try {
    await _kCallChannel.invokeMethod('dismissNativeRinging', {'call_id': callId.toString()});
  } catch (_) {
    // Best-effort.
  }
}

/// Posts a real system notification, even while the app is foregrounded --
/// FCM's own `notification` block never auto-displays in that state (that's
/// standard OS behavior, not something toggled server-side), so a
/// foreground-only in-app SnackBar was the only heads-up a new task ever
/// got. This is the actual visible banner instead.
Future<void> showLocalNotification(String title, String body) async {
  if (!Platform.isAndroid) return;
  try {
    await _kCallChannel.invokeMethod('showLocalNotification', {'title': title, 'body': body});
  } catch (_) {
    // Best-effort -- worst case this falls back to no visible heads-up at all.
  }
}
