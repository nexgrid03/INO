# INO — iOS Platform Support

This branch adds the iOS platform to INO (it previously had none). The app now
has a complete iOS Runner, permissions, URL schemes, min-iOS config, launcher
icons, and iPad share-sheet compatibility. **Android is untouched.**

> ⚠️ iOS builds require a Mac with Xcode (+ CocoaPods). These changes were made
> and verified on Windows (`flutter analyze`, `flutter test`); the first
> `pod install` / archive must happen on macOS.

---

## 1. What was changed (in this repo)

### iOS runner (new — `ios/`)
- Scaffolded with `flutter create --platforms=ios .` (newest scene-based
  template: `SceneDelegate`, `UIApplicationSceneManifest`).
- `.metadata` now tracks **both** `android` and `ios` for `flutter migrate`.

### Minimum iOS version → 15.5
- `ios/Podfile` (new): `platform :ios, '15.5'` and `post_install` forces every
  pod to 15.5. **Required by GoogleMLKit** (pulled in by
  `google_mlkit_text_recognition`); anything lower fails `pod install`.
- `ios/Runner.xcodeproj/project.pbxproj`: `IPHONEOS_DEPLOYMENT_TARGET = 15.5`
  (Debug/Release/Profile).

### Info.plist permissions & schemes (`ios/Runner/Info.plist`)
- `NSCameraUsageDescription` — camera / scanner / `image_picker`
- `NSPhotoLibraryUsageDescription` — gallery import / file picker
- `NSFaceIDUsageDescription` — `local_auth` (Face ID app-lock)
- `NSMicrophoneUsageDescription` — `camera` module may request it
- `LSApplicationQueriesSchemes` — `mailto`, `tel`, `https`, `http` (for
  `url_launcher`: support email + legal links)
- `CFBundleURLTypes` — two schemes:
  - **Google Sign-In** callback (placeholder `REVERSED_GOOGLE_IOS_CLIENT_ID`)
  - **`ino://share/<token>`** custom scheme (mirrors the Android intent-filter)
- `ITSAppUsesNonExemptEncryption = false` — skips the export-compliance prompt

### permission_handler (iOS)
- Podfile `post_install` defines `PERMISSION_CAMERA=1` and `PERMISSION_PHOTOS=1`
  and compiles **out** every other permission (`=0`), so App Review never sees
  unused permission code.

### Universal Links structure (`ios/Runner/Runner.entitlements`, new)
- Associated-domains entitlement scaffold with an `applinks:your-share-domain`
  placeholder. **Intentionally not wired into the build** (see §2) so it can't
  break code-signing before the Apple capability + domain exist.

### iPad share-sheet crash fix (Dart — safe, no Android/iPhone change)
- New `lib/utils/share_origin.dart` → `shareOrigin(context)` returns the popover
  anchor `Rect` iPadOS requires. `share_plus` **throws on iPad** without
  `sharePositionOrigin`; it's ignored on iPhone/Android.
- Added `sharePositionOrigin:` to all **6** share call sites:
  `document_viewer_screen.dart`, `shared_documents_screen.dart`,
  `qr_share_screen.dart` (×2), `cloud_backup_screen.dart`, `profile_screen.dart`.

### Launcher icons
- `pubspec.yaml`: `flutter_launcher_icons: ios: true` + `remove_alpha_ios: true`
  (App Store rejects icons with an alpha channel).
- Ran `dart run flutter_launcher_icons` → generated `ios/Runner/Assets.xcassets/
  AppIcon.appiconset` (21 sizes). The Android icon change it also produced was
  reverted to keep Android untouched.

### Verification
- `flutter analyze` → **No issues found**
- `flutter test` → **111 passing**

---

## 2. What still requires an **Apple Developer account** (on macOS/Xcode)

These need paid-account resources and can't be done from this repo alone:

1. **Signing** — set a real **Bundle ID** (currently `com.example.inoapp`), Team,
   and signing certificate in Xcode → *Signing & Capabilities*.
