import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secret_store.dart';

class SettingsStore extends ChangeNotifier {
  SettingsStore._() : _secrets = PlatformSecretStore();

  @visibleForTesting
  SettingsStore.forTest(SecretStore secrets) : _secrets = secrets;

  static final SettingsStore instance = SettingsStore._();

  static const String _kClip = 'cobra.clipwatch';
  static const String _kGsb = 'cobra.key.gsb';
  static const String _kVt = 'cobra.key.vt';
  static const String _kConsent = 'cobra.intel.consent';
  static const String _kEnglish = 'cobra.lang.en';

  final SecretStore _secrets;

  bool _clipWatch = false;
  String _gsbKey = '';
  String _vtKey = '';
  bool _intelConsent = false;
  bool _english = false;
  bool _keysSecure = true;

  bool get clipWatch => _clipWatch;
  String get gsbKey => _gsbKey;
  String get vtKey => _vtKey;
  bool get intelConsent => _intelConsent;
  bool get english => _english;

  /// false = التخزين الآمن مش شغال على الجهاز ده: المفاتيح بتتحفظ للجلسة الحالية
  /// بس (في الذاكرة)، ومبنكتبهاش أبدًا كنص عادي على الجهاز.
  bool get keysSecure => _keysSecure;

  Future<void> load() async {
    SharedPreferences? p;
    try {
      p = await SharedPreferences.getInstance();
      _clipWatch = p.getBool(_kClip) ?? false;
      _intelConsent = p.getBool(_kConsent) ?? false;
      _english = p.getBool(_kEnglish) ?? false;
    } catch (_) {
      p = null;
    }
    await _loadKeys(p);
    notifyListeners();
  }

  /// قراءة المفاتيح من التخزين الآمن + ترحيل آمن للنسخة القديمة (SharedPreferences).
  /// القاعدة: ما بنمسحش النسخة القديمة غير بعد ما نتأكد إن الآمنة اتكتبت واتقرت.
  Future<void> _loadKeys(SharedPreferences? p) async {
    final legacyGsb = _readLegacy(p, _kGsb);
    final legacyVt = _readLegacy(p, _kVt);
    try {
      _gsbKey = await _resolve(p, _kGsb, legacyGsb);
      _vtKey = await _resolve(p, _kVt, legacyVt);
      _keysSecure = true;
    } catch (_) {
      // التخزين الآمن غير متاح: نكمل بالقيمة القديمة (لو موجودة) في الذاكرة
      // من غير ما نمسحها، ومن غير ما نكتب أي حاجة جديدة كنص عادي.
      _gsbKey = legacyGsb;
      _vtKey = legacyVt;
      _keysSecure = false;
    }
  }

  String _readLegacy(SharedPreferences? p, String key) {
    try {
      return p?.getString(key) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _dropLegacy(SharedPreferences? p, String key) async {
    try {
      await p?.remove(key);
    } catch (_) {}
  }

  Future<String> _resolve(SharedPreferences? p, String key, String legacy) async {
    final secure = await _secrets.read(key) ?? '';
    if (secure.isNotEmpty) {
      // الآمن هو المرجع. لو لسه فيه نسخة قديمة نظيفها.
      if (legacy.isNotEmpty) await _dropLegacy(p, key);
      return secure;
    }
    if (legacy.isEmpty) return '';
    // ترحيل: اكتب، اقرأ، قارن، وبعدين امسح القديم.
    await _secrets.write(key, legacy);
    final back = await _secrets.read(key);
    if (back == legacy) {
      await _dropLegacy(p, key);
      return legacy;
    }
    // الكتابة ما اتأكدتش: نخلي القديم مكانه ونعتبر التخزين الآمن غير موثوق
    throw StateError('secure write verification failed');
  }

  Future<void> setEnglish(bool v) async {
    _english = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kEnglish, v);
    } catch (_) {}
  }

  Future<void> setClipWatch(bool v) async {
    _clipWatch = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kClip, v);
    } catch (_) {}
  }

  Future<void> setIntelConsent(bool v) async {
    _intelConsent = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kConsent, v);
    } catch (_) {}
  }

  Future<void> _put(String key, String value) {
    return value.isEmpty ? _secrets.delete(key) : _secrets.write(key, value);
  }

  /// يحفظ المفاتيح في التخزين الآمن. يرجّع true لو اتحفظت بشكل دائم، و false لو
  /// التخزين الآمن فشل (المفاتيح شغالة للجلسة الحالية بس ومش متخزنة على الجهاز).
  /// أي نسخة قديمة كنص عادي بتتمسح في الحالتين.
  Future<bool> setKeys({required String gsb, required String vt}) async {
    _gsbKey = gsb.trim();
    _vtKey = vt.trim();
    var ok = true;
    try {
      await _put(_kGsb, _gsbKey);
      await _put(_kVt, _vtKey);
    } catch (_) {
      ok = false;
    }
    _keysSecure = ok;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kGsb);
      await p.remove(_kVt);
    } catch (_) {}
    notifyListeners();
    return ok;
  }
}
