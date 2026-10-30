import 'dart:io';

import 'android_system.dart';

/// Безопасная ли ссылка для открытия в браузере: только https, без
/// пробелов и управляющих символов, разумной длины.
bool isSafeWebLink(String url) {
  if (url.length > 500 || RegExp(r'[\s\x00-\x1f"<>`]').hasMatch(url)) {
    return false;
  }
  final u = Uri.tryParse(url);
  return u != null && u.scheme == 'https' && u.host.isNotEmpty;
}

/// Открывает https-ссылку в браузере (поддержка подписки, страница релиза).
Future<bool> openWebLink(String url) async {
  if (!isSafeWebLink(url)) return false;
  if (Platform.isAndroid) return AndroidSystem.openUrl(url);
  if (Platform.isWindows) {
    try {
      // Аргументом, без оболочки: ссылка не может стать командой.
      await Process.start('rundll32', ['url.dll,FileProtocolHandler', url]);
      return true;
    } catch (_) {
      return false;
    }
  }
  return false;
}
