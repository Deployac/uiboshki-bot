import Flutter
import UIKit
import WidgetKit

// Виджеты рабочего стола: канал ru.uiboshki.app/widgets. Приложение кладёт
// снимок дня (save) файлом в общую с виджетом папку App Group, стирает его
// (clear) и спрашивает, стоит ли виджет (installed). Виджет —
// ios/KapibaraWidget/KapibaraWidget.swift.
final class WidgetBridge: NSObject {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ru.uiboshki.app/widgets", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "save":
        let args = call.arguments as? [String: Any]
        WidgetBridge.write((args?["json"] as? String)?.data(using: .utf8))
        result(nil)
      case "clear":
        WidgetBridge.write(nil)
        result(nil)
      case "installed":
        WidgetCenter.shared.getCurrentConfigurations { configs in
          let count = (try? configs.get().count) ?? 0
          DispatchQueue.main.async { result(count) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Файл снимка в папке App Group. AltStore дописывает к id приложения и
  /// группы свой Team ID — поэтому группа берётся от id приложения, а не
  /// вписана намертво; не вышло — как в проекте.
  static func fileURL() -> URL? {
    let app = Bundle.main.bundleIdentifier ?? "ru.uiboshki.app"
    for group in ["group.\(app)", "group.ru.uiboshki.app"] {
      if let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
        return dir.appendingPathComponent("widget.json")
      }
    }
    return nil
  }

  /// nil — стереть: новый дизайн выключен или вышли из аккаунта.
  static func write(_ data: Data?) {
    guard let url = fileURL() else { return }
    if let data = data {
      try? data.write(to: url, options: .atomic)
    } else {
      try? FileManager.default.removeItem(at: url)
    }
    WidgetCenter.shared.reloadAllTimelines()
  }
}
