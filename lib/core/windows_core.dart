import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../services/config_builder.dart';
import 'vpn_core.dart';

const kCoreExe = 'nexus-core.exe';
const kApiPort = 10085;

/// Windows: ядро Xray (nexus-core.exe рядом с nexus.exe) + системный прокси.
class WindowsCore extends VpnCore {
  final _states = StreamController<ConnState>.broadcast();
  final _stats = StreamController<ConnStats>.broadcast();
  final List<String> _logs = [];
  Process? _proc;
  Timer? _watchdog;
  bool _proxySet = false;
  int _lastUp = 0, _lastDown = 0;
  int _failedChecks = 0;

  // Для автопереподключения, если ядро упало.
  String? _lastRemark, _lastConfig;
  AppSettings? _lastSettings;
  int _restarts = 0;
  bool _restarting = false;
  bool _foreground = true;
  int _tickN = 0;
  DateTime? _lastStatsAt;

  /// Порт API статистики выбирается случайно при каждом подключении.
  int _apiPort = kApiPort;

  @override
  void setForeground(bool visible) => _foreground = visible;

  String get _exeDir => File(Platform.resolvedExecutable).parent.path;

  /// Папка обновляемого ядра (%APPDATA%\\Nexus\\core).
  String get _updDir => '$_dataDir\\core';

  /// Если ядро уже обновлялось — берём обновлённое, иначе встроенное.
  String get _coreDir =>
      File('$_updDir\\$kCoreExe').existsSync() ? _updDir : _exeDir;
  String get _corePath => '$_coreDir\\$kCoreExe';
  String get _assetDir =>
      File('$_coreDir\\geoip.dat').existsSync() ? _coreDir : _exeDir;

