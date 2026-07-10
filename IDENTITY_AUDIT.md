# INO — Identity & Ownership Audit

**Question:** can two users with the same username / display name / full name /
email prefix / phone number ever collide or leak data?

**Answer: No.** Ownership everywhere is keyed **exclusively on the Supabase Auth
user id** (`auth_user_id` / `owner_id`, both defaulting to and checked against
`auth.uid()`). No identity field is ever used as an ownership key, filter, cache
key, or storage path. **No code changes were required** — the audit is a
verification; new tests lock the guarantee in.

## 1. Every ownership identifier used in the app

| Layer | Ownership key | Never used for ownership |
|---|---|---|
| DB tables (`reminders`, `documents`, `users`) | `auth_user_id` (default `auth.uid()`) | email, full_name, phone |
| DB table (`document_shares`, `share_views`, `share_downloads`) | `owner_id` (default `auth.uid()`) | — |
| RLS policies + `create_document_share` RPC | `auth.uid()` | — |
| App repositories (reminders/documents/shares/users) | `_client.auth.currentUser?.id` → `.eq('auth_user_id'/'owner_id', uid)` | — |
| Storage bucket paths | `<uid>/…`, `<uid>/backups/…` | — |
| Local file cache key | derived from the uid-based `objectPath` | — |
| In-memory / SharedPreferences caches | fixed constant keys, wiped on sign-out | not keyed by any identity field |

There is **no `username` or `displayName` field** in the app at all. `email`,
`full_name`, `phone` exist **only** as profile *data* (a `users` row), Supabase
Auth *credentials* (sign-in), UI *display* (greetings/initials), or OCR
*content* (names scanned off ID documents) — never as an identifier.

## 2. Tables audited

| Table / store | Ownership | Result |
|---|---|---|
| **reminders** | `auth_user_id` + RLS + explicit filter | ✅ isolated |
| **documents** | `auth_user_id` + RLS + explicit filter | ✅ isolated |
| **Wallets / Investments / Payments / Goals / Tasks / Health / Insurance / Property** | *derived views over `documents`* (not separate tables) | ✅ inherit documents' isolation |
| **users (profile)** | `auth_user_id` + RLS | ✅ isolated |
| **document_shares / share_views / share_downloads** | `owner_id` + RLS; recipients via service-role Edge Fn only | ✅ isolated |
| **Notifications** | derived from reminders/documents (scoped); read/dismissed state = global key, cleared on sign-out | ✅ no crossover |
| **Search** | in-memory doc cache + recent terms, both cleared on sign-out | ✅ no crossover |
| **Categories** | custom list = global key, cleared on sign-out | ✅ no crossover |
| **Settings** | device prefs kept (theme/language); account prefs reset on sign-out | ✅ no crossover |
| **Storage (files, backups)** | `<uid>/…` paths + Storage RLS | ✅ isolated |

## 3. Search results — identity fields in ownership contexts

Searched `username`, `displayName`, `fullName`, `email`, `phone` across database
filters, queries, ownership checks, cache keys, SharedPreferences keys, and
document/storage paths:

- **Database filters (`.eq`)** — every one keys on `auth_user_id`, `owner_id`,
  `id`, `share_id`, or `wallet`. **Zero** filter on email/name/phone/username.
- **Storage/document paths** — all built from `$userId` / `$uid`
  (`document_repository`, `backup_service`, `account_service`). None use identity.
- **Cache keys / SharedPreferences keys** — fixed constants
  (`custom_document_categories`, `notif_read_ids`, `notif_dismissed_ids`,
  `protected_document_ids`, `search_recent_terms`, `pref_*`). None derived from
  identity; the user-scoped ones are wiped on sign-out (`SessionReset`).
- **Auth uses of email** — sign-in / re-authentication / password reset go
  through Supabase Auth (`signInWithPassword`, `resetPasswordForEmail`). That is
  the credential check, not app-data ownership.

## 4. Risks found

**None.** No ownership logic depends on username, display name, full name,
email, or phone. Consequently requirement "replace name-based ownership with
`auth_user_id` and migrate data" is **not applicable** — there was nothing to
replace or migrate.

Note: Supabase Auth already enforces a unique email per auth user, but the app
does **not** rely on that for isolation — even if two users shared every profile
field, their distinct `auth.uid()` keeps them fully separated.

## 5. Fixes applied

- **Code:** none required.
- **Tests added:** `test/duplicate_username_isolation_test.dart` — two users both
  named **"Ramesh"** (identical name, email, phone):
  - reminders owned by `auth_user_id` never cross over across a same-name account
    switch (modeled with a uid-partitioned fake repo — the client stand-in for RLS);
  - device caches (categories, search history, notification state) show no
    crossover after sign-out;
  - the identity model distinguishes two identical-name profiles **only** by
    `authUserId`.

## 6. Confirmation

**Duplicate usernames cannot cause data exposure.** Two users with the same
username, display name, full name, email prefix, or phone are isolated because
the *only* ownership identifier — in the database (RLS on `auth.uid()`), the app
(queries/paths keyed on the uid), and every cache (wiped on sign-out) — is the
Supabase Auth user id. Identical human-facing identity fields have no effect on
what data a user can see, access, modify, or affect.

**Verification:** `flutter analyze` clean · `flutter test` → **111 passing**
(incl. the new duplicate-username suite). Relates to `DATA_ISOLATION.md`.
