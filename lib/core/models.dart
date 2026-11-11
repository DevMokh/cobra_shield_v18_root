// نماذج البيانات المشتركة بين الخدمات والشاشات (Dart صرف بدون Flutter)

enum RiskLevel { low, medium, high, critical }

/// حدود المستويات: مصدر واحد للتحويل من الدرجة (0-100) إلى المستوى في كل المحللات
/// والشاشات. أي مكان تاني محتاج يقارن بدرجة لازم يستخدم [levelForScore] أو الثوابت دي.
const int kBandMedium = 20;
const int kBandHigh = 45;
const int kBandCritical = 70;

RiskLevel levelForScore(int score) {
  if (score >= kBandCritical) return RiskLevel.critical;
  if (score >= kBandHigh) return RiskLevel.high;
  if (score >= kBandMedium) return RiskLevel.medium;
  return RiskLevel.low;
}

extension RiskLevelText on RiskLevel {
  String get label {
    switch (this) {
      case RiskLevel.low:
        return 'لا مؤشرات واضحة';
      case RiskLevel.medium:
        return 'مشبوه';
      case RiskLevel.high:
        return 'خطير';
      case RiskLevel.critical:
        return 'احتيال مرجّح';
    }
  }

  String get advice {
    switch (this) {
      case RiskLevel.low:
        return 'لم نجد علامات خطر واضحة، لكن هذا لا يعني أنه آمن 100%. افتحه فقط لو كنت تتوقعه من مصدر موثوق.';
      case RiskLevel.medium:
        return 'فيه علامات تستدعي الحذر. لا تُدخل أي بيانات أو أكواد، وتأكد من المصدر أولًا.';
      case RiskLevel.high:
        return 'علامات قوية على التصيّد. الأفضل ألا تفتحه، ولا تدخل أي بيانات.';
      case RiskLevel.critical:
        return 'يشبه الاحتيال بدرجة كبيرة. لا تفتحه، لا ترد، واحذف الرسالة أو أبلغ عنها.';
    }
  }
}

enum Severity { good, info, warn, danger }

class Finding {
  const Finding({
    required this.severity,
    required this.title,
    required this.detail,
    this.points = 0,
    this.confirmed = false,
    this.code = '',
    this.family = '',
  });

  final Severity severity;
  final String title;
  final String detail;
  final int points;

  /// معرّف ثابت للإشارة (مثل ip_host / userinfo_at) للتقارير المنظمة والاختبارات.
  /// فاضي في الإشارات القديمة اللي لسه ما اتسمّتش.
  final String code;

  /// عائلة الإشارة. الإشارات الضعيفة (kFamilyWeak: HTTP، امتداد شائع في الاحتيال،
  /// شرطات/طول، كلمات...) مجموعها محدود بـ [kWeakFamilyCap] عشان مجموعة إشارات
  /// ضعيفة متراكمة ما توصلش لوحدها لمستوى "مشبوه".
  final String family;

  /// true = مصدر خارجي موثوق صنّفه تهديدًا (مثلاً Safe Browsing أو تطابق كامل مع
  /// قائمة تصيّد). الباقي اشتباه مبني على قواعد وإشارات، مش تأكيد.
  final bool confirmed;
}

/// عائلة الإشارات الضعيفة (مساعدة فقط، مش دليل).
const String kFamilyWeak = 'weak';

/// أقصى مجموع تساهم بيه الإشارات الضعيفة في الدرجة. أقل من [kBandMedium] عمدًا:
/// الإشارات الضعيفة لوحدها مهما اتراكمت ما تخلّيش النتيجة "مشبوه".
const int kWeakFamilyCap = 12;

