import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// Трафик через VPN по дням (хранится на устройстве, только числа).
class TrafficLog {
  static const _key = 'trafficLog';
  static const _keepDays = 400;

  /// «2026-10-29» → (отдано, получено) в байтах.
  final Map<String, (int, int)> days = {};

  SharedPreferences? _prefs;
  int _lastUp = 0, _lastDown = 0;
  bool _dirty = false;
  DateTime _savedAt = DateTime.now();

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void load(SharedPreferences prefs) {
    _prefs = prefs;
    days.clear();
    try {
      final j = jsonDecode(prefs.getString(_key) ?? '{}') as Map<String, dynamic>;
      j.forEach((k, v) {
        if (v is List && v.length == 2) {
          days[k] = ((v[0] as num).toInt(), (v[1] as num).toInt());
        }
      });
    } catch (_) {}
  }

  /// Новые показания счётчиков ядра (накопительные за сессию).
  void onStats(ConnStats s, {DateTime? now}) {
    // Счётчик сбросился — новая сессия или перезапуск ядра.
    if (s.upload < _lastUp || s.download < _lastDown) {
      _lastUp = 0;
      _lastDown = 0;
    }
    final du = s.upload - _lastUp, dd = s.download - _lastDown;
    _lastUp = s.upload;
    _lastDown = s.download;
    if (du <= 0 && dd <= 0) return;
    final k = dayKey(now ?? DateTime.now());
    final cur = days[k] ?? (0, 0);
    days[k] = (cur.$1 + du, cur.$2 + dd);
    _dirty = true;
    if (DateTime.now().difference(_savedAt).inSeconds >= 60) save();
  }

  /// Соединение закрыто: следующая сессия считается с нуля.
  void sessionEnded() {
    _lastUp = 0;
    _lastDown = 0;
    save();
  }

  void save() {
    if (!_dirty || _prefs == null) return;
    _dirty = false;
    _savedAt = DateTime.now();
    if (days.length > _keepDays) {
      final keys = days.keys.toList()..sort();
      for (final k in keys.take(days.length - _keepDays)) {
        days.remove(k);
      }
    }
    _prefs!.setString(_key,
        jsonEncode(days.map((k, v) => MapEntry(k, [v.$1, v.$2]))));
  }

  void clear() {
    days.clear();
    _dirty = true;
    save();
  }

  /// Сумма за дни, ключ которых начинается с [prefix] («2026-10»).
  int total(String prefix) => days.entries
      .where((e) => e.key.startsWith(prefix))
      .fold(0, (a, e) => a + e.value.$1 + e.value.$2);

  /// Последние [n] дней, от старых к новым: (дата, отдано, получено).
  List<(DateTime, int, int)> lastDays(int n, {DateTime? now}) {
    final today = now ?? DateTime.now();
    return [
      for (var i = n - 1; i >= 0; i--)
        () {
          final d = DateTime(today.year, today.month, today.day - i);
          final v = days[dayKey(d)] ?? (0, 0);
          return (d, v.$1, v.$2);
        }(),
    ];
  }
}
