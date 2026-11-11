// جداول الحروف المتشابهة (Homoglyphs) والحروف المزخرفة اللي بتتحول لحروف عادية.
// Dart صرف: مفيش اعتماد على Flutter ولا على الشبكة.
//
// ملاحظة صريحة: ده مش جدول Unicode confusables الكامل (آلاف الحروف). ده جدول
// مختار بإيدينا للحروف الأشهر في تقليد الدومينات (سيريلي/يوناني/أرمني/حروف لاتينية
// مشابهة). حرف مش موجود هنا ممكن يعدّي من غير ما يتعرف عليه كتقليد.

enum Script { latin, cyrillic, greek, armenian }

/// نتيجة فحص "ليبل" واحد من الدومين (الجزء بين نقطتين).
class LabelScan {
  const LabelScan({
    required this.skeleton,
    required this.scripts,
    required this.nonAscii,
    required this.lookalikes,
    required this.separatorLookalikes,
  });

  /// شكل الليبل بعد تحويل المتشابهات لحروفها اللاتينية (للمقارنة مع العلامات).
  final String skeleton;

  /// الأنظمة الكتابية (للحروف فقط) الموجودة في الليبل: لاتيني/سيريلي/يوناني/أرمني.
  final Set<Script> scripts;

  /// عدد الحروف غير ASCII.
  final int nonAscii;

  /// كام حرف منهم له شبيه لاتيني في الجدول.
  final int lookalikes;

  /// حروف شبيهة بفواصل الرابط (/ . @) مثل ∕ (U+2215).
  final int separatorLookalikes;

  /// خلط أنظمة كتابية متشابهة الشكل في ليبل واحد (مثال: a لاتينية + a سيريلية).
  bool get mixedScript => scripts.length >= 2;

  /// الليبل كله بنظام كتابي غير لاتيني، وكل حروفه غير الـ ASCII لها شبيه لاتيني.
  bool get wholeLookalike =>
      nonAscii > 0 &&
      lookalikes == nonAscii &&
      scripts.length == 1 &&
      !scripts.contains(Script.latin);

  bool get changedBySkeleton => lookalikes > 0 || separatorLookalikes > 0;
}

class Confusables {
  Confusables._();

  /// حرف غير لاتيني (أو لاتيني نادر) شكله مطابق تقريبًا لحرف/رمز ASCII.
  static const Map<int, String> _lookalike = <int, String>{
    // سيريلي
    0x0430: 'a', 0x0441: 'c', 0x0435: 'e', 0x043E: 'o', 0x0440: 'p',
    0x0445: 'x', 0x0443: 'y', 0x0456: 'i', 0x0458: 'j', 0x0455: 's',
    0x04BB: 'h', 0x0501: 'd', 0x051B: 'q', 0x051D: 'w', 0x04CF: 'l',
    0x0475: 'v',
    // يوناني
    0x03BF: 'o', 0x03B1: 'a', 0x03BD: 'v', 0x03C1: 'p', 0x03B9: 'i',
    0x03BA: 'k', 0x03C5: 'u', 0x03F2: 'c', 0x03C7: 'x', 0x03F3: 'j',
    // أرمني
    0x0585: 'o', 0x057D: 'u', 0x0578: 'n', 0x0570: 'h',
    // لاتيني نادر / أرقام رومانية / small caps
    0x0131: 'i', 0x0251: 'a', 0x0261: 'g', 0x01C0: 'l', 0x2113: 'l',
    0x217C: 'l', 0x2170: 'i', 0x217F: 'm', 0x217E: 'd', 0x217D: 'c',
    0x2179: 'x', 0x2174: 'v', 0x1D00: 'a', 0x1D04: 'c', 0x1D0F: 'o',
    0x1D1C: 'u', 0x1D20: 'v', 0x1D21: 'w', 0x2C9F: 'o', 0xA731: 's',
    // شرطات تشبه الواصلة
    0x2010: '-', 0x2011: '-', 0x2012: '-', 0x2013: '-', 0x2014: '-',
    0x2212: '-', 0xFE63: '-',
    // رموز تشبه فواصل الرابط (النقطة والشرطة المائلة و @)
    0x2024: '.', 0xFE52: '.', 0x2215: '/', 0x2044: '/', 0x29F8: '/',
    0x2571: '/', 0xFE6B: '@',
  };

