import 'dart:ffi';
import 'dart:io';

/// Права администратора Windows: нужны для режима TUN (виртуальная
/// сетевая карта Wintun и системные маршруты).
class WinAdmin {
  static bool? _cached;

  /// Запущен ли Nexus с правами администратора.
  static bool get isAdmin {
    if (!Platform.isWindows) return false;
    return _cached ??= () {
      try {
        final shell32 = DynamicLibrary.open('shell32.dll');
        final f = shell32
            .lookupFunction<Int32 Function(), int Function()>('IsUserAnAdmin');
        return f() != 0;
      } catch (_) {
        return false;
      }
    }();
  }

  /// Перезапускает Nexus с правами администратора (окно UAC).
  /// true — пользователь согласился и новая копия запускается.
  static Future<bool> relaunchElevated({bool connect = false}) async {
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        "Start-Process -FilePath '$exe' -ArgumentList '--relaunch${connect ? ' --connect' : ''}' -Verb RunAs",
      ]);
      // Отказ в окне UAC — Start-Process завершается с ошибкой.
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
