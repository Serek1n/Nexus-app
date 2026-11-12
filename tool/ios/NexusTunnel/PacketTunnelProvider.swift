import Darwin
import LibXray
import NetworkExtension

/// Nexus для iOS: VPN-расширение. Система отдаёт туннель (utun), а Xray
/// (libXray) работает прямо на нём — дескриптор туннеля передаётся ядру
/// через env конфига («xray.tun.fd»). Конфиг приходит из приложения при
/// каждом подключении; последний сохраняется в общей папке Nexus (с защитой iOS), чтобы
/// VPN поднимался и без приложения — переключателем в Настройках iOS и
/// при автоподключении («Держать соединение»).
final class PacketTunnelProvider: NEPacketTunnelProvider {
  static let appGroup = "group.app.nexusvpn.nexus"

  private var logURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)?
      .appendingPathComponent("xray.log")
  }

  /// Гео-базы лежат в самом приложении Nexus: …/Nexus.app/PlugIns/NexusTunnel.appex.
  private var assetDir: String {
    Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().path
  }

  override func startTunnel(
    options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void
  ) {
    let fresh = options?["config"] as? String
    guard let text = fresh ?? Self.savedConfig(),
      let data = text.data(using: .utf8),
      var cfg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
      completionHandler(Self.err("Подключитесь из приложения Nexus"))
      return
    }
    if let f = fresh { Self.saveConfig(f) }
    probe = Self.probeAddress(cfg)
    let dns = Self.dnsServer(cfg)
    let s = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
    let v4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
    v4.includedRoutes = [NEIPv4Route.default()]
    s.ipv4Settings = v4
    let v6 = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [126])
    v6.includedRoutes = [NEIPv6Route.default()]
    s.ipv6Settings = v6
    // Все DNS-запросы — в туннель; там их забирает встроенный DNS ядра.
    let d = NEDNSSettings(servers: [dns])
    d.matchDomains = [""]
    s.dnsSettings = d
    s.mtu = 1400

    setTunnelNetworkSettings(s) { [weak self] error in
      guard let self = self else { return }
      if let error = error {
        completionHandler(error)
        return
      }
      guard let fd = self.tunnelFd else {
        completionHandler(Self.err("Не найден туннель iOS"))
        return
      }
      var env = (cfg["env"] as? [String: String]) ?? [:]
      env["xray.tun.fd"] = String(fd)
      env["xray.location.asset"] = self.assetDir
      cfg["env"] = env
      if let log = self.logURL {
        try? Data().write(to: log)
        var l = (cfg["log"] as? [String: Any]) ?? [:]
        l["error"] = log.path
        cfg["log"] = l
      }
      guard let out = try? JSONSerialization.data(withJSONObject: cfg),
        let json = String(data: out, encoding: .utf8)
      else {
        completionHandler(Self.err("Неверный конфиг"))
        return
      }
      if let e = Self.invoke("runXray", ["xrayJson": json]) {
        completionHandler(Self.err(e))
      } else {
        completionHandler(nil)
      }
    }
  }

  /// Адрес служебного входа для проверок и статистики («логин:пароль@
  /// 127.0.0.1:порт»): приложение спрашивает его, если открылось, когда
  /// VPN уже работал.
  private var probe: String?

  override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
    if String(data: messageData, encoding: .utf8) == "probe" {
      completionHandler?(probe.flatMap { $0.data(using: .utf8) })
    } else {
      completionHandler?(nil)
    }
  }

  static func probeAddress(_ cfg: [String: Any]) -> String? {
    for case let ib as [String: Any] in (cfg["inbounds"] as? [Any] ?? []) {
      guard ib["tag"] as? String == "nexus-probe", let port = ib["port"] as? Int,
        let acc = ((ib["settings"] as? [String: Any])?["accounts"] as? [[String: Any]])?.first,
        let u = acc["user"] as? String, let p = acc["pass"] as? String
      else { continue }
      return "\(u):\(p)@127.0.0.1:\(port)"
    }
    return nil
  }

  // ── последний конфиг: файл в общей папке Nexus, защита iOS «до первой
  // разблокировки». Удаляется вместе с приложением и кнопкой «Сбросить всё».

  private static var savedURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appendingPathComponent("tunnel.json")
  }

  static func saveConfig(_ text: String) {
    guard let url = savedURL else { return }
    try? Data(text.utf8).write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  static func savedConfig() -> String? {
    guard let url = savedURL, let d = try? Data(contentsOf: url) else { return nil }
    return String(data: d, encoding: .utf8)
  }

  override func stopTunnel(
    with reason: NEProviderStopReason, completionHandler: @escaping () -> Void
  ) {
    _ = Self.invoke("stopXray", nil)
    completionHandler()
  }

  /// Дескриптор utun, который система выдала расширению.
  private var tunnelFd: Int32? {
    var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
    for fd: Int32 in 0...1024 {
      var len = socklen_t(buf.count)
      // SYSPROTO_CONTROL = 2, UTUN_OPT_IFNAME = 2
      if getsockopt(fd, 2, 2, &buf, &len) == 0,
        String(cString: buf).hasPrefix("utun")
      {
        return fd
      }
    }
    return packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32
  }

  static func dnsServer(_ cfg: [String: Any]) -> String {
    let servers = (cfg["dns"] as? [String: Any])?["servers"] as? [Any] ?? []
    for case let s as String in servers where !s.contains("://") {
      return s
    }
    return "1.1.1.1"
  }

  /// Вызов libXray. nil — успех, иначе текст ошибки.
  static func invoke(_ method: String, _ payload: [String: Any]?) -> String? {
    var req: [String: Any] = ["apiVersion": 3, "method": method]
    if let p = payload { req["payload"] = p }
    guard let d = try? JSONSerialization.data(withJSONObject: req),
      let s = String(data: d, encoding: .utf8)
    else { return "bad request" }
    let resp = LibXrayInvoke(s)
    guard let rd = resp.data(using: .utf8),
      let j = (try? JSONSerialization.jsonObject(with: rd)) as? [String: Any]
    else { return "bad response" }
    if j["success"] as? Bool == true { return nil }
    return (j["error"] as? String) ?? "error"
  }

  static func err(_ text: String) -> NSError {
    NSError(domain: "Nexus", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
  }
}