  String get _dataDir {
    final base = Platform.environment['APPDATA'] ?? _exeDir;
    final d = Directory('$base\\Nexus');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  @override
  Stream<ConnState> get states => _states.stream;

  @override
  Stream<ConnStats> get stats => _stats.stream;

  @override
  List<String> get logs => _logs;

  void _log(String line) {
    final t = line.trimRight();
    if (t.isEmpty) return;
    _logs.add(t);
    if (_logs.length > 400) _logs.removeRange(0, _logs.length - 400);
  }

  @override
  Future<void> init() async {
    // Убираем «хвосты» после аварийного завершения: старое ядро и прокси.
    await _killStrayCore();
    final marker = File('$_dataDir\\proxy.lock');
    if (marker.existsSync()) {
      WinProxy.restore(_readSaved(marker));
      marker.deleteSync();
    }
  }

  Future<void> _killStrayCore() async {
    try {
      await Process.start('taskkill', ['/F', '/IM', kCoreExe],
          mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (_) {}
  }

  String _withStats(String config) {
    final cfg = jsonDecode(config) as Map<String, dynamic>;
    for (final ib in (cfg['inbounds'] as List? ?? [])) {
      if (ib is! Map<String, dynamic>) continue;
      if (ib['tag'] == 'socks-in') ib['port'] = _socksPort;
      if (ib['tag'] == 'http-in') ib['port'] = _httpPort;
    }
    cfg['stats'] = <String, dynamic>{};
    // Статистика по HTTP (/debug/vars) — без запуска отдельного процесса.
    cfg['metrics'] = {
      'tag': 'metrics',
      'listen': '127.0.0.1:$_apiPort',
    };
    cfg['policy'] = {
      'system': {
        'statsOutboundUplink': true,
        'statsOutboundDownlink': true,
      },
    };
    return jsonEncode(cfg);
  }

  @override
  Future<void> connect({
    required String remark,
    required String config,
    required AppSettings settings,
  }) async {
    if (!File(_corePath).existsSync()) {
      throw Exception('Не найдено ядро $kCoreExe рядом с программой. '
          'Переустановите Nexus из архива целиком.');
    }
    _states.add(ConnState.connecting);
    await _stopProcess();
    await _applyPendingUpdate();
    _lastRemark = remark;
    _lastConfig = config;
    _lastSettings = settings;
    if (!_restarting) _restarts = 0;

    _apiPort = await _freePort();
    // 10808/10809 могут быть заняты другим клиентом (Happ, v2rayN) или
    // зависшим ядром — тогда берём запасные порты, а не падаем.
    final (sp, hp) = await _pickPorts();
    _socksPort = sp;
    _httpPort = hp;
    activeSocksPort = sp;
    activeHttpPort = hp;

    _logs.clear();
    _log('Запуск ядра: $remark');
    if (sp != kSocksPort) {
      _log('Порты $kSocksPort/$kHttpPort заняты другой программой '
          '(например, Happ или v2rayN) — Nexus использует $sp/$hp');
    }
    try {
      // Конфиг с ключами передаётся через stdin и никогда не пишется на диск.
      _proc = await Process.start(
        _corePath,
        ['run', '-format', 'json', '-c', 'stdin:'],
        workingDirectory: _coreDir,
        environment: {'XRAY_LOCATION_ASSET': _assetDir},
      );
      _proc!.stdin.add(utf8.encode(_withStats(config)));
      await _proc!.stdin.flush();
      await _proc!.stdin.close();
    } catch (e) {
      _states.add(ConnState.disconnected);
      throw Exception('Не удалось запустить ядро: $e');
    }
    final proc = _proc!;
    // Ядро завершилось само — сразу реагируем, не дожидаясь проверки порта.
    proc.exitCode.then((code) {
      if (identical(_proc, proc) && _watchdog != null) {
        _log('Ядро завершилось (код $code)');
        _exited = true;
        _tick();
      }
    });
    _proc!.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_log);
    _proc!.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_log);

    // Ждём, пока ядро откроет локальный порт.
    var up = false;
    for (var i = 0; i < 25 && !up; i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      up = await _portOpen(_httpPort);
    }
    // Старый файл конфига от прошлых версий — удаляем.
    try {
      final old = File('$_dataDir\\config.json');
      if (old.existsSync()) old.deleteSync();
    } catch (_) {}
    if (!up) {
      await _stopProcess();
      _states.add(ConnState.disconnected);
      final tail = _logs.reversed.take(3).toList().reversed.join('\n');
      throw Exception(
          'Ядро не запустилось.${tail.isEmpty ? '' : '\n$tail'}');
    }

    if (settings.windowsSystemProxy) {
      // Запоминаем прокси, который был у пользователя до Nexus, —
      // при отключении (и после сбоя) вернём именно его.
      final marker = File('$_dataDir\\proxy.lock');
      if (!marker.existsSync()) {
        _savedProxy = WinProxy.snapshot();
        marker.writeAsStringSync(jsonEncode(_savedProxy));
      }
      WinProxy.enable('127.0.0.1:$_httpPort');
      _proxySet = true;
    }

    _lastUp = 0;
    _lastDown = 0;
    _lastStatsAt = null;
    _failedChecks = 0;
    _tickN = 0;
    _blocked = false;
    _exited = false;
    _watchdog?.cancel();
    _watchdog =
        Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _states.add(ConnState.connected);
  }

  bool _exited = false;

  Future<void> _tick() async {
    _tickN++;
    if (_blocked || _recovering) return;
    // Падение ядра ловит exitCode; порт дополнительно проверяем раз в 5 секунд.
    final portDead =
        !_exited && _tickN % 5 == 0 && !await _portOpen(_httpPort);
    if (_exited || portDead) {
      _failedChecks++;
      if (_exited || _failedChecks >= 2) {
        await _recover();
        return;
      }
    } else if (_tickN % 5 == 0) {
      _failedChecks = 0;
    }
    // Статистику запрашиваем раз в 2 секунды и только когда окно открыто.
    if (!_foreground || _tickN.isOdd) return;
    final s = await _queryStats();
    if (s != null) {
      final (up, down) = s;
      final now = DateTime.now();
      final secs = _lastStatsAt == null
          ? 1.0
          : math.max(1, now.difference(_lastStatsAt!).inMilliseconds) / 1000;
      final upSpeed =
          _lastUp == 0 ? 0 : (math.max(0, up - _lastUp) / secs).round();
      final downSpeed =
          _lastDown == 0 ? 0 : (math.max(0, down - _lastDown) / secs).round();
      _lastUp = up;
      _lastDown = down;
      _lastStatsAt = now;
      _stats.add(ConnStats(
        uploadSpeed: upSpeed,
        downloadSpeed: downSpeed,
        upload: up,
        download: down,
      ));
    }
  }

  bool _recovering = false;

  /// Ядро упало: перезапуск (до 3 раз), затем kill switch или отключение.
  Future<void> _recover() async {
    _recovering = true;
    _watchdog?.cancel();
    try {
      if (_restarts < 3 && _lastConfig != null && _lastSettings != null) {
        _restarts++;
        _log('Ядро перестало работать — перезапуск ($_restarts из 3)');
        _restarting = true;
        try {
          await connect(
              remark: _lastRemark ?? '',
              config: _lastConfig!,
              settings: _lastSettings!);
          return;
        } catch (e) {
          _log('Перезапуск не удался: $e');
        } finally {
          _restarting = false;
        }
      }
      if (_lastSettings?.windowsKillSwitch == true && _proxySet) {
        // Kill switch: системный прокси остаётся на мёртвом порту —
        // трафик не пойдёт мимо VPN, пока пользователь не отключится сам.
        _log('Ядро не работает — интернет заблокирован (kill switch)');
        final p = _proc;
        _proc = null;
        if (p != null) Process.killPid(p.pid);
        _blocked = true;
        _stats.add(const ConnStats());
        _states.add(ConnState.connected);
      } else {
        _log('Ядро не работает — отключение');
        await disconnect();
      }
    } finally {
      _recovering = false;
    }
  }

  final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 1)
    ..findProxy = (_) => 'DIRECT';

