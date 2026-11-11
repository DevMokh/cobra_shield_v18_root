import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/online_intel.dart';

/// صف نتيجة مصدر تهديدات واحد
class IntelTile extends StatelessWidget {
  const IntelTile({super.key, required this.result});

  final IntelResult result;

  Color get _color {
    switch (result.status) {
      case IntelStatus.clean:
        return C.emerald;
      case IntelStatus.hit:
        return C.red;
      case IntelStatus.info:
        return C.muted;
      case IntelStatus.skipped:
        return C.muted;
      case IntelStatus.notConfigured:
        return C.muted;
      case IntelStatus.error:
        return C.amber;
    }
  }

  IconData get _icon {
    switch (result.status) {
      case IntelStatus.clean:
        return Icons.check_circle_rounded;
      case IntelStatus.hit:
        return Icons.dangerous_rounded;
      case IntelStatus.info:
        return Icons.info_rounded;
      case IntelStatus.skipped:
        return Icons.remove_circle_outline_rounded;
      case IntelStatus.notConfigured:
        return Icons.settings_rounded;
      case IntelStatus.error:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: C.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: alpha(c, 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: c, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.source,
                  style: const TextStyle(
                    color: C.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  result.message,
                  style: const TextStyle(color: C.muted, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// سلسلة التحويلات
class ChainView extends StatelessWidget {
  const ChainView({super.key, required this.chain});

  final List<String> chain;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < chain.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: alpha(C.emerald, 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: C.emerald, fontSize: 11),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(
                      chain[i],
                      style: const TextStyle(
                        color: C.text,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
