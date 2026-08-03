package com.nodexdata.speechtotext

import android.app.ActivityManager
import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver

private const val TAG = "TL_CallReceiver"

/**
 * Replaces the firebase_messaging plugin's own FlutterFirebaseMessagingReceiver
 * in AndroidManifest.xml (tools:node="remove" + this registered instead) --
 * that plugin class is the actual FCM entry point (not
 * FlutterFirebaseMessagingService, whose onMessageReceived is an empty
 * stub; verified by reading the installed plugin's source). Intercepts
 * incoming_call/call_ended to drive the native ConnectionService UI
 * directly, but ONLY while the app isn't in the foreground -- while it is,
 * the existing live /ws/notify socket already drives the in-app
 * CallOverlay instantly (this is what already worked before today's
 * change), and additionally popping the native Telecom ringing screen over
 * an already-open app would be a jarring double-UI. Every other push type,
 * and incoming_call/call_ended while foregrounded, fall through to
 * super.onReceive() unchanged, preserving the existing Dart-side dispatch
 * exactly as before.
 */
class MyFirebaseMessagingReceiver : FlutterFirebaseMessagingReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "onReceive: action=${intent.action} extrasKeys=${intent.extras?.keySet()}")
        try {
            val extras = intent.extras
            if (extras == null) {
                Log.w(TAG, "onReceive: no extras on intent, delegating to super")
                super.onReceive(context, intent)
                return
            }
            val remoteMessage = RemoteMessage(extras)
            val type = remoteMessage.data["type"]
            val foreground = isApplicationForeground(context)
            Log.d(TAG, "onReceive: type=$type data=${remoteMessage.data} foreground=$foreground")

            if (!foreground) {
                when (type) {
                    "incoming_call" -> {
                        Log.d(TAG, "onReceive: intercepting incoming_call natively")
                        handleIncomingCall(context, remoteMessage)
                        return // native UI owns this now -- don't also hand it to Dart
                    }
                    "call_ended" -> {
                        val callId = remoteMessage.data["call_id"]
                        Log.d(TAG, "onReceive: call_ended for callId=$callId, " +
                            "activeConnection=${CallConnectionService.activeConnections.containsKey(callId)}")
                        if (callId != null) {
                            CallConnectionService.activeConnections[callId]?.endFromRemote()
                        }
                        // Still fall through to super.onReceive below -- if this
                        // device is the caller (not the callee who just missed
                        // the call) and somehow still has a live background
                        // isolate, existing Dart-side handling stays intact.
                    }
                }
            }
            Log.d(TAG, "onReceive: delegating to super.onReceive")
            super.onReceive(context, intent)
        } catch (e: Exception) {
            // A crash here silently drops the broadcast with no visible
            // error -- log loudly rather than let that happen invisibly,
            // and still try to preserve existing behavior via super.
            Log.e(TAG, "onReceive: unhandled exception, falling back to super.onReceive", e)
            try {
                super.onReceive(context, intent)
            } catch (e2: Exception) {
                Log.e(TAG, "onReceive: super.onReceive also failed", e2)
            }
        }
    }

    /** Same algorithm as the (package-private, so not directly callable)
     * FlutterFirebaseMessagingUtils.isApplicationForeground in this same
     * plugin -- duplicated here since it's a small, self-contained check
     * over public Android SDK APIs. */
    private fun isApplicationForeground(context: Context): Boolean {
        val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        if (keyguardManager?.isKeyguardLocked == true) {
            Log.d(TAG, "isApplicationForeground: keyguard locked -> false")
            return false
        }

        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        if (activityManager == null) {
            Log.w(TAG, "isApplicationForeground: no ActivityManager -> false")
            return false
        }
        val packageName = context.packageName
        val processes = activityManager.runningAppProcesses
        Log.d(TAG, "isApplicationForeground: ${processes?.size ?: 0} running processes, " +
            "mine=${processes?.firstOrNull { it.processName == packageName }?.importance}")
        return processes?.any {
            it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND &&
                it.processName == packageName
        } ?: false
    }

    private fun handleIncomingCall(context: Context, remoteMessage: RemoteMessage) {
        val callId = remoteMessage.data["call_id"]
        if (callId == null) {
            Log.w(TAG, "handleIncomingCall: no call_id in payload, dropping")
            return
        }
        try {
            val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            val handle = PhoneAccountHandle(
                ComponentName(context, CallConnectionService::class.java),
                "throughline_calls"
            )
            val extras = Bundle().apply {
                putString("call_id", callId)
                putString("caller_name", remoteMessage.data["caller_name"])
                putString("caller_id", remoteMessage.data["caller_id"])
                putString("room_name", remoteMessage.data["room_name"])
            }
            Log.d(TAG, "handleIncomingCall: calling addNewIncomingCall for callId=$callId")
            telecomManager.addNewIncomingCall(handle, extras)
            Log.d(TAG, "handleIncomingCall: addNewIncomingCall returned successfully")

            // The Flutter engine may still be alive (just backgrounded, not
            // killed) with its own WS socket independently about to receive
            // this exact same incoming_call in real time -- tell Dart this
            // call is now under native control the instant ringing starts,
            // not just once answered, so it never shows its own accept/
            // decline screen for it at all (rather than showing one briefly
            // and racing to clear it on answer). No-ops harmlessly if the
            // engine isn't running or Dart hasn't attached its handler yet;
            // capturePendingCallAnswer()'s push on answer is the fallback.
            val channel = CallConnectionService.methodChannel
            if (channel != null) {
                Log.d(TAG, "handleIncomingCall: notifying Dart of native ring for callId=$callId")
                channel.invokeMethod("nativeRingStarted", mapOf("call_id" to callId))
            }
        } catch (e: Exception) {
            // Broadened from SecurityException: any failure here (PhoneAccount
            // not yet registered/enabled, IllegalStateException, etc.) must be
            // visible in logs -- minSdk 26 means the old
            // flutter_local_notifications fullScreenIntent fallback no longer
            // exists, so a failure here means the call rings nowhere.
            Log.e(TAG, "handleIncomingCall: addNewIncomingCall failed for callId=$callId", e)
        }
    }
}
