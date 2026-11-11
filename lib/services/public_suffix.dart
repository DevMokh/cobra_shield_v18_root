import '../core/psl_data.dart';

/// نتيجة مطابقة مضيف مع Public Suffix List.
///
/// [labels] هي أجزاء المضيف من اليسار لليمين (بعد تحويله لحروف صغيرة). كل الحقول
/// المشتقة (اللاحقة العامة، الدومين المسجّل، الدومين الفرعي) بتتحسب منها.
class PslMatch {
  const PslMatch({
    required this.labels,
    required this.suffixLength,
    required this.listed,
    required this.privateSection,
  });

  final List<String> labels;

  /// عدد أجزاء اللاحقة العامة (مثلًا 2 لـ co.uk).
  final int suffixLength;

  /// true = اللاحقة مطابقة لقاعدة حقيقية في القائمة. false = تطبيق القاعدة
  /// الافتراضية "*" على امتداد غير معروف (آخر جزء فقط).
  final bool listed;

  /// القاعدة اللي حسمت النتيجة من قسم PRIVATE (مثل github.io)، مش قسم ICANN.
  final bool privateSection;

  /// اللاحقة العامة (co.uk / com / github.io).
  String get publicSuffix =>
      labels.sublist(labels.length - suffixLength).join('.');

  /// فيه جزء واحد على الأقل قبل اللاحقة (يعني المضيف مش لاحقة عامة بحد ذاته).
  bool get hasRegistrable => labels.length > suffixLength;

  /// الدومين المسجّل = اللاحقة العامة + جزء واحد. فاضي لو المضيف هو نفسه لاحقة عامة.
  String get registrableDomain => hasRegistrable
      ? labels.sublist(labels.length - suffixLength - 1).join('.')
      : '';

  /// الأجزاء اللي قبل الدومين المسجّل (www / mail.example ...). فاضي لو مفيش.
  String get subdomain => hasRegistrable
      ? labels.sublist(0, labels.length - suffixLength - 1).join('.')
      : '';
}

/// قائمة اللاحقات العامة (Public Suffix List) بخوارزمية publicsuffix.org الرسمية:
///  1) لو قاعدة استثناء (!) طابقت المضيف فهي الحاسمة، واللاحقة = القاعدة من غير أول جزء.
///  2) غير كده القاعدة الأطول (الأكثر أجزاء) هي الحاسمة، والقاعدة `*.x` بتطابق أي جزء.
///  3) لو مفيش أي قاعدة طابقت تُطبَّق القاعدة الافتراضية "*" (آخر جزء هو اللاحقة).
///
/// البيانات مضمّنة في `lib/core/psl_data.dart` (لقطة بتاريخ [kPslSnapshotDate]، مولَّدة
/// بـ tool/gen_psl.py من القائمة الرسمية). المطابقة بتتم على الأجزاء بصيغة Unicode
/// (القواعد في القائمة بصيغة Unicode)؛ مرّر المضيف بعد فك xn--.
class PublicSuffixList {
  PublicSuffixList.fromRules({required String icann, String private = ''}) {
    _load(icann, false);
    _load(private, true);
  }

  /// النسخة المضمّنة في التطبيق (تُبنى مرة واحدة عند أول استخدام).
  static final PublicSuffixList instance = PublicSuffixList.fromRules(
    icann: kPslIcannRules,
    private: kPslPrivateRules,
  );

  // القيمة: true لو القاعدة من قسم PRIVATE.
  final Map<String, bool> _rules = <String, bool>{};
  final Map<String, bool> _wild = <String, bool>{};
  final Map<String, bool> _exc = <String, bool>{};

  void _load(String text, bool isPrivate) {
    for (final line in text.split('\n')) {
      final r = line.trim();
      if (r.isEmpty || r.startsWith('//')) continue;
      if (r.startsWith('!')) {
        _exc[r.substring(1)] = isPrivate;
      } else if (r.startsWith('*.')) {
        _wild[r.substring(2)] = isPrivate;
      } else {
        _rules[r] = isPrivate;
      }
    }
  }

  /// عدد القواعد المحمّلة (للاختبارات والتقارير).
  int get ruleCount => _rules.length + _wild.length + _exc.length;

  /// الامتداد (TLD) موجود كقاعدة في قسم ICANN؟ (امتداد حقيقي معروف في اللقطة المضمّنة).
  bool isKnownTld(String tld) {
    final t = tld.toLowerCase();
    return _rules[t] == false || _wild[t] == false;
  }

  /// يرجّع null لو المضيف غير صالح للمطابقة (فاضي، يبدأ بنقطة، أجزاء فاضية).
  /// نقطة واحدة في الآخر (FQDN) بتتشال. [includePrivate]=false يتجاهل قسم PRIVATE.
  PslMatch? lookup(String host, {bool includePrivate = true}) {
    var h = host.trim().toLowerCase();
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    if (h.isEmpty || h.startsWith('.')) return null;
    final labels = h.split('.');
    if (labels.any((l) => l.isEmpty)) return null;
    final n = labels.length;

    bool allowed(bool? isPrivate) =>
        isPrivate != null && (includePrivate || !isPrivate);

    // 1) قواعد الاستثناء لها الأولوية.
    for (var i = 0; i < n; i++) {
      final isPrivate = _exc[labels.sublist(i).join('.')];
      if (allowed(isPrivate)) {
        return PslMatch(
          labels: labels,
          suffixLength: n - i - 1,
          listed: true,
          privateSection: isPrivate!,
        );
      }
    }

    // 2) أطول قاعدة عادية أو wildcard (i أصغر = قاعدة أطول).
    for (var i = 0; i < n; i++) {
      final normal = _rules[labels.sublist(i).join('.')];
      if (allowed(normal)) {
        return PslMatch(
          labels: labels,
          suffixLength: n - i,
          listed: true,
          privateSection: normal!,
        );
      }
      if (i + 1 < n) {
        final wild = _wild[labels.sublist(i + 1).join('.')];
        if (allowed(wild)) {
          return PslMatch(
            labels: labels,
            suffixLength: n - i,
            listed: true,
            privateSection: wild!,
          );
        }
      }
    }

    // 3) القاعدة الافتراضية "*".
    return PslMatch(
      labels: labels,
      suffixLength: 1,
      listed: false,
      privateSection: false,
    );
  }
}
