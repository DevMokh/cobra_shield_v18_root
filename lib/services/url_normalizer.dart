import 'dart:convert' show utf8;

import 'url_confusables.dart';

// مطبّع الروابط: بياخد أي نص (حتى لو مموّه أو مكسور) ويطلّع شكل نظيف ومنظّم
// نقدر نحلله. مبني على سلوك المتصفحات (WHATWG URL) في الأماكن اللي المحتالين
// بيستغلوا فيها اختلاف الأدوات. مفيش أي استثناء بيطلع من هنا: أي مشكلة بتتسجّل
// في [NormalizedUrl.errors] ويفضل باقي التحليل شغال.
//
// الترتيب المهم: بنقسم الرابط على حدوده الخام (scheme / @ / host / path) الأول،
// وبعدين نفك الترميز لكل جزء لوحده. العكس (فك الترميز الأول ثم التقسيم) خطر:
// https://paypal.com%2F@evil.com بيتحول لـ paypal.com/@evil.com والمتصفح فعليًا
// رايح لـ evil.com.

/// صيغة كتابة عنوان الـ IPv4.
enum IpForm {
  /// a.b.c.d عشري عادي بدون أصفار زائدة.
  standard,

  /// رقم واحد (عشري أو 0x أو ثُماني): 3232235777 أو 0x7f000001.
  dword,

  /// أربعة أجزاء لكن فيها hex أو ثُماني أو أصفار زائدة: 0x7f.0.0.1 أو 0177.0.0.1.
  radix,

  /// جزءان أو ثلاثة: 127.1
  short,

  /// عنوان IPv6 بين أقواس.
  ipv6,
}

class IpInfo {
  const IpInfo({
    required this.canonical,
    required this.form,
    required this.kind,
    this.radixes = const <String>[],
  });

  /// الشكل القياسي: a.b.c.d أو نص IPv6 بحروف صغيرة.
  final String canonical;
  final IpForm form;

  /// public | loopback | private | linklocal | unspecified | reserved
  final String kind;

  /// الأنظمة العددية المستخدمة في الكتابة: hex / octal.
  final List<String> radixes;

  /// الكتابة مموّهة (مش عشري قياسي ومش IPv6 عادي).
  bool get obfuscated => form != IpForm.standard && form != IpForm.ipv6;

  /// عنوان داخلي (ما يخصش الإنترنت العام).
  bool get isInternal => kind != 'public';
}

class NormalizedUrl {
  const NormalizedUrl({
    required this.original,
    this.cleanUrl = '',
    this.fetchUrl = '',
    this.scheme = '',
    this.schemeAssumed = false,
    this.schemeMalformed = false,
    this.dangerousScheme = '',
    this.userInfo = '',
    this.atCount = 0,
    this.host = '',
    this.hostAsWritten = '',
    this.unicodeHost = '',
    this.skeletonHost = '',
    this.ip,
    this.port,
    this.path = '',
    this.query = '',
    this.fragment = '',
    this.encodingRounds = 0,
    this.hostEncoded = false,
    this.hostDelimiterTrick = false,
    this.invisibleRemoved = 0,
    this.directionMarksRemoved = 0,
    this.invisibleKinds = const <int>[],
    this.backslashInAuthority = false,
    this.rfcHost = '',
    this.spaceInAuthority = false,
    this.defanged = false,
    this.compatFolded = false,
    this.separatorLookalike = false,
    this.badPunycode = false,
    this.truncated = false,
    this.errors = const <String>[],
  });

  /// النص الأصلي كما وصل (قبل أي تعديل).
  final String original;

  /// نسخة للعرض والتحليل: كل الترميز متفكوك، الحروف الخفية متشالة. مش للفتح.
  final String cleanUrl;

  /// نسخة تصلح للاتصال (بنية خام سليمة، المضيف بشكله القياسي). فاضية لو الرابط
  /// مش صالح أو لو نوعه خطير (javascript: ...).
  final String fetchUrl;

  final String scheme;
  final bool schemeAssumed;
  final bool schemeMalformed;

  /// اسم النوع الخطير لو الرابط javascript: أو data: ... وإلا فاضي.
  final String dangerousScheme;

  /// الجزء قبل @ (بعد فك الترميز).
  final String userInfo;
  final int atCount;

  /// المضيف القياسي: حروف صغيرة، IP بصيغته العشرية، IPv6 بدون أقواس.
  final String host;

  /// المضيف كما كُتب (بعد فك الترميز فقط) لشرح التمويه للمستخدم.
  final String hostAsWritten;

  /// المضيف بعد فك punycode (xn--) لفحص الحروف.
  final String unicodeHost;

  /// المضيف بعد تحويل الحروف المتشابهة لحروفها اللاتينية.
  final String skeletonHost;

  final IpInfo? ip;
  final int? port;
  final String path;
  final String query;
  final String fragment;

  /// أكبر عدد جولات فك ترميز احتاجها أي جزء (0 = مفيش ترميز).
  final int encodingRounds;

  /// اسم الدومين نفسه كان مكتوب بترميز %XX.
  final bool hostEncoded;

  /// فك الترميز كشف فاصل (/ ? # @ \) جوه المضيف: أدوات بتفسره بشكل والمتصفح بشكل.
  final bool hostDelimiterTrick;

