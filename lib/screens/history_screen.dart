import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../services/history_store.dart';
import '../services/strings.dart';
import '../widgets/common.dart';
import '../widgets/scale_header.dart';
import '../widgets/stats_card.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface2,
        title: const Text('مسح السجل'),
        content: const Text('هيتم حذف كل الفحوصات المحفوظة على هذا الجهاز.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: C.red),
            child: const Text('امسح'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await HistoryStore.instance.clear();
    }
  }

  Future<void> _export(List<HistoryItem> items) async {
    final b = StringBuffer('سجل فحوصات Cobra Shield\n\n');
    for (final it in items) {
      b.writeln(
        '${fmtTime(it.time)} - ${it.kind == ScanKind.url ? 'رابط' : 'رسالة'} - '
        '${it.score}/100 (${it.level.label}) - ${it.title}',
      );
    }
    b.writeln('\nملاحظة: الدرجات تقديرية محليًا ولا تغني عن الحذر.');
    await SharePlus.instance.share(
      ShareParams(text: b.toString(), subject: 'سجل فحوصات Cobra Shield'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HistoryStore.instance,
      builder: (context, _) {
        final items = HistoryStore.instance.items;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            ScaleHeader(
              title: tr(S.historyTitle),
              subtitle: tr(S.historySubtitle),
              icon: Icons.history_rounded,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (items.isEmpty)
                    const Panel(
                      padding: EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                      child: Column(
                        children: [
                          Icon(Icons.inbox_rounded, color: C.muted, size: 40),
                          SizedBox(height: 10),
                          Text(
                            'لا توجد فحوصات بعد',
                            style: TextStyle(color: C.muted),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    StatsCard(items: items),
                    const SizedBox(height: 12),
                    SectionTitle(
                      '${items.length} فحص',
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: () => _export(items),
                            icon: const Icon(Icons.ios_share_rounded, size: 18),
                            label: const Text('تصدير'),
                            style: TextButton.styleFrom(foregroundColor: C.emerald),
                          ),
                          TextButton.icon(
                            onPressed: () => _confirmClear(context),
                            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                            label: const Text('مسح الكل'),
                            style: TextButton.styleFrom(foregroundColor: C.red),
                          ),
                        ],
                      ),
                    ),
                    ...items.map((it) => _tile(it)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _tile(HistoryItem it) {
    final c = levelColor(it.level);
    return Dismissible(
      key: ValueKey<int>(it.id),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => HistoryStore.instance.remove(it.id),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: alpha(C.red, 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.delete_rounded, color: C.red),
      ),
      child: Container(
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
                '${it.score}',
                style: TextStyle(color: c, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Directionality(
                    textDirection: it.kind == ScanKind.url
                        ? TextDirection.ltr
                        : TextDirection.rtl,
                    child: Text(
                      it.title,
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
                    '${it.kind == ScanKind.url ? 'رابط' : 'رسالة'} - ${it.level.label} - ${fmtTime(it.time)}',
                    style: const TextStyle(color: C.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
