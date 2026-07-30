# INO — Full Codebase Documentary

> Generated 2026-07-29 from a read-only audit of the working tree (branch `main`).
> **No code was modified.** This document describes every file, flags what is no longer
> used, catalogues what can break in production, and proposes a cleanup plan.
>
> Companion docs already in the repo: [README.md](README.md) (feature/API guide),
> [DATA_ISOLATION.md](DATA_ISOLATION.md), [DEEP_LINKING.md](DEEP_LINKING.md),
> [IDENTITY_AUDIT.md](IDENTITY_AUDIT.md), [IOS_READINESS.md](IOS_READINESS.md),
> [PASSWORD_VAULT_ENCRYPTION.md](PASSWORD_VAULT_ENCRYPTION.md),
> [PRODUCTION_GOOGLE_SIGNIN.md](PRODUCTION_GOOGLE_SIGNIN.md),
> [PUSH_NOTIFICATIONS.md](PUSH_NOTIFICATIONS.md), [RELEASE_SIGNING.md](RELEASE_SIGNING.md),
> [SHARE_REDESIGN.md](SHARE_REDESIGN.md), [VIEW_ONCE_SHARING.md](VIEW_ONCE_SHARING.md).

---

## 0. Scale of the thing

| Metric | Value |
|---|---|
| Dart files | 320 |
| Dart lines | 94,195 |
| Largest single file | [lib/l10n/app_localizations.dart](lib/l10n/app_localizations.dart) — 5,071 lines |
| Largest screen | [lib/screens/wallet/document_viewer_screen.dart](lib/screens/wallet/document_viewer_screen.dart) — 1,757 lines |
| Flutter test files | 41 |
| Supabase migrations | 19 |
| Supabase Edge Functions | 2 (`share`, `send-reminder-push`) |
| Next.js web routes | 4 pages + 3 API routes |
| `dart analyze` result | **0 issues** (clean) |
| Files unreachable from `main.dart` | **30** (see §5) |

---

## 1. What INO is

### User POV — the one-paragraph version

INO is a private vault for your life's paperwork and money. You scan an Aadhaar/PAN/DL/passport
with your phone camera and the app reads the fields off it and files it in the right wallet.
You track properties, investments, cards, passwords, expenses, notes and reminders in the same
place. You get calculators (EMI, SIP, gold, area, currency). You can share a document with
someone as a QR/link that expires, can be revoked, is view-only, or self-destructs after one
view. Everything is locked behind Face ID / fingerprint, passwords are encrypted so even the
server can't read them, and you can invite family into a shared vault.

### Developer POV — the architecture

```
┌──────────────────────── Flutter app (Android/iOS) ─────────────────────────┐
│  screens/  ── UI only. No Supabase calls (with a few legacy exceptions).    │
│      ↓                                                                     │
│  services/ ── singletons: stores (notify-on-change), device capability      │
│               wrappers (camera/biometric/TTS), pure algorithms (parsers,    │
│               calculators, crypto).                                        │
│      ↓                                                                     │
│  data/ + repositories/ ── the ONLY code that talks to Supabase.            │
│      ↓                                                                     │
│  models/   ── plain Dart value objects, JSON round-trip, no Flutter deps.  │
└────────────────────────────────────────────────────────────────────────────┘
            │ PostgREST + Storage + Auth (RLS on every table)
            ▼
┌──────────────────────────────── Supabase ──────────────────────────────────┐
│  Per-wallet tables  w_identity_wallet, w_property_wallet, w_password_vault… │
│  Read-only view     public.documents  (union all of every w_* table)        │
│  Edge Functions     share (public, no JWT) · send-reminder-push (cron)      │
└────────────────────────────────────────────────────────────────────────────┘
            │ anonymous JSON + byte proxy
            ▼
┌────────────────── share-frontend (Next.js 14 on Vercel) ──────────────────┐
│  /s/[token]  standard share   ·   /v/[token]  view-once (gated)           │
│  /api/s/[token]/file/[index] and /api/v/[token]/{claim,file} proxy bytes   │
└───────────────────────────────────────────────────────────────────────────┘
```

**Three architectural rules the codebase actually follows:**

1. **Repository boundary.** Screens never build a Supabase query. `data/` and `repositories/`
   own every `.from(...)`/`.rpc(...)` call.
2. **Store singletons + `ValueNotifier`/`ChangeNotifier`.** There is no Riverpod/Bloc/Provider
   package. State is `static final X.instance` + `notifyListeners()`. This is why
   [session_reset.dart](lib/services/session_reset.dart) exists and is load-bearing.
3. **Optimistic writes.** Stores mutate in memory, notify, then persist in the background,
   swapping in the DB-generated id when the insert lands.

---

## 2. Repository map

```
INO/
├── lib/                     Flutter app (320 files)
├── test/                    41 Flutter test files
├── android/ ios/            native hosts + FLAG_SECURE / screenshot-detection channels
├── linux/ windows/ web/     scaffolded by `flutter create`, NOT maintained (see §5.4)
├── share-frontend/          Next.js recipient viewer (Vercel)
├── share-proxy/             single Cloudflare Worker (legacy alternative to the above)
├── supabase/
│   ├── functions/           share · send-reminder-push
│   ├── migrations/          19 SQL files
│   └── diagnostics/         backend_health_check.sql
├── deep-linking/            assetlinks.json template
├── docs/                    OCR_STORAGE_AUDIT.md
├── tool/                    dev scripts
├── AnimatedBottomNav.tsx    ← stray React file at repo root (see §5.4)
└── *.md                     11 feature/ops docs
```

---

## 3. File-by-file documentary

Legend for **Status**: ✅ live · ⚠️ live but has a caveat · 🔴 **not reachable from `main.dart`**
· 🧪 test/dev-only.

### 3.1 Entry point & configuration

| File | Lines | Documentary | Status |
|---|---|---|---|
| [lib/main.dart](lib/main.dart) | 232 | **User:** the app starting up. **Dev:** the boot sequence, and it is order-sensitive: Supabase init → `AccountSwitcher` → theme/biometric/settings hydration → protection store + `VaultGuard` → category/wallet stores → the four data stores in parallel → non-awaited side effects (trusted device, auto-backup, notifications, FCM, TTS warm-up) → **awaited** `captureInitialLink()` so a cold-start share link beats the splash. Builds `MaterialApp` wrapped in `InoResponsiveInit` → `InoStyleScope` → `AppLock`. | ✅ |
| [lib/firebase_options.dart](lib/firebase_options.dart) | 82 | Generated by FlutterFire. FCM/Firebase project handles. | ✅ |
| [lib/config/supabase_config.dart](lib/config/supabase_config.dart) | 39 | Project URL + publishable key + Google web/iOS client IDs, **hardcoded as `const`**. `isGoogleConfigured` guards the placeholder case. | ⚠️ iOS client ID is still `YOUR_GOOGLE_IOS_CLIENT_ID` |
| [lib/config/share_config.dart](lib/config/share_config.dart) | 56 | Two base URLs: `publicBase` (what the QR encodes → Vercel) and `apiBase` (Edge Function, derived from the project ref). `viewOncePublicBase` swaps the trailing `/s` for `/v`. | ⚠️ host mismatch with the Android App Link filter — §6.2 |
| [lib/config/demo_account.dart](lib/config/demo_account.dart) | 21 | **User:** the "Login as Guest" button on the login screen. **Dev:** hardcoded `demo@ino.app` / `DemoUser@123`, shown when `isDemoBuild == true`. | ⚠️ `isDemoBuild` is currently `true` |

### 3.2 `lib/core/responsive/` — layout scaling

| File | Lines | Documentary | Status |
|---|---|---|---|
| [responsive.dart](lib/core/responsive/responsive.dart) | 78 | Wraps `ScreenUtilInit` at a 393×852 reference canvas. Everything downstream can use `.w`/`.h`/`.sp`. Also exposes `ResponsiveBuilder`. | ✅ |
| [responsive_extensions.dart](lib/core/responsive/responsive_extensions.dart) | 55 | `BuildContext` accessors (`context.isTablet`, …) and numeric extensions. | ✅ |
| [screen_breakpoints.dart](lib/core/responsive/screen_breakpoints.dart) | 87 | `InoDeviceType` enum + dp thresholds. | ✅ |

### 3.3 `lib/models/` — value objects (25 files)

Plain Dart, no Flutter/Supabase imports. JSON round-trip. This layer is the app's contract.

| File | Lines | Documentary |
|---|---|---|
| [area_unit.dart](lib/models/area_unit.dart) | 167 | India-specific land units (Ankanam, Cent, Gunta, Marla, Kanal, Katha, Acre) defined relative to sq.ft so the conversions stay exact. |
| [card_models.dart](lib/models/card_models.dart) | 241 | `SavedCard`. **Security-by-schema:** there is no full-PAN field and no CVV field anywhere. Only `last4`. |
| [currency.dart](lib/models/currency.dart) | 139 | Currency catalogue + whether it groups Indian-style (lakh/crore) or western. |
| [dashboard_models.dart](lib/models/dashboard_models.dart) | 407 | 18 types backing the Home dashboard (`HomeHero`, `MarketQuote`, `PriorityItem`, `SmartInsight`, …). Many are only consumed by the dead `widgets/dashboard/sections/*` — see §5.1. |
| [document.dart](lib/models/document.dart) | 62 | One row of `public.documents` (the union view). |
| [document_extraction.dart](lib/models/document_extraction.dart) | 223 | OCR-extracted fields, stored as a JSON envelope **inside the existing `notes` column** to avoid a migration. Documented as a deliberate trade. |
| [document_share.dart](lib/models/document_share.dart) | 142 | Owner-side share lifecycle (`ShareStatus`, `ShareDuration`). |
| [expense_models.dart](lib/models/expense_models.dart) | 613 | Indian financial-year model + transaction/tax-document/summary types for the ITR vault. |
| [family_vault_models.dart](lib/models/family_vault_models.dart) | 511 | `VaultRole` ordered by privilege so `index` comparisons express "at least this powerful"; vault, member, invitation, audit, document types. |
| [investment_models.dart](lib/models/investment_models.dart) | 319 | Portfolio instruments. Returns are always **derived**, never stored. |
| [metal_rates.dart](lib/models/metal_rates.dart) | 102 | Live gold/silver normalised to ₹/gram with provenance, built from USD/oz + FX. |
| [note_models.dart](lib/models/note_models.dart) | 225 | Notes + categories. |
| [ocr_result_model.dart](lib/models/ocr_result_model.dart) | 163 | `IdDocumentType` — each type carries the wallet + category it should auto-file into. |
| [ocr_stage.dart](lib/models/ocr_stage.dart) | 89 | Pipeline stages with measured `weight`s, so the progress ring reflects real work instead of a timer. |
| [password_models.dart](lib/models/password_models.dart) | 145 | `PasswordEntry` = nickname (a decoy the user invents) + sealed password + consent flag. |
| [property_models.dart](lib/models/property_models.dart) | 526 | Full property register: type, status, co-owners, attachments, legal/financial fields. |
| [public_share.dart](lib/models/public_share.dart) | 100 | Recipient-side share status as reported by the Edge Function (adds `notFound`/`error`). |
| [reminder_models.dart](lib/models/reminder_models.dart) | 480 | Reminder, priority, category, grouping and summary types. |
| [scan_models.dart](lib/models/scan_models.dart) | 209 | Scanner state machine + detection confidence + `OcrResult`. |
| [share_settings.dart](lib/models/share_settings.dart) | 69 | Colour mode + options for a processed shared copy. |
| [user_profile.dart](lib/models/user_profile.dart) | 63 | One row of `public.users`. |
| [view_once_share.dart](lib/models/view_once_share.dart) | 248 | View-once peek/claim/result types. `ready` is the only non-terminal state. |
| [voice_command.dart](lib/models/voice_command.dart) | 524 | **The whole voice feature's data.** `kVoiceCommands`: each destination lists trigger phrases in English/Hinglish/Telugu/Hindi/Tamil plus a `navigate` closure. Adding a destination is a one-entry append. |
| [wallet_detail_models.dart](lib/models/wallet_detail_models.dart) | 268 | Filters, sorts, `DocumentRecord`, overview + storage analytics. |
| [wallet_models.dart](lib/models/wallet_models.dart) | 91 | Wallet Hub types. |

