import 'dart:async';
import 'dart:io';

/// IP и страна, под которыми сайты видят пользователя.
class ExitInfo {
  const ExitInfo(this.ip, this.country);
  final String ip;

  /// Код страны ISO (DE, NL…) или пустая строка.
  final String country;
}

/// Проверки через активное подключение: IP выхода и скорость.
/// [proxy] — «127.0.0.1:port» или «user:pass@127.0.0.1:port».
class NetProbe {
  static HttpClient _client(String proxy) => HttpClient()
    ..findProxy = ((_) => 'PROXY $proxy')
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = 'Nexus';

  /// IP выхода по cdn-cgi/trace Cloudflare. null — не удалось.
  static Future<ExitInfo?> exitInfo(String proxy) async {
    final c = _client(proxy);
    try {
      final req = await c
          .getUrl(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'))
          .timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      // Ответ — несколько коротких строк «ключ=значение»; больше 4 КБ не читаем.
      final buf = <int>[];
      await for (final chunk in res.timeout(const Duration(seconds: 10))) {
        buf.addAll(chunk);
        if (buf.length > 4096) break;
      }
      String? ip, loc;
      for (final line in String.fromCharCodes(buf).split('\n')) {
        final i = line.indexOf('=');
        if (i <= 0) continue;
        final k = line.substring(0, i).trim();
        final v = line.substring(i + 1).trim();
        if (k == 'ip') ip = v;
        if (k == 'loc') loc = v;
      }
      if (ip == null || InternetAddress.tryParse(ip) == null) return null;
      final cc = (loc != null && RegExp(r'^[A-Z]{2}$').hasMatch(loc) &&
              loc != 'XX' && loc != 'T1')
          ? loc
          : '';
      return ExitInfo(ip, cc);
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  /// Тест скорости загрузки: качаем файл с серверов Cloudflare не дольше
  /// [limit] и не больше 50 МБ. Возвращает Мбит/с или null при ошибке.
  /// [onProgress] получает текущую скорость во время замера.
  static Future<double?> downloadSpeed(
    String proxy, {
    Duration limit = const Duration(seconds: 8),
    void Function(double mbps)? onProgress,
  }) async {
    const maxBytes = 50 * 1000 * 1000;
    final c = _client(proxy);
    try {
      final req = await c
          .getUrl(Uri.parse(
              'https://speed.cloudflare.com/__down?bytes=$maxBytes'))
          .timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final sw = Stopwatch()..start();
      var bytes = 0;
      var lastTick = 0;
      final sub = res.listen(null);
      final done = Completer<void>();
      sub.onData((chunk) {
        bytes += chunk.length;
        final ms = sw.elapsedMilliseconds;
        if (onProgress != null && ms - lastTick >= 250 && ms > 0) {
          lastTick = ms;
          onProgress(bytes * 8 / ms / 1000);
        }
        if (ms >= limit.inMilliseconds || bytes >= maxBytes) {
          sub.cancel();
          if (!done.isCompleted) done.complete();
        }
      });
      sub.onDone(() {
        if (!done.isCompleted) done.complete();
      });
      sub.onError((Object _) {
        if (!done.isCompleted) done.complete();
      });
      await done.future.timeout(limit + const Duration(seconds: 5),
          onTimeout: () => sub.cancel());
      final ms = sw.elapsedMilliseconds;
      // Слишком мало данных — замер недостоверен.
      if (ms <= 0 || bytes < 200 * 1000) return null;
      return bytes * 8 / ms / 1000;
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }
}
