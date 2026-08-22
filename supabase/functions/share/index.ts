// ============================================================================
// INO - Public Document Share (Supabase Edge Function)
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
//         streams it back - so the client NEVER sees the bucket path, the
//         signed URL/token, the owner, or the document UUID.
//
// VIEW ONCE (one-time links) - additive, separate routes, same proxy discipline:
//
//   GET  /share/v/:token           → NON-CONSUMING status peek (ready / viewed /
//                                    expired / revoked / not_found). Safe for
//                                    link-preview crawlers and page refreshes.
//   POST /share/v/:token/claim     → BURNS the link (atomic, exactly once) and
//                                    returns a short-lived access key.
//   GET  /share/v/:token/file?k=…  → the bytes, inline only, for the claiming
//                                    client. No download disposition: a
//                                    view-once document is viewed, not kept.
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
const GREEN = "#098F90";
const BLUE = "#2BA8A9";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  // POST is used only by the view-once /claim route (an explicit, state-changing
  // action). Every pre-existing route stays GET-only.
  "access-control-allow-methods": "GET, POST, OPTIONS",
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
  processed_paths: string[] | null;
  processed_names: string[] | null;
  processed_mimes: string[] | null;
  view_only: boolean;
  password_hash: string | null;
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

    // ---- View-once namespace: /share/v/<token>[/claim|/file] --------------
    // `v` is a reserved first segment. Real share ids are `share_…` and share
    // tokens are 12+ hex chars, so neither can ever be the literal "v".
    if (shareId === "v") {
      const token = tail[1];
      if (!token) return json({ status: "not_found", message: VO_MESSAGES.not_found }, 404);
      if (tail[2] === "claim") return await claimViewOnce(token, req);
      if (tail[2] === "file") return await serveViewOnceFile(token, url.searchParams.get("k"));
      return await peekViewOnce(token, req);
    }

    if (tail[1] === "file" && tail[2] !== undefined) {
      return await serveFile(
        shareId,
        tail[2],
        url.searchParams.get("mode") ?? "view",
        url.searchParams.get("pw"),
        req,
      );
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
  // share_id (legacy links) - both resolve to the same row.
  const { data, error } = await admin
    .from("document_shares")
    .select(
      "share_id, token, owner_id, document_ids, status, expires_at, views_count, downloads_count, " +
        "processed_paths, processed_names, processed_mimes, view_only, password_hash",
    )
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

function fileKindFromMime(mime: string): { kind: "pdf" | "image" | "other"; mime: string } {
  const m = (mime || "").toLowerCase();
  if (m.includes("pdf")) return { kind: "pdf", mime: mime || "application/pdf" };
  if (m.startsWith("image/")) return { kind: "image", mime };
  return { kind: "other", mime: mime || "application/octet-stream" };
}

function hasProcessedCopies(share: ShareRow): boolean {
  return Array.isArray(share.processed_paths) && share.processed_paths.length > 0;
}

function shareFileCount(share: ShareRow): number {
  return hasProcessedCopies(share) ? share.processed_paths!.length : share.document_ids.length;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

/** Accepts either the stored SHA-256 hex or the plaintext password. */
async function passwordAccepted(share: ShareRow, provided: string | null): Promise<boolean> {
  const expected = (share.password_hash ?? "").trim().toLowerCase();
  if (!expected) return true;
  if (!provided) return false;
  const raw = provided.trim();
  if (!raw) return false;
  const hashed = (await sha256Hex(raw)).toLowerCase();
  return timingSafeEqual(raw.toLowerCase(), expected) || timingSafeEqual(hashed, expected);
}

function passwordDenied(req: Request, shareId: string, wrong: boolean): Response {
  const message = wrong
    ? "Incorrect password."
    : "This document is password protected.";
  if (wantsJson(req)) {
    return json({ status: "password_required", message }, 401);
  }
  return htmlResponse(passwordHtml(shareId, wrong), 401);
}

/** Fetches the share's documents IN ORDER, dropping any that were deleted, and
 *  keeping each one's original position (used as its opaque file handle). */
async function loadCards(share: ShareRow): Promise<Card[]> {
  if (hasProcessedCopies(share)) {
    return share.processed_paths!.map((_p, index) => {
      const mime = share.processed_mimes?.[index] ?? "application/octet-stream";
      const { kind } = fileKindFromMime(mime);
      return {
        index,
        name: share.processed_names?.[index] ?? `Document ${index + 1}`,
        type: "Shared copy",
        kind,
        mime,
      };
    });
  }
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
  const pw = new URL(req.url).searchParams.get("pw");
  if (share.password_hash && !(await passwordAccepted(share, pw))) {
    return passwordDenied(req, shareId, Boolean(pw));
  }

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

  return renderShare("active", req, share.expires_at, cards, shareId, {
    viewOnly: Boolean(share.view_only),
    pw,
  });
}

/** Renders EITHER HTML or JSON depending on the client. */
function renderShare(
  kind: Kind,
  req: Request,
  expiresAt: string | null,
  cards: Card[],
  shareId?: string,
  opts?: { viewOnly?: boolean; pw?: string | null },
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
          viewOnly: Boolean(opts?.viewOnly),
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
  const html = kind === "active"
    ? viewerHtml(cards, expiresAt, shareId ?? "", Boolean(opts?.viewOnly), opts?.pw ?? null)
    : statusHtml(kind);
  return htmlResponse(html, STATUS[kind]);
}

// ---- File proxy (bytes; never exposes storage internals) --------------------

async function serveFile(
  shareId: string,
  handle: string,
  mode: string,
  pw: string | null,
  req: Request,
): Promise<Response> {
  const res = await loadShare(shareId);
  if (res.kind !== "active") return htmlResponse(statusHtml(res.kind), STATUS[res.kind]);
  const share = res.share;

  if (share.password_hash && !(await passwordAccepted(share, pw))) {
    return passwordDenied(req, shareId, Boolean(pw));
  }

  const download = mode === "download";
  if (share.view_only && download) {
    return json({ error: "This document is view-only." }, 403);
  }

  const index = Number.parseInt(handle, 10);
  if (!Number.isInteger(index) || index < 0 || index >= shareFileCount(share)) {
    return htmlResponse(statusHtml("not_found"), 404);
  }

  let objectPath: string;
  let filename: string;
  let documentId: string | null = null;

  if (hasProcessedCopies(share)) {
    objectPath = share.processed_paths![index];
    if (!objectPath) return htmlResponse(statusHtml("not_found"), 404);
    filename = downloadName(
      share.processed_names?.[index] ?? `document-${index + 1}`,
      objectPath,
    );
  } else {
    documentId = share.document_ids[index];

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
    objectPath = doc.file_path;
    filename = downloadName(doc.name, doc.file_path);
  }

  console.log(`[share] sign+proxy share_id=${shareId} index=${index} mode=${mode}`);

  // Signed URL generated + used server-side only; never sent to the client.
  const { data: signed, error: signErr } = await admin.storage
    .from(BUCKET)
    .createSignedUrl(objectPath, SIGNED_URL_TTL);
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
    if (documentId) {
      await admin.from("share_downloads").insert({
        share_id: share.share_id,
        document_id: documentId,
      });
    }
    await admin
      .from("document_shares")
      .update({
        downloads_count: (share.downloads_count ?? 0) + 1,
        last_accessed_at: new Date().toISOString(),
      })
      .eq("share_id", share.share_id);
  }

  const contentType = upstream.headers.get("content-type") ?? mimeFromPath(objectPath);
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

// ---- View Once --------------------------------------------------------------
// One-time links. Every decision is made by Postgres (peek / claim / resolve are
// SECURITY DEFINER RPCs granted to the service role only), so the "exactly once"
// guarantee is a single atomic UPDATE rather than anything this function does.

type VoStatus = "ready" | "viewed" | "expired" | "revoked" | "not_found" | "error";

const VO_MESSAGES: Record<VoStatus, string> = {
  ready: "",
  viewed: "This document has already been viewed or has expired.",
  expired: "This document has already been viewed or has expired.",
  revoked: "This link has been revoked by the sender.",
  not_found: "This document has already been viewed or has expired.",
  error: "Something went wrong. Please try again.",
};

// HTTP status per view-once outcome. A burned link is 410 Gone - the honest code.
const VO_STATUS: Record<VoStatus, number> = {
  ready: 200,
  viewed: 410,
  expired: 410,
  revoked: 410,
  not_found: 404,
  error: 500,
};

function voStatusOf(payload: unknown): VoStatus {
  const s = (payload as { status?: string } | null)?.status;
  switch (s) {
    case "ready":
    case "viewed":
    case "expired":
    case "revoked":
    case "not_found":
      return s;
    case "claimed":
      return "ready";
    default:
      return "error";
  }
}

/** SHA-256 of the caller's IP - forensics without ever storing a raw address. */
async function ipHash(req: Request): Promise<string | null> {
  const raw = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
  if (!raw) return null;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

/** NON-CONSUMING status check. Never burns the link - only /claim does. */
async function peekViewOnce(token: string, req: Request): Promise<Response> {
  console.log(`[view-once] peek token=${token.slice(0, 6)}…`);
  const { data, error } = await admin.rpc("peek_view_once_share", { p_token: token });
  if (error) {
    console.error("[view-once] peek error:", error);
    return wantsJson(req)
      ? json({ status: "error", message: VO_MESSAGES.error }, 500)
      : htmlResponse(viewOnceStatusHtml("error"), 500);
  }
  const payload = (data ?? {}) as Record<string, unknown>;
  const status = voStatusOf(payload);

  if (wantsJson(req)) {
    if (status === "ready") {
      return json(
        {
          status: "ready",
          name: payload.name ?? "Document",
          type: payload.type ?? "Document",
          expiresAt: payload.expiresAt ?? null,
          // How long the recipient gets ON SCREEN once they open it (0 = no
          // limit). Surfaced on the gate so the warning can be specific about
          // what spending the single view actually buys.
          viewSeconds: Number(payload.viewSeconds ?? 0),
        },
        200,
      );
    }
    return json({ status, message: VO_MESSAGES[status] }, VO_STATUS[status]);
  }

  // Browser hitting this function directly (no web frontend in front of it):
  // serve a self-contained one-time viewer so the feature still works.
  if (status === "ready") {
    return htmlResponse(
      viewOnceHtml(token, String(payload.name ?? "Document"), String(payload.type ?? "Document")),
      200,
    );
  }
  return htmlResponse(viewOnceStatusHtml(status), VO_STATUS[status]);
}

/**
 * BURNS the link. The RPC does `update … where viewed = false` atomically, so
 * exactly one caller can ever succeed. On success it hands back a short-lived
 * access key - without it the caller could never fetch the bytes it just earned.
 */
async function claimViewOnce(token: string, req: Request): Promise<Response> {
  if (req.method !== "POST") {
    // Claiming is state-changing on purpose: a GET must never destroy a share.
    return json({ status: "error", message: "Use POST to open this document." }, 405);
  }
  console.log(`[view-once] claim token=${token.slice(0, 6)}…`);
  const { data, error } = await admin.rpc("claim_view_once_share", {
    p_token: token,
    p_ip_hash: await ipHash(req),
  });
  if (error) {
    console.error("[view-once] claim error:", error);
    return json({ status: "error", message: VO_MESSAGES.error }, 500);
  }

  const payload = (data ?? {}) as Record<string, unknown>;
  if (payload.status !== "claimed") {
    const status = voStatusOf(payload);
    return json({ status, message: VO_MESSAGES[status] }, VO_STATUS[status]);
  }

  const accessKey = String(payload.accessKey ?? "");
  // Derive kind/mime from the stored path so the viewer can pick a PDF vs image
  // renderer. The path itself stays server-side and is discarded here.
  let kind: "pdf" | "image" | "other" = "other";
  let mime = "application/octet-stream";
  const { data: resolved } = await admin.rpc("resolve_view_once_file", {
    p_token: token,
    p_access_key: accessKey,
  });
  const filePath = (resolved as { status?: string; filePath?: string } | null)?.filePath;
  if (filePath) {
    const derived = fileKind(filePath);
    kind = derived.kind;
    mime = derived.mime;
  }

  console.log(`[view-once] claimed token=${token.slice(0, 6)}… kind=${kind}`);
  return json(
    {
      status: "claimed",
      accessKey,
      accessExpiresAt: payload.accessExpiresAt ?? null,
      viewedAt: payload.viewedAt ?? null,
      name: payload.name ?? "Document",
      type: payload.type ?? "Document",
      // Authoritative countdown length. The viewer must run its timer off this
      // rather than off whatever the gate rendered a moment earlier.
      viewSeconds: Number(payload.viewSeconds ?? 0),
      kind,
      mime,
    },
    200,
  );
}

/**
 * Streams the claimed document's bytes. Requires the access key minted by
 * /claim, which expires in minutes - so the link being burned doesn't lock the
 * one legitimate viewer out of the document it just opened.
 *
 * Inline only. A view-once document is viewed, not downloaded, so there is no
 * `mode=download` here at all.
 */
async function serveViewOnceFile(token: string, accessKey: string | null): Promise<Response> {
  if (!accessKey) return json({ status: "not_found", message: VO_MESSAGES.not_found }, 404);

  const { data, error } = await admin.rpc("resolve_view_once_file", {
    p_token: token,
    p_access_key: accessKey,
  });
  if (error) {
    console.error("[view-once] resolve error:", error);
    return json({ status: "error", message: VO_MESSAGES.error }, 500);
  }
  const payload = (data ?? {}) as { status?: string; filePath?: string; name?: string };
  if (payload.status !== "ok" || !payload.filePath) {
    console.log(`[view-once] file denied token=${token.slice(0, 6)}…`);
    return json({ status: "expired", message: VO_MESSAGES.expired }, 410);
  }

  // Signed URL minted + consumed server-side; never sent to the client.
  const { data: signed, error: signErr } = await admin.storage
    .from(BUCKET)
    .createSignedUrl(payload.filePath, SIGNED_URL_TTL);
  if (signErr || !signed?.signedUrl) {
    console.error("[view-once] createSignedUrl error:", signErr);
    return json({ status: "error", message: VO_MESSAGES.error }, 500);
  }

  const upstream = await fetch(signed.signedUrl);
  if (!upstream.ok || !upstream.body) {
    console.error(`[view-once] upstream fetch failed status=${upstream.status}`);
    return json({ status: "error", message: VO_MESSAGES.error }, 502);
  }

  const filename = downloadName(payload.name ?? "document", payload.filePath);
  return new Response(upstream.body, {
    status: 200,
    headers: {
      ...CORS,
      "content-type": upstream.headers.get("content-type") ?? mimeFromPath(payload.filePath),
      "cache-control": "no-store, no-cache, must-revalidate, private",
      // Inline only - never an attachment.
      "content-disposition": `inline; filename="${filename}"`,
    },
  });
}

/** Terminal state page for a burned / expired / missing one-time link. */
function viewOnceStatusHtml(kind: VoStatus): string {
  const map: Record<string, { emoji: string; bg: string; title: string; msg: string }> = {
    viewed: {
      emoji: "👁️",
      bg: "rgba(239,83,80,.15)",
      title: "This document has already been viewed",
      msg: "View-once links open exactly one time. Ask the sender for a new link.",
    },
    expired: {
      emoji: "⏳",
      bg: "rgba(245,165,36,.15)",
      title: "This document has already been viewed or has expired",
      msg: "Ask the sender for a new link.",
    },
    revoked: {
      emoji: "🚫",
      bg: "rgba(239,83,80,.15)",
      title: "This link has been revoked",
      msg: "The sender has turned off access to this document.",
    },
    not_found: {
      emoji: "🔍",
      bg: "rgba(148,163,184,.18)",
      title: "This document has already been viewed or has expired",
      msg: "This one-time link doesn’t exist any more.",
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

/**
 * The self-contained one-time viewer served when a browser hits this function
 * directly. The link is NOT burned by loading this page - only by pressing
 * "Open once", which POSTs /claim. That keeps chat-app link previews, refreshes
 * and accidental taps from destroying the share.
 */
function viewOnceHtml(token: string, name: string, type: string): string {
  const base = escapeAttr(token);
  const body = `${brandTop()}
    <div class="wrap">
      <div class="card" id="gate">
        <div class="row">
          <div class="ic">👁️</div>
          <div class="info"><b>${escapeHtml(name)}</b><span>${escapeHtml(type)} · view once</span></div>
        </div>
        <div class="warn">⚠️ This document can be opened <b>only once</b>. As soon as you open it, the
          link expires permanently — so make sure you are ready to read it now.</div>
        <div class="acts">
          <button class="btn view" id="open" type="button">${ICON_VIEW}Open once</button>
        </div>
      </div>
      <div id="stage" class="vo-stage" hidden></div>
      <div class="foot">🔒 One-time secure view via INO</div>
    </div>
    <script>
      (function () {
        var btn = document.getElementById('open');
        var gate = document.getElementById('gate');
        var stage = document.getElementById('stage');
        btn.addEventListener('click', function () {
          btn.disabled = true;
          btn.textContent = 'Opening…';
          fetch(${JSON.stringify(`${base}/claim`)}, { method: 'POST', cache: 'no-store' })
            .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, j: j }; }); })
            .then(function (res) {
              if (!res.ok || res.j.status !== 'claimed') {
                document.body.innerHTML =
                  '<div class="state"><div class="circle" style="background:rgba(239,83,80,.15)">👁️</div>' +
                  '<h2>This document has already been viewed or has expired.</h2></div>';
                return;
              }
              var src = ${JSON.stringify(`${base}/file?k=`)} + encodeURIComponent(res.j.accessKey);
              gate.hidden = true;
              stage.hidden = false;
              stage.innerHTML = res.j.kind === 'image'
                ? '<img alt="" src="' + src + '"/>'
                : '<iframe title="document" src="' + src + '"></iframe>';
            })
            .catch(function () {
              btn.disabled = false;
              btn.textContent = 'Open once';
            });
        });
        // Deterrents only - a browser cannot truly block screenshots.
        document.addEventListener('contextmenu', function (e) { e.preventDefault(); });
      })();
    </script>`;
  const headExtra = `<style>
    .warn{margin-top:12px;padding:11px 13px;border-radius:12px;font-size:13px;line-height:1.5;
          background:rgba(245,165,36,.12);border:1px solid rgba(245,165,36,.35);color:#92400e}
    .vo-stage{background:#0b1220;border-radius:18px;overflow:hidden;min-height:60vh;
              display:flex;align-items:center;justify-content:center}
    .vo-stage img{max-width:100%;height:auto;display:block;-webkit-user-select:none;user-select:none;
                  -webkit-touch-callout:none;pointer-events:none}
    .vo-stage iframe{width:100%;height:78vh;border:0;background:#fff}
    @media (prefers-color-scheme:dark){.warn{color:#fcd34d}}
  </style>`;
  return shell(body, headExtra);
}

// ---- Responses --------------------------------------------------------------

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function htmlResponse(html: string, status: number): Response {
  // `html` is a RAW HTML STRING - never JSON.stringify'd, never wrapped in an
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
  // *.functions.supabase.co domain - so these logs will show text/html while
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
<meta name="theme-color" content="${GREEN}"/>
<title>INO - Shared Documents</title>
<style>
  :root{--brand:${GREEN};--brand-2:${BLUE};--muted:#3d5266;--faint:#5a6f82;--text:#0f172a;--hairline:rgba(9,143,144,.16)}
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
       color:var(--text);background:linear-gradient(180deg,#b3e0e0 0%,#dff3f3 42%,#e6f4f4 100%) fixed;
       min-height:100vh;-webkit-font-smoothing:antialiased}
  .top{background:linear-gradient(135deg,var(--brand),var(--brand-2));padding:20px 16px 44px}
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
  .count{font-size:13.5px;color:var(--muted);font-weight:600}
  .pill{display:inline-flex;align-items:center;gap:6px;background:rgba(9,143,144,.12);
        color:var(--brand);border:1px solid rgba(9,143,144,.28);border-radius:999px;
        padding:5px 11px;font-size:12.5px;font-weight:700}
  .card{background:#fff;border:1px solid var(--hairline);border-radius:18px;padding:16px;margin-bottom:12px;
        box-shadow:0 8px 28px rgba(9,143,144,.1)}
  .row{display:flex;align-items:center;gap:13px}
  .ic{width:46px;height:46px;flex:0 0 auto;border-radius:13px;
      background:linear-gradient(135deg,var(--brand),var(--brand-2));
      display:flex;align-items:center;justify-content:center;font-size:22px}
  .info{min-width:0;flex:1}
  .info b{display:block;font-size:15.5px;font-weight:700;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .info span{font-size:12.5px;color:var(--muted)}
  .acts{display:flex;gap:10px;margin-top:14px}
  .btn{flex:1;display:inline-flex;align-items:center;justify-content:center;gap:7px;text-decoration:none;
       height:44px;border-radius:999px;font-weight:700;font-size:14px;cursor:pointer;border:1px solid transparent}
  .btn svg{width:17px;height:17px}
  .btn.primary,.view{background:linear-gradient(135deg,var(--brand),var(--brand-2));color:#fff}
  .btn.ghost,.dl{background:#fff;border-color:rgba(9,143,144,.28);color:var(--brand)}
  .foot{max-width:680px;margin:24px auto 0;text-align:center;color:var(--muted);font-size:12.5px;
        display:flex;align-items:center;justify-content:center;gap:6px;font-weight:600}
  .state{max-width:520px;margin:8vh auto 0;padding:0 24px;text-align:center}
  .state .circle{width:96px;height:96px;border-radius:50%;margin:0 auto 20px;
                 display:flex;align-items:center;justify-content:center;font-size:44px}
  .state h2{font-size:22px;font-weight:800;margin-bottom:8px}
  .state p{color:var(--muted);font-size:14.5px;line-height:1.5}
  @media (prefers-color-scheme:dark){
    body{background:#0a1926;color:#edf5fb}
    .card{background:#13293a;border-color:rgba(9,143,144,.28);box-shadow:none}
    .dl{background:#13293a;border-color:rgba(9,143,144,.35);color:#edf5fb}
    .count,.info span,.state p,.foot{color:#a8c2d6}
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

function viewerHtml(
  cards: Card[],
  expiresAt: string | null,
  shareId: string,
  viewOnly: boolean,
  pw: string | null,
): string {
  // Relative to the current page (…/share/<shareId>) the file lives at
  // <shareId>/file/<index>, so links resolve correctly on any host prefix.
  const base = escapeAttr(shareId);
  const pwQ = pw ? `&pw=${encodeURIComponent(pw)}` : "";
  const items = cards
    .map(
      (c) => `<div class="card">
        <div class="row">
          <div class="ic">📄</div>
          <div class="info"><b>${escapeHtml(c.name)}</b><span>${escapeHtml(c.type)}</span></div>
        </div>
        <div class="acts">
          <a class="btn view" href="${base}/file/${c.index}?mode=view${pwQ}" target="_blank" rel="noopener">${ICON_VIEW}View</a>
          ${viewOnly ? "" : `<a class="btn dl" href="${base}/file/${c.index}?mode=download${pwQ}">${ICON_DL}Download</a>`}
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

function passwordHtml(shareId: string, wrong: boolean): string {
  const err = wrong
    ? `<p style="color:#b91c1c;font-size:13.5px;margin:0 0 12px">Incorrect password. Try again.</p>`
    : "";
  const body = `${brandTop()}
    <div class="wrap">
      <div class="card">
        <div class="info" style="margin-bottom:14px">
          <b>Password required</b>
          <span>This share is protected. Enter the password the sender gave you.</span>
        </div>
        ${err}
        <form method="GET" action="">
          <input type="password" name="pw" autocomplete="current-password" required
            placeholder="Share password"
            style="width:100%;padding:12px 14px;border-radius:12px;border:1px solid var(--hairline);
                   font-size:15px;margin-bottom:12px"/>
          <button class="btn primary" type="submit" style="width:100%">Unlock</button>
        </form>
      </div>
      <div class="foot">🔒 Shared securely via INO</div>
    </div>`;
  return shell(body);
}

function statusHtml(kind: Kind): string {
  const map: Record<string, { emoji: string; bg: string; title: string; msg: string }> = {
    expired: {
      emoji: "⏳",
      bg: "rgba(220,38,38,.1)",
      title: "Link Expired",
      msg:
        "This secure share link is no longer valid. For your protection, access has been permanently closed.",
    },
    revoked: {
      emoji: "🚫",
      bg: "rgba(220,38,38,.1)",
      title: "Link Revoked",
      msg: "The owner has turned off access to these documents.",
    },
    not_found: {
      emoji: "🔍",
      bg: "rgba(100,116,139,.12)",
      title: "Link not found",
      msg: "This shared link doesn’t exist or has been removed.",
    },
    error: {
      emoji: "⚠️",
      bg: "rgba(217,119,6,.12)",
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
      <div style="display:flex;flex-direction:column;gap:10px;margin-top:24px">
        <a class="btn primary" href="mailto:support@ino.app?subject=Request%20new%20INO%20share%20link">Request New Link</a>
        <a class="btn ghost" href="https://inoapp.in">Return to Dashboard</a>
      </div>
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
