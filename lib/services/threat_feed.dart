import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'http_util.dart';
import 'net_guard.dart';
import 'url_analyzer.dart';

class FeedMatch {
  const FeedMatch(this.kind, this.points);

  final String kind; // exact | host | domain
  final int points;
}

/// نتيجة قراءة نص الخلاصة (قبل ما تتعتمد).
class FeedParse {
  FeedParse._(this.urls, this.hosts, this.domains, this.validLines, this.rejectedLines);

  final Set<String> urls;
  final Set<String> hosts;
  final Set<String> domains;

  /// عدد الأسطر الصالحة / المرفوضة (التعليقات والأسطر الفاضية مش محسوبة).
  final int validLines;
  final int rejectedLines;

  /// الأسطر الصالحة بعد التطبيع، بتتحفظ في الملف بدل الرد الخام.
  List<String> keptLines = <String>[];
}

/// حالة محاولة تحديث القاعدة.
enum FeedUpdateStatus {
  /// نزلت خلاصة صالحة واتحفظت على الجهاز، والمحتوى اتغيّر.
  updated,

  /// نزلت خلاصة صالحة واتحفظت، لكن نفس محتوى القاعدة الحالية (مفيش جديد).
  unchanged,

  /// نزلت خلاصة صالحة واتطبّقت في الذاكرة، لكن *تعذّر حفظها* على الجهاز: ترجع للقديمة بعد إعادة تشغيل التطبيق.
  updatedNotSaved,

  /// الرد اتنزّل لكن اترفض (فاضي / معطوب / مقطوع / أصغر بكتير): القاعدة السابقة بتفضل.
  rejected,

  /// فشل التنزيل (شبكة / مهلة / رد غير 200 ...): القاعدة السابقة بتفضل.
  failed,
}

/// تقرير محاولة تحديث واحدة. الفرق مهم: "التنزيل نجح" حاجة، و"الحفظ الدائم نجح" حاجة تانية.
class FeedUpdateReport {
  const FeedUpdateReport({
    required this.status,
    required this.countBefore,
    required this.countAfter,
    required this.time,
    required this.source,
    this.changed = false,
    this.downloaded = false,
    this.persisted = false,
    this.error,
  });

  final FeedUpdateStatus status;

  /// عدد الروابط قبل المحاولة وبعدها (بعد الفشل = نفس القبل: القاعدة القديمة سليمة).
  final int countBefore;
  final int countAfter;

  /// وقت المحاولة.
  final DateTime time;

  /// مصدر الخلاصة.
  final String source;

  /// محتوى القاعدة اتغيّر فعلًا.
  final bool changed;

  /// التنزيل نجح والخلاصة صالحة (اجتازت كل فحوصات القبول).
  final bool downloaded;

  /// الحفظ الدائم على الجهاز نجح (اتكتب واتقرا تاني وتأكدنا منه).
  final bool persisted;

  /// سبب الفشل/الرفض/عدم الحفظ (للمستخدم، بالعربي).
  final String? error;

  /// نجاح كامل: خلاصة صالحة اتنزّلت *واتحفظت*.
  bool get ok =>
      status == FeedUpdateStatus.updated || status == FeedUpdateStatus.unchanged;

  int get delta => countAfter - countBefore;

  /// ملخص بالعربي للمستخدم: العدد قبل/بعد، وهل اتحفظ، وسبب أي فشل. القاعدة السابقة بتتذكر
  /// صراحة في حالات الفشل عشان المستخدم يعرف إنها لسه شغالة.
  String get summary {
    switch (status) {
      case FeedUpdateStatus.updated:
        final d = delta >= 0 ? '+$delta' : '$delta';
        return 'تم التحديث وحُفظ على الجهاز: $countBefore ← $countAfter رابط ($d)';
      case FeedUpdateStatus.unchanged:
        return 'القاعدة محدّثة بالفعل ومحفوظة: $countAfter رابط (بدون تغيير)';
      case FeedUpdateStatus.updatedNotSaved:
        return '$error ($countBefore ← $countAfter رابط)';
      case FeedUpdateStatus.rejected:
        return 'التحديث اترفض: $error. القاعدة السابقة ($countBefore رابط) لسه شغالة.';
      case FeedUpdateStatus.failed:
        return 'فشل التحديث: $error. القاعدة السابقة ($countBefore رابط) لسه شغالة.';
    }
  }
}