2. **`pod install`** — run once on macOS (`cd ios && pod install`) to resolve
   the GoogleMLKit / permission_handler pods. Build from `Runner.xcworkspace`.
3. **Universal Links** — in Xcode add the **Associated Domains** capability
   (this wires `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` and adds the
   capability to your provisioning profile). Then:
   - replace `applinks:your-share-domain` in `Runner.entitlements` with your real
     share domain (a **custom domain** — not `*.functions.supabase.co`), and
   - host `https://<domain>/.well-known/apple-app-site-association`:
     ```json
     { "applinks": { "apps": [], "details": [
       { "appID": "<TEAMID>.com.yourco.inoapp", "paths": [ "/share/*", "/s/*" ] } ] } }
     ```
   Until then, share links still open via the `ino://` scheme + browser fallback.
4. **Guideline 4.8 — Sign in with Apple** *(likely review requirement)*: because
   the app offers Google Sign-In, App Review usually requires an equivalent
   privacy-focused option (Sign in with Apple). Not yet implemented
   (`AuthService.isAppleSignInAvailable == false`).
5. **App Store Connect** — app record, **App Privacy** questionnaire (this app
   handles documents/PII), and a **Privacy Policy URL** (link the in-app legal
   screens).
6. **APNs** — only if you later add push notifications (none exist today).

---

## 3. What still requires **Google Cloud iOS OAuth** setup

Google Sign-In on iOS will not work until:

1. **Create an iOS OAuth client** in Google Cloud Console (APIs & Services →
   Credentials → *Create OAuth client ID* → **iOS**), using your real bundle ID.
2. Put its client ID in [`lib/config/supabase_config.dart`](lib/config/supabase_config.dart)
   → `googleIosClientId` (currently the placeholder `YOUR_GOOGLE_IOS_CLIENT_ID`;
   the Dart code already passes it on iOS via `AuthService._platformClientId`).
3. In `ios/Runner/Info.plist`, replace the URL scheme
   `REVERSED_GOOGLE_IOS_CLIENT_ID` with the **reversed** iOS client ID
   (`com.googleusercontent.apps.<numbers>-<hash>`).
4. Keep `serverClientId = googleWebClientId` (already set) so Supabase accepts
   the token — no change needed there.

> The Google **web client secret** must remain only in the Supabase dashboard —
> never in the app.

---

## 4. Known iOS feature gaps (by design, not regressions)

- **Document scanner** (`google_mlkit_document_scanner`) is **Android-only**. The
  app already gates it (`DocumentScannerService.isSupported => Platform.isAndroid`),
  so on iOS the "scan" entry point is hidden — users add documents via
  camera/gallery + OCR (text recognition works on iOS). Add a VisionKit-based
  scanner later if native edge-detection is wanted on iOS.
- **Push / local OS notifications** are **not implemented on any platform**
  (no `firebase_messaging` / `flutter_local_notifications`). The in-app
  notification centre is derived UI only; reminders don't fire OS alerts.

---

## 5. Files changed on this branch

```
NEW:
  ios/…                                   (full iOS runner, 48 files)
  ios/Podfile                             (min iOS 15.5 + permission_handler macros)
  ios/Runner/Runner.entitlements          (Universal Links scaffold)
  lib/utils/share_origin.dart             (iPad share popover anchor)
  IOS_READINESS.md                        (this file)
CHANGED:
  ios/Runner/Info.plist                   (permissions, URL schemes, query schemes)
  ios/Runner.xcodeproj/project.pbxproj    (deployment target 15.5)
  .metadata                               (track android + ios)
  pubspec.yaml                            (launcher-icons ios:true; version bump*)
  lib/screens/wallet/document_viewer_screen.dart
  lib/screens/share/shared_documents_screen.dart
  lib/screens/share/qr_share_screen.dart
  lib/screens/profile/cloud_backup_screen.dart
  lib/screens/profile/profile_screen.dart   (sharePositionOrigin at 6 sites)
```
\* `version: 1.0.0+1 → 1.0.1+2` was a pre-existing local edit, kept as-is.

**Android build config and behavior are unchanged.**
