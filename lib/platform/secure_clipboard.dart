import 'dart:async';

import 'package:flutter/services.dart';

import 'android_system.dart';

/// Через сколько секретная строка (ключ, подписка, пароль) пропадает из буфера.
const kSecretClipboardTtl = Duration(minutes: 2);

String? _pending;
DateTime? _clearAt;

/// Копирует ключ, ссылку подписки или пароль и через [kSecretClipboardTtl]
/// очищает буфер обмена — если там всё ещё наша строка. Так ключи не
/// остаются в буфере, откуда их могут прочитать другие приложения.
///
/// Android 10+ не даёт читать буфер приложению в фоне: если через две
/// минуты Nexus свёрнут, буфер очищается, как только он снова откроется
/// (а Android 13+ к тому же не показывает ключ в превью буфера).
Future<void> copySecret(String text) async {
  if (!await AndroidSystem.copySecret(text)) {
    await Clipboard.setData(ClipboardData(text: text));
  }
  _pending = text;
  _clearAt = DateTime.now().add(kSecretClipboardTtl);
  Timer(kSecretClipboardTtl, secretClipboardCheck);
}

/// Пора очистить буфер (таймер или возвращение в Nexus).
Future<void> secretClipboardCheck() async {
  final text = _pending, at = _clearAt;
  if (text == null || at == null || DateTime.now().isBefore(at)) return;
  try {
    final cur = await Clipboard.getData(Clipboard.kTextPlain);
    if (cur == null) return; // в фоне буфер недоступен — попробуем позже
    if (cur.text == text) {
      await Clipboard.setData(const ClipboardData(text: ''));
    }
    _pending = null;
    _clearAt = null;
  } catch (_) {}
}
