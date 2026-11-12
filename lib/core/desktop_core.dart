import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../platform/win_admin.dart';
import '../services/config_builder.dart';
import 'desktop_os.dart';
import 'vpn_core.dart';
import '../l10n.dart';

export 'desktop_os.dart' show kCoreExe;

const kApiPort = 10085;

/// Компьютеры (Windows, Linux, macOS): ядро Xray рядом с Nexus + системный
/// прокси или режим TUN. Различия систем — в [DesktopOs].
class DesktopCore extends VpnCore {
  final DesktopOs os = DesktopOs.current;
  String get _sep => os.sep;

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
  String _apiAuth = '';

  /// «логин:пароль@» HTTP-прокси в режиме TUN, иначе пусто.
  String _httpAuth = '';

  @override
  bool get httpLocked => _proc != null && _httpAuth.isNotEmpty;

  @override
  void setForeground(bool visible) => _foreground = visible;

  Map<String, int> _autoStatus = const {};

  @override
  Map<String, int> get autoStatus => _proc == null ? const {} : _autoStatus;

  @override
  String? get activeProxy =>
      _proc != null && !_blocked ? '${_httpAuth}127.0.0.1:$activeHttpPort' : null;

  String get _exeDir => os.exeDir;

  /// Ядро из сборки (для режима TUN на Linux/macOS — только оно).
  String get _bundledCore => '$_exeDir$_sep$kCoreExe';

  /// Папка обновляемого ядра (Windows: %APPDATA%\\Nexus\\core).
  String get _updDir => '$_dataDir${_sep}core';

  /// Если ядро уже обновлялось — берём обновлённое, иначе встроенное.
  String get _coreDir =>
      File('$_updDir${_sep}$kCoreExe').existsSync() ? _updDir : _exeDir;
  String get _corePath => '$_coreDir${_sep}$kCoreExe';

  // ── Права администратора (режим TUN) ──
  // Nexus стоит в папке пользователя, куда может писать любая его
  // программа. Чтобы подменённое ядро не получило права администратора,
  // с правами администратора ядро запускается только проверенное (та же
  // SHA-256, что у ядра из сборки) и из папки, куда пишут лишь
  // администраторы (Program Files\Nexus\core).
  static const _coreSha = DesktopOs.coreSha;
  static const _wintunSha = String.fromEnvironment('WINTUN_SHA256');
  String? _safeDir;

  String get _runDir => _safeDir ?? _coreDir;

  /// Путь к ядру для запуска; с правами администратора — проверенная копия.
  Future<String> _runCore() async {
    if (Platform.isWindows &&
        WinAdmin.isAdmin &&
        _coreSha.isNotEmpty &&
        _safeDir == null) {
      await _prepareSafeCore();
    }
    return '$_runDir${_sep}$kCoreExe';
  }

  Future<void> _prepareSafeCore() async {
    final pf = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final dir = Directory('$pf${_sep}Nexus${_sep}core');
    Future<void> put(String name, String want) async {
      final src = File('$_exeDir${_sep}$name');
      if (!src.existsSync()) {
        if (name == kCoreExe) throw Exception(tr('Не найдено ядро {0} рядом с программой. Переустановите Nexus из архива целиком.', [kCoreExe]));
        return;
      }
      final bytes = await src.readAsBytes();
      if (sha256.convert(bytes).toString() != want) {
        throw Exception(tr('Файл {0} изменён после установки — запуск с правами администратора отменён. Переустановите Nexus', [name]));
      }
      final dst = File('${dir.path}${_sep}$name');
      if (dst.existsSync() &&
          sha256.convert(await dst.readAsBytes()).toString() == want) {
        return;
      }
      await dst.writeAsBytes(bytes, flush: true);
    }

    // Проверяем байты, которые сами же и записываем: подменить файл между
    // проверкой и запуском нельзя — в Program Files пишут только администраторы.
    try {
      await dir.create(recursive: true);
      await put(kCoreExe, _coreSha);
      if (_wintunSha.isNotEmpty) await put('wintun.dll', _wintunSha);
    } on FileSystemException catch (e) {
      throw Exception(tr('Не удалось подготовить ядро в {0}: {1}', [dir.path, e.osError?.message ?? e.message]));
    }
    _safeDir = dir.path;
    _log(tr('Права администратора: ядро запускается из защищённой папки'));
  }
  String get _assetDir =>
      File('$_coreDir${_sep}geoip.dat').existsSync() ? _coreDir : os.resDir;

  String get _dataDir => os.dataDir;

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

