import 'dart:async';
import 'dart:io';

import '../models.dart';
import 'android_core.dart';
import 'windows_core.dart';
import '../l10n.dart';

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

  /// Пакетный замер: одно ядро на много серверов (быстрее на сотнях).
  /// Ключ — id сервера, значение — мс или -1. null — не поддерживается
  /// или ядро не запустилось: тогда меряем по одному.
  Future<Map<String, int>?> pingBatch(
          List<ServerProfile> servers, String Function(ServerProfile) config) async =>
      null;

  Future<String> coreVersion();

  /// Последние строки журнала ядра.
  List<String> get logs;

  Future<List<String>> fetchLogs() async => logs;

  /// Строка от самого Nexus в журнал (результат проверки канала и т.п.).
  void note(String line) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    logs.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} · $line');
    if (logs.length > 400) logs.removeRange(0, logs.length - 400);
  }

  /// Можно ли обновлять ядро отдельно от приложения (только Windows).
  bool get canUpdateCore => false;

  /// Проверяет и ставит новую версию ядра. Возвращает текст результата.
  Future<String> updateCore({bool force = false}) async =>
      tr('Ядро обновляется вместе с приложением');

  /// Задержка через активное соединение (мс, -1 — нет связи).
  Future<int> connectedDelay(ServerProfile server) =>
      tcpPing(server.host, server.port);

  /// Выполняет [fn] через временный туннель к [server] (локальный HTTP-прокси
  /// «user:pass@127.0.0.1:port»). null — платформа так не умеет.
  Future<T?> viaTunnel<T>(ServerProfile server, String config,
          Future<T> Function(String proxy) fn) async =>
      null;

  /// HTTP-прокси через активное подключение («127.0.0.1:port» или
  /// «user:pass@127.0.0.1:port») — для собственных запросов Nexus
  /// (IP выхода, тест скорости, подписки). null — VPN не подключён.
  String? get activeProxy => null;

  /// Режим «Авто»: задержка каждого сервера пула по последней проверке ядра
  /// (тег nx-N → мс; -1 — не отвечает). Пусто — неизвестно.
  Map<String, int> get autoStatus => const {};

  /// Предупреждение о режиме работы (например, TUN недоступен) — или null.
  String? get modeWarning => null;

  /// Kill switch сработал: VPN упал, интернет заблокирован до отключения.
  bool get blocked => false;

  /// Окно видно пользователю (на Windows без окна статистику не опрашиваем).
  void setForeground(bool visible) {}

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
