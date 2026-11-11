import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_text.dart';

/// المحرك اللي اتستخدم فعليًا في آخر قراءة.
enum OcrEngine {
  /// Tesseract على الجهاز: عربي + إنجليزي.
  tesseract,

  /// ML Kit (لاتيني فقط): إنجليزي وأرقام وروابط، ومبيقراش العربي.
  mlkitLatin,
}

/// نتيجة قراءة صورة، مع المحرك المستخدم عشان الواجهة تقول للمستخدم الحقيقة.
class OcrOutcome {
  const OcrOutcome({
    required this.text,
    required this.engine,
    this.fallbackReason,
    this.confidence,
    this.invertedPass = false,
    bool? arabicCovered,
  }) : _arabicCovered = arabicCovered;

  final String text;
  final OcrEngine engine;

  /// سبب الرجوع للمحرك اللاتيني (null لو Tesseract اشتغل عادي). أكواد: unavailable /
  /// timeout / model_missing / out_of_memory / ocr_failed / tesseract_empty.
  final String? fallbackReason;

  /// متوسط ثقة Tesseract (0-100) لو متاح (مش متاح مع المحرك اللاتيني).
  final int? confidence;

  /// القراءة اتعملت على نسخة معكوسة الألوان (صورة داكنة).
  final bool invertedPass;

  final bool? _arabicCovered;

  /// محرك بيدعم العربي أخد فرصته كاملة على الصورة (حتى لو لقى نص فاضي). لو false يبقى
  /// أي كلام عربي في الصورة ممكن يكون ما اتقراش، فالتحليل لازم يتعامل معاه كفحص ناقص.
  bool get readsArabic => _arabicCovered ?? engine == OcrEngine.tesseract;

  OcrQuality get quality => assessOcrQuality(text, confidence: confidence);

  /// النص فيه حروف عربية فعلًا.
  bool get containsArabic => RegExp(r'[\u0600-\u06FF]').hasMatch(text);
}

class _TessRaw {
  const _TessRaw(this.text, this.confidence, this.inverted);
  final String text;
  final int? confidence;
  final bool inverted;
}

/// استخراج نص من صورة (سكرين شوت رسالة) على الجهاز بالكامل، بدون إنترنت.
///
/// الأساسي: Tesseract (عربي + إنجليزي) عن طريق كود أندرويد أصلي (قناة cobra/ocr).
/// لو المحرك الأساسي مش متاح أو فشل (نموذج ناقص، ذاكرة، مهلة...) بنرجع تلقائيًا
/// لـ ML Kit اللاتيني، وبنرجّع في النتيجة إن العربي ما اتقراش، فالواجهة تنبّه
/// المستخدم. لو Tesseract اشتغل وما لقاش نص بنجرّب ML Kit كمان (يلقط إنجليزي/روابط
/// أحيانًا)، ولو لقى نص بنستخدمه من غير ما نقول إن العربي ما اتقراش (Tesseract قراه فعلًا).
/// لو المحركين فشلوا بيترمي استثناء (الفشل مش معناه "الصورة آمنة").
///
/// تنبيه: دعم العربي هنا مبني على Tesseract (tessdata_fast) وبدون اختبار فعلي على
/// أجهزة أندرويد في بيئة التطوير؛ لا تعتبره مكتمل قبل تجربة صور عربية حقيقية.
class OcrService {
  OcrService._();

  static const MethodChannel _channel = MethodChannel('cobra/ocr');
  static const Duration _tesseractTimeout = Duration(seconds: 60);

  static TextRecognizer? _recognizer;

  /// للاختبارات فقط: بديل للمحرك اللاتيني (ML Kit).
  @visibleForTesting
  static Future<String> Function(String path)? latinFallbackOverride;

  static TextRecognizer get _latin =>
      _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);

  /// الرد من القناة: Map جديد {text, confidence, inverted} أو String قديم (للتوافق).
  static _TessRaw _parse(Object? raw) {
    if (raw is Map) {
      final c = raw['confidence'];
      return _TessRaw(
        (raw['text'] ?? '').toString(),
        c is num ? c.round() : null,
        raw['inverted'] == true,
      );
    }
    return _TessRaw(raw?.toString() ?? '', null, false);
  }

  static Future<String> _runLatin(String path) async {
    final override = latinFallbackOverride;
    final String t = override != null
        ? await override(path)
        : (await _latin.processImage(InputImage.fromFilePath(path))).text;
    return cleanOcrText(t);
  }

  static Future<OcrOutcome> extract(String path) async {
    String reason;
    try {
      final Object? raw = await _channel
          .invokeMethod<Object?>('recognize', <String, String>{'path': path})
          .timeout(_tesseractTimeout);
      final t = _parse(raw);
      final tess = OcrOutcome(
        text: cleanOcrText(t.text),
        engine: OcrEngine.tesseract,
        confidence: t.confidence,
        invertedPass: t.inverted,
      );
      if (tess.quality != OcrQuality.empty) return tess;
      // Tesseract ما لقاش نص يُذكر: ML Kit ممكن يلقط إنجليزي/أرقام/روابط. لو فشل نكمل بالنتيجة الفاضية.
      try {
        final latin = await _runLatin(path);
        if (assessOcrQuality(latin) != OcrQuality.empty) {
          return OcrOutcome(
            text: latin,
            engine: OcrEngine.mlkitLatin,
            fallbackReason: 'tesseract_empty',
            arabicCovered: true, // Tesseract (بيدعم العربي) اشتغل ومالقاش عربي
          );
        }
      } catch (_) {}
      return tess;
    } on MissingPluginException {
      reason = 'unavailable';
    } on PlatformException catch (e) {
      reason = e.code;
    } on TimeoutException {
      reason = 'timeout';
    }

    // Tesseract فشل: ML Kit اللاتيني (من غير عربي). لو ده كمان فشل الاستثناء بيطلع للمستدعي.
    return OcrOutcome(
      text: await _runLatin(path),
      engine: OcrEngine.mlkitLatin,
      fallbackReason: reason,
    );
  }

  static Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
