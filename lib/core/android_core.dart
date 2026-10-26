import 'dart:async';

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
      config: config,
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
      return l.length > 400 ? l.sublist(l.length - 400) : l;
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
