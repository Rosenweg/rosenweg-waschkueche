import Flutter
import UIKit
import UserNotifications
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // rosenweg_basis HintergrundAbfrage: Erinnerungen der Waschkueche abgleichen
    WorkmanagerPlugin.setPluginRegistrantCallback { GeneratedPluginRegistrant.register(with: $0) }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "ch.rosenweg4303.waschkueche.abfrage", earliestBeginInSeconds: 900)
    // Benachrichtigungen auch zeigen, wenn die App vorne ist
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
