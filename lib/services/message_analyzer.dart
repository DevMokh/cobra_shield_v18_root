import 'dart:math' as math;

import '../core/knowledge.dart';
import '../core/models.dart';
import 'invisible_chars.dart';
import 'text_utils.dart';
import 'url_analyzer.dart';

class _Pattern {
  _Pattern(this.word, this.regex);
  final String word;
  final RegExp regex;

  /// نص العرض للمطابقة (للتعبير النمطي بنعرض الجزء المطابق، للكلمة بنعرضها هي).
  String? match(String norm) {
    final m = regex.firstMatch(norm);
    if (m == null) return null;
    return word.startsWith('re:') ? m.group(0) : word;
  }
}

_Pattern _compile(String w) => w.startsWith('re:')
    ? _Pattern(w, RegExp(w.substring(3)))
    : _Pattern(w, buildKeywordRegex(w));

class _CompiledSignal {
  _CompiledSignal(this.def)
      : strong = def.words.map(_compile).toList(),
        soft = def.soft.map(_compile).toList();

  final SignalDef def;
  final List<_Pattern> strong;
  final List<_Pattern> soft;

  List<String> hits(List<_Pattern> ps, String norm) {
    final out = <String>[];
    for (final p in ps) {
      final m = p.match(norm);
      if (m != null && !out.contains(m)) out.add(m);
    }
    return out;
  }
}

/// نتيجة فحص الجمل بحثًا عن بيانات حساسة وسياق طلبها.
class _SecretScan {
  final List<String> handOver = <String>[]; // مصطلح حساس + فعل "ابعت/قول/send"
  final List<String> input = <String>[]; // مصطلح حساس + فعل "اكتب/enter"
  final List<String> mention = <String>[]; // مصطلح حساس بدون طلب
  bool protective = false; // فيه عبارة "لا تشارك / do not share"
}

/// محلل الرسائل: يجمع إشارات نصية (استعجال، تهديد، طلب بيانات ...) ويفحص كل
/// رابط داخل الرسالة بمحلل الروابط. كله محلي ولا يُرسل أي نص خارج الجهاز.
///
/// قواعد المعايرة:
///  - إشارة واحدة لكل مفهوم (كود `msg_<id>`) مهما اتذكر بالعربي أو الإنجليزي أو الاتنين،
///    ومفيش نقاط على تعدد الكلمات.
///  - الكلمات العامة (login / account / bank / invoice / البنك / فاتورة...) إشارات ضعيفة
///    مجموعها محدود، فلا تخلّي رسالة عادية "مشبوهة".
///  - كلمة حساسة (OTP / كلمة المرور...) لوحدها مش طلب: لازم طلب فعلي في نفس الجملة
///    وبدون تحذير "لا تشارك".
///  - الرابط مع الضغط النفسي بيرفع الدرجة بس لو الوجهة مش دومين رسمي معروف.
///  - الفحص الناقص (نص مقصوص، روابط زيادة، رابط ما اتفحصش) = نتيجة جزئية، مش "لا مؤشرات".
class MessageAnalyzer {
  MessageAnalyzer._();

  static const int maxChars = 5000;
  static const int maxLinks = 8;

  /// أقل عدد كلمات لازم يكون في الرسالة عشان نحكم عليها من غير روابط.
  static const int minWordsForVerdict = 3;

  static final List<_CompiledSignal> _signals =
      kSignals.map((s) => _CompiledSignal(s)).toList();
  static final List<_Pattern> _sensitive =
      kSensitiveTerms.map(_compile).toList();
  static final List<RegExp> _protective =
      kProtectivePhrases.map(buildKeywordRegex).toList();
  static final RegExp _handOverAr = RegExp(kHandOverVerbsAr);
  static final RegExp _handOverEn = RegExp(kHandOverVerbsEn);
  static final RegExp _inputAr = RegExp(kInputVerbsAr);
  static final RegExp _inputEn = RegExp(kInputVerbsEn);
  static final RegExp _sentenceSplit = RegExp(r'[.!?؟\n\r;؛]+');
  static final RegExp _wordToken =
      RegExp(r'[a-zء-ي٠-٩۰-۹]{2,}|\d{2,}');

