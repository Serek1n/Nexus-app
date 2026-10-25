"""
Донастраивает папки android/ и windows/, которые CI генерирует командой
`flutter create`. Запускается после неё: python tool/patch_platforms.py
Падает с ошибкой, если шаблон Flutter изменился и патч не применился.
"""
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
errors = []


def patch(path, pairs, required=True):
    p = ROOT / path
    if not p.exists():
        if required:
            errors.append(f"нет файла {path}")
        return
    s = p.read_text(encoding="utf-8")
    for old, new in pairs:
        if callable(old):
            s2 = old(s)
        elif isinstance(old, re.Pattern):
            s2 = old.sub(new, s, count=1)
        else:
            s2 = s.replace(old, new, 1)
        if s2 == s and required:
            errors.append(f"{path}: не найдено «{getattr(old, 'pattern', old)!s:.60}»")
        s = s2
    p.write_text(s, encoding="utf-8")
    print("patched", path)


def android():
    if not (ROOT / "android").exists():
        return
    # Манифест: название, http-подписки (3x-ui часто отдаёт по http).
    # Манифест: название; http-подписки (3x-ui часто отдаёт по http);
    # запрет резервного копирования (в данных — ссылки подписок с ключами);
    # убираем лишнее разрешение на чтение памяти, которое объявляет плагин ядра.
    patch("android/app/src/main/AndroidManifest.xml", [
        (re.compile(r'<manifest xmlns:android="http://schemas.android.com/apk/res/android"'),
         '<manifest xmlns:android="http://schemas.android.com/apk/res/android"\n'
         '    xmlns:tools="http://schemas.android.com/tools"'),
        (re.compile(r'android:label="[^"]*"'), 'android:label="Nexus"'),
        # Ссылки nexus://add/... из Discord-бота открывают Nexus.
        (re.compile(r"(<category android:name=\"android.intent.category.LAUNCHER\"\s*/>\s*</intent-filter>)"),
         r'\1\n            <intent-filter>\n'
         r'                <action android:name="android.intent.action.VIEW" />\n'
         r'                <category android:name="android.intent.category.DEFAULT" />\n'
         r'                <category android:name="android.intent.category.BROWSABLE" />\n'
         r'                <data android:scheme="nexus" />\n'
         r'            </intent-filter>'),
        # FileProvider для установки скачанных обновлений.
        (re.compile(r"(\s*)</application>"),
         r'\1    <provider\n'
         r'            android:name="androidx.core.content.FileProvider"\n'
         r'            android:authorities="${applicationId}.nexus.files"\n'
         r'            android:exported="false"\n'
         r'            android:grantUriPermissions="true">\n'
         r'            <meta-data\n'
         r'                android:name="android.support.FILE_PROVIDER_PATHS"\n'
         r'                android:resource="@xml/nexus_files" />\n'
         r'        </provider>\1</application>'),
        # Видеть установленные приложения (для списка «Приложения без VPN»).
        (re.compile(r"<queries>"),
         '<queries>\n        <intent>\n'
         '            <action android:name="android.intent.action.MAIN"/>\n'
         '            <category android:name="android.intent.category.LAUNCHER"/>\n'
         '        </intent>'),
        (re.compile(r"(\s*)<application"),
         r'\1<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" tools:node="remove" />'
         r'\1<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />'
         r'\1<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />'
         r'\1<application\n        android:usesCleartextTraffic="true"'
         r'\n        android:allowBackup="false"'),
    ])

    gradle = "android/app/build.gradle.kts"
    if not (ROOT / gradle).exists():
        errors.append("ожидался android/app/build.gradle.kts (Kotlin DSL)")
        return
    patch(gradle, [
        (lambda s: "import java.util.Properties\nimport java.io.FileInputStream\n\n" + s, None),
        (re.compile(r"(plugins \{.*?\n\}\n)", re.S),
         r"""\1
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
"""),
        (re.compile(r"android \{\n"),
         """android {
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

"""),
        (re.compile(r"\nflutter \{"),
         '\ndependencies {\n    implementation("androidx.core:core-ktx:1.13.1")\n}\n\nflutter {'),
        (re.compile(r'signingConfig = signingConfigs\.getByName\("debug"\)'),
         'signingConfig = if (keystorePropertiesFile.exists()) '
         'signingConfigs.getByName("release") else signingConfigs.getByName("debug")\n'
         '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")'),
    ])
    shutil.copy(ROOT / "tool/proguard-rules.pro", ROOT / "android/app/proguard-rules.pro")

    # Папка, откуда FileProvider отдаёт APK обновления установщику.
    xml_dir = ROOT / "android/app/src/main/res/xml"
    xml_dir.mkdir(parents=True, exist_ok=True)
    (xml_dir / "nexus_files.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<paths>\n    <cache-path name="updates" path="updates/" />\n</paths>\n',
        encoding="utf-8")

    # MainActivity с системным каналом nexus/system (фон, уведомления, настройки VPN).
    acts = list((ROOT / "android/app/src/main").rglob("MainActivity.kt"))
    if len(acts) != 1:
        errors.append(f"ожидался один MainActivity.kt, найдено {len(acts)}")
    else:
        m = re.search(r"^package\s+([\w.]+)", acts[0].read_text(encoding="utf-8"), re.M)
        if not m:
            errors.append("в MainActivity.kt не найден package")
        else:
            tpl = (ROOT / "tool/MainActivity.kt").read_text(encoding="utf-8")
            acts[0].write_text(tpl.replace("__PACKAGE__", m.group(1)), encoding="utf-8")
            print("patched", acts[0].relative_to(ROOT))

    # Плагин ядра (flutter_v2ray_client) собран под AGP 8.13 — выравниваем версию.
    patch("android/settings.gradle.kts", [
        (re.compile(r'id\("com\.android\.application"\) version "[^"]+"'),
         'id("com.android.application") version "8.13.0"'),
    ])



def windows():
    if not (ROOT / "windows").exists():
        return
    patch("windows/runner/main.cpp", [
        (re.compile(r'Size size\(\d+, \d+\);'), "Size size(1120, 720);"),
        (re.compile(r'window\.Create\(L"[^"]*"'), 'window.Create(L"Nexus"'),
    ])
    patch("windows/runner/Runner.rc", [
        (re.compile(r'VALUE "FileDescription", "[^"]*"'),
         'VALUE "FileDescription", "Nexus"'),
        (re.compile(r'VALUE "ProductName", "[^"]*"'),
         'VALUE "ProductName", "Nexus"'),
        (re.compile(r'VALUE "CompanyName", "[^"]*"'),
         'VALUE "CompanyName", "NEXUS_VPN"'),
    ], required=False)


android()
windows()

if errors:
    print("\nОШИБКИ ПАТЧА:\n  " + "\n  ".join(errors))
    sys.exit(1)
print("ok")
