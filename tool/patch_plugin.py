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


ALWAYS_OLD = """    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {"""
ALWAYS_NEW = """    public int onStartCommand(Intent intent, int flags, int startId) {
        // Nexus: «Постоянная VPN» Android запускает службу сама — без команды
        // и конфига. Раньше служба тут же останавливалась, и с «Блокировать
        // соединения без VPN» телефон оставался без интернета. Берём
        // последний конфиг Nexus (зашифрован ключом устройства).
        if (intent == null || intent.getSerializableExtra("COMMAND") == null) {
            try {
                Class<?> nx = Class.forName(getPackageName() + ".NexusTile");
                String saved = (String) nx.getMethod("alwaysOnConfig", android.content.Context.class)
                        .invoke(null, this);
                if (saved != null) {
                    JSONObject j = new JSONObject(saved);
                    java.util.ArrayList<String> blocked = new java.util.ArrayList<>();
                    JSONArray arr = j.optJSONArray("blocked");
                    if (arr != null) for (int i = 0; i < arr.length(); i++) blocked.add(arr.getString(i));
                    AppConfigs.V2RAY_CONNECTION_MODE = AppConfigs.V2RAY_CONNECTION_MODES.VPN_TUN;
                    AppConfigs.APPLICATION_ICON = getResources().getIdentifier("ic_launcher", "mipmap", getPackageName());
                    AppConfigs.APPLICATION_NAME = "Nexus";
                    if (AppConfigs.NOTIFICATION_DISCONNECT_BUTTON_NAME == null) {
                        AppConfigs.NOTIFICATION_DISCONNECT_BUTTON_NAME = "ОТКЛЮЧИТЬ";
                    }
                    V2rayConfig cfg = Utilities.parseV2rayJsonFile(j.optString("remark", "Nexus"),
                            j.getString("config"), blocked.isEmpty() ? null : blocked, null);
                    if (cfg != null) {
                        intent = new Intent(this, V2rayVPNService.class);
                        intent.putExtra("COMMAND", AppConfigs.V2RAY_SERVICE_COMMANDS.START_SERVICE);
                        intent.putExtra("V2RAY_CONFIG", cfg);
                        nx.getMethod("markStarted", android.content.Context.class).invoke(null, this);
                        Log.i("V2rayVPNService", "Nexus: started by always-on VPN with saved config");
                    }
                }
            } catch (Throwable t) {
                Log.w("V2rayVPNService", "Nexus: no saved config for always-on VPN", t);
            }
        }
        if (intent == null) {"""


def patch_always_on(base: pathlib.Path) -> bool:
    f = base / 'v2ray/services/V2rayVPNService.java'
    src = f.read_text(encoding='utf-8')
    if 'Nexus: «Постоянная VPN»' in src:
        return True
    if ALWAYS_OLD not in src:
        return False
    f.write_text(src.replace(ALWAYS_OLD, ALWAYS_NEW, 1), encoding='utf-8')
    print('V2rayVPNService.java: запуск постоянной VPN исправлен')
    return True


ASSETS_OLD = 'String geo = "geosite.dat,geoip.dat";'
ASSETS_NEW = 'String geo = "geosite.dat,geoip.dat,nexus-blocked.dat";'


def patch_assets(base: pathlib.Path) -> bool:
    """Плагин копирует из APK только geosite.dat и geoip.dat — добавляем
    nexus-blocked.dat (список для режима «Только заблокированное»)."""
    f = base / 'v2ray/utils/Utilities.java'
    src = f.read_text(encoding='utf-8')
    if ASSETS_NEW in src:
        return True
    if ASSETS_OLD not in src:
        return False
    f.write_text(src.replace(ASSETS_OLD, ASSETS_NEW), encoding='utf-8')
    print(f'{f.name}: + nexus-blocked.dat')
    return True


SWAP_OLD = """            if (V2rayCoreManager.getInstance().isV2rayCoreRunning()) {
                V2rayCoreManager.getInstance().stopCore();
            }

            // 1) Establish VpnService TUN first (v2rayNG order).
            if (!establishVpnInterface()) {"""
