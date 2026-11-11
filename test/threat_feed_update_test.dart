import 'dart:async';
import 'dart:io';

import 'package:cobra_shield/services/http_util.dart';
import 'package:cobra_shield/services/threat_feed.dart';
import 'package:flutter_test/flutter_test.dart';

const String _good = '''
https://evil-login.example.net/verify?id=1
http://bad.test-site.xyz/a/b/
https://another.phish.top/path
''';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cobra_feed_test');
  });

  tearDown(() async {
    httpOverride = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ThreatFeed newFeed() => ThreatFeed.forTest(dirProvider: () async => dir);
  File feedFile() => File('${dir.path}/cobra_openphish.txt');

  void respond(HttpResult Function() make) {
    httpOverride = (String method, Uri uri, {Map<String, String>? headers, String? body}) async {
      expect(method, 'GET');
      expect(uri.scheme, 'https');
      return make();
    };
  }

  Future<FeedUpdateReport> updateWith(ThreatFeed f, String body, {int status = 200, bool truncated = false}) {
    respond(() => HttpResult(status, body, truncated: truncated));
    return f.update();
  }

  test('تحديث ناجح: تقرير كامل، يحمّل ويحفظ الملف ومفيش ملف مؤقت متبقي', () async {
    final f = newFeed();
    final rep = await updateWith(f, _good);
    expect(rep.status, FeedUpdateStatus.updated);
    expect(rep.ok, isTrue);
    expect(rep.downloaded, isTrue);
    expect(rep.persisted, isTrue);
    expect(rep.changed, isTrue);
    expect(rep.countBefore, 0);
    expect(rep.countAfter, 3);
    expect(rep.delta, 3);
    expect(rep.source, ThreatFeed.feedUrl);
    expect(rep.error, isNull);
    expect(f.count, 3);
    expect(f.lastError, isNull);
    expect(f.lastReport, same(rep));
    expect(f.updated, isNotNull);
    expect(f.memoryOnly, isFalse);
    expect(f.busy, isFalse);
    expect(await feedFile().exists(), isTrue);
    expect(await File('${dir.path}/cobra_openphish.txt.tmp').exists(), isFalse);
    expect((await feedFile().readAsString()).trim().split('\n').length, 3);
    expect(rep.summary, contains('0 ← 3'));
  });

  test('نفس المحتوى: unchanged، العدد قبل = بعد، وبرضو محفوظ', () async {
    final f = newFeed();
    await updateWith(f, _good);
    final rep = await updateWith(f, _good);
    expect(rep.status, FeedUpdateStatus.unchanged);
    expect(rep.ok, isTrue);
    expect(rep.changed, isFalse);
    expect(rep.countBefore, 3);
    expect(rep.countAfter, 3);
    expect(rep.persisted, isTrue);
  });

  test('عدد مختلف: updated وdelta صحيح (زيادة ونقصان بسيط)', () async {
    final f = newFeed();
    await updateWith(f, _good);
    final more = '$_good\nhttps://new-one.example.org/login\n';
    var rep = await updateWith(f, more);
    expect(rep.status, FeedUpdateStatus.updated);
    expect(rep.changed, isTrue);
    expect(rep.countBefore, 3);
    expect(rep.countAfter, 4);
    expect(rep.delta, 1);
    expect(f.match('https://new-one.example.org/login')?.kind, 'exact');
    // نقصان (القاعدة صغيرة أقل من حد المقارنة، فبيتقبل)
    rep = await updateWith(f, _good);
    expect(rep.status, FeedUpdateStatus.updated);
    expect(rep.delta, -1);
    expect(f.count, 3);
  });

  test('نفس العدد لكن محتوى مختلف = changed', () async {
    final f = newFeed();
    await updateWith(f, _good);
    const swapped = '''
https://evil-login.example.net/verify?id=1
http://bad.test-site.xyz/a/b/
https://different.phish.top/path
''';
    final rep = await updateWith(f, swapped);
    expect(rep.countBefore, rep.countAfter);
    expect(rep.changed, isTrue);
    expect(rep.status, FeedUpdateStatus.updated);
  });

  test('instance جديدة (إعادة تشغيل) تقرأ الملف المحفوظ ووقت آخر تحديث من الميتاداتا', () async {
    final first = newFeed();
    final rep = await updateWith(first, _good);
    expect(rep.persisted, isTrue);
    final again = newFeed();
    expect(again.count, 0);
    await again.load();
    expect(again.count, 3);
    expect(again.memoryOnly, isFalse);
    expect(again.match('https://evil-login.example.net/verify?id=1')?.kind, 'exact');
    expect(again.updated, isNotNull);
    // وقت الميتاداتا (بالميلي ثانية) = وقت التحديث الناجح
    expect(again.updated!.millisecondsSinceEpoch, rep.time.millisecondsSinceEpoch);
    expect(await File('${dir.path}/cobra_openphish.meta.json').exists(), isTrue);
  });

  test('رد غير 200: failed، القاعدة والملف القديمين بيفضلوا زي ما هما', () async {
    final f = newFeed();
    await updateWith(f, _good);
    final before = await feedFile().readAsString();
    final rep = await updateWith(f, '', status: 503);
    expect(rep.status, FeedUpdateStatus.failed);
    expect(rep.ok, isFalse);
    expect(rep.downloaded, isFalse);
    expect(rep.error, contains('503'));
    expect(rep.countBefore, 3);
    expect(rep.countAfter, 3);
    expect(rep.summary, contains('لسه شغالة'));
    expect(f.lastError, contains('503'));
    expect(f.count, 3);
    expect(await feedFile().readAsString(), before);
  });

  test('رد مقطوع (truncated) يترفض ومبيلمسش القاعدة', () async {
    final f = newFeed();
    await updateWith(f, _good);
    final before = await feedFile().readAsString();
    final rep = await updateWith(f, 'https://a.example.org/x\n', truncated: true);
    expect(rep.status, FeedUpdateStatus.rejected);
    expect(f.count, 3);
    expect(await feedFile().readAsString(), before);
  });

  test('رد فاضي أو معطوب (HTML / ثنائي) يترفض ومبيمسحش القاعدة', () async {
    final f = newFeed();
    await updateWith(f, _good);
    final before = await feedFile().readAsString();
    for (final bad in <String>[
      '',
      '<html><body>Error</body></html>',
      '\u0000\u0001\u0002 binary garbage\nnot urls\n???\n',
    ]) {
      final rep = await updateWith(f, bad);
      expect(rep.status, FeedUpdateStatus.rejected, reason: bad);
      expect(rep.ok, isFalse);
      expect(f.count, 3);
      expect(await feedFile().readAsString(), before);
    }
  });

  test('خلاصة أصغر بكتير من القاعدة الكبيرة الحالية تترفض', () async {
    final f = newFeed();
    final big = List<String>.generate(300, (i) => 'https://phish$i.example.org/p').join('\n');
    var rep = await updateWith(f, big);
    expect(rep.status, FeedUpdateStatus.updated);
    expect(f.count, 300);
    rep = await updateWith(f, 'https://only-one.example.org/x\n');
    expect(rep.status, FeedUpdateStatus.rejected);
    expect(rep.countAfter, 300);
    expect(f.count, 300);
  });

  test('أخطاء الشبكة بتتحول لرسالة ومبتكسرش القاعدة', () async {
    final f = newFeed();
    await updateWith(f, _good);

    httpOverride = (String m, Uri u, {Map<String, String>? headers, String? body}) async =>
        throw const SocketException('no route');
    var rep = await f.update();
    expect(rep.status, FeedUpdateStatus.failed);
    expect(f.lastError, 'لا يوجد اتصال بالإنترنت');

    httpOverride = (String m, Uri u, {Map<String, String>? headers, String? body}) async =>
        throw TimeoutException('slow');
    rep = await f.update();
    expect(f.lastError, 'انتهت المهلة');
    expect(f.count, 3);
  });

  group('فشل الحفظ الدائم', () {
    test('التنزيل نجح لكن الحفظ فشل: مش "نجاح"، التقرير يقول كده والقاعدة تتطبق في الذاكرة', () async {
      // نخلّي مجلد التخزين مسار ملف عادي (مينفعش يتعمل كمجلد) => الكتابة بتفشل.
      final blocker = File('${dir.path}/not_a_dir');
      await blocker.writeAsString('x');
      final f = ThreatFeed.forTest(
        dirProvider: () async => Directory('${blocker.path}/sub'),
      );
      final rep = await updateWith(f, _good);
      expect(rep.status, FeedUpdateStatus.updatedNotSaved);
      expect(rep.ok, isFalse);
      expect(rep.downloaded, isTrue);
      expect(rep.persisted, isFalse);
      expect(rep.error, contains('تعذّر حفظها'));
      expect(f.memoryOnly, isTrue);
      expect(f.count, 3);
      expect(f.updated, isNull); // مفيش "آخر تحديث ناجح محفوظ"
    });

    test('فشل الحفظ بيسيب الملف القديم المحفوظ سليم', () async {
      final f = newFeed();
      await updateWith(f, _good);
      final before = await feedFile().readAsString();
      // نكسر الكتابة: ملف مؤقت اسمه مجلد => writeAsString بتفشل.
      await Directory('${dir.path}/cobra_openphish.txt.tmp').create();
      final rep = await updateWith(f, '$_good\nhttps://x.example.org/y\n');
      expect(rep.status, FeedUpdateStatus.updatedNotSaved);
      expect(rep.persisted, isFalse);
      expect(await feedFile().readAsString(), before);
    });
  });

  test('ملف محفوظ تالف يتجاهل عند التحميل', () async {
    await feedFile().writeAsString('<<<garbage>>>\nnot urls\n');
    final f = newFeed();
    await f.load();
    expect(f.count, 0);
  });

  test('httpRequest يرفض أي رابط غير https', () async {
    expect(
      () => httpRequest('GET', Uri.parse('http://example.com/feed.txt')),
      throwsA(isA<ArgumentError>()),
    );
  });
}
