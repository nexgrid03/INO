# INO — Security fix handoff

Two things live here:

- **Part 1** is a prompt. Copy everything inside the fenced block and paste it as your first message in a fresh Claude Code session.
- **Part 2** is the work only you can do, outside the code, with exact steps.

Do the two **Deploy now** items in Part 2 before anything else. They are already-written fixes sitting inert on disk.

---

## Part 1 — The prompt

Copy from `You are continuing` down to the final line of the block.

```
You are continuing a pre-Play-Store security remediation of INO, a Flutter personal
wealth and document vault app at c:\Users\yashw\Downloads\INO. Supabase backend,
Firebase push, Next.js share site in share-frontend/. Windows machine: use the Bash
tool (Git Bash) for reading with cat/grep/sed. Gradle needs JAVA_HOME set first:
export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"
There is no java on PATH otherwise.

A full source audit was completed and scored the app 4/10. Every finding below was
confirmed by reading the code, so treat them as real, not as leads to re-verify from
scratch. Read the file before changing it, but do not re-audit the whole app.

== HOW I WANT YOU TO WORK ==

1. BEFORE changing anything that could alter behaviour users notice, break a working
   feature, risk data loss, or require me to do console work to keep the app running:
   STOP and tell me what it affects, then wait for my go-ahead. Specifically ask
   before: anything that could sign users out, anything that migrates or re-encrypts
   stored data, anything that changes what a signed-out user can reach, anything that
   makes a currently-succeeding action start failing, and the package rename.
2. Everything that is purely additive or clearly safe (new files, text, comments,
   masking, headers, config hardening), just do without asking.
3. Work in dependency order and finish each item fully before starting the next.
   Do not leave a half-applied change in the tree.
4. After each group, run the relevant tests and report real results. Never claim
   something passed that you did not run. If you cannot verify something, say so.
5. If a fix turns out to be wrong, riskier than described, or already done, say so
   plainly instead of forcing it through.
6. Do not commit or push. Leave changes in the working tree for me to review.
7. Keep a running list of anything I must do outside the code and give it to me at
   the end with exact steps.

== ALREADY DONE — LEAVE ALONE ==

Do not modify these, they are finished and verified: supabase/functions/share/index.ts
loadShare(), supabase/migrations/20260903000000_security_hardening.sql, the
READ_MEDIA_* removal in android/app/src/main/AndroidManifest.xml,
android/app/src/main/res/xml/network_security_config.xml, and
lib/services/camera_permission_service.dart requestPhotos(). Everything still
outstanding is listed below.

Two fixes were applied and then deliberately REVERTED because they changed
behaviour before the app was ready for them. They are items 42 and 43 below. Do
not reapply them early, and do not treat their absence as an oversight.

== DECISIONS ALREADY MADE ==

- The Android application ID will become in.inoapp.app (currently com.example.inoapp).
- The privacy policy and account-deletion page will be hosted on inoapp.in.

== THE WORK ==

Do these in order. Stop and ask where marked ASK FIRST.

--- GROUP 1: Critical ---

1. [ASK FIRST — after this, Delete Account errors until I run the migration]
   Account deletion does not delete the account.
   lib/services/account_service.dart:89-139 deletes storage files, wallet rows and
   the profile row, then calls rpc('delete_account') inside a try/catch that logs
   failure and ignores it. That function does not exist anywhere in supabase/. So
   auth.users survives, the user can sign straight back in, no cascade fires, and
   notes, reminders, expenses, tax_documents, offline_documents, document_shares,
   share_views, share_downloads, view_once_shares, user_qr_codes, vault_keys,
   device_tokens, notification_outbox, push_log, the family vault tables and every
   w_* wallet table keep their data. Active share links keep serving documents.
   Play's account-deletion policy and India's DPDP Act both require real deletion.
   FIX: write a security definer delete_account() in a NEW migration file
   (set search_path = public, auth, storage; grant execute to authenticated only).
   Resolve v_uid := auth.uid(), raise if null, delete from every user-scoped table
   (enumerate them by reading all migrations), delete storage.objects under the
   user's <uid>/ folder in the documents bucket, and delete from auth.users LAST so
   the cascades fire. Handle vaults the user solely owns (delete the vault) versus
   vaults with co-owners (remove only their membership). Use to_regclass guards so a
   missing table cannot abort the whole deletion. Then in the client: treat RPC
   failure as a hard error shown to the user instead of a swallowed log, unregister
   the push token before the session ends, and wipe local data afterwards.

2. Write the public legal documents.
   The privacy policy exists only as bundled strings at lib/l10n/app_localizations.dart
   around 2338-2348. It names no third party, no retention period, no age policy, no
   DPDP or GDPR rights, no legal entity, no direct contact, and it falsely claims
   users can export all their data at any time. Play requires a publicly hosted
   policy URL and a web account-deletion URL.
   FIX: create PRIVACY_POLICY.md and TERMS.md at the repo root, and a deletion-request
   page, all ready to host at inoapp.in. Cover every data type in the mapping below,
   each purpose, every named third party, retention, DPDP Act 2023 and GDPR-equivalent
   rights, a grievance contact, an 18-or-older clause, and a last-updated date. Leave
   the legal entity name as a clearly marked placeholder for me to fill in.
   Then rewrite the in-app policy text to match, and link out to the hosted URL.

   Data types to cover: email, name, phone, language and Google profile; password
   hash and TOTP factor; government ID document images in private Supabase Storage;
   ID numbers plus name, DOB, gender and expiry extracted by ON-DEVICE ML Kit OCR
   (no image ever leaves the device for OCR — say so, it is a real strength); card
   bank, label, holder, last four and expiry (never the full number, never the CVV —
   also a real strength); vault passwords, end-to-end encrypted with AES-256-GCM
   under a PBKDF2 key the server never sees; expenses, investments, property, net
   worth, notes, reminders, tax documents; UPI payment QR; family vault membership,
   shared documents and audit log; share links and their view and download analytics,
   served via a Supabase Edge Function and a Vercel-hosted page; FCM push token and
   platform; Firebase installation ID collected for every install including guests;
   notification titles and bodies, which pass through Google FCM and are logged
   server-side; voice audio sent to the OS speech recogniser, which may be cloud
   based; IP address and user agent disclosed to Supabase, FCM, fonts.gstatic.com,
   forex-data-feed.swissquote.com and api.frankfurter.dev; local offline document
   copies; and the biometric flag, where the OS holds the biometric and the app
   stores only a boolean.

3. [ASK FIRST — this one breaks Google Sign-In until I finish console work]
   Rename the application ID from com.example.inoapp to in.inoapp.app. Play refuses
   com.example.* and the value is immutable after first upload.
   Touches: android/app/build.gradle.kts:25 namespace and :45 applicationId; the
   MainActivity.kt package declaration and its directory path; google-services.json
   package_name; lib/firebase_options.dart androidBundleId/iosBundleId;
   deep-linking/assetlinks.json; the iOS bundle identifier.
   Confirm with me whether I have finished the Google Cloud and Firebase steps first.

--- GROUP 2: High ---

4. [ASK FIRST — changes the auth flow]
   Two-factor authentication is bypassed by force-quitting at the TOTP prompt.
   needsMfaChallenge() is called in exactly one place: lib/screens/auth/auth_flow.dart:57-71.
   signInWithPassword persists an aal1 session immediately, then the code merely
   PUSHES MfaChallengeScreen. If the process dies there, on relaunch
   lib/screens/splash/splash_screen.dart:192-209,257-260 sees a session and opens the
   shell with no AAL check. No RLS policy checks the aal claim either.
   FIX: check needsMfaChallenge() in the splash cold-start path and anywhere else a
   persisted session is adopted, including AccountSwitcher.switchTo. Do not save an
   account into the switcher until aal2 (account_switcher.dart:126-131 currently saves
   on the signedIn event). Fail CLOSED if the AAL check cannot reach the network, but
   never block a user who has no enrolled factor.

5. [ASK FIRST — signed-out users lose offline access entirely]
   A logged-out phone in airplane mode opens the previous user's documents.
   splash_screen.dart:250-255 routes to the offline library BEFORE checking for a
   session. offline_document_store.dart:209-221 falls back to a persisted
   ino_offline_docs_last_uid that is never cleared. auth_service.dart:253 turns the
   biometric app lock OFF on sign-out, and SessionReset wipes the per-document
   protection flags that offline_documents_screen.dart:120-128 gates on. Nothing
   purges the offline files.
   FIX: do not route to the offline root with no session. Stop disabling the app lock
   on sign-out while offline data may remain. Add clearForSignOut() to
   OfflineDocumentStore that deletes offline_docs/<uid>/, the ino_offline_docs_<uid>
   key and ino_offline_docs_last_uid, and call it from lib/services/session_reset.dart.
   Make it exception-safe so a failed delete cannot break sign-out.

6. [ASK FIRST — data migration, and users may have to sign in once]
   Refresh tokens for every saved account use a constant single-byte XOR.
   lib/services/account_switcher.dart:34-53 XORs with 0x57 and base64s it; the comment
   claims a "device salt" that does not exist. Persisted at :241-251 in SharedPreferences.
   A Supabase refresh token mints sessions from any machine, every account ever signed
   in is retained, and removeAccount at :175 never revokes server-side. Separately,
   lib/main.dart:45-49 calls Supabase.initialize with no localStorage override, so the
   live session is plaintext JSON in SharedPreferences.
   FIX: move the token list to flutter_secure_storage (already a dependency at ^10.3.1;
   lib/services/vault_key_store.dart shows the AndroidOptions pattern), migrate existing
   entries once then delete the old key, delete the XOR helper, best-effort revoke on
   removeAccount, and pass a secure-storage-backed LocalStorage to Supabase.initialize
   with a first-run migration so nobody is signed out by the upgrade. Make every read
   and write exception-safe so a Keystore failure degrades to signed-out, not a crash.

7. [ASK FIRST — re-encrypts stored passwords]
   The password vault caches entries as plaintext JSON.
   lib/services/password_store.dart:36-51 writes every entry, nickname and real
   password, via lib/services/local_collection_store.dart:243-254 into
   ino_passwords_<uid>. The file's own comment at :32-35 admits it. The server copy is
   AES-GCM sealed and the key is memory-only, so the entire end-to-end design is
   undone locally and the passphrase gate is cosmetic.
   FIX: persist the sealed ciphertext and decrypt lazily while unlocked, or move the
   cache to flutter_secure_storage. resealForNewKey() at :127-163 currently depends on
   the plaintext, so keep the passphrase-change flow working. Write a one-time
   migration; never leave plaintext behind and never destroy entries the server does
   not already have.

8. Mask government ID numbers.
   The parsers extract full 12-digit Aadhaar plus name, DOB and gender; they are stored
   unmasked in record_number and shown in full as SelectableText with a copy button at
   lib/screens/wallet/document_viewer_screen.dart:927,971. No masking exists anywhere.
   FIX: mask by default as XXXX XXXX 1234 with a deliberate reveal action, matching how
   the password vault gates reveals. Add a masking helper in the data layer and use it
   in the viewer, the quick view and the export. Tell me what a server-side encryption
   migration for record_number would involve, but do not attempt it in this pass.

--- GROUP 3: Medium ---

9.  Sender-controlled MIME is served inline on the share origin.
    create_processed_share (supabase/migrations/20260810000000_share_security_fixes.sql:39-93)
    accepts any p_mimes; supabase/functions/share/index.ts:466-474 passes the stored
    content-type through with content-disposition: inline; the Next.js route at
    share-frontend/app/api/s/[token]/file/[index]/route.ts:29-31 copies it verbatim.
    Neither sets nosniff or a CSP, so a sender can upload HTML or SVG and get a
    phishing page on the INO share domain.
    FIX: allow-list MIME in the SQL function, derive Content-Type server-side from that
    allow-list rather than trusting stored metadata, and add X-Content-Type-Options:
    nosniff and Content-Security-Policy: sandbox to every file response in both places.

10. Share password travels in the query string and its unsalted SHA-256 IS the credential.
    lib/utils/share_password.dart:6-11 hashes with bare SHA-256; index.ts:217-238
    accepts either the raw password or the hash, so the stored hash is replayable;
    index.ts:948-956 renders a GET form so it lands in ?pw=. Query strings reach Vercel
    and Supabase logs, browser history and Referer headers.
    FIX: accept the password only in a POST body or header, hash with pgcrypto crypt()
    server-side via a service_role-only verification function, stop accepting a hash as
    a credential, and add Referrer-Policy: no-referrer. Keep a documented compatibility
    path so existing links still work.

11. No rate limiting on the public share endpoint (index.ts:283-286 password checks,
    :304-308 view inserts). Add a Postgres-backed limiter keyed by hashed client IP and
    token. Fail open on limiter errors for availability, but fail CLOSED for password
    attempts.

12. Storage quota is client-side only (lib/repositories/document_repository.dart:135-141).
    Enforce it server-side with a trigger or INSERT policy on storage.objects.

13. Offline documents and every viewed document sit unencrypted and are never purged.
    lib/services/offline_document_store.dart:298-332 is a plain file copy;
    lib/services/document_file_service.dart:15-47 streams every viewed document into
    the temp directory and keeps it forever. Purge the temp cache on sign-out and after
    open, and encrypt offline copies with a Keystore-wrapped key. Keep existing offline
    documents openable; back-compat matters more than covering every old file.

14. The document metadata cache holds ID numbers in plain prefs and outlives sign-out
    (lib/repositories/document_repository.dart:93-121, and the profile cache at
    lib/repositories/user_repository.dart:113-125,277-288 where clearCache() at :273
    only nulls memory). Remove both on sign-out and encrypt or stop caching the
    sensitive fields.

15. Notification content is readable on the lock screen. lib/services/push_service.dart:82-92
    never sets NotificationVisibility, and bodies carry document names, card bank and
    last four, and reminder text. Set NotificationVisibility.private with a generic
    public version. Also add 90-day retention to push_log and notification_outbox
    (supabase/migrations/20260813000000_push_log.sql) with a service_role-only prune
    function and a pg_cron note.

16. Voice navigation uses the cloud recogniser by default and logs transcripts
    (lib/services/voice_navigation_service.dart:86-93, :198-203). Prefer on-device
    where available, add a rationale before the first mic prompt, and guard the
    transcript logging with kDebugMode.

17. Consent gaps. The FCM permission prompt fires one frame after launch for everyone
    including guests (lib/main.dart:133 into push_service.dart:129,211-216) — make it
    contextual. The Profile Notifications switch is cosmetic: profile_screen.dart:77,220-226
    persists a bool nothing reads, so pushes keep arriving — make it real by
    deleting and re-registering the device token. Google sign-in creates an account with
    no terms acceptance while email sign-up requires a ticked box — add the consent.

18. No age gate. Add an 18-or-older clause to the Terms and the sign-up copy.

19. Clipboard has no auto-clear for passwords and ID numbers
    (lib/screens/passwords/password_vault_screen.dart:223-230,252,376;
    document_viewer_screen.dart:1741; lib/widgets/wallet_detail/document_quick_view.dart:242;
    lib/widgets/wallet_modules/module_kit.dart:177). Note
    lib/screens/vault/vault_item_detail_screen.dart:26-42 already does it correctly with a
    30-second wipe. Add one shared helper that clears only if the clipboard still holds
    the value it wrote, and use it everywhere.

20. Data export is advertised but unreachable. lib/services/data_export_service.dart and
    backup_service.dart are only called from auto_backup_coordinator.dart:81, there is no
    Export row in Profile, and the auto-backup toggle has no UI — yet the policy, the FAQ
    and the Terms all promise export. Wire it to a Profile row, or remove the claims.
    Wiring it is strongly preferred.

21. iOS Podfile:56-60 sets PERMISSION_MICROPHONE=0 and PERMISSION_SPEECH_RECOGNIZER=0, so
    voice navigation never prompts on iOS despite the usage strings being declared. Set
    both to 1, or drop the feature and the strings.

22. Close the user-enumeration oracle. invite_ino_user_to_vault
    (supabase/migrations/20260901010000_family_vault_join_and_coowners.sql:199-265) resolves
    any email, phone or name against the whole users table and returns distinguishable
    USER_NOT_FOUND and MULTIPLE_USERS outcomes. Make the outcomes uniform and rate-limit.
    Check lib/data/family_vault_repository.dart for client handling of those codes.

--- GROUP 4: Low, do these last ---

23. Enable the existing ref-counted ScreenSecurityService (FLAG_SECURE) on the document
    viewer, password vault and card screens. It is currently used only at
    lib/screens/share/view_once_viewer_screen.dart:84. Also raise the app-lock overlay on
    inactive, not just paused (lib/screens/lock/app_lock.dart:82-98), without letting the
    biometric prompt lock the app against itself — extend the existing _authenticating guard.
24. Drop the vault key when the app backgrounds. VaultCrypto.lock() exists
    (lib/services/vault_crypto.dart:219-224) but is only called from session_reset.dart:80.
25. Trusted Devices is local-only and gates nothing, but the UI at
    app_localizations.dart:1465 says "devices signed in to your INO account". Make the copy
    honest. Also switch the id at lib/services/trusted_device_service.dart:135-144 from
    hashCode to Random.secure().
26. Account switching requires no re-auth (lib/screens/profile/profile_screen.dart:616-635).
    Gate it with VaultGuard.ensureUnlocked(force: true).
27. Google Sign-In has no nonce (lib/services/auth_service.dart:234-240). Add one if the
    installed google_sign_in 7.2.0 API allows it; if not, leave it and say so.
28. Correct the misleading encryption copy: app_localizations.dart:1297
    "256-BIT AES ENCRYPTION ACTIVE", :1845 "MILITARY-GRADE AES ENCRYPTION", :2330
    onboardingBody1. Only the password vault is client-side encrypted. Match the honest
    tone already used at :1378. This is a Play misleading-claims risk.
29. The wallets registry is world-readable and exposes created_by user UUIDs
    (supabase/migrations/20260727000000_per_wallet_tables.sql:96-100). Stop exposing
    created_by. Check which columns the client actually selects before changing it.
30. device_tokens UPDATE uses using(true)
    (supabase/migrations/20260727120000_device_tokens.sql:65-66). Scope it to the owner and
    use delete-then-insert for the account hand-off path.
31. Delete supabase/share_schema.sql and supabase/vault_schema.sql. The first defines
    get_document_share granted to anon returning storage paths, plus a PUBLIC bucket. They
    are paste-and-run files nobody should ever run. Neither is referenced by lib/.
32. Allow-list the MIME before OpenFilex on the recipient's device
    (lib/screens/share/shared_documents_screen.dart:161-167,
    view_once_viewer_screen.dart:251-254), and delete the temp files after use.
33. Bundle the pdf.js worker instead of loading it from unpkg
    (share-frontend/app/s/[token]/DocViewer.tsx:15, app/v/[token]/OneTimeDoc.tsx:13) and add
    a headers() block to next.config.js with CSP, nosniff, Referrer-Policy and frame-ancestors.
34. Validate deep-link and QR tokens (lib/services/deep_link_service.dart:156-176,186-200;
    lib/models/payment_qr.dart:67-79 currently treats any https://host/s/x as an INO share) and
    build URLs with Uri(pathSegments:) instead of string concatenation in
    lib/config/share_config.dart:38,63.
35. Add --obfuscate --split-debug-info to the release build and document symbol upload.
36. Guard PII logging with kDebugMode: lib/services/auth_service.dart:208 and
    account_switcher.dart:206,218 log emails.
37. Fix the offline _local fallback key that is merged into every account's library
    (lib/services/offline_document_store.dart:180,227-233,322).
38. create_document_share takes only (uuid[], integer) in
    supabase/migrations/20260704000000_document_shares.sql:127-130, but
    lib/repositories/share_repository.dart:100-105 passes p_password and p_is_view_only, so
    password-protected shares of originals fail with PGRST202. Fix the signature.
39. Use filename*=UTF-8'' in content-disposition (index.ts:473,591); non-Latin document
    names currently return 500.
40. Three tests fail because ReminderStore calls Supabase.instance and the harness never
    initialises it: test/data_isolation_test.dart and test/duplicate_username_isolation_test.dart.
    Reminder account-switch isolation is therefore untested. Fix the harness gap.
41. The lib/screens/vault/ plus VaultController plus VaultKeyStore stack is dead code, not
    imported anywhere outside its own folder. The live vault is VaultCrypto plus PasswordStore.
    Recommend whether to delete it; do not delete without asking.

--- GROUP 5: DEFERRED — these were applied once, then reverted on purpose ---

Both of these are correct fixes that were rolled back because they changed behaviour
before their prerequisites existed. Do NOT reapply either one on your own initiative.
Raise each with me when its prerequisite below is satisfied, and apply it only if I agree.

42. [DEFERRED — reapply only AFTER items 6, 7, 13 and 14 have landed]
    Android auto-backup is enabled, so app-private data is copied to Google's servers and
    to any new device the user restores onto. Today that set includes the plaintext
    password cache, the XOR-obfuscated refresh tokens, the live session, the document
    metadata cache containing full Aadhaar and PAN numbers, and the unencrypted offline
    scans. The <application> tag sets none of allowBackup, fullBackupContent or
    dataExtractionRules.
    Why it was reverted: turning backup off means app data no longer restores onto a new
    phone, so users must sign in again and lose local settings. I did not want that cost
    while the underlying secrets were still being moved into secure storage.
    Once items 6, 7, 13 and 14 land, the secrets are Keystore-backed or encrypted, and
    this becomes much less urgent — but it is still the right default for a vault app.
    FIX WHEN APPROVED: add android:allowBackup="false" plus res/xml/backup_rules.xml
    (fullBackupContent, API <= 30) and res/xml/data_extraction_rules.xml (API 31+),
    excluding the sharedpref and file domains for both cloud-backup and device-transfer.
    A narrower alternative worth proposing to me: leave backup enabled but exclude only
    the sensitive prefs and the offline_docs directory, which keeps restore working.

43. [DEFERRED — reapply only once the CI signing secrets exist]
    The release build falls back to the committed debug key with only a warning when
    android/key.properties is absent (android/app/build.gradle.kts, the release buildType).
    .github/workflows/build-apk.yml runs `flutter build apk --release` with no signing
    secrets and publishes the result as a GitHub Release with make_latest: true, so the
    published artifact is debug-signed. Anyone able to read that key can sign an APK
    Android accepts as an in-place UPDATE to a tester's install, inheriting its private
    data directory.
    Why it was reverted: making the build fail hard broke the existing CI workflow
    immediately, before the signing secrets were in place.
    FIX WHEN APPROVED: once ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD,
    ANDROID_KEY_ALIAS and ANDROID_KEY_PASSWORD exist as repository secrets and the
    workflow writes android/key.properties before building, add a
    gradle.taskGraph.whenReady guard that throws when a release assemble/bundle/package
    task is in the graph and hasReleaseSigning is false, with a -PallowDebugSignedRelease
    opt-in for local use. Put the check on the task graph, NOT in the buildTypes block:
    throwing during configuration breaks `flutter run`, debug builds and even
    `./gradlew help`. Verify all three cases: debug passes, release without a key fails,
    release with the opt-in passes.
    Note the debug keystore is already untracked and re-ignored, but it remains in git
    history, so it still needs rotating regardless of this item.

== DO NOT BREAK THESE — they were audited and are correct ==

Row-level security is owner-scoped on every table. Sign-in uses PKCE, so deep-link session
injection is already rejected. The password vault crypto is correct: AES-256-GCM, library
generated nonces, PBKDF2-HMAC-SHA256 at 210,000 iterations, 32-byte per-user salt, a verifier
rather than a stored hash, key in memory only. Every security-relevant random is Random.secure().
No CVV or full card number is stored anywhere. No real secret has ever been committed. View-once
links are consumed by a single atomic conditional UPDATE and their RPCs are service_role only.
Push senders gate on the service-role bearer with a constant-time compare. Biometrics re-prompt
every time and fail closed. Guest mode is in-memory only. UPI links are rebuilt from an
allow-list so intent://, javascript: and file:// can never reach a launcher. OCR is fully
on-device. There are no analytics, ad or tracking SDKs. Sign-out already unregisters the push
token before signOut.

== VERIFY ==

flutter analyze on files you touched.
flutter test test/vault_crypto_test.dart test/data_isolation_test.dart test/offline_protection_test.dart test/password_vault_gate_test.dart test/public_share_test.dart test/view_once_test.dart test/auth_flow_test.dart test/deep_link_test.dart test/share_test.dart test/family_vault_test.dart test/l10n_parity_test.dart test/profile_test.dart
For Gradle: export JAVA_HOME="/c/Program Files/Android/Android Studio/jbr" then
cd android && ./gradlew help -q --offline
Note the l10n parity test enforces en/hi/te key parity — every new string needs all three.

Start with Group 1 item 1. Ask me before each ASK FIRST item.
```

