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
    setUpUpiAppsChannel(engineBridge.pluginRegistry)
  }

  // MARK: - Payment apps for scanned UPI QRs
  //
  // STATED HONESTLY: **iOS cannot enumerate installed apps.** Android asks the
  // package manager which apps handle `upi://pay` and gets the user's real list
  // with icons; there is no equivalent here. The only thing iOS permits is
  // probing a FIXED set of URL schemes that the app declares up-front in
  // `LSApplicationQueriesSchemes` (Info.plist).
  //
  // So this list is necessarily hard-coded and necessarily incomplete: a UPI app
  // not named in Info.plist is invisible to us, however installed it is. Icons
  // are unavailable too, so the Flutter picker draws lettered avatars instead.
  // When nothing is found the Dart side falls back to handing the URI straight
  // to iOS, which opens whatever is registered for it.

  /// The payment apps iOS lets us probe for. Must stay in sync with
  /// `LSApplicationQueriesSchemes` in Info.plist - a scheme missing there always
  /// reports "not installed", no matter what the user actually has.
  private static let upiSchemes: [(id: String, name: String)] = [
    ("gpay", "Google Pay"),
    ("tez", "Google Pay"),
    ("phonepe", "PhonePe"),
    ("paytmmp", "Paytm"),
    ("bhim", "BHIM"),
  ]

  private func setUpUpiAppsChannel(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry.registrar(forPlugin: "InoUpiApps")?.messenger() else {
      return
    }
    let channel = FlutterMethodChannel(name: "ino/upi_apps", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "list":
        result(Self.installedUpiApps())
      case "launch":
        guard let args = call.arguments as? [String: Any],
              let uri = args["uri"] as? String else {
          result(false)
          return
        }
        let id = args["id"] as? String ?? ""
        // iOS has no `setPackage` equivalent, so targeting a specific app means
        // rewriting the `upi://` URI into THAT app's own scheme. If the rewrite
        // can't be opened we fall back to the plain `upi://` URI rather than
        // dead-ending, and iOS routes it wherever it likes.
        let targeted = Self.appSpecificURL(id: id, upiUri: uri)
        Self.open(targeted, fallback: URL(string: uri), result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Rewrites a canonical `upi://pay?…` URI into the chosen app's own scheme,
  /// keeping the query (the payee, amount and note) exactly as-is. Returns nil
  /// for an app we have no template for, so the caller uses the plain URI.
  private static func appSpecificURL(id: String, upiUri: String) -> URL? {
    guard let query = URLComponents(string: upiUri)?.query, !query.isEmpty else {
      return nil
    }
    let prefix: String
    switch id {
    case "gpay", "tez": prefix = "tez://upi/pay"
    case "phonepe": prefix = "phonepe://pay"
    case "paytmmp": prefix = "paytmmp://pay"
    case "bhim": prefix = "bhim://pay"
    default: return nil
    }
    return URL(string: "\(prefix)?\(query)")
  }

  /// Opens [url], falling back to [fallback] when it can't be opened.
  private static func open(
    _ url: URL?, fallback: URL?, result: @escaping FlutterResult
  ) {
    if let url = url, UIApplication.shared.canOpenURL(url) {
      UIApplication.shared.open(url, options: [:]) { ok in
        if ok { result(true) } else { Self.open(nil, fallback: fallback, result: result) }
      }
      return
    }
    guard let fallback = fallback else {
      result(false)
      return
    }
    UIApplication.shared.open(fallback, options: [:]) { ok in result(ok) }
  }

  private static func installedUpiApps() -> [[String: Any]] {
    var seenNames = Set<String>()
    var apps: [[String: Any]] = []
    for entry in upiSchemes {
      guard let probe = URL(string: "\(entry.id)://"),
            UIApplication.shared.canOpenURL(probe) else { continue }
      // Google Pay answers to two schemes; the user should see one entry.
      guard seenNames.insert(entry.name).inserted else { continue }
      // No "icon" key at all rather than an explicit nil - a nil inside a
      // dictionary does not survive the Flutter standard codec cleanly, and the
      // Dart side already treats a missing icon as "draw the lettered avatar".
      apps.append(["id": entry.id, "name": entry.name])
    }
    return apps
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
