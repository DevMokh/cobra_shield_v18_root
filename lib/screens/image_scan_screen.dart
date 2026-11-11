import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../services/history_store.dart';
import '../services/message_analyzer.dart';
import '../services/ocr_service.dart';
import '../services/ocr_text.dart';
import '../widgets/common.dart';
import '../widgets/scan_report.dart';

/// فحص رسالة من صورة (سكرين شوت): استخراج النص بالكاميرا/المعرض محليًا،
/// ثم إتاحة تعديله قبل تحليله - لأن القراءة الآلية ممكن تخطئ (راجع OcrService).
class ImageScanScreen extends StatefulWidget {
  const ImageScanScreen({super.key});

  @override
  State<ImageScanScreen> createState() => _ImageScanScreenState();
}

class _ImageScanScreenState extends State<ImageScanScreen> {
  final TextEditingController _ctrl = TextEditingController();
  File? _image;
  bool _busy = false;
  ScanResult? _result;
  OcrOutcome? _ocr;
  bool _ocrFailed = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    try {
      final XFile? x = await ImagePicker().pickImage(
        source: src,
        maxWidth: 2000,
        imageQuality: 92,
      );
      if (x == null || !mounted) return;
      setState(() {
        _image = File(x.path);
        _busy = true;
        _result = null;
        _ocr = null;
        _ocrFailed = false;
      });
      OcrOutcome? outcome;
      try {
        outcome = await OcrService.extract(x.path);
      } catch (_) {
        outcome = null;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ocr = outcome;
        _ocrFailed = outcome == null;
        _ctrl.text = outcome?.text ?? '';
      });
      if (outcome == null) {
        toast(context, 'فشلت قراءة الصورة. ده مش معناه إنها آمنة. اكتب النص يدويًا.');
      } else if (outcome.quality == OcrQuality.empty) {
        toast(context, 'ما قدرناش نقرأ نص واضح من الصورة. اكتب النص يدويًا.');
      } else if (outcome.quality == OcrQuality.low) {
        toast(context, 'جودة القراءة منخفضة. راجع النص وصحّحه قبل الفحص.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, 'تعذر فتح الكاميرا أو المعرض.');
    }
  }