  /// عدد الحروف الخفية/التحكم اللي اتشالت من وسط الرابط (مش من أطرافه) وتُعتبر تمويهًا:
  /// صفر العرض، محارف قلب الاتجاه، تحكم، Tag... وكمان علامات الاتجاه (LRM/RLM/ALM) لو
  /// ظهرت جوه اسم الموقع أو بيانات الدخول (مكان ملوش أي استخدام طبيعي).
  final int invisibleRemoved;

  /// علامات اتجاه طبيعية (LRM U+200E / RLM U+200F / ALM U+061C) اتشالت من مسار الرابط أو
  /// استعلامه من غير ما تتحسب تمويهًا (النص العربي المختلط وتطبيقات المراسلة بتضيفها).
  final int directionMarksRemoved;

  /// أكواد الحروف الخفية اللي اتعدّت في [invisibleRemoved] (مرتبة، حد أقصى 6) لعرض السبب الحقيقي.
  final List<int> invisibleKinds;

  /// \ قبل نهاية الـ authority (المتصفح بيعتبرها /).
  final bool backslashInAuthority;

  /// لو أداة بتقرأ الرابط حسب RFC 3986 (بتعتبر \ حرف عادي) هتشوف مضيف مختلف عن
  /// اللي المتصفح هيروحله (https://evil.com\@google.com): هنا المضيف اللي هتشوفه
  /// الأداة. فاضي لو مفيش اختلاف.
  final String rfcHost;
  final bool spaceInAuthority;

  /// الرابط كان مكتوب بصيغة defang (hxxp / [.]).
  final bool defanged;

  /// المضيف فيه حروف مزخرفة/عريضة بتتحول لحروف عادية في المتصفح.
  final bool compatFolded;

  /// المضيف فيه رمز بيشبه / أو . أو @ (مثل ∕).
  final bool separatorLookalike;

  /// فيه ليبل xn-- مش قابل للفك.
  final bool badPunycode;

  /// النص كان أطول من الحد وتم تحليل أوله فقط.
  final bool truncated;

  /// أكواد المشاكل: empty, no_host, bad_host_char, bad_numeric_host, bad_ipv6,
  /// bad_port, bad_host.
  final List<String> errors;

  bool get hasIp => ip != null;

  /// قابل للتحليل كرابط ويب (فيه مضيف ومفيش أخطاء بنيوية).
  bool get valid => errors.isEmpty && host.isNotEmpty && dangerousScheme.isEmpty;
}

class _Decoded {
  const _Decoded(this.text, this.rounds);
  final String text;
  final int rounds;
}

/// عدّاد الحروف الخفية اللي اتشالت أثناء التطبيع (يتجمع من كل أجزاء الرابط).
class _HiddenAcc {
  /// حروف خفية تُعتبر تمويهًا.
  int removed = 0;

  /// علامات اتجاه طبيعية اتجاهلت.
  int marks = 0;
  final Set<int> kinds = <int>{};

  List<int> get kindList {
    final l = kinds.toList()..sort();
    return l.length > 6 ? l.sublist(0, 6) : l;
  }
}

class _Split {
  String scheme = '';
  bool assumed = false;
  bool malformed = false;
  bool backslash = false;
  String rfcHost = '';
  bool spaceInAuth = false;
  String userInfo = '';
  int atCount = 0;
  String host = '';
  String portText = '';
  String path = '';
  String query = '';
  String fragment = '';
  bool hasQuery = false;
  bool hasFragment = false;
  final List<String> errors = <String>[];
}

class UrlNormalizer {
  UrlNormalizer._();

  /// أقصى طول بنحلله (حماية من نصوص ضخمة). الباقي بيتقطع ويتعلّم truncated.
  static const int maxLength = 4096;

  /// أقصى عدد جولات لفك الترميز المتكرر.
  static const int maxDecodeRounds = 6;

  static const Set<String> _webSchemes = <String>{
    'http', 'https', 'ftp', 'ftps', 'ws', 'wss',
  };

