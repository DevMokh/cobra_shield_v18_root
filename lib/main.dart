import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/theme.dart';
import 'services/history_store.dart';
import 'services/progress_store.dart';
import 'services/settings_store.dart';
import 'services/threat_feed.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.surface,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Future.wait<void>(<Future<void>>[
    HistoryStore.instance.load(),
    SettingsStore.instance.load(),
    ProgressStore.instance.load(),
    ThreatFeed.instance.load(),
  ]);
  runApp(const CobraShieldApp());
}