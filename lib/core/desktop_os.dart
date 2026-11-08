import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../l10n.dart';
import '../platform/win_admin.dart';
import 'win_proxy.dart';

/// Имя ядра Xray внутри Nexus.
final String kCoreExe = Platform.isWindows ? 'nexus-core.exe' : 'nexus-core';

/// Всё, чем Windows, Linux и macOS отличаются для ядра: папки, системный
/// прокси, запуск в режиме TUN. Логика подключения — общая (DesktopCore).
abstract class DesktopOs {
  static final DesktopOs current = Platform.isWindows
      ? WindowsOs()
      : Platform.isMacOS
          ? MacOs()
          : LinuxOs();

  String get sep => Platform.pathSeparator;

  /// Папка с nexus и встроенным ядром.
  String get exeDir => File(Platform.resolvedExecutable).parent.path;

  /// Папка с гео-базами и списком заблокированных сайтов из сборки.
  String get resDir => exeDir;

  /// Папка данных Nexus (обновлённое ядро, отметка о прокси).
  String get dataDir;

  /// Архив ядра в релизе Xray для этой системы и имя ядра внутри.
  String? get xrayAsset;
  String get xrayExeInZip => 'xray';

  Future<void> killStrayCore();

  /// Закрыть файлы Nexus от других пользователей компьютера.
  Future<void> harden() async {}

  // ── системный прокси ──
  bool get hasSystemProxy => true;
  Future<Map<String, dynamic>> proxySnapshot();
  Future<void> proxyEnable(String hostPort);
  Future<void> proxyRestore(Map<String, dynamic>? saved);

  // ── режим TUN ──

  /// Почему TUN сейчас недоступен (null — доступен).
  Future<String?> tunBlocker();

  /// Вызывается перед запуском в режиме TUN: может попросить пароль
  /// администратора (Linux — один раз, macOS — при каждом включении).
  /// Возвращает путь к ядру для запуска.
  Future<String> prepareTun(String bundledCore);

  /// Имя виртуальной сетевой карты.
  String get tunName;

  /// Особые поля настроек TUN-входа для этой системы.
  Map<String, dynamic> tunExtra() => const {};

  /// Запуск ядра в режиме TUN с конфигом [config]. null — запускать как
  /// обычно (через stdin).
  Future<Process>? startTun(String core, String config, String assetDir) =>
      null;

  /// Остановка ядра, запущенного [startTun].
  Future<void> stopTun() async {}

  /// Обновление ядра из Nexus (без прав администратора).
  bool get canUpdateCore => true;

  static Map<String, dynamic> readJson(File f) {
    try {
      final j = jsonDecode(f.readAsStringSync());
      return j is Map<String, dynamic> ? j : {};
    } catch (_) {
      return {};
    }
  }

  /// Ядро из сборки, проверенное по SHA-256 (пусто в отладочной сборке).
  static const coreSha = String.fromEnvironment('CORE_SHA256');

  static Future<bool> shaOk(String path, String want) async {
    try {
      final f = File(path);
      if (!f.existsSync()) return false;
      return sha256.convert(await f.readAsBytes()).toString() == want;
    } catch (_) {
      return false;
    }
  }

