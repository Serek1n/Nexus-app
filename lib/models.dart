import 'dart:convert';

/// Один сервер (одна ссылка vless:// / vmess:// / trojan:// / ss:// ...).
class ServerProfile {
  ServerProfile({
    required this.id,
    required this.link,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    this.subscriptionId,
    this.ping,
  });

  final String id;
  final String link;
  final String name;
  final String protocol;
  final String host;
  final int port;

  /// null — сервер добавлен вручную.
  final String? subscriptionId;

  /// Задержка в мс; -1 — недоступен; null — не измерялась.
  int? ping;

  Map<String, dynamic> toJson() => {
        'id': id,
        'link': link,
        'name': name,
        'protocol': protocol,
        'host': host,
        'port': port,
        'subscriptionId': subscriptionId,
      };

  factory ServerProfile.fromJson(Map<String, dynamic> j) => ServerProfile(
        id: j['id'] as String,
        link: j['link'] as String,
        name: j['name'] as String? ?? 'Сервер',
        protocol: j['protocol'] as String? ?? '',
        host: j['host'] as String? ?? '',
        port: (j['port'] as num?)?.toInt() ?? 443,
        subscriptionId: j['subscriptionId'] as String?,
      );

  /// Флаг-эмодзи из названия, если есть (3x-ui часто кладёт его в remark).
  String? get flag {
    final runes = name.runes.toList();
    for (var i = 0; i < runes.length - 1; i++) {
      final a = runes[i], b = runes[i + 1];
      if (a >= 0x1F1E6 && a <= 0x1F1FF && b >= 0x1F1E6 && b <= 0x1F1FF) {
        return String.fromCharCodes([a, b]);
      }
    }
    return null;
  }

  /// Название без флага — для аккуратного отображения.
  String get cleanName {
    final f = flag;
    final n = (f == null ? name : name.replaceFirst(f, '')).trim();
    return n.isEmpty ? host : n;
  }
}

/// Подписка 3x-ui / Marzban / любой панели, отдающей список ссылок.
class Subscription {
  Subscription({
    required this.id,
    required this.url,
    required this.title,
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire,
    this.updatedAt,
    this.supportUrl,
    this.webPageUrl,
    this.announce,
  });

  final String id;
  String url;
  String title;
  int upload;
  int download;

  /// 0 — безлимит.
  int total;
  DateTime? expire;
  DateTime? updatedAt;
  String? supportUrl;
  String? webPageUrl;
  String? announce;

  int get used => upload + download;

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'upload': upload,
        'download': download,
        'total': total,
        'expire': expire?.millisecondsSinceEpoch,
        'updatedAt': updatedAt?.millisecondsSinceEpoch,
        'supportUrl': supportUrl,
        'webPageUrl': webPageUrl,
        'announce': announce,
      };

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'] as String,
        url: j['url'] as String,
        title: j['title'] as String? ?? 'Подписка',
        upload: (j['upload'] as num?)?.toInt() ?? 0,
        download: (j['download'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        expire: j['expire'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['expire'] as num).toInt()),
        updatedAt: j['updatedAt'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (j['updatedAt'] as num).toInt()),
        supportUrl: j['supportUrl'] as String?,
        webPageUrl: j['webPageUrl'] as String?,
        announce: j['announce'] as String?,
      );
}

enum RoutingMode { global, smart }

enum ConnState { disconnected, connecting, connected, disconnecting }

class AppSettings {
  AppSettings({
    this.routing = RoutingMode.smart,
    this.androidVpnMode = true,
    this.windowsSystemProxy = true,
    this.autoUpdateOnStart = true,
    this.autoConnectOnStart = false,
  });

  RoutingMode routing;

  /// true — VPN (весь трафик устройства), false — только локальный прокси.
  bool androidVpnMode;

  /// Включать системный прокси Windows при подключении.
  bool windowsSystemProxy;
  bool autoUpdateOnStart;
  bool autoConnectOnStart;

  String toJsonString() => jsonEncode({
        'routing': routing.name,
        'androidVpnMode': androidVpnMode,
        'windowsSystemProxy': windowsSystemProxy,
        'autoUpdateOnStart': autoUpdateOnStart,
        'autoConnectOnStart': autoConnectOnStart,
      });

  factory AppSettings.fromJsonString(String? s) {
    if (s == null) return AppSettings();
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      return AppSettings(
        routing: RoutingMode.values.firstWhere((e) => e.name == j['routing'],
            orElse: () => RoutingMode.smart),
        androidVpnMode: j['androidVpnMode'] as bool? ?? true,
        windowsSystemProxy: j['windowsSystemProxy'] as bool? ?? true,
        autoUpdateOnStart: j['autoUpdateOnStart'] as bool? ?? true,
        autoConnectOnStart: j['autoConnectOnStart'] as bool? ?? false,
      );
    } catch (_) {
      return AppSettings();
    }
  }
}

/// Живая статистика соединения.
class ConnStats {
  const ConnStats({
    this.uploadSpeed = 0,
    this.downloadSpeed = 0,
    this.upload = 0,
    this.download = 0,
  });
  final int uploadSpeed;
  final int downloadSpeed;
  final int upload;
  final int download;
}
