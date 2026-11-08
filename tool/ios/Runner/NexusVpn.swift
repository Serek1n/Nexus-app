import Flutter
import Security
import LibXray
import NetworkExtension

/// Nexus для iOS: управление VPN-профилем (NETunnelProviderManager) и
/// вызовы libXray в самом приложении (пинг, версия). Канал nexus/ios_vpn.
final class NexusVpn: NSObject {
  static let shared = NexusVpn()
  static let tunnelId = "app.nexusvpn.nexus.tunnel"
  static let appGroup = "group.app.nexusvpn.nexus"

  private var channel: FlutterMethodChannel?
  private var manager: NETunnelProviderManager?
  private var observer: NSObjectProtocol?

  func attach(_ messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "nexus/ios_vpn", binaryMessenger: messenger)
    ch.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }
    channel = ch
    load { _ in }
  }

  private func load(_ done: @escaping (NETunnelProviderManager?) -> Void) {
    NETunnelProviderManager.loadAllFromPreferences { [weak self] list, _ in
      let m = list?.first {
        ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
          == NexusVpn.tunnelId
      }
      DispatchQueue.main.async {
        self?.watch(m)
        done(m)
      }
    }
  }

  private func watch(_ m: NETunnelProviderManager?) {
    manager = m
    if let o = observer { NotificationCenter.default.removeObserver(o) }
    observer = nil
    guard let m = m else { return }
    observer = NotificationCenter.default.addObserver(
      forName: .NEVPNStatusDidChange, object: m.connection, queue: .main
    ) { [weak self] _ in
      guard let self = self, let m = self.manager else { return }
      self.channel?.invokeMethod("status", arguments: Self.name(m.connection.status))
      if m.connection.status == .disconnected, #available(iOS 16.0, *) {
        m.connection.fetchLastDisconnectError { err in
          guard let err = err else { return }
          DispatchQueue.main.async {
            self.channel?.invokeMethod("error", arguments: err.localizedDescription)
          }
        }
      }
    }
  }

  static func name(_ s: NEVPNStatus) -> String {
    switch s {
    case .connected: return "connected"
    case .connecting: return "connecting"
    case .reasserting: return "reasserting"
    case .disconnecting: return "disconnecting"
    case .invalid: return "invalid"
    default: return "disconnected"
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "status":
      if manager != nil {
        result(Self.name(manager!.connection.status))
      } else {
        load { m in result(m.map { Self.name($0.connection.status) } ?? "disconnected") }
      }
    case "start":
      guard let config = args?["config"] as? String else {
        result(FlutterError(code: "args", message: "no config", details: nil))
        return
      }
      start(config, onDemand: args?["onDemand"] as? Bool ?? false, result)
    case "stop":
      // Сначала выключаем автоподключение — иначе iOS сразу поднимет VPN снова.
      guard let m = manager else {
        result(nil)
        return
      }
      if m.isOnDemandEnabled {
        m.isOnDemandEnabled = false
        m.saveToPreferences { _ in
          DispatchQueue.main.async {
            m.connection.stopVPNTunnel()
            result(nil)
          }
        }
      } else {
        m.connection.stopVPNTunnel()
        result(nil)
      }
    case "probe":
      guard let session = manager?.connection as? NETunnelProviderSession,
        session.status == .connected
      else {
        result(nil)
        return
      }
      do {
        try session.sendProviderMessage(Data("probe".utf8)) { data in
          DispatchQueue.main.async {
            result(data.flatMap { String(data: $0, encoding: .utf8) })
          }
        }
      } catch {
        result(nil)
      }
    case "pingBatch":
      guard let req = args?["request"] as? String,
        let payload = try? JSONSerialization.jsonObject(with: Data(req.utf8))
      else {
        result(nil)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let r = Self.invoke("pingBatch", payload)
        DispatchQueue.main.async { result(r) }
      }
    case "version":
      let r = Self.invoke("xrayVersion", nil)
      let j = (try? JSONSerialization.jsonObject(with: Data(r.utf8))) as? [String: Any]
      result(((j?["data"] as? [String: Any])?["version"] as? String) ?? "—")
    case "logs":
      result(Self.logTail())
    case "forget":
      // «Сбросить всё»: последний конфиг туннеля и журнал ядра.
      if let dir = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Self.appGroup)
      {
        for name in ["tunnel.json", "xray.log"] {
          try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(_ config: String, onDemand: Bool, _ result: @escaping FlutterResult) {
    let m = manager ?? NETunnelProviderManager()
    let p = (m.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
    p.providerBundleIdentifier = Self.tunnelId
    p.serverAddress = "Nexus"
    p.disconnectOnSleep = false
    m.protocolConfiguration = p
    m.localizedDescription = "Nexus"
    m.isEnabled = true
    // «Держать соединение»: если VPN оборвался (iOS выгрузила расширение,
    // сменилась сеть), система поднимет его сама. Отключение из Nexus или
    // из Настроек iOS выключает это правило.
    m.onDemandRules = onDemand ? [NEOnDemandRuleConnect()] : nil
    m.isOnDemandEnabled = onDemand
    // Первое сохранение показывает системный запрос «Добавить VPN».
    m.saveToPreferences { [weak self] err in
      if let err = err as NSError? {
        let denied = err.domain == NEVPNErrorDomain
          && err.code == NEVPNError.configurationReadWriteFailed.rawValue
        DispatchQueue.main.async {
          result(FlutterError(
            code: denied ? "denied" : "save", message: err.localizedDescription, details: nil))
        }
        return
      }
      m.loadFromPreferences { err in
        DispatchQueue.main.async {
          if let err = err {
            result(FlutterError(code: "load", message: err.localizedDescription, details: nil))
            return
          }
          self?.watch(m)
          do {
            // Конфиг с ключами — только в параметрах запуска, без записи на диск.
            try m.connection.startVPNTunnel(options: ["config": config as NSString])
            result(nil)
          } catch {
            result(FlutterError(code: "start", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  static func invoke(_ method: String, _ payload: Any?) -> String {
    var req: [String: Any] = ["apiVersion": 3, "method": method]
    if let p = payload { req["payload"] = p }
    guard let d = try? JSONSerialization.data(withJSONObject: req),
      let s = String(data: d, encoding: .utf8)
    else { return "{}" }
    return LibXrayInvoke(s)
  }

  static func logTail() -> [String] {
    guard
      let url = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
        .appendingPathComponent("xray.log"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return [] }
    return Array(text.split(separator: "\n").suffix(300).map(String.init))
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
          result(FlutterError(code: "keychain", message: "\(st)", details: nil))
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
