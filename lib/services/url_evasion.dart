import '../core/brands.dart';
import '../core/models.dart';
import 'invisible_chars.dart';
import 'url_confusables.dart';
import 'url_normalizer.dart';

/// جدول الأوزان (نقاط الخطر). كل كاشف بياخد وزنه من هنا، فتقدر تعدّل التوازن
/// من مكان واحد. المجموع بيتقصّ عند 100 في [UrlAnalyzer].
class UrlWeights {
  UrlWeights._();

  /// IP مباشر بدل اسم دومين (عشري عادي أو IPv6).
  static const int ipHost = 30;

  /// IP مكتوب بصيغة مموّهة (hex / ثُماني / رقم واحد / مختصر).
  static const int ipObfuscated = 35;

  /// العنوان الداخلي (127.x / 192.168.x ...) كإضافة فوق وزن الـ IP.
  static const int ipInternal = 10;

  /// بيانات قبل @ (الوجهة الحقيقية بعد @).
  static const int userInfo = 35;

  /// إضافة لما الجزء قبل @ بيحتوي اسم علامة معروفة.
  static const int userInfoBrand = 10;

  /// تقليد بحروف متشابهة (Homograph).
  static const int homograph = 25;

  /// الدومين نسخة متشابهة الشكل من دومين رسمي معروف.
  static const int officialLookalike = 40;

  /// حروف مزخرفة/عريضة بتتحول لحروف عادية في المتصفح.
  static const int compatChars = 25;

  /// رمز بيشبه / أو . أو @ جوه الدومين.
  static const int separatorLookalike = 30;

  static const int badPunycode = 25;
  static const int idn = 8;

  static const int hiddenChars = 20;
  static const int hostEncoded = 20;
  static const int ambiguousHost = 35;
  static const int multiEncoding = 12;
  static const int doubleEncoding = 5;
  static const int badSchemeFormat = 10;
  static const int backslash = 15;

  /// المتصفح هيروح لمضيف وأدوات RFC هتشوف مضيف تاني (\ + @).
  static const int parserMismatch = 35;
  static const int spaceInHost = 15;
  static const int invalidUrl = 25;

  /// مستويات فرعية كثيرة في الدومين.
  static const int manySubdomains = 15;

  /// كلمات حساسة كثيرة (login / verify / bank ...).
  static const int keywordStuffing = 15;
}

/// كواشف التمويه والتهرّب: بتشتغل على [NormalizedUrl] (بعد التنظيف) وبتطلّع
/// قايمة [Finding]. كل كاشف مستقل، وكل إشارة ليها `code` ثابت ووزن ووصف مقروء.
class UrlEvasion {
  UrlEvasion._();

  static List<Finding> detect(NormalizedUrl n) {
    final f = <Finding>[];
    _hidden(n, f);
    _encoding(n, f);
    _structure(n, f);
    _ip(n, f);
    _userInfo(n, f);
    _homograph(n, f);
    _invalid(n, f);
    return f;
  }

  static const Map<String, String> _errorText = <String, String>{
    'empty': 'النص فاضي',
    'no_host': 'مفيش اسم دومين واضح',
    'bad_host_char': 'اسم الدومين فيه رموز غير مسموحة',
    'bad_numeric_host': 'اسم الدومين رقمي بشكل غير صالح',
    'bad_ipv6': 'عنوان IPv6 غير صالح',
    'bad_port': 'رقم المنفذ غير صالح',
    'bad_host': 'تركيب الدومين غير صالح',
  };

  static void _hidden(NormalizedUrl n, List<Finding> f) {
    if (n.invisibleRemoved > 0) {
      final kinds = n.invisibleKinds.map(InvisibleChars.label).join('، ');
      f.add(Finding(
        code: 'hidden_chars',
        severity: Severity.danger,
        title: 'حروف خفية داخل الرابط',
        detail:
            'وُجد ${n.invisibleRemoved} حرف غير مرئي${kinds.isEmpty ? '' : ' ($kinds)'} داخل الرابط (أو داخل اسم الموقع) وتم حذفها قبل التحليل. وجودها أسلوب لتمويه الرابط وكسر الفلاتر. علامات الاتجاه العادية (LRM/RLM) في مسار الرابط أو آخره لا تُحتسب.',
        points: UrlWeights.hiddenChars,
      ));
    } else if (n.directionMarksRemoved > 0) {
      f.add(Finding(
        code: 'direction_marks',
        severity: Severity.info,
        title: 'علامات اتجاه نص طبيعية في الرابط',
        detail:
            'وُجد ${n.directionMarksRemoved} علامة اتجاه (LRM/RLM) في مسار الرابط أو استعلامه. بتظهر طبيعيًا مع النص العربي المختلط، فتم تجاهلها ولم تُحتسب كخطر.',
      ));
    }
  }

