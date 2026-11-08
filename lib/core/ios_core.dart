import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

import '../l10n.dart';
import '../models.dart';
import '../services/config_builder.dart';
import 'vpn_core.dart';

/// iOS: Xray работает в расширении NexusTunnel (Network Extension,
/// Packet Tunnel). Приложение управляет VPN через системный
/// NETunnelProviderManager (канал nexus/ios_vpn), задержку серверов меряет
/// своим экземпляром libXray, статистику и «Авто» читает через служебный
/// вход ядра с паролем.
class IosCore extends VpnCore {
  static const _ch = MethodChannel('nexus/ios_vpn');

  final _states = StreamController<ConnState>.broadcast();
  final _stats = StreamController<ConnStats>.broadcast();
  final List<String> _logs = [];
  ConnState _last = ConnState.disconnected;
  DateTime? _startedAt;
  Timer? _poll;
  bool _foreground = true;
  Map<String, int> _autoStatus = const {};
  (int, int)? _prev;
  DateTime? _prevAt;
  int _up = 0, _down = 0;

  /// Служебный HTTP-вход ядра «user:pass@127.0.0.1:port». На iPhone к
  /// 127.0.0.1 могут подключиться и другие приложения, поэтому обычных
  /// (без пароля) входов у ядра нет совсем; пароль новый при каждом
  /// подключении.
  String? _probe;

  @override
  String? get activeProxy => _last == ConnState.connected ? _probe : null;

  @override
  bool get httpLocked => true;

  @override
  Map<String, int> get autoStatus =>
      _last == ConnState.connected ? _autoStatus : const {};

  @override
  Stream<ConnState> get states => _states.stream;

  @override
  Stream<ConnStats> get stats => _stats.stream;

  @override
  List<String> get logs => _logs;

  @override
  void setForeground(bool visible) {
    _foreground = visible;
    if (visible && _last == ConnState.connected) unawaited(_pollStats());
  }

  void _set(ConnState s) {
    if (s == _last) return;
    _last = s;
    _states.add(s);
    if (s == ConnState.connected) {
      // Адрес служебного входа берём у самого туннеля: VPN мог подняться
      // без приложения (Настройки iOS, автоподключение) или до его запуска.
      unawaited(_fetchProbe().whenComplete(() {
        if (_last == ConnState.connected) _startPolling();
      }));
    } else if (s == ConnState.disconnected) {
      _poll?.cancel();
      _poll = null;
      _autoStatus = const {};
      _stats.add(const ConnStats());
    }
  }

