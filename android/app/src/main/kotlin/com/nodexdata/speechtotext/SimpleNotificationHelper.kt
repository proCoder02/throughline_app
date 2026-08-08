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
 *
 * task_created notifications additionally carry conversationId/taskDescription
 * so tapping them opens that exact conversation (rather than just relaunching
 * the app generically), and get a distinct "Ask" action that opens the same
 * conversation and has Dart auto-submit a question about the task -- see
 * MainActivity.ACTION_TASK_ASK.
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

    fun show(
        context: Context,
        title: String,
        body: String,
        conversationId: String? = null,
        taskDescription: String? = null
    ) {
        ensureChannel(context)
        val id = notificationIdCounter++

        fun buildIntent(action: String?): Intent {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            return Intent(launchIntent).apply {
                if (action != null) this.action = action
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                if (conversationId != null) putExtra("conversation_id", conversationId)
                if (taskDescription != null) putExtra("task_description", taskDescription)
            }
        }

        val contentPendingIntent = PendingIntent.getActivity(
            context, id, buildIntent(if (conversationId != null) MainActivity.ACTION_TASK_OPEN else null),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = Notification.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(context.applicationInfo.icon)
            .setAutoCancel(true)
            .setContentIntent(contentPendingIntent)

        // Only a task_created notification carries a conversationId -- other
        // callers of this same helper (general app updates) get the plain
        // notification with no action, exactly as before.
        if (conversationId != null) {
            val askPendingIntent = PendingIntent.getActivity(
                context, id + 1_000_000, buildIntent(MainActivity.ACTION_TASK_ASK),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder.addAction(
                Notification.Action.Builder(context.applicationInfo.icon, "Ask", askPendingIntent).build()
            )
        }

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(id, builder.build())
    }
}
