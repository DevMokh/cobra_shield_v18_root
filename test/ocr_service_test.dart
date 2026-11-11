import 'package:cobra_shield/services/ocr_service.dart';
import 'package:cobra_shield/services/ocr_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _channel = MethodChannel('cobra/ocr');

void mockChannel(Future<Object?>? Function(MethodCall call)? handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    mockChannel(null);
    OcrService.latinFallbackOverride = null;
  });

  test('Tesseract شغّال: النص بيتنضّف والمحرك يقرأ العربي', () async {
    String? seenPath;
    mockChannel((call) async {
      expect(call.method, 'recognize');
      seenPath = (call.arguments as Map<Object?, Object?>)['path'] as String?;
      return 'مرحبا\f\r\nhttp://a.example.com  \n\n\n\nشكرا';
    });
    OcrService.latinFallbackOverride = (_) async => fail('لازم ما يرجعش للاحتياطي');
    final o = await OcrService.extract('/tmp/shot.png');
    expect(seenPath, '/tmp/shot.png');
    expect(o.engine, OcrEngine.tesseract);
    expect(o.readsArabic, isTrue);
    expect(o.fallbackReason, isNull);
    expect(o.text, 'مرحبا\nhttp://a.example.com\n\nشكرا');
  });

  test('الرد الجديد (Map): النص والثقة والقراءة المعكوسة', () async {
    mockChannel((call) async => <String, Object?>{
          'text': 'تنبيه: حسابك تم تعليقه، ادخل على الرابط http://x.example.top/v',
          'confidence': 83,
          'inverted': true,
          'langs': 'ara+eng',
        });
    OcrService.latinFallbackOverride = (_) async => fail('لازم ما يرجعش للاحتياطي');
    final o = await OcrService.extract('/tmp/dark.png');
    expect(o.engine, OcrEngine.tesseract);
    expect(o.confidence, 83);
    expect(o.invertedPass, isTrue);
    expect(o.containsArabic, isTrue);
    expect(o.quality, OcrQuality.good);
    expect(o.readsArabic, isTrue);
  });

  test('ثقة منخفضة: جودة low حتى لو فيه نص', () async {
    mockChannel((call) async => <String, Object?>{
          'text': 'مرحبا بك في خدمة العملاء الرسمية',
          'confidence': 31,
          'inverted': false,
        });
    final o = await OcrService.extract('/tmp/blurry.png');
    expect(o.quality, OcrQuality.low);
    expect(o.readsArabic, isTrue);
  });

  test('صورة بدون نص: Tesseract فاضي وML Kit كمان فاضي = empty (والعربي مغطّى)', () async {
    mockChannel((call) async => '');
    OcrService.latinFallbackOverride = (_) async => '   ';
    final o = await OcrService.extract('/tmp/blank.png');
    expect(o.engine, OcrEngine.tesseract);
    expect(o.text, '');
    expect(o.quality, OcrQuality.empty);
    expect(o.readsArabic, isTrue);
  });

  test('Tesseract فاضي لكن ML Kit لقى نص لاتيني: نستخدمه ومنقولش إن العربي ما اتقراش', () async {
    mockChannel((call) async => <String, Object?>{'text': '', 'confidence': 0});
    OcrService.latinFallbackOverride = (_) async => 'Visit http://a.example.com now';
    final o = await OcrService.extract('/tmp/latin.png');
    expect(o.engine, OcrEngine.mlkitLatin);
    expect(o.fallbackReason, 'tesseract_empty');
    expect(o.text, 'Visit http://a.example.com now');
    expect(o.readsArabic, isTrue);
  });

  test('Tesseract فاضي وML Kit بيفشل: بنرجّع النتيجة الفاضية (مش استثناء)', () async {
    mockChannel((call) async => '');
    OcrService.latinFallbackOverride = (_) async => throw StateError('mlkit down');
    final o = await OcrService.extract('/tmp/blank.png');
    expect(o.quality, OcrQuality.empty);
  });

  test('نموذج اللغة ناقص (model_missing): رجوع للاحتياطي مع السبب ومن غير عربي', () async {
    mockChannel((call) async => throw PlatformException(code: 'model_missing'));
    OcrService.latinFallbackOverride = (_) async => 'hello world text here';
    final o = await OcrService.extract('/tmp/shot.png');
    expect(o.fallbackReason, 'model_missing');
    expect(o.readsArabic, isFalse);
  });

  test('فشل Tesseract (PlatformException): رجوع لـ ML Kit واللغة العربية غير مدعومة', () async {
    mockChannel((call) async => throw PlatformException(code: 'ocr_failed', message: 'x'));
    OcrService.latinFallbackOverride = (path) async => 'hello  \f';
    final o = await OcrService.extract('/tmp/shot.png');
    expect(o.engine, OcrEngine.mlkitLatin);
    expect(o.readsArabic, isFalse);
    expect(o.fallbackReason, 'ocr_failed');
    expect(o.text, 'hello');
  });

  test('القناة غير موجودة (MissingPluginException): سبب unavailable', () async {
    mockChannel(null);
    OcrService.latinFallbackOverride = (_) async => 'english text';
    final o = await OcrService.extract('/tmp/shot.png');
    expect(o.engine, OcrEngine.mlkitLatin);
    expect(o.fallbackReason, 'unavailable');
    expect(o.text, 'english text');
  });

  test('لو المحركين فشلوا يترمي استثناء (الفشل مش "آمن")', () async {
    mockChannel((call) async => throw PlatformException(code: 'ocr_failed'));
    OcrService.latinFallbackOverride = (_) async => throw StateError('mlkit failed');
    expect(() => OcrService.extract('/tmp/shot.png'), throwsA(isA<StateError>()));
  });
}
