import 'dart:io';

import 'android_system.dart';

/// Текущая сеть Wi-Fi: имя (SSID) и точка доступа (BSSID, MAC роутера).
class WifiNet {
  const WifiNet(this.ssid, this.bssid);
  final String ssid;

  /// null — система не сообщила (нет разрешения).
  final String? bssid;

  /// Запись для списка доверенных: «имя|bssid» или просто «имя».
  String get key => bssid == null ? ssid : '$ssid|$bssid';

  /// Сеть доверенная: запись с точкой доступа совпадает только с этой
  /// точкой (чужая сеть с тем же именем не пройдёт), запись без точки
  /// (старые версии) — по одному имени.
  bool trustedBy(Iterable<String> trusted) => trusted.any((t) {
        final i = t.lastIndexOf('|');
        if (i < 0) return t == ssid;
        return t.substring(0, i) == ssid &&
            bssid != null &&
            t.substring(i + 1).toLowerCase() == bssid!.toLowerCase();
      });
}

/// Имя доверенной записи для показа: «Дом · …:3f:a1» или «Дом».
String trustedLabel(String entry) {
  final i = entry.lastIndexOf('|');
  if (i < 0) return entry;
  final b = entry.substring(i + 1);
  return '${entry.substring(0, i)} · …${b.length > 5 ? b.substring(b.length - 5) : b}';
}

bool _validBssid(String? b) =>
    b != null &&
    RegExp(r'^[0-9a-fA-F]{2}(:[0-9a-fA-F]{2}){5}$').hasMatch(b) &&
    // Так Android прячет настоящий адрес без разрешения.
    b != '02:00:00:00:00:00' &&
    b != '00:00:00:00:00:00';

/// Сеть Wi-Fi, к которой подключено устройство, или null.
Future<WifiNet?> currentWifi() async {
  if (Platform.isAndroid) {
    final m = await AndroidSystem.wifiInfo();
    final ssid = m?['ssid'];
    if (ssid == null || ssid.isEmpty) return null;
    final b = m?['bssid'];
    return WifiNet(ssid, _validBssid(b) ? b!.toLowerCase() : null);
  }
  if (Platform.isWindows) {
    try {
      final r = await Process.run('netsh', ['wlan', 'show', 'interfaces'])
          .timeout(const Duration(seconds: 5));
      return parseNetsh('${r.stdout}');
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Из вывода «netsh wlan show interfaces»: строки «SSID : имя» и
/// «BSSID : aa:bb:…». Подключения нет — null.
WifiNet? parseNetsh(String out) {
  String? ssid, bssid;
  for (final line in out.split(RegExp(r'\r?\n'))) {
    final s = RegExp(r'^\s*SSID\s*:\s*(.+?)\s*$').firstMatch(line);
    if (s != null && ssid == null) ssid = s.group(1);
    final b = RegExp(r'^\s*BSSID\s*:\s*(\S+)\s*$').firstMatch(line);
    if (b != null && bssid == null) bssid = b.group(1);
  }
  if (ssid == null || ssid.isEmpty) return null;
  return WifiNet(ssid, _validBssid(bssid) ? bssid!.toLowerCase() : null);
}
