// Быстрые проверки самого хрупкого: разбор ссылок, правил, QR-код.
// Запускаются в CI до сборки APK и Windows (flutter test).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/models.dart';
import 'package:nexus/services/deep_links.dart';
import 'package:nexus/services/qr.dart';
import 'package:nexus/services/subscription_service.dart';
import 'package:nexus/services/support_report.dart';

void main() {
  group('Ссылки nexus://', () {
    test('add/<url>', () {
      expect(DeepLinks.parse('nexus://add/https://sub.example.com/abc'),
          'https://sub.example.com/abc');
    });
    test('import?url=', () {
      expect(
          DeepLinks.parse(
              'nexus://import?url=${Uri.encodeComponent('vless://id@h:443?security=reality#X')}'),
          'vless://id@h:443?security=reality#X');
    });
    test('чужие схемы и мусор отклоняются', () {
      expect(DeepLinks.parse('nexus://add/javascript:alert(1)'), isNull);
      expect(DeepLinks.parse('nexus://add/file:///etc/passwd'), isNull);
      expect(DeepLinks.parse('https://evil.com'), isNull);
      expect(DeepLinks.parse('nexus://toggle'), isNull);
      expect(DeepLinks.parse('nexus://add/${'a' * 9000}'), isNull);
      expect(DeepLinks.parse('nexus://add/https://x.com/%E0%A4%A'), isNull);
      expect(DeepLinks.parse('nexus://add/https://x.com/a%0Ab'), isNull);
      expect(DeepLinks.parse('nexus://add/wireguard://k@1.2.3.4:51820'),
          'wireguard://k@1.2.3.4:51820');
    });
  });

  group('Ссылки других клиентов', () {
    test('Happ, Hiddify, v2rayNG, sing-box, Clash', () {
      const sub = 'https://sub.example.com/abc';
      final enc = Uri.encodeComponent(sub);
      expect(unwrapForeignLink('happ://add/$sub'), sub);
      expect(unwrapForeignLink('hiddify://import/$sub#Nexus'), '$sub#Nexus');
      expect(unwrapForeignLink('v2rayng://install-config?url=$enc'), sub);
      expect(unwrapForeignLink('sing-box://import-remote-profile?url=$enc#X'), sub);
      expect(unwrapForeignLink('clash://install-config?url=$enc'), sub);
      expect(unwrapForeignLink('streisand://import/vless://id@h:443#A'),
          'vless://id@h:443#A');
    });
    test('мусор и неизвестное', () {
      expect(unwrapForeignLink('https://x.com'), isNull);
      expect(unwrapForeignLink('happ://add/javascript:alert(1)'), isNull);
      expect(unwrapForeignLink('evil://add/https://x.com'), isNull);
      expect(unwrapForeignLink('happ://crypt4/AAAA'), isNull);
    });
  });

  group('Запасные адреса подписки', () {
    test('из ссылки nexus:// — только https', () {
      const sub = 'https://a.example.com/s/1';
      final link = 'nexus://import?url=${Uri.encodeComponent(sub)}'
          '&mirror=${Uri.encodeComponent('https://b.example.com/s/1')}'
          '&mirror=${Uri.encodeComponent('http://c.example.com/s/1')}';
      expect(DeepLinks.parse(link), sub);
      expect(DeepLinks.takeMirrors(sub), ['https://b.example.com/s/1']);
      expect(DeepLinks.takeMirrors(sub), isEmpty);
    });
    test('чистка списка', () {
      expect(
          cleanMirrors(['https://a/1', 'https://a/1', 'http://b/1', 'ftp://c',
            ' https://d/2 '], except: 'https://d/2'),
          ['https://a/1']);
    });
  });

  test('Одна подписка с «хвостом» Happ — та же подписка', () {
    expect(subscriptionKey('https://Sub.Example.com:2096/s/abc/#?providerid=1'),
        subscriptionKey('https://sub.example.com:2096/s/abc'));
  });

  group('Свои правила', () {
    test('домены, адреса и подсети', () {
      expect(
          parseRuleList('https://Site.com/path\n*.ya.ru, 1.2.3.4 10.0.0.0/8 '
              'host.net:8080 мусор'),
          ['site.com', 'ya.ru', '1.2.3.4', '10.0.0.0/8', 'host.net']);
    });
  });

  group('Страна по названию', () {
    test('русские и английские названия', () {
      expect(countryFromText('🇩🇪 Германия #1'), 'de');
      expect(countryFromText('Netherlands Amsterdam'), 'nl');
      expect(countryFromText('nl-2'), 'nl');
      expect(countryFromText('UK London'), 'gb');
      expect(countryFromText('Server 0863'), isNull);
    });
  });

  test('Название подписки по адресу', () {
    expect(titleFromUrl('https://www.example.com/sub/x'), 'example.com');
    expect(titleFromUrl('https://raw.githubusercontent.com/user/repo/main/a'),
        'repo');
    expect(titleFromUrl('не ссылка'), 'Подписка');
  });

  group('QR-код', () {
    test('короткий текст — версия 1, поисковые узоры на месте', () {
      final q = QrCode.text('hello');
      expect(q.size, 21);
      // Углы поисковых квадратов тёмные, разделитель рядом — светлый.
      for (final (x, y) in [(0, 0), (6, 6), (20, 0), (0, 20)]) {
        expect(q.dark(x, y), isTrue, reason: '($x,$y)');
      }
      expect(q.dark(7, 0), isFalse);
      expect(q.dark(7, 7), isFalse);
    });
    test('длинная ссылка подписки помещается', () {
      final q = QrCode.text('https://sub.example.com/${'x' * 600}');
      expect(q.size, greaterThan(21));
      expect((q.size - 17) % 4, 0);
    });
    test('слишком длинный текст — понятная ошибка', () {
      expect(() => QrCode.text('x' * 4000), throwsArgumentError);
    });
  });

  group('Подписка', () {
    test('base64 (в том числе url-safe) и повторы', () {
      const a = 'vless://u@1.1.1.1:443?security=reality#A';
      const b = 'trojan://p@2.2.2.2:443#B';
      final body = base64Url.encode(utf8.encode('$a\r\n$b\n$a\n')).replaceAll('=', '');
      expect(extractLinks(body), [a, b]);
      expect(extractLinks('мусор $a ещё'), [a]);
    });
    test('subscription-userinfo: дробные числа, бессрочно, мусор', () {
      final s = Subscription(id: '1', url: 'https://x', title: 't');
      SubscriptionService.applyUserInfo(
          s, 'upload=100; download=200.0; total=1073741824; expire=1893456000');
      expect(s.used, 300);
      expect(s.total, 1073741824);
      expect(s.expire, DateTime.fromMillisecondsSinceEpoch(1893456000000));
      SubscriptionService.applyUserInfo(s, 'expire=0; total=abc');
      expect(s.expire, isNull);
      expect(s.total, 0);
    });
    test('profile-update-interval', () {
      expect(SubscriptionService.updateHours('12'), 12);
      expect(SubscriptionService.updateHours('0'), isNull);
      expect(SubscriptionService.updateHours('9999'), isNull);
      expect(SubscriptionService.updateHours(null), isNull);
    });
  });

  test('Отчёт для поддержки не содержит ключей', () {
    final r = redactSecrets(
        'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:443?pbk=AAA#x\n'
        'sub https://panel.example.com:2096/sub/secrettoken ok\n'
        'id 11111111-2222-3333-4444-555555555555 password=qwerty');
    expect(r.contains('11111111'), isFalse);
    expect(r.contains('secrettoken'), isFalse);
    expect(r.contains('qwerty'), isFalse);
    expect(r.contains('panel.example.com:2096'), isTrue);
    final w = redactSecrets('wireguard://cHJpdmF0ZQ@1.2.3.4:2408?publickey=abc#x '
        'publickey=SECRETPUB');
    expect(w.contains('cHJpdmF0ZQ'), isFalse);
    expect(w.contains('SECRETPUB'), isFalse);
  });

  group('Другие форматы подписок', () {
    test('sing-box JSON', () {
      const body = '{"outbounds":[{"type":"vless","tag":"DE","server":"de.x.com",'
          '"server_port":443,"uuid":"11111111-2222-3333-4444-555555555555",'
          '"tls":{"enabled":true,"server_name":"g.com","reality":{"enabled":true,'
          '"public_key":"KEY","short_id":"ab"}}},{"type":"direct","tag":"direct"}]}';
      final l = extractLinks(body);
      expect(l.length, 1);
      expect(l.first, startsWith('vless://'));
      expect(l.first, contains('security=reality'));
      expect(profileFromLink(l.first)?.host, 'de.x.com');
    });
    test('Clash YAML', () {
      const body = 'proxies:\n'
          '  - {name: SS, type: ss, server: 8.8.4.4, port: 443, cipher: aes-128-gcm, password: pw}\n'
          '  - name: T\n    type: trojan\n    server: t.com\n    port: 443\n    password: p\n';
      final l = extractLinks(body);
      expect(l.length, 2);
      expect(profileFromLink(l[1])?.protocol, 'Trojan');
    });
    test('WireGuard', () {
      const link = 'wireguard://cHJpdmF0ZQ%3D%3D@1.2.3.4:2408?publickey=cHVi'
          '&address=172.16.0.2&reserved=1,2,3#WARP';
      final p = profileFromLink(link);
      expect(p?.protocol, 'WireGuard');
      expect(p?.name, 'WARP');
      expect(profileFromLink('wireguard://key@1.2.3.4:2408#bad'), isNull);
    });
  });

  test('Программы Windows', () {
    expect(parseProcessList('Discord.exe\nC:\\Games\\steam.exe, chrome\n<script>'),
        ['Discord.exe', 'steam.exe', 'chrome.exe']);
  });
}
