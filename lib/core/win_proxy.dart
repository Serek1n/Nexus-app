import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'desktop_core.dart';

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

  static final _regDel = _advapi.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>)>('RegDeleteKeyValueW');

  static void _delete(String name) {
    final sub = _path.toNativeUtf16();
    final n = name.toNativeUtf16();
    try {
      _regDel(_hkcu, sub, n);
    } finally {
      calloc.free(sub);
      calloc.free(n);
    }
  }

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
        // Скрипт автонастройки (PAC) главнее ручного прокси: пока он задан,
        // браузеры могли бы идти мимо Nexus — на время VPN его убираем.
        'pac': _getString('AutoConfigURL'),
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
      final ours = server is String && DesktopCore.isOwnProxy(server);
      if (server is String && !ours) _setString('ProxyServer', server);
      if (ovr is String) _setString('ProxyOverride', ovr);
      final pac = saved['pac'];
      if (pac is String && pac.isNotEmpty) _setString('AutoConfigURL', pac);
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
      _delete('AutoConfigURL');
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