  /// Запуск «nexus.exe --restore-proxy» (удаление программы): вернуть
  /// системный прокси пользователя, если Nexus оставил свой.
  static Future<void> restoreProxyOnly() async {
    try {
      final os = DesktopOs.current;
      final marker =
          File('${os.dataDir}${Platform.pathSeparator}proxy.lock');
      if (!marker.existsSync()) return;
      Map<String, dynamic>? saved;
      try {
        final j = jsonDecode(marker.readAsStringSync());
        if (j is Map<String, dynamic>) saved = j;
      } catch (_) {}
      await os.proxyRestore(saved);
      marker.deleteSync();
    } catch (_) {}
  }

  @override
  Future<void> init() async {
    await os.harden();
    // Убираем «хвосты» после аварийного завершения: старое ядро и прокси.
    await _killStrayCore();
    final marker = File('$_dataDir${_sep}proxy.lock');
    if (marker.existsSync()) {
      await os.proxyRestore(_readSaved(marker));
      marker.deleteSync();
    }
    // Блокировка kill switch осталась после сбоя — снимаем, как и прокси.
    await _killSwitchOff();
  }

  Future<void> _killStrayCore() => os.killStrayCore();

  String _withStats(String config) {
    final cfg = jsonDecode(config) as Map<String, dynamic>;
    for (final ib in (cfg['inbounds'] as List? ?? [])) {
      if (ib is! Map<String, dynamic>) continue;
      if (ib['tag'] == 'socks-in') ib['port'] = _socksPort;
      if (ib['tag'] == 'http-in') ib['port'] = _httpPort;
    }
    if (_tun) _addTun(cfg);
    // В режиме TUN системный прокси не нужен: все программы и так идут
    // через Nexus. Тогда HTTP-прокси закрываем случайным паролем (новым при
    // каждом подключении) — им пользуется только сам Nexus для проверок.
    _httpAuth = '';
    if (_tun) {
      final r = math.Random.secure();
      String tok() => List.generate(
          20, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[r.nextInt(32)]).join();
      final u = tok(), p = tok();
      for (final ib in (cfg['inbounds'] as List? ?? [])) {
        if (ib is Map<String, dynamic> && ib['tag'] == 'http-in') {
          ib['settings'] = {
            'accounts': [
              {'user': u, 'pass': p},
            ],
          };
        }
      }
      _httpAuth = '$u:$p@';
    }
    cfg['stats'] = <String, dynamic>{};
    // Статистика по HTTP (/debug/vars) — через отдельный вход с паролем,
    // новым при каждом подключении: другие программы её не прочитают.
    final r = math.Random.secure();
    String tok() => List.generate(
        20, (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[r.nextInt(32)]).join();
    final user = tok(), pass = tok();
    _apiAuth = '$user:$pass';
    (cfg['inbounds'] as List).add({
      'tag': 'nexus-api',
      'listen': '127.0.0.1',
      'port': _apiPort,
      'protocol': 'http',
      'settings': {
        'accounts': [
          {'user': user, 'pass': pass},
        ],
      },
    });
    addPrivateMetrics(cfg, 'nexus-api');
    cfg['policy'] = {
      'system': {
        'statsOutboundUplink': true,
        'statsOutboundDownlink': true,
      },
    };
    return jsonEncode(cfg);
  }

  /// Подключения и отключения идут строго по очереди: два одновременных
  /// запуска (переподключение + обновление подписки) раньше писали в один
  /// и тот же процесс ядра и падали с «StreamSink is bound to a stream».
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final next = _queue.then((_) => op());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  @override
  Future<void> connect({
    required String remark,
    required String config,
    required AppSettings settings,
  }) =>
      _serial(() =>
          _connect(remark: remark, config: config, settings: settings));

  @override
  bool get swapsInPlace => true;

  @override
  bool get tunActive => _tun && _proc != null;

  /// Возвращает системный прокси пользователя (если Nexus его менял).
  Future<void> _dropProxy() async {
    if (!_proxySet) return;
    final marker = File('$_dataDir${_sep}proxy.lock');
    await os.proxyRestore(_savedProxy ?? _readSaved(marker));
    _savedProxy = null;
    _proxySet = false;
    if (marker.existsSync()) marker.deleteSync();
  }

  Future<void> _connect({
    required String remark,
    required String config,
    required AppSettings settings,
  }) async {
    try {
      await _connectInner(remark: remark, config: config, settings: settings);
      return;
    } catch (_) {
      if (!(_tun && (os.tunDnsToGateway || os.tunIpv6))) {
        if (_keepBlocked()) return;
        await _afterFailedConnect();
        rethrow;
      }
    }
    // Linux и macOS: ядро не поднялось с IPv6 или системным DNS в туннеле —
    // пробуем ещё раз по-старому, только с IPv4.
    os.tunPlain = true;
    try {
      await _connectInner(remark: remark, config: config, settings: settings);
      _log(tr('Системный DNS не удалось направить в туннель — подключаюсь без этого'));
    } catch (_) {
      // Дело было не в них — в следующий раз пробуем с защитой снова.
      os.tunPlain = false;
      if (_keepBlocked()) return;
      await _afterFailedConnect();
      rethrow;
    }
  }

  /// Смена сервера «на месте» не удалась: прокси от прошлого соединения
  /// указывал бы в никуда при статусе «Не подключено». При перезапуске
  /// после сбоя прокси не трогаем — это решает kill switch.
  Future<void> _afterFailedConnect() async {
    if (_restarting) return;
    try {
      await _dropProxy();
    } catch (_) {}
  }

  /// Новое ядро не запустилось, а kill switch уже стоит (смена сервера в
  /// режиме TUN): блокировку не снимаем — интернет закрыт, пока
  /// пользователь не отключится сам. true — так и сделали.
  bool _keepBlocked() {
    if (_restarting || !os.killSwitchActive) return false;
    _log(tr('Новое ядро не запустилось — интернет заблокирован (kill switch). Нажмите «Отключить», чтобы снять блокировку'));
    _blocked = true;
    _stats.add(const ConnStats());
    _states.add(ConnState.connected);
    return true;
  }

  Future<void> _connectInner({
    required String remark,
    required String config,
    required AppSettings settings,
  }) async {
    if (!File(_corePath).existsSync()) {
      throw Exception(tr('Не найдено ядро {0} рядом с программой. Переустановите Nexus из архива целиком.', [kCoreExe]));
    }
    _states.add(ConnState.connecting);
    // Смена ядра: блокировка трафика (kill switch) остаётся на месте.
    await _stopProcess(keepBlock: true);
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
    _log(tr('Запуск ядра: {0}', [remark]));
    final String corePath;
    try {
      corePath = await _runCore();
    } catch (e) {
      _states.add(ConnState.disconnected);
      rethrow;
    }
    _tun = false;
    _modeWarning = null;
    if (settings.windowsTun && !Platform.isWindows) {
      // Linux / macOS: права нужны только ядру, а не всему Nexus.
      final why = await os.tunBlocker();
      if (why != null) {
        _modeWarning = tr('{0} — пока Nexus работает через системный прокси', [why]);
      } else {
        try {
          final c = await os.prepareTun(_bundledCore);
          _tunCore = c;
          _tun = true;
          _log(tr('Режим TUN: весь трафик компьютера идёт через Nexus'));
        } catch (e) {
          _modeWarning = tr('{0} — пока Nexus работает через системный прокси',
              ['$e'.replaceFirst('Exception: ', '')]);
        }
      }
      if (_modeWarning != null) _log(_modeWarning!);
    } else if (settings.windowsTun) {
      if (!WinAdmin.isAdmin) {
        _modeWarning = tr('Режим TUN работает только с правами администратора — пока Nexus работает через системный прокси. Включите TUN в настройках ещё раз, чтобы перезапустить Nexus от администратора');
      } else if (!_ensureWintun()) {
        _modeWarning = tr('Нет файла wintun.dll рядом с ядром — режим TUN недоступен, работаю через системный прокси. Переустановите Nexus');
      } else {
        _tun = true;
        _log(tr('Режим TUN: весь трафик компьютера идёт через Nexus'));
      }
      if (_modeWarning != null) _log(_modeWarning!);
    }
    if (sp != kSocksPort) {
      _log(tr('Порты {0}/{1} заняты другой программой (например, Happ или v2rayN) — Nexus использует {2}/{3}', [kSocksPort, kHttpPort, sp, hp]));
    }
    os.killSwitchWanted =
        _tun && settings.windowsKillSwitch && os.killSwitchSupported;
    try {
      final full = _withStats(config);
      final special = _tun ? os.startTun(_tunCore!, full, _assetDir) : null;
      if (special != null) {
        // macOS: ядро от root после окна с паролем администратора.
        _proc = await special;
      } else {
        // Конфиг с ключами передаётся через stdin и никогда не пишется на диск.
        final started = await Process.start(
          _tun && _tunCore != null ? _tunCore! : corePath,
          ['run', '-format', 'json', '-c', 'stdin:'],
          workingDirectory: _tun && _tunCore != null
              ? File(_tunCore!).parent.path
              : _runDir,
          environment: {'XRAY_LOCATION_ASSET': _assetDir},
        );
        _proc = started;
        // Пишем в «свой» процесс, а не в поле _proc — его мог сменить
        // другой запуск.
        started.stdin.add(utf8.encode(full));
        await started.stdin.flush();
        await started.stdin.close();
      }
    } catch (e) {
      _states.add(ConnState.disconnected);
      throw Exception(tr('Не удалось запустить ядро: {0}', [e]));
    }
    final proc = _proc!;
    // Ядро завершилось само — сразу реагируем, не дожидаясь проверки порта.
    proc.exitCode.then((code) {
      if (identical(_proc, proc) && _watchdog != null) {
        _log(tr('Ядро завершилось (код {0})', [code]));
        _exited = true;
        _tick();
      }
    });
    proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_log);
    proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_log);

