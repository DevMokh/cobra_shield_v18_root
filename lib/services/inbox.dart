import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// نص وارد (كل مرة نص جديد = كائن جديد عشان المستمعين يتنبهوا حتى لو النص نفسه)
class Incoming {
  Incoming(this.text);
  final String text;
}

/// جسر استقبال النص من أندرويد (مشاركة / تحديد نص) + صناديق وارد داخلية للشاشات.
class Inbox {
  Inbox._();

  static const MethodChannel _ch = MethodChannel('cobra/share');

  /// نص جاي من خارج التطبيق
  static final ValueNotifier<Incoming?> shared = ValueNotifier<Incoming?>(null);

  /// طلبات فحص موجّهة للشاشات
  static final ValueNotifier<Incoming?> toUrl = ValueNotifier<Incoming?>(null);
  static final ValueNotifier<Incoming?> toMessage = ValueNotifier<Incoming?>(null);

  static bool _started = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onText') {
        _push(call.arguments as String?);
      }
      return null;
    });
    try {
      _push(await _ch.invokeMethod<String>('getInitialText'));
    } catch (_) {
      // نسخة بدون الجسر الأصلي: نتجاهل
    }
  }

  static void _push(String? t) {
    if (t == null) return;
    var s = t.trim();
    if (s.isEmpty) return;
    if (s.length > 5000) s = s.substring(0, 5000);
    shared.value = Incoming(s);
  }
}
