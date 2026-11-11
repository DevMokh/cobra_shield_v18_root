package com.cobrashield.cobra_shield

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: String? = null

    // OCR بيشتغل على thread خلفي واحد (TessBaseAPI مش thread-safe)
    private val ocrExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val ocr = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cobra/ocr")
        ocr.setMethodCallHandler { call, result ->
            if (call.method != "recognize") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("bad_args", "path is required", null)
                return@setMethodCallHandler
            }
            ocrExecutor.execute {
                try {
                    val r = TesseractOcr.recognize(applicationContext, path)
                    val map = hashMapOf<String, Any>(
                        "text" to r.text,
                        "confidence" to r.confidence,
                        "inverted" to r.inverted,
                        "langs" to "ara+eng"
                    )
                    runOnUiThread { result.success(map) }
                } catch (e: OcrModelMissingException) {
                    runOnUiThread { result.error("model_missing", e.message, null) }
                } catch (e: OutOfMemoryError) {
                    runOnUiThread { result.error("out_of_memory", "image too large", null) }
                } catch (t: Throwable) {
                    val msg = t.javaClass.simpleName + ": " + (t.message ?: "")
                    runOnUiThread { result.error("ocr_failed", msg, null) }
                }
            }
        }

        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cobra/share")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialText" -> {
                    result.success(pending)
                    pending = null
                }
                else -> result.notImplemented()
            }
        }
        channel = ch

        // النص اللي فتح التطبيق (لو جاي من مشاركة)
        val text = extractText(intent)
        if (text != null) {
            pending = text
            // نمنع إعادة قراءته لو الـ Activity اتعمل لها restore
            intent.action = Intent.ACTION_MAIN
        }
    }

    override fun onDestroy() {
        ocrExecutor.shutdown()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractText(intent) ?: return
        intent.action = Intent.ACTION_MAIN
        val ch = channel
        if (ch != null) {
            ch.invokeMethod("onText", text)
        } else {
            pending = text
        }
    }

    private fun extractText(i: Intent?): String? {
        if (i == null) return null
        return when (i.action) {
            Intent.ACTION_SEND ->
                if (i.type?.startsWith("text/") == true) i.getStringExtra(Intent.EXTRA_TEXT) else null
            Intent.ACTION_PROCESS_TEXT ->
                i.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            else -> null
        }
    }
}
