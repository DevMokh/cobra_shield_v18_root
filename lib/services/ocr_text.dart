/// تنظيف النص الخارج من محرك قراءة الصور (OCR) قبل عرضه للمستخدم أو تحليله.
///
/// دالة نقية (بدون أي مكتبات) عشان تتختبر بسهولة:
/// - توحيد نهايات الأسطر.
/// - شيل محارف التحكم اللي بيرجّعها Tesseract (زي فاصل الصفحة \f).
/// - شيل المسافات الزايدة في آخر كل سطر.
/// - دمج الأسطر الفاضية المتتالية في سطر فاضي واحد.
String cleanOcrText(String raw) {
  var s = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // محارف التحكم (ما عدا \n و \t)
  s = s.replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'), '');
  final lines = s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t ]+$'), ''));
  final out = <String>[];
  var blank = 0;
  for (final l in lines) {
    if (l.trim().isEmpty) {
      blank++;
      if (blank > 1) continue;
      out.add('');
    } else {
      blank = 0;
      out.add(l);
    }
  }
  return out.join('\n').trim();
}

/// جودة النص المستخرج: بتتحدد من النص نفسه (ومن ثقة المحرك لو متاحة).
enum OcrQuality {
  /// نص مقروء بشكل معقول (لسه محتاج مراجعة بشرية).
  good,

  /// نص قصير جدًا أو ثقة المحرك منخفضة أو فيه رموز غريبة كتير: على الأغلب فيه أخطاء أو نقص.
  low,

  /// مفيش نص تقريبًا (أقل من 3 حروف/أرقام).
  empty,
}

/// ثقة المحرك (0-100) الأقل منها تعتبر منخفضة.
const int kOcrLowConfidence = 55;

const String _okPunct = '.,:;!?()[]{}<>/\\-_@#%&*+=~"\'`|\$€£،؛؟…«»';

bool _isOcrWordChar(int r) =>
    (r >= 0x30 && r <= 0x39) ||
    (r >= 0x41 && r <= 0x5A) ||
    (r >= 0x61 && r <= 0x7A) ||
    (r >= 0xC0 && r <= 0x24F) ||
    (r >= 0x0621 && r <= 0x064A) ||
    (r >= 0x0660 && r <= 0x0669) ||
    (r >= 0x066E && r <= 0x06D3) ||
    (r >= 0x06F0 && r <= 0x06F9) ||
    (r >= 0x0750 && r <= 0x077F);

/// يقيّم جودة نص OCR. دالة نقية للاختبار.
OcrQuality assessOcrQuality(String text, {int? confidence}) {
  var words = 0;
  var total = 0;
  var odd = 0;
  for (final r in text.runes) {
    if (r == 0x20 || r == 0x0A || r == 0x09 || r == 0xA0) continue;
    total++;
    if (_isOcrWordChar(r)) {
      words++;
    } else if (!_okPunct.contains(String.fromCharCode(r))) {
      odd++;
    }
  }
  if (words < 3) return OcrQuality.empty;
  if (confidence != null && confidence < kOcrLowConfidence) return OcrQuality.low;
  if (words < 8) return OcrQuality.low;
  if (total > 0 && odd / total > 0.30) return OcrQuality.low;
  return OcrQuality.good;
}
