# INO — Android App Links for QR Document Sharing

Scanning a share QR opens the URL

```
https://ilfzppryyojoponkomrw.functions.supabase.co/share/<share_id>
```

With App Links configured, that opens **the INO app** directly on
`SharedDocumentsScreen`. If INO isn't installed, the same link opens in the
**browser** (the content-negotiated HTML viewer) — no extra work for that
fallback.

Everything in the app is already wired:

| Piece | Where |
|---|---|
| Intent filters (App Link + `ino://` scheme) | `android/app/src/main/AndroidManifest.xml` |
| Link capture + routing | `lib/services/deep_link_service.dart` |
| Cold-start root + warm listener | `lib/main.dart` (`InoApp`) |
| Recipient screen | `lib/screens/share/shared_documents_screen.dart` |

- **App identifier:** `com.example.inoapp`
- **Handled path:** `https://…/share/*` and `ino://share/<id>`

---

## The one manual step: verify the domain (assetlinks.json)

For Android to open the app **automatically** (no "Open with…" chooser), the
link's domain must serve a Digital Asset Links file at:

```
https://<host>/.well-known/assetlinks.json
```

### ⚠️ Limitation of the Supabase Functions domain
`ilfzppryyojoponkomrw.functions.supabase.co` is a **shared** Supabase host — you
cannot place a file at its `/.well-known/` root. So auto-verification can't be
completed for that domain. You have two options:

### Option A (recommended): a custom domain you control
1. Point a domain/subdomain (e.g. `https://ino.app` or `https://share.ino.app`)
   at the Edge Function — e.g. a Cloudflare Worker / Vercel rewrite that proxies
   `/share/*` → `https://ilfzppryyojoponkomrw.functions.supabase.co/share/*`.
2. Host `deep-linking/assetlinks.json` (this repo) at
   `https://<your-domain>/.well-known/assetlinks.json` with your real fingerprint
   (below). It **must** be served as `content-type: application/json` over HTTPS,
   no redirects.
3. In `AndroidManifest.xml`, uncomment the custom-domain `<intent-filter>` and
   set its `android:host` to your domain.
4. In `lib/config/share_config.dart`, set
   `customBaseUrlOverride = 'https://<your-domain>/share'` so **new** QR codes
   encode the verified domain.

Result: scans of your domain's links auto-open the app; browser fallback still
works when the app is absent.

### Option B (no custom domain): manual per-device enable
The intent filter still registers INO as a handler for the functions.supabase.co
links, but without verification Android 12+ won't auto-open them. A user can
enable it manually: **Settings → Apps → INO → Open by default → “Open supported
links” → add the functions.supabase.co domain.** (Good enough for testing; not a
shippable UX — prefer Option A.)

The `ino://share/<id>` custom scheme **always** opens the app with no
verification (handy for testing and app-to-app hand-offs), but a browser can't
fall back on it, so it isn't used for the public QR.

---

## Get your SHA-256 signing fingerprint

`assetlinks.json` must list the fingerprint of the **key that signs the APK the
user installs**:

- **debug** builds (local testing):
  ```bash
  keytool -list -v -keystore ~/.android/debug.keystore \
    -alias androiddebugkey -storepass android -keypass android
  ```
- **release** builds: use your upload keystore. If you ship via **Google Play
  App Signing**, use the SHA-256 shown in *Play Console → Release → Setup → App
  signing* (Google re-signs, so the Play fingerprint is the one that matters).

Copy the `SHA256:` value into `sha256_cert_fingerprints` in
`deep-linking/assetlinks.json`. You can list multiple (e.g. debug + upload + Play).

---

## Verify it works

Build/install the app, then:

```bash
# Cold start (app closed):
adb shell am start -a android.intent.action.VIEW \
  -d "https://ilfzppryyojoponkomrw.functions.supabase.co/share/share_TESTID"

# Custom scheme (always opens the app):
adb shell am start -a android.intent.action.VIEW -d "ino://share/share_TESTID"

# Check App Links verification status for the app:
adb shell pm get-app-links com.example.inoapp
```

Filter the app's logs by tag `deeplink` to trace: incoming link → extracted
share id → navigation, and `share` for the API fetch.

Expected: the app opens on **Shared Documents** for that id and fetches the share
via the Edge Function.