### 3.4 `lib/data/` — aggregate read models & repositories (9 files)

| File | Lines | Documentary | Status |
|---|---|---|---|
| [dashboard_repository.dart](lib/data/dashboard_repository.dart) | 457 | **Dev:** `DashboardRepository.instance` defaults to `SampleDashboardRepository` — i.e. **the Home dashboard aggregate is still sample data.** The live Home screen builds its own `_HomeData` from real services instead, so this is mostly a leftover contract. | ⚠️ sample impl still wired |
| [expense_repository.dart](lib/data/expense_repository.dart) | 135 | `public.expenses` + `public.tax_documents`. | ✅ |
| [family_vault_repository.dart](lib/data/family_vault_repository.dart) | 578 | Vaults, members, invitations, audit, vault documents. All mutations go through RPCs that re-check permission server-side. | ✅ |
| [notes_repository.dart](lib/data/notes_repository.dart) | 91 | `public.notes`, double-filtered by `auth_user_id` as defense-in-depth. | ✅ |
| [reminder_repository.dart](lib/data/reminder_repository.dart) | 130 | `public.reminders`. | ✅ |
| [reminder_store.dart](lib/data/reminder_store.dart) | 235 | The shared notify-on-change store behind all four reminder screens. (Note: a *store*, filed under `data/` rather than `services/` — an inconsistency.) | ⚠️ misplaced layer |
| [scan_repository.dart](lib/data/scan_repository.dart) | 89 | `MlKitScanRepository` (live) vs `SampleScanRepository` (fallback). Throws `OcrException` the processing screen catches. | ✅ |
| [wallet_detail_repository.dart](lib/data/wallet_detail_repository.dart) | 269 | One wallet's detail aggregate. | ✅ |
| [wallet_repository.dart](lib/data/wallet_repository.dart) | 292 | Wallet Hub aggregate. | ✅ |

### 3.5 `lib/repositories/` — Supabase access (6 files)

| File | Lines | Documentary |
|---|---|---|
| [document_repository.dart](lib/repositories/document_repository.dart) | 343 | The only reader/writer of wallet records. Writes go to the per-wallet table; cross-wallet reads go through the `documents` view. Bumps a `revision` notifier that `AutoBackupCoordinator` listens to. |
| [metals_repository.dart](lib/repositories/metals_repository.dart) | 109 | Wraps `MetalsApiService`, carries provenance (live / cached / error) for the UI. |
| [share_repository.dart](lib/repositories/share_repository.dart) | 470 | Creates/lists/revokes standard shares; uploads processed copies. Throws `ShareBackendNotConfiguredException` when the backend isn't deployed. |
| [user_repository.dart](lib/repositories/user_repository.dart) | 146 | The only reader/writer of `public.users`. |
| [view_once_repository.dart](lib/repositories/view_once_repository.dart) | 286 | Sender side via Supabase session + `create_view_once_share` RPC; recipient side (`peek`/`claim`/bytes) via anonymous HTTP to the Edge Function. The split is deliberate. |
| [wallet_tables.dart](lib/repositories/wallet_tables.dart) | 84 | `"Property Wallet"` → `w_property_wallet`. **Client-side twin of the DB's `ino_wallet_slug()` — the two must stay in step or writes land in the wrong table.** |

### 3.6 `lib/services/` — 68 files

The largest layer. Four distinct kinds of thing live here.

#### (a) Auth, identity, session

| File | Lines | Documentary |
|---|---|---|
| [auth_service.dart](lib/services/auth_service.dart) | 261 | Every Supabase auth call: email/password, native Google, sign-out, auth stream. |
| [account_switcher.dart](lib/services/account_switcher.dart) | 232 | Multi-account registry on one device; hot-swaps the active session. |
| [account_service.dart](lib/services/account_service.dart) | 140 | Password-strength scoring for the Change Password meter. |
| [session_reset.dart](lib/services/session_reset.dart) | 115 | **Load-bearing security code.** Wipes every singleton + user-scoped `shared_preferences` key on sign-out. The client half of data isolation; RLS is the server half. |
| [guest_mode.dart](lib/services/guest_mode.dart) | 134 | In-memory "explore without an account" flag; `requireAuth` funnels every real action into the sign-in sheet. |
| [two_factor_service.dart](lib/services/two_factor_service.dart) | 106 | Supabase MFA TOTP enrollment/verify/unenroll. |
| [trusted_device_service.dart](lib/services/trusted_device_service.dart) | 176 | Local registry of devices this install has seen. |
| [biometric_service.dart](lib/services/biometric_service.dart) | 263 | `local_auth` wrapper: capability detection, normalised error taxonomy, persisted lock preference. |
| [vault_guard.dart](lib/services/vault_guard.dart) | 79 | 2-minute session gate for *specific* sensitive actions, independent of the whole-app lock. Invalidated on background. |
| [vault_crypto.dart](lib/services/vault_crypto.dart) | 238 | **Zero-knowledge crypto.** PBKDF2-HMAC-SHA256, 210k iterations, per-user salt in `vault_keys`, AES-GCM seal. Passphrase never stored or transmitted. |
| [document_protection_store.dart](lib/services/document_protection_store.dart) | 63 | Set of document IDs requiring biometric unlock. |
| [screen_security_service.dart](lib/services/screen_security_service.dart) | 147 | MethodChannel `ino/secure_screen`. Android: real `FLAG_SECURE`. iOS: capture-notification observers (detection, not prevention). |

#### (b) Stores — the app's state layer

| File | Lines | Documentary |
|---|---|---|
| [local_collection_store.dart](lib/services/local_collection_store.dart) | 327 | The base class for Property/Investment/Card/Password stores. `shared_preferences` is the per-user local cache; a store that sets `syncTable` is additionally backed by its `w_*` table (which then becomes truth). One-time upload of pre-sync records. |
| [property_store.dart](lib/services/property_store.dart) | 213 | → `w_property_wallet`. |
| [investment_store.dart](lib/services/investment_store.dart) | 167 | → `w_investment_wallet`. Every aggregate derived, never persisted. |
| [card_store.dart](lib/services/card_store.dart) | 145 | → `w_cards_wallet`. `last4` carries a `^[0-9]{4}$` DB check constraint. |
| [password_store.dart](lib/services/password_store.dart) | 185 | → `w_password_vault`, ciphertext only. Nickname is plaintext-by-design (hence the decoy-name rule). |
| [expense_store.dart](lib/services/expense_store.dart) | 402 | ITR transaction vault; optimistic writes; works in memory when signed out. |
| [notes_store.dart](lib/services/notes_store.dart) | 326 | `public.notes` with a legacy `shared_preferences` fallback and a one-shot migration of old local notes. |
| [family_vault_store.dart](lib/services/family_vault_store.dart) | 247 | Vault list + loading/error state; `clear()` wired into `SessionReset`. |
| [offline_document_store.dart](lib/services/offline_document_store.dart) | 259 | Documents pinned for offline viewing; zero-network read path. |
| [category_store.dart](lib/services/category_store.dart) | 231 | Custom document categories. Icons are a **fixed const catalogue** so the icon font still tree-shakes. |
| [wallet_store.dart](lib/services/wallet_store.dart) | 218 | `CustomWalletStore` — user-created wallets; same const-icon discipline. |
| [app_settings.dart](lib/services/app_settings.dart) | 193 | Locally-persisted preferences as `ValueNotifier`s (push, auto-backup, language, currency, quick-menu, last backup). |
| [notification_center.dart](lib/services/notification_center.dart) | 228 | In-app notification feed derived from app state, with unread tracking. |

#### (c) Scan / OCR pipeline

