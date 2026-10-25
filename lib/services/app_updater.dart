import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../platform/android_system.dart';

/// Репозиторий с релизами Nexus (задаётся при сборке в GitHub Actions).
const kUpdateRepo = String.fromEnvironment('UPDATE_REPO');

/// Найденное обновление приложения (на Android ядро Xray встроено в APK).
class AppUpdate {
  AppUpdate({
    required this.build,
    required this.version,
    required this.xray,
    required this.apkUrl,
    required this.apkName,
    required this.sha256,
  });
  final int build;
  final String version;
  final String xray;
  final String apkUrl;
  final String apkName;
  final String sha256;
}

class AppUpdater {
  static Map<String, String> get _headers => {
        'User-Agent': 'Nexus',
        'Accept': 'application/vnd.github+json',
      };

  /// Проверяет последний релиз. null — обновлений нет.
  static Future<AppUpdate?> check() async {
    if (kUpdateRepo.isEmpty) {
      throw Exception('Источник обновлений не задан в сборке');
    }
    final info = await AndroidSystem.appInfo();
    final current = (info['versionCode'] as num?)?.toInt() ?? 0;
    final abi = (info['abi'] ?? '').toString();

    final res = await http
        .get(
            Uri.parse(
                'https://api.github.com/repos/$kUpdateRepo/releases/latest'),
            headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) {
      throw Exception('Релизы недоступны — репозиторий закрыт или пуст');
    }
    if (res.statusCode != 200) {
      throw Exception('GitHub ответил ${res.statusCode}');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final body = (j['body'] ?? '').toString();
    final build = int.tryParse(
            RegExp(r'nexus-build:[ \t]*(\d+)').firstMatch(body)?.group(1) ?? '') ??
        0;
    if (build <= current) return null;
    final xray =
        RegExp(r'xray:[ \t]*([\d.]+)').firstMatch(body)?.group(1) ?? '';
    final version = (j['name'] ?? j['tag_name'] ?? '').toString();

    final want = switch (abi) {
      'arm64-v8a' => 'Nexus-arm64.apk',
      'armeabi-v7a' => 'Nexus-armv7.apk',
      _ => 'Nexus-universal.apk',
    };
    String? apkUrl, sumsUrl;
    String apkName = want;
    String? universal;
    for (final a in (j['assets'] as List? ?? [])) {
      final name = a['name']?.toString() ?? '';
      final url = a['browser_download_url']?.toString();
      if (url == null || !url.startsWith('https://github.com/')) continue;
      if (name == want) apkUrl = url;
      if (name == 'Nexus-universal.apk') universal = url;
      if (name == 'SHA256SUMS.txt') sumsUrl = url;
    }
    if (apkUrl == null && universal != null) {
      apkUrl = universal;
      apkName = 'Nexus-universal.apk';
    }
    if (apkUrl == null || sumsUrl == null) {
      throw Exception('В релизе нет APK или контрольных сумм');
    }
    final sums = (await http.get(Uri.parse(sumsUrl), headers: _headers)).body;
    final line = sums
        .split('\n')
        .firstWhere((l) => l.trim().endsWith(apkName), orElse: () => '');
    final sha = line.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (sha.length != 64) throw Exception('Нет контрольной суммы для $apkName');

    return AppUpdate(
      build: build,
      version: version,
      xray: xray,
      apkUrl: apkUrl,
      apkName: apkName,
      sha256: sha,
    );
  }

  /// Скачивает APK, проверяет SHA-256 и открывает установщик.
  /// [onProgress] — доля от 0 до 1.
  static Future<void> downloadAndInstall(AppUpdate u,
      {void Function(double)? onProgress}) async {
    if (!await AndroidSystem.canInstallApk()) {
      await AndroidSystem.openInstallSettings();
      throw Exception(
          'Разрешите Nexus устанавливать приложения и нажмите «Обновить» ещё раз');
    }
    final info = await AndroidSystem.appInfo();
    final dir = Directory('${info['cacheDir']}/updates');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final file = File('${dir.path}/${u.apkName}');

    final client = http.Client();
    try {
      final resp = await client
          .send(http.Request('GET', Uri.parse(u.apkUrl))
            ..headers['User-Agent'] = 'Nexus')
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw Exception('Загрузка не удалась (код ${resp.statusCode})');
      }
      final total = resp.contentLength ?? 0;
      final sink = file.openWrite();
      final hashSink = _DigestSink();
      final hasher = sha256.startChunkedConversion(hashSink);
      var got = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
      hasher.close();
      if (hashSink.value.toString() != u.sha256) {
        file.deleteSync();
        throw Exception('Контрольная сумма не совпала — обновление отменено');
      }
    } finally {
      client.close();
    }
    if (!await AndroidSystem.installApk(file.path)) {
      throw Exception('Не удалось открыть установщик');
    }
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
