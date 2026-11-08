import 'dart:io';

import 'package:flutter/services.dart';

/// macOS: ссылки nexus:// приходят от системы в Swift (MainFlutterWindow)
/// и передаются сюда. На Windows и Linux ссылка — аргумент запуска.
class MacLinks {
  static const _ch = MethodChannel('nexus/links');

  static Future<void> listen(void Function(String) onLink) async {
    if (!Platform.isMacOS) return;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) {
        onLink(call.arguments as String);
      }
    });
    try {
      final first = await _ch.invokeListMethod<String>('initialLinks');
      for (final l in first ?? const <String>[]) {
        onLink(l);
      }
    } catch (_) {}
  }
}