  static void _encoding(NormalizedUrl n, List<Finding> f) {
    if (n.hostEncoded) {
      if (n.hostDelimiterTrick) {
        f.add(const Finding(
          code: 'ambiguous_host',
          severity: Severity.danger,
          title: 'دومين مموّه بترميز (%)',
          detail:
              'اسم الدومين مكتوب بترميز %XX وبعد فكه يظهر فيه فاصل (/ ? # @). أدوات مختلفة بتقرأ الدومين الحقيقي بشكل مختلف، وده أسلوب معروف للتحايل.',
          points: UrlWeights.ambiguousHost,
        ));
      } else {
        f.add(Finding(
          code: 'host_encoded',
          severity: Severity.warn,
          title: 'اسم الدومين مكتوب بترميز (%)',
          detail:
              'المواقع الحقيقية لا تكتب اسم الدومين بترميز %XX. بعد فك الترميز الدومين هو "${n.host}".',
          points: UrlWeights.hostEncoded,
        ));
      }
    }
    if (n.encodingRounds >= 3) {
      f.add(Finding(
        code: 'multi_encoding',
        severity: Severity.warn,
        title: 'ترميز متعدد المستويات (${n.encodingRounds})',
        detail:
            'احتاج الرابط ${n.encodingRounds} جولات من فك الترميز ليظهر محتواه. الترميز المتكرر يُستخدم لتهريب الرابط من الفلاتر.',
        points: UrlWeights.multiEncoding,
      ));
    } else if (n.encodingRounds == 2) {
      f.add(const Finding(
        code: 'double_encoding',
        severity: Severity.info,
        title: 'ترميز مزدوج',
        detail: 'جزء من الرابط مرمّز مرتين (مثل %252F). نادر في الروابط العادية.',
        points: UrlWeights.doubleEncoding,
      ));
    }
  }

  static void _structure(NormalizedUrl n, List<Finding> f) {
    if (n.schemeMalformed) {
      f.add(const Finding(
        code: 'bad_scheme_format',
        severity: Severity.warn,
        title: 'صيغة بروتوكول غير قياسية',
        detail:
            'البروتوكول مكتوب بشكل مختلف عن http:// أو https:// (شرطة ناقصة أو زيادة أو \\). المتصفحات بتتسامح معه، لكن فلاتر كثيرة لا تتعرف عليه.',
        points: UrlWeights.badSchemeFormat,
      ));
    }
    if (n.rfcHost.isNotEmpty) {
      f.add(Finding(
        code: 'parser_mismatch',
        severity: Severity.danger,
        title: 'الرابط بيتقرأ بشكلين مختلفين',
        detail:
            'المتصفح هيذهب لـ "${n.host}"، لكن أدوات وفلاتر كثيرة هتقرأ الرابط على إنه "${n.rfcHost}" بسبب \\ و @. أسلوب معروف لتمرير رابط خبيث على إنه موقع مألوف.',
        points: UrlWeights.parserMismatch,
      ));
    } else if (n.backslashInAuthority) {
      f.add(const Finding(
        code: 'backslash_authority',
        severity: Severity.warn,
        title: 'شرطة معكوسة (\\) في عنوان الموقع',
        detail:
            'المتصفح بيعتبر \\ نفس / فينهي اسم الدومين عندها، لكن أدوات تانية بتقرأ الرابط بشكل مختلف. أسلوب لإخفاء الوجهة الحقيقية.',
        points: UrlWeights.backslash,
      ));
    }
    if (n.spaceInAuthority) {
      f.add(const Finding(
        code: 'space_in_host',
        severity: Severity.warn,
        title: 'مسافات داخل اسم الدومين',
        detail:
            'اسم الدومين فيه مسافات (المتصفح كان هيرفضه). أزلناها لتحليل الدومين المقصود.',
        points: UrlWeights.spaceInHost,
      ));
    }
    if (n.defanged) {
      f.add(const Finding(
        code: 'defanged',
        severity: Severity.info,
        title: 'رابط مكتوب بصيغة محمية',
        detail: 'الرابط مكتوب بشكل hxxp أو [.] لتعطيله. فكّيناه للتحليل. لا تفتحه بعد إعادة تفعيله إلا بعد التأكد.',
      ));
    }
  }

