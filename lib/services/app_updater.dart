import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:http/http.dart' as http;

import '../platform/android_system.dart';

/// Репозиторий с релизами Nexus и номер сборки (задаются в GitHub Actions).
const kUpdateRepo = String.fromEnvironment('UPDATE_REPO');
const kAppBuild = int.fromEnvironment('APP_BUILD');

/// Открытый ключ Ed25519 для проверки подписи релизов (base64).
/// Если сборка сделана с ключом — обновления без верной подписи не ставятся.
const kUpdatePubKey = String.fromEnvironment('UPDATE_PUBKEY');

/// Найденное обновление приложения.
class AppUpdate {
  AppUpdate({
    required this.build,
    required this.version,
    required this.xray,
    required this.url,
    required this.fileName,
    required this.sha256,
  });
  final int build;
  final String version;
  final String xray;
  final String url;
  final String fileName;
  final String sha256;
}

class AppUpdater {
  static Map<String, String> get _headers => {
        'User-Agent': 'Nexus',
        'Accept': 'application/vnd.github+json',
      };

  static bool get configured => kUpdateRepo.isNotEmpty;

  static Future<int> currentBuild() async {
    if (kAppBuild > 0) return kAppBuild;
    if (Platform.isAndroid) {
      final info = await AndroidSystem.appInfo();
      return (info['versionCode'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// Какие файлы релиза подходят этому устройству (по порядку предпочтения).
  static Future<List<bool Function(String)>> _wanted() async {
    if (Platform.isWindows) {
      // Установлен установщиком — обновляем установщиком; портативная версия — архивом.
      final installed = File(Platform.resolvedExecutable)
          .parent
          .path
          .toLowerCase()
          .endsWith(r'\programs\nexus');
      bool setup(String n) => n.startsWith('Nexus-Setup-') && n.endsWith('.exe');
      bool zip(String n) => n == 'Nexus-Windows-x64.zip';
      return installed ? [setup, zip] : [zip];
    }
    final abi = (await AndroidSystem.appInfo())['abi']?.toString() ?? '';
    final own = switch (abi) {
      'arm64-v8a' => 'Nexus-arm64.apk',
      'armeabi-v7a' => 'Nexus-armv7.apk',
      _ => 'Nexus-universal.apk',
    };
    return [(n) => n == own, (n) => n == 'Nexus-universal.apk'];
  }

  /// Проверяет последний (не пробный) релиз. null — обновлений нет.
  static Future<AppUpdate?> check() async {
    if (!configured) throw Exception('Источник обновлений не задан в сборке');
    final current = await currentBuild();

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
            RegExp(r'nexus-build:[ \t]*(\d+)').firstMatch(body)?.group(1) ??
                '') ??
        0;
    if (build <= current) return null;
    final xray = RegExp(r'xray:[ \t]*([\d.]+)').firstMatch(body)?.group(1) ?? '';
    final version = (j['name'] ?? j['tag_name'] ?? '').toString();

    final assets = <String, String>{};
    for (final a in (j['assets'] as List? ?? [])) {
      final name = a['name']?.toString() ?? '';
      final url = a['browser_download_url']?.toString();
      if (url != null && url.startsWith('https://github.com/')) {
        assets[name] = url;
      }
    }
    String? fileName;
    for (final want in await _wanted()) {
      fileName = assets.keys.where(want).firstOrNull;
      if (fileName != null) break;
    }
    final sumsUrl = assets['SHA256SUMS.txt'];
    if (fileName == null || sumsUrl == null) {
      throw Exception('В релизе нет файла для этого устройства');
    }

    final sumsBytes =
        (await http.get(Uri.parse(sumsUrl), headers: _headers)).bodyBytes;
    if (kUpdatePubKey.isNotEmpty) {
      // Подпись списка контрольных сумм ключом владельца (секрет в GitHub).
      final sigUrl = assets['SHA256SUMS.txt.sig'];
      if (sigUrl == null) throw Exception('Релиз не подписан — пропущен');
      final sig =
          (await http.get(Uri.parse(sigUrl), headers: _headers)).bodyBytes;
      final ok = await cg.Ed25519().verify(
        sumsBytes,
        signature: cg.Signature(sig,
            publicKey: cg.SimplePublicKey(base64.decode(kUpdatePubKey),
                type: cg.KeyPairType.ed25519)),
      );
      if (!ok) throw Exception('Подпись релиза неверна — обновление отклонено');
    }
    final sums = utf8.decode(sumsBytes, allowMalformed: true);
    final line = sums.split('\n').firstWhere(
        (l) => l.trim().endsWith(' $fileName') || l.trim().endsWith('*$fileName'),
        orElse: () => '');
    final sha = line.trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (sha.length != 64) throw Exception('Нет контрольной суммы для $fileName');

    return AppUpdate(
      build: build,
      version: version,
      xray: xray,
      url: assets[fileName]!,
      fileName: fileName,
      sha256: sha,
    );
  }

  static Future<Directory> _dir() async {
    final base = Platform.isAndroid
        ? (await AndroidSystem.appInfo())['cacheDir'].toString()
        : '${Directory.systemTemp.path}\\NexusUpdate';
    final dir = Directory(Platform.isAndroid ? '$base/updates' : base);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Скачивает файл обновления и проверяет SHA-256.
  /// Если файл уже скачан и цел — повторно не качает.
  static Future<File> download(AppUpdate u,
      {void Function(double)? onProgress}) async {
    final dir = await _dir();
    final file = File(
        '${dir.path}${Platform.pathSeparator}b${u.build}-${u.fileName}');
    if (file.existsSync() &&
        sha256.convert(await file.readAsBytes()).toString() == u.sha256) {
      return file;
    }
    // Старые загрузки больше не нужны.
    for (final f in dir.listSync()) {
      try {
        f.deleteSync(recursive: true);
      } catch (_) {}
    }

    final client = http.Client();
    try {
      final resp = await client
          .send(http.Request('GET', Uri.parse(u.url))
            ..headers['User-Agent'] = 'Nexus')
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw Exception('Загрузка не удалась (код ${resp.statusCode})');
      }
      final total = resp.contentLength ?? 0;
      final sink = file.openWrite();
      final digest = _DigestSink();
      final hasher = sha256.startChunkedConversion(digest);
      var got = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        hasher.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress?.call(got / total);
      }
      await sink.close();
      hasher.close();
      if (digest.value.toString() != u.sha256) {
        file.deleteSync();
        throw Exception('Контрольная сумма не совпала — обновление отменено');
      }
    } finally {
      client.close();
    }
    return file;
  }

  /// Запускает установку. На Windows после вызова приложение нужно закрыть.
  static Future<void> install(File file) async {
    if (Platform.isAndroid) {
      if (!await AndroidSystem.canInstallApk()) {
        await AndroidSystem.openInstallSettings();
        throw Exception(
            'Разрешите Nexus устанавливать приложения и нажмите «Установить» ещё раз');
      }
      if (!await AndroidSystem.installApk(file.path)) {
        throw Exception('Не удалось открыть установщик');
      }
      return;
    }

    if (file.path.toLowerCase().endsWith('.exe')) {
      // Тихая установка поверх; установщик сам закроет Nexus и запустит заново.
      await Process.start(
        file.path,
        ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'],
        mode: ProcessStartMode.detached,
      );
      return;
    }

    // Портативная версия: распаковываем рядом и подменяем файлы скриптом,
    // который дождётся закрытия Nexus.
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final stage = Directory('${file.parent.path}\\stage');
    if (stage.existsSync()) stage.deleteSync(recursive: true);
    stage.createSync(recursive: true);
    final zip = ZipDecoder().decodeBytes(await file.readAsBytes());
    for (final f in zip.files) {
      // Защита от путей вида ..\..\ и абсолютных путей внутри архива.
      final parts = f.name.split(RegExp(r'[\\/]'));
      if (f.name.contains(':') ||
          f.name.startsWith('/') ||
          f.name.startsWith('\\') ||
          parts.any((p) => p == '..')) {
        throw Exception('Подозрительный путь в архиве обновления');
      }
      final out = '${stage.path}\\${parts.where((p) => p.isNotEmpty).join('\\')}';
      if (f.isFile) {
        File(out)
          ..createSync(recursive: true)
          ..writeAsBytesSync(f.content as List<int>);
      }
    }
    // В .cmd знак % раскрывается как переменная — экранируем пути.
    String q(String p) => p.replaceAll('%', '%%');
    final exe = q(Platform.resolvedExecutable);
    final script = File('${file.parent.path}\\apply.cmd');
    await script.writeAsString('''@echo off
chcp 65001 >nul
:wait
tasklist /FI "PID eq $pid" | find "$pid" >nul && (timeout /t 1 /nobreak >nul & goto wait)
robocopy "${q(stage.path)}" "${q(appDir)}" /E /R:5 /W:1 /NFL /NDL /NJH /NJS >nul
start "" "$exe"
''');
    await Process.start('cmd', ['/c', script.path],
        mode: ProcessStartMode.detached);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