    // Ждём, пока ядро откроет локальный порт. На macOS в режиме TUN
    // сначала вводят пароль — ждём, пока открыто окно ввода (до 2 минут).
    var up = false;
    var gone = false;
    unawaited(proc.exitCode.then((_) => gone = true));
    final tries = _tun && !Platform.isWindows && Platform.isMacOS ? 600 : 25;
    for (var i = 0; i < tries && !up && !(gone && i > 2); i++) {
      await Future.delayed(const Duration(milliseconds: 200));
      up = await _portOpen(_httpPort);
    }
    // Старый файл конфига от прошлых версий — удаляем.
    try {
      final old = File('$_dataDir${_sep}config.json');
      if (old.existsSync()) old.deleteSync();
    } catch (_) {}
    if (!up) {
      await _stopProcess();
      _states.add(ConnState.disconnected);
      await _rollbackCore(config);
      final tail = _logs.reversed.take(3).toList().reversed.join('\n');
      throw Exception(
          tr('Ядро не запустилось.{0}', [tail.isEmpty ? '' : '\n$tail']));
    }

    // В режиме TUN системный прокси не нужен: трафик и так идёт через ядро.
    if (settings.windowsSystemProxy && !_tun) {
      // Запоминаем прокси, который был у пользователя до Nexus, —
      // при отключении (и после сбоя) вернём именно его.
      final marker = File('$_dataDir${_sep}proxy.lock');
      if (!marker.existsSync()) {
        _savedProxy = await os.proxySnapshot();
        marker.writeAsStringSync(jsonEncode(_savedProxy));
      }
      try {
        await os.proxyEnable('127.0.0.1:$_httpPort');
      } catch (e) {
        _modeWarning = '$e'.replaceFirst('Exception: ', '');
        _log(_modeWarning!);
      }
      _proxySet = true;
    } else {
      // Перешли на TUN или выключили системный прокси — возвращаем прежний.
      await _dropProxy();
    }

