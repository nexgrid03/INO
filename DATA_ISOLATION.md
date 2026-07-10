# INO — User Data Isolation Fix

**Reported bug:** reminders created by User A were visible after User B signed
in on the same device. Root-caused to two independent leaks and fixed on three
layers (client cache reset, client-side owner filters, server-side RLS).

## Root cause

The app's model is **one Supabase row per user, scoped by `auth_user_id`
(= `auth.uid()`), enforced by Row Level Security.** Two things broke isolation:

1. **Same-device cache leak (the reported symptom).** The Dart process does not
   restart on sign-out, and `AuthService.signOut()` only cleared the Supabase
   session + biometric lock. Every user-data singleton survived the account
   switch. The decisive one: `ReminderStore` is a `static final instance` with a
   `_loaded` guard — once User A populated it, User B's `ensureLoaded()` was a
   no-op and returned **User A's in-memory reminders**. The same pattern leaked
   `NotificationCenter` (global `notif_read_ids` / `notif_dismissed_ids` keys),
   `CategoryStore` (global `custom_document_categories` key) and
   `DocumentProtectionStore` (global `protected_document_ids` key).

2. **Server-side RLS not guaranteed.** There was **no migration** for the
   `reminders` / `documents` / `users` tables — they were created by hand in the
   dashboard. The reminders repository relied 100% on RLS (reads had no user
   filter; inserts set no owner). If RLS was never enabled on `reminders`, a
   plain `select()` returns **every user's rows** — a cross-device leak.

## The fix

### Layer 1 — reset user-scoped caches on sign-out  (fixes the reported bug)
- New `lib/services/session_reset.dart` — `SessionReset.instance.clear()` wipes
  every user-scoped singleton (in-memory **and** its `shared_preferences` keys).
- New public `clear()` on `ReminderStore`, `NotificationCenter`, `CategoryStore`,
  `DocumentProtectionStore`; bumps `DocumentRepository.revision`.
- Wired into `AuthService.signOut()` (runs after the Supabase sign-out, so
  nothing re-hydrates from the old session). `deleteAccount()` ends in
  `signOut()`, so it's covered too.

### Layer 2 — explicit owner filters (defense-in-depth with RLS)
Every read/write is now also filtered by `auth_user_id`, so a missing or
mis-scoped RLS policy can't leak or cross-write:
- `reminder_repository.dart`: `load()` filters `.eq('auth_user_id', uid)` (and
  returns empty when signed out); `add()` stamps `auth_user_id` and refuses when
  signed out; `setCompleted()` / `remove()` filter `.eq('id', id).eq('auth_user_id', uid)`
  so a user can only mutate their **own** reminder.
- `document_repository.dart`: same treatment on `listAll` / `listForWallet` /
  `create` / `update` / `delete`.

### Layer 3 — guarantee RLS in the database
`supabase/migrations/20260710000000_user_data_isolation.sql` (idempotent):
- Creates `public.reminders` if absent (with `auth_user_id uuid not null default
  auth.uid()`), or just ensures the owner column exists.
- **Enables RLS** on `reminders`, `documents`, `users`.
- Creates owner-only `select` / `insert` / `update` / `delete` policies
  (`auth_user_id = auth.uid()`) on all three.

## Other modules — audit result

- **Tasks / Goals / Wallets / Investments / Payments / Health / Insurance /
  Property**: not separate tables. They're *views over the `documents` table*
  (see `WalletRepository`, which derives every wallet's count/recents from
  `DocumentRepository.listAll()`). They inherit the `documents` RLS + owner
  filter fixed above — no separate storage to leak.
- **Notifications / Activity feed**: derived at runtime from reminders +
  documents (already scoped) + settings; the persisted notification read/dismiss
  state is now cleared on sign-out.
- **Users (profile)**: already filtered by `auth_user_id`; RLS re-asserted here.
- **Document shares**: already had RLS + owner scoping
  (`20260704000000_document_shares.sql`); recipients never touch the tables
  directly (service-role Edge Function). Unchanged.

## You must apply the migration

The code changes ship in the app, but the database half needs you to run the
migration against project `ilfzppryyojoponkomrw`:

```bash
supabase db push
# or paste supabase/migrations/20260710000000_user_data_isolation.sql into
# the Supabase SQL editor and run it.
```

### Verify (two-user isolation test)
1. In **Supabase → SQL editor**, confirm RLS is on:
   ```sql
   select relname, relrowsecurity
   from pg_class
   where relname in ('reminders','documents','users');
   -- relrowsecurity must be true for all three
   ```
2. Confirm no over-permissive policy remains (nothing should be `USING (true)`):
   ```sql
   select tablename, policyname, qual
   from pg_policies
   where tablename in ('reminders','documents','users');
   ```
3. In the app: sign in as **User A**, create a reminder. Sign out, sign in as
   **User B** → User B sees **zero** of User A's reminders (empty state). Repeat
   in the other direction.

## Note on pre-existing orphan rows
If the `reminders` table already held rows with no `auth_user_id`, the migration
leaves those NULL. Under the new policies a NULL owner never matches `auth.uid()`,
so orphan rows become invisible to everyone (fail-closed). If any were
legitimate, assign an owner manually:
```sql
update public.reminders set auth_user_id = '<the-users-uid>' where auth_user_id is null;
```

## Files changed
```
lib/services/session_reset.dart              (new — cache-reset coordinator)
lib/services/auth_service.dart               (signOut → SessionReset.clear())
lib/data/reminder_store.dart                 (public clear())
lib/services/notification_center.dart        (clear() + wipes global keys)
lib/services/category_store.dart             (clear() + wipes global key)
lib/services/document_protection_store.dart  (clear() + wipes global key)
lib/services/global_search_service.dart      (clear() — in-memory doc cache + recent-search history)
lib/services/app_settings.dart               (resetAccountScoped() — 2FA flag/last-backup/toggles)
lib/data/reminder_repository.dart            (auth_user_id filters + owner stamp)
lib/repositories/document_repository.dart    (auth_user_id filters + owner stamp)
lib/repositories/share_repository.dart       (owner_id filters on list/fetch/revoke/delete)
supabase/migrations/20260710000000_user_data_isolation.sql  (new — RLS)
test/data_isolation_test.dart                (new — isolation tests)
```
Verified: `flutter analyze` clean, `flutter test` → 106 passing.

## Verify Storage bucket RLS (outside this migration)
Document files live in the private `documents` Storage bucket at `<uid>/<file>`.
Access is guarded by **Storage** RLS on `storage.objects` (not covered by the
table migration). Confirm a policy scopes objects to the owner folder:
```sql
select policyname, cmd, qual
from pg_policies
where schemaname = 'storage' and tablename = 'objects';
-- expect a USING clause like: (storage.foldername(name))[1] = auth.uid()::text
```
```
