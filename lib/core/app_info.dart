/// رقم إصدار التطبيق (اسم الإصدار فقط، من غير build number).
///
/// لازم يطابق `version:` في pubspec.yaml، وفيه اختبار (`app_info_test.dart`) بيفشل لو اتخالفوا.
/// بيتبعت كـ clientVersion لخدمة Google Safe Browsing، فمش لازم يفضل رقم قديم.
const String kAppVersion = '1.11.0';
