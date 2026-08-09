package ru.qesto.qesto

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.googlecode.tesseract.android.TessBaseAPI
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.text.PDFTextStripper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val notificationChannelName = "ru.qesto.qesto/notifications"
    private val statementChannelName = "ru.qesto.qesto/statements"
    private val receiptChannelName = "ru.qesto.qesto/receipts"
    private val voiceChannelName = "ru.qesto.qesto/voice"
    private var pendingStatementResult: MethodChannel.Result? = null
    private var pendingReceiptResult: MethodChannel.Result? = null
    private var pendingReceiptDocumentResult: MethodChannel.Result? = null
    private var pendingVoiceResult: MethodChannel.Result? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var voiceRecognitionOnDevice = false

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
                "scanReceiptDocument" -> scanReceiptDocument(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            voiceChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "recognizeTransaction" -> recognizeVoiceTransaction(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun recognizeVoiceTransaction(result: MethodChannel.Result) {
        if (pendingVoiceResult != null) {
            result.error(
                "voice_recognizer_busy",
                "Распознавание речи уже запущено",
                null,
            )
            return
        }

        pendingVoiceResult = result
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                REQUEST_RECORD_AUDIO,
            )
            return
        }
        startVoiceRecognition()
    }

    private fun startVoiceRecognition() {
        val pending = pendingVoiceResult ?: return
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            pendingVoiceResult = null
            pending.error(
                "voice_recognizer_unavailable",
                "На телефоне не найден системный модуль распознавания речи",
                null,
            )
            return
        }

        try {
            speechRecognizer?.destroy()
            voiceRecognitionOnDevice =
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
            speechRecognizer = if (voiceRecognitionOnDevice) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
            } else {
                SpeechRecognizer.createSpeechRecognizer(this)
            }
            speechRecognizer?.setRecognitionListener(
                object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) = Unit
                    override fun onBeginningOfSpeech() = Unit
                    override fun onRmsChanged(rmsdB: Float) = Unit
                    override fun onBufferReceived(buffer: ByteArray?) = Unit
                    override fun onEndOfSpeech() = Unit
                    override fun onPartialResults(partialResults: Bundle?) = Unit
                    override fun onEvent(eventType: Int, params: Bundle?) = Unit

                    override fun onError(error: Int) {
                        finishVoiceWithError(error)
                    }

                    override fun onResults(results: Bundle?) {
                        val text = results
                            ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                            ?.firstOrNull()
                            ?.trim()
                        if (text.isNullOrEmpty()) {
                            finishVoiceWithError(SpeechRecognizer.ERROR_NO_MATCH)
                            return
                        }
                        val result = pendingVoiceResult ?: return
                        pendingVoiceResult = null
                        result.success(
                            mapOf(
                                "text" to text,
                                "onDevice" to voiceRecognitionOnDevice,
                            ),
                        )
                        releaseSpeechRecognizer()
                    }
                },
            )
            speechRecognizer?.startListening(
                Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(
                        RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                        RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                    )
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, "ru-RU")
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                    putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                },
            )
        } catch (error: Exception) {
            pendingVoiceResult = null
            pending.error(
                "voice_recognizer_failed",
                "Не удалось запустить распознавание речи",
                error.javaClass.simpleName,
            )
            releaseSpeechRecognizer()
        }
    }

    private fun finishVoiceWithError(error: Int) {
        val result = pendingVoiceResult ?: return
        pendingVoiceResult = null
        val message = when (error) {
            SpeechRecognizer.ERROR_AUDIO -> "Не удалось записать звук"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                "Нет разрешения на использование микрофона"
            SpeechRecognizer.ERROR_NETWORK,
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                "Системному распознавателю не удалось подключиться к сети"
            SpeechRecognizer.ERROR_NO_MATCH ->
                "Не удалось разобрать фразу. Произнесите её ещё раз"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY ->
                "Системный распознаватель сейчас занят"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                "Речь не услышана. Нажмите микрофон и повторите фразу"
            else -> "Не удалось распознать речь"
        }
        result.error("voice_recognition_failed", message, error)
        releaseSpeechRecognizer()
    }

    private fun releaseSpeechRecognizer() {
        speechRecognizer?.destroy()
        speechRecognizer = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_RECORD_AUDIO) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startVoiceRecognition()
        } else {
            val result = pendingVoiceResult ?: return
            pendingVoiceResult = null
            result.error(
                "microphone_permission_denied",
                "Разрешите Qesto использовать микрофон в настройках Android",
                null,
            )
        }
    }

    override fun onDestroy() {
        pendingVoiceResult = null
        releaseSpeechRecognizer()
        super.onDestroy()
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

    private fun scanReceiptDocument(result: MethodChannel.Result) {
        if (pendingReceiptDocumentResult != null) {
            result.error(
                "receipt_document_scanner_busy",
                "Сканер бумажного чека уже открыт",
                null,
            )
            return
        }

        pendingReceiptDocumentResult = result
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(true)
            .setPageLimit(1)
            .setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            .setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_FULL)
            .build()

        GmsDocumentScanning.getClient(options)
            .getStartScanIntent(this)
            .addOnSuccessListener { intentSender ->
                startIntentSenderForResult(
                    intentSender,
                    REQUEST_RECEIPT_DOCUMENT,
                    null,
                    0,
                    0,
                    0,
                )
            }
            .addOnFailureListener { error ->
                val pending = pendingReceiptDocumentResult
                    ?: return@addOnFailureListener
                pendingReceiptDocumentResult = null
                pending.error(
                    "receipt_document_scan_failed",
                    "Не удалось открыть сканер бумажного чека",
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
        when (requestCode) {
            REQUEST_STATEMENT_PDF -> {
                val result = pendingStatementResult ?: return
                val uri = data?.data
                if (resultCode != Activity.RESULT_OK || uri == null) {
                    pendingStatementResult = null
                    result.success(null)
                    return
                }
                extractStatement(uri, result)
            }

            REQUEST_RECEIPT_DOCUMENT -> {
                val result = pendingReceiptDocumentResult ?: return
                if (resultCode != Activity.RESULT_OK) {
                    pendingReceiptDocumentResult = null
                    result.success(null)
                    return
                }
                val scan = GmsDocumentScanningResult
                    .fromActivityResultIntent(data)
                val uri = scan?.pages?.firstOrNull()?.imageUri
                if (uri == null) {
                    pendingReceiptDocumentResult = null
                    result.error(
                        "receipt_document_empty",
                        "Сканер не вернул изображение чека",
                        null,
                    )
                    return
                }
                recognizeReceiptDocument(uri, result)
            }
        }
    }

    private fun recognizeReceiptDocument(
        uri: Uri,
        result: MethodChannel.Result,
    ) {
        Thread {
            var tess: TessBaseAPI? = null
            var imageFile: File? = null
            try {
                val dataPath = ensureRussianOcrData()
                imageFile = copyReceiptImageToCache(uri)
                tess = TessBaseAPI()
                if (!tess.init(dataPath, "rus", TessBaseAPI.OEM_LSTM_ONLY)) {
                    throw IllegalStateException("Unable to initialize Russian OCR")
                }
                tess.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)
                tess.setVariable("preserve_interword_spaces", "1")
                tess.setVariable("user_defined_dpi", "300")
                tess.setImage(imageFile)
                val text = tess.getUTF8Text().orEmpty().trim()
                if (text.isEmpty()) {
                    throw IllegalArgumentException("No text recognized")
                }
                val lines = text.lineSequence()
                    .map { it.trim() }
                    .filter { it.isNotEmpty() }
                    .map { line -> mapOf("text" to line) }
                    .toList()

                runOnUiThread {
                    val pending = pendingReceiptDocumentResult
                        ?: return@runOnUiThread
                    pendingReceiptDocumentResult = null
                    pending.success(
                        mapOf(
                            "text" to text,
                            "lines" to lines,
                        ),
                    )
                }
            } catch (error: Exception) {
                runOnUiThread {
                    val pending = pendingReceiptDocumentResult
                        ?: return@runOnUiThread
                    pendingReceiptDocumentResult = null
                    pending.error(
                        "receipt_ocr_failed",
                        "Не удалось распознать русский текст бумажного чека",
                        error.javaClass.simpleName,
                    )
                }
            } finally {
                tess?.recycle()
                imageFile?.delete()
            }
        }.start()
    }

    private fun ensureRussianOcrData(): String {
        val dataDirectory = File(filesDir, "tesseract")
        val tessdataDirectory = File(dataDirectory, "tessdata")
        if (!tessdataDirectory.exists() && !tessdataDirectory.mkdirs()) {
            throw IllegalStateException("Unable to create OCR data directory")
        }

        val model = File(tessdataDirectory, RUSSIAN_OCR_MODEL)
        if (!model.exists() || model.length() != RUSSIAN_OCR_MODEL_BYTES) {
            val temporary = File(tessdataDirectory, "$RUSSIAN_OCR_MODEL.tmp")
            assets.open("tessdata/$RUSSIAN_OCR_MODEL").use { input ->
                temporary.outputStream().use { output -> input.copyTo(output) }
            }
            if (model.exists() && !model.delete()) {
                throw IllegalStateException("Unable to replace OCR model")
            }
            if (!temporary.renameTo(model)) {
                temporary.copyTo(model, overwrite = true)
                temporary.delete()
            }
        }
        return dataDirectory.absolutePath
    }

    private fun copyReceiptImageToCache(uri: Uri): File {
        val target = File(cacheDir, "receipt-ocr-${System.nanoTime()}.jpg")
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: throw IllegalArgumentException("Unable to open receipt image")
        return target
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
        const val REQUEST_RECEIPT_DOCUMENT = 4103
        const val REQUEST_RECORD_AUDIO = 4104
        const val RUSSIAN_OCR_MODEL = "rus.traineddata"
        const val RUSSIAN_OCR_MODEL_BYTES = 3_861_738L
    }
}