/// يحسب الدرجة النهائية (0-100) من قايمة إشارات بطريقة موحدة:
///  - الإشارة اللي ليها `code` بتتحسب مرة واحدة بس (الأعلى نقاطًا) حتى لو اتكرّرت.
///  - الإشارات الضعيفة ([kFamilyWeak]) مجموعها محدود بـ [kWeakFamilyCap].
///  - الإشارات من غير `code` (القديمة) بتتحسب كلها زي ما هي.
int aggregateScore(Iterable<Finding> findings) {
  final byCode = <String, Finding>{};
  final uncoded = <Finding>[];
  for (final f in findings) {
    if (f.code.isEmpty) {
      uncoded.add(f);
      continue;
    }
    final prev = byCode[f.code];
    if (prev == null || f.points > prev.points) byCode[f.code] = f;
  }
  var strong = 0;
  var weak = 0;
  for (final f in <Finding>[...byCode.values, ...uncoded]) {
    if (f.family == kFamilyWeak && f.points > 0) {
      weak += f.points;
    } else {
      strong += f.points;
    }
  }
  if (weak > kWeakFamilyCap) weak = kWeakFamilyCap;
  final total = strong + weak;
  if (total < 0) return 0;
  if (total > 100) return 100;
  return total;
}

/// الحكم النهائي على نتيجة الفحص. سبع حالات منفصلة (الدرجة الرقمية مالهاش معنى
/// في الحالات [invalidInput] و[analysisFailed]):
///  - [confirmedThreat]: مصدر موثوق أكّد إنه تهديد.
///  - [suspicious]: علامات اشتباه (المستوى التفصيلي في [RiskLevel]).
///  - [noIndicators]: الفحص اكتمل ومفيش علامات (ده مش معناه "آمن").
///  - [insufficient]: المحتوى قليل/غير واضح فمينفعش نحكم (مثلًا رسالة من كلمة).
///  - [invalidInput]: المدخل مش رابط/نص صالح للفحص (ما اتفحصش أصلًا).
///  - [analysisFailed]: حصل خطأ داخلي أثناء التحليل (ما نعرفش النتيجة).
///  - [partialScan]: الفحص ناقص (مصدر فشل أو جزء ما اتفحصش) فمينفعش نقول "لا مؤشرات".
enum Verdict {
  confirmedThreat,
  suspicious,
  noIndicators,
  insufficient,
  invalidInput,
  analysisFailed,
  partialScan,
}

extension VerdictText on Verdict {
  String get label {
    switch (this) {
      case Verdict.confirmedThreat:
        return 'تهديد مؤكد';
      case Verdict.suspicious:
        return 'مشبوه';
      case Verdict.noIndicators:
        return 'لا مؤشرات واضحة';
      case Verdict.insufficient:
        return 'معلومات غير كافية';
      case Verdict.invalidInput:
        return 'إدخال غير صالح';
      case Verdict.analysisFailed:
        return 'فشل التحليل';
      case Verdict.partialScan:
        return 'فحص جزئي';
    }
  }

  String get advice {
    switch (this) {
      case Verdict.confirmedThreat:
        return 'مصدر موثوق صنّف هذا المحتوى كتهديد. لا تفتحه ولا تدخل أي بيانات، واحذف الرسالة أو أبلغ عنها.';
      case Verdict.suspicious:
        return 'فيه علامات تستدعي الحذر. تأكد من المصدر قبل أي خطوة.';
      case Verdict.noIndicators:
        return 'لم نجد علامات خطر واضحة، لكن هذا لا يعني أنه آمن 100%. افتحه فقط لو كنت تتوقعه من مصدر موثوق.';
      case Verdict.insufficient:
        return 'المحتوى قليل أو غير واضح بما يكفي للحكم عليه. لا نستطيع القول إنه بلا مؤشرات؛ أضف تفاصيل أكثر أو تحقق من المصدر.';
      case Verdict.invalidInput:
        return 'المدخل ليس رابط ويب صالحًا (http/https)، فلم يتم فحصه ولا تُعرض له درجة خطر. راجع الكتابة وحاول مرة أخرى.';
      case Verdict.analysisFailed:
        return 'حدث خطأ أثناء التحليل، فلا نعرف نتيجة هذا الفحص. اعتبره غير مفحوص وتعامل معه بحذر.';
      case Verdict.partialScan:
        return 'الفحص لم يكتمل (مصدر فشل أو جزء من المحتوى لم يُفحص)، فلا نستطيع القول إنه بلا مؤشرات. تعامل معه بحذر وراجع تفاصيل النتيجة.';
    }
  }
}

enum ScanKind { url, message }

/// حالة الفحص نفسه (منفصلة عن درجة الخطر).
enum ScanState { completed, invalidInput, failed }

