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

  /// Своё название, заданное пользователем (переживает обновление подписки).
  String? alias;

  /// Ключ для своего названия: адрес сервера не меняется при обновлении.
  String get aliasKey => '$host:$port';

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

  /// Код страны (две строчные буквы): из флага-эмодзи, а если его нет —
  /// из названия («Германия», «Germany», «DE-1», «nl_ams»).
  String? get countryCode {
    final f = flag;
    if (f != null) {
      return String.fromCharCodes(f.runes.map((r) => r - 0x1F1E6 + 97));
    }
    return countryFromText(name);
  }

  /// Транспорт и защита из ссылки: «Reality · TCP», «TLS · WS».
  String get transport {
    final q = link.indexOf('?');
    if (q < 0) return '';
    var query = link.substring(q + 1);
    final h = query.indexOf('#');
    if (h >= 0) query = query.substring(0, h);
    Map<String, String> m;
    try {
      m = Uri.splitQueryString(query);
    } catch (_) {
      return '';
    }
    final sec = switch (m['security']?.toLowerCase()) {
      'reality' => 'Reality',
      'tls' => 'TLS',
      _ => null,
    };
    final type = m['type']?.toLowerCase();
    final net = switch (type) {
      null || '' => null,
      'xhttp' || 'splithttp' => 'XHTTP',
      'httpupgrade' => 'HTTPUpgrade',
      final t => t.toUpperCase(),
    };
    return [if (sec != null) sec, if (net != null) net].join(' · ');
  }

  /// В названии нет ни одной буквы (только номер) — показываем адрес.
  bool get nameIsBare => !RegExp(r'\p{L}', unicode: true).hasMatch(cleanName);

  /// Устойчивый ключ для избранного.
  String get favKey => '$name|$host:$port';

  /// Название без флага — для аккуратного отображения.
  String get cleanName {
    if (alias != null && alias!.trim().isNotEmpty) return alias!.trim();
    final f = flag;
    final n = (f == null ? name : name.replaceFirst(f, '')).trim();
    return n.isEmpty ? host : n;
  }
}

/// Страна по тексту названия сервера.
String? countryFromText(String text) {
  final t = ' ${text.toLowerCase()} ';
  for (final e in _countryWords.entries) {
    for (final w in e.value) {
      if (t.contains(w)) return e.key;
    }
  }
  // Код страны отдельным словом: «DE», «nl-1», «US_west».
  final m = RegExp(r'(?:^|[^a-z])([a-z]{2})(?:[^a-z]|$)')
      .allMatches(text.toLowerCase());
  for (final x in m) {
    final c = x.group(1)!;
    if (_codes.contains(c)) return c == 'uk' ? 'gb' : c;
  }
  return null;
}

const _codes = {
  'ru', 'de', 'nl', 'fi', 'se', 'dk', 'ee', 'lv', 'lt', 'pl', 'cz',
  'ch', 'fr', 'gb', 'uk', 'us', 'ca', 'tr', 'kz', 'ge', 'ae',
  'jp', 'kr', 'sg', 'hk', 'tw', 'il', 'es', 'pt', 'ie',
  'lu', 'ro', 'bg', 'hu', 'rs', 'md', 'ua', 'au', 'br', 'ar', 'mx',
  'cy', 'gr', 'si', 'sk', 'hr', 'az', 'uz', 'kg', 'th',
  'vn', 'za',
};

