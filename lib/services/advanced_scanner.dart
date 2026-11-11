import '../core/knowledge.dart';
import '../core/models.dart';
import 'link_expander.dart';
import 'online_intel.dart';
import 'settings_store.dart';
import 'url_analyzer.dart';

class AdvancedReport {
  const AdvancedReport({
    required this.expand,
    required this.finalLocal,
    required this.intel,
    required this.combinedScore,
  });

  final ExpandResult expand;
  final ScanResult? finalLocal; // تحليل الوجهة النهائية لو اختلفت عن الأصل
  final List<IntelResult> intel;
  final int combinedScore;

  /// مصادر فشلت (مش اللي اتخطت لعدم وجود مفتاح): يعني الفحص ناقص.
  /// تتبع التحويلات بيتحسب هنا لو ما اتممش (خطأ شبكة، أو الحارس منع الاتصال).
  List<String> get failedSources => <String>[
        if (expand.error != null) 'تتبع التحويلات',
        for (final r in intel)
          if (r.status == IntelStatus.error) r.source,
      ];

  /// الفحص المتقدم ما اكتملش: النتيجة مبنية على اللي اشتغل بس.
  bool get partial => failedSources.isNotEmpty;

  /// نتيجة موحدة: درجة مجمّعة + كل المؤشرات بدون تكرار
  ScanResult toResult(ScanResult local) {
    final seen = <String>{};
    final all = <Finding>[];
    void add(Iterable<Finding> list) {
      for (final f in list) {
        if (seen.add(f.title)) all.add(f);
      }
    }

    if (expand.blockedOnRedirect) {
      add(<Finding>[
        Finding(
          code: 'redirect_to_internal',
          severity: Severity.danger,
          title: 'الرابط بيحوّل لوجهة داخلية أو غير آمنة',
          detail: '${expand.error ?? ''}\nرابط خارجي بيوجّه لعنوان محلي/داخلي أسلوب هجوم معروف.',
          points: AdvancedScanner.blockedRedirectPoints,
        ),
      ]);
    }
    if (expand.hostUnreachable) {
      // الموقع غير متاح (DNS/مهلة/اتصال): حالة مستقلة، مش دليل تصيّد ومالهاش نقاط.
      add(<Finding>[
        Finding(
          code: 'host_unreachable',
          severity: Severity.info,
          title: 'تعذّر الوصول للموقع',
          detail:
              '${expand.error ?? ''}\nعدم الوصول للموقع ليس دليلًا على التصيّد (قد يكون الموقع متوقفًا أو الإنترنت ضعيفًا)، وليس دليلًا على الأمان أيضًا: الوجهة النهائية للرابط غير معروفة.',
        ),
      ]);
    } else if (expand.failure == ExpandFailure.tls) {
      add(<Finding>[
        Finding(
          code: 'tls_invalid',
          severity: Severity.info,
          title: 'شهادة الأمان (SSL) غير صالحة',
          detail:
              '${expand.error ?? ''}\nمواقع حقيقية كتير عندها شهادة منتهية أو غلط إعداد، فمش بنعتبره تصيّد لوحده، لكن لا تدخل أي بيانات في موقع شهادته غير صالحة.',
        ),
      ]);
    } else if (AdvancedScanner.isRedirectAnomaly(expand)) {
      add(<Finding>[
        Finding(
          code: 'redirect_anomaly',
          severity: Severity.warn,
          title: 'تحويلات غير طبيعية',
          detail: '${expand.error ?? ''}',
          points: AdvancedScanner.redirectAnomalyPoints,
          family: kFamilyWeak,
        ),
      ]);
    }
    if (partial) {
      add(<Finding>[
        Finding(
          severity: Severity.warn,
          title: 'الفحص المتقدم غير مكتمل',
          detail:
              'تعذر: ${failedSources.join('، ')}. النتيجة مبنية على المصادر اللي اشتغلت بس، وفشل مصدر لا يعني إن الرابط آمن.',
        ),
      ]);
    }
    for (final r in intel) {
      add(r.findings);
    }
    add(finalLocal?.findings ?? const <Finding>[]);
    add(local.findings);
    all.sort((a, b) => b.points.compareTo(a.points));
    return ScanResult(
      kind: ScanKind.url,
      score: combinedScore,
      findings: all,
      parts: finalLocal?.parts ?? local.parts,
      title: local.title,
      partial: partial,
    );
  }
}

/// الفحص المتقدم: تتبع التحويلات ثم استعلام مصادر التهديدات عن الوجهة النهائية.
class AdvancedScanner {
  AdvancedScanner._();

  static final RegExp _ipLike = RegExp(r'^[\d.]+$');

  /// نقاط الخطر لو رابط خارجي حوّل لوجهة داخلية/غير آمنة.
  static const int blockedRedirectPoints = 30;

  /// حلقة تحويلات / تحويلات أكتر من الحد / عنوان تحويلة غير صالح: إشارة ضعيفة.
  static const int redirectAnomalyPoints = 6;

  static bool isRedirectAnomaly(ExpandResult r) =>
      r.failure == ExpandFailure.loop ||
      r.failure == ExpandFailure.tooManyHops ||
      r.failure == ExpandFailure.badRedirect;

  static Future<AdvancedReport> run(
    ScanResult local, {
    void Function(String step)? onStep,
  }) async {
    final parts = local.parts;
    if (parts == null) {
      throw StateError('no parts');
    }

    onStep?.call('تتبع التحويلات...');
    final expand = await LinkExpander.expand(parts.normalizedUrl);

    ScanResult? fin;
    var targetUrl = parts.normalizedUrl;
    var target = parts;
    if (expand.error == null && expand.redirected) {
      final analyzed = UrlAnalyzer.analyze(expand.finalUrl);
      // وجهة نهائية مش رابط صالح: مفيش تحليل ليها (بنكمل بالرابط الأصلي).
      if (analyzed.hasScore && analyzed.parts != null) {
        fin = analyzed;
        targetUrl = expand.finalUrl;
        target = analyzed.parts!;
      }
    }

    onStep?.call('الاستعلام من مصادر التهديدات...');
    final s = SettingsStore.instance;
    final host = target.host;
    final isIp = _ipLike.hasMatch(host) || host.contains(':');
    final skipAge = isIp || kShorteners.contains(host);

    final results = <Future<IntelResult>>[
      Future<IntelResult>.value(OnlineIntel.feed(targetUrl)),
      if (!skipAge)
        OnlineIntel.rdap(target.domain)
      else
        Future<IntelResult>.value(const IntelResult(
          source: 'عمر الدومين (RDAP)',
          status: IntelStatus.skipped,
          message: 'لا ينطبق على عنوان IP أو رابط مختصر.',
        )),
      OnlineIntel.safeBrowsing(targetUrl, s.gsbKey),
      OnlineIntel.virusTotal(targetUrl, s.vtKey),
    ];
    final intel = await Future.wait<IntelResult>(results);

    var add = expand.blockedOnRedirect ? blockedRedirectPoints : 0;
    if (isRedirectAnomaly(expand)) add += redirectAnomalyPoints;
    for (final r in intel) {
      for (final f in r.findings) {
        add += f.points;
      }
    }
    final base = fin != null && fin.score > local.score ? fin.score : local.score;
    var combined = base + add;
    if (combined < 0) combined = 0;
    if (combined > 100) combined = 100;

    return AdvancedReport(
      expand: expand,
      finalLocal: fin,
      intel: intel,
      combinedScore: combined,
    );
  }
}
