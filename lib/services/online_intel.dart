import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/app_info.dart';
import '../core/models.dart';
import 'http_util.dart';
import 'threat_feed.dart';

/// حالة نتيجة مصدر تهديدات واحد.
///
///  - clean: المصدر اشتغل ومارصدش الرابط (مش معناها "آمن").
///  - hit: المصدر رصد تهديد أو مؤشر.
///  - info: المصدر اشتغل بس مفيش بيانات كفاية (مثلًا VirusTotal ما فحصش الرابط قبل كده).
///  - skipped: المصدر مش منطبق على المدخل (عنوان IP، رابط مختصر، امتداد بدون RDAP).
///  - notConfigured: الخدمة غير مُعدّة (مفتاح API ناقص أو قاعدة OpenPhish غير محمّلة):
///    الرابط ما اتفحصش بيها، وده مش معناه إنه نظيف ولا بيتحسب كفشل في الفحص.
///  - error: المصدر فشل (مهلة / شبكة / مفتاح مرفوض / رد غير مفهوم): الفحص ناقص.
///    مفيش نقاط ولا حكم "نظيف" بيتبني على الحالة دي.
enum IntelStatus { clean, hit, info, skipped, notConfigured, error }

class IntelResult {
  const IntelResult({
    required this.source,
    required this.status,
    required this.message,
    this.findings = const <Finding>[],
  });

  final String source;
  final IntelStatus status;
  final String message;
  final List<Finding> findings;
}

/// مصادر الاستعلام الحي. كل دالة لا ترمي استثناء: تعيد IntelResult دائمًا.
class OnlineIntel {
  OnlineIntel._();

  static const String _notConfiguredMsg =
      'الخدمة غير مُعدّة: أضف مفتاح API من تبويب أدوات. الرابط ما اتفحصش بها، وده لا يعني إنه نظيف.';
  static const String _badKeyMsg =
      'شكل المفتاح غير صالح (مسافات أو رموز غير مسموحة). لم يُرسل شيء. أعد إدخاله من تبويب أدوات.';

  /// فحص شكلي بس للمفتاح قبل ما نبعته: ASCII مطبوع من غير مسافات أو رموز تحكم، وطول معقول.
  /// الهدف إن مفتاح معطوب (فيه سطر جديد مثلًا) ما يتحوّلش لرد "غير متوقع" مبهم أو يتبعت كهيدر شاذ.
  /// ما بنفرضش صيغة معينة لأن شكل مفاتيح الخدمات ممكن يتغيّر.
  static final RegExp _keyShape = RegExp(r'^[\x21-\x7E]{8,512}$');
  static bool isPlausibleApiKey(String key) => _keyShape.hasMatch(key);

  // ---- قاعدة OpenPhish المحلية ----------------------------------------
  static IntelResult feed(String url) {
    const src = 'OpenPhish (محلي)';
    final f = ThreatFeed.instance;
    if (f.count == 0) {
      return const IntelResult(
        source: src,
        status: IntelStatus.notConfigured,
        message: 'القاعدة غير محمّلة، فالرابط ما اتفحصش بها. حدّثها من تبويب أدوات.',
      );
    }
    final m = f.match(url);
    if (m == null) {
      return IntelResult(
        source: src,
        status: IntelStatus.clean,
        message: 'غير مدرج في قائمة التصيّد (${f.count} رابط). القائمة لا تغطي كل الروابط.',
      );
    }
    final String why;
    switch (m.kind) {
      case 'exact':
        why = 'الرابط نفسه مدرج كتصيّد نشط.';
        break;
      case 'host':
        why = 'هذا الموقع مدرج كمصدر تصيّد.';
        break;
      default:
        why = 'الدومين الأساسي مدرج في روابط تصيّد.';
    }
    return IntelResult(
      source: src,
      status: IntelStatus.hit,
      message: why,
      findings: <Finding>[
        Finding(
          severity: Severity.danger,
          title: 'مدرج في قائمة التصيّد (OpenPhish)',
          detail: why,
          points: m.points,
          // تطابق الرابط نفسه فقط يعتبر تأكيد؛ تطابق المضيف/الدومين اشتباه قوي
          confirmed: m.kind == 'exact',
        ),
      ],
    );
  }

