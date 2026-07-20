# INO — Android Release Signing & Google Sign-In (Permanent Setup)

The definitive, production-grade guide to signing INO for Android and making
**Google Sign-In work on every device** — your machine, teammates, CI, internal
testing (APK + AAB), and Play Store production.

Credentials live **only** in `android/key.properties` (git-ignored); nothing
secret is committed. Until a keystore is configured, release builds fall back to
debug signing **and print a loud warning** so a debug-signed build can't be
shipped by accident.

---

## Why Google Sign-In "works on my device but not others"

On Android this app authenticates to Google **purely by
`package name + signing-certificate SHA-1`** (native `google_sign_in` v7 —
`initialize(clientId: null, serverClientId: webClientId)` in
`lib/services/auth_service.dart`). Google issues an ID token **only** if the
installed APK's signing SHA-1 is registered in the **Android OAuth client** of
your Google Cloud project (`535920485088`, the project behind the Web client ID
`535920485088-…`). Supabase then trusts that token via `signInWithIdToken`.

The debug keystore is **unique per machine**, so:
- Your device works (your debug SHA-1 is registered).
- Teammates' debug builds, CI builds, internal-test builds, and Play installs are
  signed with **different keys** whose SHA-1 is **not** registered → Google
  rejects them → sign-in fails.

**Permanent fix = one stable release key + Play App Signing, with the correct
SHAs registered.** This document is that setup.

---

## How the signing pipeline works (already wired — PR #5)

- `android/app/build.gradle.kts` loads `android/key.properties` and builds a
  `release` `signingConfig` from it. **No passwords are hardcoded.**
- If `key.properties` is absent it falls back to debug signing **and warns**.
- `android/.gitignore` ignores `key.properties`, `**/*.jks`, `**/*.keystore`.
- `android/key.properties.example` is the template to copy.

---

## 🚫 Production blocker: the package name

`applicationId` / `namespace` are the placeholder **`com.example.inoapp`**.
Google Play **rejects `com.example.*`**, and you don't own that namespace. Pick a
real, reverse-domain package **before your first production/Play upload** (e.g.
`in.inoapp.app` or `com.yourcompany.ino`). It is **permanent** once published.

**Rename steps (infra only):**
1. `android/app/build.gradle.kts` → set `namespace` and `applicationId` to the new id.
2. Move `android/app/src/main/kotlin/com/example/inoapp/MainActivity.kt` to the
   new package folders and update its `package` line.
3. `AndroidManifest.xml` uses `.MainActivity` (relative) — no change needed.
4. **Re-register** the new package name + your SHA-1s in the Android OAuth client
   (below). The OAuth client's package must exactly match the installed
   `applicationId`.

> You can keep `com.example.inoapp` for **internal testing** today (it already
> works on your device), but you must migrate before production.

---

## Step 1 — Create the ONE release keystore (one time, ever)

Keep the `.jks` **outside the repo** and **back it up** — losing it means you can
never update the app under the same key.

```powershell
keytool -genkeypair -v `
  -keystore C:\Users\you\keys\ino-release.jks `
  -alias ino -keyalg RSA -keysize 2048 -validity 10000
```
(`keytool` ships with the JDK, e.g. `C:\Users\tanis\jdk17\jdk-17.0.19+10\bin\keytool.exe`.)

## Step 2 — Configure `android/key.properties`

```powershell
Copy-Item android\key.properties.example android\key.properties
```
```
storePassword=<store password>
keyPassword=<key password>
keyAlias=ino
storeFile=C:/Users/you/keys/ino-release.jks
```

## Step 3 — Enroll in Play App Signing (recommended, permanent)

When you create the app in Play Console and upload your first AAB, opt into
**Play App Signing** (default for new apps). Google then holds the **app signing
key**; you sign uploads with your **upload key** (the keystore above). This is
the durable strategy — you can reset the upload key if lost, and Google manages
the production signing key.

Consequence you MUST handle: **installs from Play are signed with Google's app
signing key**, whose SHA differs from your upload/release key. That Play SHA
**must** be registered for Google Sign-In (Step 5), or production sign-in fails.

---

## Step 4 — Obtain every fingerprint (exact commands)

| Fingerprint | How to get it |
|---|---|
| **Release / Upload key SHA-1 & SHA-256** | `keytool -list -v -keystore C:\Users\you\keys\ino-release.jks -alias ino` — read `SHA1:` / `SHA256:` |
| (alt: both keys at once) | `cd android; .\gradlew signingReport` (shows debug + release) |
| **Play App Signing SHA-1 & SHA-256** | Play Console → your app → **Test and release → Setup → App integrity → App signing key certificate** |
| **Upload key SHA-1 & SHA-256** (shown by Play) | same page → **Upload key certificate** |
| **Debug SHA-1 & SHA-256** (per developer) | `keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android` |

This machine's **debug** fingerprints (already registered — why your device works):
```
Debug SHA-1  : 6B:DE:A0:0D:8B:32:CA:A5:A8:FB:7A:FF:CC:C2:AF:60:A9:BD:DE:BD
Debug SHA-256: EC:37:23:6C:C2:09:86:E3:A6:88:75:90:DE:97:E9:D3:F6:95:4F:D8:8E:16:5F:31:00:84:DB:94:ED:AC:0A:52
```

