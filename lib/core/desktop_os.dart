import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

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

  /// Linux: системный DNS направляется в туннель (systemd-resolved).
  bool tunDnsToGateway = false;

  /// Linux и macOS: IPv6 заведён в туннель (иначе он шёл бы мимо VPN).
  /// Только там, где IPv6 в системе включён: иначе ядро не поднимет TUN.
  bool tunIpv6 = false;

  /// Ядро не запустилось с этими добавками — до перезапуска Nexus без них.
  bool tunPlain = false;

  /// Запуск ядра в режиме TUN с конфигом [config]. null — запускать как
  /// обычно (через stdin).
  Future<Process>? startTun(String core, String config, String assetDir) =>
      null;

  /// Остановка ядра, запущенного [startTun]. [keepBlock] — ядро меняется
  /// на новое: блокировку трафика (kill switch) не снимать.
  Future<void> stopTun({bool keepBlock = false}) async {}

  // ── kill switch уровня системы (режим TUN) ──
  // Пока VPN работает, весь трафик мимо туннеля запрещён правилами
  // файрвола. Ядро упало — правила остаются, и программы не выходят в сеть
  // напрямую. Снимаются по кнопке «Отключить» (и при следующем запуске
  // Nexus, как и системный прокси). Перезагрузка их тоже снимает
  // (кроме Windows — там их снимет Nexus или удаление программы).

  /// Блокировку можно поставить на этой системе.
  bool get killSwitchSupported => false;

  /// macOS: блокировку ставит тот же скрипт администратора, что запускает
  /// ядро, — его нужно попросить об этом до запуска.
  bool killSwitchWanted = false;

  File get ksMarker => File('$dataDir${sep}killswitch.lock');

  /// Блокировка сейчас стоит (или осталась после сбоя).
  bool get killSwitchActive => ksMarker.existsSync();

  /// Поставить блокировку. [core] — ядро, которому сеть разрешена;
  /// [servers] — адреса VPN-серверов; [dns] — обычные DNS-серверы системы
  /// (через них ядро находит адрес сервера).
  Future<void> killSwitchOn({
    required String core,
    required List<String> servers,
    required List<String> dns,
  }) async {}

  /// Снять блокировку.
  Future<void> killSwitchOff() async {}

  /// Linux: метка исходящих соединений ядра (их файрвол пропускает).
  int? get coreMark => null;

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
  Future<void> proxyEnable(String hostPort) async {
    WinProxy.enable(hostPort);
    await _owned(true);
  }

  @override
  Future<void> proxyRestore(Map<String, dynamic>? saved) async {
    WinProxy.restore(saved);
    await _owned(false);
  }

  /// Сообщаем окну, что системный прокси сейчас «наш»: при выключении
  /// Windows оно выключит его само (см. WM_ENDSESSION в раннере).
  static Future<void> _owned(bool v) async {
    try {
      await const MethodChannel('nexus/hotkey')
          .invokeMethod('proxyOwned', v)
          .timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

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

  // ── kill switch: брандмауэр Windows ──
  // Исходящие по умолчанию запрещены; разрешены ядро Nexus, трафик через
  // туннель (адрес 172.19.0.1), локальная сеть, DHCP и служба DNS Windows
  // (через неё ядро находит адрес сервера). Прежняя политика профилей
  // запоминается и возвращается.
  static const _ksGroup = 'Nexus Kill Switch';

  @override
  bool get killSwitchSupported => WinAdmin.isAdmin;

  Future<ProcessResult> _ps(String script, [Map<String, String>? env]) =>
      Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
        environment: env,
      ).timeout(const Duration(seconds: 40));

  @override
  Future<void> killSwitchOn({
    required String core,
    required List<String> servers,
    required List<String> dns,
  }) async {
    if (!killSwitchActive) {
      final snap = await _ps(
          r"Get-NetFirewallProfile | ForEach-Object { $_.Name + '=' + $_.DefaultOutboundAction + '=' + $_.Enabled }");
      final saved = <String, String>{};
      var enabled = false;
      for (final l in '${snap.stdout}'.split(RegExp(r'\r?\n'))) {
        final m = RegExp(r'^(Domain|Private|Public)=(\w+)=(\w+)$').firstMatch(l.trim());
        if (m == null) continue;
        saved[m[1]!] = m[2]!;
        if (m[3] == 'True') enabled = true;
      }
      if (saved.length != 3) {
        throw Exception(tr('Не удалось прочитать настройки брандмауэра Windows'));
      }
      if (!enabled) {
        throw Exception(tr('Брандмауэр Windows выключен — kill switch не может блокировать трафик'));
      }
      ksMarker.writeAsStringSync(jsonEncode(saved));
    }
    final r = await _ps('''
\$ErrorActionPreference = 'Stop'
\$g = '$_ksGroup'
Get-NetFirewallRule -Group \$g -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -Group \$g -DisplayName 'Nexus: ядро' -Direction Outbound -Action Allow -Program \$env:NEXUS_CORE | Out-Null
New-NetFirewallRule -Group \$g -DisplayName 'Nexus: туннель' -Direction Outbound -Action Allow -LocalAddress 172.19.0.0/30 | Out-Null
New-NetFirewallRule -Group \$g -DisplayName 'Nexus: локальная сеть' -Direction Outbound -Action Allow -RemoteAddress LocalSubnet | Out-Null
New-NetFirewallRule -Group \$g -DisplayName 'Nexus: DHCP' -Direction Outbound -Action Allow -Protocol UDP -RemotePort 67 | Out-Null
foreach (\$p in 'UDP','TCP') {
  New-NetFirewallRule -Group \$g -DisplayName 'Nexus: DNS' -Direction Outbound -Action Allow -Protocol \$p -RemotePort 53 -Program "\$env:SystemRoot\\System32\\svchost.exe" -Service dnscache | Out-Null
}
Set-NetFirewallProfile -Profile Domain,Private,Public -DefaultOutboundAction Block
''', {'NEXUS_CORE': core});
    if (r.exitCode != 0) {
      await killSwitchOff();
      throw Exception(tr('Не удалось включить kill switch: {0}', ['${r.stderr}'.trim().split('\n').first]));
    }
  }

  @override
  Future<void> killSwitchOff() async {
    final m = ksMarker;
    if (!m.existsSync()) return;
    if (!WinAdmin.isAdmin) {
      // Правила брандмауэра снимает только администратор: запускаем
      // Nexus с правами администратора ровно для этого (окно UAC).
      final r = await _ps(
          r"Start-Process -FilePath $env:NEXUS_EXE -ArgumentList '--killswitch-off' -Verb RunAs -Wait",
          {'NEXUS_EXE': Platform.resolvedExecutable});
      if (m.existsSync()) {
        throw Exception(tr('Блокировка kill switch не снята — нужны права администратора{0}', [r.exitCode == 0 ? '' : ' (отменено)']));
      }
      return;
    }
    final saved = DesktopOs.readJson(m);
    final restore = [
      for (final p in const ['Domain', 'Private', 'Public'])
        if (RegExp(r'^(Allow|Block|NotConfigured)$').hasMatch('${saved[p] ?? ''}'))
          "Set-NetFirewallProfile -Profile $p -DefaultOutboundAction ${saved[p]}"
        else
          "Set-NetFirewallProfile -Profile $p -DefaultOutboundAction Allow",
    ].join('\n');
    final r = await _ps('''
$restore
Get-NetFirewallRule -Group '$_ksGroup' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
''');
    if (r.exitCode == 0) {
      try {
        m.deleteSync();
      } catch (_) {}
    } else {
      throw Exception(tr('Не удалось снять блокировку kill switch: {0}', ['${r.stderr}'.trim().split('\n').first]));
    }
  }
}

