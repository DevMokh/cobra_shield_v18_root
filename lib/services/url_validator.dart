import 'public_suffix.dart';
import 'url_normalizer.dart';

/// نتيجة التحقق من صحة المدخل كرابط ويب قبل أي تحليل أو حساب درجة.
///
/// الفرق المهم: "المدخل مش رابط أصلًا" (not-a-url أو https://) حالة مستقلة اسمها
/// إدخال غير صالح، ومالهاش درجة خطر ولا بتتصنف مشبوهة. أما الروابط المموّهة قصدًا
/// (حروف شبيهة بـ / أو ترميز مضلّل...) فهي روابط حقيقية بتتحلل وبتاخد درجة، لأن
/// التمويه نفسه إشارة تصيّد.
class UrlValidation {
  const UrlValidation._(this.code, this.detail);

  const UrlValidation.valid() : this._('', '');

  /// سبب الرفض: empty / not_a_url / incomplete_url / unsupported_scheme /
  /// invalid_host / invalid_port / non_public_host. فاضي = صالح.
  final String code;

  /// شرح السبب للمستخدم (عربي).
  final String detail;

  bool get ok => code.isEmpty;
}

class UrlValidator {
  UrlValidator._();

  /// البروتوكولات المدعومة للفحص والاتصال الخارجي.
  static const Set<String> supportedSchemes = <String>{'http', 'https'};

  static const int maxLabelLength = 63;
  static const int maxHostLength = 253;

