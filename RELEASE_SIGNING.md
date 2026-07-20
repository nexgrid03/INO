# INO — Android Release Signing

Production-ready release signing for the INO app. Credentials live **only** in
`android/key.properties` (git-ignored); nothing secret is committed. Until you
create the keystore, release builds fall back to debug signing so the build
never breaks.

> Why this matters: on Android, Google Sign-In identifies the app by
> **package name + signing-certificate SHA-1**. A build signed with an
> unregistered key gets rejected by Google (works on one device, fails on
> others). A single, stable release keystore — with its SHA registered — fixes
> that permanently. See "Register SHA fingerprints" below.

---

## How it works (already wired)

- `android/app/build.gradle.kts` loads `android/key.properties` and creates a
  `release` signing config from it. **No passwords are hardcoded.**
- If `key.properties` is **absent** (fresh clone, CI), release **falls back to
  debug signing** so `flutter build` still succeeds.
- `android/.gitignore` already ignores `key.properties`, `**/*.jks`,
  `**/*.keystore` — secrets can't be committed.
- `android/key.properties.example` is the template to copy.

---

## 1. Create the release keystore (one time)

Keep the `.jks` **outside** the repo (e.g. `C:\Users\you\keys\`). You only ever
create this once — reuse it for every future release.

```powershell
keytool -genkeypair -v `
  -keystore C:\Users\you\keys\ino-release.jks `
  -alias ino -keyalg RSA -keysize 2048 -validity 10000
```
(`keytool` ships with the JDK, e.g. `C:\Users\tanis\jdk17\jdk-17.0.19+10\bin\keytool.exe`.)

You'll be prompted for a **store password**, a **key password**, and your
name/org. **Back this file + passwords up safely** — losing them means you can
never update the app under the same key.

## 2. Configure `android/key.properties`

```powershell
Copy-Item android\key.properties.example android\key.properties
```
Edit `android/key.properties` with your real values:
```
storePassword=<your store password>
keyPassword=<your key password>
keyAlias=ino
storeFile=C:/Users/you/keys/ino-release.jks
```
`storeFile` may be absolute (recommended) or relative to `android/app`.

## 3. Obtain SHA-1 / SHA-256

**From the keystore directly:**
```powershell
keytool -list -v -keystore C:\Users\you\keys\ino-release.jks -alias ino
```
Look for the `SHA1:` and `SHA256:` lines under *Certificate fingerprints*.

**Or via Gradle (shows debug + release together):**
```powershell
cd android
.\gradlew signingReport
```

For reference, this machine's **debug** fingerprints (already registered, which
is why sign-in works on your device) are:
```
Debug SHA-1  : 6B:DE:A0:0D:8B:32:CA:A5:A8:FB:7A:FF:CC:C2:AF:60:A9:BD:DE:BD
Debug SHA-256: EC:37:23:6C:C2:09:86:E3:A6:88:75:90:DE:97:E9:D3:F6:95:4F:D8:8E:16:5F:31:00:84:DB:94:ED:AC:0A:52
```

---

## 4. Register SHA fingerprints for Google Sign-In

You must register the SHA of **every** signing key that end users' installs are
signed with. Add them to the **Android OAuth client** in the same Google Cloud
project as your Web client ID (`535920485088-…`).

**Google Cloud Console** → project **535920485088** →
**APIs & Services → Credentials** → open the OAuth client of type **Android**
(package `com.example.inoapp`) → **Add** each SHA-1 under
*SHA-1 certificate fingerprints* → **Save** (allow ~5 min to propagate).

> If Google was set up through **Firebase** instead: **Firebase Console →
> Project settings → Your apps → (Android) → SHA certificate fingerprints →
> Add fingerprint.**

Register:
- **Release SHA-1** (from step 3) — for builds you distribute directly.
- **Debug SHA-1** (above) — so `flutter run` keeps working on this machine.
- **Play App Signing SHA-1 + SHA-256** — see next section (required if you ship
  via Google Play).

## 5. Register Play App Signing SHA (if distributing via Google Play)

When you upload an **AAB**, Google Play **re-signs** the app with its own
**app signing key** — a different SHA-1 than your release key. If you skip this,
Google Sign-In fails for everyone who installs from Play.

**Play Console** → your app → **Test and release → Setup → App integrity →
App signing key certificate** → copy the **SHA-1** *and* **SHA-256** → add both
to the Android OAuth client (step 4). Also copy the **Upload key certificate**
SHA-1 and add it too.

> ⚠️ `applicationId` is currently the placeholder `com.example.inoapp`. Set your
> real package name **before** the first Play upload, and register the SHA under
> that package — the OAuth client's package must exactly match the installed
> app's `applicationId`.

---

## 6. Release build commands

```powershell
# Play upload artifact (recommended)
flutter build appbundle --release      # → build/app/outputs/bundle/release/app-release.aab

# Standalone APK (direct install / sideload)
flutter build apk --release            # → build/app/outputs/flutter-apk/app-release.apk
```
With `android/key.properties` present these are signed with your **release
key**. Verify what a build was signed with:
```powershell
keytool -printcert -jarfile build\app\outputs\flutter-apk\app-release.apk
```

---

## Checklist
- [ ] Created `ino-release.jks` (kept outside the repo, backed up)
- [ ] `android/key.properties` filled in (never committed)
- [ ] Release SHA-1 + SHA-256 registered in the Android OAuth client
- [ ] Debug SHA-1 kept registered (for local `flutter run`)
- [ ] Play App Signing SHA-1 + SHA-256 registered (if shipping via Play)
- [ ] Real `applicationId` set before first Play upload
- [ ] `flutter build appbundle --release` produces a release-signed AAB
