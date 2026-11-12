import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Подписки в форматах sing-box (JSON) и Clash / Mihomo (YAML):
/// каждый сервер переводится в обычную ссылку vless:// trojan:// …,
/// дальше с ним работает весь остальной Nexus.
List<String> convertSubscription(String body) {
  var t = body.trim();
  if (t.startsWith('\uFEFF')) t = t.substring(1);
  try {
    if (t.startsWith('[') || t.startsWith('{')) {
      final j = jsonDecode(t);
      // Xray JSON (Remnawave, Marzban и др. для v2rayNG, Happ, Streisand):
      // массив полных конфигов или один конфиг с outbounds[].protocol.
      final xray = _fromXray(j);
      if (xray.isNotEmpty) return xray;
      if (j is Map) return _fromSingBox(j);
      return const [];
    }
    if (RegExp(r'(^|\n)\s*proxies\s*:').hasMatch(t)) {
      return _fromClash(loadYaml(t));
    }
  } catch (_) {}
  return const [];
}

// ───────────────────────────── общие помощники ─────────────────────────────

String _q(Map<String, Object?> params) => params.entries
    .where((e) => e.value != null && '${e.value}'.isNotEmpty)
    .map((e) => '${e.key}=${Uri.encodeQueryComponent('${e.value}')}')
    .join('&');

String _host(String h) => h.contains(':') && !h.startsWith('[') ? '[$h]' : h;

String _name(Object? n) => Uri.encodeComponent('${n ?? ''}'.trim());

Map<String, dynamic> _m(Object? v) =>
    v is Map ? v.map((k, x) => MapEntry('$k', x)) : const {};

String? _s(Object? v) => v == null ? null : '$v';

/// Общий вид ссылки VLESS / Trojan с параметрами транспорта и TLS.
String _link(String scheme, String user, String server, Object port,
        Map<String, Object?> p, Object? name) =>
    '$scheme://${Uri.encodeComponent(user)}@${_host(server)}:$port'
    '?${_q(p)}#${_name(name)}';

// ──────────────────────────────── Xray JSON ────────────────────────────────

List<String> _fromXray(Object? j) {
  final configs = j is List ? j : [j];
  final out = <String>[];
  for (final c in configs.take(1000)) {
    final cfg = _m(c);
    final obs = (cfg['outbounds'] as List?) ?? const [];
    if (obs.isEmpty) continue;
    final maps = obs.map(_m).toList();
    // Основной сервер — outbound с тегом proxy, иначе первый с протоколом
    // прокси (в конфиге бывают ещё direct, block, dns и звенья цепочки).
    const proto = {
      'vless', 'vmess', 'trojan', 'shadowsocks', 'socks', 'hysteria',
      'wireguard',
    };
    final main = maps.firstWhere(
        (o) => o['tag'] == 'proxy' && proto.contains(o['protocol']),
        orElse: () => maps.firstWhere((o) => proto.contains(o['protocol']),
            orElse: () => const {}));
    if (main.isEmpty) continue;
    try {
      final l = _xrayOne(main, cfg['remarks'] ?? main['tag']);
      if (l != null) out.add(l);
    } catch (_) {}
  }
  return out;
}

/// Список строк или строка → «a,b».
String? _join(Object? v) => v is List ? v.join(',') : _s(v);

