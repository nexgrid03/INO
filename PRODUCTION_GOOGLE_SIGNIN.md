# INO — Production Google Sign-In Readiness

Audit date basis: PR #5 merged to `main` (`62f1488`); `ino-release.jks` created;
release SHA-1/256 generated. This document is the current status, the remaining
actions, the risks, and how to verify.

---

## Current status

| Area | Status | Evidence |
|---|---|---|
| Release signing **config** (build.gradle.kts) | ✅ correct | Loads `android/key.properties`, builds a `release` signingConfig, no hardcoded passwords, warns on debug fallback |
| Release signing **active** | ❌ **NOT active** | `android/key.properties` **does not exist** → release builds currently fall back to **debug** signing |
| Release keystore | ⚠️ exists but **inside the repo** | `ino-release.jks` is at the repo **root** and is **NOT git-ignored** (security risk) |
| `applicationId` consistency | ✅ consistent | `namespace` = `applicationId` = `com.example.inoapp`; `MainActivity` at `.../kotlin/com/example/inoapp/`; manifest `.MainActivity` |
| Production package name | ❌ placeholder | `com.example.inoapp` — Play rejects `com.example.*` |
| Google Sign-In code | ✅ best-practice | Native `google_sign_in` v7 → `signInWithIdToken`; robust error handling; config guard |
| Google Cloud SHA registration | ⏳ manual, pending | Release/Play/upload/debug SHAs (see below) |
| Play App Signing | ⏳ pending | Enroll on first AAB upload |

**Bottom line:** the signing *pipeline* is in place and correct, but it is **not
yet switched on** (no `key.properties`), the keystore is in a risky location, and
the Google Cloud SHA registration + real package name are still required. The app
is **not production-ready for Google Sign-In yet.**

---

## 🔴 Blockers & risks (fix these)

### B1 — Release signing is not active (HIGH)
`android/key.properties` is missing, so `flutter build --release` produces a
**debug-signed** build (Gradle prints the "DEBUG-signed — do NOT distribute"
warning). Debug-signed builds fail Google Sign-In on other devices and cannot be
uploaded to Play.
**Fix:** create `android/key.properties` (below).

### B2 — Keystore is committable (HIGH, security)
`ino-release.jks` is at the repo **root**, which is **not** covered by
`android/.gitignore` (`**/*.jks` only applies under `android/`). It's untracked
now, but `git add -A` would commit your **release keystore** — a credential leak.
**Fix (pick one):**
- **Recommended:** move `ino-release.jks` **outside** the repo (e.g.
  `C:\Users\tanis\keys\ino-release.jks`) and point `key.properties` at it; **or**
- add these lines to the **root** `.gitignore`:
  ```
  *.jks
  *.keystore
  key.properties
  ```
Also confirm it never got committed: `git log --all --oneline -- ino-release.jks`
(should be empty). If it was ever committed, rotate the key.

### B3 — Placeholder package name (MEDIUM, pre-production)
`com.example.inoapp` cannot be published to Play. Migrate to a real reverse-domain
package before production and re-register SHAs under it. (Fine for internal
testing today.)

---

## Remaining actions

### 1. Activate release signing (local)
```powershell
Copy-Item android\key.properties.example android\key.properties
```
Edit `android/key.properties` (git-ignored — never commit):
```
storePassword=<store password>
keyPassword=<key password>
keyAlias=ino
storeFile=C:/Users/tanis/keys/ino-release.jks   # absolute path; keep OUTSIDE the repo
```
Then confirm a release build is signed with the release key:
```powershell
flutter build apk --release      # no "DEBUG-signed" warning should appear
keytool -printcert -jarfile build\app\outputs\flutter-apk\app-release.apk
# → SHA1 must equal 05:5D:BE:42:52:80:98:16:C1:E2:00:6C:87:BD:BF:CC:35:53:93:B3
```

### 2. Google Cloud Console (manual)
Console → project **535920485088** → **APIs & Services → Credentials** → open the
**Android** OAuth client (package `com.example.inoapp`) → add SHA-1(s) → **Save**
(~5 min). *(If configured via Firebase: Firebase Console → Project settings → Your
apps → Android → SHA certificate fingerprints → Add.)*

