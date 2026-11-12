"""
Донастраивает папки android/, windows/, linux/ и macos/, которые CI генерирует командой
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
        # Android TV: значок в меню телевизора (LEANBACK_LAUNCHER).
        (re.compile(r"(<category android:name=\"android.intent.category.LAUNCHER\"\s*/>)"),
         r'\1\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>'),
        (re.compile(r"(<category android:name=\"android.intent.category.LEANBACK_LAUNCHER\"/>\s*</intent-filter>)"),
         r'\1\n            <intent-filter>\n'
         r'                <action android:name="android.intent.action.VIEW" />\n'
         r'                <category android:name="android.intent.category.DEFAULT" />\n'
         r'                <category android:name="android.intent.category.BROWSABLE" />\n'
         r'                <data android:scheme="nexus" />\n'
         r'            </intent-filter>'),
        # FileProvider для установки скачанных обновлений.
        (re.compile(r"(\s*)</application>"),
         r'\1    <receiver\n'
         r'            android:name=".NexusWidget"\n'
         r'            android:exported="true"\n'
         r'            android:label="Nexus">\n'
         r'            <intent-filter>\n'
         r'                <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />\n'
         r'            </intent-filter>\n'
         r'            <meta-data\n'
         r'                android:name="android.appwidget.provider"\n'
         r'                android:resource="@xml/nexus_widget_info" />\n'
         r'        </receiver>'
         r'\1    <receiver android:name=".NexusAlarmReceiver" android:exported="false" />'
         r'\1    <receiver\n'
         r'            android:name=".NexusBootReceiver"\n'
         r'            android:exported="true">\n'
         r'            <intent-filter>\n'
         r'                <action android:name="android.intent.action.BOOT_COMPLETED" />\n'
         r'            </intent-filter>\n'
         r'        </receiver>'
         r'\1    <service\n'
         r'            android:name=".NexusTileService"\n'
         r'            android:exported="true"\n'
         r'            android:label="Nexus"\n'
         r'            android:icon="@drawable/ic_nexus_tile"\n'
         r'            android:permission="android.permission.BIND_QUICK_SETTINGS_TILE">\n'
         r'            <intent-filter>\n'
         r'                <action android:name="android.service.quicksettings.action.QS_TILE" />\n'
         r'            </intent-filter>\n'
         r'            <meta-data\n'
         r'                android:name="android.service.quicksettings.TOGGLEABLE_TILE"\n'
         r'                android:value="true" />\n'
         r'        </service>'
         r'\1    <provider\n'
         r'            android:name="androidx.core.content.FileProvider"\n'
         r'            android:authorities="${applicationId}.nexus.files"\n'
         r'            android:exported="false"\n'
         r'            android:grantUriPermissions="true">\n'
         r'            <meta-data\n'
         r'                android:name="android.support.FILE_PROVIDER_PATHS"\n'
         r'                android:resource="@xml/nexus_files" />\n'
         r'        </provider>'
         r'\1    <meta-data\n'
         r'            android:name="com.google.mlkit.vision.DEPENDENCIES"\n'
         r'            android:value="barcode_ui" />\1</application>'),
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
         r'\1<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />'
         # Телевизоры без сенсорного экрана тоже могут ставить Nexus.
         r'\1<uses-feature android:name="android.hardware.touchscreen" android:required="false" />'
         r'\1<uses-feature android:name="android.software.leanback" android:required="false" />'
         # Внутреннее разрешение: статус VPN могут присылать только
         # процессы самого Nexus (см. tool/patch_plugin.py).
         r'\1<permission android:name="${applicationId}.permission.NEXUS_INTERNAL" android:protectionLevel="signature" />'
         r'\1<uses-permission android:name="${applicationId}.permission.NEXUS_INTERNAL" />'
         r'\1<application\n        android:usesCleartextTraffic="true"'
         r'\n        android:allowBackup="false"'
         # Android 12+: allowBackup не запрещает перенос данных при смене
         # телефона — запрещаем его отдельными правилами.
         r'\n        android:fullBackupContent="false"'
         r'\n        android:dataExtractionRules="@xml/nexus_no_backup"'
         r'\n        android:banner="@drawable/nexus_banner"'),
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
         '\ndependencies {\n    implementation("androidx.core:core-ktx:1.13.1")\n    // Сканер QR из сервисов Google: своё окно камеры, без разрешения на камеру.\n    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")\n}\n\nflutter {'),
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
    # Значок плитки в шторке: одноцветная «N» (система сама красит её).
    dr_dir = ROOT / "android/app/src/main/res/drawable"
    # Баннер для меню Android TV (320×180 dp).
    tv_dir = ROOT / "android/app/src/main/res/drawable-xhdpi"
    tv_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy(ROOT / "tool/res/nexus_banner.png", tv_dir / "nexus_banner.png")
    dr_dir.mkdir(parents=True, exist_ok=True)
    (dr_dir / "ic_nexus_tile.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="24dp" android:height="24dp"\n'
        '    android:viewportWidth="24" android:viewportHeight="24">\n'
        '    <path android:fillColor="#FFFFFFFF"\n'
        '        android:pathData="M6,19V5h2.4l7.2,9.6V5H18v14h-2.4L8.4,9.4V19Z" />\n'
        '    <path android:fillColor="#FFFFFFFF"\n'
        '        android:pathData="M20,4m-1.5,0a1.5,1.5 0,1 1,3 0a1.5,1.5 0,1 1,-3 0" />\n'
        '</vector>\n',
        encoding="utf-8")

    # Виджет на рабочий стол.
    lay_dir = ROOT / "android/app/src/main/res/layout"
    lay_dir.mkdir(parents=True, exist_ok=True)
    (lay_dir / "nexus_widget.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:id="@+id/nexus_widget_root"\n'
        '    android:layout_width="match_parent" android:layout_height="match_parent"\n'
        '    android:orientation="horizontal" android:gravity="center_vertical"\n'
        '    android:padding="12dp" android:background="@drawable/nexus_widget_bg">\n'
        '    <ImageView android:id="@+id/nexus_widget_icon"\n'
        '        android:layout_width="38dp" android:layout_height="38dp"\n'
        '        android:padding="9dp" android:src="@drawable/ic_nexus_tile"\n'
        '        android:background="@drawable/nexus_widget_dot_off" />\n'
        '    <LinearLayout android:layout_width="0dp" android:layout_weight="1"\n'
        '        android:layout_height="wrap_content" android:orientation="vertical"\n'
        '        android:layout_marginStart="12dp">\n'
        '        <TextView android:layout_width="wrap_content" android:layout_height="wrap_content"\n'
        '            android:text="Nexus" android:textColor="#FFECECF1"\n'
        '            android:textSize="15sp" android:textStyle="bold" />\n'
        '        <TextView android:id="@+id/nexus_widget_state"\n'
        '            android:layout_width="wrap_content" android:layout_height="wrap_content"\n'
        '            android:text="Отключено" android:textColor="#FF9C9CAD" android:textSize="12sp" />\n'
        '    </LinearLayout>\n'
        '</LinearLayout>\n',
        encoding="utf-8")
    def shape(name, body):
        (dr_dir / name).write_text(
            '<?xml version="1.0" encoding="utf-8"?>\n'
            '<shape xmlns:android="http://schemas.android.com/apk/res/android" ' + body + '</shape>\n',
            encoding="utf-8")
    shape("nexus_widget_bg.xml",
          'android:shape="rectangle">\n    <solid android:color="#F215151C" />\n'
          '    <corners android:radius="22dp" />\n'
          '    <stroke android:width="1dp" android:color="#22FFFFFF" />\n')
    shape("nexus_widget_dot_off.xml",
          'android:shape="oval">\n    <solid android:color="#33FFFFFF" />\n')
    shape("nexus_widget_dot_on.xml",
          'android:shape="oval">\n    <solid android:color="#FF8B7CF6" />\n')
    (xml_dir / "nexus_widget_info.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:minWidth="140dp" android:minHeight="50dp"\n'
        '    android:targetCellWidth="2" android:targetCellHeight="1"\n'
        '    android:updatePeriodMillis="1800000"\n'
        '    android:initialLayout="@layout/nexus_widget"\n'
        '    android:previewLayout="@layout/nexus_widget"\n'
        '    android:resizeMode="horizontal"\n'
        '    android:widgetCategory="home_screen" />\n',
        encoding="utf-8")

    # Ни облачная копия, ни перенос на новый телефон не забирают данные
    # Nexus (подписки с ключами, ID устройства для лимита HWID).
    (xml_dir / "nexus_no_backup.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<data-extraction-rules>\n'
        '    <cloud-backup>\n'
        '        <exclude domain="root" />\n'
        '        <exclude domain="file" />\n'
        '        <exclude domain="database" />\n'
        '        <exclude domain="sharedpref" />\n'
        '        <exclude domain="external" />\n'
        '    </cloud-backup>\n'
        '    <device-transfer>\n'
        '        <exclude domain="root" />\n'
        '        <exclude domain="file" />\n'
        '        <exclude domain="database" />\n'
        '        <exclude domain="sharedpref" />\n'
        '        <exclude domain="external" />\n'
        '    </device-transfer>\n'
        '</data-extraction-rules>\n',
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
            # Плитка «Nexus» в шторке — рядом с MainActivity, в том же пакете.
            tile = (ROOT / "tool/NexusTileService.kt").read_text(encoding="utf-8")
            (acts[0].parent / "NexusTileService.kt").write_text(
                tile.replace("__PACKAGE__", m.group(1)), encoding="utf-8")

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
    # Горячая клавиша Ctrl+Alt+N (подключить/отключить из любой программы):
    # Windows присылает WM_HOTKEY окну, передаём его в Dart по каналу.
    patch("windows/runner/flutter_window.h", [
        ("#include <flutter/flutter_view_controller.h>\n",
         "#include <flutter/flutter_view_controller.h>\n"
         "#include <flutter/method_channel.h>\n"
         "#include <flutter/standard_method_codec.h>\n"),
        ("  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;\n",
         "  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;\n\n"
         "  // Канал горячей клавиши Nexus (Ctrl+Alt+N).\n"
         "  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> hotkey_channel_;\n"
         "  // Nexus включил свой системный прокси (см. WM_ENDSESSION).\n"
         "  bool proxy_owned_ = false;\n"),
    ])
    patch("windows/runner/flutter_window.cpp", [
        ("  RegisterPlugins(flutter_controller_->engine());\n",
         "  RegisterPlugins(flutter_controller_->engine());\n"
         "  hotkey_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(\n"
         "      flutter_controller_->engine()->messenger(), \"nexus/hotkey\",\n"
         "      &flutter::StandardMethodCodec::GetInstance());\n"
         "  hotkey_channel_->SetMethodCallHandler(\n"
         "      [this](const flutter::MethodCall<flutter::EncodableValue>& call,\n"
         "             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {\n"
         "        if (call.method_name() == \"register\") {\n"
         "          UnregisterHotKey(GetHandle(), 0x4E58);\n"
         "          BOOL ok = RegisterHotKey(GetHandle(), 0x4E58,\n"
         "                                   MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, 'N');\n"
         "          result->Success(flutter::EncodableValue(ok != 0));\n"
         "        } else if (call.method_name() == \"unregister\") {\n"
         "          UnregisterHotKey(GetHandle(), 0x4E58);\n"
         "          result->Success();\n"
         "        } else if (call.method_name() == \"proxyOwned\") {\n"
         "          const auto* v = std::get_if<bool>(call.arguments());\n"
         "          proxy_owned_ = v != nullptr && *v;\n"
         "          result->Success();\n"
         "        } else {\n"
         "          result->NotImplemented();\n"
         "        }\n"
         "      });\n"),
        ("    case WM_FONTCHANGE:\n",
         # Выключение или выход из Windows при подключённом VPN: выключаем
         # системный прокси, иначе после загрузки браузеры остались бы без
         # интернета до запуска Nexus. Прежний прокси пользователя Nexus
         # вернёт при следующем запуске (отметка proxy.lock).
         "    case WM_ENDSESSION:\n"
         "      if (wparam && proxy_owned_) {\n"
         "        HKEY key;\n"
         "        if (RegOpenKeyExW(HKEY_CURRENT_USER,\n"
         "                L\"Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Internet Settings\",\n"
         "                0, KEY_SET_VALUE, &key) == ERROR_SUCCESS) {\n"
         "          DWORD off = 0;\n"
         "          RegSetValueExW(key, L\"ProxyEnable\", 0, REG_DWORD,\n"
         "                         reinterpret_cast<const BYTE*>(&off), sizeof(off));\n"
         "          RegCloseKey(key);\n"
         "        }\n"
         "      }\n"
         "      break;\n"
         "    case WM_HOTKEY:\n"
         "      if (wparam == 0x4E58 && hotkey_channel_) {\n"
         "        hotkey_channel_->InvokeMethod(\"hotkey\", nullptr);\n"
         "        return 0;\n"
         "      }\n"
         "      break;\n"
         "    case WM_FONTCHANGE:\n"),
        ("  if (flutter_controller_) {\n    flutter_controller_ = nullptr;\n  }\n",
         "  if (GetHandle()) UnregisterHotKey(GetHandle(), 0x4E58);\n"
         "  hotkey_channel_ = nullptr;\n"
         "  if (flutter_controller_) {\n    flutter_controller_ = nullptr;\n  }\n"),
    ])
    patch("windows/runner/Runner.rc", [
        (re.compile(r'VALUE "FileDescription", "[^"]*"'),
         'VALUE "FileDescription", "Nexus"'),
        (re.compile(r'VALUE "ProductName", "[^"]*"'),
         'VALUE "ProductName", "Nexus"'),
        (re.compile(r'VALUE "CompanyName", "[^"]*"'),
         'VALUE "CompanyName", "NEXUS_VPN"'),
    ], required=False)


def linux():
    """Окно «Nexus» нужного размера."""
    patch("linux/runner/my_application.cc", [
        (re.compile(r'gtk_header_bar_set_title\(header_bar, "[^"]*"\)'),
         'gtk_header_bar_set_title(header_bar, "Nexus")'),
        (re.compile(r'gtk_window_set_title\(window, "[^"]*"\)'),
         'gtk_window_set_title(window, "Nexus")'),
        (re.compile(r'gtk_window_set_default_size\(window, \d+, \d+\)'),
         'gtk_window_set_default_size(window, 1120, 720)'),
    ])


MAC_WINDOW = """import Cocoa
import FlutterMacOS
import Security

