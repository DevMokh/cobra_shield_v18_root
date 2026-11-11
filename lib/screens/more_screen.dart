import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/settings_store.dart';
import '../services/strings.dart';
import '../widgets/common.dart';
import '../widgets/intel_settings.dart';
import '../widgets/scale_header.dart';
import '../widgets/sub_page.dart';
import '../widgets/tools.dart';
import '../widgets/tools_extra.dart';
import 'learn_screen.dart';
import 'train_screen.dart';

/// نص بحسب لغة الواجهة الحالية (عربي/إنجليزي) لهذه الشاشة فقط.
String _t(String ar, String en) => SettingsStore.instance.english ? en : ar;

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

void openTrain(BuildContext context) {
  _push(context, const BackPage(child: TrainScreen()));
}

void openLearn(BuildContext context) {
  _push(context, const LearnPage());
}

void openSettings(BuildContext context) {
  _push(
    context,
    ToolPage(
      title: _t('الإعدادات', 'Settings'),
      subtitle: _t('اللغة والتنبيهات ومصادر الفحص المتقدم',
          'Language, alerts and advanced scan sources'),
      icon: Icons.settings_rounded,
      children: const <Widget>[
        SettingsPanel(),
        SizedBox(height: 14),
        IntelSettingsPanel(),
      ],
    ),
  );
}

void _openTool(
  BuildContext context,
  String title,
  String subtitle,
  IconData icon,
  Widget tool,
) {
  _push(
    context,
    ToolPage(
      title: title,
      subtitle: subtitle,
      icon: icon,
      children: <Widget>[tool],
    ),
  );
}

/// تبويب "المزيد": كل الميزات التانية مرتبة في أقسام واضحة.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.onQr, required this.onImage});

  final VoidCallback onQr;
  final VoidCallback onImage;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ScaleHeader(
          title: tr(S.moreTitle),
          subtitle: tr(S.moreSubtitle),
          icon: Icons.apps_rounded,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(_t('فحوصات إضافية', 'More scans')),
              _MoreItem(
                icon: Icons.qr_code_scanner_rounded,
                title: _t('مسح رمز QR', 'Scan a QR code'),
                subtitle: _t('افحص الرابط داخل الرمز قبل ما تفتحه',
                    'Check the link inside a code before opening it'),
                onTap: onQr,
              ),
              _MoreItem(
                icon: Icons.image_search_rounded,
                title: _t('فحص صورة رسالة', 'Scan a message screenshot'),
                subtitle: _t('اقرأ النص من لقطة شاشة وحلّله',
                    'Read the text from a screenshot and analyze it'),
                onTap: onImage,
              ),
              _MoreItem(
                icon: Icons.alternate_email_rounded,
                title: _t('فحص المرسل', 'Check a sender'),
                subtitle: _t('إيميل أو رقم أو اسم مرسل مريب؟',
                    'Suspicious email, number or sender name?'),
                onTap: () => _openTool(
                  context,
                  _t('فحص المرسل', 'Check a sender'),
                  _t('تحقق من هوية المرسل', 'Verify who sent it'),
                  Icons.alternate_email_rounded,
                  const SenderTool(),
                ),
              ),
              _MoreItem(
                icon: Icons.playlist_add_check_rounded,
                title: _t('فحص مجمّع', 'Batch scan'),
                subtitle: _t('افحص عدة روابط مرة واحدة',
                    'Scan several links at once'),
                onTap: () => _openTool(
                  context,
                  _t('فحص مجمّع', 'Batch scan'),
                  _t('الصق عدة روابط وافحصها دفعة واحدة',
                      'Paste several links and scan them together'),
                  Icons.playlist_add_check_rounded,
                  const BatchTool(),
                ),
              ),
              const SizedBox(height: 10),
              SectionTitle(_t('تعلّم وتدرّب', 'Learn and train')),
              _MoreItem(
                icon: Icons.sports_esports_rounded,
                title: _t('تدرّب على الكشف', 'Train your detection'),
                subtitle: _t('خمس مراحل تتصاعد في الصعوبة',
                    'Five levels that get harder'),
                onTap: () => openTrain(context),
              ),
              _MoreItem(
                icon: Icons.school_rounded,
                title: _t('دروس الحماية', 'Protection lessons'),
                subtitle: _t('قواعد سريعة تحميك من الاحتيال',
                    'Quick rules that protect you from scams'),
                onTap: () => openLearn(context),
              ),
              const SizedBox(height: 10),
              SectionTitle(_t('أدوات كلمات السر والروابط', 'Password and link tools')),
              _MoreItem(
                icon: Icons.password_rounded,
                title: _t('قوة كلمة السر', 'Password strength'),
                subtitle: _t('اعرف كلمة سرك قوية ولا لأ',
                    'See how strong your password is'),
                onTap: () => _openTool(
                  context,
                  _t('قوة كلمة السر', 'Password strength'),
                  _t('التحليل بيتم على جهازك فقط', 'Analyzed on your device only'),
                  Icons.password_rounded,
                  const StrengthTool(),
                ),
              ),
              _MoreItem(
                icon: Icons.casino_rounded,
                title: _t('مولّد كلمات السر', 'Password generator'),
                subtitle: _t('كلمات سر عشوائية قوية',
                    'Strong random passwords'),
                onTap: () => _openTool(
                  context,
                  _t('مولّد كلمات السر', 'Password generator'),
                  _t('كلمات سر عشوائية قوية', 'Strong random passwords'),
                  Icons.casino_rounded,
                  const GeneratorTool(),
                ),
              ),
              _MoreItem(
                icon: Icons.cleaning_services_rounded,
                title: _t('منظّف الروابط', 'Link cleaner'),
                subtitle: _t('شيل التتبّع من الرابط قبل ما تشاركه',
                    'Remove tracking from a link before sharing it'),
                onTap: () => _openTool(
                  context,
                  _t('منظّف الروابط', 'Link cleaner'),
                  _t('شيل التتبّع من الرابط', 'Remove tracking from a link'),
                  Icons.cleaning_services_rounded,
                  const CleanerTool(),
                ),
              ),
              _MoreItem(
                icon: Icons.tag_rounded,
                title: _t('هاش', 'Hash'),
                subtitle: _t('احسب بصمة نص (SHA وغيرها)',
                    'Compute a text fingerprint (SHA and more)'),
                onTap: () => _openTool(
                  context,
                  _t('هاش', 'Hash'),
                  _t('بصمة النص على جهازك', 'Text fingerprint on your device'),
                  Icons.tag_rounded,
                  const HashTool(),
                ),
              ),
              const SizedBox(height: 10),
              SectionTitle(_t('الإعدادات', 'Settings')),
              _MoreItem(
                icon: Icons.settings_rounded,
                title: _t('الإعدادات ومصادر الفحص', 'Settings and scan sources'),
                subtitle: _t('اللغة، مراقبة الحافظة، مفاتيح الفحص المتقدم',
                    'Language, clipboard watch, advanced scan keys'),
                onTap: () => openSettings(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreItem extends StatelessWidget {
  const _MoreItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: C.line),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: alpha(C.emerald, 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: C.emerald, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: C.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: C.muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, color: C.muted),
            ],
          ),
        ),
      ),
    );
  }
}
