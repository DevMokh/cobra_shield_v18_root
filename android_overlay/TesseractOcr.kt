package com.cobrashield.cobra_shield

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Matrix
import android.graphics.Paint
import android.media.ExifInterface
import com.googlecode.tesseract.android.TessBaseAPI
import java.io.File
import java.io.FileNotFoundException
import java.io.FileOutputStream
import kotlin.math.max

/** نموذج اللغة ناقص أو تالف داخل التطبيق (الـ APK اتبنى من غير نماذج tessdata سليمة). */
class OcrModelMissingException(message: String) : Exception(message)

/** نتيجة قراءة: النص + متوسط الثقة (0-100) + هل القراءة اتعملت على صورة معكوسة الألوان. */
class OcrResult(val text: String, val confidence: Int, val inverted: Boolean)

/**
 * قراءة نص عربي + إنجليزي من صورة على الجهاز بالكامل (Tesseract).
 * نماذج اللغة (tessdata_fast) بتتنسخ مرة واحدة من assets لمجلد التطبيق الخاص.
 * مفيش أي اتصال بالإنترنت وقت القراءة.
 */
object TesseractOcr {
    private const val LANGS = "ara+eng"
    private val DATA_FILES = arrayOf("ara.traineddata", "eng.traineddata")

    /** أقصى طول لأي ضلع بعد التصغير (يحمي الذاكرة من الصور الكبيرة جدًا) */
    private const val MAX_SIDE = 2600

    /** أصغر حجم منطقي لملف نموذج (tessdata_fast: ara ~1.4MB, eng ~4MB). أقل من كده = ناقص/تالف. */
    private const val MIN_MODEL_BYTES = 500_000L

    /** لو ثقة القراءة الأولى أقل من كده نجرّب نفس الصورة بالألوان المعكوسة ونختار الأفضل. */
    private const val RETRY_BELOW = 60

    /** متوسط سطوع (0-255) أقل منه = صورة داكنة (سكرين شوت وضع ليلي): نبدأ بالمعكوسة. */
    private const val DARK_LUMA = 110

    private fun ensureData(context: Context): String {
        val root = File(context.filesDir, "tesseract")
        val dir = File(root, "tessdata")
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("cannot create tessdata dir")
        }
        for (name in DATA_FILES) {
            val out = File(dir, name)
            if (out.exists() && out.length() >= MIN_MODEL_BYTES) continue
            if (out.exists()) out.delete() // نسخة ناقصة/تالفة من قبل: نعيد النسخ
            // نكتب في ملف مؤقت ثم نعمل rename: عشان ما يتبقاش ملف نصف مكتوب
            val tmp = File(dir, "$name.part")
            try {
                context.assets.open("tessdata/$name").use { input ->
                    FileOutputStream(tmp).use { output -> input.copyTo(output) }
                }
            } catch (e: FileNotFoundException) {
                tmp.delete()
                throw OcrModelMissingException("model asset missing: $name")
            }
            if (tmp.length() < MIN_MODEL_BYTES) {
                tmp.delete()
                throw OcrModelMissingException("model asset too small (corrupt?): $name")
            }
            if (!tmp.renameTo(out)) {
                tmp.delete()
                throw IllegalStateException("cannot install $name")
            }
        }
        return root.absolutePath
    }

    private fun loadBitmap(path: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

        var sample = 1
        val longest = max(bounds.outWidth, bounds.outHeight)
        while (longest / sample > MAX_SIDE) sample *= 2

        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        var bmp = BitmapFactory.decodeFile(path, opts) ?: return null

        // تصحيح اتجاه صور الكاميرا (EXIF)
        val degrees = try {
            when (
                ExifInterface(path).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL
                )
            ) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } catch (e: Exception) {
            0f
        }
        if (degrees != 0f) {
            val m = Matrix()
            m.postRotate(degrees)
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
            if (rotated !== bmp) bmp.recycle()
            bmp = rotated
        }
        return bmp
    }

    /** هل الصورة داكنة (نص فاتح على خلفية غامقة)؟ بنقيس متوسط السطوع على عيّنة من البكسلات. */
    private fun isDark(bmp: Bitmap): Boolean {
        val w = bmp.width
        val h = bmp.height
        val step = max(1, max(w, h) / 64)
        var sum = 0L
        var n = 0
        var y = 0
        while (y < h) {
            var x = 0
            while (x < w) {
                val p = bmp.getPixel(x, y)
                sum += (Color.red(p) * 299 + Color.green(p) * 587 + Color.blue(p) * 114) / 1000
                n++
                x += step
            }
            y += step
        }
        return n > 0 && (sum / n) < DARK_LUMA
    }

    /** نسخة معكوسة الألوان من الصورة (Tesseract بيقرأ نص غامق على خلفية فاتحة أحسن بكتير). */
    private fun invert(src: Bitmap): Bitmap {
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val paint = Paint()
        paint.colorFilter = ColorMatrixColorFilter(
            ColorMatrix(
                floatArrayOf(
                    -1f, 0f, 0f, 0f, 255f,
                    0f, -1f, 0f, 0f, 255f,
                    0f, 0f, -1f, 0f, 255f,
                    0f, 0f, 0f, 1f, 0f
                )
            )
        )
        Canvas(out).drawBitmap(src, 0f, 0f, paint)
        return out
    }

    private fun readOnce(api: TessBaseAPI, bmp: Bitmap, inverted: Boolean): OcrResult {
        api.setImage(bmp)
        val text = api.getUTF8Text() ?: ""
        val conf = try {
            api.meanConfidence()
        } catch (e: Throwable) {
            0
        }
        return OcrResult(text, conf, inverted)
    }

    private fun better(a: OcrResult, b: OcrResult): Boolean {
        if (a.text.isBlank()) return false
        return b.text.isBlank() || a.confidence > b.confidence
    }

    /**
     * يرجّع النص المقروء + الثقة (ممكن يكون النص فاضي لو مفيش نص). يرمي استثناء لو فشل المحرك:
     * [OcrModelMissingException] لو نموذج اللغة ناقص، غيره لأي فشل تاني.
     * للصور الداكنة بنبدأ بنسخة معكوسة، ولو الثقة منخفضة بنجرّب الاتجاه التاني ونختار الأفضل.
     */
    fun recognize(context: Context, path: String): OcrResult {
        val bitmap = loadBitmap(path) ?: throw IllegalArgumentException("cannot decode image")
        val api = TessBaseAPI()
        var inverted: Bitmap? = null
        try {
            val dataPath = ensureData(context)
            if (!api.init(dataPath, LANGS)) {
                throw IllegalStateException("tesseract init failed")
            }
            api.setPageSegMode(TessBaseAPI.PageSegMode.PSM_AUTO)

            val dark = isDark(bitmap)
            var best: OcrResult
            if (dark) {
                val inv = invert(bitmap)
                inverted = inv
                best = readOnce(api, inv, true)
            } else {
                best = readOnce(api, bitmap, false)
            }
            if (best.confidence < RETRY_BELOW) {
                // محاولة تانية اختيارية: لو فشلت (ذاكرة مثلًا) نكمل بالنتيجة الأولى.
                try {
                    val second: OcrResult
                    if (dark) {
                        second = readOnce(api, bitmap, false)
                    } else {
                        val inv = invert(bitmap)
                        inverted = inv
                        second = readOnce(api, inv, true)
                    }
                    if (better(second, best)) best = second
                } catch (e: Throwable) {
                    // نتجاهل
                }
            }
            return best
        } finally {
            api.recycle()
            bitmap.recycle()
            inverted?.recycle()
        }
    }
}
