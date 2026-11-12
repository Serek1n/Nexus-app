// Сборка конфигурации Xray: то, что ломалось раньше, и новые режимы.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/models.dart';
import 'package:nexus/services/config_builder.dart';

ServerProfile _s(String link, String id) => ServerProfile(
    id: id, link: link, name: id, protocol: link.split(':').first,
    host: 'h', port: 443);

final _vless = _s(
    'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?type=tcp'
    '&security=reality&pbk=Z4N5d0Wq9W3o0sOOrq5GkRrkL2WQh1Y5vC8pvvVtq2o'
    '&fp=chrome&sni=www.google.com&sid=ab&flow=xtls-rprx-vision&pqv=AAAA#FI',
    'fi');
final _hy = _s(
    'hysteria2://pass@5.6.7.8:443?sni=x.com&obfs=salamander'
    '&obfs-password=zz&mport=20000-30000#NL',
    'nl');

Map<String, dynamic> _cfg(ServerProfile s,
        {bool desktop = true,
        bool antiBlock = false,
        bool blockAds = false,
        RoutingMode routing = RoutingMode.smart}) =>
    jsonDecode(buildXrayConfig(s,
        routing: routing,
        desktop: desktop,
        antiBlock: antiBlock,
        blockAds: blockAds)) as Map<String, dynamic>;

Map<String, dynamic> _out(Map<String, dynamic> c, String tag) =>
    (c['outbounds'] as List).cast<Map<String, dynamic>>()
        .firstWhere((o) => o['tag'] == tag);

