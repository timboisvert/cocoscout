package com.cocoscout.app.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import com.cocoscout.app.MainActivity
import com.cocoscout.app.R

/**
 * Shows a notification the server sent (PushDeliveryJob.android_data): Coco's
 * outline in the status bar (Android draws those in one color; the
 * notification itself shows the app's icon, Coco in color), the title with
 * the production beside it when there is one, the message, and a tap that
 * opens its page. One notification per thread; a
 * newer message in the same thread replaces it.
 */
object Notifications {
    const val MESSAGES_CHANNEL = "messages"

    /** Android lists each kind of notification in the app's settings; ours is one. */
    fun createChannels(context: Context) {
        val channel = NotificationChannel(MESSAGES_CHANNEL, context.getString(R.string.notification_channel_messages),
            NotificationManager.IMPORTANCE_HIGH)
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun show(context: Context, data: Map<String, String>) {
        val title = data["title"] ?: return
        val body = data["body"].orEmpty()
        val path = data["path"]?.takeIf { it.startsWith("/") } ?: "/my/messages"
        val key = data["thread_id"] ?: path

        // The same link a browser return uses (MainActivity.openLinkFrom).
        val open = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .setData("cocoscout://open?path=${Uri.encode(path)}".toUri())
        val tap = PendingIntent.getActivity(context, key.hashCode(), open,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)

        val notification = NotificationCompat.Builder(context, MESSAGES_CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ContextCompat.getColor(context, R.color.pink))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSubText(data["subtitle"])
            .setNumber(data["badge"]?.toIntOrNull() ?: 0)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(tap)
            .setAutoCancel(true)
            .build()

        val manager = NotificationManagerCompat.from(context)
        if (manager.areNotificationsEnabled()) {
            try {
                manager.notify("thread", key.hashCode(), notification)
            } catch (_: SecurityException) {
                // Permission withdrawn between the check and the post.
            }
        }
    }
}
