import 'dart:async';
import 'dart:io';

import 'package:cobra_shield/services/link_expander.dart';
import 'package:cobra_shield/services/net_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبارات بدون شبكة: الحارس بيرفض قبل أي اتصال، فمفيش socket بيتفتح هنا.
void main() {
  group('LinkExpander يرفض وجهات غير آمنة قبل الاتصال', () {
    for (final u in <String>[
      'http://127.0.0.1/',
      'http://localhost:8080/admin',
      'http://192.168.1.1/',
      'http://169.254.169.254/latest/meta-data/',
      'http://[::1]/',
      'http://2130706433/',
      'ftp://example.com/file',
      'https://user:secret@example.com/',
      'http://example.com:22/',
    ]) {
      test(u, () async {
        final r = await LinkExpander.expand(u);
        expect(r.blocked, isTrue);
        expect(r.blockedHop, 0);
        expect(r.blockedOnRedirect, isFalse);
        expect(r.error, isNotNull);
        expect(r.chain, <String>[u]);
        expect(r.redirected, isFalse);
      });
    }
  });

  // ---- خادم محلي حقيقي: بنختبر التحويلات والاتصال المثبّت على IP فعليًا. --------
  // allowLoopbackForTesting بيسمح بـ 127.0.0.1 بس هنا؛ كل الوجهات الداخلية التانية
  // (169.254.x و 10.x ...) لسه محظورة، وده اللي بنتأكد منه.
  group('مسار التحويلات (خادم محلي)', () {
    late HttpServer server;
    late int port;
    var hits = <String>[];
    late FutureOr<void> Function(HttpRequest req) handler;

    setUp(() async {
      NetGuard.allowLoopbackForTesting = true;
      hits = <String>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = server.port;
      server.listen((req) async {
        hits.add('${req.method} ${req.uri.path}');
        await handler(req);
      });
    });

    tearDown(() async {
      NetGuard.allowLoopbackForTesting = false;
      await server.close(force: true);
    });

    Future<void> redirect(HttpRequest req, String to) async {
      req.response.statusCode = 302;
      req.response.headers.set(HttpHeaders.locationHeader, to);
      await req.response.close();
    }

    test('تحويلة عادية ثم 200: الاتصال بيشتغل وبينتهي للوجهة النهائية', () async {
      handler = (req) async {
        if (req.uri.path == '/start') return redirect(req, '/final');
        req.response.statusCode = 200;
        await req.response.close();
      };
      final r = await LinkExpander.expand('http://127.0.0.1:$port/start');
      expect(r.error, isNull);
      expect(r.blocked, isFalse);
      expect(r.redirected, isTrue);
      expect(r.finalUrl, 'http://127.0.0.1:$port/final');
      expect(r.statusCode, 200);
    });

    test('تحويلة لعنوان metadata: الحارس يوقفها (blockedOnRedirect) من غير اتصال', () async {
      handler = (req) => redirect(req, 'http://169.254.169.254/latest/meta-data/');
      final r = await LinkExpander.expand('http://127.0.0.1:$port/start');
      expect(r.blocked, isTrue);
      expect(r.blockedHop, 1);
      expect(r.blockedOnRedirect, isTrue);
      expect(r.chain.last, contains('169.254.169.254'));
      expect(r.error, contains('تحويلة'));
      expect(hits, <String>['HEAD /start']);
    });

    test('تحويلة لشبكة داخلية 192.168 / 10 أو user@ أو بروتوكول غريب كلها بتتوقف', () async {
      for (final target in <String>[
        'http://192.168.1.1/admin',
        'http://10.0.0.5:8080/',
        'http://user:pw@example.com/',
        'ftp://example.com/file',
      ]) {
        handler = (req) => redirect(req, target);
        final r = await LinkExpander.expand('http://127.0.0.1:$port/start');
        expect(r.blockedOnRedirect, isTrue, reason: target);
      }
    });

    test('حلقة تحويلات مفرغة', () async {
      handler = (req) => redirect(req, req.uri.path == '/a' ? '/b' : '/a');
      final r = await LinkExpander.expand('http://127.0.0.1:$port/a');
      expect(r.error, contains('حلقة'));
      expect(r.blocked, isFalse);
    });

    test('تحويلات كتير جدًا', () async {
      var n = 0;
      handler = (req) => redirect(req, '/hop${++n}');
      final r = await LinkExpander.expand('http://127.0.0.1:$port/hop0');
      expect(r.error, contains('عدد التحويلات'));
      expect(r.chain.length, LinkExpander.maxHops + 1);
    });

    test('Location طويل بشكل غير طبيعي', () async {
      handler = (req) => redirect(req, '/${'a' * 3000}');
      final r = await LinkExpander.expand('http://127.0.0.1:$port/start');
      expect(r.error, contains('طويل'));
    });

    test('سيرفر بيرفض HEAD: بنجرّب GET', () async {
      handler = (req) async {
        if (req.method == 'HEAD') {
          req.response.statusCode = 405;
        } else {
          req.response.statusCode = 200;
        }
        await req.response.close();
      };
      final r = await LinkExpander.expand('http://127.0.0.1:$port/x');
      expect(r.error, isNull);
      expect(r.statusCode, 200);
      expect(hits, <String>['HEAD /x', 'GET /x']);
    });
  });
}
