import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'scale_header.dart';

/// صفحة فرعية بزر إغلاق عائم (للشاشات اللي ليها ترويسة كاملة بالفعل).
class BackPage extends StatelessWidget {
  const BackPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          child,
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            left: 12,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: C.text),
              style: IconButton.styleFrom(backgroundColor: alpha(C.bg, 0.6)),
            ),
          ),
        ],
      ),
    );
  }
}

/// صفحة أداة: ترويسة + محتوى، مع زر إغلاق.
class ToolPage extends StatelessWidget {
  const ToolPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return BackPage(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ScaleHeader(title: title, subtitle: subtitle, icon: icon),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
