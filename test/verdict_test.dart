import 'package:cobra_shield/core/models.dart';
import 'package:cobra_shield/services/advanced_scanner.dart';
import 'package:cobra_shield/services/link_expander.dart';
import 'package:cobra_shield/services/online_intel.dart';
import 'package:cobra_shield/services/url_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

ScanResult res(
  int score, {
  List<Finding> findings = const <Finding>[],
  bool partial = false,
  List<ScanResult> links = const <ScanResult>[],
}) =>
    ScanResult(
      kind: ScanKind.url,
      score: score,
      findings: findings,
      partial: partial,
      links: links,
    );

const Finding _confirmed = Finding(
  severity: Severity.danger,
  title: 'مؤكد',
  detail: 'x',
  points: 80,
  confirmed: true,
);

void main() {
  group('Verdict', () {
    test('فحص كامل بدون علامات: لا مؤشرات (مش "آمن")', () {
      final r = res(0);
      expect(r.verdict, Verdict.noIndicators);
      expect(r.headline, 'لا مؤشرات واضحة');
      expect(Verdict.noIndicators.advice, contains('لا يعني أنه آمن'));
    });

    test('فحص ناقص بدون علامات: "فحص جزئي" (مش "لا مؤشرات")', () {
      final r = res(0, partial: true);
      expect(r.verdict, Verdict.partialScan);
      expect(r.headline, 'فحص جزئي');
    });

    test('محتوى قليل بدون فحص ناقص: معلومات غير كافية', () {
      final r = ScanResult(
        kind: ScanKind.message,
        score: 0,
        findings: const <Finding>[],
        insufficientInfo: true,
      );
      expect(r.verdict, Verdict.insufficient);
      expect(r.headline, 'معلومات غير كافية');
    });

    test('اشتباه: بيستخدم المستوى التفصيلي', () {
      expect(res(25).verdict, Verdict.suspicious);
      expect(res(25).headline, 'مشبوه');
      expect(res(50).headline, 'خطير');
      expect(res(80).headline, 'احتيال مرجّح');
    });

    test('الفحص الناقص لا يخفي اشتباه موجود', () {
      expect(res(30, partial: true).verdict, Verdict.suspicious);
    });

    test('علامة "مؤكد" تغلب كل حاجة حتى لو الدرجة منخفضة', () {
      final r = res(5, findings: const <Finding>[_confirmed]);
      expect(r.verdict, Verdict.confirmedThreat);
      expect(r.headline, 'تهديد مؤكد');
    });

    test('رسالة فيها رابط مؤكد أو رابط ناقص', () {
      final msg = ScanResult(
        kind: ScanKind.message,
        score: 0,
        findings: const <Finding>[],
        links: <ScanResult>[res(5, findings: const <Finding>[_confirmed])],
      );
      expect(msg.verdict, Verdict.confirmedThreat);
      final msg2 = ScanResult(
        kind: ScanKind.message,
        score: 0,
        findings: const <Finding>[],
        links: <ScanResult>[res(0, partial: true)],
      );
      expect(msg2.verdict, Verdict.partialScan);
    });

    test('التقرير بيعكس الحكم', () {
      expect(res(5, findings: const <Finding>[_confirmed]).toReport(), contains('تهديد مؤكد'));
      final partial = res(0, partial: true).toReport();
      expect(partial, contains('فحص جزئي'));
      expect(partial, contains('تنبيه'));
    });
  });

  group('AdvancedReport', () {
    final local = res(0);

    test('مصدر فشل: الفحص جزئي والحكم "فحص جزئي"', () {
      const report = AdvancedReport(
        expand: ExpandResult(chain: <String>['https://a.example.com/']),
        finalLocal: null,
        intel: <IntelResult>[
          IntelResult(source: 'VirusTotal', status: IntelStatus.error, message: 'x'),
          IntelResult(source: 'OpenPhish (محلي)', status: IntelStatus.clean, message: 'x'),
        ],
        combinedScore: 0,
      );
      expect(report.partial, isTrue);
      expect(report.failedSources, <String>['VirusTotal']);
      final r = report.toResult(local);
      expect(r.partial, isTrue);
      expect(r.verdict, Verdict.partialScan);
      expect(r.findings.any((f) => f.title == 'الفحص المتقدم غير مكتمل'), isTrue);
    });

    test('مصدر "notConfigured" (بدون مفتاح) مش فشل ومش بيتحسب نظيف', () {
      const report = AdvancedReport(
        expand: ExpandResult(chain: <String>['https://a.example.com/']),
        finalLocal: null,
        intel: <IntelResult>[
          IntelResult(source: 'VirusTotal', status: IntelStatus.notConfigured, message: 'x'),
        ],
        combinedScore: 0,
      );
      expect(report.partial, isFalse);
      expect(report.toResult(local).verdict, Verdict.noIndicators);
    });

    test('فشل تتبع التحويلات = جزئي', () {
      const report = AdvancedReport(
        expand: ExpandResult(chain: <String>['https://a.example.com/'], error: 'تعذر'),
        finalLocal: null,
        intel: <IntelResult>[],
        combinedScore: 0,
      );
      expect(report.failedSources, <String>['تتبع التحويلات']);
      expect(report.toResult(local).verdict, Verdict.partialScan);
    });

    test('تحويلة لوجهة داخلية = علامة خطر', () {
      const report = AdvancedReport(
        expand: ExpandResult(
          chain: <String>['https://a.example.com/', 'http://10.0.0.1/'],
          error: 'تحويلة رقم 1 تشير لوجهة غير آمنة',
          blockedHop: 1,
        ),
        finalLocal: null,
        intel: <IntelResult>[],
        combinedScore: AdvancedScanner.blockedRedirectPoints,
      );
      final r = report.toResult(local);
      final f = r.findings.firstWhere((x) => x.title.contains('وجهة داخلية'));
      expect(f.severity, Severity.danger);
      expect(f.points, AdvancedScanner.blockedRedirectPoints);
      expect(r.verdict, Verdict.suspicious);
    });

    test('مصدر موثوق أكّد التهديد = تهديد مؤكد', () {
      const hit = IntelResult(
        source: 'Google Safe Browsing',
        status: IntelStatus.hit,
        message: 'x',
        findings: <Finding>[_confirmed],
      );
      const report = AdvancedReport(
        expand: ExpandResult(chain: <String>['https://a.example.com/']),
        finalLocal: null,
        intel: <IntelResult>[hit],
        combinedScore: 80,
      );
      expect(report.toResult(local).verdict, Verdict.confirmedThreat);
    });
  });

  group('AdvancedScanner.run (بدون شبكة)', () {
    test('رابط IP محلي: الحارس يمنع الاتصال والفحص يطلع جزئي', () async {
      final local = UrlAnalyzer.analyze('http://127.0.0.1/login');
      final report = await AdvancedScanner.run(local);
      expect(report.expand.blocked, isTrue);
      expect(report.expand.blockedHop, 0);
      expect(report.partial, isTrue);
      expect(report.toResult(local).partial, isTrue);
    });
  });
}
