import 'package:flutter_test/flutter_test.dart';
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
}