SWAP_NEW = """            // Nexus: смена сервера без разрыва VPN. Новый интерфейс поднимается
            // раньше, чем останавливается старое ядро: Android переводит трафик
            // на него сразу, и в паузе между ядрами пакеты ждут в туннеле, а не
            // уходят в сеть напрямую.
            ParcelFileDescriptor nexusOld = null;
            boolean nexusSwap = V2rayCoreManager.getInstance().isV2rayCoreRunning()
                    && mInterface != null;
            if (nexusSwap) {
                nexusOld = mInterface;
                mInterface = null;
            } else if (V2rayCoreManager.getInstance().isV2rayCoreRunning()) {
                V2rayCoreManager.getInstance().stopCore();
            }

            // 1) Establish VpnService TUN first (v2rayNG order).
            boolean nexusUp = establishVpnInterface();
            if (nexusSwap) {
                nexusSwapping = true;
                try {
                    V2rayCoreManager.getInstance().stopLoopOnly();
                } finally {
                    nexusSwapping = false;
                }
                V2rayCoreManager.getInstance().v2rayServicesListener = this;
                try {
                    nexusOld.close();
                } catch (Exception ignored) {
                }
            }
            if (!nexusUp) {"""

SWAP_FIELD_OLD = """    private boolean vpnInterfaceReady = false;
"""
SWAP_FIELD_NEW = """    private boolean vpnInterfaceReady = false;
    /** Nexus: идёт смена ядра без разрыва — сигнал «ядро остановлено» не гасит VPN. */
    private boolean nexusSwapping = false;
"""

SWAP_STOP_OLD = """    public void stopService() {
        stopAllProcess();"""
SWAP_STOP_NEW = """    public void stopService() {
        if (nexusSwapping) return;
        stopAllProcess();"""

LOOP_OLD = """    public void stopCore() {"""
LOOP_NEW = """    /** Nexus: остановить только ядро — VPN-интерфейс и служба остаются. */
    public void stopLoopOnly() {
        try {
            if (countDownTimer != null) countDownTimer.cancel();
            if (coreController != null && isV2rayCoreRunning()) coreController.stopLoop();
        } catch (Exception e) {
            Log.w(V2rayCoreManager.class.getSimpleName(), "stopLoopOnly failed", e);
        }
    }

    public void stopCore() {"""


def patch_swap(base: pathlib.Path) -> bool:
    """Смена сервера на Android без выхода трафика напрямую (и MTU 1400)."""
    f = base / 'v2ray/services/V2rayVPNService.java'
    src = f.read_text(encoding='utf-8')
    if 'Nexus: смена сервера без разрыва' not in src:
        for a, b in [(SWAP_OLD, SWAP_NEW), (SWAP_FIELD_OLD, SWAP_FIELD_NEW),
                     (SWAP_STOP_OLD, SWAP_STOP_NEW)]:
            if a not in src:
                return False
            src = src.replace(a, b, 1)
        # Запас на заголовки туннеля: без дробления пакетов на мобильных сетях.
        src = src.replace('VPN_MTU = 1500;', 'VPN_MTU = 1400;')
        f.write_text(src, encoding='utf-8')
        print('V2rayVPNService.java: смена сервера без разрыва, MTU 1400')
    f = base / 'v2ray/core/V2rayCoreManager.java'
    src = f.read_text(encoding='utf-8')
    if 'public void stopLoopOnly()' not in src:
        if LOOP_OLD not in src:
            return False
        src = src.replace(LOOP_OLD, LOOP_NEW, 1)
        src = src.replace('Utilities.ensureTunInbound(config, 1500)',
                          'Utilities.ensureTunInbound(config, 1400)')
        f.write_text(src, encoding='utf-8')
        print('V2rayCoreManager.java: остановка ядра без остановки VPN')
    return True


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
    if not patch_always_on(base):
        print('Не удалось исправить запуск постоянной VPN — плагин изменился')
        return 1
    if not patch_swap(base):
        print('Не удалось включить смену сервера без разрыва — плагин изменился')
        return 1
    if not patch_assets(base):
        print('Не удалось добавить список заблокированных сайтов — плагин изменился')
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
