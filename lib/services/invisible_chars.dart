import '../core/models.dart';

/// سبب تحذير حقيقي واحد عن حروف خفية/تحكم في اتجاه النص.
class InvisibleIssue {
  const InvisibleIssue({
    required this.code,
    required this.severity,
    required this.title,
    required this.detail,
    required this.points,
    required this.codePoints,
  });

  /// كود ثابت للإشارة (bidi_override / bidi_unbalanced / zero_width_split / tag_chars /
  /// control_chars / format_controls).
  final String code;
  final Severity severity;
  final String title;
  final String detail;
  final int points;

  /// المحارف اللي سببت التحذير (مرتبة، بدون تكرار).
  final List<int> codePoints;

  Finding toFinding() => Finding(
        code: code,
        severity: severity,
        title: title,
        detail: detail,
        points: points,
      );
}

class InvisibleReport {
  const InvisibleReport({required this.issues, required this.benignCount});

  final List<InvisibleIssue> issues;

  /// عدد المحارف الطبيعية اللي اتجاهلت من غير تحذير (LRM/RLM/ALM، عزل اتجاه متوازن،
  /// ZWNJ/ZWJ في سياقها الطبيعي، BOM في أول النص).
  final int benignCount;

  bool get hasIssues => issues.isNotEmpty;
}

/// تصنيف الحروف الخفية ومحارف اتجاه النص.
///
/// المبدأ: النص العربي/الإنجليزي المختلط بيحتاج علامات الاتجاه (LRM U+200E و RLM U+200F
/// و ALM U+061C)، وكمان OCR وتطبيقات المراسلة بتضيفها. فوجودها لوحده مش تهديد وما بيدّيش
/// نقاط. اللي بيتحذّر منه:
///  - محارف قلب الترتيب (LRO/RLO U+202D/U+202E) وتضمين/عزل اتجاه غير متوازن: أسلوب
///    "Trojan Source" لإخفاء ترتيب النص الحقيقي.
///  - حروف عرض صفري (ZWSP/WJ/BOM...) وسط كلمة، و ZWNJ/ZWJ وسط كلمة لاتينية: تقطيع
///    الكلمات المشبوهة لتخطي الفلاتر. (ZWNJ/ZWJ بين حروف عربية/فارسية أو في الإيموجي طبيعي.)
///  - محارف Tag (U+E0000..E007F): نص مخفي (ASCII smuggling).
///  - محارف تحكم C0/C1 وتحكم التنسيق المهجور (U+206A..206F).
class InvisibleChars {
  InvisibleChars._();

  // ---- تصنيف المحارف ----

  /// علامات اتجاه طبيعية (LRM, RLM, ALM).
  static bool isBidiMark(int r) => r == 0x200E || r == 0x200F || r == 0x061C;

  /// LRO / RLO: قلب الترتيب الفعلي للنص.
  static bool isBidiOverride(int r) => r == 0x202D || r == 0x202E;

  /// LRE / RLE / LRO / RLO / PDF.
  static bool isBidiEmbedding(int r) => r >= 0x202A && r <= 0x202E;

  /// LRI / RLI / FSI / PDI.
  static bool isBidiIsolate(int r) => r >= 0x2066 && r <= 0x2069;

  static bool isJoiner(int r) => r == 0x200C || r == 0x200D;

  static bool isTag(int r) => r >= 0xE0000 && r <= 0xE007F;

  /// تحكم التنسيق المهجور (U+206A..206F).
  static bool isDeprecatedFormat(int r) => r >= 0x206A && r <= 0x206F;

  /// حروف عرض صفري/فراغ غير مرئي (غير الـ joiners وعلامات الاتجاه).
  static bool isZeroWidth(int r) {
    switch (r) {
      case 0x00AD: // soft hyphen
      case 0x034F: // combining grapheme joiner
      case 0x115F: // hangul choseong filler
      case 0x1160: // hangul jungseong filler
      case 0x17B4:
      case 0x17B5:
      case 0x180E: // mongolian vowel separator
      case 0x200B: // ZWSP
      case 0x2060: // word joiner
      case 0x3164: // hangul filler
      case 0xFEFF: // ZWNBSP / BOM
      case 0xFFA0: // halfwidth hangul filler
        return true;
    }
    return r >= 0x2061 && r <= 0x2064; // invisible math operators
  }

  /// محارف تحكم C0/C1 اللي مش مسافات عادية (tab/LF/VT/FF/CR/NEL مسموحة: OCR بيطلّعها).
  static bool isControl(int r) {
    if (r >= 0x09 && r <= 0x0D) return false;
    if (r == 0x85) return false;
    return r <= 0x1F || (r >= 0x7F && r <= 0x9F);
  }

  /// محارف بنتجاهلها وقت مطابقة الكلمات (مش وقت العرض): تشكيل مش داخل هنا، دي بس
  /// المحارف غير المرئية اللي ممكن تقطّع كلمة مفتاحية.
  static bool isIgnorableForMatching(int r) =>
      isBidiMark(r) ||
      isBidiEmbedding(r) ||
      isBidiIsolate(r) ||
      isJoiner(r) ||
      isZeroWidth(r) ||
      isTag(r) ||
      isDeprecatedFormat(r);

