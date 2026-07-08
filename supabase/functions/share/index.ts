// ============================================================================
// INO — Public Document Share (Supabase Edge Function)
// ----------------------------------------------------------------------------
// Serves the recipient experience for a scanned QR / opened link. It runs with
// the service-role key (server-side only, never shipped) and CONTENT-NEGOTIATES:
//
//   GET /share/:shareId
//       • Browser (Accept: text/html) → a responsive, branded HTML viewer
//         (document cards + View/Download + live expiry countdown, or a
//         professional Expired / Revoked / Not-found page).
//       • App / API (Accept: application/json, or ?format=json) → JSON.
//
//   GET /share/:shareId/file/:index?mode=view|download
//       → the file BYTES, streamed (proxied) through this function. It mints a
//         60-second signed URL server-side, fetches the object itself, and
//         streams it back — so the client NEVER sees the bucket path, the
//         signed URL/token, the owner, or the document UUID.
//
// Security: every request re-validates status='active' AND expires_at>now();
// documents are referenced by their POSITION in the share (0,1,2…), not by
// their Supabase id; files are only served when that position maps to a doc in
// the share AND owned by the share's owner. No raw JSON to browsers, no HTML
// source leak, no storage internals.
//
// Deploy:  supabase functions deploy share --no-verify-jwt
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BUCKET = "documents";
const SIGNED_URL_TTL = 60;

// Brand palette (INO green + blue).
const GREEN = "#00E676";
const BLUE = "#29B6F6";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, OPTIONS",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
};

interface ShareRow {
  share_id: string;
  token: string;
  owner_id: string;
  document_ids: string[];
  status: "active" | "expired" | "revoked";
  expires_at: string;
  views_count: number;
  downloads_count: number;
}

interface DocRow {
  id: string;
  name: string;
  category: string | null;
  file_path: string | null;
  auth_user_id: string;
}

/** One shared document, referenced by its position in the share. `kind`/`mime`
 *  let the web viewer choose a PDF viewer vs an image preview vs download. */
interface Card {
  index: number;
  name: string;
  type: string;
  kind: "pdf" | "image" | "other";
  mime: string;
}

type Kind = "active" | "expired" | "revoked" | "not_found" | "error";
type LoadResult = { kind: "active"; share: ShareRow } | { kind: Exclude<Kind, "active"> };

// HTTP status for each terminal kind.
const STATUS: Record<Kind, number> = {
  active: 200,
  expired: 410,
  revoked: 410,
  not_found: 404,
  error: 500,
};

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  // Diagnostic: what the client asked for drives HTML-vs-JSON negotiation.
  console.log("Accept:", req.headers.get("accept"));

  try {
    const url = new URL(req.url);
    const parts = url.pathname.replace(/^\/+/, "").split("/").filter(Boolean);
    const i = parts.indexOf("share");
    const tail = i >= 0 ? parts.slice(i + 1) : parts;

    const shareId = tail[0];
    if (!shareId) return renderShare("not_found", req, null, []);

    if (tail[1] === "file" && tail[2] !== undefined) {
      return await serveFile(shareId, tail[2], url.searchParams.get("mode") ?? "view");
    }
    return await serveShare(shareId, req);
  } catch (e) {
    console.error("[share] FATAL:", e);
    return renderShare("error", req, null, []);
  }
});

// ---- Validation -------------------------------------------------------------

async function loadShare(idOrToken: string): Promise<LoadResult> {
  console.log(`[share] fetch id/token=${idOrToken}`);
  // Accept EITHER the short public token (new /s/{token} links) or the internal
  // share_id (legacy links) — both resolve to the same row.
  const { data, error } = await admin
    .from("document_shares")
    .select("share_id, token, owner_id, document_ids, status, expires_at, views_count, downloads_count")
    .or(`token.eq.${idOrToken},share_id.eq.${idOrToken}`)
    .maybeSingle();

  if (error) {
    console.error(`[share] load error id/token=${idOrToken}:`, error);
    return { kind: "error" };
  }
  if (!data) {
    console.log(`[share] not found id/token=${idOrToken}`);
    return { kind: "not_found" };
  }
  const share = data as ShareRow;

  if (share.status === "revoked") return { kind: "revoked" };

  const expired = share.status === "expired" || new Date(share.expires_at).getTime() <= Date.now();
  console.log(
    `[share] expiry check share_id=${share.share_id} status=${share.status} ` +
      `expires_at=${share.expires_at} expired=${expired}`,
  );
  if (expired) {
    if (share.status !== "expired") {
      await admin.from("document_shares").update({ status: "expired" }).eq("share_id", share.share_id);
    }
    return { kind: "expired" };
  }
  return { kind: "active", share };
}