  // ---- عمر الدومين (RDAP) ---------------------------------------------
  static String _fmtAge(int days) {
    if (days < 60) return '$days يوم';
    if (days < 730) return '${(days / 30).round()} شهر';
    return '${(days / 365).floor()} سنة';
  }

  static final RegExp _asciiDomain =
      RegExp(r'^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$');

  static final RegExp _numericOnly = RegExp(r'^[0-9.]+$');

  static Future<IntelResult> rdap(String domain) async {
    const src = 'عمر الدومين (RDAP)';
    // الدومين لازم يوصل ASCII (punycode للأسماء الدولية) وبشكل اسم مضيف عادي؛ أي شيء تاني ما بنبعتوش.
    if (!_asciiDomain.hasMatch(domain) || _numericOnly.hasMatch(domain)) {
      return const IntelResult(
        source: src,
        status: IntelStatus.skipped,
        message: 'لا ينطبق: الاسم ليس دومينًا قياسيًا قابلًا للاستعلام.',
      );
    }
    try {
      final r = await httpRequest(
        'GET',
        Uri(scheme: 'https', host: 'rdap.org', pathSegments: <String>['domain', domain]),
        headers: <String, String>{'accept': 'application/rdap+json, application/json'},
        timeout: const Duration(seconds: 12),
        maxBytes: 1024 * 1024,
      );
      if (r.status == 404) {
        return const IntelResult(
          source: src,
          status: IntelStatus.skipped,
          message: 'لا توجد بيانات RDAP لهذا الامتداد.',
        );
      }
      if (r.status != 200) {
        return IntelResult(
          source: src,
          status: IntelStatus.error,
          message: 'تعذر الاستعلام (${r.status}).',
        );
      }
      final j = jsonDecode(r.body);
      DateTime? reg;
      if (j is Map && j['events'] is List) {
        for (final e in (j['events'] as List)) {
          if (e is Map && e['eventAction'] == 'registration') {
            reg = DateTime.tryParse('${e['eventDate']}');
            break;
          }
        }
      }
      if (reg == null) {
        return const IntelResult(
          source: src,
          status: IntelStatus.skipped,
          message: 'لم يُرجع السجل تاريخ التسجيل.',
        );
      }
      final days = DateTime.now().toUtc().difference(reg.toUtc()).inDays;
      final age = _fmtAge(days < 0 ? 0 : days);
      if (days < 7) {
        return IntelResult(
          source: src,
          status: IntelStatus.hit,
          message: 'الدومين عمره $age فقط.',
          findings: <Finding>[
            Finding(
              severity: Severity.danger,
              title: 'دومين جديد جدًا ($age)',
              detail: 'معظم حملات التصيّد تستخدم دومينات عمرها أيام. مؤشر قوي.',
              points: 40,
            ),
          ],
        );
      }
      if (days < 30) {
        return IntelResult(
          source: src,
          status: IntelStatus.hit,
          message: 'الدومين عمره $age.',
          findings: <Finding>[
            Finding(
              severity: Severity.danger,
              title: 'دومين حديث ($age)',
              detail: 'الدومينات الأقل من شهر أكثر عرضة للاستخدام في الاحتيال.',
              points: 30,
            ),
          ],
        );
      }
      if (days < 90) {
        return IntelResult(
          source: src,
          status: IntelStatus.hit,
          message: 'الدومين عمره $age.',
          findings: <Finding>[
            Finding(
              severity: Severity.warn,
              title: 'دومين حديث نسبيًا ($age)',
              detail: 'عمر أقل من 3 شهور. ليس دليلًا بذاته لكنه يستحق الحذر.',
              points: 15,
            ),
          ],
        );
      }
      if (days < 365) {
        return IntelResult(
          source: src,
          status: IntelStatus.info,
          message: 'الدومين عمره $age.',
          findings: <Finding>[
            Finding(
              severity: Severity.info,
              title: 'عمر الدومين $age',
              detail: 'أقل من سنة.',
              points: 5,
            ),
          ],
        );
      }
      return IntelResult(
        source: src,
        status: IntelStatus.clean,
        message: 'الدومين عمره $age.',
        findings: <Finding>[
          Finding(
            severity: Severity.good,
            title: 'دومين قديم ($age)',
            detail: 'عمر الدومين لا يضمن الأمان لكنه أقل شيوعًا في الاحتيال.',
          ),
        ],
      );
    } on TimeoutException {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: 'انتهت المهلة.',
      );
    } on SocketException {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: 'لا يوجد اتصال بالإنترنت.',
      );
    } catch (_) {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: 'رد غير متوقع من RDAP.',
      );
    }
  }

  // ---- Google Safe Browsing (مفتاحك) ----------------------------------
  static String _gsbType(String t) {
    switch (t) {
      case 'MALWARE':
        return 'برمجيات خبيثة';
      case 'SOCIAL_ENGINEERING':
        return 'تصيّد / هندسة اجتماعية';
      case 'UNWANTED_SOFTWARE':
        return 'برامج غير مرغوبة';
      case 'POTENTIALLY_HARMFUL_APPLICATION':
        return 'تطبيقات ضارة';
      default:
        return t;
    }
  }

  static Future<IntelResult> safeBrowsing(String url, String key) async {
    const src = 'Google Safe Browsing';
    if (key.isEmpty) {
      return const IntelResult(
        source: src,
        status: IntelStatus.notConfigured,
        message: _notConfiguredMsg,
      );
    }
    if (!isPlausibleApiKey(key)) {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: _badKeyMsg,
      );
    }
    try {
      final body = jsonEncode(<String, dynamic>{
        'client': <String, String>{
          'clientId': 'cobra-shield',
          'clientVersion': kAppVersion,
        },
        'threatInfo': <String, dynamic>{
          'threatTypes': <String>[
            'MALWARE',
            'SOCIAL_ENGINEERING',
            'UNWANTED_SOFTWARE',
            'POTENTIALLY_HARMFUL_APPLICATION',
          ],
          'platformTypes': <String>['ANY_PLATFORM'],
          'threatEntryTypes': <String>['URL'],
          'threatEntries': <Map<String, String>>[
            <String, String>{'url': url},
          ],
        },
      });
      final r = await httpRequest(
        'POST',
        Uri.parse(
          'https://safebrowsing.googleapis.com/v4/threatMatches:find?key=${Uri.encodeQueryComponent(key)}',
        ),
        headers: <String, String>{'content-type': 'application/json'},
        body: body,
        timeout: const Duration(seconds: 12),
      );
      if (r.status == 400 || r.status == 401 || r.status == 403) {
        return const IntelResult(
          source: src,
          status: IntelStatus.error,
          message: 'المفتاح غير صالح أو الخدمة غير مفعّلة في مشروعك.',
        );
      }
      if (r.status == 429) {
        return const IntelResult(
          source: src,
          status: IntelStatus.error,
          message: 'تجاوزت حد الطلبات. جرّب لاحقًا.',
        );
      }
      if (r.status != 200) {
        return IntelResult(
          source: src,
          status: IntelStatus.error,
          message: 'رد غير متوقع (${r.status}).',
        );
      }
      final j = jsonDecode(r.body);
      final matches = (j is Map && j['matches'] is List)
          ? (j['matches'] as List)
          : const <dynamic>[];
      if (matches.isEmpty) {
        return const IntelResult(
          source: src,
          status: IntelStatus.clean,
          message: 'غير مدرج في قوائم Google.',
          findings: <Finding>[
            Finding(
              severity: Severity.good,
              title: 'لم يُدرج لدى Google Safe Browsing',
              detail: 'لا يعني أنه آمن، فقد يكون التهديد جديدًا لم يُرصد بعد.',
            ),
          ],
        );
      }
      final first = matches.first;
      final type = (first is Map && first['threatType'] is String)
          ? _gsbType(first['threatType'] as String)
          : 'تهديد';
      return IntelResult(
        source: src,
        status: IntelStatus.hit,
        message: 'Google يصنّفه: $type.',
        findings: <Finding>[
          Finding(
            severity: Severity.danger,
            title: 'Google Safe Browsing: موقع غير آمن',
            detail: 'التصنيف: $type.',
            points: 80,
            confirmed: true,
          ),
        ],
      );
    } on TimeoutException {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: 'انتهت المهلة.',
      );
    } on SocketException {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: 'لا يوجد اتصال بالإنترنت.',
      );
    } catch (_) {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: 'رد غير متوقع.',
      );
    }
  }

  // ---- VirusTotal (مفتاحك) --------------------------------------------
  static Future<IntelResult> virusTotal(String url, String key) async {
    const src = 'VirusTotal';
    if (key.isEmpty) {
      return const IntelResult(
        source: src,
        status: IntelStatus.notConfigured,
        message: _notConfiguredMsg,
      );
    }
    if (!isPlausibleApiKey(key)) {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: _badKeyMsg,
      );
    }
    try {
      final id = base64Url.encode(utf8.encode(url)).replaceAll('=', '');
      final r = await httpRequest(
        'GET',
        Uri.parse('https://www.virustotal.com/api/v3/urls/$id'),
        headers: <String, String>{'x-apikey': key},
        timeout: const Duration(seconds: 12),
      );
      if (r.status == 404) {
        return const IntelResult(
          source: src,
          status: IntelStatus.info,
          message: 'الرابط لم يُفحص من قبل لدى VirusTotal.',
        );
      }
      if (r.status == 401 || r.status == 403) {
        return const IntelResult(
          source: src,
          status: IntelStatus.error,
          message: 'مفتاح VirusTotal غير صالح.',
        );
      }
      if (r.status == 429) {
        return const IntelResult(
          source: src,
          status: IntelStatus.error,
          message: 'تجاوزت حد الطلبات (المفتاح المجاني 4 طلبات/دقيقة).',
        );
      }
      if (r.status != 200) {
        return IntelResult(
          source: src,
          status: IntelStatus.error,
          message: 'رد غير متوقع (${r.status}).',
        );
      }
      final j = jsonDecode(r.body);
      Map<dynamic, dynamic>? stats;
      if (j is Map && j['data'] is Map) {
        final attrs = (j['data'] as Map)['attributes'];
        if (attrs is Map && attrs['last_analysis_stats'] is Map) {
          stats = attrs['last_analysis_stats'] as Map;
        }
      }
      if (stats == null) {
        return const IntelResult(
          source: src,
          status: IntelStatus.info,
          message: 'لا توجد نتائج تحليل بعد.',
        );
      }
      int n(String k) {
        final v = stats![k];
        return v is int ? v : 0;
      }

      final mal = n('malicious');
      final sus = n('suspicious');
      final total = mal + sus + n('harmless') + n('undetected');
      if (mal >= 3) {
        return IntelResult(
          source: src,
          status: IntelStatus.hit,
          message: '$mal من $total محرك يعتبره خبيثًا.',
          findings: <Finding>[
            Finding(
              severity: Severity.danger,
              title: 'VirusTotal: $mal محرك يرصده',
              detail: 'عدد كبير من محركات الفحص صنّفته خبيثًا.',
              points: 70,
              confirmed: true,
            ),
          ],
        );
      }
      if (mal >= 1) {
        return IntelResult(
          source: src,
          status: IntelStatus.hit,
          message: '$mal من $total محرك يعتبره خبيثًا.',
          findings: <Finding>[
            Finding(
              severity: Severity.warn,
              title: 'VirusTotal: $mal محرك يرصده',
              detail: 'عدد قليل من المحركات صنّفته خبيثًا. قد يكون إنذارًا كاذبًا، لكن تعامل بحذر.',
              points: 35,
            ),
          ],
        );
      }
      if (sus >= 1) {
        return IntelResult(
          source: src,
          status: IntelStatus.hit,
          message: '$sus محرك يراه مشبوهًا.',
          findings: <Finding>[
            Finding(
              severity: Severity.warn,
              title: 'VirusTotal: مشبوه عند $sus محرك',
              detail: 'لا تصنيف خبيث صريح لكن هناك شبهات.',
              points: 20,
            ),
          ],
        );
      }
      return IntelResult(
        source: src,
        status: IntelStatus.clean,
        message: 'لا محرك رصده (من $total).',
        findings: const <Finding>[
          Finding(
            severity: Severity.good,
            title: 'VirusTotal: لا رصد',
            detail: 'لم يرصده أي محرك، وهذا لا يضمن الأمان.',
          ),
        ],
      );
    } on TimeoutException {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: 'انتهت المهلة.',
      );
    } on SocketException {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: 'لا يوجد اتصال بالإنترنت.',
      );
    } catch (_) {
      return const IntelResult(
        source: src,
        status: IntelStatus.error,
        message: 'رد غير متوقع.',
      );
    }
  }
}
