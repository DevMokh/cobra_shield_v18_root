import 'package:cobra_shield/services/threat_feed.dart';
import 'package:flutter_test/flutter_test.dart';

const String _good = '''
# OpenPhish test feed
https://evil-login.example.net/verify?id=1
http://bad.test-site.xyz/a/b/

HTTPS://Another.Phish.TOP/path#frag
''';

void main() {
  group('ThreatFeed.parse', () {
    test('يطبّع الروابط ويتجاهل التعليقات والأسطر الفاضية', () {
      final p = ThreatFeed.parse(_good);
      expect(p.validLines, 3);
      expect(p.rejectedLines, 0);
      expect(p.urls, <String>{
        'evil-login.example.net/verify?id=1',
        'bad.test-site.xyz/a/b',
        'another.phish.top/path',
      });
      expect(p.hosts, <String>{
        'evil-login.example.net',
        'bad.test-site.xyz',
        'another.phish.top',
      });
    });

    test('يرفض الأسطر اللي مش روابط http(s)', () {
      final p = ThreatFeed.parse('$_good\nnot a url line\nftp://x.example.org/a\n');
      expect(p.validLines, 3);
      expect(p.rejectedLines, 2);
    });
  });

  group('ThreatFeed.validate', () {
    test('خلاصة سليمة تتقبل', () {
      expect(ThreatFeed.validate(ThreatFeed.parse(_good), previousCount: 0), isNull);
    });

    test('فاضية أو صفحة HTML أو أغلبها أسطر غير صالحة تترفض', () {
      expect(ThreatFeed.validate(ThreatFeed.parse(''), previousCount: 0), isNotNull);
      expect(
        ThreatFeed.validate(
          ThreatFeed.parse('<html>\n<body>Error</body>\n</html>\n'),
          previousCount: 0,
        ),
        isNotNull,
      );
      // 3 صالح + 1 غير صالح = 75% (أقل من 80%)
      expect(
        ThreatFeed.validate(ThreatFeed.parse('$_good\nnot a url line\n'), previousCount: 0),
        isNotNull,
      );
    });

    test('خلاصة أصغر بكتير من القاعدة الحالية الكبيرة تترفض', () {
      final p = ThreatFeed.parse(_good);
      expect(ThreatFeed.validate(p, previousCount: 1000), isNotNull);
      // القاعدة الحالية صغيرة (أقل من الحد): مفيش مقارنة
      expect(ThreatFeed.validate(p, previousCount: 10), isNull);
    });
  });

  group('ThreatFeed.applyBody / match', () {
    test('تطابق كامل ومضيف ودومين', () {
      final f = ThreatFeed.instance;
      expect(f.applyBody(_good), isNull);
      expect(f.count, 3);
      expect(f.match('https://evil-login.example.net/verify?id=1')?.kind, 'exact');
      expect(f.match('https://evil-login.example.net/other')?.kind, 'host');
      expect(f.match('https://sub.example.net/')?.kind, 'domain');
      expect(f.match('https://unrelated.example.org/'), isNull);
    });

    test('تحديث فاشل لا يمسح القاعدة القديمة', () {
      final f = ThreatFeed.instance;
      expect(f.applyBody(_good), isNull);
      expect(f.applyBody('<html>error</html>'), isNotNull);
      expect(f.applyBody(''), isNotNull);
      expect(f.count, 3);
      expect(f.match('https://evil-login.example.net/verify?id=1')?.kind, 'exact');
    });
  });
}
