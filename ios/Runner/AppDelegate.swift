import UIKit
import Flutter
import CarPlay
import AVFoundation
import flutter_downloader

@main
@objc class AppDelegate: FlutterAppDelegate {

  /// Shared MethodChannel used by CarPlayController to call into Dart.
  @objc var carPlayChannel: FlutterMethodChannel?

  /// Retained chapter extraction channel — MUST be an instance var so it is
  /// not deallocated after setupChapterChannel() returns (which would silently
  /// remove the method call handler).
  @objc var chapterChannel: FlutterMethodChannel?

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
    setupChapterChannel()

    return result
  }

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

  // Internal so CarPlaySceneDelegate can call it when the scene connects.
  func setupChapterChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("[Chapters] setupChapterChannel skipped — rootVC is not FlutterViewController (type: \(String(describing: window?.rootViewController.self)))")
      return
    }
    NSLog("[Chapters] Creating MethodChannel on binaryMessenger")
    let channel = FlutterMethodChannel(
      name: "com.moonie.angleramp/chapters",
      binaryMessenger: controller.binaryMessenger
    )
    // Retain strongly so the handler is not removed when this method returns.
    chapterChannel = channel
    channel.setMethodCallHandler { (call, result) in
      guard call.method == "extractChapters",
            let urlString = call.arguments as? String,
            let url = URL(string: urlString) else {
        result(FlutterMethodNotImplemented)
        return
      }

      NSLog("[Chapters] Loading availableChapterLocales for URL: \(urlString)")
      let asset = AVURLAsset(url: url, options: [
        AVURLAssetPreferPreciseDurationAndTimingKey: false
      ])

      // Load chapter metadata groups asynchronously.
      // Try "und" (undetermined) locale first, then fall back to any available.
      asset.loadValuesAsynchronously(forKeys: ["availableChapterLocales"]) {
        var loadError: NSError?
        let status = asset.statusOfValue(forKey: "availableChapterLocales", error: &loadError)
        guard status == .loaded else {
          NSLog("[Chapters] Failed to load availableChapterLocales: status=\(status.rawValue) error=\(String(describing: loadError))")
          DispatchQueue.main.async { result([]) }
          return
        }

        // Prefer the user's preferred languages; fall back to all available.
        let preferredLanguages = Locale.preferredLanguages + ["und", ""]
        NSLog("[Chapters] availableChapterLocales: \(asset.availableChapterLocales)")
        let groups = asset.chapterMetadataGroups(bestMatchingPreferredLanguages: preferredLanguages)
        NSLog("[Chapters] Found \(groups.count) chapter groups")

        var chapters: [[String: Any]] = []
        for group in groups {
          let startMs = Int64(CMTimeGetSeconds(group.timeRange.start) * 1000)
          // startPositionTicks = 100-nanosecond units (10^7 per second)
          let ticks = startMs * 10000
          var title = ""
          for item in group.items {
            if item.commonKey == AVMetadataKey.commonKeyTitle,
               let t = item.value as? String {
              title = t
              break
            }
          }
          chapters.append(["ticks": ticks, "name": title])
        }

        NSLog("[Chapters] Returning \(chapters.count) chapters")
        DispatchQueue.main.async { result(chapters) }
      }
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
