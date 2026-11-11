import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/theme.dart';
import 'common.dart';

/// ملخص إحصائي بسيط لكل الفحوصات المحفوظة على الجهاز.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.items});

  final List<HistoryItem> items;

  @override
  Widget build(BuildContext context) {
    var low = 0;
    var mid = 0;
    var high = 0;
    var urls = 0;
    var msgs = 0;
    for (final it in items) {
      switch (it.level) {
        case RiskLevel.low:
          low++;
          break;
        case RiskLevel.medium:
          mid++;
          break;
        case RiskLevel.high:
        case RiskLevel.critical:
          high++;
          break;
      }
      if (it.kind == ScanKind.url) {
        urls++;
      } else {
        msgs++;
      }
    }
    final total = items.length;
    final blocked = high + mid;

    Widget bar(Color c, int n) {
      if (n == 0) return const SizedBox.shrink();
      return Expanded(
        flex: n,
        child: Container(height: 10, color: c),
      );
    }

    Widget stat(String label, int n, Color c) {
      return Expanded(
        child: Column(
          children: [
            Text(
              '$n',
              style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 22),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: C.muted, fontSize: 12)),
          ],
        ),
      );
    }

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_moon_rounded, color: C.emerald, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  blocked == 0
                      ? 'فحصت $total ولا حاجة مريبة'
                      : 'كشفت $blocked حاجة مريبة من أصل $total',
                  style: const TextStyle(
                    color: C.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                bar(C.emerald, low),
                bar(C.amber, mid),
                bar(C.red, high),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              stat('نظيف', low, C.emerald),
              stat('مشبوه', mid, C.amber),
              stat('خطير', high, C.red),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'روابط: $urls - رسائل: $msgs',
            textAlign: TextAlign.center,
            style: const TextStyle(color: C.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
