import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/scenarios.dart';

/// تقدّم التدريب: أفضل نتيجة لكل مرحلة + نقاط الخبرة والرتبة.
class ProgressStore extends ChangeNotifier {
  ProgressStore._();

  static final ProgressStore instance = ProgressStore._();

  final Map<String, int> _best = <String, int>{};

  String _key(String id) => 'cobra.best.$id';

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final l in kLevels) {
        _best[l.id] = p.getInt(_key(l.id)) ?? 0;
      }
      notifyListeners();
    } catch (_) {}
  }

  int best(String id) => _best[id] ?? 0;

  bool unlocked(int index) {
    if (index <= 0) return true;
    return best(kLevels[index - 1].id) >= kPassMark;
  }

  int get xp {
    var total = 0;
    for (final v in _best.values) {
      total += v;
    }
    return total * 10;
  }

  int get maxXp => kTotalQuestions * 10;

  String get rank {
    final r = maxXp == 0 ? 0.0 : xp / maxXp;
    if (r < 0.25) return 'متدرّب';
    if (r < 0.55) return 'حارس';
    if (r < 0.85) return 'صيّاد';
    return 'كوبرا';
  }

  Future<void> record(String id, int correct) async {
    if (correct <= best(id)) return;
    _best[id] = correct;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_key(id), correct);
    } catch (_) {}
  }

  Future<void> reset() async {
    _best.clear();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      for (final l in kLevels) {
        await p.remove(_key(l.id));
      }
    } catch (_) {}
  }
}
