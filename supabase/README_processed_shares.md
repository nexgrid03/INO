# Processed-copy QR shares — deploy guide

The **Advanced Document Share** flow ("Share Settings" screen) can share a
**processed copy** of a document (colour mode, watermark, redaction) instead of
the original. The "Generate & Share" (direct OS share) path works with **no
backend changes**. Making the **QR link** point to the processed copy needs the
two steps below. Until they're deployed, the QR button shows a clear
"backend not configured" message and direct share still works.

## 1. Database migration

Apply `migrations/20260722000000_processed_shares.sql`:

```bash
supabase db push
```

It adds `processed_paths / processed_names / processed_mimes / view_only /
password_hash` columns to `document_shares` and a `create_processed_share` RPC.
It does **not** touch the existing `create_document_share` (original-file) path.

The app uploads each processed copy to `documents/<uid>/shares/<stamp>/<i>.<ext>`
before calling the RPC. Your existing Storage RLS (which already lets a user
write under their own `<uid>/` prefix — the normal upload path) covers this; no
new Storage policy is required.

## 2. `share` Edge Function patch

Update `functions/share/index.ts` so it prefers the processed copies when a
share has them, enforces view-only, and gates on the password hash. Then
redeploy:

```bash
supabase functions deploy share
```

### a) Select the new columns in `loadShare`

```ts
const { data } = await admin
  .from("document_shares")
  .select(
    "id, share_id, token, owner_id, document_ids, status, expires_at, " +
    "processed_paths, processed_names, processed_mimes, view_only, password_hash",
  )
  // …existing token/share_id filter…
```

### b) Build the card list from processed copies when present (`loadCards`)

```ts
if (Array.isArray(share.processed_paths) && share.processed_paths.length > 0) {
  return share.processed_paths.map((_p: string, index: number) => ({
    index,
    name: share.processed_names?.[index] ?? `Document ${index + 1}`,
    type: "Shared copy",
    kind: fileKindFromMime(share.processed_mimes?.[index] ?? ""),
    mime: share.processed_mimes?.[index] ?? "application/octet-stream",
  }));
}
// …else fall back to the existing documents lookup…
```

### c) Serve the processed object + enforce controls (`serveFile`)

```ts
// view-only: refuse downloads
if (share.view_only && mode === "download") {
  return json({ error: "This document is view-only." }, 403);
}
// password gate (client sends ?pw=<sha256(password)>)
if (share.password_hash) {
  const pw = url.searchParams.get("pw");
  if (pw !== share.password_hash) {
    return json({ error: "This document is password protected." }, 401);
  }
}
// serve the processed copy instead of the original document
if (Array.isArray(share.processed_paths) && share.processed_paths.length > 0) {
  const objectPath = share.processed_paths[index];
  if (!objectPath) return json({ error: "Not found" }, 404);
  const signed = await admin.storage.from("documents")
    .createSignedUrl(objectPath, SIGNED_URL_TTL);
  // …fetch + stream bytes exactly as the existing original-file branch does…
}
```

The processed bytes are already colour-converted / watermarked / redacted, so
the Vercel web viewer needs **no change** to display them (it just renders
whatever the function returns). The web viewer WOULD need its own UI work to
prompt for the password and hide a download button for view-only shares; the
function-level enforcement above already refuses the bytes without a correct
`pw` / for `download` on a view-only share.
