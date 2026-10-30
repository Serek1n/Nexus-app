import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models.dart';
import '../l10n.dart';

const supportedSchemes = [
  'vless',
  'vmess',
  'trojan',
  'ss',
  'socks',
  'hysteria2',
  'hy2',
];

String newId() {
  final r = Random.secure();
  return DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      List.generate(4, (_) => r.nextInt(36).toRadixString(36)).join();
}

bool isShareLink(String s) {
  final i = s.indexOf('://');
  if (i <= 0) return false;
  return supportedSchemes.contains(s.substring(0, i).toLowerCase());
}

bool isHttpUrl(String s) =>
    s.startsWith('http://') || s.startsWith('https://');

/// Пытается декодировать base64 (обычный и url-safe, с/без паддинга).
String? tryBase64(String s) {
  var t = s.replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty) return null;
  t = t.replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  try {
    return utf8.decode(base64.decode(t), allowMalformed: true);
  } catch (_) {
    return null;
  }
}

/// Достаёт все поддерживаемые ссылки из произвольного текста
/// (тело подписки в base64 или обычным списком, вставка из буфера).
List<String> extractLinks(String raw) {
  var text = raw.trim();
  if (!text.contains('://')) {
    final decoded = tryBase64(text);
    if (decoded != null && decoded.contains('://')) text = decoded;
  }
  // Повторы (одна ссылка дважды) убираем, порядок сохраняем.
  return text
      .split(RegExp(r'[\r\n\s]+'))
      .map((l) => l.trim())
      .where(isShareLink)
      .toSet()
      .toList();
}

/// Превращает ссылку в профиль. Возвращает null, если ссылку не удалось разобрать.
ServerProfile? profileFromLink(String link, {String? subscriptionId}) {
  try {
    final parsed = V2ray.parseFromURL(link);
    // Проверяем, что конфиг вообще собирается.
    parsed.getFullConfiguration();
    final scheme = link.substring(0, link.indexOf('://')).toLowerCase();
    var name = parsed.remark.trim();
    if (name.isEmpty) name = '${parsed.address}:${parsed.port}';
    return ServerProfile(
      id: newId(),
      link: link,
      name: name,
      protocol: switch (scheme) {
        'ss' => 'Shadowsocks',
        'vless' => 'VLESS',
        'vmess' => 'VMess',
        'trojan' => 'Trojan',
        'socks' => 'SOCKS',
        _ => 'Hysteria2',
      },
      host: parsed.address,
      port: parsed.port,
      subscriptionId: subscriptionId,
    );
  } catch (_) {
    return null;
  }
}

class FetchResult {
  FetchResult(this.servers, this.meta);
  final List<ServerProfile> servers;
  final Subscription meta;
}

/// Ошибка сети, а не ответ сервера: провайдер оборвал соединение,
/// не прошло TLS-рукопожатие, истекло время. Такие подписки пробуем
/// загрузить через туннель Nexus.
bool isTransportError(Object e) =>
    e is IOException || e is TimeoutException || e is http.ClientException;

/// Понятный текст для сетевой ошибки.
String transportErrorText(Object e) {
  if ('$e'.contains('CERTIFICATE_VERIFY_FAILED')) {
    return tr('Сертификат сервера подписки недействителен или просрочен — сообщите владельцу подписки');
  }
  if (e is HandshakeException || e is TlsException ||
      '$e'.contains('Handshake')) {
    return tr('Не удалось установить защищённое соединение с сервером подписки — похоже, адрес блокирует провайдер. Подключитесь к VPN и повторите');
  }
  if (e is TimeoutException) return tr('Сервер подписки не ответил вовремя');
  return tr('Сервер подписки недоступен — проверьте интернет или подключитесь к VPN');
}

bool _isLoopback(String host) {
  final h = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
  return h == 'localhost' ||
      h.endsWith('.localhost') ||
      h.startsWith('127.') ||
      h == '0.0.0.0' ||
      h == '::1' ||
      h == '::';
}

class SubscriptionService {
  /// Случайный идентификатор этой установки (задаёт AppState при запуске).
  static String? deviceId;

  /// Версия Nexus для User-Agent (задаёт AppState). Начало «v2rayNG» —
  /// чтобы панели отдавали обычный список ссылок.
  static String appVersion = '';
  static String get userAgent =>
      'v2rayNG/1.10.0 Nexus/${appVersion.isEmpty ? '2' : appVersion}';

