import 'package:cobra_shield/core/psl_data.dart';
import 'package:cobra_shield/services/public_suffix.dart';
import 'package:cobra_shield/services/url_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

// اختبارات Public Suffix List.
//
// المتجهات الرسمية (checkPublicSuffix) منسوخة من ملف الاختبار الرسمي للقائمة
// (publicsuffix/list: tests/test_psl.txt، مرخّص Public Domain / CC0) بنفس نسخة اللقطة
// المضمّنة (2025-12-28، تطابق kPslSnapshotDate). كل قيمة متوقعة هنا = الدومين المسجّل (registrable domain)،
// و null = المدخل نفسه لاحقة عامة أو غير صالح.
//
// تنبيه: التحقق من إن الخوارزمية تعطي هذه النتائج على البيانات المضمّنة اتعمل في بيئة التطوير
// بنسخة Python من نفس الخوارزمية (77 من 77)؛ تشغيل Dart الفعلي لسه مستني الـ CI.
void main() {
  String? registrable(String host) {
    final m = PublicSuffixList.instance.lookup(host);
    if (m == null || !m.hasRegistrable) return null;
    return m.registrableDomain;
  }

  group('المتجهات الرسمية (labels بصيغة Unicode)', () {
    const vectors = <List<String?>>[
      <String?>['COM', null],
      <String?>['example.COM', 'example.com'],
      <String?>['WwW.example.COM', 'example.com'],
      <String?>['.com', null],
      <String?>['.example', null],
      <String?>['.example.com', null],
      <String?>['.example.example', null],
      <String?>['example', null],
      <String?>['example.example', 'example.example'],
      <String?>['b.example.example', 'example.example'],
      <String?>['a.b.example.example', 'example.example'],
      <String?>['biz', null],
      <String?>['domain.biz', 'domain.biz'],
      <String?>['b.domain.biz', 'domain.biz'],
      <String?>['a.b.domain.biz', 'domain.biz'],
      <String?>['com', null],
      <String?>['example.com', 'example.com'],
      <String?>['b.example.com', 'example.com'],
      <String?>['a.b.example.com', 'example.com'],
      <String?>['uk.com', null],
      <String?>['example.uk.com', 'example.uk.com'],
      <String?>['b.example.uk.com', 'example.uk.com'],
      <String?>['a.b.example.uk.com', 'example.uk.com'],
      <String?>['test.ac', 'test.ac'],
      <String?>['mm', null],
      <String?>['c.mm', null],
      <String?>['b.c.mm', 'b.c.mm'],
      <String?>['a.b.c.mm', 'b.c.mm'],
      <String?>['jp', null],
      <String?>['test.jp', 'test.jp'],
      <String?>['www.test.jp', 'test.jp'],
      <String?>['ac.jp', null],
      <String?>['test.ac.jp', 'test.ac.jp'],
      <String?>['www.test.ac.jp', 'test.ac.jp'],
      <String?>['kyoto.jp', null],
      <String?>['test.kyoto.jp', 'test.kyoto.jp'],
      <String?>['ide.kyoto.jp', null],
      <String?>['b.ide.kyoto.jp', 'b.ide.kyoto.jp'],
      <String?>['a.b.ide.kyoto.jp', 'b.ide.kyoto.jp'],
      <String?>['c.kobe.jp', null],
      <String?>['b.c.kobe.jp', 'b.c.kobe.jp'],
      <String?>['a.b.c.kobe.jp', 'b.c.kobe.jp'],
      <String?>['city.kobe.jp', 'city.kobe.jp'],
      <String?>['www.city.kobe.jp', 'city.kobe.jp'],
      <String?>['ck', null],
      <String?>['test.ck', null],
      <String?>['b.test.ck', 'b.test.ck'],
      <String?>['a.b.test.ck', 'b.test.ck'],
      <String?>['www.ck', 'www.ck'],
      <String?>['www.www.ck', 'www.ck'],
      <String?>['us', null],
      <String?>['test.us', 'test.us'],
      <String?>['www.test.us', 'test.us'],
      <String?>['ak.us', null],
      <String?>['test.ak.us', 'test.ak.us'],
      <String?>['www.test.ak.us', 'test.ak.us'],
      <String?>['k12.ak.us', null],
      <String?>['test.k12.ak.us', 'test.k12.ak.us'],
      <String?>['www.test.k12.ak.us', 'test.k12.ak.us'],
      <String?>['食狮.com.cn', '食狮.com.cn'],
      <String?>['食狮.公司.cn', '食狮.公司.cn'],
      <String?>['www.食狮.公司.cn', '食狮.公司.cn'],
      <String?>['shishi.公司.cn', 'shishi.公司.cn'],
      <String?>['公司.cn', null],
      <String?>['食狮.中国', '食狮.中国'],
      <String?>['www.食狮.中国', '食狮.中国'],
      <String?>['shishi.中国', 'shishi.中国'],
      <String?>['中国', null],
    ];
    for (final v in vectors) {
      test('${v[0]} -> ${v[1]}', () {
        expect(registrable(v[0]!), v[1]);
      });
    }
  });

  group('المتجهات الرسمية بصيغة Punycode (عبر UrlAnalyzer.registrableDomain)', () {
    const vectors = <List<String?>>[
      <String?>['xn--85x722f.com.cn', 'xn--85x722f.com.cn'],
      <String?>['xn--85x722f.xn--55qx5d.cn', 'xn--85x722f.xn--55qx5d.cn'],
      <String?>['www.xn--85x722f.xn--55qx5d.cn', 'xn--85x722f.xn--55qx5d.cn'],
      <String?>['shishi.xn--55qx5d.cn', 'shishi.xn--55qx5d.cn'],
      <String?>['xn--55qx5d.cn', null],
      <String?>['xn--85x722f.xn--fiqs8s', 'xn--85x722f.xn--fiqs8s'],
      <String?>['www.xn--85x722f.xn--fiqs8s', 'xn--85x722f.xn--fiqs8s'],
      <String?>['shishi.xn--fiqs8s', 'shishi.xn--fiqs8s'],
      <String?>['xn--fiqs8s', null],
    ];
    for (final v in vectors) {
      test('${v[0]} -> ${v[1]}', () {
        final got = UrlAnalyzer.registrableDomain(v[0]!);
        // الدالة بترجّع المضيف نفسه لو مفيش دومين مسجّل (لاحقة عامة).
        expect(got, v[1] ?? v[0]!.toLowerCase());
      });
    }
  });

  group('حالات إضافية (قسم PRIVATE، دومينات مصرية، تمويه)', () {
    test('github.io من قسم PRIVATE: دومين المستخدم هو الدومين المسجّل', () {
      expect(registrable('evil.github.io'), 'evil.github.io');
      final m = PublicSuffixList.instance.lookup('evil.github.io')!;
      expect(m.privateSection, isTrue);
      expect(m.publicSuffix, 'github.io');
      // لو تجاهلنا قسم PRIVATE بترجع github.io نفسه.
      final icann = PublicSuffixList.instance.lookup('evil.github.io', includePrivate: false)!;
      expect(icann.registrableDomain, 'github.io');
    });

    test('مضيف مثل www.amazon.co.uk و nbe.com.eg', () {
      expect(registrable('www.amazon.co.uk'), 'amazon.co.uk');
      expect(registrable('nbe.com.eg'), 'nbe.com.eg');
      expect(registrable('www.nbe.com.eg'), 'nbe.com.eg');
      expect(registrable('sub.example.com.au'), 'example.com.au');
    });

    test('التمويه بدومين رسمي كدومين فرعي: الدومين المسجّل هو الأخير', () {
      expect(registrable('paypal.com.evil.xyz'), 'evil.xyz');
      expect(registrable('login.paypal.com.account-verify.top'), 'account-verify.top');
      expect(UrlAnalyzer.registrableDomain('paypal.com.evil.xyz'), 'evil.xyz');
    });

    test('عنوان IP: الدالة بترجّعه كما هو', () {
      expect(UrlAnalyzer.registrableDomain('192.168.1.1'), '192.168.1.1');
      expect(UrlAnalyzer.registrableDomain('::1'), '::1');
    });

    test('نقطة في الآخر (FQDN) بتتشال', () {
      expect(registrable('example.com.'), 'example.com');
      expect(UrlAnalyzer.registrableDomain('www.example.com.'), 'example.com');
    });

    test('مضيف غير صالح: null (فاضي / نقطة في الأول / جزء فاضي)', () {
      expect(PublicSuffixList.instance.lookup(''), isNull);
      expect(PublicSuffixList.instance.lookup('.example.com'), isNull);
      expect(PublicSuffixList.instance.lookup('a..com'), isNull);
    });

    test('امتداد غير معروف: القاعدة الافتراضية (listed=false) وisKnownTld=false', () {
      final m = PublicSuffixList.instance.lookup('foo.example')!;
      expect(m.listed, isFalse);
      expect(PublicSuffixList.instance.isKnownTld('example'), isFalse);
      expect(PublicSuffixList.instance.isKnownTld('com'), isTrue);
      expect(PublicSuffixList.instance.isKnownTld('COM'), isTrue);
    });

    test('اللقطة المضمّنة فيها آلاف القواعد وتاريخها معروف', () {
      expect(PublicSuffixList.instance.ruleCount, greaterThan(9000));
      expect(kPslSnapshotDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });

    test('الاستثناء والـ wildcard: www.ck دومين مسجّل و test.ck لاحقة', () {
      expect(registrable('www.ck'), 'www.ck');
      expect(registrable('test.ck'), isNull);
      expect(registrable('b.test.ck'), 'b.test.ck');
    });
  });
}
