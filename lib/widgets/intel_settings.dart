import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/settings_store.dart';
import '../services/threat_feed.dart';
import 'common.dart';

/// إعدادات مصادر التهديدات: قاعدة OpenPhish المحلية + مفاتيح API الخاصة بك.
class IntelSettingsPanel extends StatefulWidget {
  const IntelSettingsPanel({super.key});

  @override
  State<IntelSettingsPanel> createState() => _IntelSettingsPanelState();
}

class _IntelSettingsPanelState extends State<IntelSettingsPanel> {
  final TextEditingController _gsb = TextEditingController();
  final TextEditingController _vt = TextEditingController();
  late final Listenable _merged =
      Listenable.merge(<Listenable>[ThreatFeed.instance, SettingsStore.instance]);
  bool _hide = true;

  @override
  void initState() {
    super.initState();
    _gsb.text = SettingsStore.instance.gsbKey;
    _vt.text = SettingsStore.instance.vtKey;
  }

  @override
  void dispose() {
    _gsb.dispose();
    _vt.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    final rep = await ThreatFeed.instance.update();
    if (!mounted) return;
    toast(context, rep.summary);
  }

  Future<void> _saveKeys() async {
    FocusScope.of(context).unfocus();
    final saved = await SettingsStore.instance.setKeys(gsb: _gsb.text, vt: _vt.text);
    if (!mounted) return;
    toast(
      context,
      saved
          ? 'تم حفظ المفاتيح في التخزين الآمن للجهاز'
          : 'التخزين الآمن غير متاح: المفاتيح شغالة حتى تقفل التطبيق ولن تُحفظ',
    );
  }

  Widget _keyField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      obscureText: _hide,
      autocorrect: false,
      enableSuggestions: false,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
      style: const TextStyle(fontFamily: 'monospace', color: C.text, fontSize: 13),
      decoration: fieldDecoration(hint: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _merged,
      builder: (context, _) {
        final feed = ThreatFeed.instance;
        final updated = feed.updated;
        final stale = updated == null ||
            DateTime.now().difference(updated) > const Duration(days: 14);
        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('مصادر التهديدات الحية'),
              const Text(
                'تُستخدم في "الفحص المتقدم" داخل تبويب فحص الرابط. كلها اختيارية.',
                style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 6),
              // موافقة الإرسال للخدمات الخارجية: كانت بتتحفظ بدون أي طريقة لسحبها.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: SettingsStore.instance.intelConsent,
                onChanged: (v) => SettingsStore.instance.setIntelConsent(v),
                title: const Text(
                  'السماح بالفحص المتقدم عبر الإنترنت',
                  style: TextStyle(color: C.text, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                  'يتصل بالرابط نفسه ويرسل الدومين لـ RDAP، والرابط الكامل لـ Google/VirusTotal إن أضفت مفاتيحهم. أوقفه وما يتبعت شيء.',
                  style: TextStyle(color: C.muted, fontSize: 12, height: 1.4),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.shield_moon_rounded, color: C.emerald, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'قاعدة OpenPhish (محلية)',
                          style: TextStyle(
                            color: C.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          feed.count == 0
                              ? 'غير محمّلة'
                              : '${feed.count} رابط${updated != null ? ' - آخر تحديث ناجح محفوظ: ${fmtTime(updated)}' : ''}',
                          style: const TextStyle(color: C.muted, fontSize: 12.5),
                        ),
                        const Text(
                          'المصدر: OpenPhish Community Feed',
                          style: TextStyle(color: C.muted, fontSize: 11.5),
                        ),
                        if (feed.memoryOnly)
                          const Text(
                            'تنبيه: التحديث الأخير لم يُحفظ على الجهاز.',
                            style: TextStyle(color: C.amber, fontSize: 12),
                          ),
                        if (feed.lastReport != null && !feed.lastReport!.ok)
                          Text(
                            feed.lastReport!.summary,
                            style: const TextStyle(color: C.amber, fontSize: 12, height: 1.4),
                          ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: feed.busy ? null : _update,
                    style: outlineButtonStyle(),
                    child: feed.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('تحديث'),
                  ),
                ],
              ),
              if (stale) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: alpha(C.amber, 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: alpha(C.amber, 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: C.amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          updated == null
                              ? 'القاعدة لسه مش محمّلة. اضغط تحديث فوق.'
                              : 'آخر تحديث من أكتر من أسبوعين. حدّثها عشان تفضل فعّالة.',
                          style: const TextStyle(color: C.muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(color: C.line, height: 28),
              const Text(
                'مفاتيح API (اختيارية)',
                style: TextStyle(
                  color: C.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              if (!SettingsStore.instance.keysSecure) ...[
                const Text(
                  'تنبيه: التخزين الآمن غير متاح على جهازك، فالمفاتيح هتفضل في الذاكرة حتى تقفل التطبيق وتحتاج تدخلها تاني.',
                  style: TextStyle(color: C.amber, fontSize: 12, height: 1.5),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              _keyField(_gsb, 'Google Safe Browsing API key'),
              const SizedBox(height: 8),
              _keyField(_vt, 'VirusTotal API key'),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(
                    _hide ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                    size: 18,
                  ),
                  label: Text(_hide ? 'إظهار' : 'إخفاء'),
                  style: TextButton.styleFrom(foregroundColor: C.muted),
                ),
              ),
              FilledButton.icon(
                onPressed: _saveKeys,
                style: filledButtonStyle(),
                icon: const Icon(Icons.save_rounded),
                label: const Text('حفظ المفاتيح'),
              ),
              const SizedBox(height: 12),
              const Text(
                'الحصول على المفاتيح: Google Safe Browsing من Google Cloud Console (فعّل Safe Browsing API وأنشئ API key)، و VirusTotal من حسابك المجاني في موقعهم. '
                'المفاتيح بتتخزن مشفّرة في مخزن مفاتيح أندرويد على جهازك، ولا تُكتب في سجلات التطبيق.\n\n'
                'تنبيه ترخيص: الخطط المجانية لـ Google Safe Browsing و VirusTotal و OpenPhish مخصصة للاستخدام غير التجاري. '
                'لو ستنشر التطبيق بمقابل أو بإعلانات فراجع شروط كل جهة أو استخدم خطط تجارية.',
                style: TextStyle(color: C.muted, fontSize: 12, height: 1.5),
              ),
            ],
          ),
        );
      },
    );
  }
}
