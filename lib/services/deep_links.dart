import 'dart:async';

/// Ссылки вида nexus://add/<подписка или ключ> и nexus://import?url=...
/// Используются кнопками в Discord-боте и на сайте.
class DeepLinks {
  static final _ctrl = StreamController<String>.broadcast();

  /// Поток содержимого для импорта (уже извлечённого из ссылки).
  static Stream<String> get stream => _ctrl.stream;

  static String? _pending;

  /// Запасные адреса подписки из ссылки (…&mirror=https://…), по адресу
  /// подписки. Забираются при добавлении подписки.
  static final _mirrors = <String, List<String>>{};

  static List<String> takeMirrors(String url) => _mirrors.remove(url) ?? const [];

  /// Посмотреть, не забирая (для окна подтверждения).
  static List<String> peekMirrors(String url) => _mirrors[url] ?? const [];

  /// Пользователь отказался добавлять — запасные адреса тоже забываем.
  static void dropMirrors(String url) => _mirrors.remove(url);

  /// Ссылка, пришедшая до того, как интерфейс был готов.
  static String? takePending() {
    final p = _pending;
    _pending = null;
    return p;
  }

  /// Принимает «сырую» ссылку nexus://… и, если она корректна, публикует её.
  static void handle(String raw) {
    final payload = parse(raw);
    if (payload == null) return;
    if (_ctrl.hasListener) {
      _ctrl.add(payload);
    } else {
      _pending = payload;
    }
  }

  /// Возвращает ссылку на подписку или ключ из nexus://-ссылки.
  static String? parse(String raw) {
    final s = raw.trim();
    if (s.length > 8192) return null;
    final uri = Uri.tryParse(s);
    if (uri == null || uri.scheme.toLowerCase() != 'nexus') return null;
    String? value;
    if (uri.host == 'import' || uri.host == 'add') {
      value = uri.queryParameters['url'];
      if (value == null && uri.host == 'add') {
        // nexus://add/<url> — всё после «add/» как есть.
        final i = s.indexOf('add/');
        if (i >= 0) {
          try {
            value = Uri.decodeComponent(s.substring(i + 4));
          } catch (_) {
            return null; // битая %-последовательность
          }
        }
      }
    }
    if (value == null || value.isEmpty) return null;
    // Переводы строк и управляющие символы в ссылке — признак подмены.
    if (value.codeUnits.any((c) => c < 0x20 || c == 0x7f)) return null;
    final lower = value.toLowerCase();
    // Запасные адреса: только https и только вместе с https-подпиской.
    if (lower.startsWith('https://')) {
      final ms = [
        for (final m in uri.queryParametersAll['mirror'] ?? const <String>[])
          if (m.toLowerCase().startsWith('https://') &&
              !m.codeUnits.any((c) => c < 0x20 || c == 0x7f))
            m,
      ].take(5).toList();
      if (ms.isNotEmpty) _mirrors[value] = ms;
    }
    const allowed = [
      'https://', 'http://', 'vless://', 'vmess://', 'trojan://',
      'ss://', 'socks://', 'hysteria2://', 'hy2://', 'wireguard://', 'wg://',
    ];
    return allowed.any(lower.startsWith) ? value : null;
  }
}

/// Ссылки «Открыть в …» других клиентов (Happ, Hiddify, v2rayNG, v2rayN,
/// sing-box, Clash, Streisand, Karing, V2Box, FlClash): достаём из них
/// ссылку подписки или ключ, чтобы такие кнопки из ботов и с сайтов
/// работали и в Nexus. Возвращает null, если это не такая ссылка.
String? unwrapForeignLink(String raw) {
  final s = raw.trim();
  if (s.length > 8192 || s.contains('\n')) return null;
  final i = s.indexOf('://');
  if (i <= 0) return null;
  final scheme = s.substring(0, i).toLowerCase();
  const known = {
    'happ', 'hiddify', 'v2rayng', 'v2rayn', 'sing-box', 'clash',
    'clashmeta', 'clashx', 'streisand', 'karing', 'v2box', 'flclash',
    'nekobox', 'foxray', 'shadowrocket',
  };
  if (!known.contains(scheme)) return null;
  String? value;
  final uri = Uri.tryParse(s);
  final q = uri?.queryParameters ?? const <String, String>{};
  value = q['url'] ?? q['link'];
  if (value == null) {
    // happ://add/<…>, hiddify://import/<…>, streisand://import/<…>
    final m = RegExp(r'^[a-z0-9-]+://(?:add|import|install-config|install-sub|sub)/(.+)$',
            caseSensitive: false)
        .firstMatch(s);
    if (m != null) {
      value = m.group(1);
      try {
        if (value != null && value.contains('%')) value = Uri.decodeComponent(value);
      } catch (_) {
        return null;
      }
    }
  }
  if (value == null) return null;
  value = value.trim();
  if (value.codeUnits.any((c) => c < 0x20 || c == 0x7f)) return null;
  final lower = value.toLowerCase();
  const allowed = [
    'https://', 'http://', 'vless://', 'vmess://', 'trojan://', 'ss://',
    'socks://', 'hysteria2://', 'hy2://', 'wireguard://', 'wg://',
  ];
  return allowed.any(lower.startsWith) ? value : null;
}