// ──────────────────────────────── Linux ────────────────────────────────

/// Linux: системный прокси GNOME (gsettings) и KDE (kwriteconfig).
/// TUN: проверенная копия ядра в /usr/local/lib/nexus с правом только на
/// управление сетью (CAP_NET_ADMIN) — ставится один раз через pkexec.
class LinuxOs extends DesktopOs {
  static const _tunDir = '/usr/local/lib/nexus';
  static const _tunCore = '$_tunDir/nexus-core';
  static bool _dirLocked = false;

  @override
  String get dataDir {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final base = Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share';
    final d = Directory('$base/nexus');
    if (!d.existsSync()) d.createSync(recursive: true);
    // Только владелец: здесь отметка о прокси и обновлённое ядро.
    // Один раз за запуск, а не при каждом обращении к папке.
    if (!_dirLocked) {
      _dirLocked = true;
      DesktopOs.run('chmod', ['700', d.path]);
    }
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

  /// IPv6 в системе не выключен (sysctl или параметр ядра).
  static bool _ipv6On() {
    try {
      return File('/proc/sys/net/ipv6/conf/all/disable_ipv6')
              .readAsStringSync()
              .trim() ==
          '0';
    } catch (_) {
      return false;
    }
  }

  /// Системный DNS ведёт systemd-resolved — тогда ядро само направит его
  /// в туннель (иначе запросы к роутеру шли бы мимо VPN).
  Future<bool> _resolvedActive() async {
    if (_which('resolvectl') == null) return false;
    final r = await DesktopOs.run('systemctl', ['is-active', 'systemd-resolved']);
    if ('${r?.stdout ?? ''}'.trim() != 'active') return false;
    try {
      return File('/etc/resolv.conf').readAsStringSync().contains('127.0.0.53');
    } catch (_) {
      return false;
    }
  }

  @override
  Map<String, dynamic> tunExtra() =>
      {if (tunDnsToGateway) 'autoSystemDnsToGateway': true};

  @override
  Future<String?> tunBlocker() async {
    if (DesktopOs.coreSha.isEmpty) {
      return tr('Режим TUN доступен только в сборке Nexus из релиза');
    }
    if (!File('/dev/net/tun').existsSync()) {
      return tr('В системе нет /dev/net/tun — режим TUN недоступен');
    }
    if (_which('pkexec') == null &&
        !Platform.resolvedExecutable.startsWith('/opt/nexus/') &&
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
    tunDnsToGateway = !tunPlain && await _resolvedActive();
    tunIpv6 = !tunPlain && _ipv6On();
    final want = DesktopOs.coreSha;
    // Пакет .deb: ядро в /opt/nexus принадлежит root, право на управление
    // сетью ему выдал установщик — пароль не нужен.
    // Запускать его может только группа «nexus»: нового пользователя
    // установщик добавляет в неё, но группа действует после входа в
    // систему заново — до тех пор работает копия ниже (с паролем).
    const debCore = '/opt/nexus/tun/nexus-core';
    if (bundledCore.startsWith('/opt/nexus/') &&
        await DesktopOs.shaOk(debCore, want) &&
        await _hasCaps(debCore) &&
        (await DesktopOs.run('test', ['-x', debCore]))?.exitCode == 0) {
      return debCore;
    }
    final gid = await _gid();
    if (await DesktopOs.shaOk(_tunCore, want) &&
        await _hasCaps() &&
        await _privateTo(gid)) {
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
      // Запускать ядро с правом на сеть может только группа пользователя,
      // а не любой пользователь компьютера.
      'case "\$2" in ""|*[!0-9]*) G=0;; *) G="\$2";; esac',
      'chown root:"\$G" $_tunCore',
      'chmod 0750 $_tunCore',
      'setcap cap_net_admin,cap_net_raw+ep $_tunCore',
    ].join('\n');
    final r = await Process.run('pkexec',
            ['/bin/sh', '-c', script, 'nexus-tun', bundledCore, gid ?? ''])
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

  /// Основная группа текущего пользователя.
  Future<String?> _gid() async {
    final r = await DesktopOs.run('id', ['-g']);
    final g = '${r?.stdout ?? ''}'.trim();
    return RegExp(r'^\d+$').hasMatch(g) ? g : null;
  }

  /// Ядро для TUN закрыто от остальных пользователей (0750, группа
  /// пользователя). Старые установки с 0755 переустанавливаются.
  Future<bool> _privateTo(String? gid) async {
    if (gid == null) return true;
    final r = await DesktopOs.run('stat', ['-c', '%a %g', _tunCore]);
    return '${r?.stdout ?? ''}'.trim() == '750 $gid';
  }

  // ── kill switch: nftables через помощник root ──
  // Помощник и правило polkit ставятся один раз (пароль администратора);
  // дальше включение и снятие блокировки — без пароля. Соединения ядра
  // помечаются (SO_MARK, право CAP_NET_ADMIN у ядра уже есть) — им сеть
  // разрешена, остальным программам — только через туннель.
  static const _ksHelper = '$_tunDir/nexus-killswitch';
  static const _ksPolicy =
      '/usr/share/polkit-1/actions/app.nexusvpn.killswitch.policy';
  static const ksHelperText = r'''#!/bin/sh
# Nexus kill switch (nftables). Запускается через pkexec без пароля только
# для активного сеанса (правило polkit app.nexusvpn.killswitch).
# Принимает лишь IP-адреса — ничего другого в правила не попадает.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
NFT=$(command -v nft) || exit 3
if [ "${1:-}" = off ]; then
  $NFT delete table inet nexus_ks 2>/dev/null || true
  exit 0
fi
[ "${1:-}" = on ] || exit 2
shift
S4=""; S6=""; D4=""; D6=""
for a in "$@"; do
  k=${a%%=*}; v=${a#*=}
  case "$v" in ""|*[!0-9a-fA-F.:/]*) exit 2;; esac
  case "$k:$v" in
    srv:*:*) S6="$S6, $v";;
    srv:*) S4="$S4, $v";;
    dns:*:*) D6="$D6, $v";;
    dns:*) D4="$D4, $v";;
    *) exit 2;;
  esac
done
{
  echo 'table inet nexus_ks'
  echo 'delete table inet nexus_ks'
  echo 'table inet nexus_ks {'
  echo ' chain out {'
  echo '  type filter hook output priority 0; policy drop;'
  echo '  oifname "lo" accept'
  echo '  oifname "nexus0" accept'
  echo '  meta mark 0x4e58 accept'
  echo '  ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4, 255.255.255.255 } accept'
  echo '  ip6 daddr { fe80::/10, fc00::/7, ff00::/8 } accept'
  echo '  udp dport { 67, 68, 546, 547 } accept'
  if [ -n "$S4" ]; then echo "  ip daddr { ${S4#, } } accept"; fi
  if [ -n "$S6" ]; then echo "  ip6 daddr { ${S6#, } } accept"; fi
  if [ -n "$D4" ]; then echo "  ip daddr { ${D4#, } } meta l4proto { tcp, udp } th dport 53 accept"; fi
  if [ -n "$D6" ]; then echo "  ip6 daddr { ${D6#, } } meta l4proto { tcp, udp } th dport 53 accept"; fi
  # Отказ сразу, а не молчание: программы не «висят», а видят, что сети нет.
  echo '  meta l4proto tcp reject with tcp reset'
  echo '  reject with icmpx type admin-prohibited'
  echo ' }'
  echo '}'
} | $NFT -f -
''';
  static const ksPolicyText = r'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN" "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <action id="app.nexusvpn.killswitch">
    <description>Nexus kill switch</description>
    <message>Nexus blocks traffic outside the VPN</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>yes</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/local/lib/nexus/nexus-killswitch</annotate>
  </action>
</policyconfig>
''';

  @override
  bool get killSwitchSupported =>
      _which('nft') != null && _which('pkexec') != null;

  @override
  int? get coreMark => killSwitchWanted ? 0x4E58 : null;

  Future<void> _ensureKsHelper() async {
    final want = sha256.convert(utf8.encode(ksHelperText)).toString();
    final pol = sha256.convert(utf8.encode(ksPolicyText)).toString();
    if (await DesktopOs.shaOk(_ksHelper, want) &&
        await DesktopOs.shaOk(_ksPolicy, pol)) {
      return;
    }
    // Файлы — во временной папке пользователя; root сверяет их SHA-256
    // уже после копирования к себе, подменить их по дороге нельзя.
    final tmp = await Directory.systemTemp.createTemp('nexus-ks');
    try {
      final h = File('${tmp.path}/h')..writeAsStringSync(ksHelperText);
      final p = File('${tmp.path}/p')..writeAsStringSync(ksPolicyText);
      final script = [
        'set -e',
        'umask 022',
        'mkdir -p $_tunDir',
        'install -o root -g root -m 0755 "\$1" $_tunDir/.ks',
        'echo "$want  $_tunDir/.ks" | sha256sum -c --status',
        'mv -f $_tunDir/.ks $_ksHelper',
        'install -o root -g root -m 0644 "\$2" $_ksPolicy.new',
        'echo "$pol  $_ksPolicy.new" | sha256sum -c --status',
        'mv -f $_ksPolicy.new $_ksPolicy',
      ].join('\n');
      final r = await Process.run('pkexec',
              ['/bin/sh', '-c', script, 'nexus-ks', h.path, p.path])
          .timeout(const Duration(minutes: 3));
      if (r.exitCode != 0 || !await DesktopOs.shaOk(_ksHelper, want)) {
        throw Exception(r.exitCode == 126 || r.exitCode == 127
            ? tr('Установка kill switch отменена')
            : tr('Не удалось установить kill switch'));
      }
    } finally {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  static final _ipArg = RegExp(r'^[0-9a-fA-F.:/]+$');

  @override
  Future<void> killSwitchOn({
    required String core,
    required List<String> servers,
    required List<String> dns,
  }) async {
    await _ensureKsHelper();
    ksMarker.writeAsStringSync('{}');
    final r = await Process.run('pkexec', [
      _ksHelper,
      'on',
      for (final s in servers)
        if (_ipArg.hasMatch(s)) 'srv=$s',
      for (final d in dns)
        if (_ipArg.hasMatch(d)) 'dns=$d',
    ]).timeout(const Duration(minutes: 2));
    if (r.exitCode != 0) {
      try {
        ksMarker.deleteSync();
      } catch (_) {}
      throw Exception(tr('Не удалось включить kill switch: {0}', ['${r.stderr}'.trim()]));
    }
  }

  @override
  Future<void> killSwitchOff() async {
    if (!killSwitchActive) return;
    if (File(_ksHelper).existsSync()) {
      final r = await Process.run('pkexec', [_ksHelper, 'off'])
          .timeout(const Duration(minutes: 2));
      if (r.exitCode != 0) {
        throw Exception(tr('Не удалось снять блокировку kill switch: {0}', ['${r.stderr}'.trim()]));
      }
    }
    try {
      ksMarker.deleteSync();
    } catch (_) {}
  }

  /// Обычные DNS-серверы системы (не 127.x): к ним ядро обращается,
  /// чтобы найти адрес VPN-сервера.
  static Future<List<String>> systemDns() async {
    final out = <String>{};
    try {
      for (final l in File('/etc/resolv.conf').readAsLinesSync()) {
        final m = RegExp(r'^\s*nameserver\s+(\S+)').firstMatch(l);
        if (m != null) out.add(m[1]!);
      }
    } catch (_) {}
    final r = await DesktopOs.run('resolvectl', ['dns']);
    for (final m in RegExp(r'(?<![\w.:])(\d{1,3}(?:\.\d{1,3}){3}|[0-9a-fA-F]*:[0-9a-fA-F:]+)(?![\w.:])')
        .allMatches('${r?.stdout ?? ''}')) {
      out.add(m[1]!);
    }
    return out
        .where((a) =>
            InternetAddress.tryParse(a) != null &&
            !a.startsWith('127.') &&
            a != '::1')
        .toList();
  }

  Future<bool> _hasCaps([String path = _tunCore]) async {
    final getcap = _which('getcap') ?? '/usr/sbin/getcap';
    final r = await DesktopOs.run(getcap, [path]);
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
    tunIpv6 = !tunPlain;
    if (!await DesktopOs.shaOk(bundledCore, DesktopOs.coreSha)) {
      throw Exception(tr('Файл {0} изменён после установки — запуск с правами администратора отменён. Переустановите Nexus', [kCoreExe]));
    }
    return bundledCore;
  }

  File? _stopFlag;
  Process? _lastScript;

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
    // Конфиг тоже сверяется по SHA-256 уже в папке root: подменить его
    // между записью и запуском (и заставить ядро от root писать в чужие
    // файлы) посторонняя программа не может.
    final cfgSha = sha256.convert(utf8.encode(config)).toString();
    // Адрес DNS из конфига туннеля (только IP — он попадает в команду root).
    var dns = '1.1.1.1';
    try {
      for (final ib in (jsonDecode(config)['inbounds'] as List)) {
        if (ib is Map && ib['tag'] == 'tun-in') {
          final d = '${((ib['settings'] as Map)['dns'] as List).first}';
          if (InternetAddress.tryParse(d) != null) dns = d;
        }
      }
    } catch (_) {}
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
      'install -o root -g wheel -m 0600 ${q(cfg.path)} ${q('$root/run.json')}',
      'rm -f ${q(cfg.path)}',
      '[ "\$(shasum -a 256 ${q('$root/run.json')} | cut -d" " -f1)" = "$cfgSha" ] || { rm -f ${q('$root/run.json')}; exit 1; }',
      'XRAY_LOCATION_ASSET=${q(assetDir)} ${q('$root/nexus-core')} run -c ${q('$root/run.json')} >/dev/null 2>&1 &',
      'CORE=\$!',
      'sleep 2; rm -f ${q('$root/run.json')}',
      // Kill switch: правила pf в якоре com.apple/nexus. Пока ядро работает,
      // наружу выходят только туннель, ядро (root), локальная сеть, DHCP и
      // DNS системной службы. Ядро упало или Nexus закрылся — правила
      // остаются; снимаются по «Отключить» (флаг off) или перезагрузкой.
      'KSF=${q('$root/ks.token')}',
      ...macKsScript(killSwitchWanted),
      // Системный DNS — в туннель: иначе запросы к роутеру идут мимо VPN.
      // Прежние значения записываются и возвращаются при отключении
      // (и при следующем включении, если Mac выключили с VPN).
      'DNSF=${q('$root/dns.saved')}',
      ...macDnsScript(dns),
      'while kill -0 $pid 2>/dev/null && kill -0 \$CORE 2>/dev/null && [ ! -e ${q(stop.path)} ]; do sleep 1; done',
      'kill \$CORE 2>/dev/null || true',
      'restore_dns || true',
      'if [ "\$(cat ${q(stop.path)} 2>/dev/null)" = off ]; then ks_off; fi',
    ].join('\n');
    final apple = 'do shell script ${_appleStr(sh)} with administrator privileges '
        'with prompt ${_appleStr(tr('Nexus включает режим TUN: весь трафик Mac пойдёт через VPN.'))}';
    final p = await Process.start('/usr/bin/osascript', ['-e', apple]);
    _scriptAlive = true;
    _lastScript = p;
    // Если пароль не ввели, osascript завершится с ошибкой сразу.
    unawaited(p.exitCode.then((_) {
      if (identical(_lastScript, p)) _scriptAlive = false;
      try {
        if (cfg.existsSync()) cfg.deleteSync();
      } catch (_) {}
    }));
    return p;
  }

  /// Команды оболочки для kill switch (pf). ks_off — снять правила.
  static List<String> macKsScript(bool on) => [
        r'''ks_off() { pfctl -a com.apple/nexus -F all >/dev/null 2>&1 || true; if [ -f "$KSF" ]; then pfctl -X "$(cat "$KSF")" >/dev/null 2>&1 || true; rm -f "$KSF"; fi; return 0; }''',
        if (on) ...[
          r'''printf '%s\n' 'pass out quick on lo0 all' 'pass out quick inet from 172.19.0.0/30 to any' 'pass out quick inet6 from fd19:6e78::/126 to any' 'pass out quick proto { tcp, udp } from any to any user root' 'pass out quick proto { tcp, udp } from any to any port 53 user _mdnsresponder' 'pass out quick inet from any to { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4, 255.255.255.255 }' 'pass out quick inet6 from any to { fe80::/10, fc00::/7, ff00::/8 }' 'pass out quick proto udp from any to any port { 67, 68 }' 'block return out quick all' | pfctl -a com.apple/nexus -f - >/dev/null 2>&1 || true''',
          r'''[ -s "$KSF" ] || pfctl -E 2>&1 | sed -n 's/.*Token : //p' > "$KSF" || true''',
        ] else
          'ks_off',
      ];

  @override
  bool get killSwitchSupported => true;

  /// Скрипт администратора ещё работает (снимет блокировку по флагу).
  bool _scriptAlive = false;

  @override
  Future<void> killSwitchOn({
    required String core,
    required List<String> servers,
    required List<String> dns,
  }) async {
    // Правила уже поставил скрипт, запустивший ядро.
    ksMarker.writeAsStringSync('{}');
  }

  @override
  Future<void> killSwitchOff() async {
    if (!killSwitchActive) return;
    if (!_scriptAlive) {
      // Скрипт уже завершился (ядро упало) — правила снимаем отдельно,
      // это снова просит пароль администратора.
      const root = '/Library/Application Support/Nexus/core';
      final sh = [
        "KSF='$root/ks.token'",
        macKsScript(false).first,
        'ks_off',
      ].join('\n');
      final apple = 'do shell script ${_appleStr(sh)} with administrator privileges '
          'with prompt ${_appleStr(tr('Nexus снимает блокировку интернета (kill switch).'))}';
      final r = await Process.run('/usr/bin/osascript', ['-e', apple])
          .timeout(const Duration(minutes: 3));
      if (r.exitCode != 0) {
        throw Exception(tr('Блокировка не снята — нужен пароль администратора. Перезагрузка Mac тоже её снимает'));
      }
    }
    try {
      ksMarker.deleteSync();
    } catch (_) {}
  }

  /// Команды оболочки: запомнить DNS всех сетевых служб и поставить [dns].
  /// В файл попадают только цифры, точки и двоеточия (или «Empty»).
  static List<String> macDnsScript(String dns) => [
        r'''restore_dns() { [ -f "$DNSF" ] || return 0; while IFS='|' read -r S D; do [ -n "$S" ] && networksetup -setdnsservers "$S" $D >/dev/null 2>&1; done < "$DNSF"; rm -f "$DNSF"; return 0; }''',
        'restore_dns || true',
        r'''networksetup -listallnetworkservices 2>/dev/null | tail -n +2 | grep -v '^\*' | while IFS= read -r S; do D=$(networksetup -getdnsservers "$S" 2>/dev/null | tr '\n' ' '); case "$D" in *[!0-9a-fA-F.:\ ]*) D=Empty;; esac; [ -n "${D# }" ] || D=Empty; printf '%s|%s\n' "$S" "$D" >> "$DNSF"; networksetup -setdnsservers "$S" '''
            '$dns'
            r''' >/dev/null 2>&1 || true; done || true''',
      ];

  static String _appleStr(String s) =>
      '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  @override
  Future<void> stopTun({bool keepBlock = false}) async {
    try {
      await _stopFlag?.writeAsString(keepBlock ? 'keep' : 'off');
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 1500));
  }

  @override
  Map<String, dynamic> tunExtra() => const {};
}