---

## Step 5 — Register the fingerprints in Google Cloud (the actual fix)

**Where:** Google Cloud Console → project **535920485088** →
**APIs & Services → Credentials** → open the OAuth 2.0 client of type
**Android** (package `com.example.inoapp`, or your new package) → add each SHA-1
under *SHA-1 certificate fingerprints* → **Save** (≈5 min to propagate).
> If Google was configured via **Firebase**: Firebase Console → Project settings
> → Your apps → (Android) → **SHA certificate fingerprints → Add fingerprint**.

**Which SHA to add, and why:**

| Fingerprint | Register? | Why |
|---|---|---|
| **Release/Upload key SHA-1** | ✅ Required | Signs internal-test APK/AAB you distribute **before** Play re-signs |
| Release/Upload key SHA-256 | ✅ Add too | Credential Manager (Android 14+) prefers SHA-256 |
| **Play App Signing SHA-1** | ✅ Required | **Every install from Play** is signed with Google's app signing key |
| Play App Signing SHA-256 | ✅ Add too | SHA-256 path for Play installs |
| **Each developer's Debug SHA-1** | ✅ Required | So `flutter run` (debug) signs in on each teammate's machine |
| Debug SHA-256 | ✅ Recommended | SHA-256 path for local dev |

You can add **multiple** SHA-1s to one Android OAuth client — add all of the above.

---

## Step 6 — Release build commands

```powershell
flutter build appbundle --release   # → build/app/outputs/bundle/release/app-release.aab  (Play upload)
flutter build apk --release         # → build/app/outputs/flutter-apk/app-release.apk      (direct install)
```
With `android/key.properties` present these are signed with your **release key**.
Verify what a build was signed with:
```powershell
keytool -printcert -jarfile build\app\outputs\flutter-apk\app-release.apk
```

---

## Team members & CI (sign with the SAME release key)

- **Teammates building releases**: share `ino-release.jks` **securely** (a secrets
  manager / password vault — never git/Slack/email). Each creates their own local
  `android/key.properties` pointing at it.
- **CI**: store the keystore (base64) + passwords as CI **secrets**; in the job,
  decode the keystore and write `android/key.properties` before `flutter build`.
  All CI artifacts are then signed with the one release key.
- **Teammates doing local dev** (`flutter run`, debug): register **each** person's
  debug SHA-1 in the OAuth client, **or** distribute a shared debug keystore. This
  is why teammates currently can't sign in.

---

## Will Google Sign-In work? (cross-channel verification)

| Channel | Signed with | Works after… |
|---|---|---|
| **Local dev (you)** | your debug key | your debug SHA-1 registered ✅ (already) |
| **Local dev (teammate)** | their debug key | their debug SHA-1 registered |
| **Internal testing APK** (direct install) | your **release/upload** key | release SHA-1/256 registered |
| **Internal testing AAB** (via Play) | **Play App Signing** key | Play App Signing SHA-1/256 registered |
| **Play production** | **Play App Signing** key | Play App Signing SHA-1/256 registered |

All rows also require: package name in the OAuth client == installed
`applicationId`, and Supabase Google provider enabled with the Web client ID.

---

## Migration plan: debug-signing → release-signing

1. **Merge PR #5** (this signing config).
2. Create `ino-release.jks` (Step 1) and back it up.
3. Create `android/key.properties` (Step 2).
4. `flutter build appbundle --release` → confirm no debug-fallback warning, and
   `keytool -printcert` shows your release key.
5. Create the app in **Play Console**, upload the AAB, **enroll in Play App
   Signing** (Step 3).
6. Collect all fingerprints (Step 4) and **register** them (Step 5): release SHA,
   Play App Signing SHA, each dev's debug SHA.
7. **(Before production)** migrate off `com.example.inoapp` to your real package
   and re-register the SHAs under the new package.
8. Reinstall on a previously-failing device → sign-in works.

---

## Supabase (verify — already correct since one device works)

Authentication → Providers → **Google**: enabled; **Client ID** = the Web client
`535920485088-…`; its **Client Secret** set; the Web client ID also listed under
**Authorized Client IDs** (audience for `signInWithIdToken`). No change needed
unless it breaks.

---

## Final checklist
- [ ] PR #5 merged
- [ ] `ino-release.jks` created, kept out of the repo, **backed up**
- [ ] `android/key.properties` filled in (never committed)
- [ ] Release build signed with the release key (`keytool -printcert` verified)
- [ ] Play App Signing enrolled
- [ ] **Release** SHA-1 + SHA-256 registered in the Android OAuth client
- [ ] **Play App Signing** SHA-1 + SHA-256 registered
- [ ] **Each developer's debug** SHA-1 (+256) registered
- [ ] Real `applicationId` set before production, SHAs re-registered under it
- [ ] Supabase Google provider verified
- [ ] Sign-in verified on a teammate device + an internal-testing install