  Future<(int, int)?> _queryStats() async {
    if (_blocked) return null;
    try {
      final req = await _http
          .getUrl(Uri.parse('http://127.0.0.1:$_apiPort/debug/vars'));
      final res = await req.close().timeout(const Duration(seconds: 2));
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final proxy = (j['stats']?['outbound']?['proxy'] as Map?) ?? const {};
      final up = (proxy['uplink'] as num?)?.toInt() ?? 0;
      final down = (proxy['downlink'] as num?)?.toInt() ?? 0;
      return (up, down);
    } catch (_) {
      return null;
    }
  }

  int _socksPort = kSocksPort;
  int _httpPort = kHttpPort;

  /// Адрес системного прокси — наш (на любом из портов Nexus).
  static bool isOwnProxy(String server) {
    const own = [kHttpPort, 20809, 30809];
    return own.any((p) => server.trim() == '127.0.0.1:$p') ||
        server.trim() == '127.0.0.1:$activeHttpPort';
  }

  Future<bool> _canBind(int port) async {
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await s.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<(int, int)> _pickPorts() async {
    for (final (a, b) in const [
      (kSocksPort, kHttpPort),
      (20808, 20809),
      (30808, 30809),
    ]) {
      if (await _canBind(a) && await _canBind(b)) return (a, b);
    }
    return (await _freePort(), await _freePort());
  }

  Future<int> _freePort() async {
    try {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final p = s.port;
      await s.close();
      return p;
    } catch (_) {
      return kApiPort;
    }
  }

  Future<bool> _portOpen(int port) async {
    try {
      final s = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 400));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopProcess() async {
    final p = _proc;
    _proc = null;
    if (p != null) {
      Process.killPid(p.pid);
    }
    await _killStrayCore();
  }

  /// Kill switch сработал: ядро остановлено, прокси указывает в никуда.
  bool _blocked = false;

  @override
  bool get blocked => _blocked;

  @override
  Future<void> disconnect() async {
    _watchdog?.cancel();
    _watchdog = null;
    _blocked = false;
    if (!_restarting) {
      _lastConfig = null;
      _lastSettings = null;
    }
    if (_proxySet) {
      final marker = File('$_dataDir\\proxy.lock');
      WinProxy.restore(_savedProxy ?? _readSaved(marker));
      _savedProxy = null;
      _proxySet = false;
      if (marker.existsSync()) marker.deleteSync();
    }
    await _stopProcess();
    _stats.add(const ConnStats());
    _states.add(ConnState.disconnected);
  }

  @override
  Future<T?> viaTunnel<T>(ServerProfile server, String config,
      Future<T> Function(String proxy) fn) async {
    if (!File(_corePath).existsSync()) return null;
    Process? p;
    try {
      final port = await _freePort();
      final rnd = math.Random.secure();
      String token() =>
          List.generate(16, (_) => rnd.nextInt(36).toRadixString(36)).join();
      final user = token(), pass = token();
      final cfg = jsonDecode(config) as Map<String, dynamic>;
      cfg['log'] = {'loglevel': 'none'};
      cfg['inbounds'] = [
        {
          'tag': 'tunnel',
          'listen': '127.0.0.1',
          'port': port,
          'protocol': 'http',
          'settings': {
            'accounts': [
              {'user': user, 'pass': pass}
            ],
          },
        }
      ];
      cfg['routing'] = {'domainStrategy': 'AsIs', 'rules': <dynamic>[]};
      cfg.remove('metrics');
      cfg.remove('stats');
      cfg.remove('api');
      p = await Process.start(
        _corePath,
        ['run', '-format', 'json', '-c', 'stdin:'],
        workingDirectory: _coreDir,
        environment: {'XRAY_LOCATION_ASSET': _assetDir},
      );
      p.stdout.drain<void>();
      p.stderr.drain<void>();
      p.stdin.add(utf8.encode(jsonEncode(cfg)));
      await p.stdin.close();
      var up = false;
      for (var i = 0; i < 40 && !up; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        up = await _portOpen(port);
      }
      if (!up) return null;
      return await fn('$user:$pass@127.0.0.1:$port');
    } finally {
      if (p != null) Process.killPid(p.pid);
    }
  }

  @override
  Future<Map<String, int>?> pingBatch(List<ServerProfile> servers,
      String Function(ServerProfile) config) async {
    if (servers.isEmpty || !File(_corePath).existsSync()) return null;
    Process? p;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final rnd = math.Random.secure();
      String token() =>
          List.generate(16, (_) => rnd.nextInt(36).toRadixString(36)).join();
      final user = token(), pass = token();
      final inbounds = <Map<String, dynamic>>[];
      final outbounds = <dynamic>[];
      final rules = <Map<String, dynamic>>[];
      final ports = <String, int>{};
      Map<String, dynamic>? base;
      for (var i = 0; i < servers.length; i++) {
        final s = servers[i];
        Map<String, dynamic> cfg;
        try {
          cfg = jsonDecode(config(s)) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        base ??= cfg;
        final ob = (cfg['outbounds'] as List? ?? []).firstWhere(
            (o) => o is Map && o['tag'] == 'proxy',
            orElse: () => null);
        if (ob is! Map<String, dynamic>) continue;
        final port = await _freePort();
        ports[s.id] = port;
        ob['tag'] = 'p$i';
        outbounds.add(ob);
        inbounds.add({
          'tag': 'in$i',
          'listen': '127.0.0.1',
          'port': port,
          'protocol': 'http',
          'settings': {
            'accounts': [
              {'user': user, 'pass': pass}
            ],
          },
        });
        rules.add({
          'type': 'field',
          'inboundTag': ['in$i'],
          'outboundTag': 'p$i',
        });
      }
      if (base == null || ports.isEmpty) return null;
      final cfg = <String, dynamic>{
        'log': {'loglevel': 'none', 'access': 'none'},
        'inbounds': inbounds,
        'outbounds': outbounds,
        'dns': base['dns'],
        'routing': {'domainStrategy': 'AsIs', 'rules': rules},
      }..removeWhere((_, v) => v == null);

      p = await Process.start(
        _corePath,
        ['run', '-format', 'json', '-c', 'stdin:'],
        workingDirectory: _coreDir,
        environment: {'XRAY_LOCATION_ASSET': _assetDir},
      );
      p.stdout.drain<void>();
      p.stderr.drain<void>();
      p.stdin.add(utf8.encode(jsonEncode(cfg)));
      await p.stdin.close();

      // Ждём последний порт: ядро открывает входы все сразу.
      final lastPort = ports.values.last;
      var up = false;
      for (var i = 0; i < 50 && !up; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        up = await _portOpen(lastPort);
      }
      if (!up) return null; // какой-то конфиг не принят — меряем по одному

      Future<int> measure(int port) async {
        try {
          return await _warmDelay('$user:$pass@127.0.0.1:$port');
        } catch (_) {
          return -1;
        }
      }

      final out = <String, int>{};
      final queue = ports.entries.toList();
      Future<void> worker() async {
        while (queue.isNotEmpty) {
          final e = queue.removeAt(0);
          out[e.key] = await measure(e.value);
        }
      }

      await Future.wait(List.generate(8, (_) => worker()));
      return out;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
      if (p != null) Process.killPid(p.pid);
    }
  }

  /// Реальная задержка: временный экземпляр ядра с этим сервером и
  /// HTTP-запрос через него. Работает для любых протоколов, в том числе
  /// Hysteria2 (UDP), где простой TCP-пинг показывает ерунду.
  @override
  Future<int> ping(ServerProfile server, String config) async {
    if (!File(_corePath).existsSync()) return tcpPing(server.host, server.port);
    Process? p;
    String? failReason;
    var probeOut = <String>[];
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final port = await _freePort();
      final rnd = math.Random.secure();
      String token() =>
          List.generate(16, (_) => rnd.nextInt(36).toRadixString(36)).join();
      final user = token(), pass = token();
      final cfg = jsonDecode(config) as Map<String, dynamic>;
      cfg['log'] = {'loglevel': 'warning'};
      cfg['inbounds'] = [
        {
          'tag': 'probe',
          'listen': '127.0.0.1',
          'port': port,
          'protocol': 'http',
          // Пароль, чтобы другие программы не воспользовались проверочным прокси.
          'settings': {
            'accounts': [
              {'user': user, 'pass': pass}
            ],
          },
        }
      ];
      // Весь трафик проверки — только через сервер.
      cfg['routing'] = {'domainStrategy': 'AsIs', 'rules': <dynamic>[]};
      cfg.remove('metrics');
      cfg.remove('stats');
      cfg.remove('api');

      p = await Process.start(
        _corePath,
        ['run', '-format', 'json', '-c', 'stdin:'],
        workingDirectory: _coreDir,
        environment: {'XRAY_LOCATION_ASSET': _assetDir},
      );
      // Вывод ядра проверки сохраняем: при неудаче причина попадёт в журнал.
      final out = <String>[];
      void collect(Stream<List<int>> st) => st
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((l) {
            if (out.length < 40) out.add(l);
          });
      collect(p.stdout);
      collect(p.stderr);
      probeOut = out;
      p.stdin.add(utf8.encode(jsonEncode(cfg)));
      await p.stdin.close();

      var up = false;
      for (var i = 0; i < 40 && !up; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        up = await _portOpen(port);
      }
      if (!up) {
        failReason = 'ядро не запустилось';
        return -1;
      }

      return await _warmDelay('$user:$pass@127.0.0.1:$port');
    } catch (e) {
      failReason = e is TimeoutException ? 'сервер не ответил за 6 с' : '$e';
      return -1;
    } finally {
      client.close(force: true);
      if (p != null) Process.killPid(p.pid);
      if (failReason != null) {
        final why = probeOut
            .where((l) =>
                l.contains('[Warning]') ||
                l.contains('[Error]') ||
                l.contains('Failed') ||
                l.contains('failed'))
            .map((l) => l.replaceFirst(
                RegExp(r'^\d{4}/\d\d/\d\d [\d:.]+ '), ''))
            .where((l) => !l.contains('core: Xray'))
            .take(3)
            .join(' | ');
        _log('Проверка «${server.cleanName}» (${server.protocol}): '
            '$failReason${why.isEmpty ? '' : ' — $why'}');
      }
    }
  }

