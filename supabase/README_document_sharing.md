# Secure Document Sharing via QR — Backend Deploy

This feature needs two backend pieces deployed to **your** Supabase project
(`ilfzppryyojoponkomrw`). The Flutter app is already wired to them. Nothing here
touches existing tables — it only **adds** `document_shares`, `share_views`,
`share_downloads` and one Edge Function.

## 1. Database migration

`supabase/migrations/20260704000000_document_shares.sql`

Adds the tables, indexes, RLS policies, and the `create_document_share` /
`expire_due_shares` functions.

**Apply it** (either one):

```bash
supabase db push
```

or paste the file into **Supabase Dashboard → SQL Editor → Run**.

**Verify it applied** — run `supabase/verify_document_sharing.sql` in the SQL
Editor. Every row must say `OK` (tables, the `create_document_share` RPC,
indexes, RLS). If the app shows **“QR Sharing Backend Not Configured”**, this
migration hasn't been applied (or the PostgREST cache is stale — the migration
ends with `notify pgrst, 'reload schema';` to handle that; you can re-run just
that line).

## 2. Edge Function (content-negotiated: HTML for browsers, JSON for the app)

`supabase/functions/share/index.ts`

Runs server-side with the service-role key, validates the share on every request
(`status = active` AND `expires_at > now()`), and serves the right format to
each caller:

- `GET /share/:id`
  - **Browser** (`Accept: text/html`, the default for a scanned QR) → a
    responsive, branded **HTML viewer**: INO header, document count, live expiry
    countdown, and a card per document with **View** / **Download**. Expired,
    revoked and not-found render professional full-page states.
  - **App / API** (`Accept: application/json`, or `?format=json`) → JSON
    `{ status, shareId, count, expiresAt, documents:[{id,name,type}] }`.
- `GET /share/:id/file/:index?mode=view|download` → the file **bytes**, streamed
  **through** the function. It mints a 60-second signed URL server-side, fetches
  the object itself, and proxies the bytes.

Documents are referenced by their **position in the share** (`0,1,2…`), never by
their Supabase UUID. The function never exposes the wallet, owner, other
documents, storage paths, signed URLs/tokens, or the service key.

**Deploy (or redeploy) it:**

```bash
supabase functions deploy share --no-verify-jwt
```

`--no-verify-jwt` is required — recipients are anonymous and have no JWT. Auth is
enforced *inside* the function by the share validation, not by the gateway.

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically by the
Edge runtime — you do **not** set them yourself.

## ⚠️ Known Supabase limitation: HTML is downgraded on the shared domain

**Proven behavior (2026-07-07):** the Supabase Edge Runtime rewrites
`Content-Type: text/html` → **`text/plain`** and injects
`X-Content-Type-Options: nosniff` + `Content-Security-Policy: default-src 'none';
sandbox` for responses served on `*.functions.supabase.co` — an anti-abuse
measure. Result: opening `https://…functions.supabase.co/share/<id>` in a browser
shows the **HTML source**, not the rendered page. `application/json` and file
bytes (`image/*`, `application/pdf`) are **not** downgraded — only `text/html`.

This is enforced *after* the function returns, so **no code change in
`index.ts` can fix it**. Two ways to get a rendered browser page:

1. **Reverse proxy (recommended, free)** — `share-proxy/cloudflare-worker.js`:
   a Cloudflare Worker on a domain you control that re-serves the page as real
   `text/html`. Deploy it, then set `ShareConfig.customBaseUrlOverride` to your
   domain so new QR codes point at it.
2. **App deep link** — with App Links configured (see `DEEP_LINKING.md`), the QR
   opens the native `SharedDocumentsScreen` instead of the browser.

Verify the downgrade yourself:
```
curl -sD - -o /dev/null "https://…functions.supabase.co/share/<id>"
# → Content-Type: text/plain  +  Content-Security-Policy: default-src 'none'; sandbox
```

## 3. Verify

After both are deployed, the QR encodes:

```
https://ilfzppryyojoponkomrw.functions.supabase.co/share/<share_id>
```

- **Through the proxy domain** (option 1 above) → a rendered INO document viewer:
  cards with View / Download and a live countdown.
- **The raw functions.supabase.co URL** shows source in a browser — that's the
  Supabase downgrade above, not a bug in the function.
- Force JSON (what the app receives): `curl -s "https://…/share/<share_id>?format=json"`
  → `application/json` with the documents.
- Revoke it / let it expire → the browser shows a professional
  “This link has been revoked.” / “This link has expired.” page and no file is
  reachable.
- In the app, **QR share → “Preview what recipients see”** opens the native
  `SharedDocumentsScreen` (same documents, via the JSON path).

## Storage note

The Edge Function signs files from the existing **private** `documents` bucket
using the service role, so you do **not** need to make the bucket public — keep
it private. Recipients only ever get short-lived signed URLs for the exact files
in the share.

## Optional: auto-expire housekeeping

`expire_due_shares()` flips past-due `active` rows to `expired`. Correctness does
not depend on it (the function checks expiry live), but you can schedule it via
`pg_cron` if you want statuses to self-tidy:

```sql
select cron.schedule('expire-shares', '*/10 * * * *', $$select public.expire_due_shares()$$);
```

## Custom domain (later)

To serve links as `https://ino.app/share/<id>` instead, point that route at the
Edge Function and set `ShareConfig.customBaseUrlOverride` in
`lib/config/share_config.dart`. Everything else is unchanged.
