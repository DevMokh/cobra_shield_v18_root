import 'dart:io';

import 'package:cobra_shield/services/net_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NetGuard.isBlockedAddress', () {
    const blocked = <String>[
    '127.0.0.1',
    '127.255.255.254',
    '10.0.0.5',
    '172.16.0.1',
    '172.31.255.255',
    '192.168.1.1',
    '169.254.169.254',
    '100.64.0.1',
    '100.127.255.255',
    '0.0.0.0',
    '255.255.255.255',
    '224.0.0.1',
    '198.18.0.1',
    '198.19.255.255',
    '203.0.113.9',
    '192.0.2.1',
    '::',
    '::1',
    'fe80::1',
    'febf::1',
    'fec0::1',
    'fc00::1',
    'fd12:3456::1',
    'ff02::1',
    '2001:db8::1',
    '::ffff:127.0.0.1',
    '::ffff:10.1.2.3',
    '64:ff9b::7f00:1',
    '2002:7f00:1::1',
    '2001:0::1',
    ];
    const allowed = <String>[
    '172.32.0.1',
    '172.15.255.255',
    '100.128.0.1',
    '198.20.0.1',
    '8.8.8.8',
    '1.1.1.1',
    '93.184.216.34',
    '142.250.190.46',
    '::ffff:8.8.8.8',
    '64:ff9b::808:808',
    '2002:808:808::1',
    '2001:4860:4860::8888',
    '2606:4700:4700::1111',
    '2a00:1450:4001::200e',
    ];
    for (final s in blocked) {
      test('يمنع $s', () {
        expect(NetGuard.isBlockedAddress(InternetAddress(s)), isTrue);
      });
    }
    for (final s in allowed) {
      test('يسمح بـ $s', () {
        expect(NetGuard.isBlockedAddress(InternetAddress(s)), isFalse);
      });
    }
  });

  group('NetGuard.hostBlockReason', () {
    const bad = <String>[
    'localhost',
    'LOCALHOST.',
    'foo.localhost',
    'printer.local',
    'db.internal',
    'router',
    'nas',
    '127.0.0.1',
    '2130706433',
    '0x7f000001',
    '0x7f.0.0.1',
    '0177.0.0.1',
    '127.1',
    '192.168.0.1',
    '169.254.169.254',
    '999.1.1.1',
    '::1',
    'fe80::1',
    '::ffff:7f00:1',
    '',
    ];
    const ok = <String>[
    'example.com',
    'sub.example.co.uk',
    '8.8.8.8',
    '93.184.216.34',
    '2001:4860:4860::8888',
    '1e100.net',
    '123.example.com',
    'a.b',
    ];
    for (final h in bad) {
      test('يرفض المضيف "$h"', () {
        expect(NetGuard.hostBlockReason(h), isNotNull);
      });
    }
    for (final h in ok) {
      test('يقبل المضيف "$h"', () {
        expect(NetGuard.hostBlockReason(h), isNull);
      });
    }
  });

  group('NetGuard.blockReason', () {
    test('روابط عادية تعدّي', () {
      expect(NetGuard.blockReason(Uri.parse('https://example.com/path?a=1')), isNull);
      expect(NetGuard.blockReason(Uri.parse('http://example.com')), isNull);
      expect(NetGuard.blockReason(Uri.parse('http://example.com:8080/x')), isNull);
      expect(NetGuard.blockReason(Uri.parse('https://example.com:8443/x')), isNull);
    });

    test('بروتوكول غير ويب مرفوض', () {
      expect(NetGuard.blockReason(Uri.parse('ftp://example.com/')), isNotNull);
      expect(NetGuard.blockReason(Uri.parse('file:///etc/passwd')), isNotNull);
      expect(NetGuard.blockReason(Uri.parse('javascript:alert(1)')), isNotNull);
    });

    test('user:pass@ مرفوض', () {
      expect(NetGuard.blockReason(Uri.parse('https://user:pass@example.com/')), isNotNull);
      expect(NetGuard.blockReason(Uri.parse('https://paypal.com@evil.example/')), isNotNull);
    });

    test('منفذ غير معتاد مرفوض', () {
      expect(NetGuard.blockReason(Uri.parse('http://example.com:22/')), isNotNull);
      expect(NetGuard.blockReason(Uri.parse('http://example.com:6379/')), isNotNull);
    });

    test('وجهات داخلية مرفوضة', () {
      for (final u in <String>[
        'http://localhost/',
        'http://127.0.0.1/',
        'http://[::1]/',
        'http://2130706433/',
        'http://0x7f000001/',
        'http://192.168.1.1/admin',
        'http://169.254.169.254/latest/meta-data/',
        'http://10.0.0.1:8080/',
        'http://printer.local/',
      ]) {
        expect(NetGuard.blockReason(Uri.parse(u)), isNotNull, reason: u);
      }
    });

    test('رابط طويل جدًا مرفوض', () {
      final long = 'https://example.com/${'a' * 2100}';
      expect(NetGuard.blockReason(Uri.parse(long)), isNotNull);
    });
  });

  group('NetGuard.pickSafeAddress', () {
    test('عنوان عام واحد يتقبل', () {
      final a = NetGuard.pickSafeAddress(<InternetAddress>[InternetAddress('93.184.216.34')]);
      expect(a.address, '93.184.216.34');
    });

    test('يفضّل IPv4', () {
      final a = NetGuard.pickSafeAddress(<InternetAddress>[
        InternetAddress('2606:4700:4700::1111'),
        InternetAddress('93.184.216.34'),
      ]);
      expect(a.type, InternetAddressType.IPv4);
    });

    test('لو أي عنوان داخلي يترفض الكل', () {
      expect(
        () => NetGuard.pickSafeAddress(<InternetAddress>[
          InternetAddress('93.184.216.34'),
          InternetAddress('10.0.0.1'),
        ]),
        throwsA(isA<BlockedTargetException>()),
      );
    });

    test('قائمة فاضية ترمي استثناء', () {
      expect(
        () => NetGuard.pickSafeAddress(const <InternetAddress>[]),
        throwsA(isA<BlockedTargetException>()),
      );
    });
  });
}
