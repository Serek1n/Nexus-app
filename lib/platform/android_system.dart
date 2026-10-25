import 'dart:io';

import 'package:flutter/services.dart';

/// Системные функции Android (канал nexus/system в MainActivity).
class AndroidSystem {
  static const _ch = MethodChannel('nexus/system');

  static Future<T?> _call<T>(String method, [Object? arg]) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ch.invokeMethod<T>(method, arg);
    } catch (_) {
      return null;
    }
  }

  /// Android 13+: разрешение на уведомление о подключении.
  static Future<void> requestNotifications() => _call('requestNotifications');

  /// Отключена ли для Nexus экономия батареи (нужно для стабильной работы в фоне).
  static Future<bool> isIgnoringBattery() async =>
      await _call<bool>('isIgnoringBattery') ?? true;

  static Future<void> requestIgnoreBattery() => _call('requestIgnoreBattery');

  /// Установленные приложения: пары (пакет, название).
  static Future<List<(String, String)>> listApps() async {
    final raw = await _call<List<dynamic>>('listApps') ?? const [];
    return [
      for (final e in raw)
        if (e is List && e.length == 2) (e[0].toString(), e[1].toString()),
    ];
  }

  /// Версия приложения, архитектура процессора и папка кэша.
  static Future<Map<String, dynamic>> appInfo() async {
    final m = await _call<Map<dynamic, dynamic>>('appInfo');
    return m?.cast<String, dynamic>() ?? {};
  }

  /// Разрешена ли установка APK из Nexus (Android 8+).
  static Future<bool> canInstallApk() async =>
      await _call<bool>('canInstallApk') ?? false;

  static Future<void> openInstallSettings() => _call('openInstallSettings');

  /// Открывает системный установщик для скачанного обновления.
  static Future<bool> installApk(String path) async =>
      await _call<bool>('installApk', path) ?? false;

  /// Системные настройки VPN: «Постоянная VPN» и «Блокировать без VPN».
  static Future<void> openVpnSettings() => _call('openVpnSettings');

  /// Запрет снимков экрана и показа содержимого в списке недавних приложений.
  static Future<void> setSecureScreen(bool on) => _call('setSecureScreen', on);
}