class UrlParts {
  const UrlParts({
    required this.scheme,
    required this.host,
    required this.domain,
    required this.tld,
    required this.path,
    required this.query,
    required this.port,
    required this.normalizedUrl,
    this.registrableDomain = '',
    this.publicSuffix = '',
    this.unicodeHost = '',
    this.asciiHost = '',
    this.pslListed = true,
  });

  final String scheme;

  /// اسم المضيف الكامل (Hostname) بالشكل القياسي: حروف صغيرة، وIP بصيغته العشرية.
  /// ده اللي بيتعرض للمستخدم كاسم الموقع، وليس الدومين المسجّل فقط.
  final String host;

  /// للتوافق مع الكود القديم: الدومين المسجّل لو متاح، وإلا المضيف نفسه (IP أو لاحقة عامة).
  final String domain;
  final String tld;
  final String path;
  final String query;
  final String port;
  final String normalizedUrl;

  /// الدومين المسجّل (Registrable Domain) حسب Public Suffix List، مثل example.co.uk.
  /// فاضي لو المضيف عنوان IP أو هو نفسه لاحقة عامة.
  final String registrableDomain;

  /// اللاحقة العامة (com / co.uk / github.io). فاضي لو المضيف IP.
  final String publicSuffix;

  /// المضيف بحروفه الأصلية (Unicode) بعد فك xn--؛ للعرض.
  final String unicodeHost;

  /// المضيف بصيغة ASCII (Punycode) لو فيه حروف دولية؛ للعرض.
  final String asciiHost;

  /// false = الامتداد غير موجود في قائمة اللاحقات المضمّنة (قد يكون جديدًا أو غير حقيقي).
  final bool pslListed;
}

class ScanResult {
  const ScanResult({
    required this.kind,
    required this.score,
    required this.findings,
    this.parts,
    this.links = const <ScanResult>[],
    this.title = '',
    this.partial = false,
    this.state = ScanState.completed,
    this.issueCode = '',
    this.insufficientInfo = false,
  });

  /// نتيجة "إدخال غير صالح": المدخل ما اتفحصش، فمفيش درجة خطر حقيقية.
  /// [issueCode] سبب الرفض (empty / not_a_url / incomplete_url / unsupported_scheme /
  /// invalid_host / invalid_port / non_public_host)، و[detail] شرحه للمستخدم.
  factory ScanResult.invalid({
    required ScanKind kind,
    required String issueCode,
    required String detail,
    String title = '',
  }) =>
      ScanResult(
        kind: kind,
        score: 0,
        findings: <Finding>[
          Finding(
            code: 'invalid_input_$issueCode',
            severity: Severity.warn,
            title: 'إدخال غير صالح',
            detail: detail,
          ),
        ],
        title: title,
        state: ScanState.invalidInput,
        issueCode: issueCode,
      );

  /// نتيجة "فشل التحليل": خطأ داخلي، مفيش حكم.
  factory ScanResult.failed({
    required ScanKind kind,
    required String detail,
    String title = '',
  }) =>
      ScanResult(
        kind: kind,
        score: 0,
        findings: <Finding>[
          Finding(
            code: 'analysis_failed',
            severity: Severity.warn,
            title: 'تعذّر التحليل',
            detail: detail,
          ),
        ],
        title: title,
        state: ScanState.failed,
        partial: true,
      );

  final ScanKind kind;
  final int score;
  final List<Finding> findings;
  final UrlParts? parts;
  final List<ScanResult> links; // روابط الرسالة (للرسائل فقط)
  final String title;

  /// الفحص ما اكتملش (مصدر فشل، أو جزء من النص/الروابط ما اتفحصش).
  final bool partial;

  /// حالة الفحص: اكتمل / إدخال غير صالح / فشل داخلي.
  final ScanState state;

  /// سبب رفض المدخل (لما [state] = invalidInput)، وإلا فاضي.
  final String issueCode;

  /// المحتوى قليل/غير واضح بما يكفي للحكم (مثلًا رسالة من كلمة واحدة بدون روابط).
  final bool insufficientInfo;

