import 'dart:convert' show JsonEncoder;

import '../core/models.dart';
import 'url_normalizer.dart';

/// ثلاث مراحل بسيطة للحكم على رابط. متطابقة مع عتبات [RiskLevel] (مصدرها الوحيد
/// [kBandMedium] و[kBandHigh] في models.dart): أقل من [kBandMedium] = [safe]،
/// من [kBandMedium] لحد أقل من [kBandHigh] = [suspicious]، [kBandHigh] فأكثر = [dangerous].
/// الإدخال غير الصالح وفشل التحليل ملهمش tier (القيمة null) لأنهم مش درجة خطر.
///
/// تنبيه مهم: [safe] معناها "لا مؤشرات خطر وجدناها"، مش ضمان. دومين جديد
/// مخترق ممكن يعدّي بدون أي إشارة.
enum ThreatTier { safe, suspicious, dangerous }

ThreatTier tierForScore(int score) {
  switch (levelForScore(score)) {
    case RiskLevel.low:
      return ThreatTier.safe;
    case RiskLevel.medium:
      return ThreatTier.suspicious;
    case RiskLevel.high:
    case RiskLevel.critical:
      return ThreatTier.dangerous;
  }
}

extension ThreatTierText on ThreatTier {
  String get label {
    switch (this) {
      case ThreatTier.safe:
        return 'لا مؤشرات خطر';
      case ThreatTier.suspicious:
        return 'مشبوه';
      case ThreatTier.dangerous:
        return 'خطير';
    }
  }
}

/// إشارة واحدة اتكشفت في الرابط.
class ThreatFlag {
  const ThreatFlag({
    required this.code,
    required this.severity,
    required this.title,
    required this.explanation,
    required this.weight,
  });

  factory ThreatFlag.fromFinding(Finding f) => ThreatFlag(
        code: f.code,
        severity: f.severity,
        title: f.title,
        explanation: f.detail,
        weight: f.points,
      );

  final String code;
  final Severity severity;
  final String title;
  final String explanation;

  /// نقاط الخطر اللي أضافتها الإشارة للدرجة النهائية.
  final int weight;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'severity': severity.name,
        'title': title,
        'explanation': explanation,
        'weight': weight,
      };
}

/// تقرير منظم عن رابط واحد: الدرجة، المستوى، الرابط بعد التنظيف، وقايمة الإشارات.
class UrlThreatReport {
  const UrlThreatReport({
    required this.input,
    required this.cleanUrl,
    required this.score,
    required this.rawScore,
    required this.tier,
    required this.level,
    required this.status,
    required this.issueCode,
    required this.valid,
    required this.partial,
    required this.flags,
    required this.errors,
  });

  factory UrlThreatReport.from(String input, ScanResult r, NormalizedUrl? n) {
    final flags = <ThreatFlag>[
      for (final f in r.findings)
        if (f.severity != Severity.good) ThreatFlag.fromFinding(f),
    ];
    var raw = 0;
    for (final f in r.findings) {
      raw += f.points;
    }
    return UrlThreatReport(
      input: input,
      cleanUrl: n?.cleanUrl ?? '',
      score: r.hasScore ? r.score : 0,
      rawScore: raw,
      tier: r.hasScore ? tierForScore(r.score) : null,
      level: r.hasScore ? r.level : null,
      status: r.state,
      issueCode: r.issueCode,
      valid: n?.valid ?? false,
      partial: r.partial,
      flags: flags,
      errors: n?.errors ?? const <String>[],
    );
  }

  final String input;

  /// الرابط بعد التنظيف (ترميز مفكوك، حروف خفية متشالة، بروتوكول مصلّح).
  /// للعرض والتحليل فقط، ما تفتحوش مباشرة.
  final String cleanUrl;

  /// الدرجة النهائية 0-100. بتتحسب بالقاعدة الموحّدة ([aggregateScore]: بدون تكرار
  /// لنفس الإشارة، وسقف للإشارات الضعيفة). مالهاش معنى لو [status] مش [ScanState.completed].
  final int score;

  /// مجموع أوزان كل الإشارات كما هي (قبل إزالة التكرار وسقف الضعيفة وقبل القص عند 100)،
  /// للشفافية.
  final int rawScore;

  /// null لو الفحص ما أنتجش درجة (إدخال غير صالح / فشل تحليل).
  final ThreatTier? tier;
  final RiskLevel? level;

  /// حالة الفحص: اكتمل / إدخال غير صالح / فشل داخلي.
  final ScanState status;

  /// سبب رفض المدخل لو [status] = invalidInput (not_a_url / incomplete_url ...)، وإلا فاضي.
  final String issueCode;

  /// الرابط قابل للتحليل كرابط ويب. false = شكله مكسور أو نوعه خطير.
  final bool valid;

  /// التحليل ناقص (نص أطول من الحد مثلًا).
  final bool partial;

  final List<ThreatFlag> flags;

  /// أكواد أخطاء الشكل (no_host, bad_host_char, ...) لو الرابط مش صالح.
  final List<String> errors;

  Map<String, Object?> toJson() => <String, Object?>{
        'input': input,
        'clean_url': cleanUrl,
        'score': score,
        'raw_score': rawScore,
        'status': status.name,
        'issue_code': issueCode,
        'tier': tier?.name,
        'level': level?.name,
        'valid': valid,
        'partial': partial,
        'errors': errors,
        'flags': <Object?>[for (final f in flags) f.toJson()],
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// نص مقروء للعرض أو المشاركة.
  String toText() {
    final b = StringBuffer();
    if (tier == null) {
      b.writeln(status == ScanState.invalidInput
          ? 'إدخال غير صالح (لم يُفحص، بدون درجة خطر)'
          : 'تعذّر التحليل (بدون درجة خطر)');
    } else {
      b.writeln('الدرجة: $score/100 - ${tier!.label}');
    }
    if (cleanUrl.isNotEmpty) b.writeln('الرابط بعد التنظيف: $cleanUrl');
    if (partial) b.writeln('تنبيه: التحليل ناقص.');
    for (final f in flags) {
      final w = f.weight > 0 ? ' (+${f.weight})' : '';
      b.writeln('- ${f.title}$w');
      b.writeln('  ${f.explanation}');
    }
    return b.toString();
  }
}