  static final RegExp _dangerRe = RegExp(
      r'^(javascript|data|vbscript|file|intent|blob|about):',
      caseSensitive: false);
  static final RegExp _schemeRe = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):([/\\]*)');
  static final RegExp _noColonRe =
      RegExp(r'^(https?|ftps?)([/\\]{2,})', caseSensitive: false);
  static final RegExp _protoRelRe = RegExp(r'^[/\\]{2,}');
  static final RegExp _hxxpRe = RegExp(r'^hxxp(s?)(?=[:\[/\\])', caseSensitive: false);
  static final RegExp _defangDot =
      RegExp(r'\[\.\]|\(\.\)|\{\.\}|\[dot\]|\(dot\)', caseSensitive: false);
  static final RegExp _defangColon = RegExp(r'\[:\]|\[://\]');
  static final RegExp _defangAt = RegExp(r'\[@\]|\[at\]', caseSensitive: false);

  // ---------------------------------------------------------------------
  // أحرف خفية ومسافات
  // ---------------------------------------------------------------------

  /// حروف تحكم/تنسيق غير مرئية (صفر العرض، اتجاه النص، تحكم C0/C1، علامات ...).
  /// المتصفحات بتشيل tab و CR و LF من الرابط تلقائيًا، ومحتالين بيستخدموها لكسر الفلاتر.
  static bool isInvisible(int r) {
    if (r <= 0x1F || (r >= 0x7F && r <= 0x9F)) return true;
    switch (r) {
      case 0xAD:
      case 0x34F:
      case 0x61C:
      case 0x115F:
      case 0x1160:
      case 0x17B4:
      case 0x17B5:
      case 0x3164:
      case 0xFEFF:
      case 0xFFA0:
        return true;
    }
    if (r >= 0x180B && r <= 0x180E) return true;
    if (r >= 0x200B && r <= 0x200F) return true;
    if (r >= 0x2028 && r <= 0x202E) return true;
    if (r >= 0x2060 && r <= 0x206F) return true;
    if (r >= 0xFE00 && r <= 0xFE0F) return true;
    if (r >= 0xFFF9 && r <= 0xFFFB) return true;
    if (r >= 0xE0000 && r <= 0xE0FFF) return true;
    return false;
  }

  static bool isSpace(int r) =>
      r == 0x20 ||
      r == 0xA0 ||
      r == 0x1680 ||
      (r >= 0x2000 && r <= 0x200A) ||
      r == 0x202F ||
      r == 0x205F ||
      r == 0x3000;

  /// علامات الاتجاه الطبيعية: LRM / RLM / ALM.
  static bool isDirectionMark(int r) => r == 0x200E || r == 0x200F || r == 0x61C;

  /// يشيل الحروف الخفية من [s] ويسجّلها في [acc]. علامات الاتجاه الطبيعية بتتشال
  /// بدون ما تتحسب تمويهًا إلا لو [strictMarks] = true (جوه المضيف وبيانات الدخول).
  static String _stripInvisible(String s, _HiddenAcc acc, {required bool strictMarks}) {
    var any = false;
    final sb = StringBuffer();
    for (final r in s.runes) {
      if (!isInvisible(r)) {
        sb.writeCharCode(r);
        continue;
      }
      any = true;
      if (isDirectionMark(r) && !strictMarks) {
        acc.marks++;
      } else {
        acc.removed++;
        acc.kinds.add(r);
      }
    }
    return any ? sb.toString() : s;
  }

  /// الجزء بين بروتوكول:// وأول / ? # \ (المضيف وبيانات الدخول والمنفذ).
  static String _authorityOf(String s) {
    var t = s;
    final m = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:[/\\]+').firstMatch(t);
    if (m != null) {
      t = t.substring(m.end);
    } else {
      final lead = RegExp(r'^[/\\]{2,}').firstMatch(t);
      if (lead != null) t = t.substring(lead.end);
    }
    final end = t.indexOf(RegExp(r'[/\\?#]'));
    return end < 0 ? t : t.substring(0, end);
  }

  /// يشيل المسافات والحروف الخفية من أول النص وآخره (بدون ما نعتبرها تمويه:
  /// تطبيقات المراسلة بتضيفها كتير).
  static String _trimEnds(String s) {
    final r = s.runes.toList();
    var a = 0;
    var b = r.length;
    while (a < b && (isInvisible(r[a]) || isSpace(r[a]))) {
      a++;
    }
    while (b > a && (isInvisible(r[b - 1]) || isSpace(r[b - 1]))) {
      b--;
    }
    return String.fromCharCodes(r.sublist(a, b));
  }

  static String _removeSpaces(String s) {
    final sb = StringBuffer();
    for (final r in s.runes) {
      if (!isSpace(r)) sb.writeCharCode(r);
    }
    return sb.toString();
  }

  static bool _hasSpace(String s) => s.runes.any(isSpace);

  static String _encodeSpaces(String s) {
    if (!_hasSpace(s)) return s;
    final sb = StringBuffer();
    for (final r in s.runes) {
      if (isSpace(r)) {
        sb.write('%20');
      } else {
        sb.writeCharCode(r);
      }
    }
    return sb.toString();
  }

  // ---------------------------------------------------------------------
  // ترميز النسبة المئوية
  // ---------------------------------------------------------------------

  static int _hexVal(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    return -1;
  }

  static bool _isPct(String s, int i) =>
      i + 2 < s.length &&
      s.codeUnitAt(i) == 0x25 &&
      _hexVal(s.codeUnitAt(i + 1)) >= 0 &&
      _hexVal(s.codeUnitAt(i + 2)) >= 0;

  static void _appendBytes(StringBuffer out, List<int> bytes) {
    try {
      out.write(utf8.decode(bytes));
    } on FormatException {
      // UTF-8 غير صالح: نفك الـ ASCII ونسيب باقي البايتات كما هي (%XX).
      for (final b in bytes) {
        if (b < 0x80) {
          out.writeCharCode(b);
        } else {
          out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
        }
      }
    }
  }

  /// جولة واحدة من فك %XX (UTF-8). التسلسلات غير الصالحة بتفضل زي ما هي.
  static String percentDecode(String s) {
    if (!s.contains('%')) return s;
    final out = StringBuffer();
    var i = 0;
    var plain = 0; // بداية الجزء العادي اللي لسه ما اتكتبش
    while (i < s.length) {
      if (_isPct(s, i)) {
        if (i > plain) out.write(s.substring(plain, i));
        final bytes = <int>[];
        var j = i;
        while (j < s.length && _isPct(s, j)) {
          bytes.add(_hexVal(s.codeUnitAt(j + 1)) * 16 + _hexVal(s.codeUnitAt(j + 2)));
          j += 3;
        }
        _appendBytes(out, bytes);
        i = j;
        plain = j;
      } else {
        i++;
      }
    }
    if (plain < s.length) out.write(s.substring(plain));
    return out.toString();
  }

  /// فك ترميز متكرر (%252F -> %2F -> /) لحد ما النص يثبت أو نوصل للحد الأقصى.
  /// بيشيل الحروف الخفية اللي بتظهر بعد كل جولة (%0A و %E2%80%8B).
  static _Decoded _decodeAll(String s, _HiddenAcc acc, {required bool strictMarks}) {
    var cur = s;
    var rounds = 0;
    while (rounds < maxDecodeRounds) {
      final d = percentDecode(cur);
      if (d == cur) break;
      cur = _stripInvisible(d, acc, strictMarks: strictMarks);
      rounds++;
    }
    return _Decoded(cur, rounds);
  }

  // ---------------------------------------------------------------------
  // المضيف: طي الحروف المزخرفة، punycode، IP
  // ---------------------------------------------------------------------

  /// بيطبّق نفس تحويلات المتصفح على المضيف: حروف عريضة/مزخرفة -> عادية، نقاط
  /// بديلة -> '.'، وبعدين حروف صغيرة. بيرجّع (النص، هل اتغيرت حروف/أرقام).
  static List<Object> _foldHost(String h) {
    final sb = StringBuffer();
    var compat = false;
    for (final r in h.runes) {
      final f = Confusables.foldCompat(r);
      if (f == null) {
        sb.writeCharCode(r);
        continue;
      }
      final c = f.codeUnitAt(0);
      final alnum = (c >= 0x30 && c <= 0x39) ||
          (c >= 0x41 && c <= 0x5A) ||
          (c >= 0x61 && c <= 0x7A);
      if (alnum) compat = true;
      sb.write(f);
    }
    return <Object>[sb.toString().toLowerCase(), compat];
  }

  static String _stripTrailingDots(String s) {
    var e = s.length;
    while (e > 0 && s.codeUnitAt(e - 1) == 0x2E) {
      e--;
    }
    return s.substring(0, e);
  }

  /// فك punycode (RFC 3492). null لو المدخل غير صالح.
  static String? decodePunycode(String input) {
    if (input.isEmpty || input.length > 100) return null;
    const base = 36;
    const tMin = 1;
    const tMax = 26;
    final output = <int>[];
    var b = input.lastIndexOf('-');
    if (b < 0) b = 0;
    for (var j = 0; j < b; j++) {
      final c = input.codeUnitAt(j);
      if (c >= 0x80) return null;
      output.add(c);
    }
    var n = 128;
    var i = 0;
    var bias = 72;
    var idx = b > 0 ? b + 1 : 0;
    while (idx < input.length) {
      final oldi = i;
      var w = 1;
      for (var k = base;; k += base) {
        if (idx >= input.length) return null;
        final cp = input.codeUnitAt(idx++);
        int digit;
        if (cp >= 0x30 && cp <= 0x39) {
          digit = cp - 22;
        } else if (cp >= 0x41 && cp <= 0x5A) {
          digit = cp - 0x41;
        } else if (cp >= 0x61 && cp <= 0x7A) {
          digit = cp - 0x61;
        } else {
          return null;
        }
        i += digit * w;
        if (i > 0x7FFFFFFF) return null;
        final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
        if (digit < t) break;
        w *= base - t;
        if (w > 0x7FFFFFFF) return null;
      }
      final out = output.length + 1;
      bias = _adapt(i - oldi, out, oldi == 0);
      n += i ~/ out;
      if (n > 0x10FFFF) return null;
      i %= out;
      output.insert(i, n);
      i++;
    }
    return String.fromCharCodes(output);
  }

  /// ترميز Punycode (RFC 3492) لجزء واحد (label) بدون البادئة xn--. null لو فشل.
  /// بيُستخدم لعرض المضيف الدولي بصيغة ASCII.
  static String? encodePunycode(String input) {
    const base = 36;
    const tMin = 1;
    const tMax = 26;
    final cps = input.runes.toList();
    if (cps.isEmpty || cps.length > 100) return null;
    final out = StringBuffer();
    for (final c in cps) {
      if (c < 0x80) out.writeCharCode(c);
    }
    final b = out.length;
    var h = b;
    if (b > 0) out.write('-');
    var n = 128;
    var delta = 0;
    var bias = 72;
    while (h < cps.length) {
      var m = 0x7FFFFFFF;
      for (final c in cps) {
        if (c >= n && c < m) m = c;
      }
      if (m - n > (0x7FFFFFFF - delta) ~/ (h + 1)) return null;
      delta += (m - n) * (h + 1);
      n = m;
      for (final c in cps) {
        if (c < n) {
          delta++;
          if (delta > 0x7FFFFFFF) return null;
        }
        if (c == n) {
          var q = delta;
          for (var k = base;; k += base) {
            final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
            if (q < t) break;
            out.writeCharCode(_punyDigit(t + (q - t) % (base - t)));
            q = (q - t) ~/ (base - t);
          }
          out.writeCharCode(_punyDigit(q));
          bias = _adapt(delta, h + 1, h == b);
          delta = 0;
          h++;
        }
      }
      delta++;
      n++;
    }
    return out.toString();
  }

  static int _punyDigit(int d) => d < 26 ? d + 0x61 : d - 26 + 0x30;

  static int _adapt(int delta, int numPoints, bool first) {
    var d = first ? delta ~/ 700 : delta ~/ 2;
    d += d ~/ numPoints;
    var k = 0;
    while (d > ((36 - 1) * 26) ~/ 2) {
      d ~/= 36 - 1;
      k += 36;
    }
    return k + (((36 - 1 + 1) * d) ~/ (d + 38));
  }

  /// فك أي ليبل xn-- لشكله الأصلي. بيرجّع القائمة المفكوكة + هل فشل أي ليبل.
  static List<Object> _unicodeLabels(List<String> labels) {
    var bad = false;
    final out = <String>[];
    for (final l in labels) {
      if (l.startsWith('xn--')) {
        final d = decodePunycode(l.substring(4));
        if (d == null || d.isEmpty || !d.runes.any((r) => r >= 0x80)) {
          bad = true;
          out.add(l);
        } else {
          out.add(d.toLowerCase());
        }
      } else {
        out.add(l);
      }
    }
    return <Object>[out, bad];
  }

  // ---------------------------------------------------------------------
  // IP
  // ---------------------------------------------------------------------

  static String _v4Kind(int a, int b) {
    if (a == 0) return 'unspecified';
    if (a == 127) return 'loopback';
    if (a == 10) return 'private';
    if (a == 172 && b >= 16 && b <= 31) return 'private';
    if (a == 192 && b == 168) return 'private';
    if (a == 100 && b >= 64 && b <= 127) return 'private';
    if (a == 169 && b == 254) return 'linklocal';
    if (a >= 224) return 'reserved';
    return 'public';
  }

  /// نفس قواعد inet_aton / المتصفحات: 1-4 أجزاء، كل جزء عشري أو 0x أو ثُماني،
  /// والجزء الأخير بيملأ باقي البايتات. بيرجّع null لو مش عنوان صالح.
  static IpInfo? parseIpv4(String host) {
    final parts = host.split('.');
    if (parts.length > 1 && parts.last.isEmpty) parts.removeLast();
    if (parts.isEmpty || parts.length > 4) return null;
    final nums = <int>[];
    final radixes = <String>[];
    for (final p in parts) {
      if (p.isEmpty) return null;
      var radix = 10;
      var s = p;
      if (s.length >= 2 && (s.startsWith('0x') || s.startsWith('0X'))) {
        radix = 16;
        s = s.substring(2);
        if (!radixes.contains('hex')) radixes.add('hex');
      } else if (s.length >= 2 && s.startsWith('0')) {
        radix = 8;
        s = s.substring(1);
        if (!radixes.contains('octal')) radixes.add('octal');
      }
      var value = 0;
      if (s.isNotEmpty) {
        var z = 0;
        while (z < s.length - 1 && s.codeUnitAt(z) == 0x30) {
          z++;
        }
        s = s.substring(z);
        if (s.length > 11) return null;
        for (final c in s.codeUnits) {
          final h = _hexVal(c);
          if (h < 0 || h >= radix) return null;
          value = value * radix + h;
        }
      }
      nums.add(value);
    }
    for (var i = 0; i < nums.length - 1; i++) {
      if (nums[i] > 255) return null;
    }
    var limit = 1;
    for (var i = 0; i < 5 - nums.length; i++) {
      limit *= 256;
    }
    if (nums.last >= limit) return null;
    // الأجزاء الأولى بتاخد أوزان 2^24 ثم 2^16 ثم 2^8 من اليسار، والأخير بيملأ الباقي.
    var v = nums.last;
    var weight = 16777216;
    for (var i = 0; i < nums.length - 1; i++) {
      v += nums[i] * weight;
      weight ~/= 256;
    }
    final a = (v ~/ 16777216) % 256;
    final b = (v ~/ 65536) % 256;
    final c = (v ~/ 256) % 256;
    final d = v % 256;
    IpForm form;
    if (nums.length == 4 && radixes.isEmpty) {
      form = IpForm.standard;
    } else if (nums.length == 4) {
      form = IpForm.radix;
    } else if (nums.length == 1) {
      form = IpForm.dword;
    } else {
      form = IpForm.short;
    }
    return IpInfo(
      canonical: '$a.$b.$c.$d',
      form: form,
      kind: _v4Kind(a, b),
      radixes: radixes,
    );
  }

  static bool _strictV4(String s) {
    final p = s.split('.');
    if (p.length != 4) return false;
    for (final x in p) {
      if (x.isEmpty || x.length > 3) return false;
      for (final c in x.codeUnits) {
        if (c < 0x30 || c > 0x39) return false;
      }
      if (int.parse(x) > 255) return false;
    }
    return true;
  }

  /// IPv6 بسيط وصارم (بدون zone id). s بحروف صغيرة وبدون أقواس.
  static IpInfo? parseIpv6(String s) {
    if (s.isEmpty || s.length > 45) return null;
    for (final c in s.codeUnits) {
      if (!(c == 0x3A || c == 0x2E || _hexVal(c) >= 0)) return null;
    }
    if (s.contains(':::')) return null;
    final dbl = s.indexOf('::');
    if (dbl >= 0 && s.indexOf('::', dbl + 1) >= 0) return null;
    final head = dbl >= 0 ? s.substring(0, dbl) : s;
    final tail = dbl >= 0 ? s.substring(dbl + 2) : '';
    final all = <String>[
      if (head.isNotEmpty) ...head.split(':'),
      if (tail.isNotEmpty) ...tail.split(':'),
    ];
    var count = 0;
    for (var i = 0; i < all.length; i++) {
      final g = all[i];
      if (g.isEmpty) return null;
      if (g.contains('.')) {
        if (i != all.length - 1 || !_strictV4(g)) return null;
        count += 2;
      } else {
        if (g.length > 4) return null;
        count += 1;
      }
    }
    if (dbl >= 0 ? count > 7 : count != 8) return null;
    var kind = 'public';
    if (s == '::') {
      kind = 'unspecified';
    } else if (s == '::1') {
      kind = 'loopback';
    } else if (s.startsWith('::ffff:') && s.substring(7).contains('.')) {
      final inner = parseIpv4(s.substring(7));
      kind = inner == null ? 'reserved' : inner.kind;
    } else if (s.startsWith('fe8') ||
        s.startsWith('fe9') ||
        s.startsWith('fea') ||
        s.startsWith('feb')) {
      kind = 'linklocal';
    } else if (s.startsWith('fc') || s.startsWith('fd')) {
      kind = 'private';
    }
    return IpInfo(canonical: s, form: IpForm.ipv6, kind: kind);
  }

  /// المضيف "بينتهي برقم" (آخر ليبل أرقام فقط أو 0x...). المتصفح وقتها بيعامله IPv4
  /// وبيرفض الرابط لو مش IP صالح.
  static bool _endsInNumber(String host) {
    final parts = host.split('.');
    if (parts.length > 1 && parts.last.isEmpty) parts.removeLast();
    if (parts.isEmpty) return false;
    final last = parts.last;
    if (last.isEmpty) return false;
    var digits = true;
    for (final c in last.codeUnits) {
      if (c < 0x30 || c > 0x39) {
        digits = false;
        break;
      }
    }
    if (digits) return true;
    if (last.length >= 2 && (last.startsWith('0x') || last.startsWith('0X'))) {
      for (final c in last.substring(2).codeUnits) {
        if (_hexVal(c) < 0) return false;
      }
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------
  // التقسيم الخام
  // ---------------------------------------------------------------------

  static String _splitScheme(String t, _Split r) {
    final m = _schemeRe.firstMatch(t);
    if (m != null) {
      final sch = m.group(1)!.toLowerCase();
      final slashes = m.group(2)!;
      if (_webSchemes.contains(sch)) {
        r.scheme = sch;
        r.malformed = slashes != '//';
        return t.substring(m.end);
      }
      if (slashes.length >= 2) {
        r.scheme = sch;
        return t.substring(m.end);
      }
      // غير كده مش بروتوكول (مثلاً example.com:8080): بنكمل كمضيف.
    }
    final n = _noColonRe.firstMatch(t);
    if (n != null) {
      r.scheme = n.group(1)!.toLowerCase();
      r.malformed = true;
      return t.substring(n.end);
    }
    r.assumed = true;
    r.scheme = 'https';
    final p = _protoRelRe.firstMatch(t);
    if (p != null) return t.substring(p.end);
    return t;
  }

  static _Split _split(String t) {
    final r = _Split();
    final rest = _splitScheme(t, r);

    var end = rest.length;
    for (var i = 0; i < rest.length; i++) {
      final c = rest[i];
      if (c == '/' || c == '\\' || c == '?' || c == '#') {
        end = i;
        if (c == '\\') r.backslash = true;
        break;
      }
    }
    if (r.backslash) {
      // قراءة RFC 3986: \ حرف عادي، والـ authority بتنتهي عند / ? # فقط.
      var rfcEnd = rest.length;
      for (var i = 0; i < rest.length; i++) {
        final c = rest[i];
        if (c == '/' || c == '?' || c == '#') {
          rfcEnd = i;
          break;
        }
      }
      final rfcAuth = rest.substring(0, rfcEnd);
      final at2 = rfcAuth.lastIndexOf('@');
      if (at2 >= 0) {
        var h = rfcAuth.substring(at2 + 1);
        final colon = h.lastIndexOf(':');
        if (colon >= 0) h = h.substring(0, colon);
        r.rfcHost = h.toLowerCase();
      }
    }
    var auth = rest.substring(0, end);
    final remainder = rest.substring(end);

    final hash = remainder.indexOf('#');
    if (hash >= 0) {
      r.hasFragment = true;
      r.fragment = remainder.substring(hash + 1);
    }
    final before = hash >= 0 ? remainder.substring(0, hash) : remainder;
    final q = before.indexOf('?');
    if (q >= 0) {
      r.hasQuery = true;
      r.query = before.substring(q + 1);
    }
    r.path = (q >= 0 ? before.substring(0, q) : before).replaceAll('\\', '/');

    if (_hasSpace(auth)) {
      r.spaceInAuth = true;
      auth = _removeSpaces(auth);
    }
    r.atCount = '@'.allMatches(auth).length;
    final at = auth.lastIndexOf('@');
    if (at >= 0) {
      r.userInfo = auth.substring(0, at);
      auth = auth.substring(at + 1);
    }
    if (auth.startsWith('[')) {
      final close = auth.indexOf(']');
      if (close < 0) {
        r.errors.add('bad_ipv6');
        r.host = auth;
      } else {
        r.host = auth.substring(0, close + 1);
        final after = auth.substring(close + 1);
        if (after.startsWith(':')) {
          r.portText = after.substring(1);
        } else if (after.isNotEmpty) {
          r.errors.add('bad_host');
        }
      }
    } else {
      final colon = auth.lastIndexOf(':');
      if (colon >= 0) {
        r.host = auth.substring(0, colon);
        r.portText = auth.substring(colon + 1);
      } else {
        r.host = auth;
      }
    }
    return r;
  }

  /// صيغة defang (hxxp، [.]) -> رابط عادي. بيرجّع النص الجديد وهل اتغير.
  static List<Object> _refang(String s) {
    var t = s;
    var changed = false;
    final m = _hxxpRe.firstMatch(t);
    if (m != null) {
      t = 'http${m.group(1)}${t.substring(m.end)}';
      changed = true;
    }
    final t2 = t
        .replaceAll(_defangDot, '.')
        .replaceAll(_defangColon, ':')
        .replaceAll(_defangAt, '@');
    if (t2 != t) changed = true;
    return <Object>[t2, changed];
  }

  // ---------------------------------------------------------------------
  // الدالة الرئيسية
  // ---------------------------------------------------------------------

  /// يطبّع أي نص مدخل. ما بيرميش استثناءات.
  static NormalizedUrl normalize(String input) {
    try {
      return _normalize(input);
    } catch (_) {
      // شبكة أمان أخيرة: أي خطأ غير متوقع = رابط غير قابل للتحليل (مش "آمن").
      return NormalizedUrl(
        original: input,
        errors: const <String>['bad_host'],
      );
    }
  }

  static NormalizedUrl _normalize(String input) {
    var s = input;
    var truncated = false;
    if (s.length > maxLength) {
      var cut = maxLength;
      final last = s.codeUnitAt(cut - 1);
      if (last >= 0xD800 && last <= 0xDBFF) cut--; // ما نقطعش في نص زوج بديل
      s = s.substring(0, cut);
      truncated = true;
    }

    s = _trimEnds(s);
    if (s.isEmpty) {
      return NormalizedUrl(original: input, errors: const <String>['empty']);
    }

    // الحروف الخفية: علامات الاتجاه الطبيعية (LRM/RLM/ALM) في المسار والاستعلام مش تمويه،
    // لكنها جوه المضيف أو بيانات الدخول (قبل أول / ? #) تمويه.
    final hidden = _HiddenAcc();
    final authMarks = _authorityOf(s).runes.where(isDirectionMark).toList();
    s = _stripInvisible(s, hidden, strictMarks: false);
    if (authMarks.isNotEmpty) {
      hidden.marks -= authMarks.length;
      hidden.removed += authMarks.length;
      hidden.kinds.addAll(authMarks);
    }

    final rf = _refang(s);
    s = rf[0] as String;
    final defanged = rf[1] as bool;

    // نوع خطير (javascript: ...) حتى لو كان مموّهًا بالترميز.
    final dangerAcc = _HiddenAcc();
    final dm = _dangerRe.firstMatch(s) ??
        _dangerRe.firstMatch(_decodeAll(s, dangerAcc, strictMarks: false).text);
    if (dm != null) {
      final dec = _decodeAll(s, hidden, strictMarks: false);
      return NormalizedUrl(
        original: input,
        cleanUrl: dec.text,
        scheme: dm.group(1)!.toLowerCase(),
        dangerousScheme: dm.group(1)!.toLowerCase(),
        encodingRounds: dec.rounds,
        invisibleRemoved: hidden.removed,
        directionMarksRemoved: hidden.marks,
        invisibleKinds: hidden.kindList,
        defanged: defanged,
        truncated: truncated,
      );
    }

    final r = _split(s);
    final errors = <String>[...r.errors];

    // ---- المضيف ----
    final hd = _decodeAll(r.host, hidden, strictMarks: true);
    var rounds = hd.rounds;
    final hostEncoded = hd.rounds > 0;
    final hostText = hd.text;

    var host = '';
    var unicodeHost = '';
    var skeletonHost = '';
    IpInfo? ip;
    var compat = false;
    var sepLook = false;
    var delimTrick = false;
    var badPuny = false;

    if (hostText.startsWith('[')) {
      if (hostText.endsWith(']') && hostText.length > 2) {
        final inner = hostText.substring(1, hostText.length - 1).toLowerCase();
        ip = parseIpv6(inner);
        if (ip == null) {
          errors.add('bad_ipv6');
        } else {
          host = ip.canonical;
          unicodeHost = host;
          skeletonHost = host;
        }
      } else if (!errors.contains('bad_ipv6')) {
        errors.add('bad_ipv6');
      }
    } else {
      final fh = _foldHost(hostText);
      var h = _stripTrailingDots(fh[0] as String);
      compat = fh[1] as bool;
      var bad = false;
      final srcRunes = hostText.runes.toSet();
      for (final c in h.runes) {
        if (c == 0x2F || c == 0x5C || c == 0x3F || c == 0x23 || c == 0x40 || c == 0x3A) {
          if (!srcRunes.contains(c)) {
            sepLook = true; // الفاصل ظهر بعد طي حرف مزخرف/عريض (مثل ／)
          } else if (hostEncoded) {
            delimTrick = true; // الفاصل ظهر بعد فك الترميز
          }
          bad = true;
        } else if (c <= 0x20 ||
            c == 0x25 ||
            c == 0x3C ||
            c == 0x3E ||
            c == 0x5B ||
            c == 0x5D ||
            c == 0x5E ||
            c == 0x7C ||
            c == 0x22) {
          bad = true;
        }
      }
      if (h.isEmpty) {
        errors.add('no_host');
      } else if (bad) {
        errors.add('bad_host_char');
      } else if (_endsInNumber(h)) {
        ip = parseIpv4(h);
        if (ip == null) {
          errors.add('bad_numeric_host');
        } else {
          h = ip.canonical;
        }
      }
      host = h;
      if (host.isNotEmpty) {
        if (ip != null) {
          unicodeHost = host;
          skeletonHost = host;
        } else {
          final ul = _unicodeLabels(host.split('.'));
          final labels = ul[0] as List<String>;
          badPuny = ul[1] as bool;
          unicodeHost = labels.join('.');
          skeletonHost =
              labels.map((l) => Confusables.scanLabel(l).skeleton).join('.');
        }
      }
    }

    // ---- المنفذ ----
    int? port;
    if (r.portText.isNotEmpty) {
      var digits = r.portText.length <= 6;
      for (final c in r.portText.codeUnits) {
        if (c < 0x30 || c > 0x39) digits = false;
      }
      final v = digits ? int.parse(r.portText) : -1;
      if (v < 0 || v > 65535) {
        errors.add('bad_port');
      } else {
        port = v;
      }
    }

    // ---- باقي الأجزاء ----
    final ud = _decodeAll(r.userInfo, hidden, strictMarks: true);
    final pd = _decodeAll(r.path, hidden, strictMarks: false);
    final qd = _decodeAll(r.query, hidden, strictMarks: false);
    final fd = _decodeAll(r.fragment, hidden, strictMarks: false);
    for (final x in <_Decoded>[ud, pd, qd, fd]) {
      if (x.rounds > rounds) rounds = x.rounds;
    }

    final ok = errors.isEmpty && host.isNotEmpty;
    final hostOut = ip != null && ip.form == IpForm.ipv6 ? '[$host]' : host;

    final clean = StringBuffer('${r.scheme}://');
    if (ud.text.isNotEmpty) clean.write('${ud.text}@');
    clean.write(hostOut);
    if (port != null) clean.write(':$port');
    clean.write(_encodeSpaces(pd.text));
    if (r.hasQuery) clean.write('?${_encodeSpaces(qd.text)}');
    if (r.hasFragment) clean.write('#${_encodeSpaces(fd.text)}');

    var fetch = '';
    if (ok) {
      final f = StringBuffer('${r.scheme}://');
      if (r.userInfo.isNotEmpty) f.write('${r.userInfo}@');
      f.write(hostOut);
      if (port != null) f.write(':$port');
      f.write(_encodeSpaces(r.path));
      if (r.hasQuery) f.write('?${_encodeSpaces(r.query)}');
      if (r.hasFragment) f.write('#${_encodeSpaces(r.fragment)}');
      fetch = f.toString();
    }

    return NormalizedUrl(
      original: input,
      cleanUrl: clean.toString(),
      fetchUrl: fetch,
      scheme: r.scheme,
      schemeAssumed: r.assumed,
      schemeMalformed: r.malformed,
      userInfo: ud.text,
      atCount: r.atCount,
      host: host,
      hostAsWritten: hostText,
      unicodeHost: unicodeHost,
      skeletonHost: skeletonHost,
      ip: ip,
      port: port,
      path: pd.text,
      query: qd.text,
      fragment: fd.text,
      encodingRounds: rounds,
      hostEncoded: hostEncoded,
      hostDelimiterTrick: delimTrick,
      invisibleRemoved: hidden.removed,
      directionMarksRemoved: hidden.marks,
      invisibleKinds: hidden.kindList,
      backslashInAuthority: r.backslash,
      rfcHost: r.rfcHost.isNotEmpty && r.rfcHost != host ? r.rfcHost : '',
      spaceInAuthority: r.spaceInAuth,
      defanged: defanged,
      compatFolded: compat,
      separatorLookalike: sepLook,
      badPunycode: badPuny,
      truncated: truncated,
      errors: errors,
    );
  }
}
