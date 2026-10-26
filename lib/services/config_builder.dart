import 'dart:convert';
import 'dart:math';

import 'package:flutter_v2ray_client/flutter_v2ray.dart';

import '../models.dart';

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

  cfg['dns'] = {
    'servers': ['1.1.1.1', '8.8.8.8'],
    'queryStrategy': 'UseIPv4',
  };

  final rules = <Map<String, dynamic>>[
    {
      'type': 'field',
      'ip': _privateNets,
      'outboundTag': 'direct',
    },
  ];

  if (routing == RoutingMode.smart) {
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

String _randomToken() {
  final r = Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
}