String? _xrayOne(Map<String, dynamic> o, Object? name) {
  final st = _m(o['settings']);
  final ss = _m(o['streamSettings']);
  var net = '${ss['network'] ?? 'tcp'}';
  if (net == 'raw') net = 'tcp';
  if (net == 'splithttp') net = 'xhttp';
  final sec = '${ss['security'] ?? 'none'}';
  final tls = _m(ss['tlsSettings']);
  final re = _m(ss['realitySettings']);
  final ws = _m(ss['wsSettings']);
  final grpc = _m(ss['grpcSettings']);
  final xh = _m(ss['xhttpSettings'] ?? ss['splithttpSettings']);
  final hu = _m(ss['httpupgradeSettings']);
  final kcp = _m(ss['kcpSettings']);
  final tcp = _m(ss['rawSettings'] ?? ss['tcpSettings']);
  final tcpHeader = _m(tcp['header']);
  final tcpReq = _m(tcpHeader['request']);
  String? first(Object? v) => v is List ? (v.isEmpty ? null : '${v.first}') : _s(v);

  final params = <String, Object?>{
    'type': net,
    'security': sec,
    'sni': sec == 'reality' ? re['serverName'] : tls['serverName'],
    'fp': sec == 'reality' ? re['fingerprint'] : tls['fingerprint'],
    'alpn': _join(tls['alpn']),
    'allowInsecure': tls['allowInsecure'] == true ? 1 : null,
    'pbk': re['publicKey'] ?? re['password'],
    'sid': re['shortId'],
    'spx': re['spiderX'],
    'pqv': re['mldsa65Verify'],
    'ech': tls['echConfigList'],
    switch (net) {
      'ws' => 'path',
      'xhttp' => 'path',
      'httpupgrade' => 'path',
      _ => '_',
    }: switch (net) {
      'ws' => ws['path'],
      'xhttp' => xh['path'],
      'httpupgrade' => hu['path'],
      _ => null,
    },
    'host': switch (net) {
      'ws' => ws['host'] ?? _m(ws['headers'])['Host'],
      'xhttp' => xh['host'],
      'httpupgrade' => hu['host'],
      'tcp' => first(_m(tcpReq['headers'])['Host']),
      'grpc' => grpc['authority'],
      _ => null,
    },
    'serviceName': grpc['serviceName'],
    'authority': grpc['authority'],
    'mode': net == 'grpc'
        ? (grpc['multiMode'] == true ? 'multi' : null)
        : xh['mode'],
    'extra': xh['extra'] is Map && (xh['extra'] as Map).isNotEmpty
        ? jsonEncode(xh['extra'])
        : null,
    'headerType': net == 'tcp'
        ? (tcpHeader['type'] == 'http' ? 'http' : null)
        : net == 'kcp'
            ? _m(kcp['header'])['type']
            : null,
    'seed': kcp['seed'],
    'fm': ss['finalmask'] is Map ? jsonEncode(ss['finalmask']) : null,
  };
  if (net == 'tcp' && tcpHeader['type'] == 'http') {
    params['path'] = first(tcpReq['path']);
  }
  params.remove('_');

  // Адрес: старый вид (vnext / servers) и новый плоский (Xray 25+).
  final vnext = _m((st['vnext'] as List?)?.firstOrNull);
  final server = _m((st['servers'] as List?)?.firstOrNull);
  final user = _m((vnext['users'] as List?)?.firstOrNull);
  final addr = _s(vnext['address'] ?? server['address'] ?? st['address']);
  final port = vnext['port'] ?? server['port'] ?? st['port'];

  switch (o['protocol']) {
    case 'vless':
      final id = user['id'] ?? st['id'];
      if (addr == null || port == null || id == null) return null;
      return _link('vless', '$id', addr, port, {
        ...params,
        'flow': user['flow'] ?? st['flow'],
        'encryption': user['encryption'] ?? st['encryption'] ?? 'none',
      }, name);
    case 'trojan':
      final pw = server['password'] ?? st['password'];
      if (addr == null || port == null || pw == null) return null;
      return _link('trojan', '$pw', addr, port, params, name);
    case 'vmess':
      final id = user['id'] ?? st['id'];
      if (addr == null || port == null || id == null) return null;
      return 'vmess://${base64.encode(utf8.encode(jsonEncode({
            'v': '2',
            'ps': '${name ?? ''}',
            'add': addr,
            'port': '$port',
            'id': '$id',
            'aid': '${user['alterId'] ?? 0}',
            'scy': '${user['security'] ?? st['security'] ?? 'auto'}',
            'net': net,
            'type': params['headerType'] ?? 'none',
            'host': params['host'] ?? '',
            'path': params['path'] ?? params['serviceName'] ?? '',
            'tls': sec == 'tls' ? 'tls' : '',
            'sni': params['sni'] ?? '',
            'alpn': params['alpn'] ?? '',
            'fp': params['fp'] ?? '',
          })))}';
    case 'shadowsocks':
      final m = server['method'] ?? st['method'];
      final pw = server['password'] ?? st['password'];
      if (addr == null || port == null || m == null || pw == null) return null;
      final cred =
          base64Url.encode(utf8.encode('$m:$pw')).replaceAll('=', '');
      return 'ss://$cred@${_host(addr)}:$port#${_name(name)}';
    case 'socks':
      if (addr == null || port == null) return null;
      final u = _m((server['users'] as List?)?.firstOrNull);
      final auth = u['user'] == null
          ? ''
          : '${base64Url.encode(utf8.encode('${u['user']}:${u['pass'] ?? ''}')).replaceAll('=', '')}@';
      return 'socks://$auth${_host(addr)}:$port#${_name(name)}';
    case 'hysteria':
      if (addr == null || port == null) return null;
      final hy = _m(ss['hysteriaSettings']);
      return _link('hysteria2', '${hy['auth'] ?? st['auth'] ?? ''}', addr,
          port, {
        'sni': tls['serverName'],
        'alpn': _join(tls['alpn']),
        'insecure': tls['allowInsecure'] == true ? 1 : null,
      }, name);
    case 'wireguard':
      final peer = _m((st['peers'] as List?)?.firstOrNull);
      final ep = _s(peer['endpoint']);
      if (ep == null) return null;
      final i = ep.lastIndexOf(':');
      if (i <= 0) return null;
      final host = ep.substring(0, i).replaceAll('[', '').replaceAll(']', '');
      return _link('wireguard', '${st['secretKey']}', host, ep.substring(i + 1), {
        'publickey': peer['publicKey'],
        'presharedkey': peer['preSharedKey'],
        'address': _join(st['address']),
        'reserved': _join(st['reserved']),
        'mtu': st['mtu'],
      }, name);
  }
  return null;
}

