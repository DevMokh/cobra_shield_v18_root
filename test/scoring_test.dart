import 'package:cobra_shield/core/models.dart';
import 'package:cobra_shield/services/url_report.dart';
import 'package:flutter_test/flutter_test.dart';

// المقياس الموحّد: حدود المستويات، تجميع الإشارات (aggregateScore)، وحالات الحكم.
// القيم متتبّعة يدويًا من models.dart؛ أول تشغيل فعلي في الـ CI.
Finding _f(String code, int points, {String family = '', Severity sev = Severity.warn, bool confirmed = false}) =>
    Finding(
      severity: sev,
      title: code,
      detail: '',
      points: points,
      code: code,
      family: family,
      confirmed: confirmed,
    );

void main() {
  group('حدود المستويات (مصدر واحد)', () {
    test('قيم الحدود', () {
      expect(kBandMedium, 20);
      expect(kBandHigh, 45);
      expect(kBandCritical, 70);
      // الإشارات الضعيفة مهما اتراكمت أقل من "مشبوه".
      expect(kWeakFamilyCap, lessThan(kBandMedium));
    });

    test('حواف كل مستوى', () {
      expect(levelForScore(0), RiskLevel.low);
      expect(levelForScore(19), RiskLevel.low);
      expect(levelForScore(20), RiskLevel.medium);
      expect(levelForScore(44), RiskLevel.medium);
      expect(levelForScore(45), RiskLevel.high);
      expect(levelForScore(69), RiskLevel.high);
      expect(levelForScore(70), RiskLevel.critical);
      expect(levelForScore(100), RiskLevel.critical);
    });

    test('تصنيف الرابط (tier) متطابق مع المستوى في كل الدرجات 0..100', () {
      for (var s = 0; s <= 100; s++) {
        final level = levelForScore(s);
        final tier = tierForScore(s);
        final expected = level == RiskLevel.low
            ? ThreatTier.safe
            : level == RiskLevel.medium
                ? ThreatTier.suspicious
                : ThreatTier.dangerous;
        expect(tier, expected, reason: 'score=$s');
      }
    });

    test('عنصر السجل بيستخدم نفس الحدود', () {
      for (final s in <int>[0, 19, 20, 44, 45, 69, 70, 100]) {
        final h = HistoryItem(id: 1, kind: ScanKind.url, title: 't', score: s, time: DateTime(2026));
        expect(h.level, levelForScore(s));
      }
    });
  });

  group('aggregateScore', () {
    test('قائمة فاضية = 0', () {
      expect(aggregateScore(const <Finding>[]), 0);
    });

    test('نفس الـ code متكرر: بيتحسب مرة واحدة (الأعلى نقاطًا)', () {
      expect(aggregateScore(<Finding>[_f('a', 10), _f('a', 25), _f('a', 5)]), 25);
    });

    test('codes مختلفة: بتتجمع', () {
      expect(aggregateScore(<Finding>[_f('a', 10), _f('b', 15)]), 25);
    });

    test('الإشارات الضعيفة: مجموعها بيتقصّ عند kWeakFamilyCap', () {
      final weak = <Finding>[
        _f('w1', 5, family: kFamilyWeak),
        _f('w2', 5, family: kFamilyWeak),
        _f('w3', 5, family: kFamilyWeak),
        _f('w4', 5, family: kFamilyWeak),
      ];
      expect(aggregateScore(weak), kWeakFamilyCap);
      expect(levelForScore(aggregateScore(weak)), RiskLevel.low);
    });

    test('الضعيفة تحت السقف بتتحسب زي ما هي', () {
      expect(aggregateScore(<Finding>[_f('w1', 3, family: kFamilyWeak), _f('w2', 4, family: kFamilyWeak)]), 7);
    });

    test('ضعيفة + قوية: القوية كاملة والضعيفة بسقفها', () {
      final f = <Finding>[
        _f('s', 15),
        _f('w1', 8, family: kFamilyWeak),
        _f('w2', 8, family: kFamilyWeak),
      ];
      expect(aggregateScore(f), 15 + kWeakFamilyCap);
    });

    test('نفس الـ code ضعيف مكرر ما بيتضاعفش', () {
      expect(aggregateScore(<Finding>[_f('w', 5, family: kFamilyWeak), _f('w', 5, family: kFamilyWeak)]), 5);
    });

    test('إشارات بدون code (قديمة) بتتحسب كلها', () {
      const a = Finding(severity: Severity.warn, title: 'x', detail: '', points: 7);
      const b = Finding(severity: Severity.warn, title: 'x', detail: '', points: 7);
      expect(aggregateScore(const <Finding>[a, b]), 14);
    });

    test('السقف 100 وما تحتش الصفر', () {
      expect(aggregateScore(<Finding>[_f('a', 80), _f('b', 80)]), 100);
      expect(aggregateScore(<Finding>[_f('a', -30)]), 0);
    });

    test('إشارة بصفر نقاط ما بتغيّرش الدرجة', () {
      expect(aggregateScore(<Finding>[_f('a', 0), _f('b', 12)]), 12);
    });
  });

  group('حالات الحكم (Verdict)', () {
    ScanResult res({
      int score = 0,
      List<Finding> findings = const <Finding>[],
      bool partial = false,
      bool insufficient = false,
      List<ScanResult> links = const <ScanResult>[],
    }) =>
        ScanResult(
          kind: ScanKind.message,
          score: score,
          findings: findings,
          partial: partial,
          insufficientInfo: insufficient,
          links: links,
        );

    test('إدخال غير صالح: مفيش درجة', () {
      final r = ScanResult.invalid(kind: ScanKind.url, issueCode: 'not_a_url', detail: 'x');
      expect(r.verdict, Verdict.invalidInput);
      expect(r.hasScore, isFalse);
      expect(r.state, ScanState.invalidInput);
      expect(r.toReport(), contains('بدون درجة خطر'));
      expect(r.toReport(), isNot(contains('درجة الخطر: ')));
    });

    test('فشل التحليل: حالة مستقلة وجزئي', () {
      final r = ScanResult.failed(kind: ScanKind.url, detail: 'x');
      expect(r.verdict, Verdict.analysisFailed);
      expect(r.partial, isTrue);
      expect(r.hasScore, isFalse);
    });

    test('تهديد مؤكد (finding.confirmed) حتى لو الدرجة صفر', () {
      final r = res(findings: <Finding>[_f('gsb', 0, confirmed: true)]);
      expect(r.verdict, Verdict.confirmedThreat);
    });

    test('درجة ≥ مشبوه = suspicious، والعنوان بيستخدم المستوى التفصيلي', () {
      expect(res(score: 20).verdict, Verdict.suspicious);
      expect(res(score: 20).headline, RiskLevel.medium.label);
      expect(res(score: 50).headline, RiskLevel.high.label);
      expect(res(score: 80).headline, RiskLevel.critical.label);
    });

    test('درجة منخفضة وفحص كامل = لا مؤشرات (مش "آمن")', () {
      final r = res(score: 5);
      expect(r.verdict, Verdict.noIndicators);
      expect(r.headline, 'لا مؤشرات واضحة');
      expect(r.headline, isNot(contains('آمن')));
    });

    test('فحص ناقص بدون علامات: فحص جزئي (مش لا مؤشرات)', () {
      expect(res(partial: true).verdict, Verdict.partialScan);
    });

    test('محتوى قليل: معلومات غير كافية', () {
      expect(res(insufficient: true).verdict, Verdict.insufficient);
    });

    test('الأولوية: مشبوه يغلب الجزئي، والمؤكد يغلب كل حاجة', () {
      expect(res(score: 30, partial: true).verdict, Verdict.suspicious);
      expect(res(partial: true, findings: <Finding>[_f('x', 0, confirmed: true)]).verdict,
          Verdict.confirmedThreat);
    });

    test('رابط مشبوه جوه رسالة درجتها منخفضة: الحكم والعرض بيتبعوا الرابط', () {
      final link = res(score: 50);
      final msg = res(score: 0, links: <ScanResult>[link]);
      expect(msg.verdict, Verdict.suspicious);
      expect(msg.effectiveScore, 50);
      expect(msg.displayLevel, RiskLevel.high);
      expect(msg.headline, RiskLevel.high.label);
    });

    test('رابط جزئي أو غير مفحوص داخل رسالة: فحص جزئي', () {
      final partialLink = res(partial: true);
      expect(res(links: <ScanResult>[partialLink]).verdict, Verdict.partialScan);
      final invalidLink = ScanResult.invalid(kind: ScanKind.url, issueCode: 'invalid_host', detail: 'x');
      expect(res(links: <ScanResult>[invalidLink]).verdict, Verdict.partialScan);
    });

    test('نصوص الحكم: "لا مؤشرات" بتنبّه إنه مش ضمان، والجزئي مش بيقول لا مؤشرات', () {
      expect(Verdict.noIndicators.advice, contains('لا يعني أنه آمن'));
      expect(Verdict.partialScan.advice, contains('لا نستطيع القول إنه بلا مؤشرات'));
      expect(Verdict.insufficient.advice, contains('لا نستطيع القول إنه بلا مؤشرات'));
      for (final v in Verdict.values) {
        expect(v.label, isNotEmpty);
        expect(v.advice, isNotEmpty);
      }
    });
  });
}
