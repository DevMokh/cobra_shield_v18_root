import 'package:flutter/material.dart';

import '../core/scenarios.dart';
import '../core/theme.dart';
import '../services/progress_store.dart';
import '../services/strings.dart';
import '../widgets/common.dart';
import '../widgets/scale_header.dart';
import 'learn_screen.dart';
import 'quiz_page.dart';

class TrainScreen extends StatelessWidget {
  const TrainScreen({super.key});

  Widget _rankCard(ProgressStore ps) {
    final ratio = ps.maxXp == 0 ? 0.0 : ps.xp / ps.maxXp;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: alpha(C.emerald, 0.4)),
        boxShadow: [BoxShadow(color: alpha(C.emerald, 0.08), blurRadius: 24)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: alpha(C.emerald, 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.military_tech_rounded, color: C.emerald),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'رتبتك',
                      style: TextStyle(color: C.muted, fontSize: 12.5),
                    ),
                    Text(
                      ps.rank,
                      style: const TextStyle(
                        color: C.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${ps.xp} / ${ps.maxXp} XP',
                style: const TextStyle(
                  color: C.emerald,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              color: C.emerald,
              backgroundColor: C.surface2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelCard(BuildContext context, ProgressStore ps, int i) {
    final level = kLevels[i];
    final unlocked = ps.unlocked(i);
    final best = ps.best(level.id);
    final stars = starsFor(best, level.scenarios.length);
    final c = unlocked ? C.emerald : C.muted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (!unlocked) {
            toast(context,
                'أنجز المرحلة السابقة بـ $kPassMark إجابات صحيحة على الأقل');
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => QuizPage(levelIndex: i)),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: unlocked ? alpha(C.emerald, 0.35) : C.line),
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: alpha(c, 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(unlocked ? level.icon : Icons.lock_rounded, color: c),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level.title,
                      style: TextStyle(
                        color: unlocked ? C.text : C.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      level.subtitle,
                      style: const TextStyle(color: C.muted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (var s = 0; s < 3; s++)
                          Icon(
                            s < stars
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 20,
                            color: s < stars ? C.amber : C.muted,
                          ),
                        const SizedBox(width: 8),
                        Text(
                          'أفضل: $best/${level.scenarios.length}',
                          style: const TextStyle(color: C.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                unlocked ? Icons.chevron_left_rounded : Icons.lock_outline_rounded,
                color: C.muted,
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
      listenable: ProgressStore.instance,
      builder: (context, _) {
        final ps = ProgressStore.instance;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ScaleHeader(
              title: tr(S.trainTitle),
              subtitle: tr(S.trainSubtitle),
              icon: Icons.sports_esports_rounded,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _rankCard(ps),
                  const SizedBox(height: 14),
                  const SectionTitle('المراحل'),
                  for (var i = 0; i < kLevels.length; i++)
                    _levelCard(context, ps, i),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => const LearnPage()),
                    ),
                    style: outlineButtonStyle(),
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: const Text('اقرأ الدروس أولًا'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
