package ru.qesto.qesto

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.Locale

class BankNotificationListener : NotificationListenerService() {
    // Замените или дополните ID нужных банковских приложений.
    private val allowedPackages = setOf(
        "ru.sberbankmobile",
        "com.idamob.tinkoff.android",
    )
    private val sensitiveMarkers = listOf(
        "код подтверждения",
        "код для",
        "одноразовый код",
        "никому не сообщ",
        "otp",
        "парол",
    )

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in allowedPackages) return

        val extras = sbn.notification.extras

        val title = extras
            .getCharSequence(Notification.EXTRA_TITLE)
            ?.toString()
            .orEmpty()

        val text = (
            extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)
            )?.toString().orEmpty()

        if (title.isBlank() && text.isBlank()) return
        val normalizedContent = "$title\n$text".lowercase(Locale.ROOT)
        if (sensitiveMarkers.any(normalizedContent::contains)) return

        NotificationInbox.save(
            context = applicationContext,
            packageName = sbn.packageName,
            notificationKey = sbn.key,
            postedAt = sbn.postTime,
            title = title,
            text = text,
        )
        sendBroadcast(
            Intent(NotificationInbox.ACTION_CAPTURED)
                .setPackage(applicationContext.packageName)
                .putExtra(
                    NotificationInbox.EXTRA_NOTIFICATION_KEY,
                    sbn.key,
                ),
        )
    }
}