/** Derives a display `kind` + real `mime` from the stored file path (never
 *  exposes the path itself). */
function fileKind(path: string | null): { kind: "pdf" | "image" | "other"; mime: string } {
  const ext = (path && path.includes(".") ? path.split(".").pop() : "")?.toLowerCase() ?? "";
  if (ext === "pdf") return { kind: "pdf", mime: "application/pdf" };
  if (["png", "jpg", "jpeg", "webp", "heic", "gif"].includes(ext)) {
    return { kind: "image", mime: mimeFromPath(path ?? "") };
  }
  return { kind: "other", mime: mimeFromPath(path ?? "") };
}

/** Fetches the share's documents IN ORDER, dropping any that were deleted, and
 *  keeping each one's original position (used as its opaque file handle). */
async function loadCards(share: ShareRow): Promise<Card[]> {
  const { data, error } = await admin
    .from("documents")
    .select("id, name, category, file_path")
    .in("id", share.document_ids);
  if (error) {
    console.error(`[share] documents error share_id=${share.share_id}:`, error);
    throw error;
  }
  console.log(`[share] documents fetched share_id=${share.share_id} count=${data?.length ?? 0}`);
  const byId = new Map((data ?? []).map((d) => [(d as DocRow).id, d as DocRow]));
  const cards: Card[] = [];
  share.document_ids.forEach((id, index) => {
    const d = byId.get(id);
    if (d) {
      const { kind, mime } = fileKind(d.file_path);
      cards.push({ index, name: d.name, type: d.category ?? "Document", kind, mime });
    }
  });
  return cards;
}

// ---- Share endpoint (HTML for browsers, JSON for the app) -------------------

function wantsJson(req: Request): boolean {
  const url = new URL(req.url);
  if (url.searchParams.get("format") === "json") return true;
  const accept = (req.headers.get("accept") ?? "").toLowerCase();
  return accept.includes("application/json") && !accept.includes("text/html");
}

async function serveShare(shareId: string, req: Request): Promise<Response> {
  const res = await loadShare(shareId);
  if (res.kind !== "active") return renderShare(res.kind, req, null, []);

  const share = res.share;
  let cards: Card[];
  try {
    cards = await loadCards(share);
  } catch {
    return renderShare("error", req, null, []);
  }

  // Analytics: record a view (best-effort). Keyed on the canonical share_id
  // (the URL segment may be the short token).
  await admin.from("share_views").insert({ share_id: share.share_id });
  await admin
    .from("document_shares")
    .update({ views_count: (share.views_count ?? 0) + 1, last_accessed_at: new Date().toISOString() })
    .eq("share_id", share.share_id);

  return renderShare("active", req, share.expires_at, cards, shareId);
}

/** Renders EITHER HTML or JSON depending on the client. */
function renderShare(
  kind: Kind,
  req: Request,
  expiresAt: string | null,
  cards: Card[],
  shareId?: string,
): Response {
  const asJson = wantsJson(req);
  console.log("Branch:", asJson ? "JSON" : "HTML"); // requirement 6
  if (asJson) {
    if (kind === "active") {
      return json(
        {
          status: "active",
          shareId,
          count: cards.length,
          expiresAt,
          documents: cards.map((c) => ({
            id: String(c.index),
            name: c.name,
            type: c.type,
            kind: c.kind,
            mime: c.mime,
          })),
        },
        200,
      );
    }
    return json({ status: kind, message: MESSAGES[kind] }, STATUS[kind]);
  }
  // Browser → HTML.
  const html = kind === "active" ? viewerHtml(cards, expiresAt, shareId ?? "") : statusHtml(kind);
  return htmlResponse(html, STATUS[kind]);
}

// ---- File proxy (bytes; never exposes storage internals) --------------------

