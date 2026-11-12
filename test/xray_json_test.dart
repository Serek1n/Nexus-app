// Подписки в формате Xray JSON (Remnawave, Marzban для v2rayNG / Happ).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/models.dart';
import 'package:nexus/services/config_builder.dart';
import 'package:nexus/services/subscription_service.dart';

void main() {
  final body = jsonEncode([
    {
      'remarks': '🇳🇱 Нидерланды',
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'vless',
          'settings': {
            'vnext': [
              {
                'address': 'nl.example.com',
                'port': 443,
                'users': [
                  {
                    'id': '11111111-2222-3333-4444-555555555555',
                    'flow': 'xtls-rprx-vision',
                    'encryption': 'none',
                  }
                ],
              }
            ],
          },
          'streamSettings': {
            'network': 'raw',
            'security': 'reality',
            'realitySettings': {
              'serverName': 'www.google.com',
              'fingerprint': 'chrome',
              'publicKey': 'Z84J2IelR9ch3k8VtlVhhs5ycBUlXA7wHBWcBrjqnAw',
              'shortId': 'ab12',
            },
          },
        },
        {'tag': 'direct', 'protocol': 'freedom'},
      ],
    },
    {
      'remarks': 'Германия',
      'outbounds': [
        {
          'tag': 'proxy',
          'protocol': 'trojan',
          'settings': {
            'servers': [
              {'address': 'de.example.com', 'port': 443, 'password': 'pw'}
            ],
          },
          'streamSettings': {
            'network': 'httpupgrade',
            'security': 'tls',
            'tlsSettings': {'serverName': 'de.example.com'},
            'httpupgradeSettings': {'path': '/up', 'host': 'cdn.example.com'},
          },
        },
      ],
    },
  ]);

  test('Xray JSON превращается в серверы', () {
    final links = extractLinks(body);
    expect(links.length, 2);
    final nl = profileFromLink(links[0])!;
    expect(nl.name, '🇳🇱 Нидерланды');
    expect(nl.host, 'nl.example.com');
    expect(nl.protocol, 'VLESS');
    final de = profileFromLink(links[1])!;
    expect(de.protocol, 'Trojan');
    expect(de.port, 443);
  });

  test('HTTPUpgrade сохраняет путь и адрес', () {
    final link = extractLinks(body)[1];
    final cfg = jsonDecode(buildXrayConfig(profileFromLink(link)!,
        routing: RoutingMode.global, desktop: true)) as Map;
    final ob = (cfg['outbounds'] as List)
        .cast<Map>()
        .firstWhere((o) => o['tag'] == 'proxy');
    final ss = ob['streamSettings'] as Map;
    expect(ss['network'], 'httpupgrade');
    expect(ss['httpupgradeSettings'], {'path': '/up', 'host': 'cdn.example.com'});
  });
}