  static final RegExp _urlRe = RegExp(
    r'(?:(?:https?://|www\.)[^\s<>"]+)'
    r'|(?<![@\w.\-/])(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+'
    r'(?:com|net|org|info|xyz|top|click|link|co|me|eg|ly|gl|is|cc|app|site|online|live|shop|icu|vip|club|work|support|cfd|sbs|buzz|tk|ml|ga|cf|gq|ws|to|gd)'
    r'(?:/[^\s<>"]*)?(?![\w@])',
    caseSensitive: false,
  );
  // علامات ترقيم نهائية + علامات اتجاه طبيعية (LRM/RLM/ALM) بتتشال من آخر الرابط.
  static final RegExp _trail =
      RegExp('[\\.\\,\\;\\:\\!\\?\\)\\]\\}»،؛؟"\u200E\u200F\u061C]+\$');
  static final RegExp _lead = RegExp('^[\u200E\u200F\u061C]+');

  static List<String> extractLinks(String text) => _extract(text, maxLinks);

  static List<String> _extract(String text, int limit) {
    final seen = <String>{};
    final out = <String>[];
    for (final m in _urlRe.allMatches(text)) {
      var s = m.group(0) ?? '';
      s = s.replaceAll(_trail, '').replaceAll(_lead, '');
      if (s.isEmpty) continue;
      final key = s.toLowerCase();
      if (seen.add(key)) out.add(s);
      if (out.length >= limit) break;
    }
    return out;
  }

  static Severity _sev(int pts) =>
      pts >= 20 ? Severity.danger : (pts >= 8 ? Severity.warn : Severity.info);

  /// يفحص الجمل: كل جملة فيها مصطلح حساس بتتصنّف (تسليم / إدخال / مجرد ذكر) حسب الفعل
  /// المرافق، والجملة اللي فيها تحذير ("لا تشارك") ما بتتحسبش طلب.
  static _SecretScan _scanSecrets(String norm) {
    final scan = _SecretScan();
    for (final sentence in norm.split(_sentenceSplit)) {
      if (sentence.trim().isEmpty) continue;
      final terms = <String>[];
      for (final p in _sensitive) {
        final m = p.match(sentence);
        if (m != null && !terms.contains(m)) terms.add(m);
      }
      if (terms.isEmpty) continue;
      final warns = _protective.any((r) => r.hasMatch(sentence));
      if (warns) {
        scan.protective = true;
        scan.mention.addAll(terms);
        continue;
      }
      if (_handOverAr.hasMatch(sentence) || _handOverEn.hasMatch(sentence)) {
        scan.handOver.addAll(terms);
      } else if (_inputAr.hasMatch(sentence) || _inputEn.hasMatch(sentence)) {
        scan.input.addAll(terms);
      } else {
        scan.mention.addAll(terms);
      }
    }
    return scan;
  }

  static bool _isOfficial(ScanResult l) =>
      l.findings.any((f) => f.code == 'official_domain');

