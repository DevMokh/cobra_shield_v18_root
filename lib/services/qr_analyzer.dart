import 'message_analyzer.dart';

enum QrKind { url, wifi, phone, sms, mail, payment, otp, contact, text }

/// تصنيف محتوى رمز QR. الرموز مش دايمًا روابط: ممكن تكون واي فاي أو
/// رقم أو عملية دفع، وكل نوع له مخاطره.
class QrInfo {
  const QrInfo({
    required this.kind,
    required this.title,
    required this.note,
    required this.raw,
    this.link,
  });

  final QrKind kind;
  final String title;
  final String note;
  final String raw;

  /// الرابط الذي يمكن فحصه (لو وُجد)
  final String? link;
}

class QrAnalyzer {
  QrAnalyzer._();

  static final RegExp _bareDomain = RegExp(
    r'^[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?)+(?:/\S*)?$',
    caseSensitive: false,
  );

  static QrInfo classify(String input) {
    final raw = input.trim();
    final low = raw.toLowerCase();

    if (low.startsWith('http://') ||
        low.startsWith('https://') ||
        low.startsWith('www.')) {
      return QrInfo(
        kind: QrKind.url,
        title: 'رابط',
        note: 'الرمز يحتوي على رابط. افحصه قبل أي فتح.',
        raw: raw,
        link: raw,
      );
    }
    if (low.startsWith('wifi:')) {
      return QrInfo(
        kind: QrKind.wifi,
        title: 'شبكة واي فاي',
        note: 'الاتصال بشبكة مجهولة قد يعرّض بياناتك للتجسس. اتصل فقط بشبكات تعرف مصدرها.',
        raw: raw,
      );
    }
    if (low.startsWith('tel:')) {
      return QrInfo(
        kind: QrKind.phone,
        title: 'رقم هاتف',
        note: 'الرمز سيطلب منك الاتصال برقم. تأكد من الرقم قبل المكالمة، بعض الأرقام مدفوعة.',
        raw: raw,
      );
    }
    if (low.startsWith('sms:') || low.startsWith('smsto:')) {
      return QrInfo(
        kind: QrKind.sms,
        title: 'رسالة SMS جاهزة',
        note: 'قد ترسل رسالة لرقم مدفوع أو تشترك في خدمة. اقرأ الرقم والنص قبل الإرسال.',
        raw: raw,
      );
    }
    if (low.startsWith('mailto:')) {
      return QrInfo(
        kind: QrKind.mail,
        title: 'إيميل جاهز',
        note: 'تأكد من العنوان والنص قبل الإرسال.',
        raw: raw,
      );
    }
    if (low.startsWith('otpauth://')) {
      return QrInfo(
        kind: QrKind.otp,
        title: 'مفتاح مصادقة ثنائية',
        note: 'هذا الرمز سرّي. من يصوّره يقدر يولّد أكوادك. لا تشاركه مع أي أحد.',
        raw: raw,
      );
    }
    if (low.startsWith('upi:') ||
        low.startsWith('bitcoin:') ||
        low.startsWith('ethereum:') ||
        low.startsWith('litecoin:') ||
        low.startsWith('paypal:')) {
      return QrInfo(
        kind: QrKind.payment,
        title: 'طلب دفع',
        note: 'رمز دفع: راجع اسم المستلم والمبلغ كويس. النصابون يلصقون رموزهم فوق رموز المحلات.',
        raw: raw,
      );
    }
    if (low.startsWith('begin:vcard') || low.startsWith('mecard:')) {
      return QrInfo(
        kind: QrKind.contact,
        title: 'جهة اتصال',
        note: 'بطاقة اتصال. لا تحفظ بيانات من مصدر غير معروف.',
        raw: raw,
      );
    }
    if (_bareDomain.hasMatch(low) && !low.contains(' ')) {
      return QrInfo(
        kind: QrKind.url,
        title: 'رابط',
        note: 'الرمز يحتوي على عنوان موقع. افحصه قبل أي فتح.',
        raw: raw,
        link: raw,
      );
    }
    final links = MessageAnalyzer.extractLinks(raw);
    if (links.isNotEmpty) {
      return QrInfo(
        kind: QrKind.url,
        title: 'نص فيه رابط',
        note: 'الرمز نص يحتوي على رابط. سنفحص الرابط.',
        raw: raw,
        link: links.first,
      );
    }
    return QrInfo(
      kind: QrKind.text,
      title: 'نص',
      note: 'الرمز يحتوي نصًا فقط. لا يوجد رابط لفحصه.',
      raw: raw,
    );
  }
}
