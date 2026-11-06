import 'dart:io';

import 'package:flutter/services.dart';

/// Горячая клавиша Ctrl+Alt+N на Windows: подключить/отключить из любой
/// программы, даже когда Nexus свёрнут в трей. Регистрирует её окно
/// приложения (см. tool/patch_platforms.py → flutter_window.cpp).
class Hotkey {
  static const _ch = MethodChannel('nexus/hotkey');

  /// true — клавиша занята Nexus; false — её уже забрала другая программа.
  static Future<bool> register(void Function() onPress) async {
    if (!Platform.isWindows) return false;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'hotkey') onPress();
    });
    try {
      return await _ch.invokeMethod<bool>('register') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> unregister() async {
    if (!Platform.isWindows) return;
    try {
      await _ch.invokeMethod('unregister');
    } catch (_) {}
  }
}
