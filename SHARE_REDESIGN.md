# INO — Google-Drive-style Document Sharing (redesign)

Redesigns the recipient experience so a shared link behaves like a Google Drive
link: **one document opens directly; multiple open a folder page.** The link is a
short token on your own domain, served by a Next.js frontend (Supabase can't
render HTML on its shared domain).

```
Owner: select docs → Share → link  https://share.inoapp.in/s/<token>
Recipient opens link →
   1 doc   → document opens immediately  (PDF viewer / image preview)
   N docs  → shared-folder page          (list + Preview/Download)
```

## Architecture

```
                    ┌─────────────────────────────────────────────┐
  QR / link  ─────▶ │  share.inoapp.in  (Next.js on Vercel)        │
  /s/<token>        │  • /s/[token]      server-fetches metadata   │
                    │  • /api/.../file   streams bytes (proxy)     │
                    └───────────────┬─────────────────────────────┘
                                    │ server-side only (host hidden)
                                    ▼
                    ┌─────────────────────────────────────────────┐
  INO app  ───────▶ │  Supabase `share` Edge Function             │
  (JSON + bytes)    │  • token→row, validate active+unexpired      │
                    │  • JSON metadata (kind/mime, index ids)      │
                    │  • file byte proxy (60s signed URL, server)  │
                    └───────────────┬─────────────────────────────┘
                                    ▼
                    document_shares (token, share_id, …) + documents + Storage
```

Security is unchanged and reinforced: the browser only ever talks to
`share.inoapp.in`; **no Supabase IDs, bucket paths, signed URLs, or document
UUIDs** reach it (documents are referenced by position index; files are proxied).

## 1. Database changes

`supabase/migrations/20260707000000_share_tokens.sql`
- Adds `document_shares.token` — a short (12-hex) unique public handle, default
  `substr(replace(gen_random_uuid()::text,'-',''),1,12)`; unique index; backfill.
- `create_document_share()` already does `returning *`, so it returns the new
  token automatically — no function change.
- `share_id` stays internal (RLS + analytics FKs); `token` is what links use.

Apply: `supabase db push` (or paste). Run after the earlier share migrations.

## 2. Token generation

Server-side by Postgres (never the client) — the column default mints an
unguessable token on insert; the RPC returns it. The Flutter app just reads
`share.token`. This keeps generation unforgeable.

## 3. Edge Function changes (`supabase/functions/share/index.ts`) — redeploy

- `loadShare()` looks up by **token OR share_id** (`.or(token.eq,share_id.eq)`),
  so new `/s/<token>` links and legacy links both resolve.
- Analytics writes key on the canonical `share.share_id` (URL segment may be a
  token).
- Metadata JSON now includes per-document **`kind`** (`pdf`|`image`|`other`) and
  **`mime`**, derived from the file path server-side (path never exposed), so the
  web viewer can pick PDF viewer vs image preview vs download.
- File proxy unchanged (index-based, bytes streamed, no path/URL exposed).

Deploy: `supabase functions deploy share --no-verify-jwt`.

## 4. Flutter app changes

- `lib/config/share_config.dart` — split into `publicBase`
  (`https://share.inoapp.in/s`, what the QR encodes) and `apiBase` (the Edge
  Function, what the app fetches). `publicUrl(token)` / `apiUrl(token)`.
- `lib/models/document_share.dart` — new `token` field; `url` → `publicUrl(token)`
  (QR now encodes the short link). `token` falls back to `share_id` for legacy rows.
- `lib/repositories/share_repository.dart` — `fetchPublicShare` / `fetchSharedFile`
  hit `apiUrl(token)` (JSON + proxied bytes) for the in-app preview.
- `lib/services/deep_link_service.dart` — `parseShareId` now also extracts
  `/s/<token>`; the in-app viewer takes a `token`.
- No UI/UX change to the owner flow (select → Share → QR). QR/link content only.

## 5. Next.js / Vercel frontend  (`share-frontend/`)

New app. See `share-frontend/README.md`. Routes:
- `app/s/[token]/page.tsx` — server component; `fetchShare(token)` (JSON);
  active → `ShareView`, else → `StatePage`.
- `app/s/[token]/ShareView.tsx` — client; **1 doc → `DocViewer` directly**,
  **N docs → folder page** (list + Preview overlay + Download).
- `app/s/[token]/DocViewer.tsx` — client (ssr:false): PDF (`react-pdf`, zoom),
  image (`react-zoom-pan-pinch`, pinch), other (download). Name, Download, expiry.
- `app/api/s/[token]/file/[index]/route.ts` — streams bytes from the Edge
  Function; keeps the Supabase host hidden.

## 6. API summary

| Endpoint | Who calls | Returns |
|---|---|---|
| `GET functions/share/<token>?format=json` | Next.js server, INO app | metadata JSON `{status,count,expiresAt,documents:[{id,name,type,kind,mime}]}` |
| `GET functions/share/<token>/file/<index>?mode=view\|download` | Next.js `/api` proxy, INO app | file bytes (inline/attachment) |
| `GET share.inoapp.in/s/<token>` | recipient browser | rendered page (single doc or folder) |
| `GET share.inoapp.in/api/s/<token>/file/<index>` | recipient browser (img/pdf/download) | proxied file bytes |

## 7. Folder structure (new / changed)

```
supabase/migrations/20260707000000_share_tokens.sql   (new)
supabase/functions/share/index.ts                     (token + kind/mime)
lib/config/share_config.dart                          (public/api split)
lib/models/document_share.dart                        (token)
lib/repositories/share_repository.dart                (apiUrl)
lib/services/deep_link_service.dart                   (/s/<token>)
share-frontend/                                        (new Next.js app)
```

## 8. Implementation / rollout plan

1. **DB**: `supabase db push` (adds token; backfills existing shares).
2. **Edge Function**: `supabase functions deploy share --no-verify-jwt`.
3. **Frontend**: deploy `share-frontend/` to Vercel; add domain
   `share.inoapp.in`; set `SUPABASE_FUNCTIONS_URL`.
4. **App**: ship the Flutter build — new QR codes encode `share.inoapp.in/s/…`.
   (Existing links keep working: the Edge Function still accepts `share_id`, and
   legacy rows get a token from the backfill.)
5. **Verify**: create a 1-doc share → open link → document opens directly;
   create a 3-doc share → folder page; revoke → revoked page.

## Compatibility / rollback
- Backward compatible: old `share_id` links still resolve; the app’s JSON path is
  unchanged in shape (only additive `kind`/`mime`).
- Rollback: point `ShareConfig.publicBase` back at the Edge Function and the app
  reverts to the previous behavior; the DB column is harmless if unused.
