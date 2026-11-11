import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// حارس الشبكة: يمنع التطبيق من الاتصال بوجهات داخلية أو محلية أثناء تتبع الروابط.
///
/// ليه ده مهم؟ رابط خبيث ممكن يحوّل التطبيق لعنوان زي http://192.168.1.1/...
/// (راوتر أو جهاز في شبكتك) أو http://169.254.169.254/ (خدمات الـ metadata)،
/// فيبعت الطلب من جهازك لجهاز داخلي. الحارس بيرفض:
///  - أي بروتوكول غير http/https، وأي رابط فيه user:pass@،
///  - منافذ غير معتادة،
///  - أسماء محلية (localhost, *.local, *.internal, اسم من كلمة واحدة...)،
///  - عناوين IP بصيغ غير معتادة (عشري/سداسي عشري/ثماني/مختصر) لأنها بتتخفى كـ IP محلي،
///  - أي عنوان IP محلي/خاص/link-local/مخصص/multicast (IPv4 و IPv6 بما فيها
///    المُضمَّنة: IPv4-mapped و NAT64 و 6to4).
class NetGuard {
  NetGuard._();

  /// للاختبارات فقط: يسمح بـ 127.0.0.1/localhost (بأي منفذ) عشان نقدر نشغّل خادم محلي
  /// ونختبر مسار التحويلات فعليًا. القيمة الافتراضية false ومحدش بيغيّرها في التطبيق.
  @visibleForTesting
  static bool allowLoopbackForTesting = false;

  static bool _isTestLoopbackHost(String host) =>
      allowLoopbackForTesting && (host == '127.0.0.1' || host == 'localhost');

  static const Set<int> allowedPorts = <int>{80, 443, 8080, 8443};
  static const int maxUrlLength = 2048;

  static const List<String> _blockedSuffixes = <String>[
    '.localhost',
    '.local',
    '.internal',
    '.lan',
    '.home',
    '.home.arpa',
    '.corp',
    '.intranet',
    '.private',
    '.localdomain',
  ];

  // شكل "رقمي" (أجزاء أرقام أو 0x...): دومين حقيقي مفيهوش TLD رقمي.
  static final RegExp _numericHost =
      RegExp(r'^(0x[0-9a-f]+|[0-9]+)(\.(0x[0-9a-f]+|[0-9]+))*$');
  static final RegExp _strictQuad =
      RegExp(r'^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$');
  static final RegExp _badHostChars = RegExp(r'[\s\x00-\x1f\\%@/?#\[\]]');

  /// سبب الرفض (بالعربي) لو الرابط مش آمن نتصل بيه، وإلا null.
  /// ده فحص على شكل الرابط فقط؛ فحص عنوان الـ IP الفعلي بيتم وقت الاتصال.
  static String? blockReason(Uri uri) {
    if (uri.toString().length > maxUrlLength) {
      return 'الرابط طويل بشكل غير طبيعي.';
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'الوجهة ليست رابط ويب عادي ($scheme).';
    }
    if (uri.userInfo.isNotEmpty) {
      return 'الرابط يحتوي اسم مستخدم/كلمة سر قبل الدومين (user@host)، وهذا أسلوب تضليل معروف.';
    }
    if (_isTestLoopbackHost(uri.host.toLowerCase())) return null;
    final hostReason = hostBlockReason(uri.host);
    if (hostReason != null) return hostReason;
    // allowLoopbackForTesting بيفتح كل المنافذ للاختبارات المحلية بس (خادم على منفذ عشوائي).
    if (!allowLoopbackForTesting && !allowedPorts.contains(uri.port)) {
      return 'الرابط يستخدم منفذًا غير معتاد (${uri.port}).';
    }
    return null;
  }

  /// فحص اسم المضيف نفسه (قبل أي DNS).
  static String? hostBlockReason(String rawHost) {
    var host = rawHost.trim().toLowerCase();
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.isEmpty) return 'الرابط بدون اسم موقع.';
    if (_badHostChars.hasMatch(host)) return 'اسم الموقع يحتوي رموزًا غير مقبولة.';

    // IPv6 حرفي (Uri.host بيشيل الأقواس)
    if (host.contains(':')) {
      final a = InternetAddress.tryParse(host);
      if (a == null) return 'عنوان IPv6 غير صالح.';
      return isBlockedAddress(a) ? 'الوجهة عنوان داخلي أو محلي.' : null;
    }

