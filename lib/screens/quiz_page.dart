import 'package:flutter/material.dart';

import '../core/scenarios.dart';
import '../core/theme.dart';
import '../services/message_analyzer.dart';
import '../services/progress_store.dart';
import '../services/url_analyzer.dart';
import '../widgets/common.dart';

/// صفحة المرحلة: سؤال تلو الآخر (احتيال أم سليم؟) مع شرح بعد كل إجابة.
class QuizPage extends StatefulWidget {
  const QuizPage({super.key, required this.levelIndex});

  final int levelIndex;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  late int _levelIndex = widget.levelIndex;
  int _i = 0;
  int _correct = 0;
  bool? _picked; // true = قال احتيال، false = قال سليم، null = لم يجب
  int _cobra = 0;
  bool _finished = false;

  TrainLevel get _level => kLevels[_levelIndex];
  Scenario get _sc => _level.scenarios[_i];

  void _answer(bool saysScam) {
    if (_picked != null) return;
    final sc = _sc;
    final score = sc.channel == Channel.link
        ? UrlAnalyzer.analyze(sc.text).score
        : MessageAnalyzer.analyze(sc.text).score;
    setState(() {
      _picked = saysScam;
      _cobra = score;
      if (saysScam == sc.isScam) _correct++;
    });
  }

  Future<void> _next() async {
    if (_i + 1 >= _level.scenarios.length) {
      await ProgressStore.instance.record(_level.id, _correct);
      if (!mounted) return;
      setState(() => _finished = true);
    } else {
      setState(() {
        _i++;
        _picked = null;
      });
    }
  }

  void _restart(int levelIndex) {
    setState(() {
      _levelIndex = levelIndex;
      _i = 0;
      _correct = 0;
      _picked = null;
      _finished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.bg,
        foregroundColor: C.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _level.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(child: _finished ? _result() : _question()),
    );
  }

  // ------------------------------------------------------------------
  Widget _question() {
    final sc = _sc;
    final total = _level.scenarios.length;
    final answered = _picked != null;
    final isLink = sc.channel == Channel.link;
    final rtl = RegExp(r'[\u0600-\u06FF]').hasMatch(sc.text);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Row(
          children: [
            Text(
              'السؤال ${_i + 1} من $total',
              style: const TextStyle(color: C.muted, fontSize: 13),
            ),
            const Spacer(),
            Text(
              'صحيح: $_correct',
              style: const TextStyle(
                color: C.emerald,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: (_i + (answered ? 1 : 0)) / total,
            minHeight: 6,
            color: C.emerald,
            backgroundColor: C.surface2,
          ),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(sc.channel.icon, color: C.emerald, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    sc.channel.label,
                    style: const TextStyle(
                      color: C.emerald,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        sc.sender,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: C.muted, fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(color: C.line, height: 24),
              Directionality(
                textDirection:
                    (isLink || !rtl) ? TextDirection.ltr : TextDirection.rtl,
                child: SelectableText(
                  sc.text,
                  style: TextStyle(
                    color: C.text,
                    fontSize: isLink ? 14 : 15,
                    height: 1.6,
                    fontFamily: isLink ? 'monospace' : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (!answered) ...[
          const Text(
            'إيه رأيك؟',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _answer(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: alpha(C.red, 0.18),
                    foregroundColor: C.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: alpha(C.red, 0.5)),
                    ),
                  ),
                  icon: const Icon(Icons.flag_rounded),
                  label: const Text('احتيال'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _answer(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: alpha(C.emerald, 0.16),
                    foregroundColor: C.emerald,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: alpha(C.emerald, 0.5)),
                    ),
                  ),
                  icon: const Icon(Icons.verified_rounded),
                  label: const Text('سليم'),
                ),
              ),
            ],
          ),
        ] else
          _feedback(sc),
      ],
    );
  }

  Widget _feedback(Scenario sc) {
    final ok = _picked == sc.isScam;
    final c = ok ? C.emerald : C.red;
    final last = _i + 1 >= _level.scenarios.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: alpha(c, 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: alpha(c, 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: c,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ok ? 'إجابة صحيحة' : 'إجابة غير صحيحة',
                    style: TextStyle(
                      color: c,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                sc.isScam ? 'الصحيح: هذا احتيال.' : 'الصحيح: هذا سليم.',
                style: const TextStyle(
                  color: C.text,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                sc.explanation,
                style: const TextStyle(color: C.text, height: 1.6, fontSize: 14),
              ),
              if (sc.clues.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final clue in sc.clues)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: C.surface2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: C.line),
                        ),
                        child: Text(
                          clue,
                          style: const TextStyle(color: C.muted, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'درجة Cobra Shield لنفس النص: $_cobra/100',
                style: const TextStyle(color: C.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _next,
          style: filledButtonStyle(),
          child: Text(last ? 'عرض النتيجة' : 'التالي'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  Widget _result() {
    final total = _level.scenarios.length;
    final stars = starsFor(_correct, total);
    final passed = _correct >= kPassMark;
    final hasNext = _levelIndex + 1 < kLevels.length;
    final c = passed ? C.emerald : C.amber;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 10),
        Icon(_level.icon, size: 64, color: c),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var s = 0; s < 3; s++)
              Icon(
                s < stars ? Icons.star_rounded : Icons.star_border_rounded,
                color: s < stars ? C.amber : C.muted,
                size: 40,
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '$_correct / $total',
          textAlign: TextAlign.center,
          style: TextStyle(color: c, fontSize: 44, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          passed
              ? (_correct == total
                  ? 'ممتاز! إجابات كاملة.'
                  : 'عمل جيد! اجتزت المرحلة.')
              : 'محتاج $kPassMark إجابات صحيحة على الأقل لفتح المرحلة التالية. جرّب تاني.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: C.muted, height: 1.5),
        ),
        const SizedBox(height: 24),
        if (passed && hasNext)
          FilledButton.icon(
            onPressed: () => _restart(_levelIndex + 1),
            style: filledButtonStyle(),
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('المرحلة التالية'),
          ),
        if (passed && hasNext) const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _restart(_levelIndex),
          style: outlineButtonStyle(),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('إعادة المرحلة'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: outlineButtonStyle(),
          child: const Text('رجوع للمراحل'),
        ),
      ],
    );
  }
}
