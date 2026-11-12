import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// PIN-код на вход в Nexus. Хранится только «отпечаток» (PBKDF2-SHA256
/// с солью), сам код нигде не сохраняется.
class Pin {
  static const _iterations = 120000;

  static Future<String> hash(String pin) async {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final h = await _derive(pin, salt, _iterations);
    return 'p1\$$_iterations\$${base64Encode(salt)}\$${base64Encode(h)}';
  }

  static Future<bool> verify(String pin, String stored) async {
    final p = stored.split('\$');
    if (p.length != 4 || p[0] != 'p1') return false;
    final it = int.tryParse(p[1]) ?? 0;
    if (it < 10000 || it > 2000000) return false;
    try {
      final h = await _derive(pin, base64Decode(p[2]), it);
      final want = base64Decode(p[3]);
      if (h.length != want.length) return false;
      var diff = 0;
      for (var i = 0; i < h.length; i++) {
        diff |= h[i] ^ want[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  /// Считается в отдельном потоке: на телефоне это около секунды,
  /// и в основном потоке экран ввода PIN на это время замирал бы.
  static Future<List<int>> _derive(String pin, List<int> salt, int it) =>
      Isolate.run(() => _deriveNow(pin, List<int>.of(salt), it));

  static Future<List<int>> _deriveNow(String pin, List<int> salt, int it) async {
    final k = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: it,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
    return k.extractBytes();
  }

  /// Пауза после неудачных попыток: 5 ошибок — 30 с, дальше дольше.
  static Duration delayAfter(int fails) {
    if (fails < 5) return Duration.zero;
    final s = 30 * (1 << ((fails - 5) ~/ 3).clamp(0, 5));
    return Duration(seconds: s);
  }
}

/// Счётчик неудачных попыток PIN и пауза после них. Состояние хранится
/// строкой через [read]/[write] (в приложении — SharedPreferences), чтобы
/// паузу нельзя было обойти перезапуском Nexus.
class PinGuard {
  PinGuard({required this.read, required this.write, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final String? Function() read;
  final void Function(String) write;
  final DateTime Function() _now;

  int fails = 0;
  DateTime? blockedUntil;

  bool get blocked => blockedUntil != null && _now().isBefore(blockedUntil!);

  void load() {
    try {
      final j = jsonDecode(read() ?? '{}') as Map;
      fails = (j['fails'] as num?)?.toInt() ?? 0;
      final u = (j['until'] as num?)?.toInt();
      blockedUntil = u == null ? null : DateTime.fromMillisecondsSinceEpoch(u);
      // Часы перевели назад, чтобы снять паузу, — не даём: пауза не
      // бывает дольше максимальной.
      if (blockedUntil != null &&
          blockedUntil!.difference(_now()) > const Duration(hours: 1)) {
        blockedUntil = _now().add(Pin.delayAfter(fails));
      }
    } catch (_) {}
  }

  void _store(int f, DateTime? until) => write(jsonEncode({
        'fails': f,
        'until': until?.millisecondsSinceEpoch,
      }));

  /// Проверяет [pin] против [stored]. Попытка засчитывается до проверки:
  /// закрыв Nexus во время проверки, её не «отменить».
  Future<bool> attempt(String pin, String stored) async {
    if (blocked) return false;
    final f = fails + 1;
    final d = Pin.delayAfter(f);
    final until = d == Duration.zero ? null : _now().add(d);
    _store(f, until);
    if (await Pin.verify(pin, stored)) {
      reset();
      return true;
    }
    fails = f;
    blockedUntil = until;
    return false;
  }

  void reset() {
    fails = 0;
    blockedUntil = null;
    _store(0, null);
  }
}
