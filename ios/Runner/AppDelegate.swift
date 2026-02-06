import Flutter
import UIKit
import SwiftUI
import FamilyControls
import ManagedSettings
import DeviceActivity

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var showAppPicker = false
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(name: "com.jimoon.jamgltime/app_blocker",
                                         binaryMessenger: controller.binaryMessenger)
    
    methodChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      
      if #available(iOS 16.0, *) {
        switch call.method {
        case "requestAuthorization":
          self.requestAuthorization(result: result)
        case "showAppPicker":
          self.showAppPicker(controller: controller, result: result)
        case "blockApps":
          self.blockApps(result: result)
        case "unblockApps":
          self.unblockApps(result: result)
        case "checkAuthStatus":
          result(AuthorizationCenter.shared.authorizationStatus == .approved)
        case "restoreBlockedApps":
          Task {
            await AppBlockerManager.shared.loadBlockedApps()
            result(true)
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      } else {
        result(FlutterError(code: "UNSUPPORTED", message: "iOS 16+ required", details: nil))
      }
    }
    
    // 저장된 차단 앱 복원 로직 제거됨 (Dart에서 호출)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  @available(iOS 16.0, *)
  private func requestAuthorization(result: @escaping FlutterResult) {
    Task {
      do {
        try await AppBlockerManager.shared.requestAuthorization()
        await MainActor.run {
          result(AppBlockerManager.shared.isAuthorized)
        }
      } catch {
        await MainActor.run {
          result(FlutterError(code: "AUTH_ERROR", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
  
  @available(iOS 16.0, *)
  private func showAppPicker(controller: FlutterViewController, result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      // Create a mutable state for binding
      let isPresented = Binding.constant(true)
      
      let swiftUIView = AppPickerView(
        isPresented: isPresented,
        onAppsSelected: { apps, categories, domains in
          controller.dismiss(animated: true)
          result([
            "apps": apps,
            "categories": categories,
            "domains": domains
          ])
        },
        onCancel: {
          controller.dismiss(animated: true)
          result(false)
        }
      )
      
      let hostingController = UIHostingController(rootView: swiftUIView)
      hostingController.modalPresentationStyle = .fullScreen
      controller.present(hostingController, animated: true)
    }
  }
  
  @available(iOS 16.0, *)
  private func blockApps(result: @escaping FlutterResult) {
    AppBlockerManager.shared.blockSelectedApps()
    result(true)
  }
  
  @available(iOS 16.0, *)
  private func unblockApps(result: @escaping FlutterResult) {
    AppBlockerManager.shared.unblockAllApps()
    result(true)
  }
}

