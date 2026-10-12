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
    // явный Optional: собирается, вернёт ли SDK registrar с ! или без
    let registrar: FlutterPluginRegistrar? = engineBridge.pluginRegistry.registrar(forPlugin: "AppIconPlugin")
    if let registrar = registrar {
      AppIconPlugin.register(with: registrar)
    }
    // виджеты рабочего стола (WidgetBridge.swift)
    let widgets: FlutterPluginRegistrar? = engineBridge.pluginRegistry.registrar(forPlugin: "WidgetBridge")
    if let widgets = widgets {
      WidgetBridge.register(with: widgets)
    }
  }
}

/// Иконка на выбор (5.79): альтернативные иконки — Icon<Имя>.appiconset в
/// Assets.xcassets (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES в проекте).
/// Из Dart приходит имя AppIcon (depth, sunset…), nil или "classic" — основная.
class AppIconPlugin: NSObject, FlutterPlugin {
  static let icons = ["depth", "indigo", "terracotta", "page", "sunset", "library"]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "uiboshki/icon", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AppIconPlugin(), channel: channel)
  }

  private static func assetName(_ name: String) -> String {
    return "Icon" + name.prefix(1).uppercased() + String(name.dropFirst())
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let app = UIApplication.shared
    switch call.method {
    case "supported":
      result(app.supportsAlternateIcons)
    case "getIcon":
      let current = app.alternateIconName
      result(AppIconPlugin.icons.first { AppIconPlugin.assetName($0) == current })
    case "setIcon":
      let name = call.arguments as? String
      var target: String? = nil
      if let name = name, name != "classic" {
        guard AppIconPlugin.icons.contains(name) else {
          result(FlutterError(code: "unknown", message: "Нет такой иконки: \(name)", details: nil))
          return
        }
        target = AppIconPlugin.assetName(name)
      }
      guard app.supportsAlternateIcons else {
        result(nil)
        return
      }
      if app.alternateIconName == target {
        result(nil)
        return
      }
      app.setAlternateIconName(target) { error in
        // ответ во Flutter — только с главного потока
        DispatchQueue.main.async {
          if let error = error {
            result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
          } else {
            result(nil)
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
