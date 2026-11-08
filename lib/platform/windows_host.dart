import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../core/desktop_os.dart';
import '../models.dart';
import 'win_admin.dart';
import '../services/deep_links.dart';
import '../state/app_state.dart';
import '../l10n.dart';

/// Компьютеры (Windows, Linux, macOS): трей, сворачивание вместо закрытия,
/// автозапуск, один экземпляр.
class WindowsHost with TrayListener, WindowListener {
  WindowsHost(this.app);
  final AppState app;

  static const _instancePort = 47821;
  static ServerSocket? _instanceServer;
  static final _showRequests = StreamController<void>.broadcast();

  ConnState? _trayState;
  String? _trayServer;
  String? _traySig;
  bool _quitting = false;

  /// Гарантирует один запущенный экземпляр. Если Nexus уже открыт —
  /// просит его показать окно и возвращает false.
  ///
  /// Linux и macOS: сокет в личной папке пользователя — у каждого
  /// пользователя компьютера свой Nexus, чужие программы до него не
  /// достучатся. Windows: порт на 127.0.0.1. Ссылки (nexus:link:…)
  /// принимаются только с секретом из личной папки — подсунуть подписку
  /// через этот канал посторонняя программа не может.
  static Future<bool> claimSingleInstance([String? link]) async {
    final token = _instanceToken();
    final unix = !Platform.isWindows;
    final addr = unix
        ? InternetAddress('${DesktopOs.current.dataDir}/instance.sock',
            type: InternetAddressType.unix)
        : InternetAddress.loopbackIPv4;
    final port = unix ? 0 : _instancePort;
    Future<bool> send() async {
      try {
        final s = await Socket.connect(addr, port,
            timeout: const Duration(seconds: 2));
        s.add(utf8.encode(link != null && token != null
            ? 'nexus:$token:link:$link'
            : 'nexus:show'));
        await s.flush();
        await s.close();
        return true;
      } catch (_) {
        return false;
      }
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        _instanceServer = await ServerSocket.bind(addr, port);
        break;
      } on SocketException {
        if (await send()) return false;
        // Сокет остался после аварийного завершения — убираем и занимаем.
        if (!unix || attempt > 0) return false;
        try {
          File(addr.address).deleteSync();
        } catch (_) {
          return false;
        }
      }
    }
    final srv = _instanceServer;
    if (srv == null) return false;
    srv.listen((client) {
      client.listen((data) {
        // Только короткие команды от второй копии Nexus.
        if (data.length > 8192) return client.destroy();
        final msg = utf8.decode(data, allowMalformed: true).trim();
        final linkPrefix = token == null ? null : 'nexus:$token:link:';
        if (msg == 'nexus:show') {
          _showRequests.add(null);
        } else if (linkPrefix != null && msg.startsWith(linkPrefix)) {
          _showRequests.add(null);
          DeepLinks.handle(msg.substring(linkPrefix.length));
        }
      }, onError: (_) {}, cancelOnError: true);
      Future.delayed(const Duration(seconds: 2), client.destroy);
    });
    return true;
  }

  /// Секрет канала между копиями Nexus (файл в личной папке пользователя).
  static String? _instanceToken() {
    try {
      final f = File('${DesktopOs.current.dataDir}${Platform.pathSeparator}instance.key');
      if (f.existsSync()) {
        final t = f.readAsStringSync().trim();
        if (RegExp(r'^[a-z0-9]{32}$').hasMatch(t)) return t;
      }
      final r = Random.secure();
      final t = List.generate(
          32, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)]).join();
      f.writeAsStringSync(t, flush: true);
      if (!Platform.isWindows) Process.runSync('chmod', ['600', f.path]);
      return t;
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    app.quitApp = quit;
    windowManager.addListener(this);
    trayManager.addListener(this);
    _showRequests.stream.listen((_) => show());
    await _updateTray(force: true);
    app.addListener(_updateTray);
    // Автозапуск: синхронизируем запись в реестре с настройкой.
    Autostart.apply(app.settings.launchAtStartup,
        tun: app.settings.windowsTun);
    // Ссылки nexus:// открывают Nexus.
    Autostart.registerProtocol();
    // Ctrl+Alt+N — подключить/отключить из любой программы (Windows).
    if (Platform.isWindows) unawaited(app.applyHotkey());
  }

  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
    app.setWindowVisible(true);
  }

  Future<void> hideToTray() async {
    await windowManager.hide();
    app.setWindowVisible(false);
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    try {
      if (app.state != ConnState.disconnected) await app.core.disconnect();
    } catch (_) {}
    try {
      await trayManager.destroy();
    } catch (_) {}
    await _instanceServer?.close();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // ───────────────────────────── трей ─────────────────────────────

  Future<void> _updateTray({bool force = false}) async {
    final st = app.state;
    final server = app.selected?.cleanName;
    // Меню зависит и от списка серверов, и от режима — следим за всем сразу.
    final sig = '${app.selectedId}|${app.servers.length}|'
        '${app.servers.take(15).map((e) => e.id).join(',')}|'
        '${app.settings.routing.name}|${app.settings.autoMode}|${L10n.lang}';
    if (!force && st == _trayState && server == _trayServer && sig == _traySig) {
      return;
    }
    _trayState = st;
    _trayServer = server;
    _traySig = sig;

    final on = st == ConnState.connected;
    try {
      if (Platform.isMacOS) {
        // Строка меню macOS: монохромный значок-шаблон — сам подстраивается
        // под светлую и тёмную тему; подключено — с точкой.
        await trayManager.setIcon(
            on ? 'assets/icon/tray_mac_on.png' : 'assets/icon/tray_mac_off.png',
            isTemplate: true);
      } else {
        final ext = Platform.isWindows ? 'ico' : 'png';
        await trayManager.setIcon(
            on ? 'assets/icon/tray_on.$ext' : 'assets/icon/tray_off.$ext');
      }
      final status = switch (st) {
        ConnState.connected => tr('подключено'),
        ConnState.connecting => tr('подключение…'),
        ConnState.disconnecting => tr('отключение…'),
        ConnState.disconnected => tr('не подключено'),
      };
      final where = app.settings.autoMode ? tr('Авто') : server;
      var tip = 'Nexus — $status${where != null && on ? ' · $where' : ''}';
      if (tip.length > 120) tip = '${tip.substring(0, 117)}…';
      await trayManager.setToolTip(tip);
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: tr('Открыть Nexus')),
        MenuItem.separator(),
        MenuItem(
          key: 'toggle',
          label: on || st == ConnState.connecting ? tr('Отключить') : tr('Подключить'),
          disabled: app.selected == null || st == ConnState.disconnecting,
        ),
        if (app.servers.length > 1)
          MenuItem.submenu(
            label: tr('Сервер'),
            submenu: Menu(items: [
              for (final x in app.servers.take(15))
                MenuItem.checkbox(
                  key: 'srv:${x.id}',
                  label: x.cleanName.length > 40
                      ? '${x.cleanName.substring(0, 39)}…'
                      : x.cleanName,
                  checked: x.id == app.selectedId,
                ),
            ]),
          ),
        MenuItem.checkbox(
          key: 'auto',
          label: tr('Режим «Авто»'),
          checked: app.settings.autoMode,
          disabled: app.selected == null,
        ),
        MenuItem.separator(),
        for (final (m, label) in [
          (RoutingMode.smart, tr('Умный режим (РФ напрямую)')),
          (RoutingMode.blocked, tr('Только заблокированное')),
          (RoutingMode.global, tr('Весь трафик')),
        ])
          MenuItem.checkbox(
            key: 'route:${m.name}',
            label: label,
            checked: app.settings.routing == m,
          ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: tr('Выход')),
      ]));
    } catch (_) {}
  }

  @override
  void onTrayIconMouseDown() => show();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        show();
      case 'toggle':
        app.toggle();
      case 'quit':
        quit();
      case 'auto':
        app.setAutoMode(!app.settings.autoMode);
      case final k? when k.startsWith('route:'):
        final m = RoutingMode.values
            .where((e) => e.name == k.substring(6))
            .firstOrNull;
        if (m == null || m == app.settings.routing) return;
        app.updateSettings((s) => s.routing = m);
        app.reconnectIfActive();
      case final k? when k.startsWith('srv:'):
        final id = k.substring(4);
        final x = app.servers.where((e) => e.id == id).firstOrNull;
        if (x != null) app.select(x);
    }
  }

  // ───────────────────────────── окно ─────────────────────────────

  @override
  void onWindowClose() {
    if (_quitting) return;
    if (app.settings.closeToTray) {
      hideToTray();
    } else {
      quit();
    }
  }

  @override
  void onWindowMinimize() => app.setWindowVisible(false);

  @override
  void onWindowRestore() => app.setWindowVisible(true);

  @override
  void onWindowFocus() => app.setWindowVisible(true);
}

