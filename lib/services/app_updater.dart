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

/// Опубликованная версия (для отката).
class AppRelease {
  AppRelease({
    required this.build,
    required this.version,
    required this.notes,
    required this.date,
    required this.pageUrl,
    required this.raw,
  });
  final int build;
  final String version;
  final List<String> notes;
  final DateTime? date;
  final String pageUrl;
  final Map<String, dynamic> raw;
}

/// Найденное обновление приложения.
class AppUpdate {
  AppUpdate({
    required this.build,
    required this.version,
    required this.xray,
    required this.url,
    required this.fileName,
    required this.sha256,
    this.notes = const [],
  });
  final int build;
  final String version;
  final String xray;
  final String url;
  final String fileName;
  final String sha256;

  /// Что изменилось (пункты из описания релиза).
  final List<String> notes;
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

  static int _buildOf(Map<String, dynamic> j) =>
      int.tryParse(RegExp(r'nexus-build:[ \t]*(\d+)')
                  .firstMatch((j['body'] ?? '').toString())
                  ?.group(1) ??
              '') ??
      0;

  static Future<http.Response> _api(String path) async {
    final res = await http
        .get(Uri.parse('https://api.github.com/repos/$kUpdateRepo/$path'),
            headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) {
      throw Exception('Релизы недоступны — репозиторий закрыт или пуст');
    }
    if (res.statusCode != 200) {
      throw Exception('GitHub ответил ${res.statusCode}');
    }
    return res;
  }

  /// Проверяет последний (не пробный) релиз. null — обновлений нет.
  static Future<AppUpdate?> check() async {
    if (!configured) throw Exception('Источник обновлений не задан в сборке');
    final current = await currentBuild();
    final j = jsonDecode((await _api('releases/latest')).body)
        as Map<String, dynamic>;
    if (_buildOf(j) <= current) return null;
    return _fromRelease(j);
  }

  /// Прошлые версии для отката (новые сверху, без пробных сборок).
  static Future<List<AppRelease>> history() async {
    if (!configured) throw Exception('Источник обновлений не задан в сборке');
    final list = jsonDecode((await _api('releases?per_page=30')).body);
    final out = <AppRelease>[];
    for (final r in (list is List ? list : const [])) {
      if (r is! Map<String, dynamic>) continue;
      if (r['prerelease'] == true || r['draft'] == true) continue;
      final build = _buildOf(r);
      if (build <= 0) continue;
      final html = r['html_url']?.toString() ?? '';
      out.add(AppRelease(
        build: build,
        version: (r['name'] ?? r['tag_name'] ?? '')
            .toString()
            .split(' · ')
            .first
            .trim(),
        notes: _notes((r['body'] ?? '').toString()),
        date: DateTime.tryParse(r['published_at']?.toString() ?? ''),
        pageUrl: html.startsWith('https://github.com/') ? html : '',
        raw: r,
      ));
    }
    out.sort((a, b) => b.build.compareTo(a.build));
    return out;
  }

  /// Готовит выбранную версию к установке (файл, контрольная сумма, подпись).
  static Future<AppUpdate> prepare(AppRelease r) => _fromRelease(r.raw);

  static Future<AppUpdate> _fromRelease(Map<String, dynamic> j) async {
    final body = (j['body'] ?? '').toString();
    final build = _buildOf(j);
    final xray = RegExp(r'xray:[ \t]*([\d.]+)').firstMatch(body)?.group(1) ?? '';
    // Из названия релиза оставляем только «Nexus 1.7.1» — без версии Xray.
    final version = (j['name'] ?? j['tag_name'] ?? '')
        .toString()
        .split(' · ')
        .first
        .trim();

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
      notes: _notes(body),
    );
  }

  /// Пункты «- …» из раздела «Что нового» описания релиза.
  static List<String> _notes(String body) {
    final start = body.indexOf('Что нового');
    if (start < 0) return const [];
    final out = <String>[];
    for (final line in body.substring(start).split('\n').skip(1)) {
      final t = line.trim();
      if (t.startsWith('- ')) {
        out.add(t.substring(2).trim());
      } else if (t.isNotEmpty) {
        break;
      }
      if (out.length >= 12) break;
    }
    return out;
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
ie4uinit.exe -show >nul 2>&1
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
