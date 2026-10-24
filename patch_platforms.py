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
    patch("android/app/src/main/AndroidManifest.xml", [
        (re.compile(r'android:label="[^"]*"'), 'android:label="Nexus"'),
        (re.compile(r"<application"),
         '<application\n        android:usesCleartextTraffic="true"'),
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
        (re.compile(r'signingConfig = signingConfigs\.getByName\("debug"\)'),
         'signingConfig = if (keystorePropertiesFile.exists()) '
         'signingConfigs.getByName("release") else signingConfigs.getByName("debug")\n'
         '            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")'),
    ])
    shutil.copy(ROOT / "tool/proguard-rules.pro", ROOT / "android/app/proguard-rules.pro")

    props = ROOT / "android/gradle.properties"
    s = props.read_text(encoding="utf-8")
    if "enableUncompressedNativeLibs" not in s:
        s += "\nandroid.bundle.enableUncompressedNativeLibs=false\n"
    props.write_text(s, encoding="utf-8")


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