  /// [partialReason]: لو النص جاي من مصدر ناقص (مثلًا OCR لاتيني بدون عربي، أو جودة قراءة
  /// منخفضة) بنضيف تحذير وبنعتبر الفحص جزئي، فمفيش "لا مؤشرات" مطمئنة على نص ممكن يكون ناقص.
  static ScanResult analyze(String input, {String? partialReason}) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return ScanResult.invalid(
        kind: ScanKind.message,
        issueCode: 'empty',
        detail: 'الرسالة فاضية. اكتب نص الرسالة أو الصقه.',
        title: 'رسالة',
      );
    }
    final textTruncated = raw.length > maxChars;
    final text = textTruncated ? raw.substring(0, maxChars) : raw;
    final norm = normalizeText(text);

    final findings = <Finding>[];

    // ---- فحص جزئي: لازم المستخدم يعرف إن في حاجة ما اتفحصتش ----
    final found = _extract(text, maxLinks + 1);
    final linksOverflow = found.length > maxLinks;
    if (textTruncated) {
      findings.add(Finding(
        code: 'msg_truncated',
        severity: Severity.warn,
        title: 'الرسالة طويلة: فحصنا أول $maxChars حرف فقط',
        detail:
            'الباقي (${raw.length - maxChars} حرف) ما اتفحصش وممكن يحتوي روابط أو طلبات مش ظاهرة في النتيجة. راجعه بنفسك.',
      ));
    }
    if (linksOverflow) {
      findings.add(Finding(
        code: 'msg_links_overflow',
        severity: Severity.warn,
        title: 'فيه روابط أكتر من $maxLinks ما اتفحصتش',
        detail: 'فحصنا أول $maxLinks روابط بس. الروابط الزيادة غير مفحوصة، فلا تفتحها.',
      ));
    }

    if (partialReason != null && partialReason.isNotEmpty) {
      findings.add(Finding(
        code: 'msg_input_partial',
        severity: Severity.warn,
        title: 'النص قد يكون ناقصًا',
        detail: partialReason,
      ));
    }

    // ---- الروابط (الحالة والجزئية بتتنقل زي ما هي) ----
    final links = found.take(maxLinks).map((l) {
      final r = UrlAnalyzer.analyze(l);
      return ScanResult(
        kind: ScanKind.url,
        score: r.score,
        findings: r.findings,
        parts: r.parts,
        title: l,
        partial: r.partial,
        state: r.state,
        issueCode: r.issueCode,
        insufficientInfo: r.insufficientInfo,
      );
    }).toList();
    final scoredLinks = links.where((r) => r.hasScore).toList();
    final unscanned = links.where((r) => !r.hasScore).toList();
    final worst = scoredLinks.isEmpty
        ? 0
        : scoredLinks.map((r) => r.score).reduce(math.max);

    // ---- حروف خفية: السبب الحقيقي فقط (LRM/RLM الطبيعية مش تحذير) ----
    final invisible = InvisibleChars.analyze(text);
    for (final issue in invisible.issues) {
      findings.add(issue.toFinding());
    }

    // ---- الإشارات النصية: واحدة لكل مفهوم ----
    final byConcept = <String, Finding>{};
    final strongHit = <String>{};
    void put(Finding f) {
      final prev = byConcept[f.code];
      if (prev == null || f.points > prev.points) byConcept[f.code] = f;
    }

    for (final s in _signals) {
      final strong = s.hits(s.strong, norm);
      if (strong.isNotEmpty) {
        strongHit.add(s.def.id);
        put(Finding(
          code: 'msg_${s.def.id}',
          severity: _sev(s.def.weight),
          title: s.def.title,
          detail: '${s.def.detail}\nوُجد: ${strong.take(3).join('، ')}',
          points: s.def.weight,
        ));
        continue;
      }
      final soft = s.hits(s.soft, norm);
      if (soft.isNotEmpty) {
        put(Finding(
          code: 'msg_${s.def.id}',
          severity: Severity.info,
          title: s.def.title,
          detail: '${s.def.detail}\nوُجد: ${soft.take(3).join('، ')}',
          points: s.def.softWeight,
          family: kFamilyWeak,
        ));
      }
    }

    // ---- طلب بيانات حساسة (بالسياق، مش بالكلمة) ----
    final secrets = _scanSecrets(norm);
    final untrustedLink = scoredLinks.any((l) => !_isOfficial(l) && l.score >= 5);
    List<String> requested = secrets.handOver;
    if (requested.isEmpty && secrets.input.isNotEmpty && untrustedLink) {
      requested = secrets.input;
    }
    if (requested.isNotEmpty) {
      strongHit.add('secret');
      put(Finding(
        code: 'msg_secret_request',
        severity: Severity.danger,
        title: 'يطلب كودًا أو بيانات سرية',
        detail:
            'الجهات الحقيقية (البنوك والمحافظ والشركات) لا تطلب منك كود التحقق أو الرقم السري أو بيانات البطاقة عبر رسالة.\nوُجد: ${requested.toSet().take(3).join('، ')}',
        points: 28,
      ));
    } else if (secrets.mention.isNotEmpty || secrets.input.isNotEmpty) {
      final all = <String>{...secrets.mention, ...secrets.input};
      put(Finding(
        code: 'msg_secret_mention',
        severity: Severity.info,
        title: 'الرسالة تذكر بيانات حساسة (بدون طلب لها)',
        detail:
            'ذكر "${all.take(3).join('، ')}" لا يعني بحد ذاته أن الرسالة احتيالية (رسائل الأكواد الرسمية بتذكرها). التحذير بيكون لو الرسالة طلبت منك تبعتها أو تقولها.',
      ));
      if (secrets.protective && links.isEmpty) {
        put(const Finding(
          code: 'msg_secret_warning',
          severity: Severity.good,
          title: 'الرسالة بتحذّرك من مشاركة الكود',
          detail:
              'الرسائل الرسمية بتنبّهك ألا تشارك الكود. هذه صيغة مألوفة، لكنها لا تثبت أن المرسل حقيقي (المحتال ممكن ينسخها).',
        ));
      }
    }

    findings.addAll(byConcept.values);

    // ---- الروابط داخل الرسالة ----
    if (unscanned.isNotEmpty) {
      findings.add(Finding(
        code: 'msg_link_unchecked',
        severity: Severity.warn,
        title: '${unscanned.length} رابط داخل الرسالة ما اتفحصش',
        detail:
            'ظهرت نصوص تشبه روابط لكنها غير صالحة للفحص (${unscanned.take(2).map((r) => r.title).join('، ')}). مفيش حكم عليها، فلا تفتحها قبل ما تتأكد منها.',
      ));
    }
    if (scoredLinks.isNotEmpty) {
      final linkPts = (worst * 0.7).round();
      if (linkPts > 0) {
        findings.add(Finding(
          code: 'msg_link_risk',
          severity: linkPts >= 25 ? Severity.danger : Severity.warn,
          title: worst >= kBandMedium ? 'رابط مشبوه داخل الرسالة' : 'علامات ضعيفة في رابط داخل الرسالة',
          detail: 'أخطر رابط حصل على $worst/100. راجع تفاصيل الروابط بالأسفل.',
          points: linkPts,
          // رابط درجته أقل من "مشبوه" بيتحسب كإشارة ضعيفة (مجموعها محدود).
          family: worst < kBandMedium ? kFamilyWeak : '',
        ));
      } else {
        findings.add(Finding(
          code: 'msg_link_present',
          severity: Severity.info,
          title: 'الرسالة تحتوي ${scoredLinks.length} رابط',
          detail: 'لم نجد علامات واضحة في الروابط، لكن لا تفتحها إلا لو كنت تتوقعها.',
        ));
      }
    }
    // رابط + ضغط نفسي (استعجال/تهديد/جائزة/طلب بيانات/دفع...) لوجهة مش رسمية.
    final allOfficial = scoredLinks.isNotEmpty && scoredLinks.every(_isOfficial);
    if (links.isNotEmpty && strongHit.isNotEmpty && !allOfficial) {
      findings.add(const Finding(
        code: 'msg_link_pressure',
        severity: Severity.danger,
        title: 'رابط مع ضغط نفسي',
        detail:
            'اجتماع رابط غير رسمي مع استعجال أو تهديد أو جائزة أو طلب بيانات أو دفع هو النمط الكلاسيكي للتصيّد.',
        points: 10,
      ));
    }

    // ---- علامات تعجب كثيرة (ضعيفة) ----
    final bangs = '!'.allMatches(text).length + '！'.allMatches(text).length;
    if (bangs >= 3) {
      findings.add(const Finding(
        code: 'msg_exclamations',
        severity: Severity.info,
        title: 'علامات تعجب كثيرة',
        detail: 'المبالغة في الترقيم أسلوب لافتعال الإثارة.',
        points: 3,
        family: kFamilyWeak,
      ));
    }

    // ---- محتوى غير كافٍ للحكم ----
    final wordCount = _wordToken.allMatches(norm).length;
    final insufficient = links.isEmpty &&
        findings.where((f) => f.points > 0).isEmpty &&
        wordCount < minWordsForVerdict &&
        !textTruncated;
    if (insufficient) {
      findings.add(const Finding(
        code: 'msg_insufficient',
        severity: Severity.info,
        title: 'النص قصير جدًا للحكم عليه',
        detail:
            'الرسالة كلمات قليلة بدون روابط، فلا نقدر نقول إنها بلا مؤشرات. أضف باقي الرسالة أو تحقق من المرسل.',
      ));
    } else if (!findings.any((f) => f.points > 0 || f.severity != Severity.info)) {
      findings.add(const Finding(
        code: 'msg_no_indicators',
        severity: Severity.good,
        title: 'لا مؤشرات نصية واضحة',
        detail:
            'لم نجد عبارات احتيال شائعة. هذا لا يعني أن الرسالة آمنة؛ ابقَ حذرًا من أي طلب مفاجئ للمال أو البيانات.',
      ));
    }

    final score = aggregateScore(findings);
    findings.sort((a, b) => b.points.compareTo(a.points));

    return ScanResult(
      kind: ScanKind.message,
      score: score,
      findings: findings,
      links: links,
      title: 'رسالة',
      partial: textTruncated ||
          linksOverflow ||
          unscanned.isNotEmpty ||
          (partialReason != null && partialReason.isNotEmpty),
      insufficientInfo: insufficient,
    );
  }
}
