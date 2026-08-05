package com.nodexdata.speechtotext

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

private const val CHANNEL_ID = "general_updates"
private var notificationIdCounter = 1000

/**
 * Posts a plain visible notification for events that happen while the app
 * is foregrounded -- e.g. a new task extracted from a conversation. FCM's
 * own `notification` block never auto-displays while the app is in the
 * foreground (standard Android/iOS behavior, not something this app
 * controls), and the in-app SnackBar (see ForegroundNotice in
 * notify_provider.dart) is easy to miss if you're not looking at the screen
 * right then. This is a real system notification instead, posted directly
 * by app code rather than relying on FCM's foreground-invisible auto-display.
 */
object SimpleNotificationHelper {

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID, "Updates", NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "New tasks and other app updates"
        }
        manager.createNotificationChannel(channel)
    }

    fun show(context: Context, title: String, body: String) {
        ensureChannel(context)
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        val id = notificationIdCounter++
        val pendingIntent = PendingIntent.getActivity(
            context, id, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(context.applicationInfo.icon)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(id, notification)
    }
}