  /// الحرف "جزء كلمة" (حرف/رقم لاتيني أو عربي أو سيريلي...).
  static bool _isWordCode(int r) {
    if (r >= 0x30 && r <= 0x39) return true;
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A)) return true;
    if (r >= 0xC0 && r <= 0x24F && r != 0xD7 && r != 0xF7) return true;
    if (r >= 0x370 && r <= 0x52F) return true;
    if ((r >= 0x620 && r <= 0x64A) ||
        (r >= 0x66E && r <= 0x6D3) ||
        (r >= 0x6FA && r <= 0x6FF) ||
        (r >= 0x750 && r <= 0x77F) ||
        (r >= 0xFB50 && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF && r != 0xFEFF)) {
      return true;
    }
    return false;
  }

  static bool _isAsciiAlnum(int r) =>
      (r >= 0x30 && r <= 0x39) ||
      (r >= 0x41 && r <= 0x5A) ||
      (r >= 0x61 && r <= 0x7A);

  static const Map<int, String> _names = <int, String>{
    0x00AD: 'SHY',
    0x034F: 'CGJ',
    0x061C: 'ALM',
    0x115F: 'HANGUL FILLER',
    0x1160: 'HANGUL FILLER',
    0x180E: 'MVS',
    0x200B: 'ZWSP',
    0x200C: 'ZWNJ',
    0x200D: 'ZWJ',
    0x200E: 'LRM',
    0x200F: 'RLM',
    0x202A: 'LRE',
    0x202B: 'RLE',
    0x202C: 'PDF',
    0x202D: 'LRO',
    0x202E: 'RLO',
    0x2060: 'WJ',
    0x2061: 'INVISIBLE FUNCTION APPLICATION',
    0x2062: 'INVISIBLE TIMES',
    0x2063: 'INVISIBLE SEPARATOR',
    0x2064: 'INVISIBLE PLUS',
    0x2066: 'LRI',
    0x2067: 'RLI',
    0x2068: 'FSI',
    0x2069: 'PDI',
    0x3164: 'HANGUL FILLER',
    0xFEFF: 'ZWNBSP/BOM',
    0xFFA0: 'HALFWIDTH HANGUL FILLER',
  };

  static String _hex(int r) =>
      'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}';

  /// اسم مختصر مقروء للمحرف: "U+202E (RLO)".
  static String label(int r) {
    final n = _names[r];
    if (n != null) return '${_hex(r)} ($n)';
    if (isTag(r)) return '${_hex(r)} (TAG)';
    if (isControl(r)) return '${_hex(r)} (CONTROL)';
    if (isDeprecatedFormat(r)) return '${_hex(r)} (DEPRECATED FORMAT)';
    return _hex(r);
  }

  static String _list(Iterable<int> cps, {int max = 4}) {
    final l = cps.toList()..sort();
    final shown = l.take(max).map(label).join('، ');
    return l.length > max ? '$shown ...' : shown;
  }

  /// يحلل [text] ويرجّع التحذيرات الحقيقية فقط. LRM/RLM/ALM وعزل الاتجاه المتوازن
  /// وZWNJ/ZWJ الطبيعيين وBOM أول النص بيتعدّوا في [InvisibleReport.benignCount] بدون نقاط.
  static InvisibleReport analyze(String text) {
    final cps = text.runes.toList();
    final n = cps.length;
    var benign = 0;

    final overrides = <int>{};
    final unbalancedMarks = <int>{};
    final splitters = <int>{};
    var splitCount = 0;
    final tags = <int>{};
    final controls = <int>{};
    final formats = <int>{};

    var embedDepth = 0;
    var isolateDepth = 0;
    var embedUnbalanced = false;
    var isolateUnbalanced = false;

    for (var i = 0; i < n; i++) {
      final r = cps[i];
      if (r < 0x7F && r >= 0x20) continue; // سريع: ASCII عادي

      if (isBidiMark(r)) {
        benign++;
        continue;
      }
      if (isBidiEmbedding(r)) {
        if (isBidiOverride(r)) overrides.add(r);
        if (r == 0x202C) {
          if (embedDepth == 0) {
            embedUnbalanced = true;
            unbalancedMarks.add(r);
          } else {
            embedDepth--;
          }
        } else {
          embedDepth++;
          if (!isBidiOverride(r)) unbalancedMarks.add(r); // يتأكد لاحقًا لو اتقفل
        }
        continue;
      }
      if (isBidiIsolate(r)) {
        if (r == 0x2069) {
          if (isolateDepth == 0) {
            isolateUnbalanced = true;
            unbalancedMarks.add(r);
          } else {
            isolateDepth--;
            benign++;
          }
        } else {
          isolateDepth++;
          unbalancedMarks.add(r);
        }
        continue;
      }
      if (isTag(r)) {
        tags.add(r);
        continue;
      }
      if (isDeprecatedFormat(r)) {
        formats.add(r);
        continue;
      }
      if (isControl(r)) {
        controls.add(r);
        continue;
      }
      if (isJoiner(r)) {
        final prev = i > 0 ? cps[i - 1] : -1;
        final next = i + 1 < n ? cps[i + 1] : -1;
        if (_isAsciiAlnum(prev) && _isAsciiAlnum(next)) {
          splitters.add(r);
          splitCount++;
        } else {
          benign++;
        }
        continue;
      }
      if (isZeroWidth(r)) {
        if (r == 0xFEFF && i == 0) {
          benign++; // BOM في أول النص
          continue;
        }
        final prev = i > 0 ? cps[i - 1] : -1;
        final next = i + 1 < n ? cps[i + 1] : -1;
        if (prev >= 0 && next >= 0 && _isWordCode(prev) && _isWordCode(next)) {
          splitters.add(r);
          splitCount++;
        }
        continue;
      }
    }

    // تضمين/عزل اتجاه اتقفل بشكل سليم = طبيعي. لو لسه فيه مفتوح = غير متوازن.
    if (embedDepth > 0) embedUnbalanced = true;
    if (isolateDepth > 0) isolateUnbalanced = true;
    if (!embedUnbalanced && !isolateUnbalanced) {
      // كل التضمينات/العزل متوازنة: مالهاش تحذير (بتتعد طبيعي).
      if (overrides.isEmpty) {
        benign += unbalancedMarks.length;
        unbalancedMarks.clear();
      }
    }

    final issues = <InvisibleIssue>[];

    if (overrides.isNotEmpty) {
      issues.add(InvisibleIssue(
        code: 'bidi_override',
        severity: Severity.danger,
        points: 20,
        codePoints: overrides.toList()..sort(),
        title: 'محارف تقلب ترتيب عرض النص (${_list(overrides)})',
        detail:
            'هذه المحارف تغيّر الترتيب الظاهر للنص بحيث يُعرض شيء ويُقرأ شيء آخر (أسلوب Trojan Source، يُستخدم لإخفاء امتداد ملف أو جزء من رابط). علامات الاتجاه العادية LRM/RLM في النص العربي المختلط لا تُحتسب.',
      ));
    }
    if (embedUnbalanced || isolateUnbalanced) {
      final marks = unbalancedMarks.where((r) => !isBidiOverride(r)).toSet();
      if (marks.isNotEmpty) {
        issues.add(InvisibleIssue(
          code: 'bidi_unbalanced',
          severity: Severity.warn,
          points: 8,
          codePoints: marks.toList()..sort(),
          title: 'محارف اتجاه نص غير متوازنة (${_list(marks)})',
          detail:
              'فُتح تضمين أو عزل اتجاه ولم يُغلق (أو أُغلق بدون فتح). النص العادي بيوازنها، وغير المتوازن غالبًا من لصق مقتطف أو محاولة تلاعب بترتيب العرض.',
        ));
      }
    }
    if (splitCount > 0) {
      issues.add(InvisibleIssue(
        code: 'zero_width_split',
        severity: Severity.warn,
        points: 10,
        codePoints: splitters.toList()..sort(),
        title: 'حروف غير مرئية تقطّع الكلمات (${_list(splitters)})',
        detail:
            'وُجد $splitCount حرف غير مرئي وسط كلمة. ده أسلوب شائع لتخطي فلاتر الكلمات المشبوهة (مثل pay + حرف غير مرئي + pal). الحروف غير المرئية على أطراف الكلمات أو بين حروف عربية/فارسية (ZWNJ) لا تُحتسب.',
      ));
    }
    if (tags.isNotEmpty) {
      issues.add(InvisibleIssue(
        code: 'tag_chars',
        severity: Severity.danger,
        points: 20,
        codePoints: tags.toList()..sort(),
        title: 'نص مخفي بمحارف Tag (${_list(tags, max: 2)})',
        detail:
            'محارف Tag (U+E0000..E007F) لا تُعرض لكن تحمل نصًا مخفيًا يقرأه البرنامج (ASCII smuggling). لا يوجد استخدام عادي لها في الرسائل.',
      ));
    }
    if (controls.isNotEmpty) {
      issues.add(InvisibleIssue(
        code: 'control_chars',
        severity: Severity.warn,
        points: 8,
        codePoints: controls.toList()..sort(),
        title: 'محارف تحكم غير مرئية (${_list(controls)})',
        detail: 'محارف تحكم (C0/C1) غير مألوفة في الرسائل، وبتُستخدم للتلاعب بالعرض أو تخطي الفلاتر.',
      ));
    }
    if (formats.isNotEmpty) {
      issues.add(InvisibleIssue(
        code: 'format_controls',
        severity: Severity.warn,
        points: 8,
        codePoints: formats.toList()..sort(),
        title: 'محارف تنسيق مهجورة (${_list(formats)})',
        detail: 'محارف تحكم تنسيق مهجورة (U+206A..206F) لا يستخدمها أي تطبيق حديث، ووجودها غير طبيعي.',
      ));
    }

    return InvisibleReport(issues: issues, benignCount: benign);
  }
}