  static String _radixText(IpInfo ip) {
    final parts = <String>[];
    if (ip.radixes.contains('hex')) parts.add('سداسي عشري (0x)');
    if (ip.radixes.contains('octal')) parts.add('ثُماني (أصفار بادئة)');
    if (ip.form == IpForm.dword && parts.isEmpty) parts.add('رقم عشري واحد');
    if (ip.form == IpForm.short) parts.add('صيغة مختصرة (أجزاء أقل من 4)');
    if (parts.isEmpty) parts.add('غير قياسية');
    return parts.join(' + ');
  }

  static const Map<String, String> _kindText = <String, String>{
    'loopback': 'عنوان جهازك نفسه (loopback)',
    'private': 'شبكة محلية خاصة',
    'linklocal': 'عنوان محلي تلقائي (link-local)',
    'unspecified': 'عنوان غير محدد (0.0.0.0)',
    'reserved': 'نطاق محجوز',
  };

  static void _ip(NormalizedUrl n, List<Finding> f) {
    final ip = n.ip;
    if (ip == null) return;
    if (ip.obfuscated) {
      f.add(Finding(
        code: 'ip_obfuscated',
        severity: Severity.danger,
        title: 'عنوان IP مموّه',
        detail:
            '"${n.hostAsWritten}" هو في الحقيقة العنوان ${ip.canonical}، مكتوب بصيغة ${_radixText(ip)} لإخفاء إنه IP مباشر.',
        points: UrlWeights.ipObfuscated,
      ));
    } else {
      f.add(Finding(
        code: 'ip_host',
        severity: Severity.danger,
        title: ip.form == IpForm.ipv6
            ? 'الرابط يستخدم عنوان IPv6'
            : 'الرابط يستخدم عنوان IP',
        detail: 'المواقع الحقيقية نادرًا ما تطلب بياناتك عبر عنوان IP مباشر (${ip.canonical}).',
        points: UrlWeights.ipHost,
      ));
    }
    if (ip.isInternal) {
      final what = _kindText[ip.kind] ?? 'عنوان داخلي';
      f.add(Finding(
        code: 'ip_internal',
        severity: Severity.warn,
        title: 'العنوان داخلي',
        detail:
            '${ip.canonical}: $what. رابط بالشكل ده ممكن يستهدف جهازك أو الراوتر أو شبكتك المحلية، مش موقع على الإنترنت.',
        points: UrlWeights.ipInternal,
      ));
    }
  }

  static void _userInfo(NormalizedUrl n, List<Finding> f) {
    if (n.userInfo.isEmpty && n.atCount == 0) return;
    final shown = n.userInfo.isEmpty ? '(فاضي)' : n.userInfo;
    f.add(Finding(
      code: 'userinfo_at',
      severity: Severity.danger,
      title: 'يحتوي على @ قبل الدومين',
      detail:
          'كل ما قبل علامة @ يتجاهله المتصفح. الرابط يعرض "$shown" لكن الوجهة الفعلية هي "${n.host}". المحتال يضع اسمًا مألوفًا قبل @ ليخدعك.',
      points: UrlWeights.userInfo,
    ));
    if (officialBrandOf(n.host) != null) return;
    final ui = n.userInfo.toLowerCase();
    Brand? hit;
    for (final tok in ui.split(RegExp(r'[^a-z0-9.\-]'))) {
      if (tok.length < 4) continue;
      hit = officialBrandOf(tok);
      if (hit != null) break;
    }
    if (hit == null) {
      outer:
      for (final b in kBrands) {
        if (b.ambiguous) continue;
        for (final key in b.keys) {
          if (key.length >= 5 && ui.contains(key)) {
            hit = b;
            break outer;
          }
        }
      }
    }
    if (hit != null) {
      f.add(Finding(
        code: 'userinfo_brand',
        severity: Severity.danger,
        title: 'اسم ${hit.name} قبل @',
        detail:
            'الجزء قبل @ يذكر ${hit.name} ليوهمك أن الرابط تابع لها، لكن الموقع الحقيقي "${n.host}".',
        points: UrlWeights.userInfoBrand,
      ));
    }
  }