/// قاعدة روابط التصيّد (OpenPhish Community Feed) محفوظة محليًا.
/// بعد التحديث يتم الفحص بدون إنترنت ولا يُرسل أي رابط لأي جهة.
/// تنبيه: الخلاصة للاستخدام غير التجاري فقط حسب شروط OpenPhish.
///
/// التحديث آمن وذري: بنقرأ الرد في مجموعات مؤقتة ونتحقق منه (مش مقطوع، أغلبه
/// أسطر روابط صالحة، مش أصغر بكتير من القاعدة الحالية) وبس بعدين نبدّل القاعدة
/// ونكتب الملف عبر ملف مؤقت + rename. لو أي شرط فشل القاعدة القديمة بتفضل زي ما هي.
class ThreatFeed extends ChangeNotifier {
  ThreatFeed._() : _dirProvider = null;

  @visibleForTesting
  ThreatFeed.forTest({required Future<Directory> Function() dirProvider})
      : _dirProvider = dirProvider;

  final Future<Directory> Function()? _dirProvider;

  static const String _fileName = 'cobra_openphish.txt';

  static final ThreatFeed instance = ThreatFeed._();

  static const String feedUrl =
      'https://raw.githubusercontent.com/openphish/public_feed/main/feed.txt';

  static const int maxEntries = 100000;
  static const int maxLineLength = 2048;

  /// أقل نسبة أسطر صالحة (من غير التعليقات) عشان نقبل الرد.
  static const double minValidRatio = 0.8;

  /// لو القاعدة الحالية كبيرة، الجديدة لازم تكون على الأقل بالنسبة دي منها.
  static const double minSizeVsPrevious = 0.2;
  static const int previousSizeThreshold = 100;

  Set<String> _urls = <String>{};
  Set<String> _hosts = <String>{};
  Set<String> _domains = <String>{};
  DateTime? _updated;
  bool _busy = false;
  bool _memoryOnly = false;
  FeedUpdateReport? _last;

  /// ملف بيانات وصفية (وقت آخر تحديث ناجح *محفوظ*، العدد، المصدر) جنب ملف القاعدة.
  static const String _metaName = 'cobra_openphish.meta.json';

  int get count => _urls.length;

  /// وقت آخر تحديث ناجح *ومحفوظ* على الجهاز (أو آخر تحميل من الملف بعد إعادة التشغيل).
  DateTime? get updated => _updated;
  bool get busy => _busy;

  /// القاعدة الحالية جاية من تحديث اتطبّق في الذاكرة بس ولم يُحفظ (هتتفقد بعد إعادة التشغيل).
  bool get memoryOnly => _memoryOnly;

  /// آخر محاولة تحديث (ناجحة أو فاشلة) في الجلسة دي، أو null لو لسه ما حصلتش محاولة.
  FeedUpdateReport? get lastReport => _last;

  /// سبب فشل آخر محاولة (null لو نجحت أو لسه ما حصلتش محاولة). للتوافق مع الواجهة القديمة.
  String? get lastError => _last?.error;

