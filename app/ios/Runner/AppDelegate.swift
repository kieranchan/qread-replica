import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    AppIconChannel.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "AppIconChannel"))
  }
}

/// 图标广场: `changeAppIcon` with `{iconIndex: n}` switches the home-screen icon to the alternate icon `icon<n>` (asset catalog
/// `Assets.xcassets/icon<n>.appiconset`, listed in ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES); 0 restores the main icon.
enum AppIconChannel {
  static func register(with registrar: FlutterPluginRegistrar?) {
    guard let registrar = registrar else { return }
    let channel = FlutterMethodChannel(name: "newread/app_icon", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "changeAppIcon" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let index = (args?["iconIndex"] as? NSNumber)?.intValue ?? 0
      guard UIApplication.shared.supportsAlternateIcons else {
        result(FlutterError(code: "unsupported", message: "当前设备不支持更换图标", details: nil))
        return
      }
      UIApplication.shared.setAlternateIconName(index > 0 ? "icon\(index)" : nil) { error in
        if let error = error {
          result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
        } else {
          result(true)
        }
      }
    }
  }
}
