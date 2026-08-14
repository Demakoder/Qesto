package ru.qesto.qesto

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object NotificationInbox {
    const val ACTION_CAPTURED = "ru.qesto.qesto.NOTIFICATION_CAPTURED"
    const val EXTRA_NOTIFICATION_KEY = "notificationKey"
    private const val PREFS_NAME = "qesto_notification_inbox"
    private const val ITEMS_KEY = "items"

    @Synchronized
    fun save(
        context: Context,
        packageName: String,
        notificationKey: String,
        postedAt: Long,
        title: String,
        text: String,
    ) {
        val prefs = context.getSharedPreferences(
            PREFS_NAME,
            Context.MODE_PRIVATE,
        )

        val oldItems = JSONArray(
            prefs.getString(ITEMS_KEY, "[]") ?: "[]",
        )

        // Уведомления могут обновляться. Удаляем старую версию с тем же key.
        val newItems = JSONArray()

        for (index in 0 until oldItems.length()) {
            val item = oldItems.getJSONObject(index)

            if (item.optString("notificationKey") != notificationKey) {
                newItems.put(item)
            }
        }

        newItems.put(
            JSONObject()
                .put("packageName", packageName)
                .put("notificationKey", notificationKey)
                .put("postedAt", postedAt)
                .put("title", title)
                .put("text", text),
        )

        prefs.edit()
            .putString(ITEMS_KEY, newItems.toString())
            .apply()
    }

    @Synchronized
    fun readAll(context: Context): List<Map<String, Any>> {
        val prefs = context.getSharedPreferences(
            PREFS_NAME,
            Context.MODE_PRIVATE,
        )

        val items = JSONArray(
            prefs.getString(ITEMS_KEY, "[]") ?: "[]",
        )

        return List(items.length()) { index ->
            val item = items.getJSONObject(index)

            mapOf(
                "packageName" to item.optString("packageName"),
                "notificationKey" to item.optString("notificationKey"),
                "postedAt" to item.optLong("postedAt"),
                "title" to item.optString("title"),
                "text" to item.optString("text"),
            )
        }
    }

    @Synchronized
    fun clear(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(ITEMS_KEY)
            .apply()
    }

    @Synchronized
    fun remove(context: Context, notificationKey: String) {
        val prefs = context.getSharedPreferences(
            PREFS_NAME,
            Context.MODE_PRIVATE,
        )
        val oldItems = JSONArray(
            prefs.getString(ITEMS_KEY, "[]") ?: "[]",
        )
        val newItems = JSONArray()

        for (index in 0 until oldItems.length()) {
            val item = oldItems.getJSONObject(index)
            if (item.optString("notificationKey") != notificationKey) {
                newItems.put(item)
            }
        }

        prefs.edit()
            .putString(ITEMS_KEY, newItems.toString())
            .apply()
    }
}