  /// مجلد التخزين: مجلد بيانات التطبيق الدائم (مش بيتمسح من النظام زي المجلد المؤقت).
  Future<Directory> _storageDir() async {
    final custom = _dirProvider;
    if (custom != null) return custom();
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  Future<void> load() async {
    try {
      final dir = await _storageDir();
      var f = File('${dir.path}/$_fileName');
      if (!await f.exists() && _dirProvider == null) {
        // ترحيل: النسخة القديمة كانت في المجلد المؤقت
        final old = File('${Directory.systemTemp.path}/$_fileName');
        if (await old.exists()) f = old;
      }
      if (!await f.exists()) return;
      final p = parse(await f.readAsString());
      // ملف تالف أو فاضي: نتجاهله وسيُعاد التحميل عند التحديث
      if (p.urls.isEmpty) return;
      _swap(p);
      _memoryOnly = false;
      _updated = await _readMetaTime(dir) ?? await f.lastModified();
      notifyListeners();
    } catch (_) {
      // ملف تالف: نتجاهله وسيُعاد التحميل عند التحديث
    }
  }

  static String normalize(String url) {
    var s = url.trim().toLowerCase();
    s = s.replaceFirst(RegExp(r'^[a-z][a-z0-9+.\-]*://'), '');
    final hash = s.indexOf('#');
    if (hash >= 0) s = s.substring(0, hash);
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String _hostOf(String normalized) {
    final end = normalized.indexOf(RegExp(r'[/?]'));
    var host = end >= 0 ? normalized.substring(0, end) : normalized;
    final at = host.lastIndexOf('@');
    if (at >= 0) host = host.substring(at + 1);
    final colon = host.indexOf(':');
    if (colon >= 0) host = host.substring(0, colon);
    return host;
  }

  static final RegExp _httpLine = RegExp(r'^https?://', caseSensitive: false);

  /// يقرأ نص الخلاصة في مجموعات جديدة (من غير ما يلمس القاعدة الحالية).
  @visibleForTesting
  static FeedParse parse(String text) {
    final urls = <String>{};
    final hosts = <String>{};
    final domains = <String>{};
    final kept = <String>[];
    var valid = 0;
    var rejected = 0;
    for (final line in text.split('\n')) {
      final l = line.trim();
      if (l.isEmpty || l.startsWith('#')) continue;
      if (!_httpLine.hasMatch(l) ||
          l.length > maxLineLength ||
          l.contains(RegExp(r'\s'))) {
        rejected++;
        continue;
      }
      final u = normalize(l);
      final host = _hostOf(u);
      if (u.isEmpty || host.isEmpty) {
        rejected++;
        continue;
      }
      valid++;
      if (urls.add(u)) {
        hosts.add(host);
        domains.add(UrlAnalyzer.registrableDomain(host));
        kept.add(l);
      }
      if (urls.length >= maxEntries) break;
    }
    return FeedParse._(urls, hosts, domains, valid, rejected)..keptLines = kept;
  }

  /// null لو الخلاصة مقبولة، وإلا سبب الرفض.
  @visibleForTesting
  static String? validate(FeedParse p, {required int previousCount}) {
    if (p.urls.isEmpty) return 'الملف فارغ أو بصيغة غير معروفة';
    final total = p.validLines + p.rejectedLines;
    if (total > 0 && p.validLines / total < minValidRatio) {
      return 'الملف مش بصيغة الخلاصة المتوقعة';
    }
    if (previousCount >= previousSizeThreshold &&
        p.urls.length < previousCount * minSizeVsPrevious) {
      return 'الخلاصة الجديدة أصغر بكتير من الحالية، اتجاهلت للحماية';
    }
    return null;
  }

  void _swap(FeedParse p) {
    _urls = p.urls;
    _hosts = p.hosts;
    _domains = p.domains;
  }

  /// يعتمد نص خلاصة في الذاكرة (قراءة + تحقق + تبديل). يرجّع سبب الرفض أو null.
  /// لا يكتب ملفات؛ الكتابة في [update].
  @visibleForTesting
  String? applyBody(String body) {
    final p = parse(body);
    final why = validate(p, previousCount: _urls.length);
    if (why != null) return why;
    _swap(p);
    return null;
  }

  Future<DateTime?> _readMetaTime(Directory dir) async {
    try {
      final f = File('${dir.path}/$_metaName');
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      if (j is Map && j['updated_ms'] is int) {
        return DateTime.fromMillisecondsSinceEpoch(j['updated_ms'] as int);
      }
    } catch (_) {}
    return null;
  }

  /// يكتب الخلاصة على الجهاز بشكل آمن ويتأكد منها. بيرمي استثناء لو فشل أي خطوة (ومبيسكتش):
  ///  1) نكتب ملف مؤقت ونعمل flush،
  ///  2) نقرأه تاني ونتأكد إن عدد الروابط مطابق (كتابة ناقصة/تالفة ما تحلّش محل الملف الجيد)،
  ///  3) rename فوق الملف القديم،
  ///  4) نكتب ملف بيانات وصفية (وقت التحديث) بنفس الطريقة، وفشلها بس بيخلي الوقت يتقرا من تاريخ الملف.
  /// لو فشل أي شيء قبل الخطوة 3، الملف القديم بيفضل سليم.
  Future<void> _persist(FeedParse p, DateTime at) async {
    final dir = await _storageDir();
    if (!await dir.exists()) await dir.create(recursive: true);
    final target = '${dir.path}/$_fileName';
    final tmp = File('$target.tmp');
    try {
      await tmp.writeAsString('${p.keptLines.join('\n')}\n', flush: true);
      final back = parse(await tmp.readAsString());
      if (back.urls.length != p.urls.length) {
        throw const FileSystemException('read-back verification failed');
      }
      await tmp.rename(target);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
    try {
      final metaTmp = File('${dir.path}/$_metaName.tmp');
      await metaTmp.writeAsString(
        jsonEncode(<String, Object?>{
          'updated_ms': at.millisecondsSinceEpoch,
          'count': p.urls.length,
          'source': feedUrl,
        }),
        flush: true,
      );
      await metaTmp.rename('${dir.path}/$_metaName');
    } catch (_) {
      // البيانات الأساسية اتحفظت؛ الوقت هيتقرا من تاريخ الملف.
    }
  }

  bool _sameContent(FeedParse p) =>
      p.urls.length == _urls.length && _urls.containsAll(p.urls);

  FeedUpdateReport _finish(FeedUpdateReport r) {
    _last = r;
    return r;
  }

  FeedUpdateReport _fail(
    FeedUpdateStatus status,
    DateTime now,
    String error,
  ) =>
      _finish(FeedUpdateReport(
        status: status,
        countBefore: _urls.length,
        countAfter: _urls.length, // القاعدة السابقة بتفضل زي ما هي
        time: now,
        source: feedUrl,
        error: error,
      ));

  /// يحدّث القاعدة ويرجّع تقرير كامل. أي فشل (تنزيل أو رفض أو حفظ) بيسيب القاعدة السابقة
  /// (في الذاكرة وعلى الجهاز) زي ما هي، ومبيتقالش "نجح" إلا لو الحفظ الدائم نجح فعلًا.
  Future<FeedUpdateReport> update() async {
    final now = DateTime.now();
    if (_busy) {
      return FeedUpdateReport(
        status: FeedUpdateStatus.failed,
        countBefore: _urls.length,
        countAfter: _urls.length,
        time: now,
        source: feedUrl,
        error: 'فيه تحديث شغال دلوقتي',
      );
    }
    _busy = true;
    notifyListeners();
    try {
      final HttpResult r;
      try {
        r = await httpRequest(
          'GET',
          Uri.parse(feedUrl),
          timeout: const Duration(seconds: 30),
          maxBytes: 12 * 1024 * 1024,
        );
      } on TimeoutException {
        return _fail(FeedUpdateStatus.failed, now, 'انتهت المهلة');
      } on SocketException {
        return _fail(FeedUpdateStatus.failed, now, 'لا يوجد اتصال بالإنترنت');
      } on TlsException {
        return _fail(FeedUpdateStatus.failed, now, 'تعذر تأمين الاتصال بالمصدر (شهادة غير صالحة)');
      } on BlockedTargetException {
        return _fail(FeedUpdateStatus.failed, now, 'تم منع الاتصال بوجهة غير آمنة');
      } catch (_) {
        return _fail(FeedUpdateStatus.failed, now, 'تعذر التحديث');
      }
      if (r.status != 200) {
        return _fail(FeedUpdateStatus.failed, now, 'رد غير متوقع من السيرفر (${r.status})');
      }
      if (r.truncated) {
        // رد مقطوع: آخر سطر ممكن يكون ناقص والقائمة غير كاملة
        return _fail(FeedUpdateStatus.rejected, now, 'الملف أكبر من الحد المسموح، اتجاهل التحديث');
      }
      final p = parse(r.body);
      final why = validate(p, previousCount: _urls.length);
      if (why != null) {
        return _fail(FeedUpdateStatus.rejected, now, why);
      }

      // خلاصة صالحة. نحفظها *قبل* ما نبدّل القاعدة الحالية؛ لو الحفظ فشل نطبّق في الذاكرة
      // ونقول بوضوح إنها ما اتحفظتش (مش "نجح").
      final before = _urls.length;
      final changed = !_sameContent(p);
      Object? saveError;
      try {
        await _persist(p, now);
      } catch (e) {
        saveError = e;
      }
      _swap(p);
      if (saveError == null) {
        _updated = now;
        _memoryOnly = false;
        return _finish(FeedUpdateReport(
          status: changed ? FeedUpdateStatus.updated : FeedUpdateStatus.unchanged,
          countBefore: before,
          countAfter: _urls.length,
          time: now,
          source: feedUrl,
          changed: changed,
          downloaded: true,
          persisted: true,
        ));
      }
      _memoryOnly = true;
      return _finish(FeedUpdateReport(
        status: FeedUpdateStatus.updatedNotSaved,
        countBefore: before,
        countAfter: _urls.length,
        time: now,
        source: feedUrl,
        changed: changed,
        downloaded: true,
        persisted: false,
        error:
            'اتنزّلت خلاصة صالحة لكن تعذّر حفظها على الجهاز. القاعدة الجديدة شغّالة لحد ما تقفل التطبيق، وبعدها هترجع للنسخة المحفوظة قبل كده.',
      ));
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// يفحص رابطًا: تطابق كامل ← مضيف ← دومين أساسي.
  FeedMatch? match(String url) {
    if (_urls.isEmpty) return null;
    final n = normalize(url);
    if (_urls.contains(n)) return const FeedMatch('exact', 90);
    final host = _hostOf(n);
    if (host.isEmpty || UrlAnalyzer.isSharedHost(host)) return null;
    if (_hosts.contains(host)) return const FeedMatch('host', 70);
    final d = UrlAnalyzer.registrableDomain(host);
    if (_domains.contains(d)) return const FeedMatch('domain', 45);
    return null;
  }
}