// Nexus: ссылки nexus:// (Apple Event «открыть URL») — в Dart через канал
// nexus/links; клик по значку в Dock показывает спрятанное окно.
final class NexusLinks: NSObject {
  static let shared = NexusLinks()
  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  weak var window: NSWindow?

  func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "nexus/links", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      if call.method == "initialLinks" {
        result(self?.pending ?? [])
        self?.pending = []
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    channel = ch
    NSAppleEventManager.shared().setEventHandler(
      self, andSelector: #selector(handle(_:withReply:)),
      forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    NotificationCenter.default.addObserver(
      self, selector: #selector(activated),
      name: NSApplication.didBecomeActiveNotification, object: nil)
  }

  @objc func handle(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
    guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
          s.lowercased().hasPrefix("nexus:"), s.count <= 8192 else { return }
    if let ch = channel { ch.invokeMethod("link", arguments: s) } else { pending.append(s) }
    show()
  }

  @objc func activated() {
    if let w = window, !w.isVisible { show() }
  }

  func show() {
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

/// Ключ шифрования подписок Nexus в Keychain (канал nexus/keychain).
/// Ошибка чтения (Keychain заблокирован) отличается от «ключа нет»:
/// в первом случае Nexus не создаёт новый ключ и ничего не перезаписывает.
final class NexusKeychain {
  static func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "nexus/keychain", binaryMessenger: messenger)
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "app.nexusvpn.nexus",
      kSecAttrAccount as String: "secrets-key",
    ]
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "get":
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &item)
        if st == errSecSuccess, let d = item as? Data {
          result(FlutterStandardTypedData(bytes: d))
        } else if st == errSecItemNotFound {
          result(nil)
        } else {
          result(FlutterError(code: "keychain", message: "\\(st)", details: nil))
        }
      case "set":
        guard let d = (call.arguments as? FlutterStandardTypedData)?.data else {
          result(false)
          return
        }
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = d
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        result(SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    NexusLinks.shared.window = self
    NexusLinks.shared.attach(flutterViewController.engine.binaryMessenger)
    NexusKeychain.attach(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
"""

MAC_ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- Без песочницы: Nexus запускает ядро Xray, меняет системный прокси
	     (networksetup) и для режима TUN просит права администратора. -->
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
</dict>
</plist>
"""


def macos():
    """Имя Nexus, идентификатор, ссылки nexus://, работа без песочницы."""
    d = ROOT / "macos/Runner"
    (d / "MainFlutterWindow.swift").write_text(MAC_WINDOW, encoding="utf-8")
    # Закрытие окна не завершает Nexus — он остаётся в строке меню.
    patch("macos/Runner/AppDelegate.swift", [
        (re.compile(r"(applicationShouldTerminateAfterLastWindowClosed[^{]*\{\s*return )true"),
         r"\1false"),
    ])
    for name in ("DebugProfile.entitlements", "Release.entitlements"):
        (d / name).write_text(MAC_ENTITLEMENTS, encoding="utf-8")
    patch("macos/Runner/Configs/AppInfo.xcconfig", [
        (re.compile(r"PRODUCT_NAME = .*"), "PRODUCT_NAME = Nexus"),
    ])
    # Идентификатор (app.nexusvpn.nexus) задаёт flutter create --org; копирайт — по желанию.
    patch("macos/Runner/Configs/AppInfo.xcconfig", [
        (re.compile(r"PRODUCT_COPYRIGHT = .*"), "PRODUCT_COPYRIGHT = NEXUS_VPN"),
    ], required=False)
    patch("macos/Runner/Info.plist", [
        ("</dict>\n</plist>",
         "\t<key>CFBundleURLTypes</key>\n"
         "\t<array>\n\t\t<dict>\n"
         "\t\t\t<key>CFBundleURLName</key>\n\t\t\t<string>app.nexusvpn.nexus</string>\n"
         "\t\t\t<key>CFBundleURLSchemes</key>\n\t\t\t<array><string>nexus</string></array>\n"
         "\t\t</dict>\n\t</array>\n"
         "\t<key>LSApplicationCategoryType</key>\n\t<string>public.app-category.utilities</string>\n"
         "</dict>\n</plist>"),
    ])


def ios():
    """Nexus для iOS: свой AppDelegate (без сцен), канал VPN, права, ссылки
    nexus://. Цель NexusTunnel добавляет tool/ios/add_tunnel.rb."""
    import plistlib
    import shutil
    src = ROOT / "tool/ios"
    for f in (src / "Runner").iterdir():
        shutil.copy(f, ROOT / "ios/Runner" / f.name)
    shutil.copytree(src / "NexusTunnel", ROOT / "ios/NexusTunnel", dirs_exist_ok=True)
    # Без сцен: регистрация плагинов и ссылки — в AppDelegate.
    (ROOT / "ios/Runner/SceneDelegate.swift").write_text(
        "// Nexus работает без сцен (UIScene) — см. AppDelegate.swift.\n", encoding="utf-8")
    p = ROOT / "ios/Runner/Info.plist"
    info = plistlib.loads(p.read_bytes())
    info.pop("UIApplicationSceneManifest", None)
    info["CFBundleDisplayName"] = "Nexus"
    info["CFBundleURLTypes"] = [{
        "CFBundleURLName": "app.nexusvpn.nexus",
        "CFBundleURLSchemes": ["nexus"],
    }]
    p.write_bytes(plistlib.dumps(info))


if (ROOT / "android").is_dir():
    android()
if (ROOT / "windows").is_dir():
    windows()
if (ROOT / "linux").is_dir():
    linux()
if (ROOT / "macos").is_dir():
    macos()
if (ROOT / "ios").is_dir():
    ios()

if errors:
    print("\nОШИБКИ ПАТЧА:\n  " + "\n  ".join(errors))
    sys.exit(1)
print("ok")
