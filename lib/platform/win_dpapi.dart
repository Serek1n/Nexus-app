import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Шифрование данных ключом текущего пользователя Windows (DPAPI).
/// Подписки и ключи серверов на диске нельзя прочитать из-под другой
/// учётной записи или на другом компьютере.
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

class WinDpapi {
  static const _prefix = 'dpapi:';
  static const _uiForbidden = 0x1;

  static final _crypt32 = DynamicLibrary.open('crypt32.dll');
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _protect = _crypt32.lookupFunction<
      Int32 Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>,
          Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>),
      int Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>,
          Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>)>(
    'CryptProtectData',
  );

  static final _unprotect = _crypt32.lookupFunction<
      Int32 Function(Pointer<_DataBlob>, Pointer<Pointer<Utf16>>,
          Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, Uint32,
          Pointer<_DataBlob>),
      int Function(Pointer<_DataBlob>, Pointer<Pointer<Utf16>>,
          Pointer<_DataBlob>, Pointer<Void>, Pointer<Void>, int,
          Pointer<_DataBlob>)>('CryptUnprotectData');

  static final _localFree = _kernel32.lookupFunction<
      IntPtr Function(Pointer<Void>), int Function(Pointer<Void>)>('LocalFree');

  static bool get available => Platform.isWindows;

  static bool isProtected(String s) => s.startsWith(_prefix);

  static Uint8List? _run(Uint8List input, bool encrypt) {
    final inBlob = calloc<_DataBlob>();
    final outBlob = calloc<_DataBlob>();
    final buf = calloc<Uint8>(input.isEmpty ? 1 : input.length);
    try {
      buf.asTypedList(input.length).setAll(0, input);
      inBlob.ref
        ..cbData = input.length
        ..pbData = buf;
      final ok = encrypt
          ? _protect(inBlob, nullptr, nullptr, nullptr, nullptr, _uiForbidden,
              outBlob)
          : _unprotect(inBlob, nullptr, nullptr, nullptr, nullptr,
              _uiForbidden, outBlob);
      if (ok == 0) return null;
      final out = Uint8List.fromList(
          outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
      _localFree(outBlob.ref.pbData.cast());
      return out;
    } finally {
      calloc.free(buf);
      calloc.free(inBlob);
      calloc.free(outBlob);
    }
  }

  /// Шифрует строку. При ошибке возвращает исходный текст.
  static String protect(String plain) {
    if (!available) return plain;
    try {
      final enc = _run(Uint8List.fromList(utf8.encode(plain)), true);
      return enc == null ? plain : '$_prefix${base64.encode(enc)}';
    } catch (_) {
      return plain;
    }
  }

  /// Расшифровывает строку; незашифрованный текст возвращает как есть.
  static String? unprotect(String stored) {
    if (!isProtected(stored)) return stored;
    if (!available) return null;
    try {
      final dec = _run(base64.decode(stored.substring(_prefix.length)), false);
      return dec == null ? null : utf8.decode(dec);
    } catch (_) {
      return null;
    }
  }
}