const _countryWords = <String, List<String>>{
  'ru': ['россия', 'russia', 'москва', 'moscow'],
  'de': ['герман', 'germany', 'deutschland', 'франкфурт', 'frankfurt', 'berlin', 'берлин'],
  'nl': ['нидерланд', 'голланд', 'netherlands', 'holland', 'амстердам', 'amsterdam'],
  'fi': ['финлянд', 'finland', 'хельсинки', 'helsinki'],
  'se': ['швеци', 'sweden', 'стокгольм', 'stockholm'],
  'no': ['норвеги', 'norway'],
  'dk': ['дания', 'дании', 'denmark'],
  'ee': ['эстони', 'estonia', 'таллин', 'tallinn'],
  'lv': ['латви', 'latvia', 'рига', 'riga'],
  'lt': ['литв', 'lithuania', 'вильнюс', 'vilnius'],
  'pl': ['польш', 'poland', 'варшав', 'warsaw'],
  'cz': ['чехи', 'czech', 'прага', 'prague'],
  'at': ['австри', 'austria', 'вена ', 'vienna'],
  'ch': ['швейцари', 'switzerland', 'цюрих', 'zurich'],
  'fr': ['франци', 'france', 'париж', 'paris'],
  'gb': ['великобритан', 'англи', 'united kingdom', 'britain', 'england', 'лондон', 'london'],
  'us': ['сша', 'америк', 'united states', 'usa', 'america', 'нью-йорк', 'new york'],
  'ca': ['канад', 'canada'],
  'tr': ['турци', 'turkey', 'türkiye', 'стамбул', 'istanbul'],
  'kz': ['казахстан', 'kazakhstan', 'алматы', 'almaty'],
  'ge': ['грузия', 'грузии', 'georgia', 'тбилиси', 'tbilisi'],
  'am': ['армени', 'armenia', 'ереван', 'yerevan'],
  'ae': ['оаэ', 'эмират', 'emirates', 'uae', 'дубай', 'dubai'],
  'jp': ['япони', 'japan', 'токио', 'tokyo'],
  'kr': ['корея', 'корее', 'korea', 'сеул', 'seoul'],
  'sg': ['сингапур', 'singapore'],
  'hk': ['гонконг', 'hong kong', 'hongkong'],
  'in': ['индия', 'индии', 'india'],
  'il': ['израил', 'israel'],
  'it': ['итали', 'italy', 'милан', 'milan'],
  'es': ['испани', 'spain', 'мадрид', 'madrid'],
  'pt': ['португал', 'portugal'],
  'ie': ['ирланд', 'ireland'],
  'be': ['бельги', 'belgium'],
  'ro': ['румыни', 'romania'],
  'bg': ['болгари', 'bulgaria'],
  'hu': ['венгри', 'hungary'],
  'rs': ['серби', 'serbia'],
  'md': ['молдов', 'moldova'],
  'ua': ['украин', 'ukraine'],
  'by': ['беларус', 'belarus'],
  'au': ['австрали', 'australia'],
  'br': ['бразили', 'brazil'],
  'cy': ['кипр', 'cyprus'],
  'gr': ['греци', 'greece'],
  'az': ['азербайджан', 'azerbaijan'],
  'uz': ['узбекистан', 'uzbekistan'],
};