  @override
  Future<void> init() async {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'status':
          _onStatus('${call.arguments}');
        case 'error':
          note(tr('VPN остановлен: {0}', [call.arguments]));
      }
      return null;
    });
    try {
      // VPN мог остаться включённым с прошлого запуска.
      final s = await _ch.invokeMethod<String>('status');
      if (s != null) _onStatus(s);
    } catch (_) {}
  }

  void _onStatus(String s) {
    switch (s) {
      case 'connected':
        _set(ConnState.connected);
      case 'connecting':
      case 'reasserting':
        _set(ConnState.connecting);
      case 'disconnecting':
        break;
      default:
        // Сразу после запуска система может прислать старое
        // «отключено» — не принимаем его за обрыв.
        if (_last == ConnState.connecting &&
            _startedAt != null &&
            DateTime.now().difference(_startedAt!).inSeconds < 3) {
          return;
        }
        _set(ConnState.disconnected);
    }
  }

  static String _token() {
    final r = Random.secure();
    return List.generate(
        24, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[r.nextInt(32)]).join();
  }

  /// Конфиг для туннеля iOS: TUN-вход (дескриптор туннеля подставит
  /// расширение), DNS программ — во встроенный DNS ядра, служебный вход
  /// с паролем для статистики и проверок. Входы без пароля убираются.
  Future<String> _forTunnel(String config) async {
    final cfg = jsonDecode(config) as Map<String, dynamic>;
    final inbounds = ((cfg['inbounds'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .where((ib) => ib['tag'] != 'socks-in' && ib['tag'] != 'http-in')
        .toList();
    final dns = ((cfg['dns'] as Map?)?['servers'] as List?)
            ?.whereType<String>()
            .where((e) => !e.contains('://'))
            .firstOrNull ??
        '1.1.1.1';
    inbounds.insert(0, {
      'tag': 'tun-in',
      'protocol': 'tun',
      'port': 0,
      'settings': {
        'name': 'utun',
        'mtu': 1500,
        'gateway': ['172.19.0.1/30'],
        'dns': [dns],
      },
      'sniffing': {
        'enabled': true,
        'destOverride': ['http', 'tls', 'quic'],
        'routeOnly': true,
      },
    });
    final sock = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = sock.port;
    await sock.close();
    final user = _token(), pass = _token();
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
    final outbounds = (cfg['outbounds'] as List?) ?? [];
    outbounds.add({'tag': 'dns-out', 'protocol': 'dns'});
    cfg['outbounds'] = outbounds;
    final routing = (cfg['routing'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final rules = (routing['rules'] as List?) ?? [];
    rules.insert(0, {
      'type': 'field',
      'inboundTag': ['tun-in'],
      'port': '53',
      'outboundTag': 'dns-out',
    });
    routing['rules'] = rules;
    cfg['routing'] = routing;
    addPrivateMetrics(cfg, 'nexus-probe');
    cfg['stats'] = <String, dynamic>{};
    cfg['policy'] = {
      'system': {
        'statsOutboundUplink': true,
        'statsOutboundDownlink': true,
      },
    };
    // Память расширения на iPhone ограничена — без журнала соединений.
    cfg['log'] = {'loglevel': 'warning', 'access': 'none'};
    _probe = '$user:$pass@127.0.0.1:$port';
    return jsonEncode(cfg);
  }

  @override
  Future<void> connect({
    required String remark,
    required String config,
    required AppSettings settings,
  }) async {
    _startedAt = DateTime.now();
    _prev = null;
    _up = _down = 0;
    _set(ConnState.connecting);
    final full = await _forTunnel(config);
    note(tr('Запуск: {0}', [remark]));
    try {
      await _ch.invokeMethod('start', {
        'config': full,
        'remark': remark,
        'onDemand': settings.autoReconnect,
      });
    } on PlatformException catch (e) {
      _set(ConnState.disconnected);
      if (e.code == 'denied') {
        throw Exception(tr('Нет разрешения на VPN — разрешите его в системном окне'));
      }
      throw Exception(e.message ?? e.code);
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
    _startedAt = null;
    _probe = null;
    _set(ConnState.disconnected);
  }

  Future<void> _fetchProbe() async {
    try {
      final p = await _ch
          .invokeMethod<String>('probe')
          .timeout(const Duration(seconds: 3));
      if (p != null &&
          RegExp(r'^[a-z0-9]+:[a-z0-9]+@127\.0\.0\.1:\d+$').hasMatch(p)) {
        _probe = p;
      }
    } catch (_) {}
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_foreground) unawaited(_pollStats());
    });
    unawaited(_pollStats());
  }

  Future<void> _pollStats() async {
    final p = activeProxy;
    if (p == null) return;
    final c = HttpClient()
      ..findProxy = ((_) => 'PROXY $p')
      ..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await c
          .getUrl(Uri.parse('http://$kMetricsHost/debug/vars'))
          .timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      final j = jsonDecode(await res.transform(utf8.decoder).join())
          as Map<String, dynamic>;
      _autoStatus = parseObservatory(j['observatory']);
      final all = (j['stats']?['outbound'] as Map?) ?? const {};
      var up = 0, down = 0;
      all.forEach((tag, v) {
        if (v is! Map) return;
        if (tag != 'proxy' && !'$tag'.startsWith(kAutoPrefix)) return;
        up += (v['uplink'] as num?)?.toInt() ?? 0;
        down += (v['downlink'] as num?)?.toInt() ?? 0;
      });
      final now = DateTime.now();
      var upS = 0, downS = 0;
      final prev = _prev, at = _prevAt;
      if (prev != null && at != null) {
        final ms = now.difference(at).inMilliseconds.clamp(1, 1 << 30);
        upS = ((up - prev.$1).clamp(0, 1 << 40) * 1000 ~/ ms);
        downS = ((down - prev.$2).clamp(0, 1 << 40) * 1000 ~/ ms);
      }
      _prev = (up, down);
      _prevAt = now;
      _up = up;
      _down = down;
      _stats.add(ConnStats(
          uploadSpeed: upS, downloadSpeed: downS, upload: _up, download: _down));
    } catch (_) {
    } finally {
      c.close(force: true);
    }
  }

  /// Задержка через libXray в самом приложении: 5 серверов за вызов.
  Future<List<int>> _pingConfigs(List<String> configs) async {
    try {
      final res = await _ch.invokeMethod<String>('pingBatch', {
        'request': jsonEncode({
          'configs': [
            for (final c in configs) {'xrayJson': c, 'outboundTag': 'proxy'},
          ],
          'timeout': 8,
          'url': 'https://www.gstatic.com/generate_204',
        }),
      }).timeout(const Duration(seconds: 20));
      final j = jsonDecode(res ?? '{}') as Map<String, dynamic>;
      final list = ((j['data'] as Map?)?['results'] as List?) ?? const [];
      return [
        for (var i = 0; i < configs.length; i++)
          i < list.length && list[i] is Map && list[i]['success'] == true
              ? ((list[i]['delay'] as num?)?.toInt() ?? -1).clamp(1, 9999)
              : -1,
      ];
    } catch (_) {
      return List.filled(configs.length, -1);
    }
  }

  @override
  Future<int> ping(ServerProfile server, String config) async =>
      (await _pingConfigs([config])).first;

  @override
  Future<Map<String, int>?> pingBatch(List<ServerProfile> servers,
      String Function(ServerProfile) config) async {
    final out = <String, int>{};
    for (var i = 0; i < servers.length; i += 5) {
      final part = servers.sublist(i, min(i + 5, servers.length));
      final r = await _pingConfigs([for (final s in part) config(s)]);
      for (var k = 0; k < part.length; k++) {
        out[part[k].id] = r[k];
      }
    }
    return out;
  }

  @override
  Future<int> connectedDelay(ServerProfile server) async {
    final p = activeProxy;
    if (p == null) return -1;
    final c = HttpClient()
      ..findProxy = ((_) => 'PROXY $p')
      ..connectionTimeout = const Duration(seconds: 6);
    final sw = Stopwatch()..start();
    try {
      final req = await c
          .getUrl(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 8));
      final res = await req.close().timeout(const Duration(seconds: 8));
      await res.drain<void>();
      return res.statusCode == 204 ? sw.elapsedMilliseconds.clamp(1, 9999) : -1;
    } catch (_) {
      return -1;
    } finally {
      c.close(force: true);
    }
  }

  @override
  Future<List<String>> fetchLogs() async {
    try {
      final l = await _ch.invokeListMethod<String>('logs') ?? const [];
      final core = l.length > 300 ? l.sublist(l.length - 300) : l;
      return [...core, ..._logs];
    } catch (_) {
      return _logs;
    }
  }

  @override
  Future<String> coreVersion() async {
    try {
      return await _ch.invokeMethod<String>('version') ?? '—';
    } catch (_) {
      return '—';
    }
  }

  @override
  Future<void> forgetSaved() async {
    try {
      await _ch.invokeMethod('forget');
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _poll?.cancel();
  }
}
