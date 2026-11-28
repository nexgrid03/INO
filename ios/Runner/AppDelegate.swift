import Flutter
import UIKit
import Photos
import VisionKit
import Vision
import CoreImage
import CoreVideo
import ImageIO

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
    setUpMediaSaverChannel(engineBridge.pluginRegistry)
    setUpDocumentScannerChannel(engineBridge.pluginRegistry)
    setUpVisionScannerChannel(engineBridge.pluginRegistry)
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

  // MARK: - Media saver (saves exported QR codes / images to Photos)

  private func setUpMediaSaverChannel(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry.registrar(forPlugin: "InoMediaSaver")?.messenger() else {
      return
    }
    let channel = FlutterMethodChannel(name: "ino/media_saver", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "saveImageToGallery":
        guard let args = call.arguments as? [String: Any],
              let flutterData = args["bytes"] as? FlutterStandardTypedData else {
          result(false)
          return
        }
        let data = flutterData.data
        guard let image = UIImage(data: data) else {
          result(false)
          return
        }

        if #available(iOS 14, *) {
          PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
              DispatchQueue.main.async { result(false) }
              return
            }
            PHPhotoLibrary.shared().performChanges({
              let request = PHAssetCreationRequest.forAsset()
              request.addResource(with: .photo, data: data, options: nil)
            }) { success, _ in
              DispatchQueue.main.async { result(success) }
            }
          }
        } else {
          UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
          result(true)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Native Document Scanner (VisionKit)
  //
  // Apple's system document scanner (VNDocumentCameraViewController). Provides
  // live ML-based boundary detection, edge snapping, perspective correction,
  // auto-capture and multi-page scanning on iOS - exactly matching Google ML Kit's
  // document scanner on Android.

  private var activeDocumentScannerSession: Any?
  private var visionScannerEngine: InoVisionDocumentEngine?

  private func setUpVisionScannerChannel(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry.registrar(forPlugin: "InoVisionScanner")?.messenger() else {
      return
    }
    let engine = InoVisionDocumentEngine()
    self.visionScannerEngine = engine
    let channel = FlutterMethodChannel(
      name: "ino/vision_document_scanner",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "detectFrame":
        guard let args = call.arguments as? [String: Any],
              let bytes = args["bytes"] as? FlutterStandardTypedData,
              let width = args["width"] as? Int,
              let height = args["height"] as? Int,
              let bytesPerRow = args["bytesPerRow"] as? Int,
              let rotation = args["rotation"] as? Int else {
          result(nil)
          return
        }
        engine.detectFrame(
          bytes: bytes.data,
          width: width,
          height: height,
          bytesPerRow: bytesPerRow,
          rotation: rotation,
          result: result
        )

      case "processCapture":
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "path required", details: nil))
          return
        }
        let maxDimension = args["maxDimension"] as? Int ?? 2400
        let fallbackCorners = args["fallbackCorners"] as? [Double]
        engine.processCapture(
          path: path,
          fallbackCorners: fallbackCorners,
          maxDimension: maxDimension,
          result: result
        )

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setUpDocumentScannerChannel(_ registry: FlutterPluginRegistry) {
    guard let messenger = registry.registrar(forPlugin: "InoDocumentScanner")?.messenger() else {
      return
    }
    let channel = FlutterMethodChannel(name: "ino/document_scanner", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate deallocated", details: nil))
        return
      }
      switch call.method {
      case "isSupported":
        if #available(iOS 13.0, *) {
          result(VNDocumentCameraViewController.isSupported)
        } else {
          result(false)
        }
      case "scanPages":
        if #available(iOS 13.0, *) {
          guard VNDocumentCameraViewController.isSupported else {
            result(FlutterError(code: "UNSUPPORTED", message: "VisionKit document scanner not supported on this device", details: nil))
            return
          }
          guard let presenter = Self.topViewController(base: self.window?.rootViewController) else {
            result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "No view controller to present scanner", details: nil))
            return
          }
          let scanner = VNDocumentCameraViewController()
          let session = InoDocumentScannerSession(scanner: scanner, result: result) { [weak self] in
            self?.activeDocumentScannerSession = nil
          }
          self.activeDocumentScannerSession = session
          scanner.delegate = session
          presenter.present(scanner, animated: true)
        } else {
          result(FlutterError(code: "UNSUPPORTED", message: "iOS 13.0+ required for VisionKit", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func topViewController(base: UIViewController?) -> UIViewController? {
    if let nav = base as? UINavigationController {
      return topViewController(base: nav.visibleViewController)
    }
    if let tab = base as? UITabBarController {
      return topViewController(base: tab.selectedViewController)
    }
    if let presented = base?.presentedViewController {
      return topViewController(base: presented)
    }
    return base
  }
}

@available(iOS 13.0, *)
private class InoDocumentScannerSession: NSObject, VNDocumentCameraViewControllerDelegate {
  private let scanner: VNDocumentCameraViewController
  private var resultCallback: FlutterResult?
  private let onComplete: () -> Void

  init(scanner: VNDocumentCameraViewController, result: @escaping FlutterResult, onComplete: @escaping () -> Void) {
    self.scanner = scanner
    self.resultCallback = result
    self.onComplete = onComplete
    super.init()
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
    controller.dismiss(animated: true) { [weak self] in
      guard let self = self, let result = self.resultCallback else { return }
      self.resultCallback = nil
      defer { self.onComplete() }

      DispatchQueue.global(qos: .userInitiated).async {
        var paths: [String] = []
        let tempDir = FileManager.default.temporaryDirectory
        for i in 0..<scan.pageCount {
          let image = scan.imageOfPage(at: i)
          if let data = image.jpegData(compressionQuality: 0.92) {
            let fileName = "ino_scan_\(UUID().uuidString).jpg"
            let fileURL = tempDir.appendingPathComponent(fileName)
            do {
              try data.write(to: fileURL)
              paths.append(fileURL.path)
            } catch {
              // Ignore single write error and continue with remaining pages
            }
          }
        }
        DispatchQueue.main.async {
          result(paths)
        }
      }
    }
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true) { [weak self] in
      guard let self = self, let result = self.resultCallback else { return }
      self.resultCallback = nil
      self.onComplete()
      result(FlutterError(code: "CANCELLED", message: "User cancelled document scanner", details: nil))
    }
  }

  func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
    controller.dismiss(animated: true) { [weak self] in
      guard let self = self, let result = self.resultCallback else { return }
      self.resultCallback = nil
      self.onComplete()
      result(FlutterError(code: "SCAN_FAILED", message: error.localizedDescription, details: nil))
    }
  }
}