  /// Реальная задержка через туннель: HTTP-запрос через локальный прокси.
  @override
  Future<int> connectedDelay(ServerProfile server) async {
    try {
      return await _warmDelay('127.0.0.1:$_httpPort',
          timeout: const Duration(seconds: 8));
    } catch (_) {
      return -1;
    }
  }

  /// Задержка через прокси так же, как её меряют VPN-клиенты («real delay»),
  /// но без рукопожатий: два HTTPS-запроса по одному туннелю, в ответ —
  /// время второго. Первый открывает соединение с сервером, TLS и прочее;
  /// второй показывает чистое время «туда-обратно» через сервер —
  /// одинаково честно для VLESS, Trojan и Hysteria2.
  Future<int> _warmDelay(String proxy,
      {Duration timeout = const Duration(seconds: 6)}) async {
    final c = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 15)
      ..findProxy = (_) => 'PROXY $proxy';
    Future<int> once() async {
      final sw = Stopwatch()..start();
      final req = await c
          .getUrl(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(timeout);
      req.persistentConnection = true;
      final res = await req.close().timeout(timeout);
      await res.drain<void>().timeout(timeout);
      if (res.statusCode >= 400) throw Exception('HTTP ${res.statusCode}');
      return sw.elapsedMilliseconds;
    }

    try {
      final first = await once();
      int? second;
      try {
        second = await once();
      } catch (_) {}
      return (second ?? first).clamp(1, 9999);
    } finally {
      c.close(force: true);
    }
  }


