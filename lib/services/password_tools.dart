import 'dart:math' as math;

class PasswordReport {
  const PasswordReport({
    required this.bits,
    required this.level,
    required this.label,
    required this.crackTime,
    required this.tips,
  });

  final double bits;
  final int level; // 0 (ضعيفة جدًا) ... 4 (ممتازة)
  final String label;
  final String crackTime;
  final List<String> tips;
}

class PasswordTools {
  PasswordTools._();

  static const List<String> _common = <String>[
    '123456', '12345678', '123456789', '1234567890', 'password', 'qwerty',
    'qwerty123', '111111', '000000', 'iloveyou', 'admin', 'letmein',
    'welcome', 'abc123', 'monkey', 'dragon', 'football', 'login', 'master',
    'passw0rd', 'p@ssw0rd', '1q2w3e', 'zaq12wsx', 'azerty', '11111111',
    'allah', 'mohamed', 'ahmed', 'egypt', 'cairo',
  ];

  static final RegExp _lower = RegExp(r'[a-z]');
  static final RegExp _upper = RegExp(r'[A-Z]');
  static final RegExp _digit = RegExp(r'[0-9]');
  static final RegExp _arabic = RegExp(r'[\u0600-\u06FF]');
  static final RegExp _symbol = RegExp(r'[^A-Za-z0-9\u0600-\u06FF\s]');
  static final RegExp _repeat = RegExp(r'(.)\1{2,}');

  static bool _hasSequence(String s) {
    for (var i = 0; i + 2 < s.length; i++) {
      final a = s.codeUnitAt(i);
      final b = s.codeUnitAt(i + 1);
      final c = s.codeUnitAt(i + 2);
      if ((b - a == 1 && c - b == 1) || (a - b == 1 && b - c == 1)) {
        return true;
      }
    }
    return false;
  }

  static String _fmtTime(double seconds) {
    if (seconds < 1) return 'لحظي';
    if (seconds < 60) return '${seconds.round()} ثانية';
    final min = seconds / 60;
    if (min < 60) return '${min.round()} دقيقة';
    final hr = min / 60;
    if (hr < 24) return '${hr.round()} ساعة';
    final day = hr / 24;
    if (day < 365) return '${day.round()} يوم';
    final yr = day / 365;
    if (yr < 1000) return '${yr.round()} سنة';
    if (yr < 1e6) return '${(yr / 1000).round()} ألف سنة';
    if (yr < 1e9) return '${(yr / 1e6).round()} مليون سنة';
    return 'أكثر من مليار سنة';
  }

  static PasswordReport analyze(String pw) {
    var pool = 0;
    if (_lower.hasMatch(pw)) pool += 26;
    if (_upper.hasMatch(pw)) pool += 26;
    if (_digit.hasMatch(pw)) pool += 10;
    if (_symbol.hasMatch(pw)) pool += 33;
    if (_arabic.hasMatch(pw)) pool += 36;
    if (pw.contains(' ')) pool += 1;
    if (pool < 2) pool = 2;

    var bits = pw.length * (math.log(pool) / math.ln2);
    final lower = pw.toLowerCase();
    final tips = <String>[];

    if (_common.contains(lower)) {
      bits = math.min(bits, 8.0);
      tips.add('كلمة سر شائعة جدًا وتُخمّن في ثوانٍ.');
    } else if (_common.any((c) => c.length >= 4 && lower.contains(c))) {
      bits *= 0.6;
      tips.add('تحتوي على كلمة أو نمط شائع.');
    }
    if (_repeat.hasMatch(pw)) {
      bits *= 0.8;
      tips.add('فيها أحرف مكررة متتالية.');
    }
    if (_hasSequence(lower)) {
      bits *= 0.8;
      tips.add('فيها تسلسل سهل (abc أو 123).');
    }
    if (RegExp(r'^[0-9]+$').hasMatch(pw)) {
      tips.add('أرقام فقط: أضف حروفًا ورموزًا.');
    }
    if (pw.length < 12) {
      tips.add('اجعلها 12 حرفًا على الأقل.');
    }
    if (pool < 40 && pw.length >= 12) {
      tips.add('نوّع بين الحروف الكبيرة والصغيرة والأرقام والرموز.');
    }

    int level;
    String label;
    if (bits < 28) {
      level = 0;
      label = 'ضعيفة جدًا';
    } else if (bits < 36) {
      level = 1;
      label = 'ضعيفة';
    } else if (bits < 60) {
      level = 2;
      label = 'متوسطة';
    } else if (bits < 80) {
      level = 3;
      label = 'قوية';
    } else {
      level = 4;
      label = 'ممتازة';
    }

    // تخمين 10 مليار محاولة/ثانية (هجوم على ملف مسروق) والمتوسط نصف الاحتمالات
    final String crack;
    if (bits > 200) {
      crack = 'أكثر من مليار سنة';
    } else {
      final guesses = math.pow(2, bits) / 2;
      crack = _fmtTime(guesses / 1e10);
    }

    if (tips.isEmpty && level >= 3) {
      tips.add('ممتاز. لا تستخدمها في أكثر من حساب.');
    }

    return PasswordReport(
      bits: bits,
      level: level,
      label: label,
      crackTime: crack,
      tips: tips,
    );
  }

  static String generate({
    required int length,
    bool upper = true,
    bool digits = true,
    bool symbols = true,
  }) {
    // بدون الأحرف المتشابهة (l 1 I O 0 o) لتسهيل القراءة
    const lowerSet = 'abcdefghijkmnpqrstuvwxyz';
    const upperSet = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const digitSet = '23456789';
    const symbolSet = '!@#\$%^&*()-_=+[]{};:,.?';

    final rnd = math.Random.secure();
    final sets = <String>[lowerSet];
    if (upper) sets.add(upperSet);
    if (digits) sets.add(digitSet);
    if (symbols) sets.add(symbolSet);

    final all = sets.join();
    final out = <String>[];
    // نضمن حرفًا واحدًا على الأقل من كل نوع مفعّل
    for (final s in sets) {
      out.add(s[rnd.nextInt(s.length)]);
    }
    while (out.length < length) {
      out.add(all[rnd.nextInt(all.length)]);
    }
    // خلط Fisher-Yates بمولّد آمن
    for (var i = out.length - 1; i > 0; i--) {
      final j = rnd.nextInt(i + 1);
      final t = out[i];
      out[i] = out[j];
      out[j] = t;
    }
    return out.take(length).join();
  }
}
