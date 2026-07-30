import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// MethodChannel used by `ScreenSecurityService`
  /// (lib/services/screen_security_service.dart).
  private var secureChannel: FlutterMethodChannel?

  /// Opaque cover placed over the app while it is in the app switcher, so a
  /// sensitive document never lands in the multitasking snapshot.
  private var privacyCover: UIView?

  /// True while a view-once document (or any other sensitive screen) is showing.
  private var secureModeOn = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    setUpSecureScreenChannel(engineBridge.pluginRegistry)
  }

  // MARK: - Screen capture protection
  //
  // STATED HONESTLY: **iOS provides no public API to block screenshots.**
  // Android's FLAG_SECURE has no counterpart here; anything claiming otherwise
  // relies on private API (App Store rejection) or on tricks that break across
  // iOS releases. So this implements the best protection iOS actually allows:
  //
  //   1. App-switcher privacy - an opaque cover is placed over the window when
  //      the app resigns active, so the document is never captured in the
  //      multitasking snapshot (the one snapshot iOS takes on its own).
  //   2. Screen-recording / AirPlay-mirroring detection - `UIScreen.isCaptured`
  //      is observed live and reported to Flutter, which hides the document
  //      while capture is active.
  //   3. Screenshot detection - `userDidTakeScreenshotNotification` is reported
  //      after the fact, so the app can close the document immediately.
  //
  // The real guarantee on iOS is the one-time token itself: the link is burned
  // the moment the document opens, so a screenshot only ever captures something
  // the recipient was already authorised to see exactly once.

  private func setUpSecureScreenChannel(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry.registrar(forPlugin: "InoSecureScreen")?.messenger() else {
      return
    }
    let channel = FlutterMethodChannel(name: "ino/secure_screen", binaryMessenger: messenger)
    secureChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "enable":
        self.enableSecureMode()
        // false = "this platform cannot actually BLOCK capture". The Dart side
        // uses it to describe the protection truthfully instead of implying
        // iOS screenshots are prevented.
        result(false)
      case "disable":
        self.disableSecureMode()
        result(true)
      case "isCaptured":
        result(UIScreen.main.isCaptured)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func enableSecureMode() {
    guard !secureModeOn else { return }
    secureModeOn = true

    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(onScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification, object: nil)
    center.addObserver(
      self, selector: #selector(onCaptureChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil)
    center.addObserver(
      self, selector: #selector(onWillResignActive),
      name: UIApplication.willResignActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(onDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification, object: nil)

    // Report the current state immediately - the screen may already be mirrored.
    onCaptureChanged()
  }

  private func disableSecureMode() {
    guard secureModeOn else { return }
    secureModeOn = false

    let center = NotificationCenter.default
    center.removeObserver(self, name: UIApplication.userDidTakeScreenshotNotification, object: nil)
    center.removeObserver(self, name: UIScreen.capturedDidChangeNotification, object: nil)
    center.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
    center.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)

    removePrivacyCover()
  }

  @objc private func onScreenshot() {
    secureChannel?.invokeMethod("screenshotTaken", arguments: nil)
  }

  @objc private func onCaptureChanged() {
    secureChannel?.invokeMethod("captureChanged", arguments: UIScreen.main.isCaptured)
  }

  @objc private func onWillResignActive() {
    addPrivacyCover()
  }

  @objc private func onDidBecomeActive() {
    removePrivacyCover()
  }

  private func addPrivacyCover() {
    guard secureModeOn, privacyCover == nil, let window = self.window else { return }
    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = UIColor(red: 0.04, green: 0.07, blue: 0.12, alpha: 1.0)

    let label = UILabel()
    label.text = "🔒 INO"
    label.textColor = .white
    label.font = .systemFont(ofSize: 26, weight: .heavy)
    label.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
    ])

    window.addSubview(cover)
    privacyCover = cover
  }

  private func removePrivacyCover() {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