Register:
- ✅ **Release key SHA-1** `05:5D:BE:42:52:80:98:16:C1:E2:00:6C:87:BD:BF:CC:35:53:93:B3`
- ✅ **Release key SHA-256** `2C:CE:7C:AA:04:E7:8A:E8:16:1C:9F:B0:FA:2B:F9:B0:B5:AA:C0:0F:6D:4A:2C:E6:BD:BF:5D:85:84:93:21:ED`
- ✅ **Play App Signing SHA-1 + SHA-256** — after step 3 (from Play Console)
- ✅ **Each developer's Debug SHA-1 + SHA-256** — so local `flutter run` signs in
  (this machine's debug SHA-1 = `6B:DE:A0:0D:8B:32:CA:A5:A8:FB:7A:FF:CC:C2:AF:60:A9:BD:DE:BD`)

### 3. Play Console (manual)
- Create the app; on first **AAB** upload, **enroll in Play App Signing** (default).
- Copy **Test and release → Setup → App integrity**:
  - **App signing key certificate** → SHA-1 + SHA-256 → register in Google Cloud (step 2).
  - **Upload key certificate** → SHA-1 + SHA-256 → register too.
- Complete Data safety + a Privacy Policy URL (document/PII app).

### 4. Before production
- Migrate `com.example.inoapp` → real package; re-register all SHAs under it.

---

## Which SHA must be registered — and why

| Key | SHA to register | Why |
|---|---|---|
| **Release/Upload key** (`ino-release.jks`) | `05:5D:…:93:B3` (+ SHA-256) | Signs internal-test APK/AAB you distribute before Play re-signs |
| **Play App Signing key** (Google's) | from Play Console | **Every install from Play** is re-signed with this key |
| **Upload key** (as recorded by Play) | from Play Console | Play maps your uploads to this cert |
| **Developer debug keys** | each dev's debug SHA | So `flutter run` (debug) signs in on each machine |

You can add **multiple** SHA-1s to one Android OAuth client — add them all.

---

## How to verify Google Sign-In per channel

| Channel | Signed with | Verifies when |
|---|---|---|
| **My device (dev)** | this machine's debug key | already works (debug SHA registered) |
| **Team member device (dev)** | their debug key | after their debug SHA-1 is registered |
| **Internal testing APK** | release key `05:5D:…` | after release SHA registered + `key.properties` active; `keytool -printcert` shows `05:5D:…`; install → sign in |
| **Internal testing AAB (Play)** | Play App Signing key | after Play App Signing SHA registered; install from Play internal track → sign in |
| **Play production** | Play App Signing key | same Play SHA; production install → sign in |

All channels also require: OAuth client package == installed `applicationId`, and
Supabase Google provider enabled with the Web client ID `535920485088-…`.

---

## Verification checklist
- [ ] `ino-release.jks` moved outside the repo (or root `.gitignore` updated) — keystore not committable
- [ ] `android/key.properties` created (git-ignored)
- [ ] Release APK `keytool -printcert` shows SHA-1 `05:5D:…:93:B3` (not the debug `6B:DE:…`)
- [ ] Release SHA-1 + SHA-256 registered in the Android OAuth client
- [ ] Play App Signing SHA-1 + SHA-256 registered
- [ ] Upload key SHA registered
- [ ] Each developer's debug SHA-1 (+256) registered
- [ ] Sign-in confirmed on a teammate device + an internal-testing install
- [ ] Real `applicationId` set before production; SHAs re-registered under it
- [ ] Supabase Google provider verified

---

## Optional hardening (not a blocker)
- **Nonce:** `signInWithIdToken` supports a nonce (pass the same nonce to
  `GoogleSignIn.authenticate` and Supabase) to prevent token replay. The current
  flow works without it; add it for defense-in-depth.

*Reference:* `RELEASE_SIGNING.md` (full keystore/SHA guide), `lib/services/auth_service.dart`,
`lib/config/supabase_config.dart`, `android/app/build.gradle.kts`.