// ─────────────────────────────── sing-box ───────────────────────────────

List<String> _fromSingBox(Object? j) {
  final out = <String>[];
  final list = [
    ...((_m(j)['outbounds'] as List?) ?? const []),
    ...((_m(j)['endpoints'] as List?) ?? const []),
  ];
  for (final o in list.take(1000)) {
    final m = _m(o);
    try {
      final l = _singBoxOne(m);
      if (l != null) out.add(l);
    } catch (_) {}
  }
  return out;
}

String? _singBoxOne(Map<String, dynamic> o) {
  final type = o['type'];
  final server = _s(o['server']);
  final port = o['server_port'];
  final tls = _m(o['tls']);
  final reality = _m(tls['reality']);
  final tr = _m(o['transport']);
  Map<String, Object?> stream() {
    final net = switch (tr['type']) {
      'ws' => 'ws',
      'grpc' => 'grpc',
      'http' => 'http',
      'httpupgrade' => 'httpupgrade',
      _ => 'tcp',
    };
    final headers = _m(tr['headers']);
    return {
      'type': net,
      'security': reality['enabled'] == true
          ? 'reality'
          : tls['enabled'] == true
              ? 'tls'
              : 'none',
      'sni': tls['server_name'],
      'fp': _m(tls['utls'])['fingerprint'],
      'pbk': reality['public_key'],
      'sid': reality['short_id'],
      'alpn': (tls['alpn'] as List?)?.join(','),
      'path': tr['path'],
      'host': headers['Host'] ?? (tr['host'] is List ? (tr['host'] as List).join(',') : tr['host']),
      'serviceName': tr['service_name'],
    };
  }

  switch (type) {
    case 'vless':
      if (server == null || port == null) return null;
      return _link('vless', '${o['uuid']}', server, port,
          {...stream(), 'flow': o['flow'], 'encryption': 'none'}, o['tag']);
    case 'trojan':
      if (server == null || port == null) return null;
      return _link('trojan', '${o['password']}', server, port, stream(), o['tag']);
    case 'vmess':
      if (server == null || port == null) return null;
      final s = stream();
      return 'vmess://${base64.encode(utf8.encode(jsonEncode({
            'v': '2',
            'ps': '${o['tag'] ?? ''}',
            'add': server,
            'port': '$port',
            'id': '${o['uuid']}',
            'aid': '${o['alter_id'] ?? 0}',
            'scy': '${o['security'] ?? 'auto'}',
            'net': s['type'],
            'type': 'none',
            'host': s['host'] ?? '',
            'path': s['path'] ?? s['serviceName'] ?? '',
            'tls': s['security'] == 'tls' ? 'tls' : '',
            'sni': s['sni'] ?? '',
            'fp': s['fp'] ?? '',
          })))}';
    case 'shadowsocks':
      if (server == null || port == null) return null;
      final cred = base64Url
          .encode(utf8.encode('${o['method']}:${o['password']}'))
          .replaceAll('=', '');
      return 'ss://$cred@${_host(server)}:$port#${_name(o['tag'])}';
    case 'hysteria2':
      if (server == null || port == null) return null;
      final obfs = _m(o['obfs']);
      return _link('hysteria2', '${o['password']}', server, port, {
        'sni': tls['server_name'],
        'alpn': (tls['alpn'] as List?)?.join(','),
        'obfs': obfs['type'],
        'obfs-password': obfs['password'],
      }, o['tag']);
    case 'wireguard':
      // Старый вид (outbound) и новый (endpoint с peers).
      final peers = (o['peers'] as List?) ?? const [];
      final peer = peers.isEmpty ? o : _m(peers.first);
      final host = _s(peer['address'] ?? peer['server'] ?? server);
      final p = peer['port'] ?? peer['server_port'] ?? port;
      if (host == null || p == null) return null;
      final addr = o['address'] ?? o['local_address'];
      return _link('wireguard', '${o['private_key']}', host, p, {
        'publickey': peer['public_key'] ?? o['peer_public_key'],
        'presharedkey': peer['pre_shared_key'] ?? o['pre_shared_key'],
        'address': addr is List ? addr.join(',') : addr,
        'reserved': (peer['reserved'] ?? o['reserved']) is List
            ? ((peer['reserved'] ?? o['reserved']) as List).join(',')
            : null,
        'mtu': o['mtu'],
      }, o['tag']);
  }
  return null;
}

