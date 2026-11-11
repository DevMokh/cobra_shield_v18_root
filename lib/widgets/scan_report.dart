import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../services/strings.dart';
import 'common.dart';
import 'risk_gauge.dart';

/// بطاقة النتيجة: العدّاد + المستوى + النصيحة + زر نسخ التقرير
class ScanSummaryCard extends StatelessWidget {
  const ScanSummaryCard({super.key, required this.result, this.heading});

  final ScanResult result;
  final String? heading;

  @override
  Widget build(BuildContext context) {
    final verdict = result.verdict;
    final Color color;
    switch (verdict) {
      case Verdict.confirmedThreat:
        color = levelColor(RiskLevel.critical);
        break;
      case Verdict.insufficient:
      case Verdict.partialScan:
      case Verdict.invalidInput:
      case Verdict.analysisFailed:
        color = C.amber;
        break;
      case Verdict.suspicious:
      case Verdict.noIndicators:
        color = levelColor(result.displayLevel);
        break;
    }
    // الإدخال غير الصالح وفشل التحليل: مفيش درجة خطر أصلًا، فمش بنرسم عدّاد.
    final showGauge = result.hasScore;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      decoration: BoxDecoration(
        color: C.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: alpha(color, 0.5)),
        boxShadow: [BoxShadow(color: alpha(color, 0.12), blurRadius: 28)],
      ),
      child: Column(
        children: [
          if (heading != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                heading!,
                style: const TextStyle(color: C.muted, fontSize: 13),
              ),
            ),
          if (showGauge) ...[
            RiskGauge(score: result.effectiveScore, color: color),
            const SizedBox(height: 10),
          ] else ...[
            Icon(
              verdict == Verdict.invalidInput
                  ? Icons.link_off_rounded
                  : Icons.error_outline_rounded,
              color: color,
              size: 44,
            ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: alpha(color, 0.15),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: alpha(color, 0.5)),
            ),
            child: Text(
              tr(verdictLabelKey(result)),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tr(verdictAdviceKey(result)),
            textAlign: TextAlign.center,
            style: const TextStyle(color: C.muted, height: 1.5, fontSize: 13.5),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: result.toReport()));
              if (context.mounted) toast(context, 'تم نسخ التقرير');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(tr(S.copyReport)),
            style: TextButton.styleFrom(foregroundColor: C.emerald),
          ),
        ],
      ),
    );
  }
}

/// عنصر نتيجة واحد (سبب + شرح + نقاط)
class FindingTile extends StatelessWidget {
  const FindingTile({super.key, required this.finding});

  final Finding finding;

  @override
  Widget build(BuildContext context) {
    final c = severityColor(finding.severity);
    final pts = finding.points;
    final badge = pts > 0 ? '+$pts' : (pts < 0 ? '$pts' : '');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          color: C.surface,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: c),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(severityIcon(finding.severity), color: c, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                finding.title,
                                style: const TextStyle(
                                  color: C.text,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                finding.detail,
                                style: const TextStyle(
                                  color: C.muted,
                                  fontSize: 12.5,
                                  height: 1.45,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (badge.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: alpha(c, 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                color: c,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FindingsList extends StatelessWidget {
  const FindingsList({super.key, required this.findings, this.title});

  final List<Finding> findings;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title ?? 'تفاصيل التحليل (${findings.length})'),
        ...findings.map((f) => FindingTile(finding: f)),
      ],
    );
  }
}

/// تفكيك الرابط إلى أجزاءه
class UrlBreakdown extends StatelessWidget {
  const UrlBreakdown({super.key, required this.parts});

  final UrlParts parts;

  Widget _row(String k, String v) {
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(k, style: const TextStyle(color: C.muted, fontSize: 12.5)),
          ),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                v,
                style: const TextStyle(
                  color: C.text,
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'تفكيك الرابط',
            style: TextStyle(color: C.text, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _row('البروتوكول', parts.scheme),
          // المضيف الكامل (Hostname) والدومين المسجّل (Registrable Domain) حقلين منفصلين.
          _row('المضيف الكامل', parts.host),
          if (parts.unicodeHost.isNotEmpty && parts.unicodeHost != parts.host)
            _row('المضيف (Unicode)', parts.unicodeHost),
          _row('الدومين المسجّل', parts.registrableDomain),
          _row('اللاحقة العامة', parts.publicSuffix),
          _row('المنفذ', parts.port),
          _row('المسار', parts.path),
          _row('الاستعلام', parts.query),
        ],
      ),
    );
  }
}
