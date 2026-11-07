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