  @override
  Future<String> coreVersion() => _versionOf(_corePath);

  Future<String> _versionOf(String exe) async {
    try {
      if (!File(exe).existsSync()) return 'не найдено';
      final p = await Process.start(exe, ['version'],
          mode: ProcessStartMode.detachedWithStdio);
      final out = await p.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 3));
      final m = RegExp(r'Xray\s+([\d.]+)').firstMatch(out);
      return m != null ? 'Xray ${m.group(1)}' : out.split('\n').first.trim();
    } catch (_) {
      return '—';
    }
  }

  // ───────────────────── автообновление ядра Xray ─────────────────────

  static const _releaseApi =
      'https://api.github.com/repos/XTLS/Xray-core/releases/latest';
  static const _geoBase =
      'https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download';
  static const _newExe = 'nexus-core-new.exe';

  @override
  bool get canUpdateCore => true;

  bool get _running => _proc != null;

  /// Сравнение версий вида 26.10.21 / v26.10.21.
  static List<int> _ver(String s) => RegExp(r'\d+')
      .allMatches(s)
      .take(4)
      .map((m) => int.parse(m.group(0)!))
      .toList();

  static bool _newer(String a, String b) {
    final x = _ver(a), y = _ver(b);
    for (var i = 0; i < math.max(x.length, y.length); i++) {
      final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
      if (p != q) return p > q;
    }
    return false;
  }

  Future<List<int>> _download(String url) async {
    final r = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'Nexus',
    }).timeout(const Duration(minutes: 3));
    if (r.statusCode != 200) {
      throw Exception('GitHub ответил ${r.statusCode} на $url');
    }
    return r.bodyBytes;
  }

  @override
  Future<String> updateCore({bool force = false}) async {
    final res = await http.get(Uri.parse(_releaseApi), headers: {
      'User-Agent': 'Nexus',
      'Accept': 'application/vnd.github+json',
    }).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Не удалось узнать последнюю версию (код ${res.statusCode})');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] ?? '').toString();
    final current = await coreVersion();
    if (!force && !_newer(tag, current)) {
      return 'Установлена последняя версия';
    }

    String? url, dgstUrl;
    for (final a in (j['assets'] as List? ?? [])) {
      final name = a['name'];
      final link = a['browser_download_url']?.toString();
      if (link == null || !link.startsWith('https://github.com/XTLS/')) continue;
      if (name == 'Xray-windows-64.zip') url = link;
      if (name == 'Xray-windows-64.zip.dgst') dgstUrl = link;
    }
    if (url == null || dgstUrl == null) {
      throw Exception('В релизе $tag нет сборки для Windows');
    }

    final dir = Directory(_updDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    // Проверяем контрольную сумму из официального файла .dgst релиза.
    final zipBytes = await _download(url);
    final dgst = utf8.decode(await _download(dgstUrl), allowMalformed: true);
    final want = RegExp(r'SHA2-256=\s*([0-9a-fA-F]{64})')
        .firstMatch(dgst)
        ?.group(1)
        ?.toLowerCase();
    final got = sha256.convert(zipBytes).toString();
    if (want == null || want != got) {
      throw Exception('Контрольная сумма ядра не совпала — обновление отменено');
    }

    final zip = ZipDecoder().decodeBytes(zipBytes);
    ArchiveFile? exe;
    for (final f in zip.files) {
      if (f.isFile && f.name.toLowerCase() == 'xray.exe') exe = f;
    }
    if (exe == null) throw Exception('В архиве нет xray.exe');
    final staged = File('$_updDir\\$_newExe');
    await staged.writeAsBytes(exe.content as List<int>, flush: true);

    // Проверяем, что скачанное ядро вообще запускается.
    final v = await _versionOf(staged.path);
    if (!v.startsWith('Xray')) {
      await staged.delete();
      throw Exception('Скачанное ядро не запускается');
    }

    // Свежие гео-базы для умного режима — тоже с проверкой SHA-256.
    for (final g in ['geoip.dat', 'geosite.dat']) {
      try {
        final data = await _download('$_geoBase/$g');
        final sum = utf8
            .decode(await _download('$_geoBase/$g.sha256sum'))
            .trim()
            .split(RegExp(r'\s+'))
            .first
            .toLowerCase();
        if (sha256.convert(data).toString() == sum) {
          await File('$_updDir\\$g.new').writeAsBytes(data, flush: true);
        } else {
          _log('Гео-база $g не прошла проверку и пропущена');
        }
      } catch (_) {}
    }

    if (_running) {
      return 'Загружено $v — применится при следующем подключении';
    }
    await _applyPendingUpdate();
    return 'Ядро обновлено до $v';
  }

  /// Подменяет ядро и гео-базы скачанными файлами (только когда ядро не запущено).
  Future<void> _applyPendingUpdate() async {
    try {
      final staged = File('$_updDir\\$_newExe');
      if (staged.existsSync()) {
        final target = File('$_updDir\\$kCoreExe');
        if (target.existsSync()) target.deleteSync();
        staged.renameSync(target.path);
      }
      for (final g in ['geoip.dat', 'geosite.dat']) {
        final n = File('$_updDir\\$g.new');
        if (n.existsSync()) {
          final t = File('$_updDir\\$g');
          if (t.existsSync()) t.deleteSync();
          n.renameSync(t.path);
        } else if (!File('$_updDir\\$g').existsSync() &&
            File('$_exeDir\\$g').existsSync() &&
            File('$_updDir\\$kCoreExe').existsSync()) {
          File('$_exeDir\\$g').copySync('$_updDir\\$g');
        }
      }
    } catch (e) {
      _log('Не удалось применить обновление ядра: $e');
    }
  }

  Map<String, dynamic>? _savedProxy;

  Map<String, dynamic>? _readSaved(File marker) {
    try {
      final j = jsonDecode(marker.readAsStringSync());
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null; // старый формат файла («1») — просто выключаем прокси
    }
  }

  @override
  Future<void> dispose() => disconnect();
}