| File | Lines | Documentary |
|---|---|---|
| [document_scanner_service.dart](lib/services/document_scanner_service.dart) | 58 | ML Kit document scanner — **Android-only**, presents its own full-screen UI. Primary capture path. |
| [scanner_screen.dart's partner] [live_document_detector.dart](lib/services/live_document_detector.dart) | 118 | Real-time camera-stream signal driving the "Document Detected" badge. |
| [camera_permission_service.dart](lib/services/camera_permission_service.dart) | 36 | Normalised camera-permission outcome. |
| [gallery_import_service.dart](lib/services/gallery_import_service.dart) | 33 | `image_picker` wrapper. |
| [pdf_import_service.dart](lib/services/pdf_import_service.dart) | 134 | `file_picker` + validation; user-safe exception messages. |
| [document_crop_service.dart](lib/services/document_crop_service.dart) | 99 | Real 4-corner perspective rectification via `img.copyRectify`, run in a **background isolate**, capped dimension. |
| [image_enhancer.dart](lib/services/image_enhancer.dart) | 500 | The WhatsApp/Adobe-Scan filter set (`ScanColorMode`) + `optimizeForPdf`. |
| [ocr_service.dart](lib/services/ocr_service.dart) | 676 | The pipeline. Multi-pass, region-based, reports each `OcrStage` to the UI. |
| [ocr_text_utils.dart](lib/services/ocr_text_utils.dart) | 143 | Stop-word lists and text normalisation shared by the parsers. |
| [document_detector.dart](lib/services/document_detector.dart) | 76 | Decides *which* ID type the text is, with a 0–1 confidence. |
| [aadhaar_parser.dart](lib/services/aadhaar_parser.dart) | 434 | The most defensive parser: Levenshtein-fuzzy rejection of garbled headers, "name = line above DOB", fuzzy DOB labels (`DOB`/`DO8`/`D0B`). |
| [pan_parser.dart](lib/services/pan_parser.dart) | 68 | `ABCDE1234F` + label-anchored name/father's name. |
| [driving_license_parser.dart](lib/services/driving_license_parser.dart) | 44 | DL number, Valid Till, COV codes. |
| [passport_parser.dart](lib/services/passport_parser.dart) | 53 | Letter+7 digits, DOB/expiry labels, nationality. |
| [voter_id_parser.dart](lib/services/voter_id_parser.dart) | 26 | EPIC number, elector's name, gender, DOB. |
| [receipt_parser.dart](lib/services/receipt_parser.dart) | 261 | Label-aware, deliberately conservative. **Cardinal rule documented in-file:** a long reference code (UTR/Transaction ID) must never flow into the amount. |
| [receipt_scan_service.dart](lib/services/receipt_scan_service.dart) | 119 | Turns receipt OCR into Add-Transaction suggestions. |
| [scan_pdf_service.dart](lib/services/scan_pdf_service.dart) | 65 | Multi-page scan → one A4 PDF with per-page optimisation. |
| [document_processor.dart](lib/services/document_processor.dart) | 184 | Produces the processed *shared copy* (colour mode, watermark-free) into temp storage. |
| [document_file_service.dart](lib/services/document_file_service.dart) | 59 | Storage download + on-disk temp cache keyed by object path. |

#### (d) Finance, market data, calculators

| File | Lines | Documentary |
|---|---|---|
| [emi_calculator_service.dart](lib/services/emi_calculator_service.dart) | 53 | Offline EMI maths. |
| [sip_calculator_service.dart](lib/services/sip_calculator_service.dart) | 51 | Offline SIP projection. |
| [gold_calculator_service.dart](lib/services/gold_calculator_service.dart) | 86 | Weight unit × purity × rate. |
| [gold_price_service.dart](lib/services/gold_price_service.dart) | 53 | 24K/gram quote with live-vs-placeholder provenance. |
| [metals_api_service.dart](lib/services/metals_api_service.dart) | 207 | Typed error taxonomy over the metals API. |
| [market_rates_service.dart](lib/services/market_rates_service.dart) | 153 | Two **free, keyless** public APIs (gold-api.com + frankfurter). Best-effort: failures fall back silently. Petrol/diesel are still static fallbacks. |
| [currency_rate_service.dart](lib/services/currency_rate_service.dart) | 342 | Shipped **indicative** rate table — editable in the UI, not a live feed. |
| [property_valuation_service.dart](lib/services/property_valuation_service.dart) | 58 | Area × rate, profit/loss vs purchase price. |
| [area_conversion_service.dart](lib/services/area_conversion_service.dart) | 114 | The single source of area maths; widgets never compute a factor. |
| [net_worth_service.dart](lib/services/net_worth_service.dart) | 182 | Ranges, points, allocation model behind the net-worth chart. |
| [tax_summary_pdf.dart](lib/services/tax_summary_pdf.dart) | 105 | ITR summary PDF. Uses `"Rs."` because the built-in PDF fonts have no ₹ glyph. |

#### (e) Sharing, sync, backup, misc

| File | Lines | Documentary |
|---|---|---|
| [deep_link_service.dart](lib/services/deep_link_service.dart) | 201 | Cold-start capture (before first frame) + warm stream. Routes `/s/` → `SharedDocumentsScreen`, `/v/` → gated `ViewOnceViewerScreen`. |
| [push_service.dart](lib/services/push_service.dart) | 409 | FCM is **transport only**; reminders live in Supabase and the cron Edge Function decides who's due. Registers device token into `device_tokens`, re-stamped with `auth_user_id` on each sign-in. |
| [backup_service.dart](lib/services/backup_service.dart) | 110 | Cloud backup objects under `<uid>/backups/`. |
| [auto_backup_coordinator.dart](lib/services/auto_backup_coordinator.dart) | 52 | Debounced backup on `DocumentRepository.revision` change, when enabled. |
| [data_export_service.dart](lib/services/data_export_service.dart) | 140 | Full account archive as JSON, written to temp and shareable. |
| [storage_stats_service.dart](lib/services/storage_stats_service.dart) | 69 | Real Storage usage snapshot. |
| [global_search_service.dart](lib/services/global_search_service.dart) | 191 | Cross-entity search (`SearchHit` carries its routing target). |
| [activity_service.dart](lib/services/activity_service.dart) | 138 | Builds the Recent Activity feed from real events. Returns empty rather than inventing rows. | 🔴 **only consumer is the dead `activity_history_screen.dart`** |
| [voice_manager.dart](lib/services/voice_manager.dart) | 216 | **The one owner of the one `FlutterTts`.** Exists because two separate instances + speaking on the first frame caused duplicate speech during the native TTS cold-start bind. |
| [voice_greeting_service.dart](lib/services/voice_greeting_service.dart) | 123 | Once-per-session greeting with a **synchronous** guard flip before any async work. |
| [voice_nav.dart](lib/services/voice_nav.dart) | 48 | Navigation via the root navigator key + `ShellController`, so a spoken command works from anywhere. |
| [voice_navigation_service.dart](lib/services/voice_navigation_service.dart) | 325 | The mic session lifecycle + fuzzy phrase matching. |

### 3.7 `lib/screens/` — 91 files

#### Onboarding & auth (14)

| File | Lines | User POV | Dev POV |
|---|---|---|---|
| [splash/splash_screen.dart](lib/screens/splash/splash_screen.dart) | 280 | Logo pops in, dissolves into onboarding. | One 2.6s controller, phases via `Interval` slices. |
| [onboarding/onboarding_screen.dart](lib/screens/onboarding/onboarding_screen.dart) | 693 | 3 swipeable intro slides. | |
| [onboarding/onboarding_icon.dart](lib/screens/onboarding/onboarding_icon.dart) | 204 | The animated hero badge. | Per-slide reveal choreography; `OverflowBox` so the flare doesn't change layout. |
| [onboarding/floating_satellites.dart](lib/screens/onboarding/floating_satellites.dart) | 181 | Little chips orbiting the icon. | |
| [onboarding/secured_intro_screen.dart](lib/screens/onboarding/secured_intro_screen.dart) | 687 | Padlock assembles, "Get Started". | Routes by session: signed-in → shell, else → `GuestMode` + Home. |
| [auth/login_screen.dart](lib/screens/auth/login_screen.dart) | 637 | Email/phone + password, Google, guest. | |
| [auth/signup_screen.dart](lib/screens/auth/signup_screen.dart) | 331 | Create account. | Routes to OTP if the project requires email confirmation. |
| [auth/otp_verification_screen.dart](lib/screens/auth/otp_verification_screen.dart) | 281 | 6-box code entry. | Backend-agnostic — pure callbacks. |
| [auth/phone_login_screen.dart](lib/screens/auth/phone_login_screen.dart) | 424 | Country picker + phone OTP. | |
| [auth/forgot_password_screen.dart](lib/screens/auth/forgot_password_screen.dart) | 277 | Reset request + calm confirmation. | |
| [auth/complete_profile_screen.dart](lib/screens/auth/complete_profile_screen.dart) | 274 | Fills the gaps Google sign-in leaves (phone). | |
| [auth/biometric_setup_screen.dart](lib/screens/auth/biometric_setup_screen.dart) | 259 | Optional Face ID/fingerprint opt-in. | |
| [auth/auth_flow.dart](lib/screens/auth/auth_flow.dart) | 108 | — | `goToShell` + a re-entrancy guard so two callers can't push the shell twice. Clears `GuestMode`. |
| [auth/auth_validators.dart](lib/screens/auth/auth_validators.dart) | 78 | — | Localised, pure validators shared by Login/Signup/Forgot. |

#### Shell & lock (4)

| File | Lines | Documentary |
|---|---|---|
| [shell/main_shell.dart](lib/screens/shell/main_shell.dart) | 337 | `IndexedStack` of Home · Wallet · Scan · Reminders · Profile behind the custom nav bar, voice mic floating. |
| [shell/shell_controller.dart](lib/screens/shell/shell_controller.dart) | 12 | A single `ValueNotifier<int>` so pushed routes can switch tabs. |
| [shell/placeholder_tab.dart](lib/screens/shell/placeholder_tab.dart) | 131 | "Coming soon" destination kept so every tab routes somewhere real. |
| [lock/app_lock.dart](lib/screens/lock/app_lock.dart) | 353 | Wraps the whole app via `MaterialApp.builder`. Locks on cold start and on every foreground return. Completely inert when disabled. |

#### Home & overview (8)

| File | Lines | Documentary | Status |
|---|---|---|---|
| [home/home_screen.dart](lib/screens/home/home_screen.dart) | 665 | The live Home: real-data hero + market snapshot + quick actions + six finance tools. Builds its own `_HomeData`. | ✅ |
| [home/pending_actions_screen.dart](lib/screens/home/pending_actions_screen.dart) | 225 | Due reminders + expiring documents in one list. | ✅ |
| [home/activity_history_screen.dart](lib/screens/home/activity_history_screen.dart) | 226 | Full activity feed with filters and pull-to-refresh. | 🔴 **no route in** |
| [home/protection_center_screen.dart](lib/screens/home/protection_center_screen.dart) | 283 | Security score, device protections, coverage. | 🔴 **no route in** |
| [assets/assets_screen.dart](lib/screens/assets/assets_screen.dart) | 424 | Total asset value + breakdown by class. | ✅ |
| [networth/net_worth_analytics_screen.dart](lib/screens/networth/net_worth_analytics_screen.dart) | 298 | Multi-range trend + donut + growth. | ✅ |
| [markets/markets_screen.dart](lib/screens/markets/markets_screen.dart) | 123 | Gold/silver/fuel list. | ⚠️ fuel rates indicative |
| [notifications/notifications_screen.dart](lib/screens/notifications/notifications_screen.dart) | 213 | Categorised feed, unread tracking, swipe-dismiss. | ✅ |

#### Wallet & documents (10)

| File | Lines | Documentary |
|---|---|---|
| [wallet/wallet_screen.dart](lib/screens/wallet/wallet_screen.dart) | 696 | The Wallet Hub — a launcher, not a dashboard. Compact header, search bar, one summary card, the grid. |
| [wallet/wallet_detail_screen.dart](lib/screens/wallet/wallet_detail_screen.dart) | 1061 | One reusable document-manager screen for *every* wallet; only the repository data changes. |
| [wallet/document_viewer_screen.dart](lib/screens/wallet/document_viewer_screen.dart) | **1757** | The single biggest screen. File-kind detection, image/PDF/other rendering, extracted-field panel, protection gate, share entry points, Family-Vault share, edit/delete. Returns a `DocumentViewerResult` describing what changed. |
| [wallet/document_search_delegate.dart](lib/screens/wallet/document_search_delegate.dart) | 172 | Global document search backed by `DocumentRepository`. |
| [documents/add_document_screen.dart](lib/screens/documents/add_document_screen.dart) | **1598** | The upload funnel: source picker (camera/scan/gallery/PDF), details form, category/wallet selection, protection toggle, consent, save. |
| [documents/offline_documents_screen.dart](lib/screens/documents/offline_documents_screen.dart) | 347 | Zero-network library; images in-app, other types via the OS default app. |
| [search/global_search_screen.dart](lib/screens/search/global_search_screen.dart) | 350 | Live search across documents/reminders/categories/tags with recents. |
| [legal/legal_document_screen.dart](lib/screens/legal/legal_document_screen.dart) | 138 | Generic heading+body renderer for T&C / Privacy. |
| [cards/cards_wallet_screen.dart](lib/screens/cards/cards_wallet_screen.dart) | 743 | Cards rendered as cards; tap expands an inline action row. Copy copies the last four — a full number was never captured. |
| [cards/card_form_screen.dart](lib/screens/cards/card_form_screen.dart) | 460 | Deliberately incomplete form: last-4 only, no CVV field. Live card-face preview. |

#### Property, investments, passwords (9)

| File | Lines | Documentary |
|---|---|---|
| [property/property_wallet_screen.dart](lib/screens/property/property_wallet_screen.dart) | 765 | Portfolio hero + searchable/filterable property cards. |
| [property/property_form_screen.dart](lib/screens/property/property_form_screen.dart) | 1209 | Six-section form (Basics/Location/Ownership/Legal/Financial/Notes). Only the name is required. |
| [property/property_detail_screen.dart](lib/screens/property/property_detail_screen.dart) | 731 | Live dashboard per property; empty sections are omitted. |
| [property/area_converter_screen.dart](lib/screens/property/area_converter_screen.dart) | 318 | Pure calculator — touches no documents. |
| [investments/investment_wallet_screen.dart](lib/screens/investments/investment_wallet_screen.dart) | 1201 | Overview / Holdings / Activity tabs with an animated allocation ring. |
| [investments/investment_form_screen.dart](lib/screens/investments/investment_form_screen.dart) | 565 | Form adapts to instrument type; live P/L preview. |
| [passwords/password_vault_screen.dart](lib/screens/passwords/password_vault_screen.dart) | 583 | Nicknames only. Entire screen gated behind `VaultGuard`; nothing renders until authenticated. |
| [passwords/password_form_screen.dart](lib/screens/passwords/password_form_screen.dart) | 610 | Nickname + password + strength meter + generator; consent sheet on every save. |
| [passwords/vault_passphrase_sheet.dart](lib/screens/passwords/vault_passphrase_sheet.dart) | 283 | Sets up/unlocks the passphrase. The blunt "there is no reset" copy is part of the security design. |

#### Expenses / tax (5), Notes (2), Reminders (4)

| File | Lines | Documentary |
|---|---|---|
| [expenses/expense_dashboard_screen.dart](lib/screens/expenses/expense_dashboard_screen.dart) | 726 | ITR transaction vault by financial year. |
| [expenses/add_expense_screen.dart](lib/screens/expenses/add_expense_screen.dart) | 1316 | Add/edit a transaction; attaching a receipt runs OCR and pre-fills amount/date/vendor. |
| [expenses/transaction_details_screen.dart](lib/screens/expenses/transaction_details_screen.dart) | 432 | Read-only detail + receipt render + share. |
| [expenses/tax_records_screen.dart](lib/screens/expenses/tax_records_screen.dart) | 416 | Form 16 / 26AS / AIS / TDS / proofs filed by FY. |
| [expenses/tax_summary_screen.dart](lib/screens/expenses/tax_summary_screen.dart) | 313 | Summary + PDF export. |
| [notes/notes_screen.dart](lib/screens/notes/notes_screen.dart) | 755 | Grid/list, search, pin, favourite, archive. |
| [notes/note_editor_screen.dart](lib/screens/notes/note_editor_screen.dart) | 450 | Create/edit one note. |
| [reminders/reminders_screen.dart](lib/screens/reminders/reminders_screen.dart) | 686 | Deliberately short home: 2×2 summary → filters → Today's Priorities (≤4) → one row out. |
| [reminders/all_reminders_screen.dart](lib/screens/reminders/all_reminders_screen.dart) | 218 | Time-bucketed full list. |
| [reminders/reminder_calendar_screen.dart](lib/screens/reminders/reminder_calendar_screen.dart) | 147 | Month view with dotted days. |
| [reminders/completed_reminders_screen.dart](lib/screens/reminders/completed_reminders_screen.dart) | 160 | Read-only history with restore. |

#### Scan flow (8)

| File | Lines | Documentary |
|---|---|---|
| [scan/scan_flow_screen.dart](lib/screens/scan/scan_flow_screen.dart) | 387 | The orchestrator: native scanner → review → OCR → wallet pick → result. Returns a `ScanFlowResult`. |
| [scan/scanner_screen.dart](lib/screens/scan/scanner_screen.dart) | 899 | In-app camera fallback with the live detection state machine. |
| [scan/scan_review_screen.dart](lib/screens/scan/scan_review_screen.dart) | 755 | Page review, colour mode, reorder, crop entry. Commits to dark chrome in both themes so capture reads as one experience. |
| [scan/document_crop_editor.dart](lib/screens/scan/document_crop_editor.dart) | 332 | Four draggable corners → real perspective correction. |
| [scan/ocr_processing_screen.dart](lib/screens/scan/ocr_processing_screen.dart) | 458 | Stage checklist driven by the **real** pipeline (replaced a fake 2.2s ring). |
| [scan/ocr_result_screen.dart](lib/screens/scan/ocr_result_screen.dart) | 702 | Editable extracted fields + detection badge + category creation. |
| [scan/scan_wallet_screen.dart](lib/screens/scan/scan_wallet_screen.dart) | 433 | "Where should this go?" — skipped when the scan started inside a wallet. |
| [scan/scan_theme.dart](lib/screens/scan/scan_theme.dart) | 41 | Scanner-only tokens, scoped so the global theme stays untouched. |

#### Sharing (7)

| File | Lines | Documentary | Status |
|---|---|---|---|
| [share/share_settings_screen.dart](lib/screens/share/share_settings_screen.dart) | 897 | The current share entry point: mode (standard / view-once / view-only), colour mode, expiry, password. | ✅ |
| [share/qr_share_screen.dart](lib/screens/share/qr_share_screen.dart) | 696 | The generated standard share: QR, live expiry ticker, copy/share/download/revoke. | ✅ |
| [share/view_once_share_screen.dart](lib/screens/share/view_once_share_screen.dart) | 743 | Sender side of a one-time link + live "opened yet?" indicator. | ✅ |
| [share/view_once_viewer_screen.dart](lib/screens/share/view_once_viewer_screen.dart) | 849 | Recipient side. Two phases: non-consuming `peek` gate, then `claim` burns it. **Loading the screen must never spend the view.** | ✅ |
| [share/shared_documents_screen.dart](lib/screens/share/shared_documents_screen.dart) | 560 | In-app recipient viewer for standard links (anonymous fetch, bytes proxied). | ✅ |
| [share/manage_shares_screen.dart](lib/screens/share/manage_shares_screen.dart) | 830 | Every link ever created; analytics + revoke. | ✅ |
| [share/share_config_screen.dart](lib/screens/share/share_config_screen.dart) | 527 | The **older** duration-picker share screen. Superseded by `share_settings_screen`. | 🔴 **no route in** (only a test imports it) |

#### Profile & settings (10)

| File | Lines | Documentary |
|---|---|---|
| [profile/profile_screen.dart](lib/screens/profile/profile_screen.dart) | **1500** | The settings hub. ~20 rows in grouped inset lists, each with its own accent hue so rows read as landmarks. Hosts theme/style/language pickers, storage card, account switcher, sign-out. |
| [profile/edit_profile_screen.dart](lib/screens/profile/edit_profile_screen.dart) | 287 | Name + phone; email read-only. |
| [profile/change_password_screen.dart](lib/screens/profile/change_password_screen.dart) | 224 | Verifies current, scores new, updates. |
| [profile/two_factor_screen.dart](lib/screens/profile/two_factor_screen.dart) | 436 | Full TOTP enrol → verify → enabled flow. |
| [profile/trusted_devices_screen.dart](lib/screens/profile/trusted_devices_screen.dart) | 178 | Device list + forget. |
| [profile/cloud_backup_screen.dart](lib/screens/profile/cloud_backup_screen.dart) | 305 | Manual backup with progress + restore list. |
| [profile/delete_account_screen.dart](lib/screens/profile/delete_account_screen.dart) | 182 | High-friction: warning → type-to-confirm → re-auth → purge. |
| [profile/help_center_screen.dart](lib/screens/profile/help_center_screen.dart) | 229 | FAQs held as translation keys; English tags kept as search aliases. |
| [profile/contact_support_screen.dart](lib/screens/profile/contact_support_screen.dart) | 187 | Composes an email via the device mail app — no backend table needed. |
| [profile/about_screen.dart](lib/screens/profile/about_screen.dart) | 180 | Real version/build from `package_info_plus`. |

#### Family vault (4)

| File | Lines | Documentary |
|---|---|---|
| [family/family_vault_screen.dart](lib/screens/family/family_vault_screen.dart) | 787 | Vault list + pending invites + create sheet. |
| [family/vault_detail_screen.dart](lib/screens/family/vault_detail_screen.dart) | 1471 | Members, roles, invitations, audit trail, vault documents. Every mutation re-checked server-side by RPC. |
| [family/invite_member_sheet.dart](lib/screens/family/invite_member_sheet.dart) | 327 | Invite by email/phone with a role. |
| [family/add_vault_document_sheet.dart](lib/screens/family/add_vault_document_sheet.dart) | 378 | Two routes in: grant an existing document (no copy — so withdrawal truly revokes) or upload fresh. |

#### Finance tools (7)

| File | Lines | Documentary |
|---|---|---|
| [property_finance/finance_tools.dart](lib/screens/property_finance/finance_tools.dart) | 97 | **The registry.** Single source of truth for both the hub grid and Home's Quick Tools row — adding a calculator is a one-line append. |
| [property_finance/property_finance_tools_screen.dart](lib/screens/property_finance/property_finance_tools_screen.dart) | 78 | The 2-column hub, driven entirely by that registry. |
| [property_finance/emi_calculator_screen.dart](lib/screens/property_finance/emi_calculator_screen.dart) | 130 | EMI. |
| [property_finance/sip_calculator_screen.dart](lib/screens/property_finance/sip_calculator_screen.dart) | 117 | SIP. |
| [property_finance/gold_calculator_screen.dart](lib/screens/property_finance/gold_calculator_screen.dart) | 149 | Gold value. |
| [property_finance/property_valuation_screen.dart](lib/screens/property_finance/property_valuation_screen.dart) | 237 | Area × rate → value, ± purchase price. |
| [property_finance/currency_calculator_screen.dart](lib/screens/property_finance/currency_calculator_screen.dart) | 643 | Pair + **editable** rate + all-currencies summary. |

### 3.8 `lib/widgets/` — 106 files

#### Design-system primitives (`widgets/` root + `common/`)

| File | Lines | Documentary |
|---|---|---|
| [pressable_scale.dart](lib/widgets/pressable_scale.dart) | 50 | The tactile "squish". Uses `Listener`, not `GestureDetector`, so it observes without consuming — the inner button still ripples. |
| [directional_reveal.dart](lib/widgets/directional_reveal.dart) | 57 | Axis wipe reveal (chart draws L→R, QR builds T→B). |
| [floating_particles.dart](lib/widgets/floating_particles.dart) | 112 | One `CustomPaint` in a `RepaintBoundary` — drift never rebuilds the tree above. |
| [soft_glow.dart](lib/widgets/soft_glow.dart) | 57 | Radial halo behind the logo, isolated in its own `AnimatedBuilder`. |
| [ino_logo.dart](lib/widgets/ino_logo.dart) | 62 | **Explicitly a placeholder** — swap the inner `Stack` for `Image.asset('assets/logo.png')` and every screen updates. |
| [common/ino_background.dart](lib/widgets/common/ino_background.dart) | 230 | The signature teal aurora backdrop; pointer-transparent, repaint-isolated. |
| [common/ino_buttons.dart](lib/widgets/common/ino_buttons.dart) | 144 | `PrimaryButton` / `SecondaryButton`. |
| [common/shiny_icon.dart](lib/widgets/common/shiny_icon.dart) | 333 | The glossy badge primitive used everywhere. |
| [common/shiny_border.dart](lib/widgets/common/shiny_border.dart) | 105 | The *soft* theme's glass sheen, painted over the classic border. Pure overlay. |
| [common/illustration_badge.dart](lib/widgets/common/illustration_badge.dart) | 93 | Vector-style empty-state illustration — no image assets shipped. |
| [common/floating_search_bar.dart](lib/widgets/common/floating_search_bar.dart) | 91 | Launcher mode (`onTap`) or live field (`controller`). |
| [common/save_consent_sheet.dart](lib/widgets/common/save_consent_sheet.dart) | 126 | The consent gate every wallet record passes through; records the `consent` column. |

#### Auth widgets (5)
`auth_scaffold` (shared chrome for the whole auth flow), `auth_primary_button`, `auth_text_field`,
`otp_input` (auto-advance, backspace-steps-back, paste-distributes), `social_auth_button`.

#### Shell (4)

| File | Lines | Documentary |
|---|---|---|
| [shell/ino_bottom_nav.dart](lib/widgets/shell/ino_bottom_nav.dart) | **1028** | The custom nav bar + the "+" scan menu + the radial quick wheel. Labels are translation keys so the `tabs` table stays `const`. |
| [shell/quick_actions.dart](lib/widgets/shell/quick_actions.dart) | 127 | The catalogue of features the "+" menu can surface. |
| [shell/quick_menu_editor.dart](lib/widgets/shell/quick_menu_editor.dart) | 211 | Pick up to 5; selection order = menu order; persists immediately. |
| [shell/feature_tour.dart](lib/widgets/shell/feature_tour.dart) | 308 | First-run spotlight tour. |

#### Home widgets (10)

| File | Lines | Documentary | Status |
|---|---|---|---|
| [home/dashboard_card.dart](lib/widgets/home/dashboard_card.dart) | 715 | "Today's Overview" hero — drifting blobs, wave, bobbing mascot, four pastel tiles. All painted, no assets. | ✅ |
| [home/market_card.dart](lib/widgets/home/market_card.dart) | 284 | Gold & silver on one shared grid. | ✅ |
| [home/net_worth_chart.dart](lib/widgets/home/net_worth_chart.dart) | 341 | Range selector + draw-in + tap-to-inspect. Pure `CustomPaint`, no chart package. | ✅ |
| [home/voice_mic_button.dart](lib/widgets/home/voice_mic_button.dart) | 537 | The mic + the voice command sheet. Matched destination navigates itself. | ✅ |
| [home/quick_action_button.dart](lib/widgets/home/quick_action_button.dart) | 69 | Round action pill. | ✅ |
| [home/empty_state.dart](lib/widgets/home/empty_state.dart) | 94 | `EmptyState` + `ErrorRetry`. | ✅ |
| [home/skeletons.dart](lib/widgets/home/skeletons.dart) | 161 | `Shimmer`, `SkeletonBox`, `DashboardSkeleton`. | ✅ |
| [home/activity_tile.dart](lib/widgets/home/activity_tile.dart) | 97 | Recent-activity row. | 🔴 |
| [home/floating_menu.dart](lib/widgets/home/floating_menu.dart) | 127 | Bottom-sheet quick-add grid. | 🔴 |
| [home/priority_card.dart](lib/widgets/home/priority_card.dart) | 98 | Priority-centre card. | 🔴 |

#### Dashboard sections — **the whole `sections/` folder is dead**

| File | Lines | Documentary | Status |
|---|---|---|---|
| [dashboard/ino_card.dart](lib/widgets/dashboard/ino_card.dart) | 65 | Surface primitive. | ✅ |
| [dashboard/section_header.dart](lib/widgets/dashboard/section_header.dart) | 86 | Section title + "See all". | ✅ |
| [dashboard/fade_slide_in.dart](lib/widgets/dashboard/fade_slide_in.dart) | 62 | Staggered entrance. | ✅ |
| [dashboard/sparkline.dart](lib/widgets/dashboard/sparkline.dart) | 118 | Mini trend line. | ✅ |
| [dashboard/expandable_fab.dart](lib/widgets/dashboard/expandable_fab.dart) | 252 | Fan-out FAB. | ✅ |
| [dashboard/welcome_header.dart](lib/widgets/dashboard/welcome_header.dart) | 307 | Greeting bar. | ✅ |
| [dashboard/donut_chart.dart](lib/widgets/dashboard/donut_chart.dart) | 115 | Allocation donut. | 🔴 (only the dead `investment_section` uses it) |
| [dashboard/sections/](lib/widgets/dashboard/sections/) — 10 files | 1,749 | Sections 2–13 of an **earlier Home design**: market, life-overview, priority, quick-actions, wallet, investment, property/health/insurance snapshots, family, activity, insights. | 🔴 **all 10 unreachable** |

#### Wallet & wallet-detail widgets (22)

| File | Lines | Documentary | Status |
|---|---|---|---|
| [wallet/wallet_grid.dart](lib/widgets/wallet/wallet_grid.dart) | 522 | The hub grid incl. the "+ add wallet" dashed card. | ✅ |
| [wallet/create_wallet_sheet.dart](lib/widgets/wallet/create_wallet_sheet.dart) | 389 | Name + icon + colour → persisted `CustomWallet`. | ✅ |
| [wallet/wallet_header.dart](lib/widgets/wallet/wallet_header.dart) | 169 | Old hub header. | 🔴 |
| [wallet/wallet_overview_card.dart](lib/widgets/wallet/wallet_overview_card.dart) | 300 | Old glassmorphism hero. | 🔴 |
| [wallet/recent_items.dart](lib/widgets/wallet/recent_items.dart) | 133 | Old recents list. | 🔴 |
| [wallet/security_center.dart](lib/widgets/wallet/security_center.dart) | 268 | Old security-score ring. | 🔴 |
| [wallet_detail/document_card.dart](lib/widgets/wallet_detail/document_card.dart) | 411 | The workhorse row: tap → viewer, ⋮/swipe-left → actions, swipe-right → favourite. Masks Aadhaar as `XXXX XXXX 1234`. | ✅ |
| [wallet_detail/wallet_header.dart](lib/widgets/wallet_detail/wallet_header.dart) | 152 | Current compact header (auto-shrinking title). | ✅ |
| [wallet_detail/wallet_summary_card.dart](lib/widgets/wallet_detail/wallet_summary_card.dart) | 180 | 3-fact stat strip. | ✅ |
| [wallet_detail/search_section.dart](lib/widgets/wallet_detail/search_section.dart) | 127 | Pinned sliver search. | ✅ |
| [wallet_detail/document_filter_bar.dart](lib/widgets/wallet_detail/document_filter_bar.dart) | 99 | Current status chips. | ✅ |
| [wallet_detail/smart_banner.dart](lib/widgets/wallet_detail/smart_banner.dart) | 108 | One attention-only strip, replaces an old "AI Insights" section. | ✅ |
| [wallet_detail/document_quick_view.dart](lib/widgets/wallet_detail/document_quick_view.dart) | 219 | Peek at extracted fields without opening the file. | ✅ |
| [wallet_detail/document_skeleton.dart](lib/widgets/wallet_detail/document_skeleton.dart) | 147 | Silhouette matching a real `DocumentCard`. | ✅ |
| [wallet_detail/empty_state.dart](lib/widgets/wallet_detail/empty_state.dart) | 150 | Wallet empty state. | ✅ |
| [wallet_detail/share_to_vault_sheet.dart](lib/widgets/wallet_detail/share_to_vault_sheet.dart) | 279 | Grant (not copy) a document into a Family Vault; only editor+ vaults offered, re-checked server-side. | ✅ |
| [wallet_detail/detail_header.dart](lib/widgets/wallet_detail/detail_header.dart) | 174 | Superseded header. | 🔴 |
| [wallet_detail/detail_overview_card.dart](lib/widgets/wallet_detail/detail_overview_card.dart) | 217 | Superseded hero. | 🔴 |
| [wallet_detail/category_chips.dart](lib/widgets/wallet_detail/category_chips.dart) | 109 | Superseded chips. | 🔴 |
| [wallet_detail/filter_bar.dart](lib/widgets/wallet_detail/filter_bar.dart) | 141 | Superseded by `document_filter_bar`. | 🔴 |
| [wallet_detail/recently_accessed_row.dart](lib/widgets/wallet_detail/recently_accessed_row.dart) | 99 | Superseded recents row. | 🔴 |
| [wallet_detail/storage_analytics_card.dart](lib/widgets/wallet_detail/storage_analytics_card.dart) | 179 | Superseded analytics card. | 🔴 |
| [wallet_modules/module_kit.dart](lib/widgets/wallet_modules/module_kit.dart) | **1299** | 17 shared building blocks (sections, fields, pickers, chips, stat tiles, skeletons, success burst) behind the four data-driven wallet modules. | ✅ |

#### Remaining widget folders

| Folder | Files | Documentary |
|---|---|---|
| `widgets/reminders/` | 10 | `reminder_card` (the workhorse), detail sheet, summary card, filter chips, month calendar, add sheet, search delegate, header, empty state, completed tile. All live. |
| `widgets/scan/` | 6 | `scanner_overlay`, `scan_controls`, `scan_detection_toast`, `detection_badge`, `ocr_field_tile`, and 🔴 `scan_fail_state` (the failure UI now lives inline in `ocr_processing_screen`). |
| `widgets/profile/` | 4 | `settings_group` / `settings_row` / `settings_scaffold` (live), 🔴 `profile_header_card` (Profile now inlines `_ProfileHero`). |
| `widgets/property/` | 3 | Area conversion summary, quick converter, unit picker. All live. |
| `widgets/property_finance/` | 3 | `calc_widgets` (the calculator design kit), `currency_selector`, `tool_card`. |
| `widgets/expenses/` | 2 | `direction_toggle` (debited/credited, pulses when auto-set from OCR), `expense_widgets`. |
| `widgets/documents/` | 1 | `create_category_sheet`. |
| `widgets/markets/` | 1 | `live_metal_rates_card` — self-driving from `MetalRatesProvider`, handles loading/loaded/offline/error. |
| `widgets/security/` | 1 | `biometric_ux` — shared biometric dialogs/snackbars, pure UI. |

### 3.9 `lib/theme/` & `lib/utils/` & `lib/l10n/`

| File | Lines | Documentary |
|---|---|---|
| [theme/app_theme.dart](lib/theme/app_theme.dart) | 799 | The brand system: **#30ACB3** and a ladder of *lighter* tints only. `AppColors`, `AppGradients`, `AppShadows`, `AppBorders`, `AppPalette` (light/dark token sets), `AppTheme.lightFor/darkFor(style)`. Legacy member names kept so the whole app re-skins from this one file. |
| [theme/theme_style.dart](lib/theme/theme_style.dart) | 105 | `classic` / `bold` / `soft`, orthogonal to light/dark. `InoStyleScope` + `InoStyle` helpers (incl. the sanctioned `deepen` used by *bold*). |
| [theme/theme_controller.dart](lib/theme/theme_controller.dart) | 111 | Persisted mode + style notifiers. No state package. |
| [theme/app_dimens.dart](lib/theme/app_dimens.dart) | 89 | 8dp-grid tokens: `AppSpacing`, `AppRadius`, `AppSizes`, `AppText`, `AppIcons`. |
| [utils/indian_number_format.dart](lib/utils/indian_number_format.dart) | 111 | Lakh/crore grouping. |
| [utils/formatting.dart](lib/utils/formatting.dart) | 33 | Binary byte sizes matching how Supabase reports them. |
| [utils/date_normalizer.dart](lib/utils/date_normalizer.dart) | 107 | Normalises every OCR date shape to `DD/MM/YYYY` *after* the parsers, *before* display/save. |
| [utils/share_origin.dart](lib/utils/share_origin.dart) | 22 | `sharePositionOrigin` — `share_plus` **throws on iPad** without it, ignores it elsewhere. |
| [l10n/app_localizations.dart](lib/l10n/app_localizations.dart) | **5071** | Dependency-free key→string maps for en/hi/te/ta with English fallback. No ARB, no codegen. |

### 3.10 Backend — `supabase/`

| File | Documentary |
|---|---|
| `functions/share/index.ts` | The public, `--no-verify-jwt` Edge Function. Serves standard-share JSON metadata, proxies file bytes, and implements the **atomic view-once burn** (single `UPDATE … WHERE viewed = false RETURNING *`, minting a 5-minute `access_key`). |
| `functions/send-reminder-push/index.ts` | Cron-invoked. Queries due reminders, looks up `device_tokens`, sends via FCM using the `FCM_SERVICE_ACCOUNT` secret. |
| `migrations/20260704…document_shares` | The original share table. |
| `…20260707…share_tokens` | Opaque tokens for shares. |
| `…20260710…user_data_isolation` | **RLS across the board** — the server half of data isolation. |
| `…20260722…processed_shares` | Processed (re-rendered) shared copies. |
| `…20260724…notes_expenses` | `public.notes`, `public.expenses`, `public.tax_documents`. |
| `…20260726…expense_direction` | Adds debited/credited. |
| `…20260727000000…per_wallet_tables` | **The big one**: splits the monolithic `documents` table into `w_*` tables + a read-only union view + `create_custom_wallet()` + `ino_wallet_slug()`. |
| `…20260727120000…device_tokens` | FCM registry. |
| `…20260727140000…vault_keys` | Per-user PBKDF2 salt. |
| `…20260728…family_vaults` → `…20260732…family_vault_production` | Vaults, owner reads, create RPC, invitations, production hardening (5 migrations). |
| `…20260733000000_password_vault_simplify` | Reduces the vault row to nickname + ciphertext. |
| `…20260733000000_vault_documents` | Vault document grants. ⚠️ **same version prefix as the file above.** |
| `…20260734000000_fix_vault_document_audit` | Audit fix. |
| `…20260734000000_wallet_consent` | `consent` column. ⚠️ **same version prefix as the file above.** |
| `…20260735000000_view_once_shares` | View-once table + `create_view_once_share` RPC + the burn function. |
| `setup_wallet_tables.sql`, `verify_document_sharing.sql`, `diagnostics/backend_health_check.sql` | Manual ops scripts, not part of `db push`. |

### 3.11 Web — `share-frontend/` (Next.js 14 App Router)

| File | Documentary |
|---|---|
| `lib/config.ts` | Server-only `FUNCTIONS_URL` + `fetchShare()` + `peekViewOnce()`. The **non-consuming peek** is the mechanism that stops link-preview crawlers burning a one-time share. Falls back to a hardcoded project URL if the env var is missing. |
| `app/layout.tsx`, `app/page.tsx`, `app/globals.css` | Shell, landing, vanilla CSS with light/dark. |
| `app/s/[token]/page.tsx` | Server component: fetches metadata, decides single-doc vs folder. |
| `app/s/[token]/ShareView.tsx` | Folder layout. |
| `app/s/[token]/DocViewer.tsx` | `react-pdf` + `react-zoom-pan-pinch`, dynamically imported with `ssr:false`. |
| `app/api/s/[token]/file/[index]/route.ts` | Byte proxy; honours `mode=view\|download`; blocks download when `viewOnly`. |
| `app/v/[token]/page.tsx` | View-once entry; peeks, never claims. |
| `app/v/[token]/ViewOnceView.tsx` | The warning gate + "Open once" button. |
| `app/v/[token]/OneTimeDoc.tsx` | Post-claim renderer, holds bytes in memory. |
| `app/api/v/[token]/claim/route.ts` | POST → burns the token, returns `accessKey`. |
| `app/api/v/[token]/file/route.ts` | GET `?k=accessKey` → streams bytes. |
| `components/Brand.tsx`, `ExpiryPill.tsx`, `StatePage.tsx` | Shared UI. |
| `next.config.js` | Stubs `canvas: false` so the server build has no native dep. |

### 3.12 Native hosts

| File | Documentary |
|---|---|
| `android/app/src/main/kotlin/.../MainActivity.kt` | Hosts the `ino/secure_screen` MethodChannel → `FLAG_SECURE` on/off. |
| `android/app/src/main/AndroidManifest.xml` | Permissions (INTERNET, BIOMETRIC, POST_NOTIFICATIONS, RECORD_AUDIO, CAMERA, READ_MEDIA_IMAGES, legacy storage), plus intent filters: `https://ilfzppryyojoponkomrw.functions.supabase.co/share/*` (autoVerify), `ino://share`, `ino://viewonce`. |
| `android/app/build.gradle.kts` | `applicationId = com.example.inoapp`; release signing from git-ignored `key.properties` with a **loud warning + debug-signing fallback**; R8 minify on with custom ProGuard rules for ML Kit. |
| `ios/Runner/AppDelegate.swift` | The iOS half of `ino/secure_screen`: observes `capturedDidChangeNotification` and `userDidTakeScreenshotNotification`. |
| `ios/Runner/SceneDelegate.swift`, `Info.plist`, `Runner.entitlements` | Scene lifecycle; the five `NS*UsageDescription` strings are present; `applinks:your-share-domain` is a **placeholder**. |

### 3.13 Tests — `test/` (41 files)

Coverage is genuinely broad and weighted toward the security-critical paths:

- **Isolation / identity:** `data_isolation_test`, `duplicate_username_isolation_test`, `profile_test`, `auth_flow_test`
- **Crypto / vault:** `vault_crypto_test`, `password_vault_sync_test`
- **Sharing:** `document_share_test`, `public_share_test`, `share_settings_test`, `share_config_screen_test`, `view_once_test`, `deep_link_test`
- **OCR:** `ocr_extraction_test`, `id_parsers_test`, `document_extraction_test`, `date_normalizer_test`, `scan_flow_test`, plus two benchmarks (`ocr_perf_benchmark_test`, `ocr_substep_bench_test`)
- **Wallets/stores:** `wallet_tables_test`, `wallet_sync_mapping_test`, `wallet_modules_test`, `wallet_detail_*`, `expense_store_test`, `notes_store_test`, `reminders_test`, `family_vault_test`, `offline_protection_test`
- **UI/other:** `home_dashboard_test`, `bottom_nav_indicator_test`, `voice_command_test`, `voice_greeting_test`, `finance_calculators_test`, `metal_rates_test`, `area_conversion_service_test`, `profile_settings_test`, `widget_test`

**Gap:** nothing tests the Edge Functions or the Next.js routes. The view-once burn — the single most security-critical piece of server logic — has Dart-side tests but no server-side test.

---

## 4. Feature inventory: user POV vs developer POV

| Feature | What the user gets | What a developer must know |
|---|---|---|
| **Auth & multi-account** | Email/phone/Google sign-in; several accounts on one device; instant switching | `AuthService` + `AccountSwitcher`; `SessionReset` **must** be extended whenever a new singleton store is added, or account B sees account A's cached data |
| **App lock** | Face ID/fingerprint on launch and on every return | `AppLock` in `MaterialApp.builder`; `VaultGuard` is separate and gates *specific* actions on a 2-min session |
| **Scan & OCR** | Point camera, fields fill themselves | ML Kit scanner is **Android-only**; iOS falls back to the in-app camera. Parsers are pure Dart and unit-testable. `DateNormalizer` runs last |
| **Wallets** | 9 built-in + custom wallets, synced | One Postgres table *per wallet*; `WalletTables.slugFor` must match the DB's `ino_wallet_slug()` |
| **Password vault** | Nicknames + passwords, unrecoverable by design | PBKDF2 210k + AES-GCM client-side. **The nickname is plaintext** — the decoy-name UX copy is a security control, not a suggestion |
| **Sharing** | QR/link: expiring, revocable, view-only, or one-time | Three surfaces (`share_settings` → `qr_share` / `view_once_share`), one Edge Function, one Next.js viewer. Bytes are always proxied |
| **View-once** | Opens exactly once, then dies | Atomic SQL burn + 5-min `access_key`. `peek` never consumes. Android `FLAG_SECURE` is real protection; iOS is detection-only |
| **Family vault** | Invite family, roles, shared documents | Grants, not copies. Every mutation is an RPC that re-checks permission server-side; the UI gate is cosmetic |
| **Expenses / ITR** | Transactions + tax docs by FY, PDF summary | Optimistic store; PDF uses `"Rs."` not `₹` |
| **Reminders + push** | Due-date alerts | Reminders in Supabase; FCM is transport only; a cron Edge Function decides who's due |
| **Voice** | "Open password vault" | Add one entry to `kVoiceCommands`. One shared `FlutterTts` — never construct another |
| **Themes / i18n** | Light/dark × classic/bold/soft, 4 languages | `ThemeController` + `InoStyleScope`; l10n is hand-maintained maps, no codegen |
| **Offline** | Pinned documents readable with no network | `OfflineDocumentStore` + local file copies |

---

## 5. What is no longer used

### 5.1 Dead Dart files — 30 files, ~4,200 lines, unreachable from `main.dart`

Verified by building the full import graph from `lib/main.dart` (transitive closure over `import`/`export`/`part`).

**Group A — the previous Home dashboard design (12 files, ~2,000 lines).**
The current [home_screen.dart](lib/screens/home/home_screen.dart) builds its own layout from
`dashboard_card`, `market_card` and quick actions. The numbered "Section 2–13" widgets it
replaced are all still on disk:

```
lib/widgets/dashboard/sections/market_section.dart          244
lib/widgets/dashboard/sections/snapshot_sections.dart       288
lib/widgets/dashboard/sections/investment_section.dart      207
lib/widgets/dashboard/sections/priority_section.dart        182
lib/widgets/dashboard/sections/wallet_section.dart          156
lib/widgets/dashboard/sections/quick_actions_section.dart   150
lib/widgets/dashboard/sections/life_overview_section.dart   148
lib/widgets/dashboard/sections/family_section.dart          133
lib/widgets/dashboard/sections/insights_section.dart        132
lib/widgets/dashboard/sections/activity_section.dart        109
lib/widgets/dashboard/donut_chart.dart                      115   (only consumer: investment_section)
lib/widgets/home/priority_card.dart                          98
```

**Group B — the previous Wallet Hub / Wallet Detail design (10 files, ~1,750 lines).**

```
lib/widgets/wallet/wallet_overview_card.dart                300
lib/widgets/wallet/security_center.dart                     268
lib/widgets/wallet/wallet_header.dart                       169
lib/widgets/wallet/recent_items.dart                        133
lib/widgets/wallet_detail/detail_overview_card.dart         217
lib/widgets/wallet_detail/detail_header.dart                174
lib/widgets/wallet_detail/storage_analytics_card.dart       179
lib/widgets/wallet_detail/filter_bar.dart                   141   (superseded by document_filter_bar)
lib/widgets/wallet_detail/category_chips.dart               109
lib/widgets/wallet_detail/recently_accessed_row.dart         99
```

**Group C — orphaned screens (3 files + 1 service, ~750 lines).** These are complete, working
screens with **no entry point anywhere in the app**:

| File | Lines | Note |
|---|---|---|
| [screens/home/protection_center_screen.dart](lib/screens/home/protection_center_screen.dart) | 283 | Its own doc comment says it sits "behind the 'Protected' summary card and the 'Protect' quick action" — neither of those navigates here anymore |
| [screens/home/activity_history_screen.dart](lib/screens/home/activity_history_screen.dart) | 226 | Full activity feed |
| [services/activity_service.dart](lib/services/activity_service.dart) | 138 | Dead *only* because its single consumer is the screen above |
| [screens/share/share_config_screen.dart](lib/screens/share/share_config_screen.dart) | 527 | Superseded by `share_settings_screen`. **Still has a passing test** (`share_config_screen_test.dart`) — so the suite is green on code users can't reach |

**Group D — misc (4 files).**

```
lib/widgets/profile/profile_header_card.dart   180   (Profile inlines its own _ProfileHero)
lib/widgets/home/activity_tile.dart             97
lib/widgets/home/floating_menu.dart            127
lib/widgets/scan/scan_fail_state.dart          128   (failure UI moved inline into ocr_processing_screen)
```

### 5.2 Live-but-vestigial code

| Item | Why it's suspect |
|---|---|
| `DashboardRepository.instance = SampleDashboardRepository()` in [dashboard_repository.dart:54](lib/data/dashboard_repository.dart#L54) | 457 lines of sample-data aggregate. The live Home builds `_HomeData` itself. Whatever still reads this gets fabricated numbers. |
| `SampleScanRepository` in [scan_repository.dart:53](lib/data/scan_repository.dart#L53) | Fallback OCR path returning canned results. Fine for tests; verify it can't be selected in a release build. |
| `placeholder_tab.dart` | "Coming soon" tab — check whether any tab still lands here in the shipped nav. |
| [ino_logo.dart](lib/widgets/ino_logo.dart) | Self-described temporary placeholder mark; still the brand mark on splash/login. |
| Petrol/diesel quotes in `market_rates_service` | Hardcoded fallbacks presented next to genuinely live gold/silver. |
| `currency_rate_service` | Shipped static table; user-editable, but a stale rate looks authoritative. |

### 5.3 Duplicated concepts (not dead, but redundant)

- **Two `WalletHeader` classes** — `widgets/wallet/wallet_header.dart` (dead) and
  `widgets/wallet_detail/wallet_header.dart` (live). Same class name, different files.
- **Two `EmptyState`s** — `widgets/home/empty_state.dart` and `widgets/wallet_detail/empty_state.dart`.
- **Two filter bars** — `filter_bar.dart` (dead) and `document_filter_bar.dart` (live).
- **Two donut painters** — `dashboard/donut_chart.dart` (dead) and a `_DonutPainter` inlined in
  `net_worth_analytics_screen.dart`.
- **`data/` vs `repositories/`** — two folders doing the same job. `reminder_store.dart` (a store)
  lives in `data/` while every other store lives in `services/`.
- **Two share back-ends** — `share-frontend/` (Next.js, live) and `share-proxy/cloudflare-worker.js`
  (a single-file alternative). Only one can be the deployment.

### 5.4 Non-Dart cruft

| Path | Verdict |
|---|---|
| [AnimatedBottomNav.tsx](AnimatedBottomNav.tsx) (14.5 KB, repo root) | A React component in a Flutter repo root. Presumably a design reference for `ino_bottom_nav.dart`. Belongs in `docs/` or deleted. |
| `linux/`, `windows/`, `web/` | Scaffolded by `flutter create`, never maintained. The app hard-depends on camera/ML Kit/biometrics — these targets cannot work. |
| `share-proxy/` | Single Cloudflare Worker; redundant with `share-frontend`. |
| `supabase/.temp/` | CLI scratch state, committed. |
| `deep-linking/assetlinks.json` | Template with `REPLACE_WITH_YOUR_APP_SIGNING_SHA256_FINGERPRINT`. |
| 11 root-level `*.md` files | Useful, but the root is cluttered; most belong in `docs/`. |

---

## 6. Production error catalogue

Ordered by likelihood × blast radius. `dart analyze` is clean — **every item below is a runtime,
configuration or deployment failure, not a compile error.**

### 🔴 Blockers — will fail at release or first contact with a real user

#### 6.1 `applicationId = com.example.inoapp`
[android/app/build.gradle.kts:45](android/app/build.gradle.kts#L45) and
`PRODUCT_BUNDLE_IDENTIFIER = com.example.inoapp` in the Xcode project.

- **Google Play rejects any package starting `com.example.`** at upload. Hard stop.
- Changing it later is irreversible for an existing listing, invalidates the Google Sign-In
  OAuth client, breaks Firebase (`google-services.json` is keyed to the package), and invalidates
  `assetlinks.json`.
- **Symptom:** upload rejected, or — worse — you ship, then discover Google Sign-In and deep links
  are dead and you cannot rename.

#### 6.2 Deep links point at the wrong host — QR codes will not open the app
- The QR encodes `https://ino-share-web.vercel.app/s/<token>`
  ([share_config.dart:24](lib/config/share_config.dart#L24)).
- The Android App Link filter listens on `ilfzppryyojoponkomrw.functions.supabase.co/share/`
  ([AndroidManifest.xml](android/app/src/main/AndroidManifest.xml)).
- **These do not overlap.** Scanning an INO QR opens the browser, never the app.
- `deep-linking/assetlinks.json` still contains `REPLACE_WITH_YOUR_APP_SIGNING_SHA256_FINGERPRINT`,
  so `autoVerify` fails regardless.
- iOS `Runner.entitlements` has `applinks:your-share-domain` — a literal placeholder, so iOS
  Universal Links are entirely non-functional.
- **Symptom:** "Open in app" never happens. `ino://` scheme links still work (testing only).

#### 6.3 Two pairs of migrations share a version number
```
20260733000000_password_vault_simplify.sql
20260733000000_vault_documents.sql          ← same version
20260734000000_fix_vault_document_audit.sql
20260734000000_wallet_consent.sql           ← same version
```
The Supabase CLI keys applied migrations by version string. Two files claiming `20260733000000`
means **one is recorded as applied and the other may be silently skipped**, or ordering becomes
non-deterministic between environments.

- **Symptom:** `supabase db push` succeeds on your machine and produces a *different schema* in
  production. The most likely casualties are the `consent` column and the vault-document audit fix
  → inserts fail with `column "consent" does not exist`, or vault document grants misbehave.
- **This is the single most dangerous item in this document** because it fails silently and
  differently per environment.

#### 6.4 iOS Google Sign-In is not configured
`googleIosClientId = 'YOUR_GOOGLE_IOS_CLIENT_ID'`
([supabase_config.dart:29](lib/config/supabase_config.dart#L29)).
`isGoogleConfigured` only validates the **web** client ID, so the guard does not catch this.
- **Symptom:** on iOS, "Continue with Google" fails to mint a token — typically a silent no-op or
  an opaque platform exception.

#### 6.5 Demo credentials ship enabled
`isDemoBuild = true` with `demo@ino.app` / `DemoUser@123`
([demo_account.dart](lib/config/demo_account.dart)).
- **Symptom:** a production build shows "Login as Guest" and hands anyone a working account whose
  credentials are in the public source. Whatever that account can see, anyone can see.

### 🟠 High — will break for a meaningful slice of users

#### 6.6 Release builds can be debug-signed
[build.gradle.kts](android/app/build.gradle.kts) falls back to the debug keystore when
`key.properties` is absent, with only a `logger.warn`.
- **Symptom:** a CI pipeline produces an AAB that Play rejects, or an APK that is distributed and
  cannot ever be updated. The warning scrolls past in build output.

#### 6.7 `SUPABASE_FUNCTIONS_URL` falls back silently
[share-frontend/lib/config.ts](share-frontend/lib/config.ts) defaults to a hardcoded project URL
when the env var is missing.
- **Symptom:** deploy to staging, forget the env var, and staging quietly serves **production
  documents**. No error, no log.

#### 6.8 ML Kit document scanner is Android-only
[document_scanner_service.dart](lib/services/document_scanner_service.dart) documents this. iOS
falls back to the in-app camera, which has **no auto edge detection**.
- **Symptom:** iOS scan quality is visibly worse; OCR accuracy drops; the feature parity implied by
  the marketing copy does not hold. Not a crash — a support-ticket generator.

#### 6.9 R8 / ProGuard stripping ML Kit
Minify is on with custom keep rules for ML Kit's reflectively-loaded classes.
- **Symptom:** works in `--debug`, `ClassNotFoundException`/`MissingPluginException` in `--release`
  only. **Always smoke-test OCR on a real release build**, never just debug.

#### 6.10 Legacy storage permissions on modern Android
`READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` are declared. On API 33+ these are ignored, and
Play's declaration form will ask about them.
- **Symptom:** review friction; on some devices the gallery/file picker path fails when the code
  assumes the legacy grant.

#### 6.11 Free keyless rate APIs, no contract
`market_rates_service` uses gold-api.com + frankfurter with no key, no SLA, no rate limit guarantee.
The code is best-effort, so failures fall back silently.
- **Symptom:** the "LIVE" badge shows stale or fallback numbers indefinitely with no user-visible
  error. Financial figures that look authoritative and are not.

#### 6.12 iOS screenshot protection is detection, not prevention
Documented honestly in [screen_security_service.dart](lib/services/screen_security_service.dart):
Android gets real `FLAG_SECURE`, iOS only observes capture notifications.
- **Symptom:** a view-once document **can** be screenshotted on iOS. If any UI copy promises
  "screenshot protected", that is a false claim on half the install base.

### 🟡 Medium — degraded behaviour, edge cases, operational risk

| # | Risk | Symptom |
|---|---|---|
| 6.13 | **`WalletTables.slugFor` drifting from `ino_wallet_slug()`** | A custom wallet whose slug differs between client and DB → writes hit a non-existent table (PostgREST 404) or the wrong one. Records vanish from the UI but exist in the DB. |
| 6.14 | **`SessionReset` incompleteness** | Any new singleton store not registered there leaks data across an account switch on a shared device. Regression-prone by construction. |
| 6.15 | **OCR extraction stored inside the `notes` column** | A user who edits notes on an old client, or any code that overwrites `notes` wholesale, destroys extracted fields. Documented as a deliberate trade — but it is a real one. |
| 6.16 | **`share_plus` on iPad** | Throws without `sharePositionOrigin`. `share_origin.dart` exists precisely for this; **every** share call site must use it. One miss = a crash on iPad only. |
| 6.17 | **80 `debugPrint` calls** | Present in release builds. Check none of them print document names, tokens, storage paths, or user identifiers. |
| 6.18 | **11 `catch (_) {}` swallows** | Silent failures. A sync or upload that never happened looks identical to one that succeeded. |
| 6.19 | **FCM token / `POST_NOTIFICATIONS` on Android 13+** | Runtime permission denied → reminders never arrive, with no in-app indication that notifications are off. |
| 6.20 | **`FCM_SERVICE_ACCOUNT` secret rotation** | Rotate the Firebase key without re-running `supabase secrets set` → the cron function fails server-side. No user-visible signal; reminders just stop. |
| 6.21 | **View-once `access_key` 5-minute window vs large files** | A 30 MB PDF over a slow connection can outlive the key. The link is already burnt → the recipient gets nothing and cannot retry. |
| 6.22 | **`react-pdf` / pdf.js worker on Vercel** | Version-sensitive. A worker mismatch renders a blank viewer with only a console error. Not covered by any test. |
| 6.23 | **No server-side tests** | The Edge Functions and Next.js API routes — including the atomic burn — have zero automated coverage. |
| 6.24 | **`shared_preferences` size** | Whole collections (properties, investments, cards, offline docs) are JSON-serialised into prefs. Large accounts mean slow startup and, on Android, a real risk of hitting XML pref limits. |
| 6.25 | **Supabase Storage egress** | Every share view proxies full bytes through the Edge Function *and* the Next.js API — double egress per view. Costs scale with sharing volume, not storage. |
| 6.26 | **Passphrase loss is unrecoverable** | Working as designed, but expect support tickets. Make sure the copy in `vault_passphrase_sheet` is never softened. |
| 6.27 | **`.temp/` and `google-services.json` committed** | Project ref and Firebase config are in git history. Not secret, but they pin you to that project. |

### 🟢 Low — polish

- `ino_logo.dart` still renders a placeholder monogram.
- `placeholder_tab.dart` can still surface "coming soon" to a paying user.
- Currency rates are indicative and editable — a user could compute against a wrong rate.
- `share_config_screen.dart` is tested but unreachable → green suite, dead feature.

---

## 7. How to clean this up

Ordered so each phase is independently shippable and low-risk. **Nothing below has been applied.**

### Phase 0 — Pre-flight (do first, ~1 hour)

```bash
git checkout -b chore/cleanup
dart analyze          # baseline: currently clean
flutter test          # baseline: record pass/fail before touching anything
```

Tag the current commit so any deletion is one `git revert` away.

### Phase 1 — Production blockers (do before *any* release)

These are correctness fixes, not cleanup. Do them even if you skip everything else.

1. **Rename the bundle id** to a real reverse-domain (`in.inoapp.app` or similar) in
   `build.gradle.kts` (`namespace` + `applicationId`), the Xcode project, `google-services.json`
   (regenerate from Firebase), the Google OAuth clients, and `assetlinks.json`.
2. **Fix the duplicate migration versions.** Renumber `20260733000000_vault_documents.sql` →
   `20260733100000_…` and `20260734000000_wallet_consent.sql` → `20260734100000_…`. Then diff a
   fresh `supabase db reset` against production schema and reconcile. Do this before any further
   migration is written.
3. **Align the deep-link hosts.** Decide the canonical share domain, then make all four agree:
   `ShareConfig.publicBase`, the Android intent filter, `assetlinks.json` (with the real release
   SHA-256), and the iOS `applinks:` entitlement.
4. **Set `googleIosClientId`** or gate the Google button off on iOS.
5. **Flip `isDemoBuild` to `false`**, and better: make it
   `const bool.fromEnvironment('INO_DEMO')` so a release build can't ship it by accident.
6. **Make debug-signed release builds fail, not warn** — `throw GradleException(...)` instead of
   `logger.warn`.
7. **Make `SUPABASE_FUNCTIONS_URL` required** in `share-frontend/lib/config.ts` — throw at boot
   rather than falling back to production.

### Phase 2 — Delete the dead code (mechanical, ~2 hours, high value)

Removes ~4,200 lines with zero behaviour change. Do it in the four commits below so each is
individually revertible.

```bash
# Commit 1 — old Home dashboard (12 files)
git rm -r lib/widgets/dashboard/sections/
git rm lib/widgets/dashboard/donut_chart.dart lib/widgets/home/priority_card.dart

# Commit 2 — old Wallet Hub / Detail (10 files)
git rm lib/widgets/wallet/{wallet_overview_card,security_center,wallet_header,recent_items}.dart
git rm lib/widgets/wallet_detail/{detail_overview_card,detail_header,storage_analytics_card,filter_bar,category_chips,recently_accessed_row}.dart

# Commit 3 — misc orphans (4 files)
git rm lib/widgets/profile/profile_header_card.dart
git rm lib/widgets/home/{activity_tile,floating_menu}.dart
git rm lib/widgets/scan/scan_fail_state.dart

# after each commit:
dart analyze && flutter test
```

**Commit 4 — orphaned screens. Decide, don't just delete.** These are finished features with no
door:

| File | Recommendation |
|---|---|
| `protection_center_screen.dart` + the "Protected" card | **Re-wire it.** A security-overview screen is worth more than the 283 lines it costs. Point the Profile "Protection" row or the Home summary card at it. |
| `activity_history_screen.dart` + `activity_service.dart` | **Re-wire or delete together.** They live or die as a pair. An audit trail is a natural fit under Profile. |
| `share_config_screen.dart` | **Delete, with its test.** Genuinely superseded by `share_settings_screen`. Deleting the test is the point — a green test on unreachable code is worse than no test. |

Then prune the now-unused `dashboard_models.dart` types (several exist only for the deleted
sections) — but only after `dart analyze` confirms nothing else references them.

### Phase 3 — Collapse the duplicated structure (~1 day)

1. **Merge `lib/data/` into `lib/repositories/`.** Two folders, one job. Move
   `reminder_store.dart` to `lib/services/` where every other store lives. Pure moves + import
   rewrites.
2. **Rename the colliding classes.** `WalletHeader` exists twice; after Phase 2 only one survives,
   but rename the survivor to `WalletDetailHeader` so a future reader isn't ambushed.
3. **Pick one share backend.** Delete `share-proxy/` if `share-frontend` is the deployment (it is,
   per `ShareConfig`).
4. **Retire the sample repositories.** Replace
   `DashboardRepository.instance = SampleDashboardRepository()` with either the real
   implementation or an explicit `throw UnimplementedError()` so sample data can never reach a
   user. Keep `SampleScanRepository` but gate it behind `kDebugMode`.
5. **Drop the unbuildable targets.** `git rm -r linux/ windows/ web/` — the app depends on camera,
   ML Kit and biometrics; these can't work. Removing them stops `flutter build` offering a broken
   path and shrinks the CI matrix.
6. **Move the strays.** `AnimatedBottomNav.tsx` → `docs/design/`. The 11 root `*.md` → `docs/`,
   leaving only `README.md` and this file at root.
7. **Un-commit `supabase/.temp/`** and add it to `.gitignore`.

### Phase 4 — Break up the giants (~1 week, do incrementally)

Seven files exceed 1,000 lines and account for ~11,000 lines between them:

| File | Lines | Suggested split |
|---|---|---|
| `l10n/app_localizations.dart` | 5,071 | Split per language: `strings_en.dart`, `strings_hi.dart`, … Or adopt ARB + `flutter gen-l10n` and get compile-time key checking — the current `t(key)` silently returns the key on a typo. |
| `wallet/document_viewer_screen.dart` | 1,757 | Extract the file-kind renderers (image / PDF / other), the extracted-fields panel, and the action bar into `widgets/document_viewer/`. |
| `documents/add_document_screen.dart` | 1,598 | Split source-picker step from details-form step; they're already two visual phases. |
| `profile/profile_screen.dart` | 1,500 | Extract each settings *group* into its own widget file; the screen becomes a list of groups. |
| `family/vault_detail_screen.dart` | 1,471 | Members tab / invitations tab / audit tab → three files. |
| `expenses/add_expense_screen.dart` | 1,316 | Extract the OCR pre-fill logic into a controller class. |
| `widgets/shell/ino_bottom_nav.dart` | 1,028 | The nav bar, the scan menu, and the quick wheel are three independent widgets sharing a file. |

Rule of thumb that fits this codebase: **a screen file should own layout and state; anything with
its own `CustomPainter` or its own state machine belongs in `widgets/`.**

### Phase 5 — Hardening (ongoing)

1. **Tighten the linter.** `analysis_options.yaml` is stock `flutter_lints` with nothing added.
   Add at minimum:
   ```yaml
   linter:
     rules:
       - avoid_print
       - prefer_final_locals
       - unawaited_futures        # you use unawaited() deliberately — make it enforced
       - avoid_empty_else
       - always_declare_return_types
   ```
   Consider `dart_code_metrics` or `dead_code` analyzer plugins so §5.1 never regenerates.
2. **Audit the 80 `debugPrint`s.** Route them through one `InoLog` helper that is a no-op in
   release, and assert no document name/token/path is ever logged.
3. **Audit the 11 `catch (_) {}`.** Each should either log or surface. Silent failure in a sync
   path is indistinguishable from success.
4. **Add server-side tests.** At minimum: the view-once burn is atomic and idempotent-once
   (second claim → 410), and the standard-share expiry/revoke gates. Deno test for the Edge
   Function; Playwright or a route test for the Next.js proxy.
5. **Add a `SessionReset` completeness test.** Enumerate every `.instance` singleton via
   reflection or a maintained manifest, and fail the test when one isn't cleared. This is the one
   piece of client-side security that regresses invisibly.
6. **Move `shared_preferences` collections to a real local DB** (`sqflite`/`drift`) if you expect
   accounts with hundreds of records — JSON-in-prefs will bite on startup time.
7. **Move secrets to `--dart-define`.** `supabase_config.dart` says to do this in its own comment.
   The anon key is safe to ship, but the pattern lets you have staging vs production builds.

### Phase 6 — Documentation hygiene

The in-code documentation in this repo is genuinely excellent — many files explain *why* a
design exists and which bug it fixed. Protect that:

- Add a `CONTRIBUTING.md` stating the three architectural rules from §1 explicitly:
  screens don't query Supabase; new stores must register with `SessionReset`;
  `WalletTables.slugFor` must mirror `ino_wallet_slug()`.
- Add a **"Known limitations"** section to `README.md` covering: Android-only ML Kit scanning,
  iOS screenshot detection-not-prevention, indicative currency/fuel rates. Users and reviewers
  will find these anyway; better they read them from you.

### Effort/impact summary

| Phase | Effort | Impact |
|---|---|---|
| 1 — Blockers | ~1 day | **Required to ship at all** |
| 2 — Delete dead code | ~2 hours | −4,200 lines, zero risk |
| 3 — Collapse duplication | ~1 day | Structural clarity |
| 4 — Break up giants | ~1 week | Long-term maintainability |
| 5 — Hardening | ongoing | Prevents regression |
| 6 — Docs | ~2 hours | Onboarding |

---

## 8. Honest assessment

**What is genuinely good here:**
the layering discipline (screens → services → repositories → models) is real and mostly held;
`dart analyze` is clean across 94k lines; the security-critical code (`vault_crypto`,
`session_reset`, `view_once_repository`, `card_store`) is not just correct but *documents its own
threat model*; the parser suite is pure Dart and properly unit-tested; and the in-code comments
routinely explain which bug a piece of code exists to prevent. That last property is rare and
worth a lot.

**What will hurt:**
the four config placeholders (§6.1, §6.2, §6.4, §6.5) are each individually enough to block or
compromise a launch, and the duplicate migration versions (§6.3) will produce a schema drift you
will debug at the worst possible time. None of these are visible to the compiler or the test
suite — which is exactly why they've survived.

**The 30 dead files are a symptom, not the disease.** They're the residue of two design iterations
(Home and Wallet) that were rebuilt rather than refactored. That's a legitimate way to work — but
the old versions were never removed, so the repo now contains two answers to "how does the Home
screen work" and a newcomer has no way to tell which one ships.
