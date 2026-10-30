import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart' as cg;
import '../l10n.dart';

/// Резервная копия Nexus: подписки, свои серверы и настройки,
/// зашифрованные паролем (PBKDF2-SHA256 → AES-256-GCM).
///
/// Формат — одна строка «nexus-backup:2:<base64url>», где внутри
/// соль (16 байт) | nonce (12) | шифротекст | метка GCM (16).
/// Без пароля из неё ничего не достать; изменённая копия не расшифруется.
/// Версия 1 — то же с 100 000 итераций PBKDF2 (читается для совместимости).
class Backup {
  static const prefix = 'nexus-backup:2:';
  static const _iterations = {'1': 100000, '2': 200000};

  static bool looksLike(String text) =>
      text.trim().toLowerCase().startsWith('nexus-backup:');

  static cg.Pbkdf2 _kdf(int iterations) => cg.Pbkdf2(
      macAlgorithm: cg.Hmac.sha256(), iterations: iterations, bits: 256);

  static List<int> _random(int n) {
    final r = Random.secure();
    return List.generate(n, (_) => r.nextInt(256));
  }

  /// Подбор ключа из пароля занимает 1–3 секунды — выполняем в отдельном
  /// потоке, чтобы интерфейс не замирал.
  static Future<String> encrypt(Map<String, dynamic> data, String password) {
    if (password.length < 6) {
      throw Exception(tr('Пароль — не короче 6 символов'));
    }
    final json = jsonEncode(data);
    final salt = _random(16);
    final nonce = _random(12);
    return Isolate.run(() async {
      final key = await _kdf(_iterations['2']!)
          .deriveKeyFromPassword(password: password, nonce: salt);
      final box = await cg.AesGcm.with256bits()
          .encrypt(utf8.encode(json), secretKey: key, nonce: nonce);
      final out = [...salt, ...box.nonce, ...box.cipherText, ...box.mac.bytes];
      return prefix + base64Url.encode(out).replaceAll('=', '');
    });
  }

  static Future<Map<String, dynamic>> decrypt(
      String text, String password) async {
    final t = text.trim();
    final m = RegExp(r'^nexus-backup:(\d+):').firstMatch(t);
    final iterations = m == null ? null : _iterations[m.group(1)];
    if (iterations == null) {
      throw Exception(tr('Это не резервная копия Nexus или она из новой версии'));
    }
    var b64 = t.substring(m!.end).replaceAll(RegExp(r'\s'), '');
    if (b64.length > 4 * 1024 * 1024) throw Exception(tr('Слишком большая копия'));
    b64 += '=' * ((4 - b64.length % 4) % 4);
    final List<int> raw;
    try {
      raw = base64Url.decode(b64);
    } catch (_) {
      throw Exception(tr('Копия повреждена — скопируйте её целиком'));
    }
    if (raw.length < 16 + 12 + 16 + 2) {
      throw Exception(tr('Копия повреждена — скопируйте её целиком'));
    }
    // null — неверный пароль, иначе текст копии.
    final plain = await Isolate.run(() async {
      final salt = raw.sublist(0, 16);
      final nonce = raw.sublist(16, 28);
      final ct = raw.sublist(28, raw.length - 16);
      final mac = raw.sublist(raw.length - 16);
      final key = await _kdf(iterations)
          .deriveKeyFromPassword(password: password, nonce: salt);
      try {
        return utf8.decode(await cg.AesGcm.with256bits().decrypt(
            cg.SecretBox(ct, nonce: nonce, mac: cg.Mac(mac)),
            secretKey: key));
      } on cg.SecretBoxAuthenticationError {
        return null;
      }
    });
    if (plain == null) throw Exception(tr('Неверный пароль'));
    try {
      final j = jsonDecode(plain);
      if (j is! Map<String, dynamic>) throw const FormatException();
      return j;
    } on FormatException {
      throw Exception(tr('Копия повреждена'));
    }
  }
}
