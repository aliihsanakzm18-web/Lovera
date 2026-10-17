import Flutter
import UIKit
import WidgetKit

enum LoveraNativeWidgetHelper {
  static func syncVendorIdAndReloadWidgets() {
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }

    let stdDefaults = UserDefaults.standard
    guard let savedUid = stdDefaults.string(forKey: "flutter.saved_uid"),
          !savedUid.isEmpty,
          let vendorId = UIDevice.current.identifierForVendor?.uuidString,
          !vendorId.isEmpty else {
      return
    }

    // App Group varsa oraya da kopyala
    if let groupDefaults = UserDefaults(suiteName: "group.com.lovera.app.lovera") {
      groupDefaults.set(savedUid, forKey: "saved_uid")
      if let pUid = stdDefaults.string(forKey: "flutter.saved_partner_uid") {
        groupDefaults.set(pUid, forKey: "saved_partner_uid")
      }
      if let cId = stdDefaults.string(forKey: "flutter.saved_couple_id") {
        groupDefaults.set(cId, forKey: "saved_couple_id")
      }
    }

    // Firestore'daki kullanıcı belgesine iosVendorId yaz (Widget'ın cihazı otomatik tanıması için)
    let urlStr = "https://firestore.googleapis.com/v1/projects/sevgili-app-fb6f4/databases/(default)/documents/users/\(savedUid)?updateMask.fieldPaths=iosVendorId"
    guard let url = URL(string: urlStr) else { return }

    var req = URLRequest(url: url)
    req.httpMethod = "PATCH"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: Any] = [
      "fields": [
        "iosVendorId": ["stringValue": vendorId]
      ]
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    URLSession.shared.dataTask(with: req) { _, _, _ in
      if #available(iOS 14.0, *) {
        WidgetCenter.shared.reloadAllTimelines()
      }
    }.resume()
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    LoveraNativeWidgetHelper.syncVendorIdAndReloadWidgets()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable : Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
    super.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
