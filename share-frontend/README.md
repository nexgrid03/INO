# INO Share Frontend (`share.inoapp.in`)

The public, Google-Drive-style viewer for INO document shares. A scanned QR /
opened link (`https://share.inoapp.in/s/<token>`) lands here and:

- **1 document** → opens the document **directly** (PDF viewer with zoom, or
  full-screen image with pinch-zoom). No file list.
- **Multiple documents** → a **shared-folder page** (count, file list, type
  icons, Preview + Download per file).
- **Expired / revoked / missing** → a professional full-page state.

It is a thin, secure layer over the Supabase `share` Edge Function:
- The page fetches share **metadata JSON** server-side (Supabase host never
  reaches the browser).
- File bytes are streamed through `/api/s/<token>/file/<index>` (same-origin),
  so **no Supabase IDs, bucket paths, signed URLs or tokens** are ever exposed.

## Stack
Next.js (App Router) · `react-pdf` (pdf.js) · `react-zoom-pan-pinch` · plain CSS.

## Local dev
```bash
cd share-frontend
cp .env.example .env.local        # set SUPABASE_FUNCTIONS_URL
npm install
npm run dev                       # http://localhost:3000/s/<token>
```

## Deploy to Vercel
1. Import this folder as a Vercel project (root = `share-frontend`).
2. Set env var **`SUPABASE_FUNCTIONS_URL`** =
   `https://ilfzppryyojoponkomrw.functions.supabase.co`.
3. Add the domain **`share.inoapp.in`** to the project (Vercel → Domains) and
   point its DNS (CNAME → `cname.vercel-dns.com`) at Vercel.
4. Deploy. Test `https://share.inoapp.in/s/<token>` — a single-doc share opens
   the document directly.

The INO app already encodes `https://share.inoapp.in/s/<token>` in new QR codes
(see `lib/config/share_config.dart` → `publicBase`).

## Structure
```
app/
  layout.tsx                       global shell + metadata
  globals.css                      mobile-first styles (light/dark)
  page.tsx                         bare-domain landing
  s/[token]/page.tsx               server: fetch metadata, choose view
  s/[token]/ShareView.tsx          client: single-doc vs folder
  s/[token]/DocViewer.tsx          client: PDF / image / other viewer (ssr:false)
  api/s/[token]/file/[index]/route.ts   byte proxy → Edge Function
components/
  Brand.tsx  StatePage.tsx  ExpiryPill.tsx
lib/
  config.ts                        server-side fetch + types
```
