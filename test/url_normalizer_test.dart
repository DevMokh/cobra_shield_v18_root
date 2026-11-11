import 'package:flutter_test/flutter_test.dart';

import 'package:cobra_shield/services/url_confusables.dart';
import 'package:cobra_shield/services/url_normalizer.dart';

// اختبارات المطبّع: فك الترميز المتكرر، الحروف الخفية، إصلاح البروتوكول،
// صيغ الـ IP، punycode، والتقسيم الخام (userinfo / host / path).
// القيم المتوقعة لـ punycode مأخوذة من كودك Python القياسي ('..'.encode('punycode')).
void main() {
  NormalizedUrl n(String s) => UrlNormalizer.normalize(s);

  group('فك الترميز', () {
    test('جولة واحدة وUTF-8', () {
      expect(UrlNormalizer.percentDecode('%C3%A9'), 'é');
      expect(UrlNormalizer.percentDecode('%252F'), '%2F');
    });
    test('تسلسلات غير صالحة تفضل زي ما هي', () {
      expect(UrlNormalizer.percentDecode('100%'), '100%');
      expect(UrlNormalizer.percentDecode('%FF%41'), '%FFA');
      expect(UrlNormalizer.percentDecode('%zz'), '%zz');
    });
    test('ترميز مزدوج في المسار (%252F -> /)', () {
      final r = n('https://evil.com/%252F..%252Fadmin');
      expect(r.path, '//../admin');
      expect(r.encodingRounds, 2);
      expect(r.host, 'evil.com');
    });
    test('ترميز متعدد المستويات له سقف', () {
      final r = n('https://a.com/x%${'25' * 6}2fy');
      expect(r.encodingRounds, UrlNormalizer.maxDecodeRounds);
      expect(r.valid, isTrue);
    });
    test('الاستعلام المتداخل بيتفك', () {
      final r = n('https://example.com/?u=https%3A%2F%2Fevil.com%2F');
      expect(r.query, 'u=https://evil.com/');
      expect(r.encodingRounds, 1);
    });
    test('أول فك الترميز ثم التقسيم خطر: نقسّم الأول', () {
      // المتصفح فعليًا رايح لـ evil.com (الجزء قبل @ هو userinfo)
      final r = n('https://paypal.com%2F@evil.com/login');
      expect(r.host, 'evil.com');
      expect(r.userInfo, 'paypal.com/');
      expect(r.atCount, 1);
    });
    test('مضيف مرمّز', () {
      final r = n('https://evil%252Ecom/');
      expect(r.host, 'evil.com');
      expect(r.hostEncoded, isTrue);
      expect(r.encodingRounds, 2);
    });
    test('فاصل مخبّأ في المضيف بالترميز', () {
      final r = n('https://evil.com%2Fpaypal.com');
      expect(r.hostDelimiterTrick, isTrue);
      expect(r.valid, isFalse);
    });
  });

  group('حروف خفية', () {
    test('صفر العرض داخل المضيف', () {
      final r = n('https://goo\u200Bgle.com/a');
      expect(r.host, 'google.com');
      expect(r.invisibleRemoved, 1);
    });
    test('الأطراف بتتنضف بدون تعليم', () {
      final r = n('  \u200Ehttps://example.com/x\n');
      expect(r.invisibleRemoved, 0);
      expect(r.host, 'example.com');
    });
    test('سطر جديد داخلي (المتصفح بيشيله)', () {
      final r = n('https://exa\nmple.com');
      expect(r.host, 'example.com');
      expect(r.invisibleRemoved, 1);
    });
    test('%0A بيتحول لسطر ويتشال', () {
      final r = n('https://exa%0Ample.com');
      expect(r.host, 'example.com');
      expect(r.invisibleRemoved, 1);
      expect(r.hostEncoded, isTrue);
    });

    // علامات الاتجاه (LRM U+200E / RLM U+200F / ALM U+061C): طبيعية في المسار والاستعلام
    // (نص عربي مختلط)، وتمويه لو جوه اسم الموقع أو بيانات الدخول.
    test('LRM في المسار: علامة طبيعية، مش حرف خفي', () {
      final r = n('https://example.com/a\u200Eb');
      expect(r.host, 'example.com');
      expect(r.invisibleRemoved, 0);
      expect(r.directionMarksRemoved, 1);
      expect(r.invisibleKinds, isEmpty);
    });
    test('RLM و ALM في الاستعلام: برضه علامات طبيعية', () {
      final r = n('https://example.com/?q=a\u200Fb\u061Cc');
      expect(r.invisibleRemoved, 0);
      expect(r.directionMarksRemoved, 2);
    });
    test('علامة اتجاه مشفّرة (%E2%80%8E) في المسار: طبيعية برضه', () {
      final r = n('https://example.com/a%E2%80%8Eb');
      expect(r.invisibleRemoved, 0);
      expect(r.directionMarksRemoved, 1);
    });
    test('LRM جوه اسم الموقع: تمويه (بتتعد وبتتسجّل بنوعها الحقيقي)', () {
      final r = n('https://exam\u200Eple.com/');
      expect(r.host, 'example.com');
      expect(r.invisibleRemoved, 1);
      expect(r.directionMarksRemoved, 0);
      expect(r.invisibleKinds, <int>[0x200E]);
    });
    test('RLM جوه اسم الموقع مشفّرة: تمويه برضه', () {
      final r = n('https://exam%E2%80%8Fple.com/');
      expect(r.host, 'example.com');
      expect(r.invisibleRemoved, 1);
      expect(r.invisibleKinds, <int>[0x200F]);
    });
    test('LRM جوه بيانات الدخول (قبل @): تمويه', () {
      final r = n('https://us\u200Eer@example.com/');
      expect(r.host, 'example.com');
      expect(r.invisibleRemoved, 1);
      expect(r.directionMarksRemoved, 0);
    });
    test('RLO (U+202E) في المسار: مش علامة طبيعية، بتتحسب تمويه', () {
      final r = n('https://example.com/a\u202Eb');
      expect(r.invisibleRemoved, 1);
      expect(r.directionMarksRemoved, 0);
      expect(r.invisibleKinds, <int>[0x202E]);
    });
    test('ZWSP في المسار: تمويه', () {
      final r = n('https://example.com/a\u200Bb');
      expect(r.invisibleRemoved, 1);
      expect(r.invisibleKinds, <int>[0x200B]);
    });
    test('علامات اتجاه في أول النص وآخره: بتتشال بدون تعليم', () {
      final r = n('\u200Fhttps://example.com/x\u200E');
      expect(r.invisibleRemoved, 0);
      expect(r.directionMarksRemoved, 0);
      expect(r.host, 'example.com');
    });
  });

  group('البروتوكول والمسافات', () {
    test('defang', () {
      final r = n('hxxps://evil[.]com/login');
      expect(r.scheme, 'https');
      expect(r.host, 'evil.com');
      expect(r.defanged, isTrue);
    });
    test('http:/ و http:\\\\ و https// بتتصلّح وتتعلّم', () {
      for (final u in <String>[
        'http:/example.com',
        'http:\\\\example.com',
        'https//example.com',
      ]) {
        final r = n(u);
        expect(r.host, 'example.com', reason: u);
        expect(r.schemeMalformed, isTrue, reason: u);
      }
    });
    test('بدون بروتوكول: https مفترض وبدون تعليم تمويه', () {
      final r = n('example.com/a');
      expect(r.scheme, 'https');
      expect(r.schemeAssumed, isTrue);
      expect(r.schemeMalformed, isFalse);
      expect(r.host, 'example.com');
    });
    test('//host و host:port', () {
      expect(n('//example.com/a').host, 'example.com');
      final r = n('example.com:8080/x');
      expect(r.host, 'example.com');
      expect(r.port, 8080);
      expect(r.scheme, 'https');
    });
    test('مسافة داخل المضيف بتتشال وتتعلّم', () {
      final r = n('https://exa mple.com/x');
      expect(r.host, 'example.com');
      expect(r.spaceInAuthority, isTrue);
    });
    test('مسافة في المسار بتتحول %20 في رابط الاتصال', () {
      expect(n('https://example.com/a b').fetchUrl, 'https://example.com/a%20b');
    });
    test('شرطة معكوسة', () {
      final r = n('https://example.com\\path');
      expect(r.host, 'example.com');
      expect(r.backslashInAuthority, isTrue);
      expect(r.path, '/path');
    });
    test('اختلاف قراءة المتصفح وأدوات RFC', () {
      final r = n('https://evil.com\\@google.com/x');
      expect(r.host, 'evil.com');
      expect(r.rfcHost, 'google.com');
      final ok = n('https://example.com\\path');
      expect(ok.rfcHost, '');
    });
    test('أنواع خطيرة حتى لو مموّهة', () {
      expect(n('javascript:alert(1)').dangerousScheme, 'javascript');
      expect(n('java\nscript:alert(1)').dangerousScheme, 'javascript');
      expect(n('JaVaScRiPt:alert(1)').dangerousScheme, 'javascript');
      expect(n('javascript%3Aalert(1)').dangerousScheme, 'javascript');
      expect(n('https://x.com/?q=javascript%3A').dangerousScheme, '');
      expect(n('database.com:8080/x').dangerousScheme, '');
    });
  });

  group('التقسيم', () {
    test('كل الأجزاء', () {
      final r = n('https://user:pw@example.com:8443/p?q=1#f');
      expect(r.userInfo, 'user:pw');
      expect(r.host, 'example.com');
      expect(r.port, 8443);
      expect(r.path, '/p');
      expect(r.query, 'q=1');
      expect(r.fragment, 'f');
      expect(r.valid, isTrue);
    });
    test('حروف كبيرة ونقطة أخيرة', () {
      final r = n('https://www.EXAMPLE.com./Path');
      expect(r.host, 'www.example.com');
      expect(r.path, '/Path');
    });
    test('@ في الاستعلام أو المسار مش userinfo', () {
      expect(n('https://example.com?x=a@b').userInfo, '');
      final m = n('https://medium.com/@x/why-paypal-won');
      expect(m.host, 'medium.com');
      expect(m.userInfo, '');
    });
    test('أخطاء الشكل ما بترميش استثناء', () {
      expect(n('   ').errors, <String>['empty']);
      expect(n('https://').errors, <String>['no_host']);
      expect(n('https://a.com:99999').errors, <String>['bad_port']);
      expect(n('https://a.com:/x').port, isNull);
      expect(n('https://a.com:/x').valid, isTrue);
      expect(n('http://[::1').valid, isFalse);
      expect(n('https://exa<mple.com').valid, isFalse);
    });
    test('نص طويل جدًا بيتقطع', () {
      final r = n('https://${'a' * 5000}.com');
      expect(r.truncated, isTrue);
    });
    test('إيموجي في المسار', () {
      expect(n('https://a.com/\u{1F600}').path, '/\u{1F600}');
    });
    test('المسارات العربية بتفضل', () {
      final r = n('https://ar.wikipedia.org/wiki/مصر');
      expect(r.host, 'ar.wikipedia.org');
      expect(r.unicodeHost, r.host);
    });
  });

  group('IPv4', () {
    void ip(String host, String canonical, IpForm form, {List<String>? radix}) {
      final r = UrlNormalizer.parseIpv4(host);
      expect(r, isNotNull, reason: host);
      expect(r!.canonical, canonical, reason: host);
      expect(r.form, form, reason: host);
      if (radix != null) expect(r.radixes, radix, reason: host);
    }

    test('الصيغ المختلفة لنفس العنوان', () {
      ip('127.0.0.1', '127.0.0.1', IpForm.standard);
      ip('0x7f000001', '127.0.0.1', IpForm.dword, radix: <String>['hex']);
      ip('3232235777', '192.168.1.1', IpForm.dword, radix: <String>[]);
      ip('0177.0.0.1', '127.0.0.1', IpForm.radix, radix: <String>['octal']);
      ip('0x7f.0.0.1', '127.0.0.1', IpForm.radix, radix: <String>['hex']);
      ip('0x7f.0.0.01', '127.0.0.1', IpForm.radix, radix: <String>['hex', 'octal']);
      ip('127.1', '127.0.0.1', IpForm.short);
      ip('10.1.258', '10.1.1.2', IpForm.short);
      ip('017700000001', '127.0.0.1', IpForm.dword, radix: <String>['octal']);
      ip('010.010.010.010', '8.8.8.8', IpForm.radix, radix: <String>['octal']);
      ip('4294967295', '255.255.255.255', IpForm.dword);
      ip('127.0.0.1.', '127.0.0.1', IpForm.standard);
    });
    test('غير صالح', () {
      for (final h in <String>[
        '256.1.1.1',
        '08.1.1.1',
        '4294967296',
        '1.2.3.4.5',
        '1..2',
        'abc',
      ]) {
        expect(UrlNormalizer.parseIpv4(h), isNull, reason: h);
      }
    });
    test('تصنيف العنوان', () {
      expect(UrlNormalizer.parseIpv4('127.0.0.1')!.kind, 'loopback');
      expect(UrlNormalizer.parseIpv4('192.168.1.1')!.kind, 'private');
      expect(UrlNormalizer.parseIpv4('10.0.0.1')!.kind, 'private');
      expect(UrlNormalizer.parseIpv4('172.16.0.1')!.kind, 'private');
      expect(UrlNormalizer.parseIpv4('172.32.0.1')!.kind, 'public');
      expect(UrlNormalizer.parseIpv4('169.254.169.254')!.kind, 'linklocal');
      expect(UrlNormalizer.parseIpv4('8.8.8.8')!.kind, 'public');
    });
    test('داخل رابط كامل', () {
      final r = n('http://0x7f000001/login');
      expect(r.host, '127.0.0.1');
      expect(r.hostAsWritten, '0x7f000001');
      expect(r.ip!.obfuscated, isTrue);
      expect(r.fetchUrl, 'http://127.0.0.1/login');
    });
    test('رقم قصير كمضيف = IP، ورقم بعد نقطة = غير صالح', () {
      expect(n('http://12345/').host, '0.0.48.57');
      final bad = n('http://example.123/');
      expect(bad.valid, isFalse);
      expect(bad.errors, <String>['bad_numeric_host']);
    });
  });

  group('IPv6', () {
    test('صالح', () {
      expect(UrlNormalizer.parseIpv6('::1')!.kind, 'loopback');
      expect(UrlNormalizer.parseIpv6('::')!.kind, 'unspecified');
      expect(UrlNormalizer.parseIpv6('2001:db8:0:0:0:0:0:1')!.kind, 'public');
      expect(UrlNormalizer.parseIpv6('fe80::1')!.kind, 'linklocal');
      expect(UrlNormalizer.parseIpv6('fd00::1')!.kind, 'private');
      expect(UrlNormalizer.parseIpv6('::ffff:127.0.0.1')!.kind, 'loopback');
    });
    test('غير صالح', () {
      expect(UrlNormalizer.parseIpv6('1:2:3'), isNull);
      expect(UrlNormalizer.parseIpv6('1::2::3'), isNull);
      expect(UrlNormalizer.parseIpv6('12345::1'), isNull);
      expect(UrlNormalizer.parseIpv6('::1%eth0'), isNull);
    });
    test('داخل رابط', () {
      final r = n('http://[::1]:8080/');
      expect(r.host, '::1');
      expect(r.port, 8080);
      expect(r.cleanUrl, 'http://[::1]:8080/');
    });
  });

  group('Punycode والحروف المتشابهة', () {
    test('فك punycode (قيم من Python)', () {
      expect(UrlNormalizer.decodePunycode('mnchen-3ya'), 'münchen');
      expect(UrlNormalizer.decodePunycode('bcher-kva'), 'bücher');
      expect(UrlNormalizer.decodePunycode('e1afmkfd'), 'пример');
      expect(UrlNormalizer.decodePunycode('80ak6aa92e'), 'аррӏе');
      expect(UrlNormalizer.decodePunycode('mgbaam7a8h'), 'امارات');
      expect(UrlNormalizer.decodePunycode('wgv71a119e'), '日本語');
    });
    test('مدخل غير صالح', () {
      expect(UrlNormalizer.decodePunycode('!!'), isNull);
      expect(UrlNormalizer.decodePunycode(''), isNull);
    });
    test('xn-- في مضيف', () {
      final r = n('https://xn--80ak6aa92e.com');
      expect(r.host, 'xn--80ak6aa92e.com');
      expect(r.unicodeHost, 'аррӏе.com');
      expect(r.skeletonHost, 'apple.com');
      expect(r.badPunycode, isFalse);
    });
    test('xn-- مش بيفك لحروف غير ASCII = غير صالح', () {
      expect(n('https://xn--zzzz-.com').badPunycode, isTrue);
    });
    test('سيريلي مخلوط', () {
      final r = n('https://аpple.com/id');
      expect(r.skeletonHost, 'apple.com');
      expect(Confusables.scanLabel('аpple').mixedScript, isTrue);
    });
    test('ليبل كله سيريلي متشابه', () {
      final s = Confusables.scanLabel('аррӏе');
      expect(s.wholeLookalike, isTrue);
      expect(s.mixedScript, isFalse);
      expect(s.skeleton, 'apple');
    });
    test('عربي وصيني مش تقليد', () {
      for (final l in <String>['مصر', '例え']) {
        final s = Confusables.scanLabel(l);
        expect(s.lookalikes, 0, reason: l);
        expect(s.wholeLookalike, isFalse, reason: l);
        expect(s.mixedScript, isFalse, reason: l);
      }
    });
    test('تشكيل لاتيني', () {
      expect(Confusables.scanLabel('paypàl').skeleton, 'paypal');
      final s = Confusables.scanLabel('münchen');
      expect(s.skeleton, 'munchen');
      expect(s.mixedScript, isFalse);
    });
    test('حروف عريضة ومزخرفة بتتحول زي المتصفح', () {
      const full = 'ｐａｙｐａｌ'; // ｐａｙｐａｌ
      const bold = '\u{1D429}\u{1D41A}\u{1D432}\u{1D429}\u{1D41A}\u{1D425}'; // 𝐩𝐚𝐲𝐩𝐚𝐥
      for (final h in <String>[full, bold]) {
        final r = n('https://$h.com');
        expect(r.host, 'paypal.com');
        expect(r.compatFolded, isTrue);
      }
    });
    test('نقطة ideographic ليست تمويه حروف', () {
      final r = n('https://example。com');
      expect(r.host, 'example.com');
      expect(r.compatFolded, isFalse);
    });
    test('رمز يشبه الشرطة المائلة', () {
      final r = n('https://paypal.com∕evil.com');
      expect(r.valid, isTrue);
      expect(r.skeletonHost, 'paypal.com/evil.com');
      expect(Confusables.scanLabel('com∕evil').separatorLookalikes, 1);
    });
  });

  group('الرابط النظيف', () {
    test('cleanUrl متفكوك وfetchUrl سليم البنية', () {
      final r = n('https://example.com/a%2Fb?x=%41');
      expect(r.cleanUrl, 'https://example.com/a/b?x=A');
      expect(r.fetchUrl, 'https://example.com/a%2Fb?x=%41');
    });
    test('رابط مش صالح: fetchUrl فاضي', () {
      final r = n('https://exa<mple.com');
      expect(r.fetchUrl, '');
    });
  });
}