/// Название подписки по её адресу, если сервер его не прислал:
/// github.com/user/repo/... → «repo», иначе — домен.
String titleFromUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return 'Подписка';
  final seg = u.pathSegments.where((e) => e.isNotEmpty).toList();
  if ((u.host == 'raw.githubusercontent.com' ||
          u.host == 'github.com' ||
          u.host == 'gist.githubusercontent.com') &&
      seg.length >= 2) {
    return seg[1];
  }
  return u.host.startsWith('www.') ? u.host.substring(4) : u.host;
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
    this.autoUpdateCore = true,
    this.lastCoreCheck = 0,
    this.closeToTray = true,
    this.launchAtStartup = false,
    this.secureScreen = false,
    this.ruAppsDirect = true,
    this.autoUpdateApp = true,
    this.windowsKillSwitch = true,
    this.windowsTun = false,
    this.clearClipboard = true,
    this.autoFailover = true,
    this.autoReconnect = true,
    List<String>? favorites,
    this.lastAppCheck = 0,
    this.skippedBuild = 0,
    Map<String, String>? aliases,
    List<String>? bypassApps,
  })  : bypassApps = bypassApps ?? [],
        favorites = favorites ?? [],
        aliases = aliases ?? {};

  RoutingMode routing;

  /// true — VPN (весь трафик устройства), false — только локальный прокси.
  bool androidVpnMode;

  /// Включать системный прокси Windows при подключении.
  bool windowsSystemProxy;
  bool autoUpdateOnStart;
  bool autoConnectOnStart;

  /// Windows: автоматически обновлять ядро Xray.
  bool autoUpdateCore;

  /// Время последней проверки обновлений ядра (мс).
  int lastCoreCheck;

  /// Windows: кнопка «закрыть» сворачивает в трей.
  bool closeToTray;

  /// Windows: запускать вместе с системой (свёрнутым в трей).
  bool launchAtStartup;

  /// Android: запрет скриншотов и скрытие в списке недавних.
  bool secureScreen;

  /// Windows: при падении VPN не выпускать трафик мимо него.
  bool windowsKillSwitch;

  /// Windows: режим TUN — через Nexus идут все программы (нужны права администратора).
  bool windowsTun;

  /// Избранные серверы (ключ — название и адрес, переживает обновление подписки).
  List<String> favorites;

  /// Держать соединение: переподключаться при обрыве и проверять канал.
  bool autoReconnect;

  /// Если сервер не пропускает трафик — переключаться на следующий.
  bool autoFailover;

  /// Очищать буфер обмена после импорта ключа или подписки.
  bool clearClipboard;

  /// Проверять и скачивать обновления приложения автоматически.
  bool autoUpdateApp;
  int lastAppCheck;

  /// Свои названия серверов: «адрес:порт» → название.
  Map<String, String> aliases;

  /// После отката: автообновление не предлагает сборки до этой включительно.
  int skippedBuild;

  /// Android, умный режим: российские приложения работают мимо VPN.
  bool ruAppsDirect;

  /// Android: приложения, выбранные пользователем для работы без VPN.
  List<String> bypassApps;

  String toJsonString() => jsonEncode({
        'routing': routing.name,
        'androidVpnMode': androidVpnMode,
        'windowsSystemProxy': windowsSystemProxy,
        'autoUpdateOnStart': autoUpdateOnStart,
        'autoConnectOnStart': autoConnectOnStart,
        'autoUpdateCore': autoUpdateCore,
        'lastCoreCheck': lastCoreCheck,
        'closeToTray': closeToTray,
        'launchAtStartup': launchAtStartup,
        'secureScreen': secureScreen,
        'ruAppsDirect': ruAppsDirect,
        'autoUpdateApp': autoUpdateApp,
        'windowsKillSwitch': windowsKillSwitch,
        'windowsTun': windowsTun,
        'clearClipboard': clearClipboard,
        'autoFailover': autoFailover,
        'autoReconnect': autoReconnect,
        'favorites': favorites,
        'lastAppCheck': lastAppCheck,
        'skippedBuild': skippedBuild,
        'aliases': aliases,
        'bypassApps': bypassApps,
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
        autoUpdateCore: j['autoUpdateCore'] as bool? ?? true,
        lastCoreCheck: (j['lastCoreCheck'] as num?)?.toInt() ?? 0,
        closeToTray: j['closeToTray'] as bool? ?? true,
        launchAtStartup: j['launchAtStartup'] as bool? ?? false,
        secureScreen: j['secureScreen'] as bool? ?? false,
        ruAppsDirect: j['ruAppsDirect'] as bool? ?? true,
        autoUpdateApp: j['autoUpdateApp'] as bool? ?? true,
        windowsKillSwitch: j['windowsKillSwitch'] as bool? ?? true,
        windowsTun: j['windowsTun'] as bool? ?? false,
        clearClipboard: j['clearClipboard'] as bool? ?? true,
        autoFailover: j['autoFailover'] as bool? ?? true,
        autoReconnect: j['autoReconnect'] as bool? ?? true,
        favorites: (j['favorites'] as List?)?.whereType<String>().toList(),
        lastAppCheck: (j['lastAppCheck'] as num?)?.toInt() ?? 0,
        skippedBuild: (j['skippedBuild'] as num?)?.toInt() ?? 0,
        aliases: (j['aliases'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString())),
        bypassApps: (j['bypassApps'] as List?)?.whereType<String>().toList(),
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
