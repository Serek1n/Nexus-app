import 'dart:convert';
import 'dart:math';

import 'package:flutter_v2ray_client/flutter_v2ray.dart';

import '../models.dart';

/// Локальные порты ядра на Windows.
const kSocksPort = 10808;
const kHttpPort = 10809;

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

  cfg['log'] = {'loglevel': 'warning'};

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
  // молча закрыть простаивающее соединение (NAT), а IPv4 исключает
  // зависания на сломанном IPv6.
  for (final ob in (cfg['outbounds'] as List? ?? [])) {
    if (ob is Map<String, dynamic> && ob['tag'] == 'proxy') {
      final ss = (ob['streamSettings'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final so = (ss['sockopt'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      so['tcpKeepAliveIdle'] = 30;
      so['tcpKeepAliveInterval'] = 15;
      so['domainStrategy'] = 'UseIPv4';
      ss['sockopt'] = so;
      ob['streamSettings'] = ss;
    }
  }

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

String _randomToken() {
  final r = Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
}
