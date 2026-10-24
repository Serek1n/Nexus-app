import 'dart:async';

import 'package:flutter_v2ray_client/flutter_v2ray.dart';

import '../models.dart';
import 'vpn_core.dart';

/// Android: ядро Xray внутри VpnService (плагин flutter_v2ray_client).
class AndroidCore extends VpnCore {
  final _states = StreamController<ConnState>.broadcast();
  final _stats = StreamController<ConnStats>.broadcast();
  final List<String> _logs = [];
  late final V2ray _v2ray = V2ray(onStatusChanged: _onStatus);
  ConnState _last = ConnState.disconnected;

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
    await _v2ray.startV2Ray(
      remark: remark,
      config: config,
      proxyOnly: !settings.androidVpnMode,
      notificationDisconnectButtonName: 'ОТКЛЮЧИТЬ',
    );
  }

  @override
  Future<void> disconnect() => _v2ray.stopV2Ray();

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
