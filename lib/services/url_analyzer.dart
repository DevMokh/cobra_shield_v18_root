import 'dart:math' as math;

import '../core/knowledge.dart';
import '../core/models.dart';
import '../core/psl_data.dart' show kPslSnapshotDate;
import 'public_suffix.dart';
import 'url_evasion.dart';
import 'url_normalizer.dart';
import 'url_report.dart';
import 'url_validator.dart';

class _Run {
  const _Run(this.result, this.norm);
  final ScanResult result;
  final NormalizedUrl? norm;
}

/// محلل الروابط: كله يعمل على الجهاز بدون اتصال بالإنترنت.
/// كل فحص بيضيف "نقاط خطر"، والمجموع (0-100) يحدد المستوى.
class UrlAnalyzer {
  UrlAnalyzer._();

  static final RegExp _embedded = RegExp(r'https?://', caseSensitive: false);
  static const List<String> _credWords = <String>[
    'login', 'log-in', 'signin', 'sign-in', 'verify', 'verification', 'secure',
    'password', 'passwd', 'otp', 'confirm', 'validate', 'authenticate',
    'unlock', 'recover', 'restore',
  ];
  static final RegExp _redirectValue =
      RegExp(r'^(https?:)?//', caseSensitive: false);

  static final RegExp _ipv4Like = RegExp(r'^[0-9.]+$');

  /// الدومين المسجّل (Registrable Domain) حسب Public Suffix List: اللاحقة العامة + جزء
  /// واحد (example.co.uk / evil.github.io). لو المضيف IP أو هو نفسه لاحقة عامة (com،
  /// co.uk) بنرجّعه كما هو. المطابقة على الأجزاء بعد فك xn-- (القواعد Unicode).
  static String registrableDomain(String host) {
    var h = host.trim().toLowerCase();
    while (h.endsWith('.')) {
      h = h.substring(0, h.length - 1);
    }
    if (h.isEmpty || h.contains(':') || _ipv4Like.hasMatch(h)) return h;
    final labels = h.split('.');
    final uni = labels
        .map((l) => l.startsWith('xn--')
            ? (UrlNormalizer.decodePunycode(l.substring(4)) ?? l)
            : l)
        .join('.');
    final m = PublicSuffixList.instance.lookup(uni);
    if (m == null || !m.hasRegistrable || m.labels.length != labels.length) {
      return h;
    }
    return labels.sublist(labels.length - m.suffixLength - 1).join('.');
  }

  static Brand? _officialOf(String host) => officialBrandOf(host);

  /// نطاق إقليمي لعلامة كبيرة (google.de / amazon.co.uk): label.cctld
  static Brand? _regionalOf(String domain, String tld) {
    if (tld.length != 2 || kRiskyTlds.contains(tld) || kAbusedCc.contains(tld)) {
      return null;
    }
    final label = domain.split('.').first;
    for (final b in kBrands) {
      if (b.regional && b.keys.contains(label)) return b;
    }
    return null;
  }

  /// مضيف مشترك (مختصِر روابط / استضافة مجانية / دومين علامة رسمية):
  /// لا نحكم عليه كله بسبب رابط واحد مدرج في قائمة تهديدات.
  static bool isSharedHost(String host) {
    if (kShorteners.contains(host)) return true;
    for (final d in kFreeHosts) {
      if (host == d || host.endsWith('.$d')) return true;
    }
    return _officialOf(host) != null;
  }

