import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme.dart';

/// شاشة الكاميرا لقراءة رمز QR. ترجع (pop) بالنص المقروء، أو null لو أُغلقت.
/// القراءة كلها على الجهاز ولا يُرسل شيء.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        _done = true;
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(v);
        return;
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (mounted) setState(() => _torch = !_torch);
    } catch (_) {
      // الجهاز بدون فلاش
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // إطار التصويب
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: C.emerald, width: 3),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton.filled(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: alpha(Colors.black, 0.55),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const Spacer(),
                  IconButton.filled(
                    onPressed: _toggleTorch,
                    style: IconButton.styleFrom(
                      backgroundColor: alpha(Colors.black, 0.55),
                      foregroundColor: _torch ? C.amber : Colors.white,
                    ),
                    icon: Icon(
                      _torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(20),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: alpha(Colors.black, 0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'وجّه الكاميرا ناحية رمز QR. هنفحصه قبل ما تفتحه.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, height: 1.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