async function serveFile(shareId: string, handle: string, mode: string): Promise<Response> {
  const res = await loadShare(shareId);
  if (res.kind !== "active") return htmlResponse(statusHtml(res.kind), STATUS[res.kind]);
  const share = res.share;

  const index = Number.parseInt(handle, 10);
  if (!Number.isInteger(index) || index < 0 || index >= share.document_ids.length) {
    return htmlResponse(statusHtml("not_found"), 404);
  }
  const documentId = share.document_ids[index];

  const { data: docData, error } = await admin
    .from("documents")
    .select("id, name, category, file_path, auth_user_id")
    .eq("id", documentId)
    .maybeSingle();

  if (error || !docData) return htmlResponse(statusHtml("not_found"), 404);
  const doc = docData as DocRow;

  // Defense in depth: the document must belong to the share's owner.
  if (doc.auth_user_id !== share.owner_id) {
    console.warn(`[share] ownership mismatch index=${index} share=${shareId}`);
    return htmlResponse(statusHtml("not_found"), 404);
  }
  if (!doc.file_path) return htmlResponse(statusHtml("not_found"), 404);

  const download = mode === "download";
  console.log(`[share] sign+proxy share_id=${shareId} index=${index} mode=${mode}`);

  // Signed URL generated + used server-side only; never sent to the client.
  const { data: signed, error: signErr } = await admin.storage
    .from(BUCKET)
    .createSignedUrl(doc.file_path, SIGNED_URL_TTL);
  if (signErr || !signed?.signedUrl) {
    console.error(`[share] createSignedUrl error index=${index}:`, signErr);
    return htmlResponse(statusHtml("error"), 500);
  }

  const upstream = await fetch(signed.signedUrl);
  if (!upstream.ok || !upstream.body) {
    console.error(`[share] upstream fetch failed index=${index} status=${upstream.status}`);
    return htmlResponse(statusHtml("error"), 502);
  }

  if (download) {
    await admin.from("share_downloads").insert({ share_id: share.share_id, document_id: documentId });
    await admin
      .from("document_shares")
      .update({
        downloads_count: (share.downloads_count ?? 0) + 1,
        last_accessed_at: new Date().toISOString(),
      })
      .eq("share_id", share.share_id);
  }

  const filename = downloadName(doc.name, doc.file_path);
  const contentType = upstream.headers.get("content-type") ?? mimeFromPath(doc.file_path);
  return new Response(upstream.body, {
    status: 200,
    headers: {
      ...CORS,
      "content-type": contentType,
      "cache-control": "no-store",
      "content-disposition": `${download ? "attachment" : "inline"}; filename="${filename}"`,
    },
  });
}