/// Автозапуск через HKCU\Software\Microsoft\Windows\CurrentVersion\Run.
class Autostart {
  static const _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'Nexus';
  static const _hkcu = -2147483647; // HKEY_CURRENT_USER со знаковым расширением
  static const _regSz = 1;

  static final _advapi = DynamicLibrary.open('advapi32.dll');
  static final _regSet = _advapi.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32,
          Pointer<Void>, Uint32),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>,
          int)>('RegSetKeyValueW');
  static final _regDelete = _advapi.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>)>('RegDeleteKeyValueW');

  /// HKCU\Software\Classes\nexus — обработчик ссылок nexus://
  /// (Linux — ярлык .desktop; macOS — Info.plist приложения).
  static void registerProtocol() {
    if (Platform.isLinux) return unawaited(LinuxDesktop.install());
    if (!Platform.isWindows) return;
    final exe = Platform.resolvedExecutable;
    void set(String key, String name, String value) {
      final k = key.toNativeUtf16();
      final n = name.toNativeUtf16();
      final d = value.toNativeUtf16();
      try {
        _regSet(_hkcu, k, name.isEmpty ? nullptr : n, _regSz, d.cast(),
            (value.length + 1) * 2);
      } catch (_) {
      } finally {
        calloc.free(k);
        calloc.free(n);
        calloc.free(d);
      }
    }

    const base = r'Software\Classes\nexus';
    set(base, '', 'URL:Nexus');
    set(base, 'URL Protocol', '');
    set('$base\\DefaultIcon', '', '"$exe",0');
    set('$base\\shell\\open\\command', '', '"$exe" "%1"');
  }

  /// Автозапуск. Для режима TUN нужны права администратора, а запуск
  /// через ключ Run их не даёт — тогда Nexus запускается задачей
  /// Планировщика с наивысшими правами (создать её можно только от
  /// администратора). Иначе — обычный ключ Run.
  static void apply(bool enabled, {bool tun = false}) {
    if (Platform.isLinux) return unawaited(LinuxDesktop.autostart(enabled));
    if (Platform.isMacOS) return unawaited(MacAutostart.apply(enabled));
    // TUN включён, но Nexus сейчас без прав администратора: задачу не
    // создать и не проверить — оставляем автозапуск как есть.
    if (enabled && tun && !WinAdmin.isAdmin) return;
    final elevated = enabled && tun && WinAdmin.isAdmin;
    _runKeySet(enabled && !elevated);
    unawaited(_task(elevated, removeOnly: !enabled || !tun));
  }

  static Future<void> _task(bool create, {required bool removeOnly}) async {
    try {
      if (create) {
        final exe = Platform.resolvedExecutable;
        await Process.run('schtasks', [
          '/Create', '/F', '/TN', 'Nexus', '/SC', 'ONLOGON', '/RL', 'HIGHEST',
          '/TR', '"$exe" --minimized',
        ]);
      } else if (removeOnly || WinAdmin.isAdmin) {
        // Удалить задачу с наивысшими правами можно только от администратора;
        // без прав она просто останется — вторую копию отсечёт защита
        // от повторного запуска.
        await Process.run('schtasks', ['/Delete', '/F', '/TN', 'Nexus']);
      }
    } catch (_) {}
  }

  static void _runKeySet(bool enabled) {
    final sub = _runKey.toNativeUtf16();
    final name = _valueName.toNativeUtf16();
    try {
      if (enabled) {
        final cmd = '"${Platform.resolvedExecutable}" --minimized';
        final data = cmd.toNativeUtf16();
        _regSet(_hkcu, sub, name, _regSz, data.cast(), (cmd.length + 1) * 2);
        calloc.free(data);
      } else {
        _regDelete(_hkcu, sub, name);
      }
    } catch (_) {
    } finally {
      calloc.free(sub);
      calloc.free(name);
    }
  }
}