// MARK: - Native iOS Vision Document Engine (VNDetectDocumentSegmentationRequest + CIPerspectiveCorrection)

private final class InoVisionDocumentEngine {
  private let stateQueue = DispatchQueue(label: "com.ino.vision_scanner.state")
  private let workQueue = DispatchQueue(
    label: "com.ino.vision_scanner.work",
    qos: .userInitiated
  )
  private var frameBusy = false
  private let downscaler = InoPixelBufferDownscaler()
  private let renderContext = CIContext(options: [.useSoftwareRenderer: false])
  private let frameMaxLongSide = 640

  private struct NormalizedQuad {
    let tl: CGPoint
    let tr: CGPoint
    let br: CGPoint
    let bl: CGPoint
    let confidence: Double
    let source: String
  }

  func detectFrame(
    bytes: Data,
    width: Int,
    height: Int,
    bytesPerRow: Int,
    rotation: Int,
    result: @escaping FlutterResult
  ) {
    guard acquireSlot() else {
      result(nil)
      return
    }
    let expected = bytesPerRow * height
    guard width > 0, height > 0, bytesPerRow >= width * 4, bytes.count >= expected else {
      releaseSlot()
      result(nil)
      return
    }

    workQueue.async { [weak self] in
      autoreleasepool {
        guard let self = self else {
          DispatchQueue.main.async { result(nil) }
          return
        }
        defer { self.releaseSlot() }

        guard let buffer = self.downscaler.downscale(
          bytes: bytes,
          width: width,
          height: height,
          bytesPerRow: bytesPerRow,
          maxLongSide: self.frameMaxLongSide
        ) else {
          DispatchQueue.main.async { result(nil) }
          return
        }

        let metrics = Self.computeFrameQuality(buffer: buffer)
        let orientation = Self.cgOrientation(fromRotation: rotation)
        let handler = VNImageRequestHandler(
          cvPixelBuffer: buffer,
          orientation: orientation,
          options: [:]
        )

        guard let quad = Self.detectDocument(using: handler, strictForLive: true) else {
          DispatchQueue.main.async { result(nil) }
          return
        }

        let payload: [String: Any] = [
          "topLeftX": Double(quad.tl.x),
          "topLeftY": Double(quad.tl.y),
          "topRightX": Double(quad.tr.x),
          "topRightY": Double(quad.tr.y),
          "bottomRightX": Double(quad.br.x),
          "bottomRightY": Double(quad.br.y),
          "bottomLeftX": Double(quad.bl.x),
          "bottomLeftY": Double(quad.bl.y),
          "confidence": quad.confidence,
          "sharpness": metrics.sharpness,
          "brightness": metrics.brightness,
          "source": quad.source,
        ]
        DispatchQueue.main.async { result(payload) }
      }
    }
  }

