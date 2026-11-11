import '../core/models.dart';

/// الجهة التي تدّعي الرسالة أنها منها
enum SenderClaim { none, bank, telecom, wallet, gov, shipping, store, relative }

extension SenderClaimText on SenderClaim {
  String get label {
    switch (this) {
      case SenderClaim.none:
        return 'غير محدد';
      case SenderClaim.bank:
        return 'بنك';
      case SenderClaim.telecom:
        return 'شركة اتصالات';
      case SenderClaim.wallet:
        return 'محفظة / دفع';
      case SenderClaim.gov:
        return 'جهة حكومية';
      case SenderClaim.shipping:
        return 'شحن وتوصيل';
      case SenderClaim.store:
        return 'متجر';
      case SenderClaim.relative:
        return 'قريب أو صديق';
    }
  }
}

enum SenderType { mobile, landline, shortCode, international, named, unknown }

extension SenderTypeText on SenderType {
  String get label {
    switch (this) {
      case SenderType.mobile:
        return 'رقم موبايل مصري عادي';
      case SenderType.landline:
        return 'رقم أرضي';
      case SenderType.shortCode:
        return 'رقم مختصر (خط ساخن أو خدمة)';
      case SenderType.international:
        return 'رقم دولي';
      case SenderType.named:
        return 'اسم مرسل (حروف)';
      case SenderType.unknown:
        return 'غير معروف';
    }
  }
}

class SenderAnalysis {
  const SenderAnalysis({
    required this.type,
    required this.normalized,
    required this.result,
  });

  final SenderType type;
  final String normalized;
  final ScanResult result;
}

/// فحص المرسل: نوع الرقم + هل يتناسب مع الجهة المُدّعاة. كله محلي.
/// ملاحظة: هذا مؤشر وليس دليلًا، فأسماء المرسل يمكن انتحالها.
class SenderAnalyzer {
  SenderAnalyzer._();

  static const String _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