  /// Разбор заголовка subscription-userinfo:
  /// «upload=..; download=..; total=..; expire=..». Числа бывают дробными.
  static void applyUserInfo(Subscription sub, String? info) {
    if (info == null) return;
    for (final part in info.split(';')) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      final n = num.tryParse(kv[1].trim());
      final v = n == null || n.isNaN || n.isInfinite || n < 0 ? 0 : n.toInt();
      switch (kv[0].trim().toLowerCase()) {
        case 'upload':
          sub.upload = v;
        case 'download':
          sub.download = v;
        case 'total':
          sub.total = v;
        case 'expire':
          // Секунды; 0 — бессрочно. Явный мусор (до 2001 или после 2200
          // года) тоже считаем «бессрочно».
          sub.expire = v > 1000000000 && v < 7258118400
              ? DateTime.fromMillisecondsSinceEpoch(v * 1000)
              : null;
      }
    }
  }

  /// profile-update-interval: часы, от 1 до 168; иначе null.
  static int? updateHours(String? v) {
    final h = int.tryParse(v?.trim() ?? '');
    return h == null || h < 1 || h > 168 ? null : h;
  }

  static String? _decodeHeader(String? v) {
    if (v == null || v.isEmpty) return null;
    if (v.startsWith('base64:')) {
      return tryBase64(v.substring(7))?.trim();
    }
    return v.trim();
  }

  /// Только http(s)-ссылки разумной длины.
  static String? _safeUrl(String? v) {
    if (v == null || v.length > 500) return null;
    final u = Uri.tryParse(v);
    return u != null && (u.scheme == 'https' || u.scheme == 'http') ? v : null;
  }

  /// Загружает подписку и обновляет [sub] (трафик, срок, название).
  static Future<FetchResult> fetch(Subscription sub, {String? proxy}) async {
    final uri = Uri.tryParse(sub.url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw Exception(tr('Ссылка подписки должна начинаться с https://'));
    }
    if (_isLoopback(uri.host)) {
      throw Exception(tr('Подписка указывает на адрес этого устройства — загрузка остановлена'));
    }
    // Читаем потоком и обрываем на 8 МБ: «бесконечный» ответ сервера
    // не должен съесть память устройства.
    const limit = 8 * 1024 * 1024;
    // proxy — «user:pass@127.0.0.1:port» временного туннеля Nexus.
    final http.Client client = proxy == null
        ? http.Client()
        : IOClient(HttpClient()..findProxy = (_) => 'PROXY $proxy');
    late http.StreamedResponse res;
    final bytes = <int>[];
    try {
      // Перенаправления проверяем сами: с https на http не идём (ссылка
      // с ключами ушла бы открытым текстом), на адреса самого устройства —
      // тоже. Идентификатор устройства отдаём только исходному серверу.
      var current = uri;
      for (var hop = 0;; hop++) {
        final req = http.Request('GET', current)
          ..followRedirects = false
          ..headers['User-Agent'] = userAgent
          ..headers['Accept'] = '*/*';
        // Идентификатор устройства для панелей с лимитом устройств (3x-ui,
        // Remnawave): без него такая подписка отвечает 404. Это случайное
        // число, созданное при установке Nexus, — не серийный номер.
        if (deviceId != null && current.host == uri.host) {
          req.headers['X-HWID'] = deviceId!;
          req.headers['X-Device-OS'] =
              Platform.isAndroid ? 'Android' : 'Windows';
          req.headers['X-Device-Model'] = 'Nexus';
          final ver = Platform.operatingSystemVersion;
          req.headers['X-Ver-OS'] =
              ver.length > 60 ? ver.substring(0, 60) : ver;
        }
        res = await client.send(req).timeout(const Duration(seconds: 20));
        if (!const [301, 302, 303, 307, 308].contains(res.statusCode)) break;
        await res.stream.drain<void>().catchError((_) {});
        final loc = res.headers['location'];
        final next = loc == null ? null : current.resolve(loc);
        if (next == null || hop >= 5) {
          throw Exception(tr('Сервер подписки отвечает бесконечными перенаправлениями'));
        }
        if (!(next.scheme == 'https' || next.scheme == 'http') ||
            (current.scheme == 'https' && next.scheme == 'http')) {
          throw Exception(tr('Сервер подписки перенаправил на незащищённый адрес — загрузка остановлена'));
        }
        if (_isLoopback(next.host)) {
          throw Exception(tr('Подписка указывает на адрес этого устройства — загрузка остановлена'));
        }
        current = next;
      }
      if (res.statusCode == 404) {
        if (res.headers['x-hwid-max-devices-reached'] == 'true') {
          throw Exception(tr('Лимит устройств подписки исчерпан — отключите старое устройство в боте или попросите увеличить лимит'));
        }
        throw Exception(tr('Подписка не найдена (404) — проверьте ссылку: возможно, она устарела, клиент удалён или срок истёк'));
      }
      if (res.statusCode != 200) {
        throw Exception(tr('Сервер ответил кодом {0}', [res.statusCode]));
      }
      await for (final chunk
          in res.stream.timeout(const Duration(seconds: 30))) {
        bytes.addAll(chunk);
        if (bytes.length > limit) {
          throw Exception(tr('Подписка слишком большая (больше 8 МБ)'));
        }
      }
    } finally {
      client.close();
    }
    final body = utf8.decode(bytes, allowMalformed: true);
    final links = extractLinks(body);
    if (links.isEmpty) {
      throw Exception(tr('В подписке не найдено ни одного сервера'));
    }

    final servers = <ServerProfile>[];
    for (final l in links.take(1000)) {
      final p = profileFromLink(l, subscriptionId: sub.id);
      // Сервер из подписки не может указывать на сам компьютер/телефон:
      // так чужая подписка могла бы стучаться в локальные службы устройства.
      if (p != null && !_isLoopback(p.host)) servers.add(p);
    }
    if (servers.isEmpty) {
      throw Exception(tr('Не удалось разобрать ссылки из подписки'));
    }

    applyUserInfo(sub, res.headers['subscription-userinfo']);
    sub.updateHours = updateHours(res.headers['profile-update-interval']);

    // Тексты из заголовков сервера ограничиваем по длине.
    String? cap(String? v, int n) =>
        v == null ? null : (v.length > n ? '${v.substring(0, n)}…' : v);
    final title = cap(_decodeHeader(res.headers['profile-title']), 60);
    if (title != null && title.isNotEmpty) {
      sub.title = title;
    } else if (sub.title == 'Подписка') {
      sub.title = titleFromUrl(sub.url);
    }
    sub.supportUrl = _safeUrl(_decodeHeader(res.headers['support-url']));
    sub.webPageUrl =
        _safeUrl(_decodeHeader(res.headers['profile-web-page-url']));
    sub.announce = cap(_decodeHeader(res.headers['announce']), 500);
    sub.updatedAt = DateTime.now();

    return FetchResult(servers, sub);
  }
}
