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

  /// Скорость загрузки через сервер, Мбит/с (проверка «Скорость всех»,
  /// не сохраняется). 0 — проверка не удалась.
  double? mbps;

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

/// Строка правила — IPv4-адрес или подсеть («1.2.3.4», «10.0.0.0/8»).
bool isIpRule(String t) {
  final m = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:/(\d{1,2}))?$')
      .firstMatch(t);
  if (m == null) return false;
  for (var i = 1; i <= 4; i++) {
    if (int.parse(m[i]!) > 255) return false;
  }
  return m[5] == null || int.parse(m[5]!) <= 32;
}

/// Разбор своих правил: по одному сайту или IP в строке. Принимает
/// «https://site.com/path», «*.site.com», «site.com», «1.2.3.4», «10.0.0.0/8».
List<String> parseRuleList(String text) {
  final out = <String>{};
  for (var t in text.split(RegExp(r'[\s,;]+'))) {
    t = t.trim().toLowerCase();
    if (t.isEmpty) continue;
    t = t.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
    // Путь отрезаем, но маску подсети «10.0.0.0/8» оставляем.
    if (!RegExp(r'^\d+\.\d+\.\d+\.\d+/\d+$').hasMatch(t)) {
      t = t.split('/').first;
    }
    t = t.replaceFirst(RegExp(r'^\*?\.'), '');
    // Похоже на адрес, но не адрес («999.1.1.1», «10.0.0.0/99») — пропускаем.
    final ipLike = RegExp(r'^[\d.]+(/\d+)?$').hasMatch(t);
    if (ipLike ? isIpRule(t) : RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$').hasMatch(t)) {
      out.add(t);
    } else if (RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+:\d+$').hasMatch(t)) {
      out.add(t.split(':').first);
    }
    if (out.length >= 300) break;
  }
  return out.toList();
}

/// Разбор списка программ Windows: по одной в строке, «Discord.exe»,
/// «chrome» или полный путь — остаётся имя файла.
List<String> parseProcessList(String text) {
  final out = <String>{};
  for (var t in text.split(RegExp(r'[\r\n,;]+'))) {
    t = t.trim().replaceAll('"', '');
    if (t.isEmpty) continue;
    t = t.split(RegExp(r'[\\/]')).last.trim();
    if (!t.toLowerCase().endsWith('.exe')) t = '$t.exe';
    if (RegExp(r'^[\w .()+-]{1,60}\.exe$', unicode: true).hasMatch(t)) out.add(t);
    if (out.length >= 50) break;
  }
  return out.toList();
}

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
    this.updateHours,
    List<String>? mirrors,
  }) : mirrors = mirrors ?? [];

  final String id;
  String url;

  /// Запасные адреса той же подписки: если основной адрес заблокирован,
  /// Nexus обновляет подписку с них (только https).
  List<String> mirrors;
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

  /// Как часто обновлять подписку (часы) — по заголовку
  /// profile-update-interval от панели; null — по умолчанию.
  int? updateHours;

  /// Почему не удалось последнее обновление (не сохраняется).
  String? error;

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
        'updateHours': updateHours,
        if (mirrors.isNotEmpty) 'mirrors': mirrors,
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
        updateHours: (j['updateHours'] as num?)?.toInt(),
        mirrors: cleanMirrors(
            (j['mirrors'] as List?)?.whereType<String>() ?? const []),
      );
}

/// Одна и та же подписка с разными «хвостами» (#?providerid=… от Happ,
/// слэш в конце, регистр домена) — это одна подписка.
String subscriptionKey(String url) {
  var u = url.trim();
  final h = u.indexOf('#');
  if (h >= 0) u = u.substring(0, h);
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  final p = Uri.tryParse(u);
  if (p == null || p.host.isEmpty) return u;
  return p.replace(host: p.host.toLowerCase()).toString();
}

