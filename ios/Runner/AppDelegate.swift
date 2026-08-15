import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    deviceChannel = FlutterMethodChannel(
      name: "com.fakegem.historylens/device",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    deviceChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "isTablet":
        result(UIDevice.current.userInterfaceIdiom == .pad)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