  static int _lev(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(
          math.min(cur[j - 1] + 1, prev[j] + 1),
          prev[j - 1] + cost,
        );
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// يحوّل الأرقام والحروف المتشابهة لحروفها (paypa1 -> paypal)
  static List<String> _deob(String t) {
    String conv(String s, String one) => s
        .replaceAll('rn', 'm')
        .replaceAll('vv', 'w')
        .replaceAll('0', 'o')
        .replaceAll('1', one)
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('5', 's')
        .replaceAll('7', 't')
        .replaceAll('\$', 's');
    return <String>[conv(t, 'l'), conv(t, 'i')];
  }

  /// اسم يبدو مولَّدًا عشوائيًا (مثل xkqzrtvbnm أو a8392kd04x1): شائع في
  /// الدومينات المؤقتة اللي تستخدمها حملات الاحتيال. حذر عمدًا لتقليل الإنذارات الكاذبة.
  static bool _looksRandom(String label) {
    if (label.length < 10) return false;
    if (!RegExp(r'^[a-z0-9]+$').hasMatch(label)) return false;
    // سلسلة حروف ساكنة طويلة (الإنجليزية العادية نادرًا تتعدى 6)
    if (RegExp(r'[bcdfghjklmnpqrstvwxz]{7,}').hasMatch(label)) return true;
    // حروف وأرقام متداخلة بكثرة
    final digits = RegExp(r'\d').allMatches(label).length;
    if (label.length >= 12 &&
        digits >= 4 &&
        RegExp(r'[a-z]\d+[a-z]').hasMatch(label)) {
      return true;
    }
    return false;
  }

  static ScanResult _finish(List<Finding> f, UrlParts? parts, String title,
      {bool partial = false}) {
    // الدرجة بطريقة موحدة: كل إشارة بكودها مرة واحدة، والإشارات الضعيفة ليها سقف.
    final total = aggregateScore(f);
    f.sort((a, b) => b.points.compareTo(a.points));
    return ScanResult(
      kind: ScanKind.url,
      score: total,
      findings: f,
      parts: parts,
      title: title,
      partial: partial,
    );
  }

  /// يحلل رابطًا ويرجّع [ScanResult] (الواجهة القديمة، بدون تغيير في الاستخدام).
  static ScanResult analyze(String input) => _run(input).result;

  /// نفس التحليل لكن بتقرير منظم: الدرجة، المستوى (آمن/مشبوه/خطير)، الرابط بعد
  /// التنظيف، وقايمة الإشارات بشرح ووزن كل واحدة.
  static UrlThreatReport report(String input) {
    final run = _run(input);
    return UrlThreatReport.from(input, run.result, run.norm);
  }

  static _Run _run(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return _Run(
        ScanResult.invalid(
          kind: ScanKind.url,
          issueCode: 'empty',
          detail: 'النص فاضي. اكتب أو الصق رابطًا.',
        ),
        null,
      );
    }
    try {
      return _analyze(raw);
    } catch (_) {
      // أي خطأ غير متوقع = تحليل فاشل (حالة مستقلة)، وده مش معناه "آمن" ولا "مشبوه".
      return _Run(
        ScanResult.failed(
          kind: ScanKind.url,
          detail:
              'حصل خطأ غير متوقع أثناء الفحص، فما نقدرش نحكم عليه. اعتبره غير مفحوص وتعامل بحذر.',
          title: raw,
        ),
        null,
      );
    }
  }