/// Системный прокси Windows через реестр + уведомление WinINet.
class WinProxy {
  static const _path =
      r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  // HKEY_CURRENT_USER = (HKEY)(ULONG_PTR)(LONG)0x80000001 — со знаковым расширением.
  static const _hkcu = -2147483647;
  static const _regSz = 1;
  static const _regDword = 4;

  static final _advapi = DynamicLibrary.open('advapi32.dll');
  static final _wininet = DynamicLibrary.open('wininet.dll');

  static final _regSet = _advapi.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32,
          Pointer<Void>, Uint32),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>,
          int)>('RegSetKeyValueW');

  static final _inetSet = _wininet.lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Uint32),
      int Function(
          Pointer<Void>, int, Pointer<Void>, int)>('InternetSetOptionW');

  static void _setDword(String name, int value) {
    final sub = _path.toNativeUtf16();
    final n = name.toNativeUtf16();
    final data = calloc<Uint32>()..value = value;
    try {
      _regSet(_hkcu, sub, n, _regDword, data.cast(), 4);
    } finally {
      calloc.free(sub);
      calloc.free(n);
      calloc.free(data);
    }
  }

  static void _setString(String name, String value) {
    final sub = _path.toNativeUtf16();
    final n = name.toNativeUtf16();
    final data = value.toNativeUtf16();
    try {
      _regSet(_hkcu, sub, n, _regSz, data.cast(), (value.length + 1) * 2);
    } finally {
      calloc.free(sub);
      calloc.free(n);
      calloc.free(data);
    }
  }

  static void _notify() {
    // INTERNET_OPTION_SETTINGS_CHANGED = 39, INTERNET_OPTION_REFRESH = 37
    _inetSet(nullptr, 39, nullptr, 0);
    _inetSet(nullptr, 37, nullptr, 0);
  }

  static final _regGet = _advapi.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32,
          Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>,
          Pointer<Void>, Pointer<Uint32>)>('RegGetValueW');

  static int? _getDword(String name) {
    final sub = _path.toNativeUtf16();
    final n = name.toNativeUtf16();
    final data = calloc<Uint32>();
    final size = calloc<Uint32>()..value = 4;
    try {
      // RRF_RT_REG_DWORD = 0x10
      final r = _regGet(_hkcu, sub, n, 0x10, nullptr, data.cast(), size);
      return r == 0 ? data.value : null;
    } finally {
      calloc.free(sub);
      calloc.free(n);
      calloc.free(data);
      calloc.free(size);
    }
  }

  static String? _getString(String name) {
    final sub = _path.toNativeUtf16();
    final n = name.toNativeUtf16();
    const cap = 8192;
    final data = calloc<Uint16>(cap ~/ 2);
    final size = calloc<Uint32>()..value = cap;
    try {
      // RRF_RT_REG_SZ = 0x2
      final r = _regGet(_hkcu, sub, n, 0x2, nullptr, data.cast(), size);
      return r == 0 ? data.cast<Utf16>().toDartString() : null;
    } finally {
      calloc.free(sub);
      calloc.free(n);
      calloc.free(data);
      calloc.free(size);
    }
  }

  /// Текущие настройки прокси пользователя.
  static Map<String, dynamic> snapshot() {
    try {
      return {
        'enable': _getDword('ProxyEnable') ?? 0,
        'server': _getString('ProxyServer'),
        'override': _getString('ProxyOverride'),
      };
    } catch (_) {
      return {'enable': 0};
    }
  }

  /// Возвращает прокси пользователя; без сохранённых данных — просто выключает.
  static void restore(Map<String, dynamic>? saved) {
    if (saved == null) return disable();
    try {
      final server = saved['server'];
      final ovr = saved['override'];
      // Не восстанавливаем собственный адрес Nexus (остался после сбоя).
      final ours = server is String && WindowsCore.isOwnProxy(server);
      if (server is String && !ours) _setString('ProxyServer', server);
      if (ovr is String) _setString('ProxyOverride', ovr);
      _setDword('ProxyEnable', saved['enable'] == 1 && !ours ? 1 : 0);
      _notify();
    } catch (_) {
      disable();
    }
  }

  static void enable(String server) {
    try {
      _setString('ProxyServer', server);
      _setString(
          'ProxyOverride',
          [
            'localhost',
            '127.*',
            '10.*',
            for (var i = 16; i <= 31; i++) '172.$i.*',
            '192.168.*',
            '*.local',
            '<local>',
          ].join(';'));
      _setDword('ProxyEnable', 1);
      _notify();
    } catch (_) {}
  }

  static void disable() {
    try {
      _setDword('ProxyEnable', 0);
      _notify();
    } catch (_) {}
  }
}
