import 'package:flutter_test/flutter_test.dart';

import 'package:cobra_shield/core/models.dart';
import 'package:cobra_shield/services/url_analyzer.dart';
import 'package:cobra_shield/services/url_report.dart';

// اختبارات المحلل: روابط معروفة بأنها احتيال لازم تتصنف "متوسط" أو أعلى،
// وروابط سليمة معروفة لازم تفضل "منخفض". لو غيرت القواعد وفشل اختبار،
// يبقى التعديل كسر حالة قديمة.
//
// ملاحظة معايرة (1.11): الإشارات الضعيفة (HTTP، امتداد شائع في الاحتيال، شرطات، طول، كلمات
// عادية) مجموعها محدود بـ kWeakFamilyCap (12) أقل من حد "مشبوه" (20)، فرابط بإشارات ضعيفة
// بس مبقاش "مشبوه". ده تقليل إنذارات كاذبة مقصود؛ الروابط دي بتتعرض "لا مؤشرات واضحة"
// (مع تنبيه إنها مش آمنة بالضرورة) وبتتغطى بقاعدة OpenPhish/Safe Browsing وتحليل الرسالة.
void main() {
  group('روابط مشبوهة', () {
    const suspicious = <String>[
    'https://evil-site.com/paypal/login',
    'https://xkqzrtvbnmpl.top/a',
    'https://a8392kd04x1zq.com/verify',
    'http://vodafone-egypt.update-line.xyz',
    'https://paypal.com.account-verify.xyz/login',
    'https://paypa1.com/signin',
    'https://secure-amazon.eg.login-check.com/ap/signin',
    'https://www.arnazon.com/orders',
    'https://sites.google.com/view/bank-login-update',
    'https://mail.google.com@evil-login.com/inbox',
    'http://nbe-secure-login.top/verify',
    'https://google.pw/login',
    'https://аpple.com/id',
    'https://dhl-parcel-redelivery.top/pay',
    'https://noon-verify-account.xyz/login',
    ];
    for (final u in suspicious) {
      test(u, () {
        final r = UrlAnalyzer.analyze(u);
        expect(r.level, isNot(RiskLevel.low), reason: 'score=${r.score}');
      });
    }
  });

  group('روابط سليمة', () {
    const legit = <String>[
    'https://www.bbc.com/news/facebook-account-changes',
    'https://www.theguardian.com/technology/amazon-prime-day',
    'https://medium.com/@x/why-paypal-won',
    'https://ar.wikipedia.org/wiki/مصر',
    'https://www.amazon.eg/gp/help/customer/display.html',
    'https://support.apple.com/ar-eg',
    'https://www.google.com',
    'https://www.google.de/search?q=x',
    'https://amazon.co.uk/orders',
    'https://apple-pie-recipes.com/best',
    'https://orange-juice-shop.com',
    'https://accounts.google.com/signin/v2',
    'https://www.paypal.com/myaccount/summary',
    'https://www.facebook.com/login',
    'https://www.microsoft.com/en-us/security',
    'https://news.ycombinator.com/item?id=1',
    'https://stackoverflow.com/questions/1',
    'https://dhl.de/track',
    'https://www.noon.com/egypt-ar/',
    'https://zoom.us/j/123',
    ];
    for (final u in legit) {
      test(u, () {
        final r = UrlAnalyzer.analyze(u);
        expect(r.level, RiskLevel.low, reason: 'score=${r.score}');
      });
    }
  });

  group('إشارات ضعيفة فقط: مش "مشبوه" (ومش "آمن" برضه)', () {
    const weakOnly = <String>[
      'http://win-prize-now.top/claim',
      'http://parcel-fee-check.click/pay',
      'https://traffic-pay.top/fine',
      'http://example.xyz/',
    ];
    for (final u in weakOnly) {
      test(u, () {
        final r = UrlAnalyzer.analyze(u);
        expect(r.hasScore, isTrue);
        expect(r.level, RiskLevel.low, reason: 'score=${r.score}');
        expect(r.score, lessThanOrEqualTo(kWeakFamilyCap));
        // لا يُقال "آمن": الحكم "لا مؤشرات واضحة" ومعاه تنبيه إنه مش ضمان.
        expect(r.verdict, Verdict.noIndicators);
        expect(Verdict.noIndicators.advice, contains('لا يعني أنه آمن'));
        // السبب ظاهر للمستخدم (مش درجة مجهولة المصدر).
        expect(r.findings.any((f) => f.code == 'risky_tld'), isTrue);
      });
    }

    test('الإشارات الضعيفة المتراكمة بتتقصّ عند السقف (rawScore أعلى من score)', () {
      // http (3) + امتداد .top (5) + دومين فرعي متعدد (3) + شرطات (3) = 14 > سقف 12
      final rep = UrlAnalyzer.report('http://a-b-c-d.x.y.top/');
      expect(rep.rawScore, 14);
      expect(rep.score, kWeakFamilyCap);
      expect(rep.level, RiskLevel.low);
      expect(rep.tier, ThreatTier.safe);
    });

    test('إشارة ضعيفة + إشارة قوية = المجموع بيتحسب (الضعيفة ما بتلغيش القوية)', () {
      // دومين عشوائي (15 قوية) + .top (5 ضعيفة) = 20 = حد "مشبوه"
      final r = UrlAnalyzer.analyze('https://xkqzrtvbnmpl.top/a');
      expect(r.score, 20);
      expect(r.level, RiskLevel.medium);
    });
  });

  group('علامات الاتجاه (LRM/RLM) في الروابط: السبب الحقيقي بيظهر', () {
    test('LRM/RLM طبيعية في المسار: مش تهديد (درجة 0) وبتتعرض كمعلومة', () {
      final r = UrlAnalyzer.analyze('https://example.com/a\u200Eb\u200F');
      expect(r.score, 0);
      expect(r.level, RiskLevel.low);
      expect(r.findings.any((f) => f.code == 'hidden_chars'), isFalse);
      final info = r.findings.where((f) => f.code == 'direction_marks');
      expect(info, isNotEmpty);
      expect(info.first.points, 0);
    });

    test('LRM جوه اسم الموقع: تمويه (+20) وبيذكر الحرف بالكود', () {
      final r = UrlAnalyzer.analyze('https://exam\u200Eple.com/');
      final hid = r.findings.where((f) => f.code == 'hidden_chars');
      expect(hid, isNotEmpty);
      expect(hid.first.points, 20);
      expect(hid.first.detail, contains('U+200E'));
      expect(r.level, RiskLevel.medium);
    });

    test('RLO في المسار: بيذكر U+202E ومش بيتعامل معاه كعلامة طبيعية', () {
      final r = UrlAnalyzer.analyze('https://example.com/a\u202Eb');
      final hid = r.findings.where((f) => f.code == 'hidden_chars');
      expect(hid, isNotEmpty);
      expect(hid.first.detail, contains('U+202E'));
    });

    test('نص العرض ما بيتغيّرش: الرابط الأصلي محفوظ كما هو', () {
      final rep = UrlAnalyzer.report('https://example.com/a\u200Eb');
      expect(rep.input, 'https://example.com/a\u200Eb');
    });
  });

  test('رابط جافاسكربت خطير', () {
    final r = UrlAnalyzer.analyze('javascript:alert(1)');
    expect(r.level, isNot(RiskLevel.low));
  });

  test('نص فاضي: إدخال غير صالح (مش درجة 0 ولا "لا مؤشرات")', () {
    final r = UrlAnalyzer.analyze('   ');
    expect(r.state, ScanState.invalidInput);
    expect(r.issueCode, 'empty');
    expect(r.hasScore, isFalse);
    expect(r.verdict, Verdict.invalidInput);
  });

  // -------------------------------------------------------------------
  // محرك التطبيع وكشف التمويه (v1.10)
  // -------------------------------------------------------------------

  group('تمويه وتهرّب (لازم يبان)', () {
    // [الرابط، أقل مستوى مقبول]
    final evasive = <List<Object>>[
      <Object>['http://0x7f000001/login', RiskLevel.high],
      <Object>['http://3232235777/', RiskLevel.high],
      <Object>['http://0177.0.0.1/', RiskLevel.high],
      // عنوان داخلي (loopback) = IP مباشر (30) + داخلي (10) + HTTP (3) = 43 → "مشبوه".
      // مش "خطير" عمدًا: روابط الراوتر/الشبكة المحلية (192.168.x.x) شائعة وسليمة غالبًا.
      <Object>['http://[::1]/admin', RiskLevel.medium],
      <Object>['https://8.8.8.8/login', RiskLevel.medium],
      <Object>['http://user:pass@192.168.1.1/admin', RiskLevel.critical],
      <Object>['https://paypal.com%2F@evil.com/login', RiskLevel.high],
      <Object>['https://evil.com\\@google.com/x', RiskLevel.medium],
      <Object>['https://@evil.com', RiskLevel.medium],
      <Object>['https://goo\u200Bgle.com/login', RiskLevel.medium],
      // حرف تحكم مشفّر داخل اسم الموقع: حروف خفية (20) + اسم موقع مرمّز (20) + HTTP (3).
      <Object>['http://exa%0Ample.com/', RiskLevel.medium],
      <Object>['https://xn--80ak6aa92e.com', RiskLevel.high],
      <Object>['https://аррӏе.com', RiskLevel.high],
      <Object>['https://paypàl.com/login', RiskLevel.critical],
      <Object>['hxxps://paypal-login[.]xyz/verify', RiskLevel.high],
      <Object>['https://paypal.com∕evil.com/login', RiskLevel.critical],
      <Object>['javascript:alert(1)', RiskLevel.critical],
      <Object>['java\nscript:alert(1)', RiskLevel.critical],
      <Object>['JaVaScRiPt:alert(1)', RiskLevel.critical],
      <Object>['javascript%3Aalert(1)', RiskLevel.critical],
    ];
    for (final e in evasive) {
      final u = e[0] as String;
      final min = e[1] as RiskLevel;
      test(u.replaceAll('\n', r'\n'), () {
        final r = UrlAnalyzer.analyze(u);
        expect(r.level.index, greaterThanOrEqualTo(min.index),
            reason: 'score=${r.score} ${r.findings.map((f) => f.code).toList()}');
        expect(r.findings.any((f) => f.code == 'analysis_failed'), isFalse);
      });
    }
  });

  group('روابط دولية سليمة (لا إنذار)', () {
    const legitIdn = <String>[
      'https://münchen.de/',
      'https://مصر.eg/',
      'https://www.google.com/url?q=https%3A%2F%2Fexample.com%2F',
      'https://ar.wikipedia.org/wiki/%D9%85%D8%B5%D8%B1',
    ];
    for (final u in legitIdn) {
      test(u, () {
        final r = UrlAnalyzer.analyze(u);
        expect(r.level, RiskLevel.low, reason: 'score=${r.score}');
        expect(r.findings.any((f) => f.code == 'analysis_failed'), isFalse);
      });
    }
  });

  test('الفشل الداخلي مش بيتحسب آمن: كل الأمثلة القديمة بدون analysis_failed', () {
    const all = <String>[
      'https://www.google.com',
      'https://evil-site.com/paypal/login',
      'https://аpple.com/id',
      'https://mail.google.com@evil-login.com/inbox',
    ];
    for (final u in all) {
      expect(UrlAnalyzer.analyze(u).findings.any((f) => f.code == 'analysis_failed'),
          isFalse,
          reason: u);
    }
  });

  group('أوزان المحرك', () {
    int w(String url, String code) {
      final r = UrlAnalyzer.analyze(url);
      final hits = r.findings.where((f) => f.code == code).toList();
      expect(hits, isNotEmpty, reason: '$url -> ${r.findings.map((f) => f.code).toList()}');
      return hits.first.points;
    }

    test('IP مباشر +30', () => expect(w('https://8.8.8.8/', 'ip_host'), 30));
    test('IP مموّه +35', () => expect(w('https://0x08080808/', 'ip_obfuscated'), 35));
    test('@ +35', () => expect(w('https://a@evil.com/', 'userinfo_at'), 35));
    test('Homograph +25', () => expect(w('https://аpple.com/', 'homograph'), 25));
    test('مستويات فرعية كثيرة +15', () {
      expect(w('https://a.b.c.d.e.evil.com/', 'many_subdomains'), 15);
    });
    test('كلمات حساسة كثيرة +15', () {
      expect(w('https://evil.com/login/verify/account/update', 'keyword_stuffing'), 15);
    });
  });

  group('التقرير المنظم', () {
    test('بنية التقرير', () {
      final rep = UrlAnalyzer.report('http://0x7f000001/login');
      expect(rep.tier, ThreatTier.dangerous);
      expect(rep.cleanUrl, 'http://127.0.0.1/login');
      expect(rep.valid, isTrue);
      expect(rep.score, lessThanOrEqualTo(100));
      expect(rep.rawScore, greaterThanOrEqualTo(rep.score));
      final f = rep.flags.firstWhere((x) => x.code == 'ip_obfuscated');
      expect(f.weight, 35);
      expect(f.explanation, contains('127.0.0.1'));
      expect(f.title, isNotEmpty);
    });

    test('JSON', () {
      final j = UrlAnalyzer.report('https://paypal.com%2F@evil.com/login').toJson();
      expect(j['tier'], 'dangerous');
      expect(j['clean_url'], contains('evil.com'));
      final flags = j['flags'] as List<Object?>;
      expect(flags, isNotEmpty);
      final first = flags.first as Map<String, Object?>;
      expect(first.keys, containsAll(<String>['code', 'severity', 'title', 'explanation', 'weight']));
    });

    test('رابط مكسور: إدخال غير صالح (بدون درجة ولا tier) وما بيرميش استثناء', () {
      const cases = <String, String>{
        'https://': 'incomplete_url',
        'http://exa<mple.com': 'invalid_host',
        'http://a.com:99999': 'invalid_port',
        'http://[::1': 'invalid_host',
      };
      cases.forEach((u, code) {
        final rep = UrlAnalyzer.report(u);
        expect(rep.valid, isFalse, reason: u);
        expect(rep.status, ScanState.invalidInput, reason: u);
        expect(rep.issueCode, code, reason: u);
        expect(rep.tier, isNull, reason: u);
        expect(rep.level, isNull, reason: u);
        expect(rep.score, 0, reason: u);
        expect(rep.flags.any((x) => x.code == 'invalid_input_$code'), isTrue, reason: u);
      });
    });

    test('رابط نضيف: safe بدون إشارات تحذير', () {
      final rep = UrlAnalyzer.report('https://www.google.com');
      expect(rep.tier, ThreatTier.safe);
      expect(rep.flags.where((x) => x.weight > 0), isEmpty);
    });

    test('النص الفاضي: إدخال غير صالح بدون tier', () {
      final rep = UrlAnalyzer.report('   ');
      expect(rep.status, ScanState.invalidInput);
      expect(rep.issueCode, 'empty');
      expect(rep.tier, isNull);
      expect(rep.score, 0);
    });

    test('رابط ضخم بيتقطع ويتعلّم partial', () {
      final rep = UrlAnalyzer.report('https://example.com/${'a' * 6000}');
      expect(rep.partial, isTrue);
    });
  });
}
