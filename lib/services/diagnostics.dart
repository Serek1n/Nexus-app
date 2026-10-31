import 'dart:async';
import 'dart:io';

import '../l10n.dart';
import '../models.dart';
import 'net_probe.dart';

/// Одна проверка: название, результат (null — пропущена) и подробности.
class DiagItem {
  DiagItem(this.id, this.title, {this.ok, this.detail = ''});

  /// net, dns, ru, sub, server, site, ip — для советов на экране.
  final String id;
  final String title;
  bool? ok;
  String detail;

  @override
  String toString() =>
      '${ok == null ? '–' : ok! ? '✓' : '✕'} $title${detail.isEmpty ? '' : ' — $detail'}';
}

/// Проверка связи по шагам: интернет → DNS → сервер подписки → сервер VPN →
/// сайты через VPN → IP выхода. По результату видно, где именно беда.
class Diagnostics {
  static Future<int?> _tcp(String host, int port,
      {Duration timeout = const Duration(seconds: 5)}) async {
    final sw = Stopwatch()..start();
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// HTTPS-запрос; через [proxy], если задан. Ответ сервера с любым кодом,
  /// кроме 5xx, — сайт доступен. Возвращает мс или null.
  static Future<int?> _https(String url, {String? proxy}) async {
    final c = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Mozilla/5.0 Nexus';
    c.findProxy = (_) => proxy == null ? 'DIRECT' : 'PROXY $proxy';
    final sw = Stopwatch()..start();
    try {
      final req =
          await c.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain<void>().timeout(const Duration(seconds: 5),
          onTimeout: () {});
      return res.statusCode < 500 ? sw.elapsedMilliseconds : null;
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static String _ms(int? v) => v == null ? '' : tr('{0} мс', [v]);

  /// Запускает все проверки; [onUpdate] вызывается после каждой.
  static Future<List<DiagItem>> run({
    required ServerProfile? server,
    required Subscription? subscription,
    required String? proxy,
    required void Function(List<DiagItem>) onUpdate,
  }) async {
    final items = <DiagItem>[];
    Future<void> step(DiagItem it, Future<void> Function() f) async {
      items.add(it);
      onUpdate(items);
      try {
        await f();
      } catch (e) {
        it.ok = false;
        it.detail = '$e';
      }
      onUpdate(items);
    }

    // 1. Есть ли интернет вообще.
    await step(DiagItem('net', tr('Интернет')), () async {
      final a = await _tcp('1.1.1.1', 443);
      final b = a ?? await _tcp('77.88.8.8', 443);
      items.last
        ..ok = b != null
        ..detail = b != null ? _ms(b) : tr('нет соединения — проверьте Wi-Fi или мобильные данные');
    });

    // 2. Работает ли DNS.
    await step(DiagItem('dns', 'DNS'), () async {
      try {
        final r = await InternetAddress.lookup('ya.ru')
            .timeout(const Duration(seconds: 5));
        items.last
          ..ok = r.isNotEmpty
          ..detail = r.isNotEmpty ? '' : tr('имена сайтов не находятся');
      } catch (_) {
        items.last
          ..ok = false
          ..detail = tr('имена сайтов не находятся');
      }
    });

    // 3. Российские сайты напрямую.
    await step(DiagItem('ru', tr('Российские сайты напрямую')), () async {
      final v = await _https('https://www.gosuslugi.ru/');
      items.last
        ..ok = v != null
        ..detail = v != null ? _ms(v) : tr('Госуслуги не открываются');
    });

    // 4. Сервер подписки.
    final su = subscription == null ? null : Uri.tryParse(subscription.url);
    if (su != null && su.host.isNotEmpty) {
      await step(DiagItem('sub', tr('Сервер подписки')), () async {
        final v = await _tcp(su.host, su.hasPort ? su.port : (su.scheme == 'https' ? 443 : 80));
        items.last
          ..ok = v != null
          ..detail = v != null
              ? '${su.host} · ${_ms(v)}'
              : tr('{0} недоступен — возможно, его блокирует провайдер', [su.host]);
      });
    }

    // 5. Сервер VPN (для TCP-протоколов; UDP проверяется подключением).
    if (server != null) {
      final udp = server.protocol == 'Hysteria2' || server.protocol == 'WireGuard';
      await step(DiagItem('server', tr('Сервер «{0}»', [server.cleanName])), () async {
        if (udp) {
          items.last
            ..ok = null
            ..detail = tr('{0} работает по UDP — проверяется подключением', [server.protocol]);
          return;
        }
        final v = await _tcp(server.host, server.port);
        items.last
          ..ok = v != null
          ..detail = v != null
              // Открытый порт ещё не значит, что провайдер пропустит
              // само соединение — это проверяют «Сайты через VPN».
              ? tr('{0}:{1} · порт открыт · {2}', [server.host, server.port, _ms(v)])
              : tr('{0}:{1} не отвечает — сервер выключен или заблокирован', [server.host, server.port]);
      });
    }

    // 6. Сайты через VPN — только при подключении.
    if (proxy == null) {
      items.add(DiagItem('site', tr('Сайты через VPN'),
          detail: tr('подключитесь, чтобы проверить')));
      onUpdate(items);
    } else {
      for (final (name, url) in const [
        ('Google', 'https://www.gstatic.com/generate_204'),
        ('YouTube', 'https://www.youtube.com/generate_204'),
        ('Instagram', 'https://www.instagram.com/'),
        ('Telegram', 'https://telegram.org/'),
        ('Discord', 'https://discord.com/api/v9/gateway'),
      ]) {
        await step(DiagItem('site', tr('{0} через VPN', [name])), () async {
          final v = await _https(url, proxy: proxy);
          items.last
            ..ok = v != null
            ..detail = v != null ? _ms(v) : tr('не открывается');
        });
      }
      await step(DiagItem('ip', tr('IP для сайтов')), () async {
        final e = await NetProbe.exitInfo(proxy);
        items.last
          // Российский IP — норма только для сервера в России.
          ..ok = e != null && (e.country != 'RU' || server?.countryCode == 'ru')
          ..detail = e == null
              ? tr('не удалось узнать')
              : '${e.ip}${e.country.isEmpty ? '' : ' · ${e.country}'}'
                  '${e.country == 'RU' && server?.countryCode != 'ru' ? tr(' — трафик идёт мимо VPN') : ''}';
      });
    }
    return items;
  }
}