    // Kill switch в режиме TUN: правила файрвола, которые переживают падение
    // ядра. Не получилось — VPN работает, но без этой защиты (в журнал).
    if (os.killSwitchWanted) {
      try {
        await os.killSwitchOn(
          core: _tunCore ?? corePath,
          servers: await _serverIps(config),
          dns: Platform.isLinux ? await LinuxOs.systemDns() : const [],
        );
        _log(tr('Kill switch: трафик мимо туннеля заблокирован'));
      } catch (e) {
        _modeWarning = '$e'.replaceFirst('Exception: ', '');
        _log(_modeWarning!);
      }
    } else {
      await _killSwitchOff();
    }

    _knownConfig = config;
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
    // Минута стабильной работы после перезапуска — счётчик сбрасывается:
    // редкие сбои за долгий день не исчерпывают три попытки.
    if (_tickN == 60 && !_exited) _restarts = 0;
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
    // Статистику запрашиваем раз в 2 секунды, когда окно открыто, и раз
    // в 30 секунд в трее — для учёта трафика по дням.
    if (_tickN.isOdd || (!_foreground && _tickN % 30 != 0)) return;
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
        _log(tr('Ядро перестало работать — перезапуск ({0} из 3)', [_restarts]));
        _restarting = true;
        try {
          await connect(
              remark: _lastRemark ?? '',
              config: _lastConfig!,
              settings: _lastSettings!);
          return;
        } catch (e) {
          _log(tr('Перезапуск не удался: {0}', [e]));
        } finally {
          _restarting = false;
        }
      }
      if ((_lastSettings?.windowsKillSwitch == true && _proxySet) ||
          (_tun && os.killSwitchActive)) {
        // Kill switch: системный прокси остаётся на мёртвом порту —
        // трафик не пойдёт мимо VPN, пока пользователь не отключится сам.
        _log(tr('Ядро не работает — интернет заблокирован (kill switch)'));
        final p = _proc;
        _proc = null;
        if (p != null) Process.killPid(p.pid);
        _blocked = true;
        _stats.add(const ConnStats());
        _states.add(ConnState.connected);
      } else {
        _log(tr('Ядро не работает — отключение'));
        await disconnect();
      }
    } finally {
      _recovering = false;
    }
  }

  late final _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 1)
    ..findProxy = (_) => 'PROXY $_apiAuth@127.0.0.1:$_apiPort';

  Future<(int, int)?> _queryStats() async {
    if (_blocked) return null;
    try {
      final req = await _http
          .getUrl(Uri.parse('http://$kMetricsHost/debug/vars'));
      final res = await req.close().timeout(const Duration(seconds: 2));
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      _autoStatus = parseObservatory(j['observatory']);
      // Один сервер — исходящий «proxy», режим «Авто» — «nx-0», «nx-1»…
      final all = (j['stats']?['outbound'] as Map?) ?? const {};
      var up = 0, down = 0;
      all.forEach((tag, v) {
        if (v is! Map) return;
        if (tag != 'proxy' && !'$tag'.startsWith(kAutoPrefix)) return;
        up += (v['uplink'] as num?)?.toInt() ?? 0;
        down += (v['downlink'] as num?)?.toInt() ?? 0;
      });
      return (up, down);
    } catch (_) {
      return null;
    }
  }

  bool _tun = false;
  String? _modeWarning;

  /// Linux/macOS: ядро для режима TUN (проверенная копия).
  String? _tunCore;

  @override
  String? get modeWarning => _modeWarning;

  /// wintun.dll должен лежать рядом с запускаемым ядром. Ядро после
  /// автообновления живёт в папке данных — копируем библиотеку туда.
  bool _ensureWintun() {
    try {
      final target = File('$_runDir${_sep}wintun.dll');
      if (target.existsSync()) return true;
      final src = File('$_exeDir${_sep}wintun.dll');
      if (!src.existsSync()) return false;
      src.copySync(target.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Режим TUN: виртуальная сетевая карта «Nexus», весь IPv4-трафик —
  /// в ядро. Ядро само держит свои соединения вне TUN (autoOutboundsInterface)
  /// и через фильтры Windows не выпускает DNS и IPv6 мимо туннеля.
  void _addTun(Map<String, dynamic> cfg) {
    final inbounds = (cfg['inbounds'] as List?) ?? [];
    inbounds.insert(0, {
      'tag': 'tun-in',
      'protocol': 'tun',
      'port': 0,
      'settings': {
        'name': os.tunName,
        ...os.tunExtra(),
        // 1400: с запасом на заголовки туннеля, без дробления пакетов.
        'mtu': 1400,
        // Windows: IPv6 целиком закрыт фильтрами ядра (misconfigtun).
        // Linux и macOS: IPv6 заводим в туннель, иначе он шёл бы мимо VPN.
        'gateway': [
          '172.19.0.1/30',
          if (os.tunIpv6) 'fd19:6e78::1/126',
        ],
        // DNS для программ — обычный адрес выбранного сервиса.
        'dns': [
          ((cfg['dns'] as Map?)?['servers'] as List?)
                  ?.whereType<String>()
                  .where((e) => !e.contains('://'))
                  .firstOrNull ??
              '1.1.1.1'
        ],
        'autoSystemRoutingTable': [
          '0.0.0.0/0',
          if (os.tunIpv6) '::/0',
        ],
      },
      'sniffing': {
        'enabled': true,
        'destOverride': ['http', 'tls', 'quic'],
        'routeOnly': true,
      },
    });
    cfg['inbounds'] = inbounds;
    final outbounds = (cfg['outbounds'] as List?) ?? [];
    outbounds.add({'tag': 'dns-out', 'protocol': 'dns'});
    // Linux, kill switch: соединения ядра помечаются — файрвол их пропускает.
    final mark = os.coreMark;
    if (mark != null) {
      for (final ob in outbounds) {
        if (ob is! Map) continue;
        final ss = (ob['streamSettings'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        final so = (ss['sockopt'] as Map?)?.cast<String, dynamic>() ??
            <String, dynamic>{};
        so['mark'] = mark;
        ss['sockopt'] = so;
        ob['streamSettings'] = ss;
      }
    }
    cfg['outbounds'] = outbounds;
    final routing = (cfg['routing'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final rules = (routing['rules'] as List?) ?? [];
    // DNS-запросы программ — во встроенный DNS ядра (он ходит через сервер).
    rules.insert(0, {
      'type': 'field',
      'inboundTag': ['tun-in'],
      'port': '53',
      'outboundTag': 'dns-out',
    });
    routing['rules'] = rules;
    cfg['routing'] = routing;
  }

  /// В режиме TUN временные ядра проверки задержки привязываем к обычной
  /// сетевой карте — иначе их трафик ушёл бы в туннель через текущий сервер
  /// и задержка всех серверов оказалась бы завышенной.
  Future<void> _bypassTun(List? outbounds, {String? iface}) async {
    // При kill switch трафик мимо туннеля запрещён — проверки идут через
    // туннель (задержка чуть выше, зато ничего не утекает).
    if (!_tun || outbounds == null || os.killSwitchActive) return;
    iface ??= await _physicalInterface();
    if (iface == null) return;
    for (final ob in outbounds) {
      if (ob is! Map<String, dynamic>) continue;
      final ss = (ob['streamSettings'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final so = (ss['sockopt'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      so['interface'] = iface;
      ss['sockopt'] = so;
      ob['streamSettings'] = ss;
    }
  }

  Future<String?> _physicalInterface() async {
    try {
      for (final i in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false)) {
        final n = i.name.toLowerCase();
        if (n == 'nexus' ||
            n == os.tunName.toLowerCase() ||
            n.startsWith('utun') ||
            n.startsWith('tun') ||
            n.contains('wintun') ||
            n.contains('vpn')) {
          continue;
        }
        if (i.addresses.any((a) =>
            !a.isLinkLocal && !a.address.startsWith('172.19.0.'))) {
          return i.name;
        }
      }
    } catch (_) {}
    return null;
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

  Future<void> _stopProcess({bool keepBlock = false}) async {
    final p = _proc;
    _proc = null;
    if (_tun && !Platform.isWindows) await os.stopTun(keepBlock: keepBlock);
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
  Future<void> disconnect() => _serial(_disconnect);

  Future<void> _disconnect() async {
    _watchdog?.cancel();
    _watchdog = null;
    _blocked = false;
    if (!_restarting) {
      _lastConfig = null;
      _lastSettings = null;
    }
    await _dropProxy();
    await _stopProcess();
    await _killSwitchOff();
    _stats.add(const ConnStats());
    _states.add(ConnState.disconnected);
  }

  /// Снять блокировку kill switch (если стоит). Ошибка — в журнал: снять
  /// её можно ещё раз кнопкой «Отключить».
  Future<void> _killSwitchOff() async {
    if (!os.killSwitchActive) return;
    try {
      await os.killSwitchOff();
      _log(tr('Kill switch: блокировка снята'));
    } catch (e) {
      _log('$e'.replaceFirst('Exception: ', ''));
    }
  }

  /// Адреса VPN-серверов из конфига (имена переводятся в IP).
  Future<List<String>> _serverIps(String config) async {
    final hosts = <String>{};
    try {
      for (final ob in (jsonDecode(config)['outbounds'] as List)) {
        if (ob is! Map) continue;
        final st = ob['settings'];
        if (st is! Map) continue;
        for (final key in const ['vnext', 'servers']) {
          for (final s in (st[key] as List? ?? const [])) {
            if (s is Map && s['address'] is String) hosts.add(s['address']);
          }
        }
        if (st['address'] is String) hosts.add(st['address']);
      }
    } catch (_) {}
    final out = <String>{};
    for (final h in hosts) {
      if (InternetAddress.tryParse(h) != null) {
        out.add(h);
        continue;
      }
      try {
        final a = await InternetAddress.lookup(h)
            .timeout(const Duration(seconds: 3));
        out.addAll(a.map((e) => e.address));
      } catch (_) {}
    }
    return out.toList();
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
      await _bypassTun(cfg['outbounds'] as List?);
      cfg.remove('metrics');
      cfg.remove('stats');
      cfg.remove('api');
      p = await Process.start(
        await _runCore(),
        ['run', '-format', 'json', '-c', 'stdin:'],
        workingDirectory: _runDir,
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
      // Сетевую карту для обхода TUN определяем один раз на весь замер.
      final iface = _tun ? await _physicalInterface() : null;
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
        await _bypassTun([ob], iface: iface);
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
        await _runCore(),
        ['run', '-format', 'json', '-c', 'stdin:'],
        workingDirectory: _runDir,
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
      await _bypassTun(cfg['outbounds'] as List?);
      cfg.remove('metrics');
      cfg.remove('stats');
      cfg.remove('api');

      p = await Process.start(
        await _runCore(),
        ['run', '-format', 'json', '-c', 'stdin:'],
        workingDirectory: _runDir,
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
        failReason = tr('ядро не запустилось');
        return -1;
      }

      return await _warmDelay('$user:$pass@127.0.0.1:$port');
    } catch (e) {
      failReason = e is TimeoutException ? tr('сервер не ответил за 6 с') : '$e';
      return -1;
    } finally {
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
        _log(tr('Проверка «{0}» ({1}): {2}{3}', [server.cleanName, server.protocol, failReason, why.isEmpty ? '' : ' — $why']));
      }
    }
  }

  /// Реальная задержка через туннель: HTTP-запрос через локальный прокси.
  @override
  Future<int> connectedDelay(ServerProfile server) async {
    try {
      return await _warmDelay('${_httpAuth}127.0.0.1:$_httpPort',
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
  Future<String> coreVersion() async {
    try {
      return await _versionOf(await _runCore());
    } catch (e) {
      return '$e';
    }
  }

  Future<String> _versionOf(String exe) async {
    try {
      if (!File(exe).existsSync()) return tr('не найдено');
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
  static final _newExe =
      Platform.isWindows ? 'nexus-core-new.exe' : 'nexus-core-new';

  /// Последний конфиг, с которым ядро работало (только в памяти) — на нём
  /// проверяется скачанное обновление ядра.
  String? _knownConfig;

  /// Ядро [exe] принимает [config] (xray run -test).
  Future<bool> _configOk(String exe, String config) async {
    try {
      final p = await Process.start(
          exe, ['run', '-test', '-format', 'json', '-c', 'stdin:'],
          environment: {'XRAY_LOCATION_ASSET': _assetDir});
      p.stdin.add(utf8.encode(config));
      await p.stdin.close();
      unawaited(p.stdout.drain<void>());
      unawaited(p.stderr.drain<void>());
      final code = await p.exitCode.timeout(const Duration(seconds: 20),
          onTimeout: () {
        p.kill();
        return -1;
      });
      return code == 0;
    } catch (_) {
      return false;
    }
  }

  /// Обновлённое ядро не запустилось: если виновато оно (конфиг не
  /// принимает, а прежнее или встроенное — принимает), возвращаем прежнее.
  Future<void> _rollbackCore(String config) async {
    try {
      final cur = File('$_updDir${_sep}$kCoreExe');
      if (!cur.existsSync() || _tun) return;
      if (await _configOk(cur.path, config)) return; // дело не в ядре
      final prev = File('$_updDir${_sep}$kCoreExe.prev');
      final fallback =
          prev.existsSync() ? prev.path : '$_exeDir${_sep}$kCoreExe';
      if (!await _configOk(fallback, config)) return;
      cur.deleteSync();
      if (prev.existsSync()) prev.renameSync(cur.path);
      _log(tr('Обновлённое ядро не принимает настройки — вернул прежнее. Подключитесь ещё раз'));
    } catch (_) {}
  }

  @override
  bool get canUpdateCore => os.xrayAsset != null;

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
      throw Exception(tr('GitHub ответил {0} на {1}', [r.statusCode, url]));
    }
    return r.bodyBytes;
  }

  @override
  Future<String> updateCore({bool force = false}) async {
    // С правами администратора работает только ядро из сборки (см.
    // _prepareSafeCore) — скачанное здесь всё равно не запустилось бы.
    if (!os.canUpdateCore) {
      return tr('С правами администратора используется ядро из сборки Nexus — оно обновляется вместе с приложением');
    }
    final asset = os.xrayAsset;
    if (asset == null) {
      return tr('Для этого процессора ядро обновляется вместе с приложением');
    }
    final res = await http.get(Uri.parse(_releaseApi), headers: {
      'User-Agent': 'Nexus',
      'Accept': 'application/vnd.github+json',
    }).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception(tr('Не удалось узнать последнюю версию (код {0})', [res.statusCode]));
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] ?? '').toString();
    final current = await coreVersion();
    if (!force && !_newer(tag, current)) {
      return tr('Установлена последняя версия');
    }

    String? url, dgstUrl;
    for (final a in (j['assets'] as List? ?? [])) {
      final name = a['name'];
      final link = a['browser_download_url']?.toString();
      if (link == null || !link.startsWith('https://github.com/XTLS/')) continue;
      if (name == asset) url = link;
      if (name == '$asset.dgst') dgstUrl = link;
    }
    if (url == null || dgstUrl == null) {
      throw Exception(tr('В релизе {0} нет сборки для этой системы', [tag]));
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
      throw Exception(tr('Контрольная сумма ядра не совпала — обновление отменено'));
    }

    final zip = ZipDecoder().decodeBytes(zipBytes);
    ArchiveFile? exe;
    for (final f in zip.files) {
      if (f.isFile && f.name.toLowerCase() == os.xrayExeInZip) exe = f;
    }
    if (exe == null) throw Exception(tr('В архиве нет {0}', [os.xrayExeInZip]));
    for (final f in zip.files) {
      if (Platform.isWindows && f.isFile && f.name.toLowerCase() == 'wintun.dll') {
        await File('$_updDir${_sep}wintun.dll.new')
            .writeAsBytes(f.content as List<int>, flush: true);
      }
    }
    final staged = File('$_updDir${_sep}$_newExe');
    await staged.writeAsBytes(exe.content as List<int>, flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['755', staged.path]);

    // Проверяем, что скачанное ядро вообще запускается.
    final v = await _versionOf(staged.path);
    if (!v.startsWith('Xray')) {
      await staged.delete();
      throw Exception(tr('Скачанное ядро не запускается'));
    }
    // …и принимает конфиг Nexus: в новых версиях Xray бывает, что
    // настройки удаляют, и с таким ядром VPN перестал бы подключаться.
    final known = _knownConfig;
    if (known != null && !await _configOk(staged.path, known)) {
      await staged.delete();
      throw Exception(tr('{0} не принимает настройки Nexus — обновление отменено, остаётся прежнее ядро', [v]));
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
          await File('$_updDir${_sep}$g.new').writeAsBytes(data, flush: true);
        } else {
          _log(tr('Гео-база {0} не прошла проверку и пропущена', [g]));
        }
      } catch (_) {}
    }

    if (_running) {
      return tr('Загружено {0} — применится при следующем подключении', [v]);
    }
    await _applyPendingUpdate();
    return tr('Ядро обновлено до {0}', [v]);
  }

  /// Подменяет ядро и гео-базы скачанными файлами (только когда ядро не запущено).
  Future<void> _applyPendingUpdate() async {
    try {
      final staged = File('$_updDir${_sep}$_newExe');
      if (staged.existsSync()) {
        final target = File('$_updDir${_sep}$kCoreExe');
        // Прежнее ядро — в запас: если новое не запустится, вернём его.
        final prev = File('$_updDir${_sep}$kCoreExe.prev');
        if (prev.existsSync()) prev.deleteSync();
        if (target.existsSync()) target.renameSync(prev.path);
        staged.renameSync(target.path);
      }
      final wt = File('$_updDir${_sep}wintun.dll.new');
      if (wt.existsSync()) {
        final t = File('$_updDir${_sep}wintun.dll');
        if (t.existsSync()) t.deleteSync();
        wt.renameSync(t.path);
      }
      for (final g in ['geoip.dat', 'geosite.dat']) {
        final n = File('$_updDir${_sep}$g.new');
        if (n.existsSync()) {
          final t = File('$_updDir${_sep}$g');
          if (t.existsSync()) t.deleteSync();
          n.renameSync(t.path);
        } else if (!File('$_updDir${_sep}$g').existsSync() &&
            File('${os.resDir}$_sep$g').existsSync() &&
            File('$_updDir${_sep}$kCoreExe').existsSync()) {
          File('${os.resDir}$_sep$g').copySync('$_updDir${_sep}$g');
        }
      }
      // Список заблокированных сайтов приходит с приложением, а не с
      // ядром — держим его копию рядом с обновлённым ядром свежей.
      final bl = File('${os.resDir}$_sep$kBlockedListFile');
      if (bl.existsSync() && File('$_updDir${_sep}$kCoreExe').existsSync()) {
        final t = File('$_updDir${_sep}$kBlockedListFile');
        if (!t.existsSync() || t.lengthSync() != bl.lengthSync()) {
          bl.copySync(t.path);
        }
      }
    } catch (e) {
      _log(tr('Не удалось применить обновление ядра: {0}', [e]));
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
