import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'net_guard.dart';

class HttpResult {
  const HttpResult(this.status, this.body, {this.truncated = false});

  final int status;
  final String body;

  /// الرد تجاوز الحد الأقصى للحجم وتم قطعه (فالمحتوى ناقص).
  final bool truncated;
}

/// بديل للشبكة في الاختبارات فقط: لو اتحدد، [httpRequest] بيستدعيه بدل ما يتصل بالإنترنت.
/// (بعد التحقق من https عشان الاختبارات تغطي القاعدة دي كمان).
typedef HttpOverride = Future<HttpResult> Function(
  String method,
  Uri uri, {
  Map<String, String>? headers,
  String? body,
});

@visibleForTesting
HttpOverride? httpOverride;

/// للاختبارات فقط: SecurityContext بديل (يثق في شهادة اختبار محلية) لاختبار مسار الاتصال
/// الحقيقي والتحويلات على خادم https محلي. الافتراضي null = جذور النظام.
@visibleForTesting
SecurityContext? httpSecurityContextForTesting;

/// طلب HTTP بسيط بمهلة وحد أقصى لحجم الرد (بدون أي حزمة خارجية).
///
/// للاستخدام مع خدمات ثابتة معروفة فقط (OpenPhish, RDAP, Google, VirusTotal):
/// بيرفض أي رابط غير https. لو الرد أكبر من [maxBytes] بيتقطع وبيرجّع
/// `truncated: true` عشان اللي بيستدعي ميتعاملش مع محتوى ناقص كأنه كامل.
///
/// التحويلات (3xx) بتتتبع يدويًا (حتى [maxRedirects]) وكل وجهة بتتفحص قبل الاتصال: https فقط،
/// بدون user@، وبدون عنوان داخلي/محلي ([NetGuard.blockReason])، والاتصال نفسه مثبّت على
/// العنوان اللي اتحقق منه ([NetGuard.pinnedClient]). لو التحويلة راحت لمضيف تاني بنشيل
/// الـ headers المخصصة (زي x-apikey) عشان المفتاح ما يتسربش لجهة تانية.
/// المهلة [timeout] لكل خطوة، و[totalTimeout] للعملية كلها.
Future<HttpResult> httpRequest(
  String method,
  Uri uri, {
  Map<String, String>? headers,
  String? body,
  Duration timeout = const Duration(seconds: 10),
  Duration totalTimeout = const Duration(seconds: 30),
  int maxBytes = 2 * 1024 * 1024,
  bool follow = true,
  int maxRedirects = 5,
}) async {
  if (!uri.isScheme('https')) {
    throw ArgumentError('https only');
  }
  final override = httpOverride;
  if (override != null) {
    return override(method, uri, headers: headers, body: body);
  }
  final clock = Stopwatch()..start();
  Duration slice() {
    final left = totalTimeout - clock.elapsed;
    if (left <= Duration.zero) return const Duration(milliseconds: 1);
    return left < timeout ? left : timeout;
  }

  final client = NetGuard.pinnedClient(
    connectTimeout: timeout,
    userAgent: 'CobraShield/1.2',
    context: httpSecurityContextForTesting,
    lookupTimeout: slice,
  );
  try {
    var current = uri;
    var verb = method;
    var payload = body;
    var sendHeaders = headers;
    for (var hop = 0;; hop++) {
      if (!current.isScheme('https')) {
        throw const HttpException('redirect to a non-https URL was refused');
      }
      final reason = NetGuard.blockReason(current);
      if (reason != null) {
        throw BlockedTargetException(reason);
      }
      final req = await client.openUrl(verb, current).timeout(slice());
      req.followRedirects = false;
      if (sendHeaders != null) {
        for (final e in sendHeaders.entries) {
          req.headers.set(e.key, e.value);
        }
      }
      if (payload != null) {
        final bytes = utf8.encode(payload);
        req.headers.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(slice());
      final code = res.statusCode;
      final loc = res.headers.value(HttpHeaders.locationHeader);
      final isRedirect = code == 301 ||
          code == 302 ||
          code == 303 ||
          code == 307 ||
          code == 308;
      if (follow && isRedirect && loc != null && loc.isNotEmpty) {
        await res.drain<void>().timeout(slice());
        if (hop >= maxRedirects) {
          throw const HttpException('too many redirects');
        }
        if (loc.length > 2048) {
          throw const HttpException('redirect location too long');
        }
        final next = current.resolve(loc);
        if (next.host != current.host) sendHeaders = null; // مفيش تسريب مفاتيح لمضيف تاني
        if (code == 301 || code == 302 || code == 303) {
          if (verb != 'GET' && verb != 'HEAD') verb = 'GET';
          payload = null;
        }
        current = next;
        continue;
      }
      final chunks = <int>[];
      var truncated = false;
      await for (final c in res.timeout(slice())) {
        chunks.addAll(c);
        if (chunks.length > maxBytes) {
          truncated = true;
          break;
        }
      }
      return HttpResult(
        code,
        utf8.decode(chunks, allowMalformed: true),
        truncated: truncated,
      );
    }
  } finally {
    client.close(force: true);
  }
}