  void _scan() {
    FocusScope.of(context).unfocus();
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      toast(context, 'مفيش نص للفحص. اكتب أو استخرج من صورة أولًا');
      return;
    }
    final r = MessageAnalyzer.analyze(text, partialReason: _partialReason(text));
    setState(() => _result = r);
    if (!r.hasScore) return;
    HistoryStore.instance.add(HistoryItem(
      id: DateTime.now().microsecondsSinceEpoch,
      kind: ScanKind.message,
      title: 'من صورة (${text.length} حرف)',
      score: r.effectiveScore,
      time: DateTime.now(),
    ));
  }

  /// لو النص لسه زي ما استخرجه المحرك (المستخدم ما عدّلوش) وفيه سبب يخلّي القراءة ناقصة،
  /// بنرجّع السبب عشان التحليل يتعامل معاه كفحص جزئي. لو المستخدم عدّل النص فهو راجعه بنفسه.
  String? _partialReason(String text) {
    final o = _ocr;
    if (o == null || text.trim() != o.text.trim()) return null;
    if (!o.readsArabic) {
      return 'النص اتقرا بمحرك لاتيني فقط: أي كلام عربي في الصورة ممكن ما يكونش اتقرا، فالنتيجة قد لا تغطي الرسالة كلها.';
    }
    if (o.quality == OcrQuality.low) {
      return 'جودة قراءة الصورة منخفضة: النص ممكن يكون فيه أخطاء أو نقص، فالنتيجة قد لا تغطي الرسالة كلها.';
    }
    return null;
  }

  /// رسالة الحالة: بتقول للمستخدم الحقيقة عن المحرك اللي قرأ النص.
  Widget _ocrNotice() {
    final OcrOutcome? o = _ocr;
    String text;
    Color color = C.amber;
    if (_ocrFailed) {
      text =
          'فشلت قراءة الصورة. ده مش معناه إنها آمنة: اكتب النص يدويًا في الخانة تحت وافحصه.';
      color = C.red;
    } else if (o == null) {
      text =
          'القراءة بتتم على جهازك بالكامل (عربي + إنجليزي). قراءة العربي تجريبية ودقتها بتعتمد على وضوح الصورة وحجم الخط، فراجع النص قبل الفحص.';
    } else if (o.quality == OcrQuality.empty) {
      text =
          'ما لقيناش نص واضح في الصورة. جرّب صورة أوضح أو اكتب النص يدويًا. غياب النص المقروء مش معناه إن الصورة آمنة.';
    } else if (o.readsArabic && o.quality == OcrQuality.low) {
      text =
          'جودة القراءة منخفضة${o.confidence != null ? ' (ثقة المحرك ${o.confidence}%)' : ''}: على الأغلب فيه كلمات غلط أو ناقصة. صحّح النص يدويًا قبل الفحص، ولو تركته كما هو هتتعامل النتيجة كفحص جزئي.';
      color = C.amber;
    } else if (o.readsArabic) {
      text =
          'اتقرأ النص على جهازك بمحرك يدعم العربي والإنجليزي${o.invertedPass ? ' (بعد عكس ألوان الصورة الداكنة)' : ''}. القراءة الآلية ممكن تخطئ (خصوصًا في الروابط والحروف المتشابهة)، فراجعه قبل الفحص.';
      color = C.muted;
    } else {
      text =
          'محرك قراءة العربي مش متاح دلوقتي، فاتقرا الإنجليزي والأرقام والروابط بس. أي كلام عربي في الصورة ممكن يكون ناقص: كمّله يدويًا قبل الفحص.';
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: alpha(color, 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: alpha(color, 0.35)),
      ),
      child: Text(
        text,
        style: const TextStyle(color: C.muted, fontSize: 12, height: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: C.bg,
        foregroundColor: C.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'فحص من صورة',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.image_search_rounded, color: C.emerald, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'استخرج نص من سكرين شوت للرسالة، راجعه، ثم افحصه.',
                          style: TextStyle(color: C.text, fontSize: 13, height: 1.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _ocrNotice(),
                  const SizedBox(height: 12),
                  if (_image != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(_image!, height: 160, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                          style: outlineButtonStyle(),
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
                          label: const Text('من المعرض'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _pick(ImageSource.camera),
                          style: outlineButtonStyle(),
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: const Text('صوّر الآن'),
                        ),
                      ),
                    ],
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: C.emerald),
                        ),
                        SizedBox(width: 10),
                        Text('جارٍ قراءة النص...', style: TextStyle(color: C.muted, fontSize: 12.5)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ctrl,
                    minLines: 5,
                    maxLines: 9,
                    style: const TextStyle(color: C.text, fontSize: 14, height: 1.5),
                    decoration: fieldDecoration(
                      hint: 'النص المستخرج هيظهر هنا. راجعه قبل الفحص...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _scan,
                    style: filledButtonStyle(),
                    icon: const Icon(Icons.radar_rounded),
                    label: const Text('افحص النص'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'الصورة والنص لا يغادران جهازك. لا يُحفظ نص الرسالة في السجل.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: C.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (r != null) ...[
              const SizedBox(height: 16),
              ScanSummaryCard(result: r),
              const SizedBox(height: 14),
              FindingsList(findings: r.findings),
              if (r.links.isNotEmpty) ...[
                const SizedBox(height: 6),
                SectionTitle('الروابط داخل النص (${r.links.length})'),
                for (final l in r.links)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: C.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: alpha(l.hasScore ? levelColor(l.level) : C.amber, 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Directionality(
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
                          ),
                          Text(
                            l.hasScore ? '${l.score}/100' : l.headline,
                            style: TextStyle(
                              color: l.hasScore ? levelColor(l.level) : C.amber,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
