package com.nodexdata.speechtotext

import android.content.ComponentName
import android.content.Intent
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val TAG = "TL_MainActivity"

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.nodexdata.speechtotext/call"
        const val ACTION_CALL_ANSWERED = "com.nodexdata.speechtotext.CALL_ANSWERED"
        // Both come from SimpleNotificationHelper's task_created notification:
        // OPEN is the notification's default tap (just view the conversation),
        // ASK is its distinct "Ask" action (view the conversation AND have
        // Dart auto-submit a question about the task).
        const val ACTION_TASK_OPEN = "com.nodexdata.speechtotext.TASK_OPEN"
        const val ACTION_TASK_ASK = "com.nodexdata.speechtotext.TASK_ASK"
        // From SimpleNotificationHelper's digest_ready notification -- no id
        // payload needed (unlike TASK_OPEN's conversation_id), DigestScreen
        // fetches its own content on open, see digest_service.dart.
        const val ACTION_DIGEST_OPEN = "com.nodexdata.speechtotext.DIGEST_OPEN"
    }

    // Set once by capturePendingCallAnswer(), read-and-cleared by Dart's
    // "getPendingCallAnswer" call once its own engine/handlers are ready --
    // a pull, not a push, so there's no race with Dart's method handler not
    // being registered yet at the exact moment the engine attaches. Only
    // used for the true cold-start case (channel below is still null);
    // see capturePendingCallAnswer().
    private var pendingCallAnswer: Map<String, String?>? = null

    // Same pull-not-push pattern as pendingCallAnswer above, for
    // ACTION_TASK_OPEN/ACTION_TASK_ASK -- "ask" distinguishes the
    // notification's default tap from its "Ask" action.
    private var pendingTaskAction: Map<String, String?>? = null

    // Same pull-not-push pattern again, for ACTION_DIGEST_OPEN -- just a
    // flag, no payload (see ACTION_DIGEST_OPEN's own comment).
    private var pendingDigestOpen: Boolean = false

    // Non-null once configureFlutterEngine has run for this engine instance
    // (it lives for as long as the engine does, across any number of later
    // onNewIntent calls). Answering a call natively while the app/engine is
    // ALREADY running (not a cold start -- e.g. the app was simply
    // backgrounded, not killed) delivers the answer via onNewIntent, not a
    // fresh configureFlutterEngine -- HomeShell.initState() (and its one-time
    // getPendingCallAnswer pull) never runs again for that, so without this
    // the native answer would go nowhere and Dart's independent WS
    // 'incoming_call' ringing screen for the same call would be the only
    // thing left on screen, already-answered call and all.
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "configureFlutterEngine: engine attaching, intent.action=${intent?.action}")
        registerPhoneAccount()
        capturePendingCallAnswer(intent)
        capturePendingTaskAction(intent)
        capturePendingDigestOpen(intent)

        val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result ->
            Log.d(TAG, "MethodChannel: received ${call.method}")
            when (call.method) {
                "cacheTokenForNative" -> {
                    val token = call.argument<String>("token")
                    val baseUrl = call.argument<String>("baseUrl")
                    if (token != null && baseUrl != null) {
                        NativeAuthStore.saveToken(applicationContext, token, baseUrl)
                        Log.d(TAG, "cacheTokenForNative: token cached, baseUrl=$baseUrl")
                    } else {
                        Log.w(TAG, "cacheTokenForNative: missing token or baseUrl")
                    }
                    result.success(null)
                }
                "clearTokenForNative" -> {
                    NativeAuthStore.clearToken(applicationContext)
                    Log.d(TAG, "clearTokenForNative: token cleared")
                    result.success(null)
                }
                "getPendingCallAnswer" -> {
                    Log.d(TAG, "getPendingCallAnswer: returning $pendingCallAnswer")
                    result.success(pendingCallAnswer)
                    pendingCallAnswer = null
                }
                "getPendingTaskAction" -> {
                    Log.d(TAG, "getPendingTaskAction: returning $pendingTaskAction")
                    result.success(pendingTaskAction)
                    pendingTaskAction = null
                }
                "getPendingDigestOpen" -> {
                    Log.d(TAG, "getPendingDigestOpen: returning $pendingDigestOpen")
                    result.success(pendingDigestOpen)
                    pendingDigestOpen = false
                }
                "markCallFinished" -> {
                    val callId = call.argument<String>("call_id")
                    Log.d(TAG, "markCallFinished: callId=$callId")
                    if (callId != null) NativeAuthStore.markCallFinished(applicationContext, callId)
                    result.success(null)
                }
                "showLocalNotification" -> {
                    val title = call.argument<String>("title") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val conversationId = call.argument<String>("conversationId")
                    val description = call.argument<String>("description")
                    val isDigest = call.argument<Boolean>("isDigest") ?: false
                    SimpleNotificationHelper.show(applicationContext, title, body, conversationId, description, isDigest)
                    result.success(null)
                }
                "dismissNativeRinging" -> {
                    // The WS/FCM call_ended event reaching Dart's NotifyProvider
                    // only ever cleared Dart-side incomingCall state -- if the
                    // native Telecom ringing screen (CallConnection/
                    // IncomingCallActivity) is what's actually showing (call
                    // arrived while backgrounded, then the app was foregrounded
                    // before the caller hung up), nothing told IT to dismiss,
                    // so it kept ringing/showing until the user manually
                    // declined. This is the bridge for that.
                    val callId = call.argument<String>("call_id")
                    Log.d(TAG, "dismissNativeRinging: callId=$callId, " +
                        "activeConnection=${CallConnectionService.activeConnections.containsKey(callId)}")
                    if (callId != null) {
                        CallConnectionService.activeConnections[callId]?.endFromRemote()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        channel = methodChannel
        CallConnectionService.methodChannel = methodChannel
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Log.d(TAG, "onNewIntent: action=${intent.action}")
        capturePendingCallAnswer(intent)
        capturePendingTaskAction(intent)
        capturePendingDigestOpen(intent)
    }

    private fun capturePendingCallAnswer(intent: Intent?) {
        if (intent?.action != ACTION_CALL_ANSWERED) return
        val data = mapOf(
            "call_id" to intent.getStringExtra("call_id"),
            "caller_id" to intent.getStringExtra("caller_id"),
            "caller_name" to intent.getStringExtra("caller_name"),
            "room_name" to intent.getStringExtra("room_name"),
        )
        val existingChannel = channel
        if (existingChannel != null) {
            // Engine already running (channel was set up by an earlier
            // configureFlutterEngine call, so Dart's own handler for this has
            // long since registered) -- push straight away rather than
            // waiting for a getPendingCallAnswer pull that will never come.
            Log.d(TAG, "capturePendingCallAnswer: pushing directly to Dart (engine already running): $data")
            existingChannel.invokeMethod("callAnswered", data)
        } else {
            pendingCallAnswer = data
            Log.d(TAG, "capturePendingCallAnswer: stored for cold-start pull: $data")
        }
    }

    /** Same push-if-running/pull-if-cold-start split as capturePendingCallAnswer,
     * for a tap on SimpleNotificationHelper's task_created notification (either
     * its default tap, ACTION_TASK_OPEN, or its "Ask" action, ACTION_TASK_ASK). */
    private fun capturePendingTaskAction(intent: Intent?) {
        val ask = when (intent?.action) {
            ACTION_TASK_OPEN -> false
            ACTION_TASK_ASK -> true
            else -> return
        }
        val data = mapOf(
            "conversation_id" to intent?.getStringExtra("conversation_id"),
            "task_description" to intent?.getStringExtra("task_description"),
            "ask" to ask.toString(),
        )
        val existingChannel = channel
        if (existingChannel != null) {
            Log.d(TAG, "capturePendingTaskAction: pushing directly to Dart (engine already running): $data")
            existingChannel.invokeMethod("taskActionRequested", data)
        } else {
            pendingTaskAction = data
            Log.d(TAG, "capturePendingTaskAction: stored for cold-start pull: $data")
        }
    }

    /** Same push-if-running/pull-if-cold-start split again, for a tap on
     * SimpleNotificationHelper's digest_ready notification. No payload to
     * carry (unlike task's conversation_id) -- DigestScreen fetches its own
     * content, this just needs to signal "open it". */
    private fun capturePendingDigestOpen(intent: Intent?) {
        if (intent?.action != ACTION_DIGEST_OPEN) return
        val existingChannel = channel
        if (existingChannel != null) {
            Log.d(TAG, "capturePendingDigestOpen: pushing directly to Dart (engine already running)")
            existingChannel.invokeMethod("digestOpenRequested", null)
        } else {
            pendingDigestOpen = true
            Log.d(TAG, "capturePendingDigestOpen: stored for cold-start pull")
        }
    }

    private fun registerPhoneAccount() {
        try {
            val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
            val handle = PhoneAccountHandle(
                ComponentName(this, CallConnectionService::class.java),
                "throughline_calls"
            )
            val account = PhoneAccount.builder(handle, "Throughline")
                .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
                .build()
            telecomManager.registerPhoneAccount(account)
            Log.d(TAG, "registerPhoneAccount: registered successfully")
        } catch (e: Exception) {
            Log.e(TAG, "registerPhoneAccount: failed", e)
        }
    }
}
