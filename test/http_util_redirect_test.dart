import 'dart:async';
import 'dart:io';

import 'package:cobra_shield/services/http_util.dart';
import 'package:cobra_shield/services/net_guard.dart';
import 'package:flutter_test/flutter_test.dart';

// اختبار مسار httpRequest الحقيقي (مش الـ override) على خادم https محلي بشهادة اختبار:
// التحويلات بتتفحص يدويًا ومبتتبعش لـ http أو وجهة داخلية أو user@.
// (اتكتب من غير تشغيل في بيئة التعديل؛ محتاج Flutter SDK. انظر test/fixtures/README.md.)
void main() {
  late HttpServer server;
  var hits = 0;
  late FutureOr<void> Function(HttpRequest req) handler;

  setUp(() async {
    NetGuard.allowLoopbackForTesting = true;
    httpSecurityContextForTesting = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates('test/fixtures/test_cert.pem');
    hits = 0;
    final ctx = SecurityContext()
      ..useCertificateChain('test/fixtures/test_cert.pem')
      ..usePrivateKey('test/fixtures/test_key.pem');
    server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
    server.listen((req) async {
      hits++;
      await handler(req);
    });
  });

  tearDown(() async {
    NetGuard.allowLoopbackForTesting = false;
    httpSecurityContextForTesting = null;
    await server.close(force: true);
  });

  Uri url([String path = '/']) => Uri.parse('https://localhost:${server.port}$path');

  Future<void> redirect(HttpRequest req, String to, {int code = 302}) async {
    req.response.statusCode = code;
    req.response.headers.set(HttpHeaders.locationHeader, to);
    await req.response.close();
  }

  test('200 عادي: بيرجّع الجسم', () async {
    handler = (req) async {
      req.response.statusCode = 200;
      req.response.write('hello');
      await req.response.close();
    };
    final r = await httpRequest('GET', url());
    expect(r.status, 200);
    expect(r.body, 'hello');
    expect(r.truncated, isFalse);
  });

  test('تحويلة https عادية بتتتبع', () async {
    handler = (req) async {
      if (req.uri.path == '/a') return redirect(req, '/b');
      req.response.statusCode = 200;
      req.response.write('final');
      await req.response.close();
    };
    final r = await httpRequest('GET', url('/a'));
    expect(r.status, 200);
    expect(r.body, 'final');
    expect(hits, 2);
  });

  test('follow=false: بيرجّع الـ 3xx زي ما هو', () async {
    handler = (req) => redirect(req, '/b');
    final r = await httpRequest('GET', url('/a'), follow: false);
    expect(r.status, 302);
    expect(hits, 1);
  });

  test('تحويلة لـ http:// مرفوضة', () async {
    handler = (req) => redirect(req, 'http://example.com/x');
    await expectLater(
      httpRequest('GET', url()),
      throwsA(isA<HttpException>()),
    );
    expect(hits, 1);
  });

  test('تحويلة لعنوان metadata مرفوضة من غير اتصال', () async {
    handler = (req) => redirect(req, 'https://169.254.169.254/latest/meta-data/');
    await expectLater(
      httpRequest('GET', url()),
      throwsA(isA<BlockedTargetException>()),
    );
    expect(hits, 1);
  });

  test('تحويلة بـ user@ مرفوضة', () async {
    handler = (req) => redirect(req, 'https://user:pw@example.com/');
    await expectLater(
      httpRequest('GET', url()),
      throwsA(isA<BlockedTargetException>()),
    );
  });

  test('حلقة تحويلات: بتقف عند الحد وبترمي استثناء', () async {
    handler = (req) => redirect(req, '/loop');
    await expectLater(
      httpRequest('GET', url('/loop'), maxRedirects: 3),
      throwsA(isA<HttpException>()),
    );
    expect(hits, 4); // الطلب الأصلي + 3 تحويلات
  });

  test('رد أكبر من الحد: truncated', () async {
    handler = (req) async {
      req.response.statusCode = 200;
      req.response.write('x' * 5000);
      await req.response.close();
    };
    final r = await httpRequest('GET', url(), maxBytes: 1000);
    expect(r.truncated, isTrue);
  });
}
