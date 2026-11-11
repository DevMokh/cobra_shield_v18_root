import 'package:cobra_shield/services/secret_store.dart';
import 'package:cobra_shield/services/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تخزين أسرار وهمي في الذاكرة (بدل Android Keystore) مع إمكانية محاكاة الفشل.
class _FakeSecrets implements SecretStore {
  final Map<String, String> data = <String, String>{};
  bool failReads = false;
  bool failWrites = false;

  /// يبلع الكتابة بدون ما يحفظها (محاكاة تخزين معطوب بيرجّع نجاح كاذب).
  bool dropWrites = false;

  @override
  Future<String?> read(String key) async {
    if (failReads) throw StateError('read failed');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('write failed');
    if (dropWrites) return;
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failWrites) throw StateError('delete failed');
    data.remove(key);
  }
}

const String _gsb = 'cobra.key.gsb';
const String _vt = 'cobra.key.vt';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('بدون مفاتيح: القيم فاضية والتخزين الآمن سليم', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final secrets = _FakeSecrets();
    final s = SettingsStore.forTest(secrets);
    await s.load();
    expect(s.gsbKey, '');
    expect(s.vtKey, '');
    expect(s.keysSecure, isTrue);
  });

  test('ترحيل المفاتيح القديمة للتخزين الآمن ومسحها من SharedPreferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      _gsb: 'old-gsb-key',
      _vt: 'old-vt-key',
    });
    final secrets = _FakeSecrets();
    final s = SettingsStore.forTest(secrets);
    await s.load();
    expect(s.gsbKey, 'old-gsb-key');
    expect(s.vtKey, 'old-vt-key');
    expect(s.keysSecure, isTrue);
    expect(secrets.data[_gsb], 'old-gsb-key');
    expect(secrets.data[_vt], 'old-vt-key');
    final p = await SharedPreferences.getInstance();
    expect(p.containsKey(_gsb), isFalse);
    expect(p.containsKey(_vt), isFalse);
  });

  test('لو الكتابة الآمنة فشلت: النسخة القديمة تفضل ومحدش يخسر المفتاح', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{_gsb: 'old-gsb-key'});
    final secrets = _FakeSecrets()..failWrites = true;
    final s = SettingsStore.forTest(secrets);
    await s.load();
    expect(s.gsbKey, 'old-gsb-key');
    expect(s.keysSecure, isFalse);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(_gsb), 'old-gsb-key');
  });

  test('لو التخزين بيبلع الكتابة (فشل تحقق): النسخة القديمة ما بتتمسحش', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{_vt: 'old-vt-key'});
    final secrets = _FakeSecrets()..dropWrites = true;
    final s = SettingsStore.forTest(secrets);
    await s.load();
    expect(s.vtKey, 'old-vt-key');
    expect(s.keysSecure, isFalse);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(_vt), 'old-vt-key');
  });

  test('لو القراءة الآمنة فشلت: نكمل بالقديم من غير مسح', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{_gsb: 'old-gsb-key'});
    final secrets = _FakeSecrets()..failReads = true;
    final s = SettingsStore.forTest(secrets);
    await s.load();
    expect(s.gsbKey, 'old-gsb-key');
    expect(s.keysSecure, isFalse);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(_gsb), 'old-gsb-key');
  });

  test('القيمة الآمنة هي المرجع وأي نسخة قديمة بتتنضف', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{_gsb: 'stale-old'});
    final secrets = _FakeSecrets()..data[_gsb] = 'secure-new';
    final s = SettingsStore.forTest(secrets);
    await s.load();
    expect(s.gsbKey, 'secure-new');
    final p = await SharedPreferences.getInstance();
    expect(p.containsKey(_gsb), isFalse);
  });

  test('setKeys يحفظ في التخزين الآمن ومبيكتبش نص عادي أبدًا', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final secrets = _FakeSecrets();
    final s = SettingsStore.forTest(secrets);
    await s.load();
    final ok = await s.setKeys(gsb: '  new-gsb  ', vt: 'new-vt');
    expect(ok, isTrue);
    expect(s.gsbKey, 'new-gsb');
    expect(secrets.data[_gsb], 'new-gsb');
    expect(secrets.data[_vt], 'new-vt');
    final p = await SharedPreferences.getInstance();
    expect(p.containsKey(_gsb), isFalse);
    expect(p.containsKey(_vt), isFalse);
  });

  test('setKeys بقيمة فاضية يمسح المفتاح', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final secrets = _FakeSecrets()..data[_gsb] = 'x';
    final s = SettingsStore.forTest(secrets);
    await s.load();
    await s.setKeys(gsb: '', vt: '');
    expect(secrets.data.containsKey(_gsb), isFalse);
    expect(s.gsbKey, '');
  });

  test('لو الحفظ الآمن فشل: false، المفتاح للجلسة بس، وملوش نسخة نص عادي', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final secrets = _FakeSecrets();
    final s = SettingsStore.forTest(secrets);
    await s.load();
    secrets.failWrites = true;
    final ok = await s.setKeys(gsb: 'k1', vt: 'k2');
    expect(ok, isFalse);
    expect(s.gsbKey, 'k1');
    expect(s.keysSecure, isFalse);
    final p = await SharedPreferences.getInstance();
    expect(p.containsKey(_gsb), isFalse);
    expect(p.containsKey(_vt), isFalse);
  });
}
