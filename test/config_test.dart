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
  test('DNS — только зашифрованный (DoH)', () {
    final dns = _cfg(_vless)['dns'] as Map;
    expect(dns['servers'],
        everyElement(startsWith('https://')));
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
}
