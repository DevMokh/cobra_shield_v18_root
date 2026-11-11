import 'package:cobra_shield/services/qr_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QrAnalyzer.classify: روابط', () {
    test('http/https/www', () {
      for (final u in <String>[
        'https://example.com/a?b=1',
        'HTTP://EXAMPLE.COM',
        'www.example.com/x',
      ]) {
        final q = QrAnalyzer.classify(u);
        expect(q.kind, QrKind.url, reason: u);
        expect(q.link, u, reason: u);
      }
    });

    test('دومين من غير بروتوكول', () {
      final q = QrAnalyzer.classify('example.com/path');
      expect(q.kind, QrKind.url);
      expect(q.link, 'example.com/path');
    });

    test('نص فيه رابط: بنفحص الرابط', () {
      final q = QrAnalyzer.classify('ادفع الآن على http://pay.example.top/x ثم أكد');
      expect(q.kind, QrKind.url);
      expect(q.link, 'http://pay.example.top/x');
    });

    test('المسافات حوالين المحتوى بتتشال', () {
      final q = QrAnalyzer.classify('  https://example.com/a  ');
      expect(q.raw, 'https://example.com/a');
      expect(q.link, 'https://example.com/a');
    });
  });

  group('QrAnalyzer.classify: أنواع غير الروابط', () {
    final cases = <String, QrKind>{
      'WIFI:T:WPA;S:Cafe;P:12345678;;': QrKind.wifi,
      'tel:+201001234567': QrKind.phone,
      'sms:+201001234567?body=hi': QrKind.sms,
      'SMSTO:123:hello': QrKind.sms,
      'mailto:a@example.com': QrKind.mail,
      'otpauth://totp/Site:me?secret=ABCDEF': QrKind.otp,
      'bitcoin:1BoatSLRHtKNngkdXEeobR76b53LETtpyT': QrKind.payment,
      'upi://pay?pa=x@bank': QrKind.payment,
      'BEGIN:VCARD\nFN:Ali\nEND:VCARD': QrKind.contact,
      'MECARD:N:Ali;;': QrKind.contact,
    };
    cases.forEach((input, kind) {
      test('$kind', () {
        final q = QrAnalyzer.classify(input);
        expect(q.kind, kind);
        expect(q.link, isNull, reason: 'غير الروابط مبيتفحصوش كروابط');
        expect(q.note, isNotEmpty);
      });
    });
  });

  group('QrAnalyzer.classify: نص عادي أو خطير', () {
    test('نص بدون رابط ومحتوى فاضي', () {
      for (final t in <String>['hello world', 'مرحبا بالعالم', '']) {
        final q = QrAnalyzer.classify(t);
        expect(q.kind, QrKind.text, reason: '"$t"');
        expect(q.link, isNull, reason: '"$t"');
      }
    });

    test('javascript: و file: مش بيتحولوا لرابط قابل للفتح', () {
      expect(QrAnalyzer.classify('javascript:alert(1)').link, isNull);
      expect(QrAnalyzer.classify('file:///etc/passwd').link, isNull);
    });
  });
}