---

## Part 2 — Outside the code

### Deploy now (already-written fixes, currently doing nothing)

**1. Deploy the share function.** This is the only remotely exploitable hole and the fix is written but not live.

```
cd c:\Users\yashw\Downloads\INO
supabase functions deploy share --no-verify-jwt
```

Then confirm a real share link still opens, and that a malformed one returns "not found" rather than an error:

```
https://ilfzppryyojoponkomrw.functions.supabase.co/share/zz,and(status.eq.active)
```

**2. Apply the hardening migration.** Open the Supabase dashboard, go to SQL Editor, paste the whole of `supabase/migrations/20260903000000_security_hardening.sql`, and run it. It is idempotent, so running it twice is harmless. Afterwards check that creating a custom wallet in the app still works, since that path calls the functions being revoked.

### Rotate the leaked signing key

The debug keystore is no longer tracked, but untracking does not remove it from git history. Anyone who cloned the repo still has the private key, and it was used to sign the APKs published to your GitHub Releases.

Delete the old file, generate a fresh one, and tell testers to uninstall before installing the next build, since a different signing key blocks in-place updates.

```
keytool -genkey -v -keystore android/app/debug.keystore -storepass android \
  -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"
```

If the repository is public, also delete the existing GitHub Releases that contain debug-signed APKs.