  static _Run _analyze(String raw) {
    final n = UrlNormalizer.normalize(raw);
    final f = <Finding>[];

    // 1) أنواع روابط خطيرة (حتى لو مموّهة بحروف خفية أو ترميز)
    if (n.dangerousScheme.isNotEmpty) {
      f.add(const Finding(
        code: 'danger_scheme',
        severity: Severity.danger,
        title: 'نوع رابط خطير',
        detail:
            'ده مش عنوان موقع عادي (javascript / data / file ...). ممكن ينفّذ كودًا أو يفتح ملفًا محليًا.',
        points: 70,
      ));
      return _Run(_finish(f, null, raw, partial: n.truncated), n);
    }

    // 1-ب) التحقق من صحة المدخل قبل أي تحليل: "not-a-url" و "https://" وبروتوكول غير
    // مدعوم = إدخال غير صالح (مالوش درجة خطر)، مش رابط مشبوه ولا رابط نضيف.
    final v = UrlValidator.check(raw, n);
    if (!v.ok) {
      return _Run(
        ScanResult.invalid(
          kind: ScanKind.url,
          issueCode: v.code,
          detail: v.detail,
          title: raw,
        ),
        n,
      );
    }

    // 2) كاشفات التمويه: حروف خفية، ترميز، بروتوكول مكسور، IP، @، homograph ...
    f.addAll(UrlEvasion.detect(n));
    if (!n.valid) {
      return _Run(_finish(f, null, raw, partial: n.truncated), n);
    }

    final scheme = n.scheme;
    final host = n.host;
    // المضيف بعد تحويل الحروف المتشابهة للاتينية (للمقارنة مع أسماء العلامات فقط)
    final brandHost = n.skeletonHost.isEmpty ? host : n.skeletonHost;
    final labels = host.split('.');
    final tld = labels.last;
    final isIp = n.hasIp;

    // الدومين المسجّل واللاحقة العامة من Public Suffix List (المضيف الكامل شيء مختلف).
    var registrable = '';
    var publicSuffix = '';
    var pslListed = true;
    if (!isIp) {
      final m = PublicSuffixList.instance
          .lookup(n.unicodeHost.isEmpty ? host : n.unicodeHost);
      if (m != null && m.labels.length == labels.length) {
        publicSuffix =
            labels.sublist(labels.length - m.suffixLength).join('.');
        if (m.hasRegistrable) {
          registrable =
              labels.sublist(labels.length - m.suffixLength - 1).join('.');
        }
        pslListed = m.listed;
      }
    }
    // لو المضيف نفسه لاحقة عامة (github.io) بنعتبره هو الدومين للمقارنات.
    final domain = isIp ? host : (registrable.isEmpty ? host : registrable);

    final Brand? exact = isIp ? null : _officialOf(host);
    final Brand? regionalBrand =
        (isIp || exact != null) ? null : _regionalOf(domain, tld);
    final Brand? official = exact ?? regionalBrand;
    final bool isRegional = regionalBrand != null;
    var freeHost = false;
    for (final d in kFreeHosts) {
      if (host == d || host.endsWith('.$d')) {
        freeHost = true;
        break;
      }
    }

    // 3) البروتوكول
    if (scheme == 'http') {
      f.add(const Finding(
        code: 'http_plain',
        severity: Severity.info,
        family: kFamilyWeak,
        title: 'اتصال غير مشفّر (HTTP)',
        detail:
            'البيانات المرسلة لهذا الموقع تُنقل بدون تشفير. ده مش دليل تصيّد بحد ذاته (مواقع قديمة أو داخلية كتير بتستخدمه، ومواقع التصيّد نفسها غالبًا HTTPS)، لكن لا تُدخل بيانات حساسة.',
        points: 3,
      ));
    }

    // امتداد غير موجود في قائمة اللاحقات المضمّنة (معلومة فقط، مش دليل: قد يكون جديدًا).
    if (!isIp && !pslListed && !n.schemeAssumed) {
      f.add(Finding(
        code: 'unknown_tld',
        severity: Severity.info,
        family: kFamilyWeak,
        title: 'امتداد غير معروف (.$tld)',
        detail:
            'الامتداد غير موجود في قائمة اللاحقات العامة المضمّنة (تاريخها $kPslSnapshotDate). ممكن يكون امتدادًا جديدًا، أو غير حقيقي.',
      ));
    }

    // 6) منطق الدومين (لا ينطبق على IP)
    if (!isIp) {
      if (kShorteners.contains(host) || kShorteners.contains(domain)) {
        f.add(const Finding(
          code: 'shortener',
          severity: Severity.warn,
          title: 'رابط مختصر',
          detail:
              'الرابط المختصر يخفي الوجهة الحقيقية. استخدم زر "فحص الوجهة الفعلية" لمعرفة أين يذهب.',
          points: 20,
        ));
      }

      if (freeHost) {
        f.add(const Finding(
          code: 'free_host',
          severity: Severity.warn,
          title: 'منصة استضافة مجانية',
          detail:
              'المحتالون يرفعون صفحات مزيفة على منصات مجانية. الدومين نفسه موثوق لكن المحتوى قد لا يكون.',
          points: 15,
        ));
      }

      if (official == null) {
        // انتحال اسم علامة معروفة
        // لو الدومين اتعلّم كنسخة مموّهة من دومين رسمي، ما نعدّش الانتحال مرتين.
        final lookalikeDone = f.any((x) => x.code == 'official_lookalike');
        final tokens = lookalikeDone
            ? <String>[]
            : brandHost
                .split(RegExp(r'[.\-_]'))
                .where((t) => t.length >= 3)
                .toList();
        final hayHost = '$brandHost ${n.path} ${n.query}'.toLowerCase();
        final sensitive = kUrlWords.any((w) => hayHost.contains(w)) ||
            kRiskyTlds.contains(tld);
        Brand? hit;
        outer:
        for (final b in kBrands) {
          for (final key in b.keys) {
            for (final t in tokens) {
              if (t == key || (key.length >= 5 && t.startsWith(key))) {
                // أسماء مثل apple/orange كلمات عادية: لا نحكم إلا مع علامات أخرى
                if (b.ambiguous && !sensitive) continue;
                hit = b;
                break outer;
              }
            }
          }
        }
        if (hit != null) {
          f.add(Finding(
            code: 'brand_impersonation',
            severity: Severity.danger,
            title: 'ينتحل اسم ${hit.name}',
            detail:
                'الاسم موجود في الرابط لكن الدومين الحقيقي هنا هو "$domain"، وهو ليس ضمن الدومينات الرسمية المعروفة لـ ${hit.name} (مثل ${hit.domains.first}).',
            points: 40,
          ));
        } else {
          // تقليد بحروف/أرقام متشابهة
          var found = false;
          for (final t in tokens) {
            if (t.length < 4 || found) continue;
            final variants = _deob(t);
            for (final b in kBrands) {
              for (final key in b.keys) {
                if (key.length < 5 || found) continue;
                if (t != key && variants.contains(key)) {
                  f.add(Finding(
                    code: 'brand_lookalike',
                    severity: Severity.danger,
                    title: 'تقليد لاسم ${b.name}',
                    detail:
                        '"$t" يشبه "$key" باستبدال أرقام/حروف متشابهة (مثل 1 بدل l).',
                    points: 40,
                  ));
                  found = true;
                  break;
                }
                if (!b.ambiguous &&
                    (t.length - key.length).abs() <= 1 &&
                    _lev(t, key) == 1) {
                  f.add(Finding(
                    code: 'brand_typo',
                    severity: Severity.danger,
                    title: 'خطأ إملائي مقصود في ${b.name}؟',
                    detail: '"$t" قريب جدًا من "$key" بحرف واحد مختلف.',
                    points: 30,
                  ));
                  found = true;
                  break;
                }
              }
            }
          }
        }

        if (kRiskyTlds.contains(tld)) {
          f.add(Finding(
            code: 'risky_tld',
            severity: Severity.info,
            family: kFamilyWeak,
            title: 'امتداد دومين كثير الاستخدام في الاحتيال (.$tld)',
            detail:
                'الامتداد رخيص أو مجاني فبيتكرر في الحملات الاحتيالية، لكن مواقع سليمة كتير بتستخدمه برضه. إشارة مساعدة فقط ومش دليل لوحدها.',
            points: 5,
          ));
        }

        final extra = labels.length - domain.split('.').length;
        if (extra >= 3) {
          f.add(Finding(
            code: 'many_subdomains',
            severity: Severity.warn,
            title: 'مستويات فرعية كثيرة ($extra)',
            detail: 'كثرة النقاط في الدومين تُستخدم لدفن الاسم الحقيقي في آخر الرابط.',
            points: UrlWeights.manySubdomains,
          ));
        } else if (extra == 2) {
          f.add(const Finding(
            code: 'multi_subdomain',
            severity: Severity.info,
            family: kFamilyWeak,
            title: 'دومين فرعي متعدد',
            detail: 'اقرأ الدومين من اليمين: الجزء الأخير قبل أول "/" هو الأهم.',
            points: 3,
          ));
        }

        if ('-'.allMatches(host.replaceAll('xn--', '')).length >= 3) {
          f.add(const Finding(
            code: 'many_hyphens',
            severity: Severity.info,
            family: kFamilyWeak,
            title: 'شرطات كثيرة في الدومين',
            detail:
                'الدومينات الاحتيالية غالبًا تحشر كلمات مثل secure-login-update، لكن أسماء سليمة طويلة بتحتوي شرطات كمان. إشارة مساعدة فقط.',
            points: 3,
          ));
        }
        if (host.length > 35) {
          f.add(const Finding(
            code: 'long_host',
            severity: Severity.info,
            family: kFamilyWeak,
            title: 'اسم دومين طويل',
            detail: 'الأسماء الطويلة قد تُستخدم لإخفاء الجزء المهم، لكنها وحدها مش دليل.',
            points: 2,
          ));
        }
      } else if (!freeHost) {
        if (isRegional) {
          f.add(Finding(
            code: 'regional_brand',
            severity: Severity.info,
            title: 'نطاق إقليمي محتمل لـ ${official.name}',
            detail:
                '"$domain" يبدو نطاقًا إقليميًا لـ ${official.name}. غالبًا سليم، لكن تأكد من الكتابة الصحيحة.',
          ));
        } else {
          f.add(Finding(
            code: 'official_domain',
            severity: Severity.good,
            title: 'الدومين رسمي: ${official.name}',
            detail: '"$domain" ضمن الدومينات الرسمية المعروفة لـ ${official.name}.',
          ));
        }
      }
    }

    // 7) المنفذ
    final port = n.port;
    if (port != null && port != 80 && port != 443) {
      f.add(Finding(
        code: 'odd_port',
        severity: Severity.warn,
        title: 'منفذ غير معتاد ($port)',
        detail: 'المواقع العادية لا تحتاج رقم منفذ ظاهرًا في الرابط.',
        points: 10,
      ));
    }

    // 8) كلمات حساسة في الرابط: مش دليل وحدها (login / account / pay موجودة في مواقع
    // سليمة كتير). بنطابق الكلمة كاملة (مش جزء من كلمة)، وبتاخد نقاط بس في سياق:
    // كلمات كتير فيها كلمة دخول/تحقق، أو مع مؤشر قوي تاني (راجع keywords_in_context).
    var credHits = <String>[];
    if (official == null || freeHost) {
      final hay = '$brandHost ${n.path} ${n.query}'.toLowerCase();
      final tokens = hay
          .split(RegExp(r'[^a-z0-9]+'))
          .where((t) => t.isNotEmpty)
          .toList();
      final hits = kUrlWords.where((w) => _wordHit(hay, tokens, w)).toList();
      credHits = hits.where(_credWords.contains).toList();
      if (hits.length >= 3 && credHits.isNotEmpty) {
        f.add(Finding(
          code: 'keyword_stuffing',
          severity: Severity.warn,
          title: 'كلمات حساسة كثيرة',
          detail: 'وُجدت: ${hits.take(5).join(', ')}. صفحات الاحتيال تحشر هذه الكلمات لإقناعك.',
          points: UrlWeights.keywordStuffing,
        ));
      } else if (hits.isNotEmpty) {
        f.add(Finding(
          code: 'keywords',
          severity: Severity.info,
          family: kFamilyWeak,
          title: 'كلمات حساسة في الرابط (لا تكفي وحدها)',
          detail:
              'وُجدت: ${hits.join(', ')}. هذه كلمات عادية في مواقع كتير، فلا نعتبرها مؤشر خطر إلا لو اجتمعت مع مؤشرات أخرى.',
        ));
      }
    }

    // 8-ب) اسم علامة معروفة في المسار (evil.com/paypal/login) أو دومين يبدو عشوائيًا
    if (!isIp && (official == null || freeHost)) {
      final pathHay = '${n.path} ${n.query}'.toLowerCase();
      final allHay = '$host $pathHay';
      // كلمات "تسجيل الدخول/التحقق" فقط (مش pay/account/bank لأنها شائعة في الأخبار)
      final sensitiveCtx =
          _credWords.any((w) => allHay.contains(w)) || kRiskyTlds.contains(tld);
      final alreadyBrand = f.any(
          (x) => x.title.startsWith('ينتحل') || x.title.startsWith('تقليد'));
      if (sensitiveCtx && !alreadyBrand) {
        Brand? inPath;
        for (final b in kBrands) {
          if (b.ambiguous || identical(b, official)) continue;
          for (final key in b.keys) {
            if (key.length >= 5 && pathHay.contains(key)) {
              inPath = b;
              break;
            }
          }
          if (inPath != null) break;
        }
        if (inPath != null) {
          f.add(Finding(
            code: 'brand_in_path',
            severity: Severity.warn,
            title: 'اسم ${inPath.name} داخل مسار الرابط',
            detail:
                'الدومين الحقيقي هنا "$domain" وليس ${inPath.domains.first}. المحتال يضع اسم العلامة بعد الدومين ليبدو الرابط مألوفًا.',
            points: 18,
          ));
        }
      }
      if (official == null && !freeHost && _looksRandom(domain.split('.').first)) {
        f.add(const Finding(
          code: 'random_domain',
          severity: Severity.warn,
          title: 'اسم دومين يبدو عشوائيًا',
          detail:
              'الاسم يشبه نصًا مولَّدًا آليًا لا كلمة مفهومة. الدومينات المؤقتة للحملات الاحتيالية غالبًا بهذا الشكل.',
          points: 15,
        ));
      }
    }

    // 9) إعادة توجيه داخل الرابط
    // الاستعلام هنا متفكوك الترميز بالكامل (حتى المزدوج)، فنكشف الوجهة المخبّأة.
    var hasRedirectParam = false;
    for (final pair in _queryPairs(n.query)) {
      if (kRedirectParams.contains(pair[0].toLowerCase()) &&
          _redirectValue.hasMatch(pair[1])) {
        hasRedirectParam = true;
        break;
      }
    }
    if (hasRedirectParam || _embedded.allMatches(raw).length >= 2) {
      f.add(const Finding(
        code: 'nested_url',
        severity: Severity.warn,
        title: 'رابط داخل رابط',
        detail: 'الرابط يحمل عنوانًا آخر بداخله وقد يحوّلك لموقع مختلف تمامًا.',
        points: 15,
      ));
    }

    // 10) أطوال وترميز
    if (raw.length > 200) {
      f.add(const Finding(
        code: 'very_long',
        severity: Severity.info,
        family: kFamilyWeak,
        title: 'رابط طويل جدًا',
        detail: 'الطول الزائد قد يُستخدم لإخفاء الجزء المهم، لكنه شائع في روابط التتبع السليمة.',
        points: 4,
      ));
    } else if (raw.length > 100) {
      f.add(const Finding(
        code: 'long_url',
        severity: Severity.info,
        family: kFamilyWeak,
        title: 'رابط طويل',
        detail: 'الروابط الطويلة تستحق نظرة أدق.',
        points: 2,
      ));
    }
    if ('%'.allMatches(raw).length >= 6) {
      f.add(const Finding(
        code: 'heavy_encoding',
        severity: Severity.info,
        family: kFamilyWeak,
        title: 'ترميز كثيف (%)',
        detail: 'الترميز الكثيف قد يُستخدم لتمويه محتوى الرابط (وفي روابط عربية سليمة كتير أيضًا).',
        points: 3,
      ));
    }

    // 11) ملفات خطيرة
    final path = n.path.toLowerCase();
    var dangerous = false;
    for (final ext in kDangerExt) {
      if (path.endsWith(ext)) {
        dangerous = true;
        f.add(Finding(
          code: 'executable_download',
          severity: Severity.danger,
          title: 'تحميل ملف تنفيذي ($ext)',
          detail:
              'ملفات $ext قد تثبّت برامج ضارة. لا تثبّت شيئًا إلا من المتجر الرسمي أو موقع الناشر.',
          points: 30,
        ));
        break;
      }
    }
    if (!dangerous) {
      for (final ext in kArchiveExt) {
        if (path.endsWith(ext)) {
          f.add(Finding(
            code: 'archive_download',
            severity: Severity.warn,
            title: 'ملف مضغوط ($ext)',
            detail: 'الملفات المضغوطة تُستخدم لإخفاء برامج ضارة عن الفلاتر.',
            points: 12,
          ));
          break;
        }
      }
    }

    // كلمات دخول/تحقق + مؤشر قوي تاني (انتحال علامة، IP، @، دومين عشوائي، امتداد
    // مشبوه، رابط مختصر...) = سياق احتيال. الكلمات لوحدها ما بتتحسبش.
    if (credHits.isNotEmpty &&
        f.any((x) => _contextCodes.contains(x.code))) {
      f.add(Finding(
        code: 'keywords_in_context',
        severity: Severity.warn,
        title: 'كلمات دخول/تحقق مع مؤشرات أخرى',
        detail:
            'وُجدت: ${credHits.join(', ')}، وبتتزامن مع مؤشرات أخرى في الرابط. الاجتماع ده هو اللي بيرفع الشك، مش الكلمات لوحدها.',
        points: 6,
      ));
    }

    if (!f.any((x) => x.points > 0 || x.severity == Severity.good)) {
      f.add(const Finding(
        code: 'no_indicators',
        severity: Severity.good,
        title: 'لا علامات تصيّد شائعة',
        detail:
            'لم يطابق الرابط أي قاعدة فحص. هذا لا يضمن أنه آمن، فقد يكون دومينًا جديدًا مخترقًا.',
      ));
    }

    final parts = UrlParts(
      scheme: scheme,
      host: host,
      domain: domain,
      tld: tld,
      path: n.path.isEmpty ? '/' : n.path,
      query: n.query,
      port: port == null ? '' : '$port',
      // نسخة صالحة للاتصال (الهيكل الخام سليم، المضيف بشكله القياسي)
      normalizedUrl: n.fetchUrl,
      registrableDomain: registrable,
      publicSuffix: publicSuffix,
      unicodeHost: n.unicodeHost,
      asciiHost: _asciiHost(host),
      pslListed: pslListed,
    );
    // العنوان = اسم المضيف الكامل (مش الدومين المسجّل فقط).
    return _Run(_finish(f, parts, host, partial: n.truncated), n);
  }

