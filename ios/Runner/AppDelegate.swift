import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let sharedFitIntakeBridge = SharedFitIntakeBridge.shared

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    let intakeResult = sharedFitIntakeBridge.publishFiles(
      urls: [url],
      sourcePlatform: "ios",
      storeAsInitial: false
    )
    switch intakeResult {
    case .notHandled:
      return super.application(app, open: url, options: options)
    case .handledSuccess, .handledFailure:
      return true
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    sharedFitIntakeBridge.configure(binaryMessenger: engineBridge.applicationRegistrar.messenger())
  }
}