  static Future<ProcessResult?> run(String exe, List<String> args,
      {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      return await Process.run(exe, args).timeout(timeout);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────── Windows ───────────────────────────────

class WindowsOs extends DesktopOs {
  @override
  String get dataDir {
    final base = Platform.environment['APPDATA'] ?? exeDir;
    final d = Directory('$base\\Nexus');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  @override
  String? get xrayAsset => 'Xray-windows-64.zip';
  @override
  String get xrayExeInZip => 'xray.exe';

  @override
  Future<void> killStrayCore() async {
    try {
      await Process.start('taskkill', ['/F', '/IM', kCoreExe],
          mode: ProcessStartMode.detached);
      await Future.delayed(const Duration(milliseconds: 300));
    } catch (_) {}
  }

  @override
  Future<Map<String, dynamic>> proxySnapshot() async => WinProxy.snapshot();
  @override
  Future<void> proxyEnable(String hostPort) async => WinProxy.enable(hostPort);
  @override
  Future<void> proxyRestore(Map<String, dynamic>? saved) async =>
      WinProxy.restore(saved);

  // TUN на Windows — внутри DesktopCore (права администратора на всё
  // приложение, защищённая копия ядра, wintun.dll).
  @override
  Future<String?> tunBlocker() async => null;
  @override
  Future<String> prepareTun(String bundledCore) async => bundledCore;
  @override
  String get tunName => 'Nexus';
  @override
  Map<String, dynamic> tunExtra() => {
        'desc': 'Nexus',
        'autoSystemWfpBlockLeak': ['dns', 'misconfigtun'],
      };

  @override
  bool get canUpdateCore =>
      !(WinAdmin.isAdmin && DesktopOs.coreSha.isNotEmpty);
}

// ──────────────────────────────── Linux ────────────────────────────────

/// Linux: системный прокси GNOME (gsettings) и KDE (kwriteconfig).
/// TUN: проверенная копия ядра в /usr/local/lib/nexus с правом только на
/// управление сетью (CAP_NET_ADMIN) — ставится один раз через pkexec.
class LinuxOs extends DesktopOs {
  static const _tunDir = '/usr/local/lib/nexus';
  static const _tunCore = '$_tunDir/nexus-core';

  @override
  String get dataDir {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final base = Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
    final d = Directory('$base/nexus');
    if (!d.existsSync()) d.createSync(recursive: true);
    // Только владелец: здесь отметка о прокси и обновлённое ядро.
    DesktopOs.run('chmod', ['700', d.path]);
    return d.path;
  }

  /// Подписки хранятся в настройках shared_preferences
  /// (~/.local/share/app.nexusvpn.nexus) — доступ только владельцу.
  @override
  Future<void> harden() async {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final base = Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
    final d = Directory('$base/app.nexusvpn.nexus');
    try {
      if (!d.existsSync()) d.createSync(recursive: true);
      await DesktopOs.run('chmod', ['700', d.path]);
      final f = File('${d.path}/shared_preferences.json');
      if (f.existsSync()) await DesktopOs.run('chmod', ['600', f.path]);
    } catch (_) {}
  }

  @override
  String? get xrayAsset {
    final arch = Platform.version.toLowerCase();
    if (arch.contains('arm64')) return 'Xray-linux-arm64-v8a.zip';
    if (arch.contains('x64')) return 'Xray-linux-64.zip';
    return null;
  }

  @override
  Future<void> killStrayCore() async {
    // Только «своё» ядро текущего пользователя.
    final user = Platform.environment['USER'];
    await DesktopOs.run('pkill', [
      if (user != null) ...['-u', user],
      '-x',
      kCoreExe,
    ]);
    await Future.delayed(const Duration(milliseconds: 200));
  }

  // ── прокси ──

  String get _desktop =>
      (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '').toLowerCase();
  bool get _kde => _desktop.contains('kde');

  Future<String?> _gs(String schema, String key) async {
    final r = await DesktopOs.run('gsettings', ['get', schema, key]);
    if (r == null || r.exitCode != 0) return null;
    return (r.stdout as String).trim();
  }

  Future<void> _gset(String schema, String key, String value) =>
      DesktopOs.run('gsettings', ['set', schema, key, value]);

  String? get _kdeWrite =>
      _which('kwriteconfig6') ?? _which('kwriteconfig5');
  String? get _kdeRead => _which('kreadconfig6') ?? _which('kreadconfig5');

  static String? _which(String name) {
    for (final d in (Platform.environment['PATH'] ?? '/usr/bin').split(':')) {
      if (File('$d/$name').existsSync()) return '$d/$name';
    }
    return null;
  }

  Future<String?> _kr(String key) async {
    final k = _kdeRead;
    if (k == null) return null;
    final r = await DesktopOs.run(
        k, ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', key]);
    return r == null || r.exitCode != 0 ? null : (r.stdout as String).trim();
  }

  Future<void> _kw(String key, String value) async {
    final k = _kdeWrite;
    if (k == null) return;
    await DesktopOs.run(k,
        ['--file', 'kioslaverc', '--group', 'Proxy Settings', '--key', key, value]);
  }

  Future<void> _kdeNotify() => DesktopOs.run('dbus-send', [
        '--type=signal',
        '/KIO/Scheduler',
        'org.kde.KIO.Scheduler.reparseSlaveConfiguration',
        'string:',
      ]);

  @override
  bool get hasSystemProxy => _which('gsettings') != null || _kdeWrite != null;

  @override
  Future<Map<String, dynamic>> proxySnapshot() async => {
        'gnome': {
          'mode': await _gs('org.gnome.system.proxy', 'mode'),
          'http': await _gs('org.gnome.system.proxy.http', 'host'),
          'httpPort': await _gs('org.gnome.system.proxy.http', 'port'),
          'https': await _gs('org.gnome.system.proxy.https', 'host'),
          'httpsPort': await _gs('org.gnome.system.proxy.https', 'port'),
          'ignore': await _gs('org.gnome.system.proxy', 'ignore-hosts'),
        },
        if (_kde)
          'kde': {
            'type': await _kr('ProxyType'),
            'http': await _kr('httpProxy'),
            'https': await _kr('httpsProxy'),
            'no': await _kr('NoProxyFor'),
          },
      };

  static const _ignore =
      "['localhost', '127.0.0.0/8', '::1', '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '*.local']";

  @override
  Future<void> proxyEnable(String hostPort) async {
    final i = hostPort.lastIndexOf(':');
    final host = hostPort.substring(0, i), port = hostPort.substring(i + 1);
    if (_which('gsettings') != null) {
      for (final s in ['http', 'https']) {
        await _gset('org.gnome.system.proxy.$s', 'host', "'$host'");
        await _gset('org.gnome.system.proxy.$s', 'port', port);
      }
      await _gset('org.gnome.system.proxy', 'ignore-hosts', _ignore);
      await _gset('org.gnome.system.proxy', 'mode', "'manual'");
    }
    if (_kde) {
      await _kw('httpProxy', 'http://$host $port');
      await _kw('httpsProxy', 'http://$host $port');
      await _kw('NoProxyFor', 'localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,.local');
      await _kw('ProxyType', '1');
      await _kdeNotify();
    }
  }

  static bool _ours(String? host, String? port) {
    if (host == null || port == null) return false;
    final h = host.replaceAll("'", '');
    return h == '127.0.0.1' && ['10809', '20809', '30809'].contains(port);
  }

  @override
  Future<void> proxyRestore(Map<String, dynamic>? saved) async {
    final g = (saved?['gnome'] as Map?)?.cast<String, dynamic>();
    if (_which('gsettings') != null) {
      final ours = _ours(g?['http'] as String?, g?['httpPort'] as String?);
      final mode = (g?['mode'] as String?) ?? "'none'";
      if (g != null && !ours) {
        for (final (k, schema, key) in const [
          ('http', 'org.gnome.system.proxy.http', 'host'),
          ('httpPort', 'org.gnome.system.proxy.http', 'port'),
          ('https', 'org.gnome.system.proxy.https', 'host'),
          ('httpsPort', 'org.gnome.system.proxy.https', 'port'),
          ('ignore', 'org.gnome.system.proxy', 'ignore-hosts'),
        ]) {
          final v = g[k];
          if (v is String && v.isNotEmpty) await _gset(schema, key, v);
        }
      }
      await _gset('org.gnome.system.proxy', 'mode',
          ours || mode == "'manual'" && g == null ? "'none'" : mode);
    }
    if (_kde) {
      final k = (saved?['kde'] as Map?)?.cast<String, dynamic>();
      final http = k?['http'] as String?;
      final ours = http != null && http.contains('127.0.0.1');
      if (k != null && !ours) {
        for (final key in ['http', 'https', 'no']) {
          final v = k[key];
          if (v is String) {
            await _kw(
                {'http': 'httpProxy', 'https': 'httpsProxy', 'no': 'NoProxyFor'}[key]!,
                v);
          }
        }
        await _kw('ProxyType', (k['type'] as String?) ?? '0');
      } else {
        await _kw('ProxyType', '0');
      }
      await _kdeNotify();
    }
  }

  // ── TUN ──

  @override
  String get tunName => 'nexus0';

  @override
  Future<String?> tunBlocker() async {
    if (DesktopOs.coreSha.isEmpty) {
      return tr('Режим TUN доступен только в сборке Nexus из релиза');
    }
    if (!File('/dev/net/tun').existsSync()) {
      return tr('В системе нет /dev/net/tun — режим TUN недоступен');
    }
    if (_which('pkexec') == null &&
        !await DesktopOs.shaOk(_tunCore, DesktopOs.coreSha)) {
      return tr('Для режима TUN нужен pkexec (polkit), чтобы один раз установить ядро с правом управления сетью');
    }
    return null;
  }

  /// Ядро уже установлено и совпадает со сборкой — пароль не нужен.
  /// Иначе — одна установка через pkexec: копия во временный файл,
  /// проверка SHA-256 именно копии (её не подменить: папка только для
  /// root), перенос на место и право CAP_NET_ADMIN (+NET_RAW для привязки
  /// к сетевой карте). Полных прав root ядро не получает.
  @override
  Future<String> prepareTun(String bundledCore) async {
    final want = DesktopOs.coreSha;
    if (await DesktopOs.shaOk(_tunCore, want) && await _hasCaps()) {
      return _tunCore;
    }
    if (!await DesktopOs.shaOk(bundledCore, want)) {
      throw Exception(tr('Файл {0} изменён после установки — запуск с правами администратора отменён. Переустановите Nexus', [kCoreExe]));
    }
    final script = [
      'set -e',
      'umask 022',
      'mkdir -p $_tunDir',
      'chown root:root $_tunDir',
      'chmod 755 $_tunDir',
      'install -o root -g root -m 0700 "\$1" $_tunDir/.new',
      'echo "$want  $_tunDir/.new" | sha256sum -c --status',
      'mv -f $_tunDir/.new $_tunCore',
      'chmod 0755 $_tunCore',
      'setcap cap_net_admin,cap_net_raw+ep $_tunCore',
    ].join('\n');
    final r = await Process.run(
            'pkexec', ['/bin/sh', '-c', script, 'nexus-tun', bundledCore])
        .timeout(const Duration(minutes: 3));
    if (r.exitCode == 126 || r.exitCode == 127) {
      throw Exception(tr('Установка ядра для TUN отменена'));
    }
    if (r.exitCode != 0 ||
        !await DesktopOs.shaOk(_tunCore, want) ||
        !await _hasCaps()) {
      final err = '${r.stderr}'.trim();
      throw Exception(tr('Не удалось подготовить ядро для TUN{0}', [err.isEmpty ? '' : ': $err']));
    }
    return _tunCore;
  }

  Future<bool> _hasCaps() async {
    final getcap = _which('getcap') ?? '/usr/sbin/getcap';
    final r = await DesktopOs.run(getcap, [_tunCore]);
    if (r == null) return true; // getcap нет — проверит сам запуск
    return '${r.stdout}'.contains('cap_net_admin');
  }
}

// ──────────────────────────────── macOS ────────────────────────────────

/// macOS: системный прокси через networksetup. TUN — ядро от root
/// (создать utun и маршруты без него нельзя): пароль администратора
/// спрашивается при каждом включении, постоянного разрешения не остаётся.
class MacOs extends DesktopOs {
  /// Ядро и данные лежат в Contents/MacOS и Contents/Resources.
  @override
  String get resDir {
    final r = Directory('$exeDir/../Resources');
    return r.existsSync() ? r.resolveSymbolicLinksSync() : exeDir;
  }

  @override
  String get dataDir {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final d = Directory('$home/Library/Application Support/Nexus');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  @override
  String? get xrayAsset => Platform.version.contains('arm64')
      ? 'Xray-macos-arm64-v8a.zip'
      : 'Xray-macos-64.zip';

  @override
  Future<void> killStrayCore() async {
    final user = Platform.environment['USER'];
    await DesktopOs.run('pkill', [
      if (user != null) ...['-u', user],
      '-x',
      kCoreExe,
    ]);
  }

  // ── прокси ──

  Future<List<String>> _services() async {
    final r = await DesktopOs.run(
        '/usr/sbin/networksetup', ['-listallnetworkservices']);
    if (r == null || r.exitCode != 0) return const [];
    return '${r.stdout}'
        .split('\n')
        .skip(1)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('*'))
        .toList();
  }

  Future<Map<String, String>> _get(String flag, String svc) async {
    final r = await DesktopOs.run('/usr/sbin/networksetup', [flag, svc]);
    final out = <String, String>{};
    for (final l in '${r?.stdout ?? ''}'.split('\n')) {
      final i = l.indexOf(':');
      if (i > 0) out[l.substring(0, i).trim()] = l.substring(i + 1).trim();
    }
    return out;
  }

  Future<void> _ns(List<String> args) async {
    final r = await DesktopOs.run('/usr/sbin/networksetup', args);
    if (r != null && r.exitCode != 0 && '${r.stdout}${r.stderr}'.contains('admin')) {
      throw Exception(tr('macOS не дал изменить прокси: нужна учётная запись администратора'));
    }
  }

  @override
  Future<Map<String, dynamic>> proxySnapshot() async {
    final out = <String, dynamic>{};
    for (final s in await _services()) {
      out[s] = {
        'web': await _get('-getwebproxy', s),
        'secure': await _get('-getsecurewebproxy', s),
      };
    }
    return out;
  }

  @override
  Future<void> proxyEnable(String hostPort) async {
    final i = hostPort.lastIndexOf(':');
    final host = hostPort.substring(0, i), port = hostPort.substring(i + 1);
    for (final s in await _services()) {
      await _ns(['-setwebproxy', s, host, port]);
      await _ns(['-setsecurewebproxy', s, host, port]);
      await _ns(['-setproxybypassdomains', s, 'localhost', '127.0.0.1', '::1',
          '10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '*.local']);
    }
  }

  @override
  Future<void> proxyRestore(Map<String, dynamic>? saved) async {
    for (final s in await _services()) {
      final m = (saved?[s] as Map?)?.cast<String, dynamic>();
      for (final (kind, set, state) in const [
        ('web', '-setwebproxy', '-setwebproxystate'),
        ('secure', '-setsecurewebproxy', '-setsecurewebproxystate'),
      ]) {
        final v = (m?[kind] as Map?)?.cast<String, dynamic>();
        final on = v?['Enabled'] == 'Yes';
        final host = v?['Server'] as String?;
        final port = v?['Port'] as String?;
        final ours = host == '127.0.0.1' &&
            ['10809', '20809', '30809'].contains(port);
        try {
          if (on && !ours && host != null && host.isNotEmpty && port != null) {
            await _ns([set, s, host, port]);
          } else {
            await _ns([state, s, 'off']);
          }
        } catch (_) {}
      }
    }
  }

  // ── TUN ──

  @override
  String get tunName => 'utun199';

  @override
  Future<String?> tunBlocker() async {
    if (DesktopOs.coreSha.isEmpty) {
      return tr('Режим TUN доступен только в сборке Nexus из релиза');
    }
    return null;
  }

  @override
  Future<String> prepareTun(String bundledCore) async {
    if (!await DesktopOs.shaOk(bundledCore, DesktopOs.coreSha)) {
      throw Exception(tr('Файл {0} изменён после установки — запуск с правами администратора отменён. Переустановите Nexus', [kCoreExe]));
    }
    return bundledCore;
  }

  File? _stopFlag;

  /// Ядро от root через окно пароля macOS. Конфиг с ключами — во
  /// временном файле, доступном только пользователю (и root); ядро
  /// читает его при старте, затем файл удаляется. Скрипт-сторож гасит
  /// ядро, когда Nexus просит (флаг) или когда Nexus закрылся.
  @override
  Future<Process>? startTun(String core, String config, String assetDir) async {
    final tmp = await Directory(
            '${Platform.environment['TMPDIR'] ?? '/tmp'}/nexus-tun')
        .create(recursive: true);
    await DesktopOs.run('chmod', ['700', tmp.path]);
    final cfg = File('${tmp.path}/c.json');
    await cfg.writeAsString(config, flush: true);
    await DesktopOs.run('chmod', ['600', cfg.path]);
    final stop = File('${tmp.path}/stop');
    if (stop.existsSync()) stop.deleteSync();
    _stopFlag = stop;
    // Копия ядра в папке root: от root запускается проверенный файл,
    // который пользовательские программы подменить не могут.
    final want = DesktopOs.coreSha;
    String q(String s) => "'${s.replaceAll("'", "'\\''")}'";
    const root = '/Library/Application Support/Nexus/core';
    final sh = [
      'set -e',
      'mkdir -p ${q(root)}',
      'chown root:wheel ${q(root)}; chmod 755 ${q(root)}',
      'install -o root -g wheel -m 0700 ${q(core)} ${q('$root/.new')}',
      '[ "\$(shasum -a 256 ${q('$root/.new')} | cut -d" " -f1)" = "$want" ]',
      'mv -f ${q('$root/.new')} ${q('$root/nexus-core')}',
      'chmod 755 ${q('$root/nexus-core')}',
      'XRAY_LOCATION_ASSET=${q(assetDir)} ${q('$root/nexus-core')} run -c ${q(cfg.path)} >/dev/null 2>&1 &',
      'CORE=\$!',
      'sleep 2; rm -f ${q(cfg.path)}',
      'while kill -0 $pid 2>/dev/null && kill -0 \$CORE 2>/dev/null && [ ! -e ${q(stop.path)} ]; do sleep 1; done',
      'kill \$CORE 2>/dev/null || true',
    ].join('\n');
    final apple = 'do shell script ${_appleStr(sh)} with administrator privileges '
        'with prompt ${_appleStr(tr('Nexus включает режим TUN: весь трафик Mac пойдёт через VPN.'))}';
    final p = await Process.start('/usr/bin/osascript', ['-e', apple]);
    // Если пароль не ввели, osascript завершится с ошибкой сразу.
    unawaited(p.exitCode.then((_) {
      try {
        if (cfg.existsSync()) cfg.deleteSync();
      } catch (_) {}
    }));
    return p;
  }

  static String _appleStr(String s) =>
      '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  @override
  Future<void> stopTun() async {
    try {
      await _stopFlag?.writeAsString('1');
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 1500));
  }

  @override
  Map<String, dynamic> tunExtra() => const {};
}