// ──────────────────────────────── Clash ────────────────────────────────

List<String> _fromClash(Object? y) {
  final out = <String>[];
  for (final p in ((_m(y)['proxies'] as List?) ?? const []).take(1000)) {
    try {
      final l = _clashOne(_m(p));
      if (l != null) out.add(l);
    } catch (_) {}
  }
  return out;
}

String? _clashOne(Map<String, dynamic> p) {
  final server = _s(p['server']);
  final port = p['port'];
  if (server == null || port == null) return null;
  final net = '${p['network'] ?? 'tcp'}';
  final ws = _m(p['ws-opts']);
  final grpc = _m(p['grpc-opts']);
  final h2 = _m(p['h2-opts']);
  final reality = _m(p['reality-opts']);
  final sni = p['servername'] ?? p['sni'];
  final alpn = p['alpn'] is List ? (p['alpn'] as List).join(',') : p['alpn'];
  Map<String, Object?> stream() => {
        'type': net == 'h2' ? 'http' : net,
        'security': reality.isNotEmpty
            ? 'reality'
            : (p['tls'] == true || p['type'] == 'trojan')
                ? 'tls'
                : 'none',
        'sni': sni,
        'fp': p['client-fingerprint'],
        'pbk': reality['public-key'],
        'sid': reality['short-id'],
        'alpn': alpn,
        'path': ws['path'] ?? (h2['path']),
        'host': _m(ws['headers'])['Host'] ??
            (h2['host'] is List ? (h2['host'] as List).join(',') : null),
        'serviceName': grpc['grpc-service-name'],
      };

  switch (p['type']) {
    case 'vless':
      return _link('vless', '${p['uuid']}', server, port,
          {...stream(), 'flow': p['flow'], 'encryption': 'none'}, p['name']);
    case 'trojan':
      return _link('trojan', '${p['password']}', server, port, stream(), p['name']);
    case 'vmess':
      final s = stream();
      return 'vmess://${base64.encode(utf8.encode(jsonEncode({
            'v': '2',
            'ps': '${p['name'] ?? ''}',
            'add': server,
            'port': '$port',
            'id': '${p['uuid']}',
            'aid': '${p['alterId'] ?? 0}',
            'scy': '${p['cipher'] ?? 'auto'}',
            'net': s['type'],
            'type': 'none',
            'host': s['host'] ?? '',
            'path': s['path'] ?? s['serviceName'] ?? '',
            'tls': p['tls'] == true ? 'tls' : '',
            'sni': s['sni'] ?? '',
            'fp': s['fp'] ?? '',
          })))}';
    case 'ss':
      final cred = base64Url
          .encode(utf8.encode('${p['cipher']}:${p['password']}'))
          .replaceAll('=', '');
      return 'ss://$cred@${_host(server)}:$port#${_name(p['name'])}';
    case 'hysteria2':
      return _link('hysteria2', '${p['password']}', server, port, {
        'sni': sni,
        'alpn': alpn,
        'obfs': p['obfs'],
        'obfs-password': p['obfs-password'],
        'mport': p['ports'],
      }, p['name']);
    case 'wireguard':
      final addr = [p['ip'], p['ipv6']].where((e) => e != null).join(',');
      return _link('wireguard', '${p['private-key']}', server, port, {
        'publickey': p['public-key'],
        'presharedkey': p['pre-shared-key'],
        'address': addr,
        'reserved': p['reserved'] is List ? (p['reserved'] as List).join(',') : p['reserved'],
        'mtu': p['mtu'],
      }, p['name']);
  }
  return null;
}
