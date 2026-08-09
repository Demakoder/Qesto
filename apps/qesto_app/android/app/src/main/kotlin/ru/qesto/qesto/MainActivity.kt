package ru.qesto.qesto

import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val notificationChannelName = "ru.qesto.qesto/notifications"
    private val statementChannelName = "ru.qesto.qesto/statements"
    private val receiptChannelName = "ru.qesto.qesto/receipts"
    private var pendingStatementResult: MethodChannel.Result? = null
    private var pendingReceiptResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            notificationChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasAccess" -> result.success(hasNotificationAccess())

                "openSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS),
                    )
                    result.success(null)
                }

                "readNotifications" -> {
                    result.success(
                        NotificationInbox.readAll(applicationContext),
                    )
                }

                "clearNotifications" -> {
                    NotificationInbox.clear(applicationContext)
                    result.success(null)
                }

                "removeNotification" -> {
                    val notificationKey = call.argument<String>("notificationKey")
                    if (notificationKey.isNullOrBlank()) {
                        result.error(
                            "invalid_notification_key",
                            "notificationKey is required",
                            null,
                        )
                    } else {
                        NotificationInbox.remove(
                            applicationContext,
                            notificationKey,
                        )
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            statementChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickPdf" -> {
                    if (pendingStatementResult != null) {
                        result.error(
                            "statement_picker_busy",
                            "A statement is already being selected",
                            null,
                        )
                    } else {
                        pendingStatementResult = result
                        startActivityForResult(
                            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/pdf"
                            },
                            REQUEST_STATEMENT_PDF,
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            receiptChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanReceiptQr" -> scanReceiptQr(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun scanReceiptQr(result: MethodChannel.Result) {
        if (pendingReceiptResult != null) {
            result.error(
                "receipt_scanner_busy",
                "Сканер чеков уже открыт",
                null,
            )
            return
        }

        pendingReceiptResult = result
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .enableAutoZoom()
            .build()
        GmsBarcodeScanning.getClient(this, options)
            .startScan()
            .addOnSuccessListener { barcode ->
                val pending = pendingReceiptResult ?: return@addOnSuccessListener
                pendingReceiptResult = null
                val rawValue = barcode.rawValue
                if (rawValue.isNullOrBlank()) {
                    pending.error(
                        "receipt_qr_empty",
                        "QR-код чека не содержит данных",
                        null,
                    )
                } else {
                    pending.success(rawValue)
                }
            }
            .addOnCanceledListener {
                val pending = pendingReceiptResult ?: return@addOnCanceledListener
                pendingReceiptResult = null
                pending.success(null)
            }
            .addOnFailureListener { error ->
                val pending = pendingReceiptResult ?: return@addOnFailureListener
                pendingReceiptResult = null
                pending.error(
                    "receipt_scan_failed",
                    "Не удалось отсканировать QR-код чека",
                    error.javaClass.simpleName,
                )
            }
    }

    @Deprecated("Deprecated in Android SDK, kept for FlutterActivity compatibility")
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_STATEMENT_PDF) return

        val result = pendingStatementResult ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingStatementResult = null
            result.success(null)
            return
        }
        extractStatement(uri, result)
    }

    private fun extractStatement(uri: Uri, result: MethodChannel.Result) {
        Thread {
            try {
                val metadata = statementMetadata(uri)
                if (metadata.size != null && metadata.size > MAX_STATEMENT_BYTES) {
                    throw IllegalArgumentException("PDF file is larger than 20 MB")
                }

                PDFBoxResourceLoader.init(applicationContext)
                val text = contentResolver.openInputStream(uri)?.use { input ->
                    PDDocument.load(input).use { document ->
                        PDFTextStripper().apply {
                            sortByPosition = true
                        }.getText(document)
                    }
                } ?: throw IllegalArgumentException("Unable to open selected PDF")

                runOnUiThread {
                    pendingStatementResult = null
                    result.success(
                        mapOf(
                            "fileName" to metadata.name,
                            "text" to text,
                        ),
                    )
                }
            } catch (error: Exception) {
                runOnUiThread {
                    pendingStatementResult = null
                    result.error(
                        "statement_read_failed",
                        "Не удалось прочитать PDF-выписку",
                        error.javaClass.simpleName,
                    )
                }
            }
        }.start()
    }

    private fun statementMetadata(uri: Uri): StatementMetadata {
        var name = "Выписка.pdf"
        var size: Long? = null
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (nameIndex >= 0) {
                    name = cursor.getString(nameIndex) ?: name
                }
                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                    size = cursor.getLong(sizeIndex)
                }
            }
        }
        return StatementMetadata(name = name, size = size)
    }

    private fun hasNotificationAccess(): Boolean {
        val component = ComponentName(
            this,
            BankNotificationListener::class.java,
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            val manager = getSystemService(
                Context.NOTIFICATION_SERVICE,
            ) as NotificationManager

            manager.isNotificationListenerAccessGranted(component)
        } else {
            val enabledListeners = Settings.Secure.getString(
                contentResolver,
                "enabled_notification_listeners",
            ).orEmpty()

            enabledListeners.contains(component.flattenToString())
        }
    }

    private data class StatementMetadata(
        val name: String,
        val size: Long?,
    )

    private companion object {
        const val MAX_STATEMENT_BYTES = 20L * 1024L * 1024L
        const val REQUEST_STATEMENT_PDF = 4102
    }
}
