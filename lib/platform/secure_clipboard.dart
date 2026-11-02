import 'dart:async';

import 'package:flutter/services.dart';

import 'android_system.dart';

/// Через сколько секретная строка (ключ, подписка, пароль) пропадает из буфера.
const kSecretClipboardTtl = Duration(minutes: 2);

/// Копирует ключ, ссылку подписки или пароль и через [kSecretClipboardTtl]
/// очищает буфер обмена — если там всё ещё наша строка. Так ключи не
/// остаются в буфере, откуда их могут прочитать другие приложения.
Future<void> copySecret(String text) async {
  if (!await AndroidSystem.copySecret(text)) {
    await Clipboard.setData(ClipboardData(text: text));
  }
  Timer(kSecretClipboardTtl, () async {
    try {
      final cur = await Clipboard.getData(Clipboard.kTextPlain);
      if (cur?.text == text) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {}
  });
}
