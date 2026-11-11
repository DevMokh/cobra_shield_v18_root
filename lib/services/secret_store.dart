import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// تخزين الأسرار (مفاتيح API). واجهة صغيرة عشان نقدر نختبر منطق الحفظ والترحيل
/// بدون الإضافة الأصلية.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// التنفيذ الفعلي: Android Keystore عبر flutter_secure_storage (مشفّر).
class PlatformSecretStore implements SecretStore {
  PlatformSecretStore() : _s = const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);

  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _s.delete(key: key);
}