// ---- Responses --------------------------------------------------------------

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function htmlResponse(html: string, status: number): Response {
  // `html` is a RAW HTML STRING — never JSON.stringify'd, never wrapped in an
  // object, never entity-escaped. Every HTML branch (active / expired /
  // revoked / not-found / error) returns through here.
  //
  // NOTE: no `...CORS` spread here. A top-level browser navigation to this page
  // does not use CORS, and spreading a shared header object was the only thing
  // that could theoretically interfere with Content-Type. This is now the exact
  // minimal form: a plain object with a single Content-Type.
  const response = new Response(html, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
  // What THIS function emits (all correct). NB: the Supabase edge runtime
  // rewrites Content-Type: text/html → text/plain AFTER this, on the shared
  // *.functions.supabase.co domain — so these logs will show text/html while
  // the browser receives text/plain. Serve via a proxy domain to fix (see
  // share-proxy/cloudflare-worker.js).
  console.log("Final response headers:", JSON.stringify([...response.headers]));
  console.log("Content-Type:", response.headers.get("content-type"));
  console.log("HTML length:", html.length);
  console.log("HTML first 500:", html.slice(0, 500));
  return response;
}

const MESSAGES: Record<Kind, string> = {
  active: "",
  expired: "This share link has expired",
  revoked: "This share link has been revoked",
  not_found: "This share link doesn’t exist",
  error: "Something went wrong. Please try again.",
};

// ---- HTML rendering ---------------------------------------------------------

function shell(bodyInner: string, headExtra = ""): string {
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="robots" content="noindex,nofollow"/>
<title>INO — Shared Documents</title>
<style>
  :root{--green:${GREEN};--blue:${BLUE};}
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
       color:#0f172a;background:#f1f5f9;min-height:100vh;-webkit-font-smoothing:antialiased}
  .top{background:linear-gradient(135deg,var(--green),var(--blue));padding:20px 16px 44px}
  .top-in{max-width:680px;margin:0 auto;display:flex;align-items:center;gap:12px}
  .logo{width:40px;height:40px;border-radius:12px;background:rgba(255,255,255,.22);
        display:flex;align-items:center;justify-content:center;font-weight:900;color:#fff;font-size:20px;
        border:1px solid rgba(255,255,255,.35)}
  .brand b{display:block;color:#fff;font-size:18px;font-weight:800;letter-spacing:-.2px}
  .brand span{color:rgba(255,255,255,.9);font-size:12.5px}
  .wrap{max-width:680px;margin:-28px auto 0;padding:0 16px 56px}
  .head{margin:0 2px 16px}
  .head h1{font-size:22px;font-weight:800;letter-spacing:-.4px;margin-bottom:8px}
  .meta{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
  .count{font-size:13.5px;color:#475569;font-weight:600}
  .pill{display:inline-flex;align-items:center;gap:6px;background:rgba(0,230,118,.12);
        color:#047857;border:1px solid rgba(0,230,118,.35);border-radius:999px;
        padding:5px 11px;font-size:12.5px;font-weight:700}
  .card{background:#fff;border:1px solid #e2e8f0;border-radius:18px;padding:16px;margin-bottom:12px;
        box-shadow:0 6px 20px rgba(2,32,71,.06)}
  .row{display:flex;align-items:center;gap:13px}
  .ic{width:46px;height:46px;flex:0 0 auto;border-radius:13px;
      background:linear-gradient(135deg,var(--green),var(--blue));
      display:flex;align-items:center;justify-content:center;font-size:22px}
  .info{min-width:0;flex:1}
  .info b{display:block;font-size:15.5px;font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .info span{font-size:12.5px;color:#64748b}
  .acts{display:flex;gap:10px;margin-top:14px}
  .btn{flex:1;display:inline-flex;align-items:center;justify-content:center;gap:7px;text-decoration:none;
       height:44px;border-radius:12px;font-weight:700;font-size:14px;cursor:pointer;border:1px solid transparent}
  .btn svg{width:17px;height:17px}
  .view{background:linear-gradient(135deg,var(--green),var(--blue));color:#fff}
  .dl{background:#fff;border-color:#e2e8f0;color:#0f172a}
  .foot{max-width:680px;margin:24px auto 0;text-align:center;color:#94a3b8;font-size:12px;
        display:flex;align-items:center;justify-content:center;gap:6px}
  .state{max-width:520px;margin:8vh auto 0;padding:0 24px;text-align:center}
  .state .circle{width:96px;height:96px;border-radius:50%;margin:0 auto 20px;
                 display:flex;align-items:center;justify-content:center;font-size:44px}
  .state h2{font-size:22px;font-weight:800;margin-bottom:8px}
  .state p{color:#64748b;font-size:14.5px;line-height:1.5}
  @media (prefers-color-scheme:dark){
    body{background:#0b1220;color:#e8eef2}
    .card{background:#111a2e;border-color:#1e293b;box-shadow:none}
    .dl{background:#111a2e;border-color:#334155;color:#e8eef2}
    .count{color:#94a3b8}.info span{color:#94a3b8}.state p{color:#94a3b8}
  }
</style>${headExtra}</head><body>${bodyInner}</body></html>`;
}

const ICON_VIEW =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>';
const ICON_DL =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>';

function brandTop(): string {
  return `<div class="top"><div class="top-in">
    <div class="logo">I</div>
    <div class="brand"><b>INO</b><span>Secure document share</span></div>
  </div></div>`;
}

function viewerHtml(cards: Card[], expiresAt: string | null, shareId: string): string {
  // Relative to the current page (…/share/<shareId>) the file lives at
  // <shareId>/file/<index>, so links resolve correctly on any host prefix.
  const base = escapeAttr(shareId);
  const items = cards
    .map(
      (c) => `<div class="card">
        <div class="row">
          <div class="ic">📄</div>
          <div class="info"><b>${escapeHtml(c.name)}</b><span>${escapeHtml(c.type)}</span></div>
        </div>
        <div class="acts">
          <a class="btn view" href="${base}/file/${c.index}?mode=view" target="_blank" rel="noopener">${ICON_VIEW}View</a>
          <a class="btn dl" href="${base}/file/${c.index}?mode=download">${ICON_DL}Download</a>
        </div>
      </div>`,
    )
    .join("");

  const count = `${cards.length} document${cards.length === 1 ? "" : "s"}`;
  const pill = expiresAt
    ? `<span class="pill" id="countdown">🔒 Active</span>`
    : "";
  const countdownScript = expiresAt
    ? `<script>
        var exp=new Date(${JSON.stringify(expiresAt)}).getTime();
        function tick(){var ms=exp-Date.now();var el=document.getElementById('countdown');
          if(ms<=0){location.reload();return;}
          var s=Math.floor(ms/1000),d=Math.floor(s/86400),h=Math.floor(s%86400/3600),
              m=Math.floor(s%3600/60),ss=s%60,t;
          if(d>0)t='Expires in '+d+' day'+(d>1?'s':'');
          else if(h>0)t='Expires in '+h+'h '+m+'m';
          else if(m>0)t='Expires in '+m+'m '+ss+'s';
          else t='Expires in '+ss+'s';
          if(el)el.textContent='⏳ '+t;}
        tick();setInterval(tick,1000);
      </script>`
    : "";

  const body = `${brandTop()}
    <div class="wrap">
      <div class="head">
        <h1>Shared Documents</h1>
        <div class="meta"><span class="count">${count}</span>${pill}</div>
      </div>
      ${cards.length ? items : `<div class="card"><div class="info"><b>No documents</b><span>This share has no documents.</span></div></div>`}
      <div class="foot">🔒 Shared securely via INO · you can only view these documents</div>
    </div>${countdownScript}`;
  return shell(body);
}

function statusHtml(kind: Kind): string {
  const map: Record<string, { emoji: string; bg: string; title: string; msg: string }> = {
    expired: {
      emoji: "⏳",
      bg: "rgba(245,165,36,.15)",
      title: "This link has expired",
      msg: "The documents shared with you are no longer available.",
    },
    revoked: {
      emoji: "🚫",
      bg: "rgba(239,83,80,.15)",
      title: "This link has been revoked",
      msg: "The owner has turned off access to these documents.",
    },
    not_found: {
      emoji: "🔍",
      bg: "rgba(148,163,184,.18)",
      title: "Link not found",
      msg: "This shared link doesn’t exist or has been removed.",
    },
    error: {
      emoji: "⚠️",
      bg: "rgba(148,163,184,.18)",
      title: "Something went wrong",
      msg: "Please try opening the link again in a moment.",
    },
  };
  const s = map[kind] ?? map.error;
  const body = `${brandTop()}
    <div class="state">
      <div class="circle" style="background:${s.bg}">${s.emoji}</div>
      <h2>${escapeHtml(s.title)}</h2>
      <p>${escapeHtml(s.msg)}</p>
      <div class="foot" style="margin-top:26px">🔒 Shared securely via INO</div>
    </div>`;
  return shell(body);
}

// ---- Helpers ----------------------------------------------------------------

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}
function escapeAttr(s: string): string {
  return encodeURIComponent(s);
}

function downloadName(name: string, filePath: string): string {
  const safe = name.replace(/[\r\n"\\]/g, "").trim() || "document";
  if (/\.[a-z0-9]{1,5}$/i.test(safe)) return safe;
  const ext = filePath.includes(".") ? filePath.split(".").pop() : "";
  return ext ? `${safe}.${ext}` : safe;
}

function mimeFromPath(path: string): string {
  const ext = (path.includes(".") ? path.split(".").pop() : "")?.toLowerCase() ?? "";
  switch (ext) {
    case "pdf":
      return "application/pdf";
    case "png":
      return "image/png";
    case "jpg":
    case "jpeg":
      return "image/jpeg";
    case "webp":
      return "image/webp";
    case "heic":
      return "image/heic";
    default:
      return "application/octet-stream";
  }
}
