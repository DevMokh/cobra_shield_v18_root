import 'package:flutter_test/flutter_test.dart';

import 'package:cobra_shield/core/models.dart';
import 'package:cobra_shield/services/message_analyzer.dart';

void main() {
  group('استخراج الروابط', () {
    test('رابط كامل بنقطة في آخر الجملة', () {
      final l = MessageAnalyzer.extractLinks(
          'عاجل: اضغط http://nbe-secure-login.top/verify.');
      expect(l, ['http://nbe-secure-login.top/verify']);
    });

    test('رابط مختصر من غير http', () {
      final l = MessageAnalyzer.extractLinks('مبروك! اضغط هنا: bit.ly/3xYz12 الآن');
      expect(l, ['bit.ly/3xYz12']);
    });

    test('إيميل مش رابط', () {
      expect(MessageAnalyzer.extractLinks('راسلنا على info@example.com للدعم'),
          isEmpty);
    });

    test('مفيش روابط', () {
      expect(MessageAnalyzer.extractLinks('لا يوجد رابط هنا'), isEmpty);
    });
  });

  group('تحليل الرسائل', () {
    test('رسالة نصب واضحة: جائزة + استعجال + رابط مشبوه', () {
      final r = MessageAnalyzer.analyze(
          'مبروك! فزت بجائزة كبيرة. اضغط الآن خلال 24 ساعة وادفع الرسوم '
          'http://win-prize-now.top/claim');
      expect(r.level, isNot(RiskLevel.low), reason: 'score=${r.score}');
    });

    test('رسالة عادية', () {
      final r = MessageAnalyzer.analyze('هنتقابل الساعة خمسة في الكافيه');
      expect(r.level, RiskLevel.low, reason: 'score=${r.score}');
    });
  });

  group('الفحص الجزئي (حدود الطول والروابط)', () {
    bool hasTitle(ScanResult r, String part) =>
        r.findings.any((f) => f.title.contains(part));

    test('رسالة طويلة جدًا: تحذير إن الباقي ما اتفحصش', () {
      final r = MessageAnalyzer.analyze('مرحبا ' * 1200);
      expect(hasTitle(r, 'الرسالة طويلة'), isTrue);
    });

    test('رسالة عادية: مفيش تحذير حدود', () {
      final r = MessageAnalyzer.analyze('هنتقابل الساعة خمسة في الكافيه');
      expect(hasTitle(r, 'الرسالة طويلة'), isFalse);
      expect(hasTitle(r, 'روابط أكتر'), isFalse);
    });

    test('أكتر من 8 روابط: تحذير، والمفحوص 8 بس', () {
      final text = List<String>.generate(10, (i) => 'https://site$i.example.com/p').join(' ');
      final r = MessageAnalyzer.analyze(text);
      expect(r.links.length, MessageAnalyzer.maxLinks);
      expect(hasTitle(r, 'روابط أكتر'), isTrue);
    });

    test('8 روابط بالظبط: مفيش تحذير', () {
      final text = List<String>.generate(8, (i) => 'https://site$i.example.com/p').join(' ');
      final r = MessageAnalyzer.analyze(text);
      expect(r.links.length, 8);
      expect(hasTitle(r, 'روابط أكتر'), isFalse);
    });
  });

  // -------------------------------------------------------------------
  // 1.11: تكافؤ عربي/إنجليزي، منع الحساب المزدوج، تقليل الإنذارات الكاذبة
  // (القيم المتوقعة اتحسبت يدويًا من kSignals والأوزان؛ أول تشغيل فعلي في الـ CI)
  // -------------------------------------------------------------------

  Set<String> msgCodes(ScanResult r) => r.findings
      .map((f) => f.code)
      .where((c) => c.startsWith('msg_'))
      .toSet();
  int count(ScanResult r, String code) =>
      r.findings.where((f) => f.code == code).length;

  group('تكافؤ العربي والإنجليزي والمختلط', () {
    test('تهديد + تحقق + استعجال: نفس الإشارات ونفس الدرجة بالعربي والإنجليزي', () {
      final ar = MessageAnalyzer.analyze('تم إيقاف حسابك. تحقق من حسابك فورًا');
      final en = MessageAnalyzer.analyze(
          'Your account has been suspended. Verify your account immediately.');
      const want = <String>{'msg_threat', 'msg_verify', 'msg_urgency'};
      expect(msgCodes(ar), want);
      expect(msgCodes(en), want);
      expect(ar.score, 40);
      expect(en.score, 40);
      expect(ar.level, RiskLevel.medium);
      expect(en.level, RiskLevel.medium);
    });

    test('نص مختلط: المفهوم بيتحسب مرة واحدة (مفيش حساب مزدوج)', () {
      final r = MessageAnalyzer.analyze(
          'Your account has been suspended - تم إيقاف حسابك');
      expect(count(r, 'msg_threat'), 1);
      expect(msgCodes(r), <String>{'msg_threat'});
      expect(r.score, 16);
    });

    test('تكرار نفس المفهوم بعبارات كتير = إشارة واحدة', () {
      final r = MessageAnalyzer.analyze(
          'urgent urgent act now immediately asap right away');
      expect(count(r, 'msg_urgency'), 1);
      expect(r.score, 12);
      final ar = MessageAnalyzer.analyze('فورا عاجل في الحال');
      expect(count(ar, 'msg_urgency'), 1);
      expect(ar.score, 12);
    });

    test('كلمات عامة (login / bank / invoice) إشارات ضعيفة: نفس الدرجة بالعربي والإنجليزي ومش "مشبوه"', () {
      final en = MessageAnalyzer.analyze(
          'Please login to your bank account to view your invoice');
      final ar = MessageAnalyzer.analyze(
          'من فضلك سجل الدخول إلى حساب البنك لعرض الفاتورة');
      const want = <String>{'msg_cta', 'msg_authority', 'msg_payment'};
      expect(msgCodes(en), want);
      expect(msgCodes(ar), want);
      expect(en.score, 10);
      expect(ar.score, 10);
      expect(en.level, RiskLevel.low);
      expect(ar.level, RiskLevel.low);
      expect(en.verdict, Verdict.noIndicators);
      expect(ar.verdict, Verdict.noIndicators);
    });

    test('طلب كود التحقق: نفس الإشارة بالعربي والإنجليزي', () {
      final en = MessageAnalyzer.analyze(
          'Please send me the verification code you received');
      final ar = MessageAnalyzer.analyze('ابعتلي كود التحقق اللي وصلك');
      expect(msgCodes(en), <String>{'msg_secret_request'});
      expect(msgCodes(ar), <String>{'msg_secret_request'});
      expect(en.score, 28);
      expect(ar.score, 28);
      expect(en.level, RiskLevel.medium);
    });
  });

  group('رسائل الأكواد الرسمية: لا إنذار كاذب', () {
    test('كود تحقق + "لا تشارك" (إنجليزي): مجرد ذكر بدون طلب', () {
      final r = MessageAnalyzer.analyze(
          'Your verification code is 482913. Do not share this code with anyone.');
      expect(r.score, 0);
      expect(r.findings.any((f) => f.code == 'msg_secret_request'), isFalse);
      expect(r.findings.any((f) => f.code == 'msg_secret_mention'), isTrue);
      expect(r.verdict, Verdict.noIndicators);
    });

    test('كود تحقق + "لا تشارك" (عربي)', () {
      final r = MessageAnalyzer.analyze(
          'كود التحقق الخاص بك 482913. لا تشارك هذا الكود مع أحد');
      expect(r.score, 0);
      expect(r.findings.any((f) => f.code == 'msg_secret_request'), isFalse);
      expect(r.verdict, Verdict.noIndicators);
    });

    test('جملة تحذير فيها المصطلح الحساس نفسه: مش طلب، وبتظهر علامة إيجابية', () {
      for (final t in <String>[
        'Never share your password. We will never ask for your password.',
        'لا تشارك كلمة المرور مع أي شخص. لن نطلب منك كلمة المرور أبدا',
      ]) {
        final r = MessageAnalyzer.analyze(t);
        expect(r.findings.any((f) => f.code == 'msg_secret_request'), isFalse, reason: t);
        expect(r.findings.any((f) => f.code == 'msg_secret_warning'), isTrue, reason: t);
        expect(r.score, 0, reason: t);
      }
    });

    test('"اكتب/Enter" لوحده مش طلب (بدون رابط مشبوه)', () {
      final r = MessageAnalyzer.analyze('Enter your password to continue');
      expect(r.findings.any((f) => f.code == 'msg_secret_request'), isFalse);
      expect(r.score, 0);
    });

    test('"Enter" مع رابط مشبوه = طلب بيانات + ضغط نفسي', () {
      final r = MessageAnalyzer.analyze(
          'Enter your password at http://secure-login.example.top/x');
      expect(r.findings.any((f) => f.code == 'msg_secret_request'), isTrue);
      expect(r.findings.any((f) => f.code == 'msg_link_pressure'), isTrue);
      expect(r.level, isNot(RiskLevel.low), reason: 'score=${r.score}');
    });
  });

  group('الروابط داخل الرسائل', () {
    test('رابط ببوابة رسمية: مفيش "ضغط نفسي"، والتهديد بيتحسب من النص', () {
      final r = MessageAnalyzer.analyze(
          'Urgent: your account will be suspended. Log in at https://www.paypal.com/myaccount');
      expect(r.findings.any((f) => f.code == 'msg_link_pressure'), isFalse);
      expect(msgCodes(r), containsAll(<String>{'msg_urgency', 'msg_threat'}));
      expect(r.score, 31);
    });

    test('رابط تقليد + استعجال وتهديد: خطير على الأقل', () {
      final r = MessageAnalyzer.analyze(
          'Urgent: your account will be suspended. Log in at https://secure-paypa1.top/login');
      expect(r.findings.any((f) => f.code == 'msg_link_pressure'), isTrue);
      expect(r.level.index, greaterThanOrEqualTo(RiskLevel.high.index),
          reason: 'score=${r.score}');
    });

    test('رابط بإشارات ضعيفة فقط ومن غير ضغط: لا يخلّي الرسالة مشبوهة', () {
      final r = MessageAnalyzer.analyze('see http://example.xyz/ tomorrow at five');
      expect(r.level, RiskLevel.low, reason: 'score=${r.score}');
      expect(r.findings.any((f) => f.code == 'msg_link_pressure'), isFalse);
      expect(r.verdict, Verdict.noIndicators);
    });

    test('علامة اتجاه (RLM) في آخر الرابط بتتشال من الرابط', () {
      expect(MessageAnalyzer.extractLinks('ادخل على bit.ly/3xYz12\u200F'),
          <String>['bit.ly/3xYz12']);
    });
  });

  group('علامات الاتجاه (LRM/RLM) والحروف الخفية في الرسائل', () {
    const invisibleCodes = <String>{
      'bidi_override',
      'bidi_unbalanced',
      'zero_width_split',
      'tag_chars',
      'control_chars',
      'format_controls',
    };

    test('LRM/RLM طبيعية في نص عربي مختلط: مش تهديد ومفيش تحذير', () {
      final r = MessageAnalyzer.analyze(
          'مرحبا\u200F كيف حالك\u200E؟ هنتقابل الساعة خمسة في الكافيه');
      expect(r.findings.where((f) => invisibleCodes.contains(f.code)), isEmpty);
      expect(r.score, 0);
      expect(r.verdict, Verdict.noIndicators);
    });

    test('LRM جوه كلمة مفتاحية ما بتخفيهاش عن المطابقة', () {
      // الكلمة الوحيدة المطابقة هنا هي "urgent" بعد ما LRM بيقطّعها: لازم تتلقط.
      final r = MessageAnalyzer.analyze('this is an ur\u200Egent matter please');
      expect(count(r, 'msg_urgency'), 1);
    });

    test('ZWSP وسط كلمة (pay[ZWSP]pal) = تحذير حقيقي بسببه الفعلي', () {
      final r = MessageAnalyzer.analyze('Please verify at pay\u200Bpal today');
      final f = r.findings.where((x) => x.code == 'zero_width_split');
      expect(f, isNotEmpty);
      expect(f.first.points, greaterThan(0));
      expect(f.first.title, contains('U+200B'));
    });

    test('RLO (U+202E) = خطر حقيقي', () {
      final r = MessageAnalyzer.analyze('open file\u202Efdp.exe now please');
      expect(r.findings.any((f) => f.code == 'bidi_override'), isTrue);
      expect(r.level, isNot(RiskLevel.low), reason: 'score=${r.score}');
    });
  });

  group('حالات الفحص (غير صالح / غير كافٍ / جزئي)', () {
    test('رسالة فاضية = إدخال غير صالح (مش "لا مؤشرات")', () {
      final r = MessageAnalyzer.analyze('   ');
      expect(r.state, ScanState.invalidInput);
      expect(r.issueCode, 'empty');
      expect(r.verdict, Verdict.invalidInput);
      expect(r.hasScore, isFalse);
    });

    test('كلمة واحدة بدون روابط = معلومات غير كافية (مش "لا مؤشرات")', () {
      final r = MessageAnalyzer.analyze('مرحبا');
      expect(r.insufficientInfo, isTrue);
      expect(r.verdict, Verdict.insufficient);
      expect(r.hasScore, isTrue);
    });

    test('نص جاي من OCR ناقص: فحص جزئي بسبب ظاهر', () {
      final r = MessageAnalyzer.analyze(
        'هنتقابل الساعة خمسة في الكافيه',
        partialReason: 'قراءة النص العربي غير متاحة',
      );
      expect(r.partial, isTrue);
      expect(r.verdict, Verdict.partialScan);
      expect(r.findings.any((f) => f.code == 'msg_input_partial'), isTrue);
    });
  });
}
