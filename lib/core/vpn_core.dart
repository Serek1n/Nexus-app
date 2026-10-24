import 'dart:async';
import 'dart:io';

import '../models.dart';
import 'android_core.dart';
import 'windows_core.dart';

/// Общий интерфейс ядра для Android и Windows.
abstract class VpnCore {
  static VpnCore create() =>
      Platform.isWindows ? WindowsCore() : AndroidCore();

  /// Поток изменений состояния.
  Stream<ConnState> get states;

  /// Поток статистики (скорости, трафик).
  Stream<ConnStats> get stats;

  Future<void> init();

  /// Запускает подключение. Бросает исключение с понятным текстом при ошибке.
  Future<void> connect({
    required String remark,
    required String config,
    required AppSettings settings,
  });

  Future<void> disconnect();

  /// Задержка до сервера в мс (-1 — недоступен).
  Future<int> ping(ServerProfile server, String config);

  Future<String> coreVersion();

  /// Последние строки журнала ядра.
  List<String> get logs;

  Future<List<String>> fetchLogs() async => logs;

  /// Можно ли обновлять ядро отдельно от приложения (только Windows).
  bool get canUpdateCore => false;

  /// Проверяет и ставит новую версию ядра. Возвращает текст результата.
  Future<String> updateCore({bool force = false}) async =>
      'Ядро обновляется вместе с приложением';

  Future<void> dispose() async {}
}

/// TCP-пинг: время установки соединения до host:port.
Future<int> tcpPing(String host, int port,
    {Duration timeout = const Duration(seconds: 4)}) async {
  final sw = Stopwatch()..start();
  try {
    final s = await Socket.connect(host, port, timeout: timeout);
    sw.stop();
    s.destroy();
    return sw.elapsedMilliseconds.clamp(1, 9999);
  } catch (_) {
    return -1;
  }
}
