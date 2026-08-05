package com.nodexdata.speechtotext

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

private const val TAG = "TL_CallNotification"
private const val CHANNEL_ID = "incoming_calls"

/**
 * Posts (and cancels) the full-screen-intent notification that drives
 * IncomingCallActivity. Needed because a self-managed
 * android.telecom.Connection reaching RINGING does not guarantee any
 * visible UI -- some OEM dialers (confirmed on this device's ColorOS) never
 * render third-party self-managed calls, so this app must show its own
 * ringing screen rather than depend on the system dialer.
 */
object CallNotificationHelper {

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID, "Incoming calls", NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Incoming voice call alerts"
            setBypassDnd(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    fun show(context: Context, callId: String, callerName: String, callerId: String?, roomName: String?) {
        ensureChannel(context)
        val fullScreenIntent = Intent(context, IncomingCallActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_NO_USER_ACTION or
                Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
            putExtra("call_id", callId)
            putExtra("caller_name", callerName)
            putExtra("caller_id", callerId)
            putExtra("room_name", roomName)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            context, callId.hashCode(), fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setContentTitle(callerName)
            .setContentText("Incoming call...")
            .setSmallIcon(context.applicationInfo.icon)
            .setPriority(Notification.PRIORITY_MAX)
            .setCategory(Notification.CATEGORY_CALL)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setContentIntent(fullScreenPendingIntent)
            .build()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(callId.hashCode(), notification)
        Log.d(TAG, "show: posted full-screen-intent notification for callId=$callId")
        try {
            context.startActivity(fullScreenIntent)
            Log.d(TAG, "show: also directly started IncomingCallActivity for callId=$callId")
        } catch (e: Exception) {
            Log.w(TAG, "show: direct startActivity failed (relying on fullScreenIntent alone)", e)
        }
    }

    fun cancel(context: Context, callId: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(callId.hashCode())
        Log.d(TAG, "cancel: canceled notification for callId=$callId")
    }
}