    if (host == 'localhost') return 'الوجهة هي الجهاز نفسه (localhost).';
    for (final s in _blockedSuffixes) {
      if (host.endsWith(s)) return 'الوجهة اسم داخلي/محلي ($host).';
    }

    if (_numericHost.hasMatch(host)) {
      if (!_strictQuad.hasMatch(host)) {
        return 'عنوان IP بصيغة غير معتادة (بيُستخدم للتخفي).';
      }
      final parts = host.split('.').map(int.parse).toList();
      if (parts.any((p) => p > 255)) return 'عنوان IP غير صالح.';
      final a = InternetAddress.tryParse(host);
      if (a == null) return 'عنوان IP غير صالح.';
      return isBlockedAddress(a) ? 'الوجهة عنوان داخلي أو محلي.' : null;
    }

    if (!host.contains('.')) return 'الوجهة اسم داخلي من كلمة واحدة ($host).';
    return null;
  }

  /// هل العنوان ده محلي/خاص/مخصص ومينفعش نتصل بيه من تطبيق مفتوح للإنترنت؟
  static bool isBlockedAddress(InternetAddress a) {
    if (allowLoopbackForTesting && a.isLoopback) return false;
    final b = a.rawAddress;
    if (b.length == 4) return _blockedV4(b[0], b[1], b[2], b[3]);
    if (b.length == 16) return _blockedV6(b);
    return true; // نوع غير معروف: نمنعه
  }

  static bool _blockedV4(int b0, int b1, int b2, int b3) {
    if (b0 == 0) return true; // 0.0.0.0/8
    if (b0 == 10) return true; // 10/8
    if (b0 == 100 && (b1 & 0xC0) == 64) return true; // 100.64/10 (CGNAT)
    if (b0 == 127) return true; // loopback
    if (b0 == 169 && b1 == 254) return true; // link-local + metadata 169.254.169.254
    if (b0 == 172 && (b1 & 0xF0) == 16) return true; // 172.16/12
    if (b0 == 192 && b1 == 0 && b2 == 0) return true; // 192.0.0.0/24
    if (b0 == 192 && b1 == 0 && b2 == 2) return true; // TEST-NET-1
    if (b0 == 192 && b1 == 88 && b2 == 99) return true; // 6to4 relay (deprecated)
    if (b0 == 192 && b1 == 168) return true; // 192.168/16
    if (b0 == 198 && (b1 & 0xFE) == 18) return true; // 198.18/15
    if (b0 == 198 && b1 == 51 && b2 == 100) return true; // TEST-NET-2
    if (b0 == 203 && b1 == 0 && b2 == 113) return true; // TEST-NET-3
    if (b0 >= 224) return true; // multicast + reserved + broadcast
    return false;
  }

  static bool _blockedV6(List<int> b) {
    bool zeros(int from, int to) {
      for (var i = from; i < to; i++) {
        if (b[i] != 0) return false;
      }
      return true;
    }

    // :: و ::1
    if (zeros(0, 15) && (b[15] == 0 || b[15] == 1)) return true;
    // ::a.b.c.d (IPv4-compatible، قديم)
    if (zeros(0, 12)) return _blockedV4(b[12], b[13], b[14], b[15]);
    // ::ffff:a.b.c.d (IPv4-mapped)
    if (zeros(0, 10) && b[10] == 0xff && b[11] == 0xff) {
      return _blockedV4(b[12], b[13], b[14], b[15]);
    }
    // 64:ff9b::/96 (NAT64) و 64:ff9b:1::/48 (استخدام محلي)
    if (b[0] == 0x00 && b[1] == 0x64 && b[2] == 0xff && b[3] == 0x9b) {
      if (zeros(4, 12)) return _blockedV4(b[12], b[13], b[14], b[15]);
      if (b[4] == 0x00 && b[5] == 0x01) return true;
    }
    if (b[0] == 0xfe && (b[1] & 0xC0) == 0x80) return true; // fe80::/10 link-local
    if (b[0] == 0xfe && (b[1] & 0xC0) == 0xC0) return true; // fec0::/10 site-local
    if ((b[0] & 0xFE) == 0xFC) return true; // fc00::/7 ULA
    if (b[0] == 0xff) return true; // multicast
    if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8) return true; // docs
    if (b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x00 && b[3] == 0x00) return true; // Teredo
    if (b[0] == 0x20 && b[1] == 0x02) {
      // 6to4: IPv4 مُضمَّن في البايتات 2..5
      return _blockedV4(b[2], b[3], b[4], b[5]);
    }
    if (b[0] == 0x01 && zeros(1, 8)) return true; // 100::/64 discard-only
    return false;
  }

  /// يتحقق من كل العناوين اللي رجعها الـ DNS. لو أي عنوان منها محظور نرفض الكل
  /// (ده بيمنع خدعة "دومين له عنوانين: واحد عام وواحد داخلي").
  /// يرجّع العنوان اللي هنتصل بيه بالتحديد، أو يرمي [BlockedTargetException].
  static InternetAddress pickSafeAddress(List<InternetAddress> addrs) {
    if (addrs.isEmpty) {
      throw const BlockedTargetException('الدومين لا يحتوي عنوان IP.');
    }
    for (final a in addrs) {
      if (isBlockedAddress(a)) {
        throw const BlockedTargetException(
          'الدومين يشير إلى عنوان داخلي أو محلي، فلم يتم الاتصال به.',
        );
      }
    }
    // نفضّل IPv4 لو متاح
    for (final a in addrs) {
      if (a.type == InternetAddressType.IPv4) return a;
    }
    return addrs.first;
  }

  /// HttpClient مثبّت على العنوان: كل اتصال جديد بنعمل له DNS lookup بإيدينا، نتحقق من *كل*
  /// العناوين (NetGuard.pickSafeAddress)، ونتصل بالعنوان اللي اتحقق منه بالتحديد. فمفيش فجوة بين
  /// "اتحققنا" و"اتصلنا" (دي الفجوة اللي بيستغلها DNS rebinding).
  ///
  /// تفاصيل مهمة (اتأكدنا منها من كود dart:io):
  ///  - لما بنحدد connectionFactory وبدون بروكسي، HttpClient بيستخدم السوكت المرجَّع زي ما هو
  ///    من غير ما يعمل TLS بنفسه، فلروابط https لازم نرجّع SecureSocket (ده اللي بنعمله).
  ///  - SecureSocket.startConnect(InternetAddress) بيستخدم `address.host` (الاسم الأصلي اللي
  ///    اتعمل له lookup) كاسم للمصافحة، فاسم الموقع هو اللي بيتبعت كـ SNI ويتطابق مع الشهادة،
  ///    مش الـ IP. (التحقق الفعلي من الشهادة بيتم في طبقة TLS الأصلية؛ والاختبار
  ///    `link_expander_network_test.dart` بيثبت السلوك ده بشهادة اختبار.)
  ///  - مفيش بروكسي ومفيش قبول لشهادات غير صالحة (مفيش onBadCertificate).
  ///  - اتصال keep-alive معاد استخدامه بيفضل على نفس العنوان اللي اتحقق منه أصلًا.
  static HttpClient pinnedClient({
    Duration connectTimeout = const Duration(seconds: 8),
    String? userAgent,
    SecurityContext? context,
    Future<List<InternetAddress>> Function(String host)? resolver,
    Duration Function()? lookupTimeout,
    void Function(String reason)? onBlocked,
    void Function()? onDnsFailure,
  }) {
    final client = HttpClient(context: context)
      ..connectionTimeout = connectTimeout
      ..findProxy = (Uri _) => 'DIRECT';
    if (userAgent != null) client.userAgent = userAgent;
    client.connectionFactory =
        (Uri target, String? proxyHost, int? proxyPort) async {
      if (proxyHost != null) {
        const msg = 'الاتصال عبر بروكسي غير مسموح في الفحص.';
        onBlocked?.call(msg);
        throw const BlockedTargetException(msg);
      }
      final List<InternetAddress> addrs;
      try {
        final lookup = resolver != null
            ? resolver(target.host)
            : InternetAddress.lookup(target.host);
        addrs = await lookup.timeout(lookupTimeout?.call() ?? connectTimeout);
      } on SocketException {
        onDnsFailure?.call();
        rethrow;
      }
      final InternetAddress ip;
      try {
        ip = pickSafeAddress(addrs);
      } on BlockedTargetException catch (e) {
        onBlocked?.call(e.reason);
        rethrow;
      }
      if (target.isScheme('https')) {
        return SecureSocket.startConnect(ip, target.port, context: context);
      }
      return Socket.startConnect(ip, target.port);
    };
    return client;
  }
}

/// الوجهة (أو عنوانها الفعلي بعد الـ DNS) محظورة: لم يحصل أي اتصال.
class BlockedTargetException implements Exception {
  const BlockedTargetException(this.reason);
  final String reason;

  @override
  String toString() => 'BlockedTargetException: $reason';
}