### Before the package rename

Do this first, then tell the fresh session to apply rename item 3. Doing it in this order means Google Sign-In never breaks.

1. Firebase Console, your `inoapp-b0101` project, Project Settings, Add app, Android. Package name `in.inoapp.app`.
2. Get both fingerprints and add them to that app:
   ```
   keytool -list -v -keystore android/app/debug.keystore -storepass android -alias androiddebugkey
   ```
   Add the SHA-1 and SHA-256 for the debug key, and later the Play App Signing SHA-256 from Play Console once you have uploaded.
3. Download the new `google-services.json` and replace `android/app/google-services.json`.
4. Google Cloud Console, APIs and Services, Credentials. On the Android OAuth client, add package `in.inoapp.app` with the same fingerprints.
5. While there, restrict the three API keys: the Android key to package plus SHA-256, the iOS key to the bundle id, the web key to referrers.
6. Supabase Dashboard, Authentication, Providers, Google: confirm the client IDs still match.

### Host the legal pages on inoapp.in

The fresh session will generate `PRIVACY_POLICY.md`, `TERMS.md` and a deletion-request page. Publish them at:

- `https://inoapp.in/privacy`
- `https://inoapp.in/terms`
- `https://inoapp.in/delete-account`

The deletion page must let someone request deletion without installing the app. A form or a clearly stated email address is enough, and it must say what gets deleted and how long it takes.

