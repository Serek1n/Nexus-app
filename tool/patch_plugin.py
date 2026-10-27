"""Исправления безопасности и надёжности в плагине flutter_v2ray_client (Android).

На Android 8–12 плагин регистрирует приёмники статуса VPN без защиты:
любое приложение на телефоне могло прислать поддельный «отключено»
(и Nexus начинал переподключаться) или испорченные данные (падение).
Ставим на приёмники разрешение уровня «signature» — присылать статус
сможет только сам Nexus. Разрешение объявляется в манифесте приложения
(tool/patch_platforms.py).

Запуск из корня проекта после `flutter pub get`:
    python tool/patch_plugin.py
"""
import json
import pathlib
import re
import sys
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
PERM = '.permission.NEXUS_INTERNAL'


def plugin_dir() -> pathlib.Path:
    cfg = json.loads((ROOT / '.dart_tool/package_config.json').read_text())
    p = next(x for x in cfg['packages'] if x['name'] == 'flutter_v2ray_client')
    u = p['rootUri']
    if u.startswith('file:'):
        return pathlib.Path(urllib.parse.unquote(urllib.parse.urlparse(u).path))
    return (ROOT / '.dart_tool' / u).resolve()


def patch(src: str) -> tuple[str, int]:
    n = 0
    # Ветка Android 8–12 для задержки: флаг RECEIVER_NOT_EXPORTED там не
    # действует — переводим её на общий защищённый вариант ниже.
    src, k = re.subn(
        r'Build\.VERSION_CODES\.O\)(\s*\{\s*context\.registerReceiver\(receiver, delayIntentFilter, Context\.RECEIVER_NOT_EXPORTED\))',
        r'Build.VERSION_CODES.TIRAMISU)\1', src)
    n += k
    # registerReceiver(приёмник, фильтр) → с разрешением отправителя.
    src, k = re.subn(
        r'(\w+)\.registerReceiver\((\w+), (\w+)\);',
        lambda m: f'{m[1]}.registerReceiver({m[2]}, {m[3]}, '
                  f'{m[1]}.getPackageName() + "{PERM}", null);',
        src)
    n += k
    return src, n


STOP_OLD = """V2RAY_SERVICE_COMMANDS.STOP_SERVICE)) {
            V2rayCoreManager.getInstance().stopCore();"""
STOP_NEW = """V2RAY_SERVICE_COMMANDS.STOP_SERVICE)) {
            // Nexus: процесс службы мог перезапуститься и потерять ссылку на
            // себя — тогда stopCore() падал с NullPointerException, служба
            // не останавливалась и VPN оставался без ядра (интернет пропадал).
            if (V2rayCoreManager.getInstance().v2rayServicesListener == null) {
                V2rayCoreManager.getInstance().v2rayServicesListener = this;
            }
            V2rayCoreManager.getInstance().stopCore();
            stopService();"""


def patch_stop(base: pathlib.Path) -> int:
    n = 0
    for rel in ['v2ray/services/V2rayVPNService.java',
                'v2ray/services/V2rayProxyOnlyService.java']:
        f = base / rel
        src = f.read_text(encoding='utf-8')
        if 'Nexus: процесс службы' in src:
            n += 1
            continue
        if STOP_OLD in src:
            f.write_text(src.replace(STOP_OLD, STOP_NEW, 1), encoding='utf-8')
            print(f'{rel}: остановка службы исправлена')
            n += 1
    f = base / 'v2ray/core/V2rayCoreManager.java'
    src = f.read_text(encoding='utf-8')
    new, k = re.subn(r'(?m)^(\s*)v2rayServicesListener\.stopService\(\);',
                     r'\1if (v2rayServicesListener != null) '
                     r'v2rayServicesListener.stopService();', src)
    if k:
        f.write_text(new, encoding='utf-8')
        print(f'V2rayCoreManager.java: защита от null — {k}')
    if k or 'if (v2rayServicesListener != null) v2rayServicesListener.stopService();' in src:
        n += 1
    return n


def main() -> int:
    base = plugin_dir() / 'android/src/main/java/dev/amirzr/flutter_v2ray_client'
    total = 0
    for rel in ['v2ray/V2rayController.java', 'FlutterV2rayPlugin.java']:
        f = base / rel
        src = f.read_text(encoding='utf-8')
        if PERM in src:
            print(f'{rel}: уже исправлен')
            total += 1
            continue
        new, n = patch(src)
        f.write_text(new, encoding='utf-8')
        print(f'{rel}: исправлено мест — {n}')
        total += n
    if total == 0:
        print('Не найдено ни одного места для исправления — плагин изменился')
        return 1
    if patch_stop(base) < 3:
        print('Не удалось исправить остановку службы VPN — плагин изменился')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
