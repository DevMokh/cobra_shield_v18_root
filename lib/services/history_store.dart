import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

/// سجل الفحوصات المحلي. لا يحفظ نص الرسائل نهائيًا (حماية للخصوصية)،
/// فقط العنوان المختصر والدرجة والوقت.
class HistoryStore extends ChangeNotifier {
  HistoryStore._();

  static final HistoryStore instance = HistoryStore._();
  static const String _key = 'cobra.history.v1';
  static const int _max = 100;

  final List<HistoryItem> _items = <HistoryItem>[];
  List<HistoryItem> get items => List<HistoryItem>.unmodifiable(_items);

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _items.clear();
      for (final e in list) {
        _items.add(HistoryItem.fromJson(Map<String, dynamic>.from(e as Map)));
      }
      notifyListeners();
    } catch (_) {
      // بيانات تالفة: نبدأ بسجل فارغ
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _key,
        jsonEncode(_items.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> add(HistoryItem item) async {
    _items.insert(0, item);
    if (_items.length > _max) {
      _items.removeRange(_max, _items.length);
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(int id) async {
    _items.removeWhere((e) => e.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    await _save();
  }
}
