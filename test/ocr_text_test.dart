import 'package:cobra_shield/services/ocr_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cleanOcrText', () {
    test('يوحّد نهايات الأسطر', () {
      expect(cleanOcrText('a\r\nb'), 'a\nb');
      expect(cleanOcrText('l1\rl2\r\r\r\rl3'), 'l1\nl2\n\nl3');
    });

    test('يشيل فاصل الصفحة ومحارف التحكم', () {
      expect(cleanOcrText('سلام\f'), 'سلام');
      expect(cleanOcrText('a\u0001b'), 'ab');
    });

    test('يدمج الأسطر الفاضية المتتالية', () {
      expect(cleanOcrText('a  \n\n\n\nb'), 'a\n\nb');
    });

    test('يشيل المسافات في آخر السطر وحول النص', () {
      expect(cleanOcrText('\n\n  x  \n'), 'x');
      expect(cleanOcrText('رابط: http://a.com '), 'رابط: http://a.com');
    });

    test('يحافظ على التاب داخل السطر', () {
      expect(cleanOcrText('a\tb'), 'a\tb');
    });

    test('نص فاضي أو مسافات فقط يرجّع نص فاضي', () {
      expect(cleanOcrText(''), '');
      expect(cleanOcrText('   \n  \n'), '');
    });
  });

  qualityTests();
}

// تقييم الجودة (assessOcrQuality)
void qualityTests() {
  group('assessOcrQuality', () {
    test('نص عربي/إنجليزي عادي = good', () {
      expect(assessOcrQuality('مرحبا بك في خدمة العملاء، رابط http://a.example.com'),
          OcrQuality.good);
    });
    test('فاضي أو رموز فقط = empty', () {
      expect(assessOcrQuality(''), OcrQuality.empty);
      expect(assessOcrQuality('  \n '), OcrQuality.empty);
      expect(assessOcrQuality('!!! ... ---'), OcrQuality.empty);
      expect(assessOcrQuality('ab'), OcrQuality.empty);
    });
    test('قصير جدًا = low', () {
      expect(assessOcrQuality('شكرا لك'), OcrQuality.low);
    });
    test('ثقة منخفضة = low حتى لو النص طويل', () {
      expect(assessOcrQuality('مرحبا بك في خدمة العملاء الرسمية', confidence: 40),
          OcrQuality.low);
      expect(assessOcrQuality('مرحبا بك في خدمة العملاء الرسمية', confidence: 80),
          OcrQuality.good);
    });
    test('رموز غريبة كتير = low', () {
      expect(assessOcrQuality('ab ¶¶§§ ░▒▓█ ◊◊ ab cd ef gh ■■■■■■■'), OcrQuality.low);
    });
  });
}
