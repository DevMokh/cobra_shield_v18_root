import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../services/history_store.dart';
import '../services/inbox.dart';
import '../services/message_analyzer.dart';
import '../services/strings.dart';
import '../widgets/common.dart';
import '../widgets/scale_header.dart';
import '../widgets/scan_report.dart';
import 'image_scan_screen.dart';

// أمثلة للتجربة (دومينات وهمية)
const List<MapEntry<String, String>> _samples = <MapEntry<String, String>>[
  MapEntry<String, String>(
    'مثال: إيقاف حساب',
    'عاجل: تم إيقاف حسابك البنكي بسبب نشاط مشبوه. سجّل الدخول خلال 24 ساعة وأدخل كود التحقق لتجنب الحظر: http://nbe-secure-login.top/verify',
  ),
  MapEntry<String, String>(
    'مثال: جائزة',
    'مبروك! فزت بجائزة 50,000 جنيه. اضغط هنا لاستلامها الآن: bit.ly/3xYz12',
  ),
  MapEntry<String, String>(
    'مثال: كود رسمي',
    'كود التحقق الخاص بك 482913. لا تشاركه مع أي شخص.',
  ),
];

class MessageScanScreen extends StatefulWidget {
  const MessageScanScreen({super.key});

  @override
  State<MessageScanScreen> createState() => _MessageScanScreenState();
}

class _MessageScanScreenState extends State<MessageScanScreen> {
  final TextEditingController _ctrl = TextEditingController();
  ScanResult? _result;

  @override
  void initState() {
    super.initState();
    Inbox.toMessage.addListener(_onInbox);
  }

  @override
  void dispose() {
    Inbox.toMessage.removeListener(_onInbox);
    _ctrl.dispose();
    super.dispose();
  }

  // نص جاي من المشاركة أو تحديد النص
  void _onInbox() {
    final inc = Inbox.toMessage.value;
    if (inc == null || !mounted) return;
    _ctrl.text = inc.text;
    _scan();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text?.trim();
    if (t == null || t.isEmpty) {
      if (mounted) toast(context, 'الحافظة فاضية');
      return;
    }
    _ctrl.text = t;
    _scan();
  }

  void _clear() {
    _ctrl.clear();
    setState(() => _result = null);
  }

  void _scan() {
    FocusScope.of(context).unfocus();
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      toast(context, 'الصق نص الرسالة أولًا');
      return;
    }
    final r = MessageAnalyzer.analyze(text);
    setState(() => _result = r);
    if (!r.hasScore) return; // مفيش درجة (إدخال غير صالح/فشل): مش بيتسجّل
    final n = r.links.length;
    HistoryStore.instance.add(HistoryItem(
      id: DateTime.now().microsecondsSinceEpoch,
      kind: ScanKind.message,
      title: n > 0
          ? 'رسالة (${text.length} حرف) - $n رابط'
          : 'رسالة (${text.length} حرف)',
      score: r.effectiveScore,
      time: DateTime.now(),
    ));
  }

  Widget _inputPanel() {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            minLines: 5,
            maxLines: 9,
            style: const TextStyle(color: C.text, fontSize: 14.5, height: 1.5),
            decoration: fieldDecoration(
              hint: 'الصق نص الرسالة المشبوهة هنا (SMS / واتساب / إيميل)...',
              suffix: IconButton(
                icon: const Icon(Icons.close_rounded, color: C.muted),
                onPressed: _clear,
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in _samples)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ActionChip(
                      label: Text(s.key, style: const TextStyle(fontSize: 12)),
                      backgroundColor: C.surface2,
                      side: const BorderSide(color: C.line),
                      onPressed: () {
                        _ctrl.text = s.value;
                        _scan();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton.icon(
                  onPressed: _scan,
                  style: filledButtonStyle(),
                  icon: const Icon(Icons.mark_email_unread_rounded),
                  label: const Text('حلّل الرسالة'),
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
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ImageScanScreen()),
              );
            },
            style: outlineButtonStyle(),
            icon: const Icon(Icons.image_search_rounded, size: 20),
            label: const Text('افحص من صورة (سكرين شوت)'),
          ),
          const SizedBox(height: 8),
          const Text(
            'التحليل محلي بالكامل ولا يُحفظ نص الرسالة في السجل.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _linkCard(ScanResult l) {
    // رابط ما اتفحصش (غير صالح/فشل): بدون درجة، بلون التنبيه.
    final c = l.hasScore ? levelColor(l.level) : C.amber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: alpha(c, 0.4)),
        ),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: C.muted,
          collapsedIconColor: C.muted,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          title: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              l.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: C.text,
                fontFamily: 'monospace',
                fontSize: 12.5,
              ),
            ),
          ),
          subtitle: Text(
            l.hasScore ? '${l.score}/100 - ${l.level.label}' : l.headline,
            style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          children: l.findings.map((f) => FindingTile(finding: f)).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        ScaleHeader(
          title: tr(S.msgTitle),
          subtitle: tr(S.msgSubtitle),
          icon: Icons.mark_email_read_rounded,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _inputPanel(),
              if (r != null) ...[
                const SizedBox(height: 16),
                ScanSummaryCard(result: r),
                const SizedBox(height: 14),
                FindingsList(findings: r.findings),
                if (r.links.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SectionTitle('الروابط داخل الرسالة (${r.links.length})'),
                  ...r.links.map(_linkCard),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'لا تفتح هذه الروابط من الرسالة. لو كنت تتوقع الرسالة، ادخل الموقع أو التطبيق الرسمي بنفسك.',
                      style: TextStyle(color: C.muted, fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
