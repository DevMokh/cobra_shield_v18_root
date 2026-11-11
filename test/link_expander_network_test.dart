import 'dart:io';

import 'package:cobra_shield/services/link_expander.dart';
import 'package:cobra_shield/services/net_guard.dart';
import 'package:flutter_test/flutter_test.dart';

// اختبارات تكامل لحماية الشبكة (SSRF / DNS rebinding) على سيرفرات محلية حقيقية.
//
// الهدف: نثبت بالتجربة (مش بالشرح) إن:
//  1) دومين بيحل لعنوان داخلي بيتمنع وقت الاتصال حتى لو شكله عادي (rebinding).
//  2) لو الـ DNS رجّع عناوين مختلطة (عام + داخلي) بنرفض الكل.
//  3) الاتصال بيروح للـ IP اللي اتحقق منه، وبيفضل مبعوت اسم الموقع في Host.
//  4) مع https: التحقق من الشهادة شغّال وبيتم على *اسم الموقع* مش الـ IP.
//  5) فشل الـ DNS حالة منفصلة (host unreachable) مش تصيّد.
//
// تنبيه صريح: الاختبارات دي لازم تتشغّل على جهاز عليه Flutter (CI أو جهازك). اتكتبت من غير
// ما تتشغّل في البيئة اللي اتعدّل فيها المشروع (مفيش Dart SDK هناك).
void main() {
  tearDown(() {
    NetGuard.allowLoopbackForTesting = false;
    LinkExpander.resolverForTesting = null;
    LinkExpander.securityContextForTesting = null;
  });

  group('DNS rebinding: الحارس وقت الاتصال', () {
    test('دومين شكله عادي لكنه بيحل لعنوان داخلي (10.x): متمنوع وبدون اتصال', () async {
      var lookups = 0;
      LinkExpander.resolverForTesting = (host) async {
        lookups++;
        return <InternetAddress>[InternetAddress('10.0.0.5')];
      };
      final r = await LinkExpander.expand('http://rebind.example.net/');
      expect(r.blocked, isTrue);
      expect(r.failure, ExpandFailure.blocked);
      expect(r.blockedHop, 0);
      expect(lookups, 1);
    });

    test('عنوان metadata (169.254.169.254) بعد الـ DNS: متمنوع', () async {
      LinkExpander.resolverForTesting =
          (host) async => <InternetAddress>[InternetAddress('169.254.169.254')];
      final r = await LinkExpander.expand('http://metadata.example.net/latest/');
      expect(r.failure, ExpandFailure.blocked);
    });

    test('IPv4-mapped داخلي (::ffff:10.0.0.5): متمنوع', () async {
      LinkExpander.resolverForTesting =
          (host) async => <InternetAddress>[InternetAddress('::ffff:10.0.0.5')];
      final r = await LinkExpander.expand('http://mapped.example.net/');
      expect(r.failure, ExpandFailure.blocked);
    });

    test('عناوين مختلطة (عام + داخلي): بنرفض الكل', () async {
      LinkExpander.resolverForTesting = (host) async => <InternetAddress>[
            InternetAddress('93.184.216.34'),
            InternetAddress('192.168.1.10'),
          ];
      final r = await LinkExpander.expand('http://mixed.example.net/');
      expect(r.failure, ExpandFailure.blocked);
    });

    test('loopback الحقيقي بدون علم الاختبار: متمنوع', () async {
      LinkExpander.resolverForTesting =
          (host) async => <InternetAddress>[InternetAddress.loopbackIPv4];
      final r = await LinkExpander.expand('http://loop.example.net/');
      expect(r.failure, ExpandFailure.blocked);
    });
  });

  group('تثبيت الاتصال على العنوان اللي اتحقق منه (http)', () {
    late HttpServer server;
    final seenHosts = <String>[];

    setUp(() async {
      NetGuard.allowLoopbackForTesting = true;
      seenHosts.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        seenHosts.add(req.headers.value(HttpHeaders.hostHeader) ?? '');
        req.response.statusCode = 200;
        await req.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('الاتصال بيروح للـ IP اللي رجّعه الـ resolver، واسم الموقع بيفضل في Host', () async {
      var lookups = 0;
      LinkExpander.resolverForTesting = (host) async {
        lookups++;
        return <InternetAddress>[InternetAddress.loopbackIPv4];
      };
      final r = await LinkExpander.expand('http://pinned.example.net:${server.port}/x');
      expect(r.error, isNull);
      expect(r.statusCode, 200);
      expect(seenHosts, isNotEmpty);
      expect(seenHosts.first, startsWith('pinned.example.net'));
      // lookup واحد للاتصال الواحد (مفيش lookup تاني من HttpClient نفسه).
      expect(lookups, 1);
    });
  });

  group('فشل الوصول للموقع = حالة مستقلة (مش تصيّد)', () {
    test('فشل DNS', () async {
      LinkExpander.resolverForTesting = (host) async =>
          throw const SocketException('Failed host lookup');
      final r = await LinkExpander.expand('http://no-such-domain.example.net/');
      expect(r.failure, ExpandFailure.dns);
      expect(r.hostUnreachable, isTrue);
      expect(r.blocked, isFalse);
      expect(r.error, contains('لا يعني'));
    });

    test('اتصال مرفوض (منفذ مقفول) ≠ DNS', () async {
      NetGuard.allowLoopbackForTesting = true;
      // نحجز منفذ ونقفله عشان نضمن إنه مقفول.
      final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closedPort = tmp.port;
      await tmp.close();
      LinkExpander.resolverForTesting =
          (host) async => <InternetAddress>[InternetAddress.loopbackIPv4];
      final r = await LinkExpander.expand('http://refused.example.net:$closedPort/');
      expect(r.failure, ExpandFailure.connection);
      expect(r.hostUnreachable, isTrue);
    });

    test('مهلة: سيرفر يقبل الاتصال ولا يرد', () async {
      NetGuard.allowLoopbackForTesting = true;
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      silent.listen(sockets.add);
      LinkExpander.resolverForTesting =
          (host) async => <InternetAddress>[InternetAddress.loopbackIPv4];
      final r = await LinkExpander.expand('http://slow.example.net:${silent.port}/');
      expect(r.failure, ExpandFailure.timeout);
      expect(r.hostUnreachable, isTrue);
      for (final s in sockets) {
        s.destroy();
      }
      await silent.close();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  group('https: التحقق من الشهادة واسم الموقع', () {
    late HttpServer tls;
    late SecurityContext trustTestCert;

    setUp(() async {
      NetGuard.allowLoopbackForTesting = true;
      final serverCtx = SecurityContext()
        ..useCertificateChain('test/fixtures/test_cert.pem')
        ..usePrivateKey('test/fixtures/test_key.pem');
      tls = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, serverCtx);
      tls.listen((req) async {
        req.response.statusCode = 200;
        await req.response.close();
      });
      trustTestCert = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('test/fixtures/test_cert.pem');
    });

    tearDown(() async {
      await tls.close(force: true);
    });

    test('شهادة موثوقة لاسم localhost: الاتصال المثبّت على IP ينجح (الاسم هو اللي بيتحقق)', () async {
      LinkExpander.securityContextForTesting = trustTestCert;
      final r = await LinkExpander.expand('https://localhost:${tls.port}/');
      expect(r.error, isNull, reason: r.error);
      expect(r.statusCode, 200);
    });

    test('نفس السيرفر بالـ IP (127.0.0.1): الشهادة لا تطابق الاسم فيفشل', () async {
      LinkExpander.securityContextForTesting = trustTestCert;
      final r = await LinkExpander.expand('https://127.0.0.1:${tls.port}/');
      expect(r.failure, ExpandFailure.tls);
    });

    test('شهادة غير موثوقة (جذور النظام): الاتصال يفشل، التحقق مش متعطّل', () async {
      final r = await LinkExpander.expand('https://localhost:${tls.port}/');
      expect(r.failure, ExpandFailure.tls);
    });
  });
}
