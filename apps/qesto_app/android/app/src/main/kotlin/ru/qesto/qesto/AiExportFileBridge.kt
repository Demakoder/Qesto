package ru.qesto.qesto

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** A user-selected JSON document only; no storage permissions or network calls. */
class AiExportFileBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private var pending: MethodChannel.Result? = null
    private var content: ByteArray? = null
    private val channel = MethodChannel(messenger, "ru.qesto.qesto/ai_export")

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "saveJson") {
                result.notImplemented()
            } else if (pending != null) {
                result.error("export_busy", "Сохранение уже выполняется", null)
            } else {
                val bytes = call.argument<ByteArray>("bytes")
                val name = call.argument<String>("fileName")
                if (bytes == null || name == null || !name.matches(Regex("qesto-ai-export-\\d{4}-\\d{2}-\\d{2}\\.json"))) {
                    result.error("export_invalid", "Некорректный файл экспорта", null)
                } else {
                    pending = result
                    content = bytes
                    try {
                        activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, name)
                        }, REQUEST_EXPORT)
                    } catch (_: Exception) {
                        clear()
                        result.error("export_picker_failed", "Не удалось открыть сохранение документа", null)
                    }
                }
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_EXPORT) return false
        val result = pending ?: return true
        val bytes = content ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            clear()
            result.success(false)
            return true
        }
        Thread {
            try {
                val stream = activity.contentResolver.openOutputStream(uri, "wt")
                    ?: throw IllegalStateException("No document stream")
                stream.use { it.write(bytes); it.flush() }
                activity.runOnUiThread {
                    if (pending === result) { clear(); result.success(true) }
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    if (pending === result) {
                        clear()
                        result.error("export_write_failed", "Не удалось сохранить документ", null)
                    }
                }
            }
        }.start()
        return true
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        val result = pending
        clear()
        result?.error("export_interrupted", "Сохранение прервано закрытием приложения", null)
    }

    private fun clear() { pending = null; content = null }
    private companion object { const val REQUEST_EXPORT = 4106 }
}
