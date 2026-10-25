import 'dart:async';

/// Ссылки вида nexus://add/<подписка или ключ> и nexus://import?url=...
/// Используются кнопками в Discord-боте и на сайте.
class DeepLinks {
  static final _ctrl = StreamController<String>.broadcast();

  /// Поток содержимого для импорта (уже извлечённого из ссылки).
  static Stream<String> get stream => _ctrl.stream;

  static String? _pending;

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
        if (i >= 0) value = Uri.decodeComponent(s.substring(i + 4));
      }
    }
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase();
    const allowed = [
      'https://', 'http://', 'vless://', 'vmess://', 'trojan://',
      'ss://', 'socks://', 'hysteria2://', 'hy2://',
    ];
    return allowed.any(lower.startsWith) ? value : null;
  }
}
