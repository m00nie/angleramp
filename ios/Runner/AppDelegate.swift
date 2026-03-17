import UIKit
import Flutter
import CarPlay
import flutter_downloader

@main
@objc class AppDelegate: FlutterAppDelegate {

  /// Shared MethodChannel used by CarPlayController to call into Dart.
  @objc var carPlayChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    FlutterDownloaderPlugin.setPluginRegistrantCallback(registerPlugins)

    // Exclude the documents folder from iCloud backup since we keep songs there.
    try! setExcludeFromiCloudBackup(isExcluded: true)

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // With UIApplicationSceneManifest present, UIKit's UIApplicationMain no longer
    // auto-creates the main UIWindow from UIMainStoryboardFile. We must create it
    // here explicitly so that FlutterSceneDelegate.willConnectToSession finds
    // appDelegate.window non-nil and calls moveRootViewControllerFrom:to:, which
    // attaches the window to the UIWindowScene and calls makeKeyAndVisible.
    // Without this, the phone shows a permanently blank screen.
    if window == nil {
      NSLog("[AppDelegate] window is nil — creating from Main storyboard for UIScene migration")
      let storyboard = UIStoryboard(name: "Main", bundle: nil)
      let rootVC = storyboard.instantiateInitialViewController()!
      let win = UIWindow(frame: UIScreen.main.bounds)
      win.rootViewController = rootVC
      self.window = win
      // Do NOT call makeKeyAndVisible here.
      // FlutterSceneDelegate.moveRootViewControllerFrom:to: creates a fresh
      // UIWindow(windowScene:) and calls makeKeyAndVisible after scene connects.
    } else {
      NSLog("[AppDelegate] window already set: \(String(describing: window))")
    }

    setupCarPlayChannel()

    return result
  }

  // Internal so CarPlaySceneDelegate can call it when the scene connects.
  func setupCarPlayChannel() {
    guard carPlayChannel == nil else {
      NSLog("[CarPlay] setupCarPlayChannel — channel already exists, skipping")
      return
    }
    NSLog("[CarPlay] setupCarPlayChannel — window=\(String(describing: window)) rootVC=\(String(describing: window?.rootViewController))")
    if let controller = window?.rootViewController as? FlutterViewController {
      carPlayChannel = FlutterMethodChannel(
        name: "com.moonie.angleramp/carplay",
        binaryMessenger: controller.binaryMessenger
      )
      NSLog("[CarPlay] Channel created OK")
    } else {
      NSLog("[CarPlay] Channel NOT created — rootVC is not a FlutterViewController")
    }
  }
}


private func setExcludeFromiCloudBackup(isExcluded: Bool) throws {
    var fileOrDirectoryURL = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = isExcluded
    try fileOrDirectoryURL.setResourceValues(values)
}


private func registerPlugins(registry: FlutterPluginRegistry) { 
    if (!registry.hasPlugin("FlutterDownloaderPlugin")) {
       FlutterDownloaderPlugin.register(with: registry.registrar(forPlugin: "FlutterDownloaderPlugin")!)
    }
}
