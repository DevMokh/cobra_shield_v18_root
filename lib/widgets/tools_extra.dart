import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../services/sender_analyzer.dart';
import '../services/url_analyzer.dart';
import 'common.dart';
import 'scan_report.dart';

Widget _title(IconData icon, String title, String sub) {
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
// فحص المرسل
// ---------------------------------------------------------------------------
class SenderTool extends StatefulWidget {
  const SenderTool({super.key});

  @override
  State<SenderTool> createState() => _SenderToolState();
}

class _SenderToolState extends State<SenderTool> {
  final TextEditingController _ctrl = TextEditingController();
  SenderClaim _claim = SenderClaim.bank;
  SenderAnalysis? _res;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _run() {
    FocusScope.of(context).unfocus();
    if (_ctrl.text.trim().isEmpty) {
      toast(context, 'اكتب رقم المرسل أو اسمه');
      return;
    }
    setState(() => _res = SenderAnalyzer.analyze(_ctrl.text, _claim));
  }

  @override
  Widget build(BuildContext context) {
    final r = _res;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(
                Icons.perm_phone_msg_rounded,
                'فحص المرسل',
                'اكتب الرقم أو الاسم اللي جتلك منه الرسالة أو المكالمة، واختار الجهة اللي بيقول إنه منها.',
              ),
              TextField(
                controller: _ctrl,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                keyboardType: TextInputType.text,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(
                    fontFamily: 'monospace', color: C.text, fontSize: 14),
                decoration: fieldDecoration(hint: '01012345678 أو +14155550123 أو اسم'),
              ),
              const SizedBox(height: 12),
              const Text(
                'بيقول إنه منين؟',
                style: TextStyle(color: C.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in SenderClaim.values)
                    ChoiceChip(
                      label: Text(c.label),
                      selected: _claim == c,
                      onSelected: (_) => setState(() => _claim = c),
                      selectedColor: alpha(C.emerald, 0.22),
                      backgroundColor: C.surface2,
                      side: const BorderSide(color: C.line),
                      labelStyle: TextStyle(
                        color: _claim == c ? C.emerald : C.muted,
                        fontSize: 12.5,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _run,
                style: filledButtonStyle(),
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text('افحص المرسل'),
              ),
            ],
          ),
        ),
        if (r != null) ...[
          const SizedBox(height: 14),
          Panel(
            child: Row(
              children: [
                const Icon(Icons.phone_android_rounded, color: C.emerald),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.type.label,
                        style: const TextStyle(
                            color: C.text, fontWeight: FontWeight.w700),
                      ),
                      if (r.normalized.isNotEmpty)
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            r.normalized,
                            style: const TextStyle(
                                color: C.muted,
                                fontFamily: 'monospace',
                                fontSize: 12.5),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${r.result.score}/100',
                  style: TextStyle(
                    color: levelColor(r.result.level),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          FindingsList(findings: r.result.findings, title: 'ليه كده؟'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text(
              'ده مؤشر مش دليل: أسماء المرسل وأرقام المتصل ممكن تتزوّر. القرار الأضمن إنك تتواصل مع الجهة من القناة الرسمية.',
              style: TextStyle(color: C.muted, fontSize: 12, height: 1.5),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// فحص مجمّع
// ---------------------------------------------------------------------------
class _BatchRow {
  _BatchRow(this.input, this.result);
  final String input;
  final ScanResult result;
}

class BatchTool extends StatefulWidget {
  const BatchTool({super.key});

  @override
  State<BatchTool> createState() => _BatchToolState();
}

class _BatchToolState extends State<BatchTool> {
  static const int _max = 30;

  final TextEditingController _ctrl = TextEditingController();
  List<_BatchRow> _rows = <_BatchRow>[];
  bool _done = false;
  int _skipped = 0;

  static final RegExp _split = RegExp('[\\s,;،؛]+');
  static final RegExp _trail = RegExp('[\\.,;:!?)\\]}»"\']+\$');
  static final RegExp _lead = RegExp('^[(\\[{«"\']+');

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
    final seen = <String>{};
    final inputs = <String>[];
    for (var tok in _ctrl.text.split(_split)) {
      tok = tok.replaceAll(_lead, '').replaceAll(_trail, '');
      if (tok.length < 4) continue;
      final low = tok.toLowerCase();
      final looksLink = low.startsWith('http://') ||
          low.startsWith('https://') ||
          low.startsWith('www.') ||
          (tok.contains('.') && !tok.contains('@'));
      if (!looksLink) continue;
      if (seen.add(low)) inputs.add(tok);
    }
    final skipped = inputs.length > _max ? inputs.length - _max : 0;
    final rows = <_BatchRow>[];
    for (final s in inputs.take(_max)) {
      rows.add(_BatchRow(s, UrlAnalyzer.analyze(s)));
    }
    rows.sort((a, b) => b.result.effectiveScore.compareTo(a.result.effectiveScore));
    setState(() {
      _rows = rows;
      _skipped = skipped;
      _done = true;
    });
  }

  String _report() {
    final b = StringBuffer('تقرير فحص مجمّع - Cobra Shield\n\n');
    for (final r in _rows) {
      if (r.result.hasScore) {
        b.writeln('${r.result.effectiveScore}/100 - ${r.result.headline} - ${r.input}');
      } else {
        b.writeln('غير مفحوص (${r.result.headline}) - ${r.input}');
      }
    }
    return b.toString();
  }

  Widget _row(_BatchRow r) {
    final scored = r.result.hasScore;
    final c = scored ? levelColor(r.result.displayLevel) : C.amber;
    final host = r.result.parts?.host ?? r.input;
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
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: alpha(c, 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              scored ? '${r.result.effectiveScore}' : '—',
              style: TextStyle(color: c, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: C.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  r.result.findings.isEmpty
                      ? r.result.headline
                      : '${r.result.headline} - ${r.result.findings.first.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // الحدود من المصدر الموحّد (kBandMedium / kBandHigh) مش أرقام مكتوبة هنا.
    final unchecked = _rows.where((r) => !r.result.hasScore).length;
    final bad = _rows
        .where((r) => r.result.hasScore && r.result.effectiveScore >= kBandHigh)
        .length;
    final mid = _rows
        .where((r) =>
            r.result.hasScore &&
            r.result.effectiveScore >= kBandMedium &&
            r.result.effectiveScore < kBandHigh)
        .length;
    final ok = _rows.length - bad - mid - unchecked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(
                Icons.playlist_add_check_rounded,
                'فحص مجمّع',
                'الصق قائمة روابط (بينها مسافة أو سطر جديد) وهنرتبها من الأخطر للأقل مؤشرات. بحد أقصى $_max رابط. بدون إنترنت.',
              ),
              TextField(
                controller: _ctrl,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                minLines: 4,
                maxLines: 8,
                style: const TextStyle(
                    fontFamily: 'monospace', color: C.text, fontSize: 13),
                decoration: fieldDecoration(hint: 'https://a.com\nhttps://b.xyz/login'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      onPressed: _run,
                      style: filledButtonStyle(),
                      icon: const Icon(Icons.radar_rounded),
                      label: const Text('افحص الكل'),
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
            ],
          ),
        ),
        if (_done && _rows.isEmpty) ...[
          const SizedBox(height: 14),
          const Panel(
            child: Text(
              'لم نجد روابط في النص. اكتب كل رابط في سطر.',
              style: TextStyle(color: C.muted),
            ),
          ),
        ],
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 14),
          Panel(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _count('خطير', bad, C.red),
                _count('مشبوه', mid, C.amber),
                _count('بلا مؤشرات', ok, C.emerald),
                if (unchecked > 0) _count('غير مفحوص', unchecked, C.muted),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._rows.map(_row),
          if (_skipped > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'تم تجاهل $_skipped رابط زيادة عن الحد.',
                style: const TextStyle(color: C.muted, fontSize: 12.5),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _report()));
              if (mounted) toast(context, 'تم نسخ التقرير');
            },
            style: outlineButtonStyle(),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('نسخ التقرير'),
          ),
        ],
      ],
    );
  }

  Widget _count(String label, int n, Color c) {
    return Column(
      children: [
        Text(
          '$n',
          style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 24),
        ),
        Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
      ],
    );
  }
}