  /// الفحص أنتج درجة خطر حقيقية (مش إدخال غير صالح ولا فشل).
  bool get hasScore => state == ScanState.completed;

  RiskLevel get level => levelForScore(score);

  /// أعلى درجة بين الرسالة نفسها وأي رابط جواها (للعرض والسجل). الحكم "مشبوه" بيتحدد
  /// بمستوى الرسالة أو أي رابط، فالعرض لازم يستخدم نفس المقياس عشان ما يظهرش "لا مؤشرات"
  /// جنب رابط مشبوه.
  int get effectiveScore {
    var best = score;
    for (final l in links) {
      if (l.hasScore && l.score > best) best = l.score;
    }
    return best;
  }

  /// المستوى المعروض: حسب [effectiveScore].
  RiskLevel get displayLevel => levelForScore(effectiveScore);

  /// الحكم النهائي. نتيجة "لا مؤشرات" مبتتقالش لو الفحص ناقص، والإدخال غير الصالح
  /// وفشل التحليل ليهم حالة مستقلة (مش درجة 0).
  Verdict get verdict {
    if (state == ScanState.invalidInput) return Verdict.invalidInput;
    if (state == ScanState.failed) return Verdict.analysisFailed;
    if (findings.any((f) => f.confirmed) ||
        links.any((l) => l.verdict == Verdict.confirmedThreat)) {
      return Verdict.confirmedThreat;
    }
    if (level != RiskLevel.low) return Verdict.suspicious;
    if (links.any((l) => l.level != RiskLevel.low)) return Verdict.suspicious;
    if (partial || links.any((l) => l.partial || !l.hasScore)) {
      return Verdict.partialScan;
    }
    if (insufficientInfo) return Verdict.insufficient;
    return Verdict.noIndicators;
  }

  /// العنوان المعروض: لو مشبوه بنستخدم المستوى التفصيلي (مشبوه/خطير/احتيال مرجّح).
  String get headline =>
      verdict == Verdict.suspicious ? displayLevel.label : verdict.label;

  String toReport() {
    final b = StringBuffer();
    b.writeln('تقرير Cobra Shield');
    if (hasScore) {
      b.writeln('درجة الخطر: $effectiveScore/100 - $headline');
    } else {
      b.writeln('الحالة: $headline (بدون درجة خطر)');
    }
    final v = verdict;
    if (v == Verdict.insufficient ||
        v == Verdict.partialScan ||
        v == Verdict.invalidInput ||
        v == Verdict.analysisFailed) {
      b.writeln('تنبيه: ${v.advice}');
    }
    if (parts != null) {
      b.writeln('المضيف (Hostname): ${parts!.host}');
      if (parts!.registrableDomain.isNotEmpty) {
        b.writeln('الدومين المسجّل (Registrable): ${parts!.registrableDomain}');
      }
    }
    b.writeln('');
    for (final f in findings) {
      var tag = '';
      if (f.points > 0) tag = ' (+${f.points})';
      if (f.points < 0) tag = ' (${f.points})';
      b.writeln('- ${f.title}$tag');
      b.writeln('  ${f.detail}');
    }
    if (links.isNotEmpty) {
      b.writeln('');
      b.writeln('الروابط داخل الرسالة:');
      for (final l in links) {
        if (l.hasScore) {
          b.writeln('* ${l.title} -> ${l.score}/100 (${l.level.label})');
        } else {
          b.writeln('* ${l.title} -> ${l.headline}');
        }
      }
    }
    b.writeln('');
    b.writeln('ملاحظة: التحليل تقديري ولا يغني عن الحذر.');
    return b.toString();
  }
}

class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.score,
    required this.time,
  });

  final int id;
  final ScanKind kind;
  final String title;
  final int score;
  final DateTime time;

  RiskLevel get level => levelForScore(score);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'k': kind == ScanKind.message ? 1 : 0,
        't': title,
        's': score,
        'ms': time.millisecondsSinceEpoch,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
        id: j['id'] as int,
        kind: (j['k'] as int) == 1 ? ScanKind.message : ScanKind.url,
        title: j['t'] as String,
        score: j['s'] as int,
        time: DateTime.fromMillisecondsSinceEpoch(j['ms'] as int),
      );
}
