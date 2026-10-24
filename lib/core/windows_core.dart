import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
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
      WinProxy.disable();
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
    cfg['stats'] = <String, dynamic>{};
    cfg['api'] = {
      'tag': 'api',
      'listen': '127.0.0.1:$kApiPort',
      'services': ['StatsService'],
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

    final cfgFile = File('$_dataDir\\config.json');
    await cfgFile.writeAsString(_withStats(config));

    _logs.clear();
    _log('Запуск ядра: $remark');
    try {
      _proc = await Process.start(
        _corePath,
        ['run', '-c', cfgFile.path],
        workingDirectory: _coreDir,
        environment: {'XRAY_LOCATION_ASSET': _assetDir},
        mode: ProcessStartMode.detachedWithStdio,
      );
    } catch (e) {
      _states.add(ConnState.disconnected);
      throw Exception('Не удалось запустить ядро: $e');
    }
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
      up = await _portOpen(kHttpPort);
    }
    if (!up) {
      await _stopProcess();
      _states.add(ConnState.disconnected);
      final tail = _logs.reversed.take(3).toList().reversed.join('\n');
      throw Exception(
          'Ядро не запустилось.${tail.isEmpty ? '' : '\n$tail'}');
    }

    if (settings.windowsSystemProxy) {
      WinProxy.enable('127.0.0.1:$kHttpPort');
      _proxySet = true;
      File('$_dataDir\\proxy.lock').writeAsStringSync('1');
    }

    _lastUp = 0;
    _lastDown = 0;
    _failedChecks = 0;
    _watchdog?.cancel();
    _watchdog =
        Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _states.add(ConnState.connected);
  }

  Future<void> _tick() async {
    // Сторож: если ядро упало — отключаемся.
    if (!await _portOpen(kHttpPort)) {
      _failedChecks++;
      if (_failedChecks >= 3) {
        _log('Ядро перестало отвечать — отключение');
        await disconnect();
      }
      return;
    }
    _failedChecks = 0;
    final s = await _queryStats();
    if (s != null) {
      final (up, down) = s;
      final upSpeed = _lastUp == 0 ? 0 : math.max(0, up - _lastUp);
      final downSpeed = _lastDown == 0 ? 0 : math.max(0, down - _lastDown);
      _lastUp = up;
      _lastDown = down;
      _stats.add(ConnStats(
        uploadSpeed: upSpeed,
        downloadSpeed: downSpeed,
        upload: up,
        download: down,
      ));
    }
  }

  Future<(int, int)?> _queryStats() async {
    try {
      final p = await Process.start(
        _corePath,
        ['api', 'statsquery', '--server=127.0.0.1:$kApiPort'],
        workingDirectory: _coreDir,
        mode: ProcessStartMode.detachedWithStdio,
      );
      final out = await p.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 2));
      final j = jsonDecode(out) as Map<String, dynamic>;
      var up = 0, down = 0;
      for (final e in (j['stat'] as List? ?? [])) {
        final name = e['name']?.toString() ?? '';
        final v = int.tryParse(e['value']?.toString() ?? '0') ?? 0;
        if (!name.startsWith('outbound>>>proxy>>>')) continue;
        if (name.endsWith('uplink')) up += v;
        if (name.endsWith('downlink')) down += v;
      }
      return (up, down);
    } catch (_) {
      return null;
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

  @override
  Future<void> disconnect() async {
    _watchdog?.cancel();
    _watchdog = null;
    if (_proxySet) {
      WinProxy.disable();
      _proxySet = false;
      final marker = File('$_dataDir\\proxy.lock');
      if (marker.existsSync()) marker.deleteSync();
    }
    await _stopProcess();
    _stats.add(const ConnStats());
    _states.add(ConnState.disconnected);
  }

  @override
  Future<int> ping(ServerProfile server, String config) =>
      tcpPing(server.host, server.port);

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
      return 'Установлена последняя версия ($current)';
    }

    String? url;
    for (final a in (j['assets'] as List? ?? [])) {
      if (a['name'] == 'Xray-windows-64.zip') {
        url = a['browser_download_url']?.toString();
      }
    }
    if (url == null) throw Exception('В релизе $tag нет сборки для Windows');

    final dir = Directory(_updDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final zip = ZipDecoder().decodeBytes(await _download(url));
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

    // Свежие гео-базы для умного режима.
    for (final g in ['geoip.dat', 'geosite.dat']) {
      try {
        await File('$_updDir\\$g.new')
            .writeAsBytes(await _download('$_geoBase/$g'), flush: true);
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

  static void enable(String server) {
    try {
      _setString('ProxyServer', server);
      _setString('ProxyOverride',
          'localhost;127.*;10.*;172.16.*;192.168.*;*.local;<local>');
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
