import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../services/history_store.dart';
import '../services/password_tools.dart';
import '../services/progress_store.dart';
import '../services/settings_store.dart';
import '../services/strings.dart';
import '../services/url_analyzer.dart';
import '../services/url_cleaner.dart';
import 'common.dart';

Future<void> _copy(BuildContext context, String text, String done) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, done);
}

Widget _toolTitle(IconData icon, String title, String sub) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: C.emerald, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: C.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: const TextStyle(color: C.muted, fontSize: 12.5, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// 1) قوة كلمة السر
// ---------------------------------------------------------------------------
class StrengthTool extends StatefulWidget {
  const StrengthTool({super.key});

  @override
  State<StrengthTool> createState() => _StrengthToolState();
}

class _StrengthToolState extends State<StrengthTool> {
  final TextEditingController _ctrl = TextEditingController();
  bool _hide = true;
  PasswordReport? _r;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color _color(int level) {
    switch (level) {
      case 0:
        return C.red;
      case 1:
        return C.orange;
      case 2:
        return C.amber;
      default:
        return C.emerald;
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolTitle(
            Icons.password_rounded,
            'اختبر قوة كلمة السر',
            'التحليل داخل جهازك. لا تُحفظ كلمة السر ولا تُرسل لأي مكان.',
          ),
          TextField(
            controller: _ctrl,
            obscureText: _hide,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontFamily: 'monospace',
              color: C.text,
              fontSize: 15,
            ),
            onChanged: (v) => setState(() {
              _r = v.isEmpty ? null : PasswordTools.analyze(v);
            }),
            decoration: fieldDecoration(
              hint: 'اكتب كلمة سر للتجربة',
              suffix: IconButton(
                icon: Icon(
                  _hide ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: C.muted,
                ),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          if (r != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (r.level + 1) / 5,
                minHeight: 9,
                color: _color(r.level),
                backgroundColor: C.surface2,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  r.label,
                  style: TextStyle(
                    color: _color(r.level),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                Text(
                  '${r.bits.round()} بت',
                  style: const TextStyle(color: C.muted, fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'زمن التخمين التقريبي: ${r.crackTime}',
              style: const TextStyle(color: C.text, fontSize: 13.5),
            ),
            const Text(
              'تقدير لهجوم سريع على ملف مسروق، وليس ضمانًا.',
              style: TextStyle(color: C.muted, fontSize: 11.5),
            ),
            if (r.tips.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final t in r.tips)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(Icons.tips_and_updates_rounded,
                            color: C.amber, size: 16),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          t,
                          style: const TextStyle(
                              color: C.muted, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2) مولّد كلمات السر
// ---------------------------------------------------------------------------
class GeneratorTool extends StatefulWidget {
  const GeneratorTool({super.key});

  @override
  State<GeneratorTool> createState() => _GeneratorToolState();
}

class _GeneratorToolState extends State<GeneratorTool> {
  double _len = 18;
  bool _upper = true;
  bool _digits = true;
  bool _symbols = true;
  String _pw = '';

  @override
  void initState() {
    super.initState();
    _gen();
  }

  void _gen() {
    _pw = PasswordTools.generate(
      length: _len.round(),
      upper: _upper,
      digits: _digits,
      symbols: _symbols,
    );
  }

  Widget _chip(String label, bool v, ValueChanged<bool> apply) {
    return FilterChip(
      label: Text(label),
      selected: v,
      onSelected: (x) => setState(() {
        apply(x);
        _gen();
      }),
      selectedColor: alpha(C.emerald, 0.22),
      backgroundColor: C.surface2,
      checkmarkColor: C.emerald,
      side: const BorderSide(color: C.line),
      labelStyle: TextStyle(color: v ? C.emerald : C.muted, fontSize: 13),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolTitle(
            Icons.casino_rounded,
            'مولّد كلمات سر',
            'عشوائي آمن (Random.secure) بدون حروف متشابهة مثل l و1 و O و0.',
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: C.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: C.line),
            ),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                _pw,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: C.emerald,
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'الطول: ${_len.round()}',
                style: const TextStyle(color: C.text, fontSize: 13.5),
              ),
              Expanded(
                child: Slider(
                  value: _len,
                  min: 8,
                  max: 40,
                  divisions: 32,
                  activeColor: C.emerald,
                  inactiveColor: C.line,
                  onChanged: (v) => setState(() {
                    _len = v;
                    _gen();
                  }),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              _chip('حروف كبيرة', _upper, (x) => _upper = x),
              _chip('أرقام', _digits, (x) => _digits = x),
              _chip('رموز', _symbols, (x) => _symbols = x),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => setState(_gen),
                  style: filledButtonStyle(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('ولّد جديدة'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _copy(context, _pw, 'تم النسخ'),
                  style: outlineButtonStyle(),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('نسخ'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'بعد النسخ، الصقها في مدير كلمات سر ثم امسح الحافظة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3) منظّف الروابط
// ---------------------------------------------------------------------------
class CleanerTool extends StatefulWidget {
  const CleanerTool({super.key});

  @override
  State<CleanerTool> createState() => _CleanerToolState();
}

class _CleanerToolState extends State<CleanerTool> {
  final TextEditingController _ctrl = TextEditingController();
  CleanResult? _res;
  int _score = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim();
    if (t == null || t.isEmpty) return;
    _ctrl.text = t;
    _run();
  }

  void _run() {
    FocusScope.of(context).unfocus();
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) return;
    final r = UrlCleaner.clean(raw);
    setState(() {
      _res = r;
      _score = r.valid ? UrlAnalyzer.analyze(r.cleaned).score : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _res;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolTitle(
            Icons.cleaning_services_rounded,
            'منظّف الروابط',
            'يشيل متتبعات الإعلانات (utm و fbclid و gclid ...) قبل ما تشارك الرابط. بدون إنترنت.',
          ),
          TextField(
            controller: _ctrl,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(
                fontFamily: 'monospace', color: C.text, fontSize: 13.5),
            decoration: fieldDecoration(hint: 'https://site.com/page?utm_source=...'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: _run,
                  style: filledButtonStyle(),
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: const Text('نظّف'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _paste,
                  style: outlineButtonStyle(),
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('لصق'),
                ),
              ),
            ],
          ),
          if (r != null) ...[
            const SizedBox(height: 14),
            if (!r.valid)
              const Text(
                'الرابط غير صالح.',
                style: TextStyle(color: C.amber),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: C.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: C.line),
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(
                    r.cleaned,
                    style: const TextStyle(
                      color: C.emerald,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                r.removed.isEmpty
                    ? 'لا توجد متتبعات معروفة في هذا الرابط.'
                    : 'تم حذف ${r.removed.length}: ${r.removed.join('، ')}',
                style: const TextStyle(color: C.muted, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 4),
              Text(
                'درجة الخطر بعد التنظيف: $_score/100',
                style: TextStyle(
                  color: levelColor(levelForScore(_score)),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _copy(context, r.cleaned, 'تم نسخ الرابط النظيف'),
                style: outlineButtonStyle(),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('نسخ الرابط النظيف'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4) هاش النص
// ---------------------------------------------------------------------------
class HashTool extends StatefulWidget {
  const HashTool({super.key});

  @override
  State<HashTool> createState() => _HashToolState();
}

class _HashToolState extends State<HashTool> {
  final TextEditingController _ctrl = TextEditingController();
  Map<String, String> _out = <String, String>{};

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _calc(String v) {
    if (v.isEmpty) {
      setState(() => _out = <String, String>{});
      return;
    }
    final bytes = utf8.encode(v);
    setState(() {
      _out = <String, String>{
        'SHA-256': crypto.sha256.convert(bytes).toString(),
        'SHA-512': crypto.sha512.convert(bytes).toString(),
        'SHA-1': crypto.sha1.convert(bytes).toString(),
        'MD5': crypto.md5.convert(bytes).toString(),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolTitle(
            Icons.fingerprint_rounded,
            'بصمة النص (Hash)',
            'مفيدة للتحقق أن النص لم يتغيّر. MD5 و SHA-1 قديمتان ولا تصلحان للحماية.',
          ),
          TextField(
            controller: _ctrl,
            minLines: 2,
            maxLines: 5,
            onChanged: _calc,
            style: const TextStyle(color: C.text, fontSize: 14.5),
            decoration: fieldDecoration(hint: 'اكتب أو الصق النص هنا'),
          ),
          for (final e in _out.entries) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              decoration: BoxDecoration(
                color: C.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: C.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.key,
                          style: const TextStyle(
                            color: C.emerald,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: SelectableText(
                            e.value,
                            style: const TextStyle(
                              color: C.text,
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: C.muted, size: 18),
                    onPressed: () => _copy(context, e.value, 'تم نسخ ${e.key}'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// الإعدادات
// ---------------------------------------------------------------------------
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  Future<void> _confirm(
    BuildContext context,
    String title,
    String body,
    Future<void> Function() action,
    String done,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface2,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: C.red),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await action();
      if (context.mounted) toast(context, done);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsStore.instance,
      builder: (context, _) {
        final s = SettingsStore.instance;
        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('الإعدادات'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.english,
                onChanged: (v) => s.setEnglish(v),
                title: Text(
                  tr(S.languageLabel),
                  style: const TextStyle(color: C.text, fontSize: 14.5),
                ),
                subtitle: Text(
                  tr(S.languageHint),
                  style: const TextStyle(color: C.muted, fontSize: 12, height: 1.4),
                ),
                secondary: const Icon(Icons.language_rounded, color: C.emerald),
              ),
              const Divider(color: C.line),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: s.clipWatch,
                onChanged: (v) => s.setClipWatch(v),
                title: const Text(
                  'تنبيه عند نسخ رابط',
                  style: TextStyle(color: C.text, fontSize: 14.5),
                ),
                subtitle: const Text(
                  'عند فتح التطبيق، لو في الحافظة رابط يعرض عليك فحصه. قد يُظهر أندرويد إشعارًا عند قراءة الحافظة.',
                  style: TextStyle(color: C.muted, fontSize: 12, height: 1.4),
                ),
              ),
              const Divider(color: C.line),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_sweep_rounded, color: C.red),
                title: const Text('مسح سجل الفحوصات',
                    style: TextStyle(color: C.text, fontSize: 14.5)),
                onTap: () => _confirm(
                  context,
                  'مسح السجل',
                  'هيتم حذف كل الفحوصات المحفوظة على هذا الجهاز.',
                  () => HistoryStore.instance.clear(),
                  'تم مسح السجل',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restart_alt_rounded, color: C.amber),
                title: const Text('تصفير تقدّم التدريب',
                    style: TextStyle(color: C.text, fontSize: 14.5)),
                onTap: () => _confirm(
                  context,
                  'تصفير التدريب',
                  'هيرجع تقدّمك ورتبتك للصفر.',
                  () => ProgressStore.instance.reset(),
                  'تم التصفير',
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Cobra Shield 1.9 - كل البيانات تبقى على جهازك.',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.muted, fontSize: 11.5),
              ),
            ],
          ),
        );
      },
    );
  }
}
