package ru.qesto.qesto

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import java.util.Locale

class BankNotificationListener : NotificationListenerService() {
    private val bankPackages = setOf(
        "ru.sberbankmobile",
        "com.idamob.tinkoff.android",
        "ru.alfabank.mobile.android",
        "ru.vtb24.mobilebanking.android",
    )
    private val smsPackages = setOf(
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging",
        "com.android.messaging",
        "com.android.mms",
        "com.miui.mms",
        "com.huawei.message",
    )
    private val sensitiveMarkers = listOf(
        "код подтверждения",
        "код для",
        "одноразовый код",
        "никому не сообщ",
        "otp",
        "парол",
    )
    private val financialMarkers = listOf(
        "покупк",
        "оплат",
        "списан",
        "зачислен",
        "поступлен",
        "пополнен",
        "перевод",
        "сбп",
        "возврат",
        "снятие",
    )
    private val currencyAmount = Regex(
        "\\d[\\d\\s\\u00A0\\u202F]*(?:[,.]\\d{1,2})?\\s*(?:₽|р(?:уб)?\\.?|rub|usd|eur|[\\x24€])",
        setOf(RegexOption.IGNORE_CASE),
    )

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val isBank = sbn.packageName in bankPackages
        val isSms = sbn.packageName in smsPackages
        if (!isBank && !isSms) return

        val extras = sbn.notification.extras

        val title = extras
            .getCharSequence(Notification.EXTRA_TITLE)
            ?.toString()
            .orEmpty()

        val text = extras
            .getCharSequence(Notification.EXTRA_TEXT)
            ?.toString()
            .orEmpty()
        val bigText = extras
            .getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?.toString()
            .orEmpty()
        val subText = extras
            .getCharSequence(Notification.EXTRA_SUB_TEXT)
            ?.toString()
            .orEmpty()
        val textLines = extras
            .getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.map(CharSequence::toString)
            .orEmpty()

        val content = listOf(title, text, bigText, subText)
            .plus(textLines)
            .filter(String::isNotBlank)
            .distinct()
            .joinToString("\n")
        if (content.isBlank()) return
        val normalizedContent = content.lowercase(Locale.ROOT)
        if (sensitiveMarkers.any(normalizedContent::contains)) return
        // SMS are deliberately observed through NotificationListener only.
        // Require both a financial verb and an amount before any encrypted
        // inbox write, so ordinary conversations never enter Qesto.
        if (isSms && (
                financialMarkers.none(normalizedContent::contains) ||
                    !currencyAmount.containsMatchIn(normalizedContent)
            )
        ) return

        try {
            NotificationInbox.save(
                context = applicationContext,
                packageName = sbn.packageName,
                notificationKey = sbn.key,
                postedAt = sbn.postTime,
                title = title,
                text = text,
                bigText = bigText,
                subText = subText,
                textLines = textLines,
            )
        } catch (_: Exception) {
            // Keep the listener alive and existing encrypted data untouched.
            // Notify the app to surface a storage error, without financial text.
            sendBroadcast(
                Intent(NotificationInbox.ACTION_CAPTURED)
                    .setPackage(applicationContext.packageName),
            )
            return
        }
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
