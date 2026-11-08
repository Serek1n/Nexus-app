import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Шифрование подписок и ключей на macOS, iOS и Linux: AES-256-GCM,
/// ключ — в системном хранилище (Keychain на Apple, Secret Service —
/// GNOME Keyring / KWallet — на Linux). На Windows — DPAPI, на Android —
/// Keystore (отдельно).
class KeyringBox {
  static const _prefix = 'kr1:';
  static const _ch = MethodChannel('nexus/keychain');
  static const _service = 'app.nexusvpn.nexus';
  static const _account = 'secrets-key';

  static List<int>? _key;

  static bool get supported =>
      Platform.isMacOS || Platform.isIOS || Platform.isLinux;

  static bool isProtected(String s) => s.startsWith(_prefix);

  @visibleForTesting
  static set debugKey(List<int>? k) => _key = k;

  /// Ключ из хранилища. Нет ключа и [create] — создаёт новый. null —
  /// хранилище недоступно (заблокировано, нет службы): тогда новый ключ
  /// НЕ создаётся, иначе старые данные стало бы нечем расшифровать.
  static Future<List<int>?> _loadKey({required bool create}) async {
    if (_key != null) return _key;
    try {
      var k = Platform.isLinux ? await _linuxGet() : await _appleGet();
      if (k == null && create) {
        final r = Random.secure();
        final fresh = List<int>.generate(32, (_) => r.nextInt(256));
        final ok =
            Platform.isLinux ? await _linuxSet(fresh) : await _appleSet(fresh);
        if (!ok) return null;
        // Перечитываем: записалось именно то, что будем использовать.
        k = Platform.isLinux ? await _linuxGet() : await _appleGet();
      }
      if (k != null && k.length == 32) _key = k;
      return _key;
    } catch (_) {
      return null;
    }
  }

  // ── Apple: Keychain через Swift (канал nexus/keychain) ──

  static Future<List<int>?> _appleGet() async =>
      await _ch.invokeMethod<Uint8List>('get');

  static Future<bool> _appleSet(List<int> k) async =>
      await _ch.invokeMethod<bool>('set', Uint8List.fromList(k)) == true;

  // ── Linux: secret-tool (libsecret); ключ передаётся через stdin ──

  static Future<List<int>?> _linuxGet() async {
    final r = await Process.run('secret-tool',
        ['lookup', 'service', _service, 'account', _account]);
    final out = '${r.stdout}'.trim();
    if (r.exitCode == 0 && out.isNotEmpty) return base64.decode(out);
    // «Не найдено» — пустой ответ без ошибки; иначе хранилище недоступно.
    if ('${r.stderr}'.trim().isEmpty) return null;
    throw Exception('${r.stderr}');
  }

  static Future<bool> _linuxSet(List<int> k) async {
    final p = await Process.start('secret-tool', [
      'store',
      '--label=Nexus',
      'service',
      _service,
      'account',
      _account,
    ]);
    p.stdin.write(base64.encode(k));
    await p.stdin.close();
    return await p.exitCode.timeout(const Duration(seconds: 20)) == 0;
  }

  static final _aes = AesGcm.with256bits();

  /// Шифрует; хранилище недоступно — возвращает текст как есть.
  static Future<String> protect(String plain) async {
    final k = await _loadKey(create: true);
    if (k == null) return plain;
    try {
      final box = await _aes.encrypt(utf8.encode(plain),
          secretKey: SecretKey(k), nonce: _aes.newNonce());
      return '$_prefix${base64.encode(box.concatenation())}';
    } catch (_) {
      return plain;
    }
  }

  /// Расшифровывает; незашифрованный текст — как есть. null — не удалось
  /// (хранилище недоступно или данные повреждены).
  static Future<String?> unprotect(String stored) async {
    if (!isProtected(stored)) return stored;
    final k = await _loadKey(create: false);
    if (k == null) return null;
    try {
      final box = SecretBox.fromConcatenation(
          base64.decode(stored.substring(_prefix.length)),
          nonceLength: 12,
          macLength: 16);
      return utf8.decode(await _aes.decrypt(box, secretKey: SecretKey(k)));
    } catch (_) {
      return null;
    }
  }
}
