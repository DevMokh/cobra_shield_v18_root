import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'net_guard.dart';

/// سبب فشل تتبع التحويلات. الفشل في الوصول للموقع (DNS/مهلة/اتصال) مش دليل تصيّد:
/// موقع ميت أو دومين اتحذف أو إنترنت ضعيف كلهم بيدّوا نفس الأعراض.
enum ExpandFailure {
  none,

  /// الحارس منع الاتصال بوجهة داخلية/غير ويب (لم يحصل اتصال).
  blocked,

  /// الدومين ما اتحلّش في DNS (غير موجود/محذوف أو مفيش إنترنت).
  dns,

  /// السيرفر ما ردّش في المهلة (أو المهلة الكلية خلصت).
  timeout,

  /// الشهادة (SSL) غير صالحة أو مش مطابقة لاسم الموقع.
  tls,

  /// الاتصال اترفض/اتقطع (منفذ مقفول، إلخ).
  connection,

  /// حلقة تحويلات.
  loop,

  /// تحويلات أكتر من الحد.
  tooManyHops,

  /// عنوان تحويلة طويل أو غير صالح.
  badRedirect,

  /// خطأ غير متوقع.
  unexpected,
}

class ExpandResult {
  const ExpandResult({
    required this.chain,
    this.statusCode,
    this.error,
    this.blockedHop,
    this.failure = ExpandFailure.none,
  });

  final List<String> chain; // الرابط الأصلي ثم كل تحويلة
  final int? statusCode;
  final String? error;

  /// رقم الحلقة اللي اتمنع الاتصال بيها (0 = الرابط الأصلي نفسه). null لو مفيش منع.
  final int? blockedHop;

  /// نوع الفشل ([ExpandFailure.none] = نجح).
  final ExpandFailure failure;

  String get finalUrl => chain.last;
  bool get redirected => chain.length > 1;

  /// الحارس منع الاتصال بوجهة (محلية/داخلية/غير ويب...)، ومحصلش اتصال بيها.
  bool get blocked => blockedHop != null;

  /// المنع حصل على وجهة تحويلة (يعني رابط خارجي بيحوّل لوجهة داخلية): علامة خطر.
  bool get blockedOnRedirect => blockedHop != null && blockedHop! > 0;

  /// تعذّر الوصول للموقع (DNS / مهلة / اتصال). ده "حالة": الموقع غير متاح، مش حكم
  /// بإنه تصيّد، ومالوش نقاط خطر.
  bool get hostUnreachable =>
      failure == ExpandFailure.dns ||
      failure == ExpandFailure.timeout ||
      failure == ExpandFailure.connection;
}

class _Probe {
  const _Probe(this.status, this.location);
  final int status;
  final String? location;
}

/// يتتبع تحويلات الرابط (HEAD فقط، بدون تحميل أي محتوى) ليكشف الوجهة الحقيقية.
/// تنبيه: ده بيتصل فعليًا بالسيرفر، فالتطبيق يطلب موافقة المستخدم قبله.
///
/// حماية الشبكة (راجع NetGuard):
///  1) كل رابط (الأصلي وكل تحويلة) بيتفحص شكله قبل الاتصال.
///  2) وقت الاتصال نفسه بنعمل DNS lookup بأنفسنا، ونتحقق من *كل* العناوين، ونتصل
///     بالعنوان اللي اتحقق منه بالتحديد (connectionFactory). فمفيش فجوة بين
///     "اتحققنا" و"اتصلنا"، وده بيقفل هجوم DNS rebinding في الاتصالات الجديدة.
///     (اتصال keep-alive معاد استخدامه بيكون لنفس العنوان اللي اتحقق منه أصلًا.)
///  3) مفيش بروكسي، ومفيش قبول لشهادات غير صالحة.
class LinkExpander {
  LinkExpander._();

  static const int maxHops = 8;
  static const int maxLocationLength = 2048;
  static const Duration _timeout = Duration(seconds: 8);
  static const Duration _totalBudget = Duration(seconds: 30);

  /// للاختبارات فقط: بديل لـ [InternetAddress.lookup] (لمحاكاة دومين بيحل لعنوان داخلي
  /// أو اتنين عناوين...). الافتراضي null (DNS حقيقي).
  @visibleForTesting
  static Future<List<InternetAddress>> Function(String host)? resolverForTesting;

  /// للاختبارات فقط: SecurityContext بديل (لاختبار التحقق من الشهادة واسم الموقع مع
  /// شهادة اختبار). الافتراضي null = جذور النظام.
  @visibleForTesting
  static SecurityContext? securityContextForTesting;

  /// مهلة العملية الواحدة = أقل من (المهلة العادية، الباقي من الميزانية الكلية).
  static Duration _slice(Stopwatch clock) {
    final left = _totalBudget - clock.elapsed;
    if (left <= Duration.zero) return const Duration(milliseconds: 1);
    return left < _timeout ? left : _timeout;
  }