/// Запасные адреса подписки: только https, без повторов, не больше 5.
List<String> cleanMirrors(Iterable<String> xs, {String? except}) {
  final out = <String>[];
  for (final raw in xs) {
    final m = raw.trim();
    final u = Uri.tryParse(m);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) continue;
    if (m.length > 2048 || m == except || out.contains(m)) continue;
    out.add(m);
    if (out.length == 5) break;
  }
  return out;
}

/// smart — российское напрямую, остальное через VPN; global — всё через VPN;
/// blocked — через VPN только заблокированное, остальное напрямую.
enum RoutingMode { global, smart, blocked }

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
    this.iosKillSwitch = false,
    this.bootConnect = false,
    this.windowsTun = false,
    this.clearClipboard = true,
    this.autoFailover = true,
    this.autoReconnect = true,
    this.blockAds = false,
    this.antiBlock = false,
    this.antiBlockFast = false,
    this.pinHash,
    this.hotkey = true,
    this.proMode = false,
    this.theme = 'dark',
    this.autoMode = false,
    this.language = 'system',
    this.socksAuth = false,
    List<String>? autoExclude,
    List<String>? appsProxy,
    this.onboarded = false,
    this.dns = 'cloudflare',
    this.betaUpdates = false,
    List<String>? appsDirect,
    this.socksUser = '',
    this.socksPass = '',
    List<String>? favorites,
    this.lastAppCheck = 0,
    this.skippedBuild = 0,
    Map<String, String>? aliases,
    List<String>? customProxy,
    List<String>? customDirect,
    List<String>? bypassApps,
  })  : bypassApps = bypassApps ?? [],
        favorites = favorites ?? [],
        aliases = aliases ?? {},
        customProxy = customProxy ?? [],
        customDirect = customDirect ?? [],
        autoExclude = autoExclude ?? [],
        appsProxy = appsProxy ?? [],
        appsDirect = appsDirect ?? [];

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

  /// iPhone: весь трафик только через туннель (includeAllNetworks). Выключен
  /// по умолчанию: у Apple с ним бывают сбои AirDrop и CarPlay.
  bool iosKillSwitch;

  /// Android: подключаться после перезагрузки телефона (без открытия Nexus).
  bool bootConnect;

  /// Windows: режим TUN — через Nexus идут все программы (нужны права администратора).
  bool windowsTun;

  /// Избранные серверы (ключ — название и адрес, переживает обновление подписки).
  List<String> favorites;

  /// Держать соединение: переподключаться при обрыве и проверять канал.
  bool autoReconnect;

  /// Если сервер не пропускает трафик — переключаться на следующий.
  bool autoFailover;

  /// Блокировать рекламу и трекеры (geosite:category-ads-all).
  bool blockAds;

  /// Маскировка соединения: фрагментация первого пакета к серверу.
  bool antiBlock;

  /// Маскировка «Быстрая»: паузы только между первыми кусками пакета.
  bool antiBlockFast;

  /// Вход по PIN-коду: отпечаток PIN (см. services/pin.dart) или null.
  String? pinHash;

  /// Windows: Ctrl+Alt+N — подключить/отключить из любой программы.
  bool hotkey;

  /// Режим настроек: false — «Пользователь» (только нужное для обычной
  /// работы), true — «Про» (все настройки). Скрытые настройки при этом
  /// продолжают действовать.
  bool proMode;

  /// Оформление: dark, light или system.
  String theme;

  /// Режим «Авто»: Nexus сам держит соединение через самый быстрый сервер.
  bool autoMode;

  /// Язык интерфейса: 'system', 'ru' или 'en'.
  String language;

  /// Windows: локальный SOCKS-прокси с логином и паролем.
  bool socksAuth;

  /// Серверы («адрес:порт»), которые режим «Авто» не использует.
  List<String> autoExclude;

  /// Windows: программы (имена процессов), которые всегда идут через VPN
  /// или всегда напрямую.
  List<String> appsProxy;
  List<String> appsDirect;



  /// Экран первого запуска пройден или пропущен.
  bool onboarded;

  /// DNS: cloudflare, google, quad9 или adguard (с блокировкой рекламы).
  String dns;

  /// Получать бета-версии (пробные сборки) раньше остальных.
  bool betaUpdates;
  String socksUser;
  String socksPass;

  /// Очищать буфер обмена после импорта ключа или подписки.
  bool clearClipboard;

  /// Проверять и скачивать обновления приложения автоматически.
  bool autoUpdateApp;
  int lastAppCheck;

  /// Свои названия серверов: «адрес:порт» → название.
  Map<String, String> aliases;

  /// Свои правила: сайты и IP, которые всегда идут через VPN / напрямую.
  List<String> customProxy;
  List<String> customDirect;

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
        'iosKillSwitch': iosKillSwitch,
        'bootConnect': bootConnect,
        'windowsTun': windowsTun,
        'clearClipboard': clearClipboard,
        'autoFailover': autoFailover,
        'autoReconnect': autoReconnect,
        'blockAds': blockAds,
        'antiBlock': antiBlock,
        'antiBlockFast': antiBlockFast,
        if (pinHash != null) 'pinHash': pinHash,
        'hotkey': hotkey,
        'proMode': proMode,
        'theme': theme,
        'autoMode': autoMode,
        'language': language,
        'socksAuth': socksAuth,
        'autoExclude': autoExclude,
        'appsProxy': appsProxy,
        'appsDirect': appsDirect,
        'onboarded': onboarded,
        'dns': dns,
        'betaUpdates': betaUpdates,
        'socksUser': socksUser,
        'socksPass': socksPass,
        'favorites': favorites,
        'lastAppCheck': lastAppCheck,
        'skippedBuild': skippedBuild,
        'aliases': aliases,
        'customProxy': customProxy,
        'customDirect': customDirect,
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
        iosKillSwitch: j['iosKillSwitch'] as bool? ?? false,
        bootConnect: j['bootConnect'] as bool? ?? false,
        windowsTun: j['windowsTun'] as bool? ?? false,
        clearClipboard: j['clearClipboard'] as bool? ?? true,
        autoFailover: j['autoFailover'] as bool? ?? true,
        autoReconnect: j['autoReconnect'] as bool? ?? true,
        blockAds: j['blockAds'] as bool? ?? false,
        antiBlock: j['antiBlock'] as bool? ?? false,
        antiBlockFast: j['antiBlockFast'] as bool? ?? false,
        pinHash: j['pinHash'] as String?,
        hotkey: j['hotkey'] as bool? ?? true,
        // Кто пользовался Nexus до появления режимов, остаётся в «Про»:
        // у них всё уже настроено, ничего не прячем.
        proMode: j['proMode'] as bool? ?? true,
        theme: const ['dark', 'light', 'system'].contains(j['theme'])
            ? j['theme'] as String
            : 'dark',
        autoMode: j['autoMode'] as bool? ?? false,
        language: j['language'] as String? ?? 'system',
        socksAuth: j['socksAuth'] as bool? ?? false,
        autoExclude: (j['autoExclude'] as List?)?.whereType<String>().toList(),
        appsProxy: (j['appsProxy'] as List?)?.whereType<String>().toList(),
        appsDirect: (j['appsDirect'] as List?)?.whereType<String>().toList(),
        onboarded: j['onboarded'] as bool? ?? false,
        dns: j['dns'] as String? ?? 'cloudflare',
        betaUpdates: j['betaUpdates'] as bool? ?? false,
        socksUser: j['socksUser'] as String? ?? '',
        socksPass: j['socksPass'] as String? ?? '',
        favorites: (j['favorites'] as List?)?.whereType<String>().toList(),
        lastAppCheck: (j['lastAppCheck'] as num?)?.toInt() ?? 0,
        skippedBuild: (j['skippedBuild'] as num?)?.toInt() ?? 0,
        aliases: (j['aliases'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString())),
        customProxy:
            (j['customProxy'] as List?)?.whereType<String>().toList(),
        customDirect:
            (j['customDirect'] as List?)?.whereType<String>().toList(),
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