  static String _digits(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final i = _arabicDigits.indexOf(ch);
      b.write(i >= 0 ? '$i' : ch);
    }
    return b.toString();
  }

  static final RegExp _mobile = RegExp(r'^01[0125]\d{8}$');
  static final RegExp _hasLetter = RegExp(r'[A-Za-z؀-ۿ]');

  static SenderAnalysis analyze(String input, SenderClaim claim) {
    final raw = _digits(input.trim());
    final findings = <Finding>[];
    SenderType type = SenderType.unknown;
    var shown = raw;

    if (raw.isEmpty) {
      return SenderAnalysis(
        type: type,
        normalized: '',
        result: ScanResult(
          kind: ScanKind.message,
          score: 0,
          findings: const <Finding>[
            Finding(
              severity: Severity.info,
              title: 'اكتب الرقم أو اسم المرسل',
              detail: 'مثال: 01012345678 أو +14155550123 أو اسم زي Bank.',
            ),
          ],
          title: 'المرسل',
        ),
      );
    }

    if (_hasLetter.hasMatch(raw)) {
      type = SenderType.named;
    } else {
      var d = raw.replaceAll(RegExp(r'[\s\-().]'), '');
      var plus = false;
      if (d.startsWith('+')) {
        plus = true;
        d = d.substring(1);
      } else if (d.startsWith('00')) {
        plus = true;
        d = d.substring(2);
      }
      d = d.replaceAll(RegExp(r'\D'), '');
      if (plus || (d.startsWith('20') && d.length >= 12)) {
        if (d.startsWith('20')) {
          final local = '0${d.substring(2)}';
          if (_mobile.hasMatch(local)) {
            type = SenderType.mobile;
            shown = local;
          } else {
            type = SenderType.landline;
            shown = local;
          }
        } else {
          type = SenderType.international;
          shown = '+$d';
        }
      } else if (_mobile.hasMatch(d)) {
        type = SenderType.mobile;
        shown = d;
      } else if (d.length >= 3 && d.length <= 6 && !d.startsWith('0')) {
        type = SenderType.shortCode;
        shown = d;
      } else if (d.startsWith('0') && d.length >= 8 && d.length <= 11) {
        type = SenderType.landline;
        shown = d;
      } else {
        type = SenderType.unknown;
        shown = d;
      }
    }

    final official = claim == SenderClaim.bank ||
        claim == SenderClaim.telecom ||
        claim == SenderClaim.wallet ||
        claim == SenderClaim.gov;

    switch (type) {
      case SenderType.mobile:
        if (official) {
          findings.add(Finding(
            severity: Severity.danger,
            title: 'جهة رسمية من رقم موبايل عادي',
            detail:
                '${claim.label} غالبًا لا تراسلك أو تتصل بك من رقم موبايل شخصي، بل من اسم مرسل أو رقم مختصر. وغالبًا هذا انتحال.',
            points: 45,
          ));
        } else if (claim == SenderClaim.relative) {
          findings.add(const Finding(
            severity: Severity.warn,
            title: 'رقم جديد يدّعي أنه قريبك',
            detail:
                'نصب شائع: "ده رقمي الجديد" ثم طلب فلوس أو كود. اتصل بالرقم القديم أو اسأل سؤالًا يعرفه القريب فقط.',
            points: 30,
          ));
        } else if (claim == SenderClaim.shipping) {
          findings.add(const Finding(
            severity: Severity.warn,
            title: 'شحن من رقم موبايل',
            detail:
                'مندوب التوصيل الحقيقي قد يتصل من موبايل، لكن لا تدفع ولا تدخل بيانات كارت عبر رابط يرسله.',
            points: 15,
          ));
        } else {
          findings.add(const Finding(
            severity: Severity.info,
            title: 'رقم موبايل شخصي',
            detail: 'لا يوجد ما يربطه بجهة رسمية. انتبه لأي طلب فلوس أو أكواد.',
            points: 5,
          ));
        }
        break;
      case SenderType.international:
        findings.add(Finding(
          severity: Severity.danger,
          title: 'رقم من خارج مصر',
          detail: claim == SenderClaim.none
              ? 'الرسائل الدولية غير المتوقعة غالبًا مزعجة أو احتيال. لا ترد.'
              : '${claim.label} في مصر لا تراسلك من رقم دولي في الغالب. الرد قد يكلّفك فلوس أو يؤكد أن رقمك شغال.',
          points: claim == SenderClaim.none ? 25 : 40,
        ));
        break;
      case SenderType.named:
        findings.add(const Finding(
          severity: Severity.info,
          title: 'اسم مرسل بحروف',
          detail:
              'الشركات الحقيقية تستخدم أسماء مرسل. لكن الاسم يمكن انتحاله وقد يظهر داخل محادثة الشركة الحقيقية نفسها، فاحكم على المحتوى والرابط لا على الاسم.',
          points: 5,
        ));
        break;
      case SenderType.shortCode:
        findings.add(const Finding(
          severity: Severity.good,
          title: 'رقم مختصر',
          detail:
              'الأرقام المختصرة غالبًا لخدمات رسمية، لكن لا تثق بها وحدها. افتح التطبيق الرسمي وتأكد.',
          points: 0,
        ));
        break;
      case SenderType.landline:
        findings.add(Finding(
          severity: official ? Severity.warn : Severity.info,
          title: 'رقم أرضي',
          detail: official
              ? 'ادعاء جهة رسمية من رقم أرضي غير مألوف. اتصل أنت بالرقم الموجود على موقعها الرسمي.'
              : 'رقم أرضي عادي.',
          points: official ? 20 : 0,
        ));
        break;
      case SenderType.unknown:
        findings.add(const Finding(
          severity: Severity.warn,
          title: 'صيغة غير مألوفة',
          detail: 'لم نتعرف على شكل الرقم. تأكد من كتابته كاملًا.',
          points: 8,
        ));
        break;
    }

    if (official || claim == SenderClaim.shipping) {
      findings.add(const Finding(
        severity: Severity.info,
        title: 'قاعدة ذهبية',
        detail:
            'لا تعطِ كود أو رقم سري أو بيانات كارت لأي حد يتصل بك، حتى لو عرف اسمك ورقمك. اقفل واتصل أنت بالرقم الرسمي.',
        points: 0,
      ));
    }

    var total = 0;
    for (final f in findings) {
      total += f.points;
    }
    if (total > 100) total = 100;
    findings.sort((a, b) => b.points.compareTo(a.points));

    return SenderAnalysis(
      type: type,
      normalized: shown,
      result: ScanResult(
        kind: ScanKind.message,
        score: total,
        findings: findings,
        title: 'المرسل',
      ),
    );
  }
}