  /// حروف لاتينية بعلامات تشكيل -> الحرف الأساسي (paypàl -> paypal).
  static const Map<String, String> _latinVariants = <String, String>{
    'a': 'àáâãäåāăąǎạả',
    'c': 'çćĉċč',
    'd': 'ďđ',
    'e': 'èéêëēĕėęěẹ',
    'g': 'ĝğġģ',
    'h': 'ĥħ',
    'i': 'ìíîïĩīĭįǐị',
    'j': 'ĵ',
    'k': 'ķ',
    'l': 'ĺļľŀł',
    'n': 'ñńņňŉ',
    'o': 'òóôõöøōŏőǒọ',
    'p': 'ṗ',
    'r': 'ŕŗř',
    's': 'śŝşš',
    't': 'ţťŧ',
    'u': 'ùúûüũūŭůűųǔụ',
    'w': 'ŵ',
    'y': 'ýÿŷ',
    'z': 'źżž',
  };

  static final Map<int, String> _diacritic = _buildDiacritics();

  static Map<int, String> _buildDiacritics() {
    final m = <int, String>{};
    _latinVariants.forEach((base, variants) {
      for (final r in variants.runes) {
        m[r] = base;
      }
    });
    return m;
  }

  static bool _isCombiningMark(int r) => r >= 0x0300 && r <= 0x036F;

  /// النظام الكتابي لحرف (للحروف فقط). null = ليس حرفًا من الأنظمة المتابَعة.
  static Script? scriptOf(int r) {
    if ((r >= 0x61 && r <= 0x7A) || (r >= 0x41 && r <= 0x5A)) {
      return Script.latin;
    }
    if ((r >= 0xC0 && r <= 0x24F) || (r >= 0x1E00 && r <= 0x1EFF)) {
      return Script.latin;
    }
    if (r >= 0x0400 && r <= 0x052F) return Script.cyrillic;
    if ((r >= 0x0370 && r <= 0x03FF) || (r >= 0x1F00 && r <= 0x1FFF)) {
      return Script.greek;
    }
    if (r >= 0x0531 && r <= 0x058F) return Script.armenian;
    return null;
  }

  /// نفس معالجة المتصفح (تطبيع Unicode التوافقي) للحروف المزخرفة وعريضة العرض:
  /// ｐａｙｐａｌ و 𝐩𝐚𝐲𝐩𝐚𝐥 و ⓟⓐⓨⓟⓐⓛ كلها بتتحول لـ paypal قبل ما المتصفح يتصل.
  /// بيرجّع حرف ASCII واحد، أو null لو الحرف مش من النوع ده.
  static String? foldCompat(int r) {
    if (r >= 0xFF01 && r <= 0xFF5E) return String.fromCharCode(r - 0xFEE0);
    if (r == 0x3002 || r == 0xFF61) return '.';
    if (r >= 0x1D400 && r <= 0x1D6A3) {
      final k = (r - 0x1D400) % 52;
      return String.fromCharCode(k < 26 ? 0x41 + k : 0x61 + (k - 26));
    }
    if (r >= 0x1D7CE && r <= 0x1D7FF) {
      return String.fromCharCode(0x30 + ((r - 0x1D7CE) % 10));
    }
    if (r >= 0x24B6 && r <= 0x24CF) return String.fromCharCode(0x61 + (r - 0x24B6));
    if (r >= 0x24D0 && r <= 0x24E9) return String.fromCharCode(0x61 + (r - 0x24D0));
    if (r >= 0x249C && r <= 0x24B5) return String.fromCharCode(0x61 + (r - 0x249C));
    switch (r) {
      case 0x210E:
        return 'h';
      case 0x212F:
        return 'e';
      case 0x210A:
        return 'g';
    }
    return null;
  }

  /// يفحص ليبل واحد (بحروف صغيرة) ويطلّع الـ skeleton وإحصائيات التقليد.
  static LabelScan scanLabel(String label) {
    final sb = StringBuffer();
    final scripts = <Script>{};
    var nonAscii = 0;
    var lookalikes = 0;
    var sepLook = 0;
    for (final r in label.runes) {
      if (_isCombiningMark(r)) continue; // علامات التشكيل المنفصلة بتتجاهل
      final sc = scriptOf(r);
      if (sc != null) scripts.add(sc);
      if (r < 0x80) {
        sb.writeCharCode(r);
        continue;
      }
      nonAscii++;
      final look = _lookalike[r];
      if (look != null) {
        lookalikes++;
        if (look == '.' || look == '/' || look == '@') sepLook++;
        sb.write(look);
        continue;
      }
      final dia = _diacritic[r];
      if (dia != null) {
        sb.write(dia);
        continue;
      }
      sb.writeCharCode(r);
    }
    return LabelScan(
      skeleton: sb.toString(),
      scripts: scripts,
      nonAscii: nonAscii,
      lookalikes: lookalikes,
      separatorLookalikes: sepLook,
    );
  }
}