  func processCapture(
    path: String,
    fallbackCorners: [Double]?,
    maxDimension: Int,
    result: @escaping FlutterResult
  ) {
    workQueue.async { [weak self] in
      autoreleasepool {
        guard let self = self else {
          DispatchQueue.main.async { result(nil) }
          return
        }
        let fileURL = URL(fileURLWithPath: path)
        guard let orientedImage = CIImage(
          contentsOf: fileURL,
          options: [.applyOrientationProperty: true]
        ) else {
          DispatchQueue.main.async { result(nil) }
          return
        }

        let extent = orientedImage.extent
        guard extent.width > 16, extent.height > 16 else {
          DispatchQueue.main.async { result(nil) }
          return
        }

        // Run Apple's ML document segmentation directly on the EXIF-upright
        // full-res capture so preview-vs-still aspect differences never skew crops.
        let handler = VNImageRequestHandler(
          ciImage: orientedImage,
          orientation: .up,
          options: [:]
        )
        var chosenQuad = Self.detectDocument(using: handler, strictForLive: false)

        if chosenQuad == nil, let fb = fallbackCorners, fb.count == 8 {
          let pts = [
            CGPoint(x: fb[0], y: fb[1]),
            CGPoint(x: fb[2], y: fb[3]),
            CGPoint(x: fb[4], y: fb[5]),
            CGPoint(x: fb[6], y: fb[7]),
          ]
          if let validated = Self.validateAndOrder(pts, confidence: 0.7, source: "fallback") {
            chosenQuad = validated
          }
        }

        var workingImage = orientedImage
        var didCrop = false

        if let quad = chosenQuad,
           let filter = CIFilter(name: "CIPerspectiveCorrection") {
          func toCI(_ p: CGPoint) -> CIVector {
            let cx = extent.origin.x + p.x * extent.width
            let cy = extent.origin.y + (1.0 - p.y) * extent.height
            return CIVector(x: cx, y: cy)
          }
          filter.setValue(orientedImage, forKey: kCIInputImageKey)
          filter.setValue(toCI(quad.tl), forKey: "inputTopLeft")
          filter.setValue(toCI(quad.tr), forKey: "inputTopRight")
          filter.setValue(toCI(quad.br), forKey: "inputBottomRight")
          filter.setValue(toCI(quad.bl), forKey: "inputBottomLeft")
          if let corrected = filter.outputImage,
             corrected.extent.width > 16,
             corrected.extent.height > 16 {
            workingImage = corrected
            didCrop = true
          }
        }

        // Cap output resolution with high-quality Lanczos resampling when larger than maxDimension.
        let workExtent = workingImage.extent
        let longSide = max(workExtent.width, workExtent.height)
        if maxDimension > 0 && longSide > CGFloat(maxDimension) {
          let scale = CGFloat(maxDimension) / longSide
          if let lanczos = CIFilter(name: "CILanczosScaleTransform") {
            lanczos.setValue(workingImage, forKey: kCIInputImageKey)
            lanczos.setValue(scale, forKey: kCIInputScaleKey)
            lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
            if let scaled = lanczos.outputImage {
              workingImage = scaled
            }
          } else {
            workingImage = workingImage.transformed(
              by: CGAffineTransform(scaleX: scale, y: scale)
            )
          }
        }

        // Subtle luminance sharpen so rectified text stays crisp without halos.
        if let sharpen = CIFilter(name: "CISharpenLuminance") {
          sharpen.setValue(workingImage, forKey: kCIInputImageKey)
          sharpen.setValue(0.32, forKey: kCIInputSharpnessKey)
          if let sharpened = sharpen.outputImage {
            workingImage = sharpened
          }
        }

        guard let cgImage = self.renderContext.createCGImage(
          workingImage,
          from: workingImage.extent
        ) else {
          DispatchQueue.main.async { result(nil) }
          return
        }

        let uiImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.95) else {
          DispatchQueue.main.async { result(nil) }
          return
        }

        let outURL = FileManager.default.temporaryDirectory
          .appendingPathComponent("ino_ios_scan_\(UUID().uuidString).jpg")
        do {
          try jpegData.write(to: outURL, options: .atomic)
          let payload: [String: Any] = [
            "path": outURL.path,
            "cropped": didCrop,
            "width": cgImage.width,
            "height": cgImage.height,
          ]
          DispatchQueue.main.async { result(payload) }
        } catch {
          DispatchQueue.main.async { result(nil) }
        }
      }
    }
  }

  private static func detectDocument(
    using handler: VNImageRequestHandler,
    strictForLive: Bool
  ) -> NormalizedQuad? {
    // 1) Primary: iOS 15+ ML Document Segmentation (same engine as Apple Notes / VisionKit).
    if #available(iOS 15.0, *) {
      let segRequest = VNDetectDocumentSegmentationRequest()
      do {
        try handler.perform([segRequest])
        if let obs = segRequest.results?.first,
           let quad = quadFromObservation(
             obs,
             source: "segmentation",
             minConfidence: strictForLive ? 0.48 : 0.40
           ) {
          return quad
        }
      } catch {
        // Fall through to strict rectangle detection.
      }
    }

    // 2) Secondary: strict rectangle detection for high-contrast cards/IDs.
    let rectRequest = VNDetectRectanglesRequest()
    rectRequest.minimumConfidence = strictForLive ? 0.72 : 0.62
    rectRequest.minimumSize = strictForLive ? 0.18 : 0.14
    rectRequest.minimumAspectRatio = 0.34
    rectRequest.maximumAspectRatio = 1.0
    rectRequest.quadratureTolerance = 25.0
    rectRequest.maximumObservations = 1
    do {
      try handler.perform([rectRequest])
      if let obs = rectRequest.results?.first,
         let quad = quadFromObservation(
           obs,
           source: "rectangle",
           minConfidence: strictForLive ? 0.72 : 0.62
         ) {
        return quad
      }
    } catch {}

    return nil
  }

  private static func quadFromObservation(
    _ obs: VNRectangleObservation,
    source: String,
    minConfidence: Double
  ) -> NormalizedQuad? {
    let conf = Double(obs.confidence)
    guard conf >= minConfidence else { return nil }
    func flipY(_ p: CGPoint) -> CGPoint {
      CGPoint(
        x: min(max(Double(p.x), 0.0), 1.0),
        y: min(max(1.0 - Double(p.y), 0.0), 1.0)
      )
    }
    let pts = [
      flipY(obs.topLeft),
      flipY(obs.topRight),
      flipY(obs.bottomRight),
      flipY(obs.bottomLeft),
    ]
    return validateAndOrder(pts, confidence: conf, source: source)
  }

  private static func validateAndOrder(
    _ pts: [CGPoint],
    confidence: Double,
    source: String
  ) -> NormalizedQuad? {
    guard pts.count == 4 else { return nil }
    for p in pts {
      if !p.x.isFinite || !p.y.isFinite { return nil }
    }

    // Order clockwise around centroid, starting at Top-Left (min x + y).
    let cx = pts.reduce(0.0) { $0 + Double($1.x) } / 4.0
    let cy = pts.reduce(0.0) { $0 + Double($1.y) } / 4.0
    let sorted = pts.sorted { a, b in
      atan2(Double(a.y) - cy, Double(a.x) - cx) < atan2(Double(b.y) - cy, Double(b.x) - cx)
    }
    var tlIdx = 0
    var minSum = Double.greatestFiniteMagnitude
    for i in 0..<4 {
      let s = Double(sorted[i].x + sorted[i].y)
      if s < minSum {
        minSum = s
        tlIdx = i
      }
    }
    let ordered = [
      sorted[tlIdx],
      sorted[(tlIdx + 1) % 4],
      sorted[(tlIdx + 2) % 4],
      sorted[(tlIdx + 3) % 4],
    ]

    // Convexity check.
    var prevSign: Bool?
    for i in 0..<4 {
      let a = ordered[i]
      let b = ordered[(i + 1) % 4]
      let c = ordered[(i + 2) % 4]
      let cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
      if abs(cross) < 1e-6 { return nil }
      let pos = cross > 0
      if let prev = prevSign, prev != pos { return nil }
      prevSign = pos
    }

    // Shoelace area check (reject tiny clutter & full-frame walls).
    var area = 0.0
    for i in 0..<4 {
      let p = ordered[i]
      let n = ordered[(i + 1) % 4]
      area += Double(p.x * n.y - n.x * p.y)
    }
    area = abs(area) / 2.0
    guard area >= 0.09, area <= 0.97 else { return nil }

    // Aspect ratio check (reject keyboards, thin slivers, table edges).
    let topW = hypot(Double(ordered[1].x - ordered[0].x), Double(ordered[1].y - ordered[0].y))
    let botW = hypot(Double(ordered[2].x - ordered[3].x), Double(ordered[2].y - ordered[3].y))
    let leftH = hypot(Double(ordered[3].x - ordered[0].x), Double(ordered[3].y - ordered[0].y))
    let rightH = hypot(Double(ordered[2].x - ordered[1].x), Double(ordered[2].y - ordered[1].y))
    let avgW = (topW + botW) / 2.0
    let avgH = (leftH + rightH) / 2.0
    guard avgW >= 0.12, avgH >= 0.12 else { return nil }
    let aspect = avgW / avgH
    guard aspect >= 0.32, aspect <= 3.10 else { return nil }

    return NormalizedQuad(
      tl: ordered[0],
      tr: ordered[1],
      br: ordered[2],
      bl: ordered[3],
      confidence: confidence,
      source: source
    )
  }

  /// Fast Laplacian variance (sharpness) and mean luminance (exposure) on the
  /// downscaled BGRA pixel buffer (~0.2 ms at 640px with stride 2).
  private static func computeFrameQuality(
    buffer: CVPixelBuffer
  ) -> (sharpness: Double, brightness: Double) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
      return (100.0, 128.0)
    }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    guard width >= 16, height >= 16 else { return (100.0, 128.0) }

    let ptr = base.assumingMemoryBound(to: UInt8.self)
    @inline(__always)
    func luma(_ x: Int, _ y: Int) -> Int {
      let off = y * bytesPerRow + x * 4
      let b = Int(ptr[off])
      let g = Int(ptr[off + 1])
      let r = Int(ptr[off + 2])
      return (r * 77 + g * 150 + b * 29) >> 8
    }

    let xStart = max(2, width / 10)
    let xEnd = min(width - 3, (width * 9) / 10)
    let yStart = max(2, height / 10)
    let yEnd = min(height - 3, (height * 9) / 10)
    let step = 3

    var sumLap = 0.0
    var sumLapSq = 0.0
    var sumLum = 0.0
    var count = 0.0

    var y = yStart
    while y < yEnd {
      var x = xStart
      while x < xEnd {
        let c = luma(x, y)
        let lap = Double(
          4 * c - luma(x - 1, y) - luma(x + 1, y) - luma(x, y - 1) - luma(x, y + 1)
        )
        sumLap += lap
        sumLapSq += lap * lap
        sumLum += Double(c)
        count += 1.0
        x += step
      }
      y += step
    }

    guard count > 0 else { return (100.0, 128.0) }
    let meanLap = sumLap / count
    let variance = max(0.0, (sumLapSq / count) - (meanLap * meanLap))
    let meanBrightness = sumLum / count
    return (variance, meanBrightness)
  }

  private static func cgOrientation(fromRotation rotation: Int) -> CGImagePropertyOrientation {
    switch ((rotation % 360) + 360) % 360 {
    case 90: return .right
    case 180: return .down
    case 270: return .left
    default: return .up
    }
  }

  private func acquireSlot() -> Bool {
    stateQueue.sync {
      if frameBusy { return false }
      frameBusy = true
      return true
    }
  }

  private func releaseSlot() {
    stateQueue.sync {
      frameBusy = false
    }
  }
}