  /// إشارات تعتبر "سياق" لكلمات الدخول/التحقق (راجع keywords_in_context).
  static const Set<String> _contextCodes = <String>{
    'brand_impersonation',
    'brand_lookalike',
    'brand_typo',
    'official_lookalike',
    'homograph',
    'brand_in_path',
    'ip_host',
    'ip_obfuscated',
    'userinfo_at',
    'random_domain',
    'shortener',
    'free_host',
    'nested_url',
    'risky_tld',
  };

  /// مطابقة كلمة كاملة (مش جزء من كلمة): pay لا تطابق paypal، وupdate تطابق updates.
  static bool _wordHit(String hay, List<String> tokens, String w) {
    if (w.contains('-')) return hay.contains(w);
    for (final t in tokens) {
      if (t == w || t == '${w}s') return true;
      if (w.length >= 6 && t.startsWith(w)) return true;
    }
    return false;
  }

  /// المضيف بصيغة ASCII للعرض: لو فيه حروف دولية بنحوّل كل ليبل لـ xn--.
  static String _asciiHost(String host) {
    if (!host.runes.any((r) => r >= 0x80)) return host;
    final out = <String>[];
    for (final l in host.split('.')) {
      if (l.runes.any((r) => r >= 0x80)) {
        final e = UrlNormalizer.encodePunycode(l);
        out.add(e == null ? l : 'xn--$e');
      } else {
        out.add(l);
      }
    }
    return out.join('.');
  }

  /// أزواج (اسم، قيمة) من نص الاستعلام. بدون استثناءات حتى لو النص مكسور.
  static List<List<String>> _queryPairs(String q) {
    final out = <List<String>>[];
    if (q.isEmpty) return out;
    for (final part in q.split('&')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out.add(<String>[part.substring(0, i), part.substring(i + 1)]);
    }
    return out;
  }
}
