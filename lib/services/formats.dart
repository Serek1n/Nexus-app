import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Подписки в форматах sing-box (JSON) и Clash / Mihomo (YAML):
/// каждый сервер переводится в обычную ссылку vless:// trojan:// …,
/// дальше с ним работает весь остальной Nexus.
List<String> convertSubscription(String body) {
  final t = body.trim();
  try {
    if (t.startsWith('{')) return _fromSingBox(jsonDecode(t));
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
