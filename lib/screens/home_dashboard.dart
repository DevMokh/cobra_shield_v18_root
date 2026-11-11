import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../services/history_store.dart';
import '../services/strings.dart';
import '../services/threat_feed.dart';
import '../widgets/common.dart';
import '../widgets/scale_header.dart';
import '../widgets/stats_card.dart';

const List<String> _tips = <String>[
  'لو رسالة بتهدّدك بإيقاف حسابك خلال ساعات، دي علامة نصب كلاسيكية. البنوك الحقيقية مش بتستعجلك كده.',
  'محدش رسمي (بنك، محفظة، شركة اتصالات) هيطلب منك كود التحقق أو الـ CVV في مكالمة أو رسالة. اقفل الخط.',
  'اقرأ اسم الدومين من اليمين لليسار قبل الـ.com أو .eg. الجزء الأهم هو أقرب حاجة لنوع الامتداد.',
  'لو حد قالك "رقمي اتغير" وطلب فلوس، اتصل بالرقم القديم أو اسأله سؤال يعرفه هو بس قبل ما تحول.',
  'رمز QR ممكن يتلصق فوق رمز حقيقي في محل أو عداد ركن. راجع اسم الموقع بعد ما تفحصه قبل الدفع.',
  'لا تثبت تطبيق تحكم عن بعد بناءً على طلب حد اتصل بيك وقال إنه دعم فني.',
  'وظيفة بتطلب فلوس تسجيل مقدمًا هي نصب في الأغلب، مهما كان المرتب المعروض مغري.',
  'لو الرسالة فيها رابط ومعاه استعجال أو تهديد، افتراض إنه نصب أأمن ليك من فتحه.',
  'غيّر كلمة السر فورًا لو ضغطت على رابط مشبوه وكتبت بياناتك، وفعّل التحقق بخطوتين لو متاح.',
  'الجهات الحكومية (تموين، تأمينات، كهرباء) مش بترسل روابط دفع أو تهديد بقطع خدمة برسالة SMS.',
];

String _tipOfDay() {
  final day = DateTime.now().difference(DateTime(2026, 1, 1)).inDays;
  return _tips[day % _tips.length];
}

/// الشاشة الرئيسية: نظرة سريعة على حالة الجهاز وآخر الفحوصات ونصيحة اليوم.
class HomeDashboard extends StatelessWidget {
  const HomeDashboard({
    super.key,
    required this.onTab,
    required this.onQr,
    required this.onImage,
    required this.onTrain,
    required this.onLearn,
    required this.onSettings,
  });

  /// 0 الرئيسية، 1 رابط، 2 رسالة، 3 السجل، 4 المزيد
  final void Function(int tabIndex) onTab;
  final VoidCallback onQr;
  final VoidCallback onImage;
  final VoidCallback onTrain;
  final VoidCallback onLearn;
  final VoidCallback onSettings;

  Widget _quick(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: C.line),
          ),
          child: Column(
            children: [
              Icon(icon, color: C.emerald, size: 26),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: C.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        HistoryStore.instance,
        ThreatFeed.instance,
      ]),
      builder: (context, _) {
        final items = HistoryStore.instance.items;
        final feed = ThreatFeed.instance;
        final stale = feed.updated == null ||
            DateTime.now().difference(feed.updated!) > const Duration(days: 14);
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ScaleHeader(
              title: tr(S.homeTitle),
              subtitle: tr(S.homeSubtitle),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Panel(
                    borderColor: alpha(C.amber, 0.4),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_rounded, color: C.amber, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _tipOfDay(),
                            style: const TextStyle(
                              color: C.text,
                              fontSize: 13,
                              height: 1.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const SectionTitle('افحص'),
                  Row(
                    children: [
                      _quick(Icons.link_rounded, 'رابط', () => onTab(1)),
                      const SizedBox(width: 10),
                      _quick(Icons.mark_email_unread_rounded, 'رسالة', () => onTab(2)),
                      const SizedBox(width: 10),
                      _quick(Icons.qr_code_scanner_rounded, 'رمز QR', onQr),
                      const SizedBox(width: 10),
                      _quick(Icons.image_search_rounded, 'صورة', onImage),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const SectionTitle('تعلّم'),
                  Row(
                    children: [
                      _quick(Icons.sports_esports_rounded, 'تدرّب', onTrain),
                      const SizedBox(width: 10),
                      _quick(Icons.school_rounded, 'دروس الحماية', onLearn),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (items.isEmpty)
                    const Panel(
                      padding: EdgeInsets.symmetric(vertical: 30, horizontal: 16),
                      child: Column(
                        children: [
                          Icon(Icons.shield_outlined, color: C.muted, size: 38),
                          SizedBox(height: 10),
                          Text(
                            'لسه معملتش أي فحص. ابدأ برابط أو رسالة وصلتك.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: C.muted, height: 1.5),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    StatsCard(items: items),
                    const SizedBox(height: 14),
                    SectionTitle(
                      'آخر الفحوصات',
                      trailing: TextButton(
                        onPressed: () => onTab(3),
                        child: const Text('الكل'),
                      ),
                    ),
                    for (final it in items.take(3)) _recent(it),
                  ],
                  if (stale) ...[
                    const SizedBox(height: 14),
                    Panel(
                      borderColor: alpha(C.amber, 0.4),
                      child: Row(
                        children: [
                          const Icon(Icons.update_rounded, color: C.amber),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              feed.updated == null
                                  ? 'قاعدة مصادر التهديدات لسه مش محمّلة. حمّلها من المزيد ← الإعدادات.'
                                  : 'قاعدة مصادر التهديدات قديمة. حدّثها من المزيد ← الإعدادات للحصول على أحدث كشف.',
                              style: const TextStyle(color: C.muted, fontSize: 12.5, height: 1.5),
                            ),
                          ),
                          TextButton(
                            onPressed: onSettings,
                            child: const Text('الإعدادات'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _recent(HistoryItem it) {
    final c = levelColor(it.level);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: C.line),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: alpha(c, 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${it.score}',
              style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Directionality(
              textDirection:
                  it.kind == ScanKind.url ? TextDirection.ltr : TextDirection.rtl,
              child: Text(
                it.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: C.text, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
