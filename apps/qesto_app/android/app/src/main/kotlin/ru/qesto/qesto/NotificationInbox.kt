package ru.qesto.qesto

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object NotificationInbox {
    const val ACTION_CAPTURED = "ru.qesto.qesto.NOTIFICATION_CAPTURED"
    const val EXTRA_NOTIFICATION_KEY = "notificationKey"
    private const val PREFS_NAME = "qesto_notification_inbox"
    private const val ITEMS_KEY = "items"
    private const val KEY_ALIAS = "qesto.notification-inbox.v1"
    private const val ENCRYPTED_PREFIX = "qesto:aes-gcm:v1:"
    private const val MAX_ITEMS = 100
    private const val RETENTION_MILLIS = 7L * 24L * 60L * 60L * 1000L
    private var cachedEncryptionKey: SecretKey? = null

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

        val oldItems = loadItems(prefs).items

        // Уведомления могут обновляться. Удаляем старую версию с тем же key.
        val oldestAllowed = System.currentTimeMillis() - RETENTION_MILLIS
        val retained = oldItems.filter { item ->
                item.optString("notificationKey") != notificationKey &&
                item.optLong("postedAt") >= oldestAllowed
            }.takeLast(MAX_ITEMS - 1)
        val updated = retained +
            JSONObject()
                .put("packageName", packageName)
                .put("notificationKey", notificationKey)
                .put("postedAt", postedAt)
                .put("title", title)
                .put("text", text)

        persist(prefs, updated)
    }

    @Synchronized
    fun readAll(context: Context): List<Map<String, Any>> {
        val prefs = context.getSharedPreferences(
            PREFS_NAME,
            Context.MODE_PRIVATE,
        )

        val loaded = loadItems(prefs)
        val oldestAllowed = System.currentTimeMillis() - RETENTION_MILLIS
        val retained = loaded.items
            .filter { item -> item.optLong("postedAt") >= oldestAllowed }
            .takeLast(MAX_ITEMS)
        if (loaded.needsRewrite || retained.size != loaded.items.size) {
            persist(prefs, retained)
        }

        return retained.map { item ->
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
        val loaded = loadItems(prefs)
        val retained = loaded.items.filter { item ->
            item.optString("notificationKey") != notificationKey
        }
        if (loaded.needsRewrite || retained.size != loaded.items.size) {
            persist(prefs, retained)
        }
    }

    private fun loadItems(prefs: SharedPreferences): LoadedItems {
        val stored = prefs.getString(ITEMS_KEY, null)
            ?: return LoadedItems(emptyList(), needsRewrite = false)
        return try {
            val encrypted = stored.startsWith(ENCRYPTED_PREFIX)
            val cleartext = if (encrypted) {
                decrypt(stored.removePrefix(ENCRYPTED_PREFIX))
            } else {
                stored
            }
            val array = JSONArray(cleartext)
            LoadedItems(
                List(array.length()) { index -> array.getJSONObject(index) },
                needsRewrite = !encrypted,
            )
        } catch (_: Exception) {
            // The inbox is transient. If its key was invalidated or the value was
            // modified, dropping it is safer than exposing partial notification data.
            prefs.edit().remove(ITEMS_KEY).apply()
            discardEncryptionKey()
            LoadedItems(emptyList(), needsRewrite = false)
        }
    }

    private fun persist(prefs: SharedPreferences, items: List<JSONObject>) {
        val array = JSONArray()
        items.forEach(array::put)
        val encrypted = ENCRYPTED_PREFIX + encrypt(array.toString())
        prefs.edit().putString(ITEMS_KEY, encrypted).apply()
    }

    private fun encrypt(cleartext: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, encryptionKey())
        val payload = Base64.encodeToString(
            cipher.doFinal(cleartext.toByteArray(Charsets.UTF_8)),
            Base64.NO_WRAP,
        )
        val iv = Base64.encodeToString(cipher.iv, Base64.NO_WRAP)
        return "$iv:$payload"
    }

    private fun decrypt(envelope: String): String {
        val separator = envelope.indexOf(':')
        require(separator > 0 && separator < envelope.lastIndex)
        val iv = Base64.decode(envelope.substring(0, separator), Base64.NO_WRAP)
        val payload = Base64.decode(envelope.substring(separator + 1), Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            encryptionKey(),
            GCMParameterSpec(128, iv),
        )
        return String(cipher.doFinal(payload), Charsets.UTF_8)
    }

    private fun encryptionKey(): SecretKey {
        cachedEncryptionKey?.let { return it }
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { key ->
            cachedEncryptionKey = key
            return key
        }

        val generator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            "AndroidKeyStore",
        )
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build(),
        )
        return generator.generateKey().also { cachedEncryptionKey = it }
    }

    private fun discardEncryptionKey() {
        cachedEncryptionKey = null
        runCatching {
            KeyStore.getInstance("AndroidKeyStore").apply {
                load(null)
                deleteEntry(KEY_ALIAS)
            }
        }
    }

    private data class LoadedItems(
        val items: List<JSONObject>,
        val needsRewrite: Boolean,
    )
}
