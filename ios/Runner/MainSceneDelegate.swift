import UIKit
import Flutter

/// UIWindowSceneDelegate for the main application window.
///
/// When UIApplicationSceneManifest is present in Info.plist (required for
/// CarPlay's CPTemplateApplicationSceneSessionRoleApplication), iOS routes
/// the main window through a UIWindowScene even when
/// UIApplicationSupportsMultipleScenes = false.
///
/// FlutterAppDelegate already creates the UIWindow + FlutterViewController
/// in application(_:didFinishLaunchingWithOptions:). This delegate simply
/// connects that pre-existing window to the UIWindowScene iOS provides,
/// making it visible. Without this, the phone shows a blank screen.
class MainSceneDelegate: UIResponder, UIWindowSceneDelegate {

    /// Must be declared; iOS assigns the key window here.
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Grab the window FlutterAppDelegate already built.
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate,
              let appWindow = appDelegate.window else {
            return
        }

        // Attach it to this scene and make it visible.
        appWindow.windowScene = windowScene
        self.window = appWindow
        appWindow.makeKeyAndVisible()
    }
}