  static Future<_Probe> _probe(
    HttpClient client,
    Uri uri,
    String method,
    Stopwatch clock,
  ) async {
    final req = await client.openUrl(method, uri).timeout(_slice(clock));
    req.followRedirects = false;
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    final res = await req.close().timeout(_slice(clock));
    final loc = res.headers.value(HttpHeaders.locationHeader);
    final status = res.statusCode;
    // لا نحمّل أي محتوى: نقطع الاتصال فورًا
    final sub = res.listen((_) {});
    await sub.cancel();
    return _Probe(status, loc);
  }

  static Future<ExpandResult> expand(String url) async {
    final chain = <String>[url];
    String? blockedReason; // بيتملي لو الحارس منع اتصال (من أي مكان)
    var dnsFailed = false; // بيتملي لو الـ DNS lookup نفسه فشل
    int? status;
    final clock = Stopwatch()..start();

    final client = NetGuard.pinnedClient(
      connectTimeout: _timeout,
      userAgent: 'Mozilla/5.0 (Linux; Android 14) CobraShield/1.0',
      context: securityContextForTesting,
      resolver: resolverForTesting,
      lookupTimeout: () => _slice(clock),
      onBlocked: (reason) => blockedReason = reason,
      onDnsFailure: () => dnsFailed = true,
    );

    ExpandResult fail(
      String message,
      ExpandFailure kind, {
      int? blockedHop,
    }) =>
        ExpandResult(
          chain: chain,
          statusCode: status,
          error: message,
          blockedHop: blockedHop,
          failure: kind,
        );

    try {
      var current = Uri.parse(url);
      for (var hop = 0; hop < maxHops; hop++) {
        if (clock.elapsed > _totalBudget) {
          return fail('انتهت المهلة الكلية لتتبع التحويلات.', ExpandFailure.timeout);
        }
        final reason = NetGuard.blockReason(current);
        if (reason != null) {
          return fail(
            hop == 0
                ? 'لم نتصل بالرابط: $reason'
                : 'تحويلة رقم $hop تشير لوجهة غير آمنة، فتوقفنا ولم نتصل بها: $reason',
            ExpandFailure.blocked,
            blockedHop: hop,
          );
        }
        var p = await _probe(client, current, 'HEAD', clock);
        if (p.status == 405 ||
            p.status == 501 ||
            p.status == 400 ||
            p.status == 403) {
          // بعض السيرفرات ترفض HEAD
          p = await _probe(client, current, 'GET', clock);
        }
        status = p.status;
        final loc = p.location;
        if (p.status >= 300 && p.status < 400 && loc != null && loc.isNotEmpty) {
          if (loc.length > maxLocationLength) {
            return fail('عنوان التحويلة طويل بشكل غير طبيعي وهذا مريب.',
                ExpandFailure.badRedirect);
          }
          final next = current.resolve(loc);
          if (chain.contains(next.toString())) {
            return fail('التحويلات بتدور في حلقة مفرغة وهذا مريب.', ExpandFailure.loop);
          }
          current = next;
          chain.add(current.toString());
          continue;
        }
        return ExpandResult(chain: chain, statusCode: status);
      }
      return fail('عدد التحويلات كبير (أكثر من $maxHops) وهذا مريب.',
          ExpandFailure.tooManyHops);
    } on BlockedTargetException catch (e) {
      return fail(
        'تم إيقاف الاتصال: ${e.reason}',
        ExpandFailure.blocked,
        blockedHop: chain.length - 1,
      );
    } on TimeoutException {
      if (blockedReason != null) {
        return fail('تم إيقاف الاتصال: $blockedReason', ExpandFailure.blocked,
            blockedHop: chain.length - 1);
      }
      return fail(
        'انتهت المهلة: الموقع لم يرد. ده لا يعني إنه تصيّد، ممكن يكون بطيء أو متوقف.',
        ExpandFailure.timeout,
      );
    } on TlsException {
      return fail(
        'شهادة الأمان (SSL) غير صالحة أو لا تطابق اسم الموقع.',
        ExpandFailure.tls,
      );
    } on SocketException {
      if (dnsFailed) {
        return fail(
          'تعذّر الوصول للموقع: الدومين لا يُحَلّ في DNS (غير موجود أو محذوف، أو لا يوجد إنترنت). ده لا يعني بحد ذاته إنه تصيّد، لكن الوجهة النهائية للرابط غير معروفة.',
          ExpandFailure.dns,
        );
      }
      return fail(
        'تعذّر الاتصال بالموقع (رُفض الاتصال أو انقطع). ده لا يعني بحد ذاته إنه تصيّد.',
        ExpandFailure.connection,
      );
    } on FormatException {
      return fail('تحويلة بعنوان غير صالح وهذا مريب.', ExpandFailure.badRedirect);
    } catch (_) {
      // لو الحارس هو سبب الخطأ (حتى لو اتغلّف الاستثناء) نقول كده بدل رسالة عامة
      final why = blockedReason;
      if (why != null) {
        return fail('تم إيقاف الاتصال: $why', ExpandFailure.blocked,
            blockedHop: chain.length - 1);
      }
      return fail('تعذر فحص الرابط (رد غير متوقع).', ExpandFailure.unexpected);
    } finally {
      client.close(force: true);
    }
  }
}
