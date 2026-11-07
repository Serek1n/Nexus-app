import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/services/deep_links.dart';
import 'package:nexus/services/phone_link.dart';

void main() {
  // Ключ 00…1f; тело получено функцией seal() со страницы для телефона.
  final key = List<int>.generate(32, (i) => i);
  const body =
      'n=07070707070707070707070707070707&c=306de96b500e11970c92bd4aced49e9ed8d732ac77d95bba122e0a2695d36b483b6f43d4805928aff5875570&t=353d81e35297ff975f895cfd989464a88986678a9657616e69337c0a20660e29';

  test('расшифровка ссылки, отправленной со страницы', () {
    expect(PhoneLink.open(key, body), 'https://sub.example.com/abc?x=1 Привет');
  });

  test('подделка и чужой ключ отклоняются', () {
    final forged = body.replaceFirst('c=30', 'c=31');
    expect(PhoneLink.open(key, forged), isNull);
    final other = List<int>.generate(32, (i) => 31 - i);
    expect(PhoneLink.open(other, body), isNull);
    expect(PhoneLink.open(key, 'n=00&c=00&t=00'), isNull);
    expect(PhoneLink.open(key, 'мусор'), isNull);
    expect(PhoneLink.open(key, ''), isNull);
  });

  test('только адреса домашней сети', () {
    expect(PhoneLink.isPrivate('192.168.1.5'), isTrue);
    expect(PhoneLink.isPrivate('10.0.0.2'), isTrue);
    expect(PhoneLink.isPrivate('172.20.1.1'), isTrue);
    expect(PhoneLink.isPrivate('172.32.0.1'), isFalse);
    expect(PhoneLink.isPrivate('8.8.8.8'), isFalse);
    expect(PhoneLink.isPrivate('100.64.0.1'), isFalse);
    expect(PhoneLink.isPrivate('192.168.1'), isFalse);
  });

  test('страница не содержит внешних ссылок', () {
    final html = PhoneLink.page();
    expect(html.contains('src="http'), isFalse);
    expect(html.contains('function seal'), isTrue);
  });

  const qr =
      'http://192.168.0.3:38969/6d50d53856c64ad66c72fec4df875b64#NRuacqRli1MdiWRqw-zS47b2y0TNpwRmtD2uPG-AWbE';

  test('QR-код телевизора распознаётся телефоном', () {
    final t = PhoneLink.parseTarget(qr)!;
    expect(t.host, '192.168.0.3');
    expect(t.endpoint.toString(),
        'http://192.168.0.3:38969/6d50d53856c64ad66c72fec4df875b64');
    expect(t.key.length, 32);
  });

  test('чужие адреса и ссылки — не QR-код телевизора', () {
    for (final bad in [
      qr.replaceFirst('192.168.0.3', '8.8.8.8'),
      qr.replaceFirst('http://', 'https://'),
      qr.replaceFirst(':38969', ''),
      qr.replaceFirst('#', '?x=1#'),
      qr.split('#').first,
      'https://sub.example.com/s/abc',
      'vless://uuid@host:443',
      '',
    ]) {
      expect(PhoneLink.parseTarget(bad), isNull, reason: bad);
    }
  });

  test('шифрование телефона расшифровывает телевизор', () {
    final k = List<int>.generate(32, (i) => i * 7 % 256);
    final body = PhoneLink.seal(
        k, 'nexus://add?url=https%3A%2F%2Fa.b%2Fs', List.filled(16, 5));
    expect(PhoneLink.open(k, body), 'nexus://add?url=https%3A%2F%2Fa.b%2Fs');
  });

  test('кнопка «Выбрать подписку в Nexus» на странице телевизора', () {
    final link = 'nexus://tv?u=${Uri.encodeComponent(qr)}';
    expect(DeepLinks.parse(link), qr);
    expect(DeepLinks.parse('nexus://tv?u=${Uri.encodeComponent('http://8.8.8.8:1/x#y')}'),
        isNull);
  });
}