  static void _homograph(NormalizedUrl n, List<Finding> f) {
    if (n.ip != null || n.unicodeHost.isEmpty) return;

    if (n.compatFolded) {
      f.add(Finding(
        code: 'compat_chars',
        severity: Severity.danger,
        title: 'حروف مزخرفة في الدومين',
        detail:
            'الدومين مكتوب بحروف مزخرفة أو عريضة (مثل ｐａｙｐａｌ أو 𝐩𝐚𝐲𝐩𝐚𝐥) والمتصفح بيحولها لحروف عادية: "${n.host}". ده تمويه متعمد.',
        points: UrlWeights.compatChars,
      ));
    }

    final labels = n.unicodeHost.split('.');
    final scans = labels.map(Confusables.scanLabel).toList();
    final sepLook =
        n.separatorLookalike || scans.any((s) => s.separatorLookalikes > 0);
    if (sepLook) {
      f.add(const Finding(
        code: 'separator_lookalike',
        severity: Severity.danger,
        title: 'رمز يشبه فاصل الرابط في الدومين',
        detail:
            'الدومين فيه رمز شكله زي / أو . أو @ لكنه حرف مختلف، لإيهامك إن الرابط ينتهي في مكان غير حقيقي.',
        points: UrlWeights.separatorLookalike,
      ));
    }

    final mixed = scans.any((s) => s.mixedScript);
    final whole = scans.any((s) => s.wholeLookalike);
    final anyNonAscii = scans.any((s) => s.nonAscii > 0) || n.unicodeHost != n.host;

    Brand? lookBrand;
    if (n.skeletonHost != n.unicodeHost && officialBrandOf(n.host) == null) {
      lookBrand = officialBrandOf(n.skeletonHost);
    }

    final reasons = <String>[];
    if (mixed) {
      reasons.add('يخلط حروفًا من أنظمة كتابة مختلفة (مثل لاتيني + سيريلي) تبدو متطابقة');
    }
    if (whole) {
      reasons.add('كل حروفه غير اللاتينية لها شبيه لاتيني فيظهر كاسم عادي');
    }
    if (lookBrand != null) {
      reasons.add('يبدو مثل "${n.skeletonHost}" لكنه مكتوب بحروف مختلفة');
    }
    if (reasons.isNotEmpty) {
      f.add(Finding(
        code: 'homograph',
        severity: Severity.danger,
        title: 'دومين بحروف متشابهة (Homograph)',
        detail: 'الدومين "${n.unicodeHost}" ${reasons.join('، و')}.',
        points: UrlWeights.homograph,
      ));
    } else if (anyNonAscii && !n.badPunycode) {
      f.add(Finding(
        code: 'idn',
        severity: Severity.info,
        title: 'دومين بحروف دولية (IDN)',
        detail:
            'الدومين "${n.unicodeHost}" فيه حروف غير لاتينية. غالبًا سليم (مواقع بالعربية أو الصينية مثلًا)، لكن راجع الكتابة جيدًا.',
        points: UrlWeights.idn,
      ));
    }
    if (lookBrand != null) {
      f.add(Finding(
        code: 'official_lookalike',
        severity: Severity.danger,
        title: 'ينتحل الدومين الرسمي لـ ${lookBrand.name}',
        detail:
            '"${n.unicodeHost}" نسخة متشابهة الشكل من "${n.skeletonHost}" الرسمي، لكنها دومين مختلف تمامًا.',
        points: UrlWeights.officialLookalike,
      ));
    }
    if (n.badPunycode) {
      f.add(const Finding(
        code: 'bad_punycode',
        severity: Severity.warn,
        title: 'ترميز Punycode غير صالح',
        detail: 'الدومين فيه جزء xn-- لا يمكن فكه. الدومينات السليمة لا تحتوي هذا.',
        points: UrlWeights.badPunycode,
      ));
    }
  }

  static void _invalid(NormalizedUrl n, List<Finding> f) {
    if (n.valid || n.dangerousScheme.isNotEmpty || n.errors.isEmpty) return;
    final why = n.errors.map((e) => _errorText[e] ?? e).toSet().join('، ');
    f.add(Finding(
      code: 'invalid_url',
      severity: Severity.warn,
      title: 'شكل الرابط غير صالح',
      detail: 'السبب: $why. الرابط بهذا الشكل لن يفتحه المتصفح كما هو، وغالبًا هو مكتوب بشكل مقصود أو مكسور.',
      points: UrlWeights.invalidUrl,
    ));
  }
}