  // "scheme:" في أول النص (مثل mailto: و tel: و ftp:// و C:\).
  static final RegExp _schemeLike = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):(.*)$', dotAll: true);
  // example.com:8080 أو localhost:3000/path => ده host:port مش بروتوكول.
  static final RegExp _portTail = RegExp(r'^\d{1,5}(?:[/?#].*)?$', dotAll: true);

  static UrlValidation _bad(String code, String detail) =>
      UrlValidation._(code, detail);

  /// يتحقق من [raw] (النص الأصلي بعد trim) و[n] (نتيجة التطبيع). لا يرمي استثناءات.
  /// الأنواع الخطيرة (javascript: ...) مش من شغل الدالة دي؛ المحلل بيتعامل معاها قبلها.
  static UrlValidation check(String raw, NormalizedUrl n) {
    if (n.errors.contains('empty') || raw.trim().isEmpty) {
      return _bad('empty', 'النص فاضي. اكتب أو الصق رابطًا.');
    }

    // 1) بروتوكول غير مدعوم (صريح): ftp:// و ws:// و mailto: و tel: ...
    // (الصيغة المعطّلة hxxp / [.] بيفكّها المطبّع، فبنعتمد على نتيجته بدل النص الخام.)
    final m = n.defanged ? null : _schemeLike.firstMatch(raw.trim());
    if (m != null) {
      final sch = m.group(1)!.toLowerCase();
      final rest = m.group(2) ?? '';
      // اسم فيه نقطة (example.com:abc) مش بروتوكول: بيتعالج كمضيف:منفذ تحت.
      if (!supportedSchemes.contains(sch) &&
          !sch.contains('.') &&
          !_portTail.hasMatch(rest)) {
        return _bad(
          'unsupported_scheme',
          'البروتوكول ($sch) غير مدعوم في الفحص. بنفحص روابط http و https فقط.',
        );
      }
    }
    if (!n.schemeAssumed && n.scheme.isNotEmpty && !supportedSchemes.contains(n.scheme)) {
      return _bad(
        'unsupported_scheme',
        'البروتوكول (${n.scheme}) غير مدعوم في الفحص. بنفحص روابط http و https فقط.',
      );
    }

    // 2) تمويه متعمّد: بنسيبه للمحلل عشان ياخد درجة بدل ما نرفضه كمدخل غلط.
    final adversarial = n.separatorLookalike || n.hostDelimiterTrick;

    // 3) رابط ناقص: بروتوكول من غير اسم موقع (https:// , http:///x)
    if (n.errors.contains('no_host')) {
      return n.schemeAssumed
          ? _bad('not_a_url',
              'النص ده مش شكل رابط. اكتب الرابط كاملًا مثل https://example.com')
          : _bad('incomplete_url',
              'الرابط ناقص: مفيش اسم موقع بعد ${n.scheme}://. اكتب الرابط كاملًا مثل https://example.com');
    }
    if (n.errors.contains('bad_port')) {
      return _bad('invalid_port', 'رقم المنفذ في الرابط غير صالح (لازم بين 0 و65535).');
    }
    if (n.errors.contains('bad_ipv6')) {
      return _bad('invalid_host', 'عنوان IPv6 في الرابط غير صالح.');
    }
    if (n.errors.contains('bad_numeric_host')) {
      return _bad('invalid_host',
          'اسم الموقع رقمي بشكل غير صالح (مش عنوان IP صحيح). المتصفح كان هيرفض الرابط ده.');
    }
    if (!adversarial && n.errors.isNotEmpty) {
      return _bad('invalid_host', 'اسم الموقع فيه رموز أو تركيب غير مسموح في الدومينات.');
    }
    if (adversarial) return const UrlValidation.valid();

    // 4) عنوان IP: صالح للتحليل (والمحلل بيعلّمه). مفيش فحص أسماء عليه.
    if (n.ip != null) return const UrlValidation.valid();

    final host = n.host;
    if (host.isEmpty) {
      return _bad('not_a_url', 'النص ده مش شكل رابط. اكتب الرابط كاملًا مثل https://example.com');
    }

    // 5) صيغة اسم المضيف: أطوال وأجزاء فاضية
    final labels = host.split('.');
    if (host.length > maxHostLength) {
      return _bad('invalid_host', 'اسم الموقع أطول من الحد المسموح ($maxHostLength حرف).');
    }
    for (final l in labels) {
      if (l.isEmpty) {
        return _bad('invalid_host', 'اسم الموقع فيه جزء فاضي (نقطتين ورا بعض أو نقطة في أوله).');
      }
      if (l.length > maxLabelLength) {
        return _bad('invalid_host',
            'جزء من اسم الموقع أطول من الحد المسموح ($maxLabelLength حرف).');
      }
    }

    // 6) اسم من كلمة واحدة: مش عنوان إنترنت عام (localhost, router, not-a-url)
    if (labels.length < 2) {
      return n.schemeAssumed
          ? _bad('not_a_url',
              'النص ده مش شكل رابط (مفيهوش http/https ولا اسم موقع بامتداد مثل .com). اكتب الرابط كاملًا مثل https://example.com')
          : _bad('non_public_host',
              'اسم الموقع "$host" كلمة واحدة، مش عنوان إنترنت عام (غالبًا اسم جهاز داخلي). الفحص للروابط على الإنترنت العام.');
    }

    // 7) الامتداد (TLD): حروف فقط أو xn-- (مفيش امتداد حقيقي فيه أرقام أو رموز)
    final tld = labels.last;
    if (!_validTld(tld)) {
      return n.schemeAssumed
          ? _bad('not_a_url',
              'النص ده مش شكل رابط (الامتداد "$tld" غير صالح). اكتب الرابط كاملًا مثل https://example.com')
          : _bad('invalid_host', 'امتداد الدومين "$tld" غير صالح (لازم حروف فقط مثل com أو eg).');
    }

    // 8) مدخل بدون بروتوكول: لازم الامتداد يكون معروف عشان نعتبره رابط (مش "file.txt")
    if (n.schemeAssumed) {
      final uni = n.unicodeHost.isEmpty ? host : n.unicodeHost;
      final ul = uni.split('.').last;
      if (!PublicSuffixList.instance.isKnownTld(ul)) {
        return _bad(
          'not_a_url',
          'النص ده مش شكل رابط (الامتداد "$ul" غير معروف). لو ده رابط فعلًا اكتبه مع https:// في أوله.',
        );
      }
    }
    return const UrlValidation.valid();
  }

  static bool _validTld(String tld) {
    if (tld.startsWith('xn--')) return tld.length > 4;
    if (tld.length < 2) return false;
    for (final r in tld.runes) {
      final isAsciiLetter = (r >= 0x61 && r <= 0x7A);
      final isNonAscii = r >= 0x80;
      if (!(isAsciiLetter || isNonAscii)) return false;
    }
    return true;
  }
}
