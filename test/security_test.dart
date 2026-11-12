// Защита: PIN, резервные копии, правила, kill switch Linux.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus/core/desktop_os.dart';
import 'package:nexus/models.dart';
import 'package:nexus/services/backup.dart';
import 'package:nexus/services/pin.dart';

void main() {
  group('PIN', () {
    test('верный и неверный код', () async {
      final h = await Pin.hash('123456');
      expect(await Pin.verify('123456', h), isTrue);
      expect(await Pin.verify('654321', h), isFalse);
      expect(await Pin.verify('123456', 'мусор'), isFalse);
    });

    test('пауза после пяти ошибок переживает перезапуск', () async {
      final h = await Pin.hash('123456');
      String? store;
      var now = DateTime(2026, 1, 1, 12);
      PinGuard g() => PinGuard(
          read: () => store, write: (v) => store = v, now: () => now);
      final a = g()..load();
      for (var i = 0; i < 5; i++) {
        expect(await a.attempt('000000', h), isFalse);
      }
      expect(a.blocked, isTrue);
      // Даже верный код во время паузы не принимается.
      expect(await a.attempt('123456', h), isFalse);
      // «Перезапуск» — новый объект с тем же хранилищем.
      final b = g()..load();
      expect(b.fails, 5);
      expect(b.blocked, isTrue);
      now = now.add(const Duration(seconds: 31));
      expect(b.blocked, isFalse);
      expect(await b.attempt('123456', h), isTrue);
      expect(b.fails, 0);
      expect((g()..load()).fails, 0);
    });

    test('перевод часов назад не снимает паузу навсегда', () {
      var now = DateTime(2026, 1, 1, 12);
      String? store =
          '{"fails":5,"until":${now.add(const Duration(days: 30)).millisecondsSinceEpoch}}';
      final g = PinGuard(read: () => store, write: (v) => store = v, now: () => now)
        ..load();
      expect(g.blockedUntil!.difference(now), Pin.delayAfter(5));
    });
  });

  group('Резервная копия', () {
    test('шифруется и расшифровывается (формат 3)', () async {
      final data = {
        'settings': {'theme': 'dark'},
        'subs': ['https://example.com/sub'],
      };
      final text = await Backup.encrypt(data, 'password123');
      expect(text, startsWith('nexus-backup:3:'));
      expect(text.contains('example.com'), isFalse);
      final back = await Backup.decrypt(text, 'password123');
      expect(back['subs'], ['https://example.com/sub']);
      expect(() => Backup.decrypt(text, 'wrong-pass'), throwsException);
    });

    test('короткий пароль не принимается', () {
      expect(() => Backup.encrypt({}, '1234567'), throwsException);
    });
  });

  test('правила: IP и подсети', () {
    expect(isIpRule('1.2.3.4'), isTrue);
    expect(isIpRule('10.0.0.0/8'), isTrue);
    expect(isIpRule('256.1.1.1'), isFalse);
    expect(isIpRule('10.0.0.0/33'), isFalse);
    expect(isIpRule('example.com'), isFalse);
  });

  test('kill switch Linux: встроенный помощник совпадает с файлом', () {
    expect(LinuxOs.ksHelperText,
        File('tool/linux/nexus-killswitch').readAsStringSync());
    expect(LinuxOs.ksPolicyText,
        File('tool/linux/app.nexusvpn.killswitch.policy').readAsStringSync());
  });
}
