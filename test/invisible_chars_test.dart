import 'package:flutter_test/flutter_test.dart';

import 'package:cobra_shield/core/models.dart';
import 'package:cobra_shield/services/invisible_chars.dart';
import 'package:cobra_shield/services/message_analyzer.dart';
import 'package:cobra_shield/services/url_analyzer.dart';
import 'package:cobra_shield/services/url_normalizer.dart';

// اختبارات الحروف الخفية ومحارف اتجاه النص (قسم 6 من المهمة).
// القاعدة: LRM (U+200E) و RLM (U+200F) و ALM (U+061C) علامات اتجاه طبيعية في النص
// العربي/الإنجليزي المختلط، فمش تهديد ومالهاش نقاط. المحارف اللي بتقلب ترتيب العرض أو
// بتقطّع الكلمات أو بتخبّي نص هي اللي بتتحذّر منها، وبسبب محدد (مش تحذير عام).
void main() {
  String cp(int r) => String.fromCharCode(r);
  Set<String> codes(InvisibleReport r) => r.issues.map((i) => i.code).toSet();

  group('علامات الاتجاه الطبيعية: مش تهديد', () {
    for (final r in <int>[0x200E, 0x200F, 0x061C]) {
      test('${InvisibleChars.label(r)} داخل نص عربي/إنجليزي', () {
        final rep = InvisibleChars.analyze('مرحبا ${cp(r)}Hello${cp(r)} كيف الحال');
        expect(rep.hasIssues, isFalse);
        expect(rep.benignCount, 2);
      });
    }

    test('LRM وRLM بجوار رقم أو رابط أو علامة ترقيم', () {
      final rep = InvisibleChars.analyze(
          'الرابط: ${cp(0x200E)}https://example.org${cp(0x200F)} 123${cp(0x200F)}.');
      expect(rep.hasIssues, isFalse);
      expect(rep.benignCount, 3);
    });

    test('نص عادي بدون أي حروف خفية', () {
      final rep = InvisibleChars.analyze('Hello مرحبا 123');
      expect(rep.hasIssues, isFalse);
      expect(rep.benignCount, 0);
    });

    test('نص فاضي', () {
      final rep = InvisibleChars.analyze('');
      expect(rep.hasIssues, isFalse);
    });
  });

  group('حروف تستحق تحذيرًا بسبب محدد', () {
    test('RLO (U+202E) بيقلب ترتيب العرض', () {
      final rep = InvisibleChars.analyze('invoice${cp(0x202E)}fdp.exe');
      expect(codes(rep), contains('bidi_override'));
      expect(rep.issues.first.points, greaterThan(0));
      expect(rep.issues.first.title, contains('U+202E'));
    });

    test('LRO (U+202D) كمان تجاوز اتجاه', () {
      final rep = InvisibleChars.analyze('abc${cp(0x202D)}def${cp(0x202C)}');
      expect(codes(rep), contains('bidi_override'));
    });

    test('عزل اتجاه متوازن (LRI ... PDI) مش تحذير', () {
      final rep = InvisibleChars.analyze('${cp(0x2066)}abc${cp(0x2069)} مرحبا');
      expect(rep.hasIssues, isFalse);
    });

    test('عزل اتجاه غير متوازن (فتح بدون إغلاق)', () {
      final rep = InvisibleChars.analyze('abc ${cp(0x2067)} مرحبا');
      expect(codes(rep), contains('bidi_unbalanced'));
    });

    test('PDI بدون فتح', () {
      final rep = InvisibleChars.analyze('abc${cp(0x2069)}');
      expect(codes(rep), contains('bidi_unbalanced'));
    });

    test('ZWSP (U+200B) وسط كلمة لاتينية بيقطّعها', () {
      final rep = InvisibleChars.analyze('pay${cp(0x200B)}pal');
      expect(codes(rep), contains('zero_width_split'));
      expect(rep.issues.first.title, contains('U+200B'));
    });

    test('Word Joiner (U+2060) وسط كلمة', () {
      final rep = InvisibleChars.analyze('veri${cp(0x2060)}fy');
      expect(codes(rep), contains('zero_width_split'));
    });

    test('ZWNJ بين حرفين لاتينيين = تقطيع', () {
      final rep = InvisibleChars.analyze('log${cp(0x200C)}in');
      expect(codes(rep), contains('zero_width_split'));
    });

    test('ZWNJ بين حروف عربية/فارسية طبيعي', () {
      final rep = InvisibleChars.analyze('می${cp(0x200C)}خواهم');
      expect(rep.hasIssues, isFalse);
    });

    test('ZWJ في تسلسل إيموجي طبيعي', () {
      final rep = InvisibleChars.analyze(
          '\u{1F468}${cp(0x200D)}\u{1F469}${cp(0x200D)}\u{1F467}');
      expect(rep.hasIssues, isFalse);
    });

    test('ZWSP على طرف الكلمة (بعد مسافة) مش تقطيع', () {
      final rep = InvisibleChars.analyze('hello ${cp(0x200B)}world');
      expect(codes(rep), isNot(contains('zero_width_split')));
    });

    test('BOM في أول النص طبيعي، وفي نصه تقطيع', () {
      expect(InvisibleChars.analyze('${cp(0xFEFF)}hello').hasIssues, isFalse);
      expect(codes(InvisibleChars.analyze('hel${cp(0xFEFF)}lo')),
          contains('zero_width_split'));
    });

    test('محارف Tag (U+E0041) نص مخفي', () {
      final rep = InvisibleChars.analyze('hello${cp(0xE0041)}${cp(0xE0042)}');
      expect(codes(rep), contains('tag_chars'));
    });

    test('محرف تحكم (U+0001)', () {
      final rep = InvisibleChars.analyze('abc${cp(0x01)}def');
      expect(codes(rep), contains('control_chars'));
    });

    test('سطر جديد وتاب مش محارف تحكم مشبوهة', () {
      final rep = InvisibleChars.analyze('سطر أول\nسطر ثان\tتاب\r\n');
      expect(rep.hasIssues, isFalse);
    });

    test('تحكم تنسيق مهجور (U+206A)', () {
      final rep = InvisibleChars.analyze('abc${cp(0x206A)}def');
      expect(codes(rep), contains('format_controls'));
    });

    test('نص مختلط: علامات طبيعية + تحذير حقيقي = التحذير الحقيقي فقط', () {
      final rep = InvisibleChars.analyze(
          'مرحبا${cp(0x200F)} Hello${cp(0x200E)} pay${cp(0x200B)}pal');
      expect(codes(rep), {'zero_width_split'});
      expect(rep.benignCount, 2);
    });
  });

  group('تصنيف الحروف', () {
    test('علامات الاتجاه', () {
      expect(InvisibleChars.isBidiMark(0x200E), isTrue);
      expect(InvisibleChars.isBidiMark(0x200F), isTrue);
      expect(InvisibleChars.isBidiMark(0x061C), isTrue);
      expect(InvisibleChars.isBidiMark(0x202E), isFalse);
      expect(InvisibleChars.isBidiMark(0x200B), isFalse);
    });
    test('التجاوز والتضمين والعزل', () {
      expect(InvisibleChars.isBidiOverride(0x202D), isTrue);
      expect(InvisibleChars.isBidiOverride(0x202E), isTrue);
      expect(InvisibleChars.isBidiOverride(0x202A), isFalse);
      expect(InvisibleChars.isBidiEmbedding(0x202A), isTrue);
      expect(InvisibleChars.isBidiIsolate(0x2066), isTrue);
      expect(InvisibleChars.isBidiIsolate(0x2069), isTrue);
    });
    test('صفر العرض', () {
      for (final r in <int>[0x200B, 0x2060, 0xFEFF, 0x00AD]) {
        expect(InvisibleChars.isZeroWidth(r), isTrue, reason: InvisibleChars.label(r));
      }
      expect(InvisibleChars.isZeroWidth(0x0041), isFalse);
    });
    test('label بيرجّع الكود والاسم', () {
      expect(InvisibleChars.label(0x200E), 'U+200E (LRM)');
      expect(InvisibleChars.label(0x200F), 'U+200F (RLM)');
      expect(InvisibleChars.label(0x202E), 'U+202E (RLO)');
    });
  });

  group('محلل الرسائل', () {
    ScanResult analyze(String t) => MessageAnalyzer.analyze(t);
    bool hasCode(ScanResult r, String c) => r.findings.any((f) => f.code == c);

    test('نص عربي مختلط بـ LRM/RLM: مفيش تحذير حروف خفية ولا نقاط', () {
      final r = analyze(
          'هنتقابل ${cp(0x200F)}Starbucks${cp(0x200E)} الساعة ${cp(0x200F)}5${cp(0x200E)} مساءً');
      expect(r.findings.any((f) => f.code.startsWith('bidi_') ||
          f.code == 'zero_width_split' || f.code == 'control_chars'), isFalse);
      expect(r.score, 0);
      expect(r.level, RiskLevel.low);
    });

    test('تقطيع كلمة بحرف صفري: تحذير بسبب محدد ونقاط', () {
      final r = analyze('please verify your pay${cp(0x200B)}pal account today');
      expect(hasCode(r, 'zero_width_split'), isTrue);
      expect(r.score, greaterThan(0));
    });

    test('RLO في رسالة: bidi_override وليس "حروف خفية" عامة', () {
      final r = analyze('الملف المرفق: report${cp(0x202E)}fdp.exe');
      expect(hasCode(r, 'bidi_override'), isTrue);
      expect(r.findings.where((f) => f.title == 'حروف خفية داخل النص'), isEmpty);
    });

    test('الكلمة المقطّعة بحرف صفري لسه بتتطابق مع قاموس الإشارات', () {
      final r = analyze('your account has been susp${cp(0x200B)}ended');
      expect(hasCode(r, 'msg_threat'), isTrue);
    });

    test('RLM في آخر الرابط داخل الرسالة مش بتتحسب', () {
      final r = analyze('الرابط https://example.org/page${cp(0x200F)} شكرا');
      expect(r.links.length, 1);
      expect(r.links.first.findings.any((f) => f.code == 'hidden_chars'), isFalse);
    });
  });

  group('الروابط', () {
    NormalizedUrl n(String s) => UrlNormalizer.normalize(s);

    test('RLM في مسار الرابط: مش تمويه', () {
      final r = n('https://example.org/a${cp(0x200F)}b');
      expect(r.invisibleRemoved, 0);
      expect(r.directionMarksRemoved, 1);
      expect(r.path, '/ab');
    });

    test('LRM في الاستعلام: مش تمويه', () {
      final r = n('https://example.org/?q=1${cp(0x200E)}2');
      expect(r.invisibleRemoved, 0);
      expect(r.directionMarksRemoved, 1);
    });

    test('LRM جوه اسم الموقع: تمويه', () {
      final r = n('https://exa${cp(0x200E)}mple.org/');
      expect(r.invisibleRemoved, 1);
      expect(r.invisibleKinds, [0x200E]);
      expect(r.host, 'example.org');
    });

    test('RLM في بيانات الدخول قبل @: تمويه', () {
      final r = n('https://user${cp(0x200F)}:pw@example.org/');
      expect(r.invisibleRemoved, 1);
    });

    test('ZWSP في المسار تمويه (مش من علامات الاتجاه)', () {
      final r = n('https://example.org/lo${cp(0x200B)}gin');
      expect(r.invisibleRemoved, 1);
      expect(r.directionMarksRemoved, 0);
    });

    test('RLM في الأطراف بتتشال بدون تعليم', () {
      final r = n('${cp(0x200F)}https://example.org/${cp(0x200F)}');
      expect(r.invisibleRemoved, 0);
      expect(r.directionMarksRemoved, 0);
    });

    test('المحلل: RLM في المسار لا يضيف hidden_chars ولا نقاط', () {
      final r = UrlAnalyzer.analyze('https://example.org/a${cp(0x200F)}b');
      expect(r.findings.any((f) => f.code == 'hidden_chars'), isFalse);
      expect(r.score, 0);
      expect(r.findings.any((f) => f.code == 'direction_marks'), isTrue);
    });

    test('المحلل: حرف صفري جوه الاسم يطلّع hidden_chars بالحرف الفعلي', () {
      final r = UrlAnalyzer.analyze('https://exa${cp(0x200B)}mple.org/');
      final f = r.findings.firstWhere((f) => f.code == 'hidden_chars');
      expect(f.points, greaterThan(0));
      expect(f.detail, contains('U+200B'));
    });
  });
}
