package com.nodexdata.speechtotext

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.telecom.Connection
import android.telecom.DisconnectCause
import android.util.Log

private const val TAG = "TL_CallConnection"

/**
 * One ringing/active call, driven entirely by the OS's native Telecom UI
 * until the user answers. onAnswer()/onReject() are called by the OS in
 * response to the user interacting with that native screen -- there is no
 * Flutter engine involved at that point, which is exactly what makes the
 * native screen appear instantly regardless of whether the app is
 * foregrounded, backgrounded, or killed.
 */
class CallConnection(
    private val context: Context,
    val callId: String,
    private val callExtras: Bundle?
) : Connection() {

    override fun onAnswer() {
        Log.d(TAG, "onAnswer: callId=$callId")
        setActive()
        CallConnectionService.activeConnections.remove(callId)
        CallNotificationHelper.cancel(context, callId)
        IncomingCallActivity.dismissIfShowing(callId)
        val intent = Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_CALL_ANSWERED
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            putExtra("call_id", callId)
            putExtra("caller_id", callExtras?.getString("caller_id"))
            putExtra("caller_name", callExtras?.getString("caller_name"))
            putExtra("room_name", callExtras?.getString("room_name"))
        }
        context.startActivity(intent)
        Log.d(TAG, "onAnswer: startActivity fired for callId=$callId")
    }

    override fun onReject() {
        Log.d(TAG, "onReject: callId=$callId")
        setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
        destroy()
        CallConnectionService.activeConnections.remove(callId)
        CallNotificationHelper.cancel(context, callId)
        IncomingCallActivity.dismissIfShowing(callId)
        NativeAuthStore.declineCall(context, callId)
    }

    override fun onDisconnect() {
        Log.d(TAG, "onDisconnect: callId=$callId")
        setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
        destroy()
        CallConnectionService.activeConnections.remove(callId)
        CallNotificationHelper.cancel(context, callId)
        IncomingCallActivity.dismissIfShowing(callId)
    }

    /** Called when a call_ended push arrives for this call_id (the caller
     * hung up before answering, or the backend's ring-timeout worker ended
     * it) -- dismisses this native ringing screen. See
     * MyFirebaseMessagingReceiver. */
    fun endFromRemote() {
        Log.d(TAG, "endFromRemote: callId=$callId")
        setDisconnected(DisconnectCause(DisconnectCause.CANCELED))
        destroy()
        CallConnectionService.activeConnections.remove(callId)
        CallNotificationHelper.cancel(context, callId)
        IncomingCallActivity.dismissIfShowing(callId)
    }
}
