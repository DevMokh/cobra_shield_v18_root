import 'package:flutter/material.dart';

import 'models.dart';

/// ألوان Cobra Shield: أسود مخضرّ + زمرّدي. الأحمر محجوز لمستوى الخطر فقط.
class C {
  C._();

  static const Color bg = Color(0xFF060C0A);
  static const Color surface = Color(0xFF0D1613);
  static const Color surface2 = Color(0xFF14201B);
  static const Color line = Color(0xFF1F3029);
  static const Color emerald = Color(0xFF2EE59D);
  static const Color amber = Color(0xFFFFC857);
  static const Color orange = Color(0xFFFF8A3D);
  static const Color red = Color(0xFFFF4D5E);
  static const Color text = Color(0xFFE6F2EC);
  static const Color muted = Color(0xFF8FA69B);
  static const Color onAccent = Color(0xFF03130C);
}

/// لون بشفافية (بدون withOpacity لتفادي اختلاف نسخ Flutter)
Color alpha(Color c, double o) => c.withAlpha((o * 255).round());

Color levelColor(RiskLevel l) {
  switch (l) {
    case RiskLevel.low:
      return C.emerald;
    case RiskLevel.medium:
      return C.amber;
    case RiskLevel.high:
      return C.orange;
    case RiskLevel.critical:
      return C.red;
  }
}

Color severityColor(Severity s) {
  switch (s) {
    case Severity.good:
      return C.emerald;
    case Severity.info:
      return C.muted;
    case Severity.warn:
      return C.amber;
    case Severity.danger:
      return C.red;
  }
}

IconData severityIcon(Severity s) {
  switch (s) {
    case Severity.good:
      return Icons.check_circle_rounded;
    case Severity.info:
      return Icons.info_rounded;
    case Severity.warn:
      return Icons.warning_amber_rounded;
    case Severity.danger:
      return Icons.dangerous_rounded;
  }
}

String fmtTime(DateTime t) {
  String two(int n) => n < 10 ? '0$n' : '$n';
  return '${t.day}/${t.month}  ${two(t.hour)}:${two(t.minute)}';
}

ThemeData buildTheme() {
  final base = ColorScheme.fromSeed(
    seedColor: C.emerald,
    brightness: Brightness.dark,
  );
  final scheme = base.copyWith(
    primary: C.emerald,
    onPrimary: C.onAccent,
    secondary: C.amber,
    surface: C.surface,
    onSurface: C.text,
    error: C.red,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      indicatorColor: alpha(C.emerald, 0.18),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.surface2,
      contentTextStyle: TextStyle(color: C.text),
    ),
  );
}
