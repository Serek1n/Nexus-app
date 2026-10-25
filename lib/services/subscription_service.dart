import 'dart:convert';
import 'dart:math';

import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

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
  return text
      .split(RegExp(r'[\r\n\s]+'))
      .map((l) => l.trim())
      .where(isShareLink)
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

class SubscriptionService {
  static const userAgent = 'v2rayNG/1.10.0 Nexus/1.0';

  static String? _decodeHeader(String? v) {
    if (v == null || v.isEmpty) return null;
    if (v.startsWith('base64:')) {
      return tryBase64(v.substring(7))?.trim();
    }
    return v.trim();
  }

  /// Загружает подписку и обновляет [sub] (трафик, срок, название).
  static Future<FetchResult> fetch(Subscription sub) async {
    final uri = Uri.tryParse(sub.url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw Exception('Ссылка подписки должна начинаться с https://');
    }
    final res = await http.get(uri, headers: {
      'User-Agent': userAgent,
      'Accept': '*/*',
    }).timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('Сервер ответил кодом ${res.statusCode}');
    }

    // Защита от слишком больших ответов.
    if (res.bodyBytes.length > 8 * 1024 * 1024) {
      throw Exception('Подписка слишком большая (больше 8 МБ)');
    }
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final links = extractLinks(body);
    if (links.isEmpty) {
      throw Exception('В подписке не найдено ни одного сервера');
    }

    final servers = <ServerProfile>[];
    for (final l in links.take(1000)) {
      final p = profileFromLink(l, subscriptionId: sub.id);
      if (p != null) servers.add(p);
    }
    if (servers.isEmpty) {
      throw Exception('Не удалось разобрать ссылки из подписки');
    }

    // subscription-userinfo: upload=..; download=..; total=..; expire=..
    final info = res.headers['subscription-userinfo'];
    if (info != null) {
      for (final part in info.split(';')) {
        final kv = part.split('=');
        if (kv.length != 2) continue;
        final v = int.tryParse(kv[1].trim()) ?? 0;
        switch (kv[0].trim().toLowerCase()) {
          case 'upload':
            sub.upload = v;
          case 'download':
            sub.download = v;
          case 'total':
            sub.total = v;
          case 'expire':
            sub.expire =
                v > 0 ? DateTime.fromMillisecondsSinceEpoch(v * 1000) : null;
        }
      }
    }

    final title = _decodeHeader(res.headers['profile-title']);
    if (title != null && title.isNotEmpty) sub.title = title;
    sub.supportUrl = _decodeHeader(res.headers['support-url']);
    sub.webPageUrl = _decodeHeader(res.headers['profile-web-page-url']);
    sub.announce = _decodeHeader(res.headers['announce']);
    sub.updatedAt = DateTime.now();

    return FetchResult(servers, sub);
  }
}
