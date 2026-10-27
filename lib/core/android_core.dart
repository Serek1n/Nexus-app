import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_v2ray_client/flutter_v2ray.dart';

import '../models.dart';
import '../services/ru_apps.dart';
import 'vpn_core.dart';

/// Android: ядро Xray внутри VpnService (плагин flutter_v2ray_client).
class AndroidCore extends VpnCore {
  final _states = StreamController<ConnState>.broadcast();
  final _stats = StreamController<ConnStats>.broadcast();
  final List<String> _logs = [];
  late final V2ray _v2ray = V2ray(onStatusChanged: _onStatus);
  ConnState _last = ConnState.disconnected;
  DateTime? _startedAt;

  /// Служебный вход ядра для запросов самого Nexus (Nexus исключён из
  /// своего же VPN, поэтому без него проверить IP выхода нельзя).
  /// Логин и пароль новые при каждом подключении — другие приложения
  /// на телефоне воспользоваться им не смогут.
  String? _probe;

  @override
  String? get activeProxy => _last == ConnState.connected ? _probe : null;

  static String _token() {
    final r = Random.secure();
    return List.generate(
        24, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[r.nextInt(32)]).join();
  }

  /// Добавляет в конфиг защищённый паролем HTTP-вход на свободном порту.
  Future<String> _withProbe(String config) async {
    try {
      final cfg = jsonDecode(config) as Map<String, dynamic>;
      final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = sock.port;
      await sock.close();
      final user = _token(), pass = _token();
      final inbounds = (cfg['inbounds'] as List?) ?? [];
      inbounds.add({
        'tag': 'nexus-probe',
        'listen': '127.0.0.1',
        'port': port,
        'protocol': 'http',
        'settings': {
          'accounts': [
            {'user': user, 'pass': pass},
          ],
        },
      });
      cfg['inbounds'] = inbounds;
      _probe = '$user:$pass@127.0.0.1:$port';
      return jsonEncode(cfg);
    } catch (_) {
      _probe = null;
      return config;
    }
  }

  void _onStatus(V2RayStatus s) {
    final st = s.state.toUpperCase();
    final ConnState mapped;
    if (st.contains('DISCONNECT')) {
      mapped = ConnState.disconnected;
    } else if (st.contains('CONNECTING')) {
      mapped = ConnState.connecting;
    } else if (st.contains('CONNECTED')) {
      mapped = ConnState.connected;
    } else {
      mapped = _last;
    }
    // Сразу после запуска плагин может прислать старый «DISCONNECTED» —
    // не принимаем его за обрыв, иначе начинается цикл переподключений.
    if (mapped == ConnState.disconnected &&
        _last == ConnState.connecting &&
        _startedAt != null &&
        DateTime.now().difference(_startedAt!).inSeconds < 10) {
      return;
    }
    if (mapped != _last) {
      _last = mapped;
      _states.add(mapped);
    }
    _stats.add(ConnStats(
      uploadSpeed: s.uploadSpeed,
      downloadSpeed: s.downloadSpeed,
      upload: s.upload,
      download: s.download,
    ));
  }

  @override
  Stream<ConnState> get states => _states.stream;

  @override
  Stream<ConnStats> get stats => _stats.stream;

  @override
  List<String> get logs => _logs;

  @override
  Future<void> init() async {
    await _v2ray.initialize(
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
    );
  }

  @override
  Future<void> connect({
    required String remark,
    required String config,
    required AppSettings settings,
  }) async {
    if (settings.androidVpnMode) {
      final ok = await _v2ray.requestPermission();
      if (!ok) {
        throw Exception('Нет разрешения на VPN — разрешите его в системном окне');
      }
    }
    // Приложения мимо VPN: выбранные вручную + российские в умном режиме.
    final bypass = <String>{
      ...settings.bypassApps,
      if (settings.routing == RoutingMode.smart && settings.ruAppsDirect)
        ...RuAppsUpdater.all,
    }.toList();
    // Новое подключение: сбрасываем запомненное состояние, иначе статус
    // «CONNECTED» от плагина может совпасть со старым и потеряться —
    // приложение тогда бесконечно ждёт подключения.
    _last = ConnState.connecting;
    _startedAt = DateTime.now();
    await _v2ray.startV2Ray(
      remark: remark,
      config: await _withProbe(config),
      blockedApps: settings.androidVpnMode && bypass.isNotEmpty ? bypass : null,
      proxyOnly: !settings.androidVpnMode,
      notificationDisconnectButtonName: 'ОТКЛЮЧИТЬ',
    );
  }

  @override
  Future<void> disconnect() async {
    try {
      await _v2ray.stopV2Ray();
    } finally {
      // Плагин не всегда присылает «DISCONNECTED» — сообщаем сами.
      _startedAt = null;
      _probe = null;
      if (_last != ConnState.disconnected) {
        _last = ConnState.disconnected;
        _states.add(ConnState.disconnected);
      }
    }
  }

  @override
  Future<int> ping(ServerProfile server, String config) async {
    try {
      final d = await _v2ray
          .getServerDelay(config: config)
          .timeout(const Duration(seconds: 10));
      return d <= 0 ? -1 : d;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<int> connectedDelay(ServerProfile server) async {
    try {
      final d = await _v2ray
          .getConnectedServerDelay()
          .timeout(const Duration(seconds: 10));
      return d <= 0 ? -1 : d;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<List<String>> fetchLogs() async {
    try {
      final l = await _v2ray.getLogs();
      final core = l.length > 300 ? l.sublist(l.length - 300) : l;
      // Строки ядра + заметки самого Nexus (проверки канала).
      return [...core, ..._logs];
    } catch (_) {
      return _logs;
    }
  }

  @override
  Future<String> coreVersion() async {
    try {
      return await _v2ray.getCoreVersion();
    } catch (_) {
      return '—';
    }
  }
}