private final class InoPixelBufferDownscaler {
  private let context = CIContext(options: [
    .workingColorSpace: NSNull(),
    .outputColorSpace: NSNull(),
  ])
  private var pool: CVPixelBufferPool?
  private var poolWidth = 0
  private var poolHeight = 0

  func downscale(
    bytes: Data,
    width: Int,
    height: Int,
    bytesPerRow: Int,
    maxLongSide: Int
  ) -> CVPixelBuffer? {
    let longSide = max(width, height)
    let scale = (maxLongSide > 0 && longSide > maxLongSide)
      ? Double(maxLongSide) / Double(longSide) : 1.0
    let outW = max(2, (Int(Double(width) * scale) / 2) * 2)
    let outH = max(2, (Int(Double(height) * scale) / 2) * 2)

    guard let output = makeBuffer(width: outW, height: outH) else { return nil }

    let sourceImage = CIImage(
      bitmapData: bytes,
      bytesPerRow: bytesPerRow,
      size: CGSize(width: width, height: height),
      format: .BGRA8,
      colorSpace: nil
    )
    let scaled = scale == 1.0
      ? sourceImage
      : sourceImage.transformed(
          by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))
        )
    context.render(scaled, to: output)
    return output
  }

  private func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    if pool == nil || width != poolWidth || height != poolHeight {
      let attrs: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
      ]
      var newPool: CVPixelBufferPool?
      guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &newPool)
        == kCVReturnSuccess, let created = newPool else { return nil }
      pool = created
      poolWidth = width
      poolHeight = height
    }
    guard let pool = pool else { return nil }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
      == kCVReturnSuccess else { return nil }
    return buffer
  }
}