/// Linux: ярлык в меню приложений (и обработчик ссылок nexus://) и
/// автозапуск через ~/.config/autostart.
class LinuxDesktop {
  static String get _home => Platform.environment['HOME'] ?? '/tmp';

  static String _entry({bool autostart = false}) {
    final exe = Platform.resolvedExecutable;
    String q(String s) => '"${s.replaceAll('"', '\\"')}"';
    final icon = '${File(exe).parent.path}/data/flutter_assets/assets/icon/logo_mark.png';
    return [
      '[Desktop Entry]',
      'Type=Application',
      'Name=Nexus',
      'Comment=VPN',
      'Exec=${q(exe)}${autostart ? ' --minimized' : ' %u'}',
      'Icon=$icon',
      'Terminal=false',
      'Categories=Network;',
      if (!autostart) 'MimeType=x-scheme-handler/nexus;',
      if (autostart) 'X-GNOME-Autostart-enabled=true',
      'StartupWMClass=nexus',
      '',
    ].join('\n');
  }

  static Future<void> install() async {
    // Установлен пакетом .deb — ярлык и обработчик ссылок уже в системе.
    if (Platform.resolvedExecutable.startsWith('/opt/nexus/')) return;
    try {
      final base = Platform.environment['XDG_DATA_HOME'] ?? '$_home/.local/share';
      final f = File('$base/applications/nexus.desktop');
      final text = _entry();
      if (!f.existsSync() || f.readAsStringSync() != text) {
        await f.create(recursive: true);
        await f.writeAsString(text);
        await Process.run('xdg-mime', ['default', 'nexus.desktop', 'x-scheme-handler/nexus']);
        await Process.run('update-desktop-database', ['$base/applications']);
      }
    } catch (_) {}
  }

  static Future<void> autostart(bool enabled) async {
    try {
      final base = Platform.environment['XDG_CONFIG_HOME'] ?? '$_home/.config';
      final f = File('$base/autostart/nexus.desktop');
      if (enabled) {
        await f.create(recursive: true);
        await f.writeAsString(_entry(autostart: true));
      } else if (f.existsSync()) {
        await f.delete();
      }
    } catch (_) {}
  }
}

/// macOS: автозапуск через LaunchAgent пользователя.
class MacAutostart {
  static const _label = 'app.nexusvpn.nexus';

  static Future<void> apply(bool enabled) async {
    try {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final f = File('$home/Library/LaunchAgents/$_label.plist');
      if (!enabled) {
        if (f.existsSync()) await f.delete();
        return;
      }
      String x(String s) => s
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      await f.create(recursive: true);
      await f.writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$_label</string>
  <key>ProgramArguments</key>
  <array><string>${x(Platform.resolvedExecutable)}</string><string>--minimized</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
''');
    } catch (_) {}
  }
}