void main() {
  test('Свои правила: сайт с цифры идёт в домены, а не в IP', () {
    final c = jsonDecode(buildXrayConfig(_vless,
        routing: RoutingMode.smart,
        desktop: true,
        customDirect: ['2ip.ru', '10.0.0.0/8'])) as Map<String, dynamic>;
    final rules = (c['routing']['rules'] as List).cast<Map>();
    expect(rules.any((r) => (r['domain'] as List?)?.contains('domain:2ip.ru') == true), isTrue);
    expect(rules.any((r) => (r['ip'] as List?)?.contains('2ip.ru') == true), isFalse);
    expect(rules.any((r) => (r['ip'] as List?)?.contains('10.0.0.0/8') == true), isTrue);
  });

  test('DNS: сначала зашифрованный (DoH), выбранный сервис', () {
    final dns = _cfg(_vless)['dns'] as Map;
    expect((dns['servers'] as List).first, 'https://1.1.1.1/dns-query');
    final ag = jsonDecode(buildXrayConfig(_vless,
            routing: RoutingMode.smart, desktop: true, dns: 'adguard'))
        as Map<String, dynamic>;
    expect(ag['dns']['servers'], ['https://94.140.14.14/dns-query', '94.140.14.14']);
  });

  test('Нет sockopt.domainStrategy (иначе «нет связи» у серверов с доменом)', () {
    final so = _out(_cfg(_vless), 'proxy')['streamSettings']['sockopt'] as Map;
    expect(so.containsKey('domainStrategy'), isFalse);
    expect(so['tcpKeepAliveIdle'], 30);
  });

  test('pqv из ссылки не применяется', () {
    final re = _out(_cfg(_vless), 'proxy')['streamSettings']['realitySettings']
        as Map;
    expect(re.containsKey('mldsa65Verify'), isFalse);
  });

  test('Hysteria2: obfs, смена портов и адрес для плагина Android', () {
    final ob = _out(_cfg(_hy, desktop: false), 'proxy');
    final udp = (ob['streamSettings']['finalmask']['udp'] as List)
        .map((m) => m['type'])
        .toList();
    expect(udp, containsAll(['salamander', 'udphop']));
    expect((ob['settings']['servers'] as List).first['address'], '5.6.7.8');
  });

  group('Обход блокировок', () {
    test('TCP: фрагментация первого пакета', () {
      final tcp = _out(_cfg(_vless, antiBlock: true), 'proxy')
          ['streamSettings']['finalmask']['tcp'] as List;
      expect(tcp.single['type'], 'fragment');
    });
    test('«Быстрая» — паузы только между первыми кусками', () {
      final c = jsonDecode(buildXrayConfig(_vless,
          routing: RoutingMode.smart,
          desktop: true,
          antiBlock: true,
          antiBlockFast: true)) as Map<String, dynamic>;
      final st = (_out(c, 'proxy')['streamSettings']['finalmask']['tcp']
          as List).single['settings'] as Map;
      expect(st['delays'], ['10-20', '10-20', '10-20', '0']);
      expect(st.containsKey('delay'), isFalse);
    });
    test('выключен — без масок', () {
      expect(_out(_cfg(_vless), 'proxy')['streamSettings']['finalmask'],
          isNull);
    });
    test('Hysteria2 (UDP) не трогаем', () {
      final fm = _out(_cfg(_hy, antiBlock: true), 'proxy')['streamSettings']
          ['finalmask'] as Map;
      expect(fm.containsKey('tcp'), isFalse);
    });
  });

  test('Блокировка рекламы: правило и исходящий block', () {
    final c = _cfg(_vless, blockAds: true);
    final rules = c['routing']['rules'] as List;
    expect(
        rules.any((r) =>
            r['outboundTag'] == 'block' &&
            (r['domain'] as List).contains('geosite:category-ads-all')),
        isTrue);
    expect(_out(c, 'block')['protocol'], 'blackhole');
  });

  test('Умный режим: российское напрямую, YouTube через VPN', () {
    final rules = (_cfg(_vless)['routing']['rules'] as List).cast<Map>();
    final yt = rules.indexWhere(
        (r) => (r['domain'] as List?)?.contains('domain:youtube.com') ?? false);
    final ru = rules.indexWhere(
        (r) => (r['ip'] as List?)?.contains('geoip:ru') ?? false);
    expect(yt, greaterThanOrEqualTo(0));
    expect(ru, greaterThan(yt));
    expect(rules[yt]['outboundTag'], 'proxy');
  });

  group('Режим «Авто»', () {
    final c = jsonDecode(buildAutoConfig(
            [_vless, _hy, _s('bad://x', 'bad')],
            routing: RoutingMode.smart, desktop: true))
        as Map<String, dynamic>;
    test('серверы первыми, битые пропущены', () {
      final tags = (c['outbounds'] as List).map((o) => o['tag']).toList();
      expect(tags.take(2), ['nx-0', 'nx-1']);
      expect(tags, isNot(contains('proxy')));
      expect(tags, isNot(contains('nx-2')));
    });
    test('балансировщик и проверка серверов', () {
      final b = (c['routing']['balancers'] as List).single as Map;
      expect(b['strategy']['type'], 'leastPing');
      expect(c['observatory']['subjectSelector'], ['nx-']);
    });
    test('всё, что шло в proxy, идёт в балансировщик', () {
      final rules = (c['routing']['rules'] as List).cast<Map>();
      expect(rules.any((r) => r['outboundTag'] == 'proxy'), isFalse);
      expect(rules.last['balancerTag'], 'auto');
    });
  });

  test('WireGuard: исходящий и адрес для плагина Android', () {
    final c = _cfg(_s(
        'wireguard://cHJpdmF0ZQ%3D%3D@1.2.3.4:2408?publickey=cHVi'
        '&address=172.16.0.2&reserved=1,2,3#WARP', 'wg'), antiBlock: true);
    final ob = _out(c, 'proxy');
    expect(ob['protocol'], 'wireguard');
    expect(ob['settings']['address'], ['172.16.0.2/32']);
    expect((ob['settings']['servers'] as List).first['address'], '1.2.3.4');
    expect(ob['streamSettings']?['finalmask'], isNull);
  });

  test('SOCKS с паролем и программы (Windows)', () {
    final c = jsonDecode(buildXrayConfig(_vless,
        routing: RoutingMode.smart,
        desktop: true,
        socksAccount: 'nexus:pw',
        appsDirect: ['steam.exe'])) as Map<String, dynamic>;
    final socks = (c['inbounds'] as List).first as Map;
    expect(socks['settings']['auth'], 'password');
    final rules = (c['routing']['rules'] as List).cast<Map>();
    expect(rules.any((r) => (r['process'] as List?)?.contains('steam.exe') ?? false),
        isTrue);
  });

  test('Метрики ядра — только через вход с паролем', () {
    final c = <String, dynamic>{'routing': {'rules': []}};
    addPrivateMetrics(c, 'nexus-api');
    expect(c['metrics'], {'tag': 'nexus-metrics'});
    final r = (c['routing']['rules'] as List).first as Map;
    expect(r['inboundTag'], ['nexus-api']);
    expect(parseObservatory({
      'nx-0': {'alive': true, 'delay': 120},
      'nx-1': {'alive': false, 'delay': 99999999},
    }), {'nx-0': 120, 'nx-1': -1});
  });

  test('Android: режим прокси с паролем, режим VPN — случайный пароль', () {
    Map socks(Map<String, dynamic> c) => (c['inbounds'] as List)
        .cast<Map>()
        .firstWhere((i) => i['protocol'] == 'socks');
    final proxyOnly = jsonDecode(buildXrayConfig(_vless,
        routing: RoutingMode.smart, desktop: false, socksAccount: 'nexus:pw'))
        as Map<String, dynamic>;
    expect(socks(proxyOnly)['settings']['accounts'],
        [{'user': 'nexus', 'pass': 'pw'}]);
    final vpn = jsonDecode(buildXrayConfig(_vless,
        routing: RoutingMode.smart, desktop: false, lockLocalProxy: true))
        as Map<String, dynamic>;
    expect(socks(vpn)['settings']['auth'], 'password');
  });

  test('«Только заблокированное»: заблокированное через VPN, остальное напрямую', () {
    final rules = (_cfg(_vless, routing: RoutingMode.blocked)['routing']
        ['rules'] as List).cast<Map>();
    final proxy = rules.firstWhere((r) =>
        r['outboundTag'] == 'proxy' &&
        (r['domain'] as List? ?? const []).contains('domain:youtube.com'));
    expect(proxy['domain'], contains('domain:chatgpt.com'));
    expect(rules.any((r) =>
        r['outboundTag'] == 'proxy' &&
        (r['ip'] as List? ?? const []).contains('geoip:telegram')), isTrue);
    expect(rules.last['outboundTag'], 'direct');
    expect(rules.last['network'], 'tcp,udp');
  });
}
