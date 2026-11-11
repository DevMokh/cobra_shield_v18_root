import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/strings.dart';
import '../widgets/scale_header.dart';

class _Lesson {
  const _Lesson(this.icon, this.title, this.points);
  final IconData icon;
  final String title;
  final List<String> points;
}

const List<_Lesson> _lessons = <_Lesson>[
  _Lesson(Icons.link_rounded, 'إزاي تقرأ الرابط صح؟', <String>[
    'الدومين الحقيقي هو الجزء الأخير قبل أول "/". مثال: paypal.com.evil.xyz دومينه الحقيقي evil.xyz.',
    'احذر الحروف المتشابهة: paypa1 بدل paypal، أو rn بدل m.',
    'الروابط المختصرة (bit.ly وأخواتها) تخفي الوجهة، افحصها قبل الفتح.',
    'قفل HTTPS لا يعني أن الموقع آمن، المحتالون يستخدمونه أيضًا.',
  ]),
  _Lesson(Icons.report_gmailerrorred_rounded, 'علامات رسالة التصيّد', <String>[
    'استعجال: "خلال 24 ساعة" أو "فورًا".',
    'تهديد: "سيتم إيقاف حسابك" أو "غرامة".',
    'طلب كود التحقق أو الرقم السري أو بيانات البطاقة.',
    'جائزة أو استرداد لم تكن تنتظره.',
    'رابط يبدو قريبًا من اسم جهة معروفة لكنه ليس دومينها الرسمي.',
  ]),
  _Lesson(Icons.phone_android_rounded, 'خدع منتشرة في مصر', <String>[
    'رسائل "تعذر تسليم الشحنة" مع رابط لدفع رسوم صغيرة.',
    'رسائل محافظ الدفع والتحويل اللحظي تطلب منك "تأكيد" بياناتك.',
    'مخالفات مرورية أو فواتير مستحقة برابط دفع غير رسمي.',
    'القاعدة: الجهة الحقيقية لا تطلب منك كود التحقق ولا الدفع عبر رابط وصلك برسالة. افتح تطبيقها أو موقعها الرسمي بنفسك.',
  ]),
  _Lesson(Icons.healing_rounded, 'لو ضغطت على رابط مشبوه', <String>[
    'لا تُدخل أي بيانات. أغلق الصفحة فورًا.',
    'لو نزّل ملفًا: لا تفتحه واحذفه، وافحص الجهاز.',
    'لو أدخلت كلمة مرور: غيّرها من جهاز آخر، وفعّل التحقق بخطوتين.',
    'لو أدخلت بيانات بطاقة أو محفظة: اتصل بالجهة فورًا لتجميدها.',
  ]),
  _Lesson(Icons.rule_rounded, 'حدود هذا التطبيق', <String>[
    'التحليل يعتمد على قواعد وأنماط شائعة محليًا، وليس على قاعدة بيانات تهديدات حيّة.',
    'نتيجة منخفضة لا تعني أن الرابط آمن، فقد يكون موقعًا جديدًا مخترقًا.',
    'نتيجة مرتفعة لا تعني بالضرورة احتيالًا مؤكدًا، لكنها سبب كافٍ للحذر.',
    'استخدمه كمساعد للانتباه، وليس بديلًا عن حكمك الشخصي.',
  ]),
];

/// صفحة الدروس بزر رجوع (تُفتح من شاشة التدريب)
class LearnPage extends StatelessWidget {
  const LearnPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const LearnScreen(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            left: 12,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: C.text),
              style: IconButton.styleFrom(backgroundColor: alpha(C.bg, 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ScaleHeader(
          title: tr(S.learnTitle),
          subtitle: tr(S.learnSubtitle),
          icon: Icons.school_rounded,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          child: Column(
            children: [
              for (final l in _lessons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: C.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: C.line),
                    ),
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      iconColor: C.emerald,
                      collapsedIconColor: C.muted,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      leading: Icon(l.icon, color: C.emerald),
                      title: Text(
                        l.title,
                        style: const TextStyle(
                          color: C.text,
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      children: [
                        for (final p in l.points)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 6),
                                  child: Icon(Icons.circle, size: 6, color: C.emerald),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    p,
                                    style: const TextStyle(
                                      color: C.muted,
                                      height: 1.55,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