### Fix share links opening in the browser

Share links currently open the browser instead of the app, because the verified intent filter points at a host you cannot serve files from.

1. Serve your fingerprint file at `https://inoapp.in/.well-known/assetlinks.json`, as `application/json`, over HTTPS, with no redirect.
2. Use the **Play App Signing** SHA-256 from Play Console, Setup, App signing. Not your local key. This is only available after your first upload, so this step comes after you upload the first build.
3. Verify with:
   ```
   https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://inoapp.in&relation=delegate_permission/common.handle_all_urls
   ```

### Supabase dashboard checks

**Verify the documents bucket folder policy.** This is the one item that could still be a Critical and I could not read it from the repo. Run this in the SQL Editor and check the result:

```sql
select policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'storage' and tablename = 'objects';
```

Every policy touching the `documents` bucket must be scoped to the caller's own folder, meaning a condition equivalent to `(storage.foldername(name))[1] = auth.uid()::text`. If any policy is missing that, or uses `true`, users can read each other's files. Paste the output into the fresh session and it will tell you whether it is safe.

Also confirm the `documents` bucket is **not** public: Storage, documents, Settings.

### Play Console

- **Target audience**: 18 and over. Do not opt into the Families programme.
- **Data Safety form**: fill it from the data-type list in the prompt above. Declare financial info, personal identifiers including government ID numbers, files and documents, and device identifiers. Declare voice recordings if you keep cloud speech recognition.
- **Account deletion**: give both the in-app path and `https://inoapp.in/delete-account`.
- **Privacy policy URL**: `https://inoapp.in/privacy`.
- **Exact alarm permission**: you will be asked to justify `SCHEDULE_EXACT_ALARM`. The honest justification is user-set document expiry and bill reminders that must fire at a specific time.
- **Photo permissions**: no longer needed, since the broad media permissions were removed. If the form still asks, answer that the app uses the system Photo Picker.

### CI secrets

Your CI release build currently publishes a **debug-signed** APK, which anyone holding the leaked key can use to push a trojaned "update" over a tester's install. The hard-fail guard that would prevent this was written and then reverted, so it does not protect you yet; it is item 43 in the prompt and gets reapplied once these secrets exist.

Add these repository secrets and have the workflow write `android/key.properties` before building. Until then, treat every APK on your GitHub Releases page as untrusted.

- `ANDROID_KEYSTORE_BASE64` — your upload keystore, base64 encoded
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

### Scheduled cleanup

Once the retention function is added, schedule it in the Supabase SQL Editor so notification logs do not grow forever:

```sql
select cron.schedule('prune-push-log', '0 3 * * *', $$select public.prune_push_log()$$);
```

