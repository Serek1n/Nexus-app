import Flutter
import UIKit

/// Nexus для iOS: классический AppDelegate (без сцен) — регистрация
/// плагинов, канал VPN и ссылки nexus://.
@main
@objc class AppDelegate: FlutterAppDelegate {
  private var links: FlutterMethodChannel?
  private var pending: [String] = []
  private var ready = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let r = self.registrar(forPlugin: "NexusNative") {
      NexusVpn.shared.attach(r.messenger())
      let ch = FlutterMethodChannel(name: "nexus/links", binaryMessenger: r.messenger())
      ch.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { return }
        if call.method == "initialLinks" {
          self.ready = true
          result(self.pending)
          self.pending = []
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      links = ch
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication, open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if url.scheme?.lowercased() == "nexus" {
      let s = url.absoluteString
      if s.count <= 8192 {
        if ready, let ch = links {
          ch.invokeMethod("link", arguments: s)
        } else {
          pending.append(s)
        }
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
