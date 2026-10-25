import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../models.dart';
import '../services/deep_links.dart';
import '../state/app_state.dart';

/// Windows: трей, сворачивание вместо закрытия, автозапуск, один экземпляр.
class WindowsHost with TrayListener, WindowListener {
  WindowsHost(this.app);
  final AppState app;

  static const _instancePort = 47821;
  static ServerSocket? _instanceServer;
  static final _showRequests = StreamController<void>.broadcast();

  ConnState? _trayState;
  String? _trayServer;
  bool _quitting = false;

  /// Гарантирует один запущенный экземпляр. Если Nexus уже открыт —
  /// просит его показать окно и возвращает false.
  static Future<bool> claimSingleInstance([String? link]) async {
    try {
      _instanceServer =
          await ServerSocket.bind(InternetAddress.loopbackIPv4, _instancePort);
      _instanceServer!.listen((client) {
        client.listen((data) {
          final msg = utf8.decode(data, allowMalformed: true).trim();
          if (msg == 'nexus:show') {
            _showRequests.add(null);
          } else if (msg.startsWith('nexus:link:')) {
            _showRequests.add(null);
            DeepLinks.handle(msg.substring('nexus:link:'.length));
          }
        }, onError: (_) {}, cancelOnError: true);
        Future.delayed(const Duration(seconds: 2), client.destroy);
      });
      return true;
    } on SocketException {
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4,
            _instancePort,
            timeout: const Duration(seconds: 2));
        s.add(utf8.encode(link != null ? 'nexus:link:$link' : 'nexus:show'));
        await s.flush();
        await s.close();
      } catch (_) {}
      return false;
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
    Autostart.apply(app.settings.launchAtStartup);
    // Ссылки nexus:// открывают Nexus.
    Autostart.registerProtocol();
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
    if (!force && st == _trayState && server == _trayServer) return;
    _trayState = st;
    _trayServer = server;

    final on = st == ConnState.connected;
    try {
      await trayManager.setIcon(
          on ? 'assets/icon/tray_on.ico' : 'assets/icon/tray_off.ico');
      final status = switch (st) {
        ConnState.connected => 'подключено',
        ConnState.connecting => 'подключение…',
        ConnState.disconnecting => 'отключение…',
        ConnState.disconnected => 'не подключено',
      };
      var tip = 'Nexus — $status${server != null && on ? ' · $server' : ''}';
      if (tip.length > 120) tip = '${tip.substring(0, 117)}…';
      await trayManager.setToolTip(tip);
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'Открыть Nexus'),
        MenuItem.separator(),
        MenuItem(
          key: 'toggle',
          label: on || st == ConnState.connecting ? 'Отключить' : 'Подключить',
          disabled: app.selected == null || st == ConnState.disconnecting,
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Выход'),
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
  static void registerProtocol() {
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

  static void apply(bool enabled) {
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
