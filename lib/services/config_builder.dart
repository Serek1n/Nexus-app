import 'dart:convert';
import 'dart:math';

import 'package:flutter_v2ray_client/flutter_v2ray.dart';

import '../models.dart';
import '../l10n.dart';

/// Локальные порты ядра на Windows.
const kSocksPort = 10808;
const kHttpPort = 10809;

/// Порты, на которых ядро Windows реально слушает сейчас
/// (если 10808/10809 заняты другой программой — запасные).
int activeSocksPort = kSocksPort;
int activeHttpPort = kHttpPort;

const _privateNets = [
  '10.0.0.0/8',
  '172.16.0.0/12',
  '192.168.0.0/16',
  '127.0.0.0/8',
  '169.254.0.0/16',
  '100.64.0.0/10',
  'fc00::/7',
  'fe80::/10',
  '::1/128',
];

/// Собирает JSON-конфиг Xray из ссылки сервера.
///
/// [desktop] — добавить SOCKS+HTTP входы для системного прокси Windows.
String buildXrayConfig(
  ServerProfile server, {
  required RoutingMode routing,
  required bool desktop,
  bool lockLocalProxy = false,
  List<String> customProxy = const [],
  List<String> customDirect = const [],
  bool blockAds = false,
  bool antiBlock = false,
}) {
  final parsed = V2ray.parseFromURL(server.link);
  final cfg =
      jsonDecode(parsed.getFullConfiguration()) as Map<String, dynamic>;

  // Журнал посещённых сайтов (access log) не ведём: в «Журнале» Nexus
  // остаются только ошибки и предупреждения ядра.
  cfg['log'] = {'loglevel': 'warning', 'access': 'none'};

  if (desktop) {
    cfg['inbounds'] = [
      {
        'tag': 'socks-in',
        'port': kSocksPort,
        'listen': '127.0.0.1',
        'protocol': 'socks',
        'settings': {'auth': 'noauth', 'udp': true},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': true,
        },
      },
      {
        'tag': 'http-in',
        'port': kHttpPort,
        'listen': '127.0.0.1',
        'protocol': 'http',
        'settings': <String, dynamic>{},
        'sniffing': {
          'enabled': true,
          'destOverride': ['http', 'tls'],
          'routeOnly': true,
        },
      },
    ];
  } else {
    // На Android включаем sniffing, чтобы правила по доменам работали в VPN-режиме.
    final inbounds = (cfg['inbounds'] as List?) ?? [];
    for (final ib in inbounds) {
      if (ib is Map<String, dynamic>) {
        ib['sniffing'] = {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': true,
        };
        // В режиме VPN локальный SOCKS не нужен приложениям. Без пароля любое
        // приложение на телефоне могло бы через него узнать IP сервера или
        // обнаружить VPN — закрываем его случайным логином и паролем.
        if (lockLocalProxy && ib['protocol'] == 'socks') {
          final settings =
              (ib['settings'] as Map?)?.cast<String, dynamic>() ?? {};
          settings['auth'] = 'password';
          settings['accounts'] = [
            {'user': _randomToken(), 'pass': _randomToken()},
          ];
          settings['udp'] = false;
          ib['settings'] = settings;
        }
      }
    }
  }

  // Стабильность на мобильной сети: TCP keep-alive не даёт оператору
  // молча закрыть простаивающее соединение (NAT).
  // domainStrategy здесь не задаём: тогда адрес сервера резолвился бы через
  // DNS самого Xray, а тот идёт через этот же сервер — замкнутый круг,
  // и серверы с доменом вместо IP переставали отвечать.
  for (final ob in (cfg['outbounds'] as List? ?? [])) {
    if (ob is Map<String, dynamic> && ob['tag'] == 'proxy') {
      final ss = (ob['streamSettings'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final so = (ss['sockopt'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      so['tcpKeepAliveIdle'] = 30;
      so['tcpKeepAliveInterval'] = 15;
      so.remove('domainStrategy');
      ss['sockopt'] = so;
      ob['streamSettings'] = ss;
    }
  }

  _patchHysteria2(cfg, server.link);
  _patchShareParams(cfg, server.link);
  if (antiBlock) _addFragment(cfg);

  // DNS-over-HTTPS: запросы Xray зашифрованы и идут через сервер —
  // провайдер не видит и не может подменить ответы. Адреса — IP, поэтому
  // отдельный DNS для начального подключения не нужен.
  cfg['dns'] = {
    'servers': [
      'https://1.1.1.1/dns-query',
      'https://8.8.8.8/dns-query',
    ],
    'queryStrategy': 'UseIPv4',
  };

  final rules = <Map<String, dynamic>>[
    {
      'type': 'field',
      'ip': _privateNets,
      'outboundTag': 'direct',
    },
  ];

  // Свои правила пользователя — важнее всех остальных.
  void custom(List<String> items, String tag) {
    final ips = items.where((e) => RegExp(r'^\d').hasMatch(e)).toList();
    final doms = items
        .where((e) => !RegExp(r'^\d').hasMatch(e))
        .map((e) => 'domain:$e')
        .toList();
    if (doms.isNotEmpty) {
      rules.add({'type': 'field', 'domain': doms, 'outboundTag': tag});
    }
    if (ips.isNotEmpty) {
      rules.add({'type': 'field', 'ip': ips, 'outboundTag': tag});
    }
  }

  custom(customDirect, 'direct');
  custom(customProxy, 'proxy');

  // Реклама и трекеры — в «чёрную дыру». Свои правила выше, поэтому
  // нужный сайт можно вернуть, добавив его в «Свои правила».
  if (blockAds) {
    final obs = (cfg['outbounds'] as List?) ?? [];
    if (!obs.any((o) => o is Map && o['tag'] == 'block')) {
      obs.add({'tag': 'block', 'protocol': 'blackhole'});
      cfg['outbounds'] = obs;
    }
    rules.add({
      'type': 'field',
      'domain': ['geosite:category-ads-all'],
      'outboundTag': 'block',
    });
  }

  if (routing == RoutingMode.smart) {
    // Сервисы, заблокированные или замедленные в России, — всегда через
    // сервер. Их CDN часто стоят у российских провайдеров (кэш YouTube,
    // узлы TikTok), и правило «российские IP напрямую» отправило бы видео
    // мимо VPN: YouTube тормозит, TikTok не грузит ленту.
    rules.add({
      'type': 'field',
      'domain': _alwaysProxy,
      'outboundTag': 'proxy',
    });
    // Российские сайты и IP — напрямую, всё остальное — через Nexus.
    rules.addAll([
      {
        'type': 'field',
        'domain': [
          'domain:ru',
          'domain:su',
          'domain:xn--p1ai', // .рф
          'domain:xn--d1acj3b', // .дети
          'domain:moscow',
          'domain:yandex.net',
          'domain:yandex.com',
          'domain:vk.com',
          'domain:userapi.com',
          'domain:vkuser.net',
          'domain:mycdn.me',
          'domain:gosuslugi.ru',
        ],
        'outboundTag': 'direct',
      },
      {
        'type': 'field',
        'ip': ['geoip:ru'],
        'outboundTag': 'direct',
      },
    ]);
  }

  cfg['routing'] = {
    'domainStrategy':
        routing == RoutingMode.smart ? 'IPIfNonMatch' : 'AsIs',
    'rules': rules,
  };

  return jsonEncode(cfg);
}

/// Режим «Авто»: несколько серверов в одном ядре. Xray сам раз в
/// [probeInterval] проверяет каждый (observatory) и отправляет новые соединения через
/// самый быстрый живой сервер (balancer leastPing). Упал сервер — трафик
/// уходит на следующий без переподключения.
///
/// [servers] — от лучшего к худшему; первый — запасной, пока проверка не
/// прошла. Серверы, ссылку которых не удалось разобрать, пропускаются.
String buildAutoConfig(
  List<ServerProfile> servers, {
  required RoutingMode routing,
  required bool desktop,
  bool lockLocalProxy = false,
  List<String> customProxy = const [],
  List<String> customDirect = const [],
  bool blockAds = false,
  bool antiBlock = false,
  String probeInterval = '2m',
}) {
  Map<String, dynamic>? base;
  final proxies = <Map<String, dynamic>>[];
  for (var i = 0; i < servers.length; i++) {
    final s = servers[i];
    final Map<String, dynamic> c;
    try {
      c = jsonDecode(buildXrayConfig(
        s,
        routing: routing,
        desktop: desktop,
        lockLocalProxy: lockLocalProxy,
        customProxy: customProxy,
        customDirect: customDirect,
        blockAds: blockAds,
        antiBlock: antiBlock,
      )) as Map<String, dynamic>;
    } catch (_) {
      continue;
    }
    final ob = (c['outbounds'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .where((o) => o['tag'] == 'proxy')
        .firstOrNull;
    if (ob == null) continue;
    base ??= c;
    // Тег — номер сервера в списке: так по результатам проверки видно,
    // какой именно сервер сейчас самый быстрый.
    proxies.add({...ob, 'tag': '$kAutoPrefix$i'});
  }
  if (base == null) {
    throw Exception(tr('Не удалось разобрать ни один сервер подписки'));
  }
  // Серверы — первыми: плагин Android берёт адрес из первого исходящего.
  base['outbounds'] = [
    ...proxies,
    ...(base['outbounds'] as List)
        .where((o) => !(o is Map && o['tag'] == 'proxy')),
  ];
  final r = (base['routing'] as Map).cast<String, dynamic>();
  final rules = (r['rules'] as List).cast<Map<String, dynamic>>();
  for (final rule in rules) {
    if (rule['outboundTag'] == 'proxy') {
      rule.remove('outboundTag');
      rule['balancerTag'] = 'auto';
    }
  }
  // Всё, что не попало под правила, — тоже через балансировщик
  // (иначе Xray отправил бы это в первый исходящий напрямую).
  rules.add({'type': 'field', 'network': 'tcp,udp', 'balancerTag': 'auto'});
  r['rules'] = rules;
  r['balancers'] = [
    {
      'tag': 'auto',
      'selector': [kAutoPrefix],
      'strategy': {'type': 'leastPing'},
      'fallbackTag': proxies.first['tag'],
    },
  ];
  base['routing'] = r;
  base['observatory'] = {
    'subjectSelector': [kAutoPrefix],
    'probeURL': 'https://www.gstatic.com/generate_204',
    'probeInterval': probeInterval,
    'enableConcurrency': true,
  };
  return jsonEncode(base);
}

/// Префикс тегов серверов в режиме «Авто».
const kAutoPrefix = 'nx-';

/// Обход блокировок: первый пакет соединения с сервером (TLS ClientHello)
/// режется на небольшие TCP-сегменты с паузами. Для сервера это обычный
/// поток TCP, а системам фильтрации провайдера сложнее распознать
/// подключение. Только для TCP-транспортов (Hysteria2 работает по UDP);
/// маски из ссылки 3x-ui (fm) не трогаем.
void _addFragment(Map<String, dynamic> cfg) {
  for (final ob in (cfg['outbounds'] as List? ?? [])) {
    if (ob is! Map<String, dynamic> || ob['tag'] != 'proxy') continue;
    if (ob['protocol'] == 'hysteria') continue;
    final ss = (ob['streamSettings'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    if (const ['kcp', 'mkcp', 'quic', 'hysteria'].contains(ss['network'])) {
      continue;
    }
    final fm = (ss['finalmask'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    if (fm['tcp'] != null) continue;
    fm['tcp'] = [
      {
        'type': 'fragment',
        'settings': {'packets': '1-1', 'length': '100-200', 'delay': '10-20'},
      },
    ];
    ss['finalmask'] = fm;
    ob['streamSettings'] = ss;
  }
}

/// Hysteria2: плагин понимает не все параметры ссылки 3x-ui (alpn, obfs
/// salamander/gecko, mport, ech) — без них сервер не отвечает. Собираем
/// настройки так же, как это делает сама панель 3x-ui для Xray 26.
void _patchHysteria2(Map<String, dynamic> cfg, String link) {
  final scheme = link.split('://').first.toLowerCase();
  if (scheme != 'hysteria2' && scheme != 'hy2') return;
  final uri = Uri.tryParse(link.trim());
  if (uri == null) return;
  final q = uri.queryParameters;
  String? p(List<String> keys) {
    for (final k in keys) {
      final v = q[k]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  for (final ob in (cfg['outbounds'] as List? ?? [])) {
    if (ob is! Map<String, dynamic> || ob['tag'] != 'proxy') continue;
    final ss = (ob['streamSettings'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final tls = (ss['tlsSettings'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    tls['alpn'] = (p(['alpn']) ?? 'h3')
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final sni = p(['sni', 'peer']);
    if (sni != null) tls['serverName'] = sni;
    final fp = p(['fp']);
    if (fp != null) tls['fingerprint'] = fp;
    final ech = p(['ech']);
    if (ech != null) tls['echConfigList'] = ech;
    final vcn = p(['vcn']);
    if (vcn != null) tls['verifyPeerCertByName'] = vcn;
    final pin = p(['pinSHA256', 'pcs']);
    if (pin != null) tls['pinnedPeerCertSha256'] = pin;
    tls.removeWhere((_, v) => v == null);
    ss['security'] = 'tls';
    ss['tlsSettings'] = tls;

    final hs = (ss['hysteriaSettings'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    hs['version'] = 2;
    hs['auth'] ??= Uri.decodeComponent(uri.userInfo);
    hs['udpIdleTimeout'] ??= 60;
    hs.removeWhere((_, v) => v == null);
    ss['hysteriaSettings'] = hs;

    // Плагин Android ищет адрес сервера в settings.vnext или
    // settings.servers; у Hysteria их нет — без этого VPN не запускается
    // и «Подключение…» крутится бесконечно. Xray лишнее поле игнорирует.
    final st = (ob['settings'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    if (st['address'] != null && st['servers'] == null) {
      st['servers'] = [
        {'address': st['address'], 'port': st['port'] ?? 443}
      ];
    }
    ob['settings'] = st;

    final fm = (ss['finalmask'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final udp = List<dynamic>.from(fm['udp'] as List? ?? const []);
    bool has(String type) =>
        udp.any((m) => m is Map && m['type'] == type);

    final obfs = p(['obfs'])?.toLowerCase();
    final pw = p(['obfs-password', 'obfs_password', 'obfsPassword']);
    if ((obfs == 'salamander' || obfs == 'gecko') && pw != null &&
        !has('salamander')) {
      final settings = <String, dynamic>{'password': pw};
      if (obfs == 'gecko') {
        final mn = int.tryParse(p(['minPacketSize']) ?? '');
        final mx = int.tryParse(p(['maxPacketSize']) ?? '');
        if (mn != null && mx != null && mn >= 1 && mx >= mn && mx <= 2048) {
          settings['packetSize'] = '$mn-$mx';
        }
      }
      udp.add({'type': 'salamander', 'settings': settings});
    }
    final mport = p(['mport']);
    if (mport != null && !has('udphop')) {
      udp.add({
        'type': 'udphop',
        'settings': {
          'mode': 'intervalremote',
          'interval': '5-10',
          'remotePorts': mport,
        },
      });
    }
    if (udp.isNotEmpty) {
      fm['udp'] = udp;
      ss['finalmask'] = fm;
    }
    // TCP keep-alive к QUIC не относится.
    final so = (ss['sockopt'] as Map?)?.cast<String, dynamic>();
    so?.remove('tcpKeepAliveIdle');
    so?.remove('tcpKeepAliveInterval');
    if (so != null && so.isEmpty) ss.remove('sockopt');
    ob['streamSettings'] = ss;
  }
}

/// VLESS / Trojan / Shadowsocks: параметры ссылок 3x-ui, которые плагин
/// пропускает. Без них часть серверов просто не отвечает:
/// ech, cs (шифры TLS), fm (finalmask —
/// фрагментация и шумы), доп. настройки XHTTP и authority у gRPC.
void _patchShareParams(Map<String, dynamic> cfg, String link) {
  final scheme = link.split('://').first.toLowerCase();
  if (!const ['vless', 'trojan', 'ss'].contains(scheme)) return;
  final qi = link.indexOf('?');
  if (qi < 0) return;
  var query = link.substring(qi + 1);
  final hi = query.indexOf('#');
  if (hi >= 0) query = query.substring(0, hi);
  Map<String, String> q;
  try {
    q = Uri.splitQueryString(query);
  } catch (_) {
    return;
  }
  String? p(String k) {
    final v = q[k]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  for (final ob in (cfg['outbounds'] as List? ?? [])) {
    if (ob is! Map<String, dynamic> || ob['tag'] != 'proxy') continue;
    final ss = (ob['streamSettings'] as Map?)?.cast<String, dynamic>();
    if (ss == null) continue;

    final tls = (ss['tlsSettings'] as Map?)?.cast<String, dynamic>();
    if (tls != null) {
      if (p('ech') != null) tls['echConfigList'] = p('ech');
      if (p('cs') != null) tls['cipherSuites'] = p('cs');
      ss['tlsSettings'] = tls;
    }
    final re = (ss['realitySettings'] as Map?)?.cast<String, dynamic>();
    if (re != null) {
      // pqv (ML-DSA-65) намеренно не применяем: если сервер не подписывает
      // сертификат (ключ в панели сгенерирован, но не включён или сменился),
      // Xray отвергает соединение целиком. Обычная проверка Reality остаётся.
      re.remove('mldsa65Verify');
      if ((re['fingerprint'] as String?)?.isEmpty ?? true) {
        re['fingerprint'] = 'chrome';
      }
      ss['realitySettings'] = re;
    }
    final fm = p('fm');
    if (fm != null && ss['finalmask'] == null) {
      try {
        final parsed = jsonDecode(fm);
        if (parsed is Map) ss['finalmask'] = parsed;
      } catch (_) {}
    }
    if (ss['network'] == 'xhttp') {
      final xh = (ss['xhttpSettings'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final xpb = p('x_padding_bytes') ?? p('xPaddingBytes');
      if (xpb != null) xh['xPaddingBytes'] = xpb;
      for (final k in const [
        'scMaxEachPostBytes',
        'scMinPostsIntervalMs',
        'uplinkChunkSize'
      ]) {
        if (p(k) != null) xh[k] = p(k);
      }
      ss['xhttpSettings'] = xh;
    }
    if (ss['network'] == 'grpc' && p('authority') != null) {
      final g = (ss['grpcSettings'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      g['authority'] = p('authority');
      ss['grpcSettings'] = g;
    }
    ob['streamSettings'] = ss;
  }
}

const _alwaysProxy = [
  // YouTube и видео Google
  'domain:youtube.com', 'domain:youtu.be', 'domain:googlevideo.com',
  'domain:ytimg.com', 'domain:ggpht.com', 'domain:youtube-nocookie.com',
  'domain:youtubei.googleapis.com',
  // TikTok
  'domain:tiktok.com', 'domain:tiktokv.com', 'domain:tiktokcdn.com',
  'domain:tiktokcdn-eu.com', 'domain:tiktokcdn-us.com', 'domain:tiktokw.us',
  'domain:ttwstatic.com', 'domain:byteoversea.com', 'domain:ibytedtos.com',
  'domain:ibyteimg.com', 'domain:muscdn.com', 'domain:musical.ly',
  'domain:byteintlapi.com', 'domain:tiktokv.us', 'domain:tiktokv.eu',
  // Instagram, Facebook
  'domain:instagram.com', 'domain:cdninstagram.com', 'domain:facebook.com',
  'domain:fbcdn.net', 'domain:fb.com', 'domain:whatsapp.net',
  // X (Twitter)
  'domain:twitter.com', 'domain:x.com', 'domain:twimg.com', 'domain:t.co',
  // Discord
  'domain:discord.com', 'domain:discord.gg', 'domain:discordapp.com',
  'domain:discordapp.net', 'domain:discord.media',
  // Прочее часто заблокированное
  'domain:linkedin.com', 'domain:licdn.com', 'domain:medium.com',
  'domain:signal.org', 'domain:telegram.org', 'domain:t.me',
  'domain:patreon.com', 'domain:soundcloud.com',
];

String _randomToken() {
  final r = Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
}
