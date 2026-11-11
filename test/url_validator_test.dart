import 'package:cobra_shield/core/models.dart';
import 'package:cobra_shield/services/url_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

// التحقق من المدخل كرابط ويب قبل أي تحليل.
//
// القاعدة: نص مش رابط (not-a-url، https://) = "إدخال غير صالح": مفيش درجة خطر ومفيش
// "مشبوه" ومفيش "لا مؤشرات". والروابط الحقيقية (حتى المموّهة) بتتحلل وبتاخد درجة.
//
// القيم المتوقعة اتتبّعت يدويًا على الكود؛ أول تشغيل فعلي في الـ CI.
void main() {
  ScanResult run(String s) => UrlAnalyzer.analyze(s);

  group('مدخلات مرفوضة (غير صالحة)', () {
    const cases = <String, String>{
      '': 'empty',
      '   ': 'empty',
      'not-a-url': 'not_a_url',
      'https://': 'incomplete_url',
      'http://': 'incomplete_url',
      'ftp://example.com/file': 'unsupported_scheme',
      'mailto:someone@example.com': 'unsupported_scheme',
      'http://a.com:99999': 'invalid_port',
      'http://exa<mple.com': 'invalid_host',
      'http://[::1': 'invalid_host',
      'http://256.256.256.256/': 'invalid_host',
      'http://example.123': 'invalid_host',
      'http://localhost/': 'non_public_host',
      'http://router/': 'non_public_host',
      'http://a..com/': 'invalid_host',
      'file.txt': 'not_a_url',
    };
    cases.forEach((input, code) {
      test('"$input" -> $code', () {
        final r = run(input);
        expect(r.state, ScanState.invalidInput);
        expect(r.issueCode, code);
        expect(r.hasScore, isFalse);
        expect(r.verdict, Verdict.invalidInput);
        // مفيش حكم "آمن/مشبوه": الدرجة 0 مجرد قيمة افتراضية ومش بتتعرض.
        expect(r.findings.length, 1);
        expect(r.findings.first.code, 'invalid_input_$code');
      });
    });

    test('جزء أطول من 63 حرف أو اسم أطول من 253: غير صالح', () {
      expect(run('http://${'a' * 64}.com/').issueCode, 'invalid_host');
      final longHost = List<String>.filled(30, 'abcdefghi').join('.');
      expect(longHost.length, greaterThan(253));
      expect(run('http://$longHost.com/').issueCode, 'invalid_host');
    });

    test('كلمة واحدة مع منفذ (localhost:3000) مش بتتقبل كرابط عام', () {
      expect(run('localhost:3000/x').state, ScanState.invalidInput);
    });

    test('نص عادي (جملة) مش رابط', () {
      expect(run('hello').state, ScanState.invalidInput);
    });

    test('الإدخال الغلط ما بيتحوّلش لنتيجة آمنة بأي شكل', () {
      for (final s in <String>['not-a-url', 'https://', 'file.txt']) {
        final r = run(s);
        expect(r.verdict, isNot(Verdict.noIndicators), reason: s);
        expect(r.level, isNot(RiskLevel.critical), reason: s);
        expect(r.partial, isFalse, reason: s);
      }
    });
  });

  group('مدخلات صالحة (بتتحلل وبتاخد درجة)', () {
    const valid = <String>[
      'https://example.com',
      'http://example.com/',
      'example.com/login',
      'www.google.com',
      'EXAMPLE.COM',
      'bit.ly/abc',
      'https://8.8.8.8/',
      'http://[2001:db8::1]/',
      'http://127.0.0.1/',
      'https://example.com:8443/x',
      'example.com:8080/path',
      'https://example.com./',
      'https://xn--mnchen-3ya.de/',
      'https://user@example.com/',
    ];
    for (final s in valid) {
      test(s, () {
        final r = run(s);
        expect(r.state, isNot(ScanState.invalidInput), reason: '${r.issueCode}');
        expect(r.hasScore, isTrue);
      });
    }

    test('عنوان داخلي (127.0.0.1) صالح كمدخل بس بيتعلّم', () {
      final r = run('http://127.0.0.1/');
      expect(r.state, ScanState.completed);
      expect(r.findings.any((f) => f.code == 'ip_host'), isTrue);
      expect(r.findings.any((f) => f.code == 'ip_internal'), isTrue);
    });
  });

  group('تمويه متعمّد = رابط حقيقي بيتحلل (مش إدخال غلط)', () {
    const tricks = <String>[
      'https://paypal.com∕evil.com/login',
      'https://evil.com\\@google.com/x',
      'http://exa%0Ample.com/',
    ];
    for (final s in tricks) {
      test(s, () {
        final r = run(s);
        expect(r.state, ScanState.completed, reason: '${r.issueCode}');
        expect(r.level, isNot(RiskLevel.low));
      });
    }
  });

  group('بروتوكولات خطيرة بتتحلل كخطر (مش "غير مدعوم")', () {
    for (final s in <String>['javascript:alert(1)', 'data:text/html,<script>alert(1)</script>']) {
      test(s, () {
        final r = run(s);
        expect(r.state, ScanState.completed);
        expect(r.level, RiskLevel.critical);
      });
    }
  });
}
