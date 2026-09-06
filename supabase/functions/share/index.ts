// @ts-nocheck
// ============================================================================
// INO - Public Document Share (Supabase Edge Function)
// ----------------------------------------------------------------------------
// Serves the recipient experience for a scanned QR / opened link.
// HARDENED AGAINST: XSS, MIME SPOOFING, PHISHING AND PASSWORD LEAKAGE.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import bcrypt from "https://esm.sh/bcryptjs@2.4.3";

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
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type, x-share-unlock-token",
};

// Security headers added to all file and HTML responses
const SECURE_HEADERS: Record<string, string> = {
  ...CORS,
  "X-Content-Type-Options": "nosniff",
  "Content-Security-Policy": "sandbox",
  "Referrer-Policy": "no-referrer",
  "X-Frame-Options": "DENY",
  "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
};

// Strict MIME allowlist as required by security spec
const ALLOWED_MIME_TYPES = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.ms-powerpoint",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
]);

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

interface Card {
  index: number;
  name: string;
  type: string;
  kind: "pdf" | "image" | "other";
  mime: string;
}

type Kind = "active" | "expired" | "revoked" | "not_found" | "error";
type LoadResult = { kind: "active"; share: ShareRow } | { kind: Exclude<Kind, "active"> };

const STATUS: Record<Kind, number> = {
  active: 200,
  expired: 410,
  revoked: 410,
  not_found: 404,
  error: 500,
};

// ---- Rate Limiting & Throttling --------------------------------------------

interface RateRecord {
  count: number;
  resetAt: number;
}

const ipRequestMap = new Map<string, RateRecord>();
const passwordFailMap = new Map<string, RateRecord>();
const viewThrottleMap = new Map<string, RateRecord>();

setInterval(() => {
  const now = Date.now();
  for (const [k, v] of ipRequestMap.entries()) {
    if (v.resetAt <= now) ipRequestMap.delete(k);
  }
  for (const [k, v] of passwordFailMap.entries()) {
    if (v.resetAt <= now) passwordFailMap.delete(k);
  }
  for (const [k, v] of viewThrottleMap.entries()) {
    if (v.resetAt <= now) viewThrottleMap.delete(k);
  }
}, 60000);

const SHARE_PROXY_SECRET =
  Deno.env.get("SHARE_PROXY_SECRET") || "ino-share-proxy-v1-production-auth";

const IPV4_REGEX =
  /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;

const IPV6_REGEX =
  /^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|:([0-9a-fA-F]{1,4}:){1,7}|(([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4})|::(ffff(:0{1,4}){0,1}:){0,1}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})$/;

export function isValidIp(ip: string | null | undefined): boolean {
  if (!ip) return false;
  const trimmed = ip.trim();
  return IPV4_REGEX.test(trimmed) || IPV6_REGEX.test(trimmed);
}

export function getClientIp(req: Request): string {
  // 1. Authenticated Proxy Route (e.g. share-frontend on Vercel or localhost)
  // When authorized via proxy token, safely trust the forwarded visitor IP.
  const proxyToken = req.headers.get("x-ino-proxy-token");
  if (proxyToken && proxyToken === SHARE_PROXY_SECRET) {
    const realIp = req.headers.get("x-real-ip")?.trim();
    if (realIp && isValidIp(realIp)) {
      return realIp;
    }

    const forwarded = req.headers.get("x-forwarded-for");
    if (forwarded) {
      const hops = forwarded.split(",").map((s) => s.trim()).filter(Boolean);
      for (const hop of hops) {
        if (isValidIp(hop)) {
          return hop;
        }
      }
    }
  }

  // 2. Direct client connection (mobile app, direct curl):
  // Strictly use platform-provided cf-connecting-ip (Cloudflare edge socket IP).
  // Directly connected untrusted clients CANNOT spoof x-forwarded-for or x-real-ip!
  const cfIp = req.headers.get("cf-connecting-ip")?.trim();
  if (cfIp && isValidIp(cfIp)) {
    return cfIp;
  }

  // 3. Fallback for environments where Cloudflare header is absent (e.g. direct localhost dev):
  const realIp = req.headers.get("x-real-ip")?.trim();
  if (realIp && isValidIp(realIp)) return realIp;

  const forwarded = req.headers.get("x-forwarded-for");
  if (forwarded) {
    const hops = forwarded.split(",").map((s) => s.trim()).filter(Boolean);
    if (hops.length > 0 && isValidIp(hops[hops.length - 1])) {
      return hops[hops.length - 1];
    }
  }

  return "127.0.0.1";
}

function checkIpRateLimit(ip: string): boolean {
  const now = Date.now();
  let record = ipRequestMap.get(ip);
  if (!record || record.resetAt <= now) {
    record = { count: 1, resetAt: now + 60000 };
    ipRequestMap.set(ip, record);
    return true;
  }
  record.count++;
  return record.count <= 60;
}

async function isPasswordLocked(ip: string, shareId: string): Promise<boolean> {
  try {
    const { data, error } = await admin.rpc("check_share_password_lock", {
      p_ip: ip,
      p_token: shareId,
    });
    if (!error && data && data.length > 0) {
      return Boolean(data[0].is_locked);
    }
    // Direct table fallback if RPC unavailable
    const { data: row } = await admin
      .from("share_rate_limits")
      .select("lock_until")
      .eq("ip", ip)
      .eq("token", shareId)
      .maybeSingle();
    if (row && row.lock_until) {
      return new Date(row.lock_until).getTime() > Date.now();
    }
  } catch (e) {
    console.error("[share] isPasswordLocked error:", e);
  }

  // In-memory fallback
  const key = `${ip}:${shareId}`;
  const record = passwordFailMap.get(key);
  if (!record) return false;
  if (record.resetAt <= Date.now()) {
    passwordFailMap.delete(key);
    return false;
  }
  return record.count >= 5;
}

async function recordPasswordFailure(ip: string, shareId: string): Promise<void> {
  try {
    const { error } = await admin.rpc("record_share_password_attempt", {
      p_ip: ip,
      p_token: shareId,
      p_success: false,
    });
    if (error) {
      const { data: existing } = await admin
        .from("share_rate_limits")
        .select("attempts")
        .eq("ip", ip)
        .eq("token", shareId)
        .maybeSingle();
      const attempts = (existing?.attempts ?? 0) + 1;
      const locked = attempts >= 5;
      const lockUntil = locked ? new Date(Date.now() + 15 * 60 * 1000).toISOString() : null;
      await admin.from("share_rate_limits").upsert({
        ip,
        token: shareId,
        attempts,
        last_attempt: new Date().toISOString(),
        lock_until: lockUntil,
      }, { onConflict: "ip,token" });
    }
  } catch (e) {
    console.error("[share] recordPasswordFailure error:", e);
  }

  // Also maintain in-memory fallback
  const key = `${ip}:${shareId}`;
  const now = Date.now();
  let record = passwordFailMap.get(key);
  if (!record || record.resetAt <= now) {
    record = { count: 1, resetAt: now + 15 * 60 * 1000 };
  } else {
    record.count++;
  }
  passwordFailMap.set(key, record);
}

async function clearPasswordFailures(ip: string, shareId: string): Promise<void> {
  try {
    await admin.rpc("record_share_password_attempt", {
      p_ip: ip,
      p_token: shareId,
      p_success: true,
    });
  } catch {
    try {
      await admin.from("share_rate_limits").delete().match({ ip, token: shareId });
    } catch {}
  }
  passwordFailMap.delete(`${ip}:${shareId}`);
}

function shouldRecordView(ip: string, shareId: string): boolean {
  const key = `${ip}:${shareId}`;
  const now = Date.now();
  const record = viewThrottleMap.get(key);
  if (!record || record.resetAt <= now) {
    viewThrottleMap.set(key, { count: 1, resetAt: now + 5 * 60 * 1000 });
    return true;
  }
  return false;
}

// ---- HMAC Unlock Token Helpers ---------------------------------------------

async function createUnlockToken(shareId: string): Promise<string> {
  const exp = Date.now() + 3600 * 1000; // 1 hour token
  const payloadStr = JSON.stringify({ shareId, exp });
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(SERVICE_ROLE_KEY),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(payloadStr));
  const sigHex = Array.from(new Uint8Array(signature)).map((b) => b.toString(16).padStart(2, "0")).join("");
  const payloadB64 = btoa(payloadStr).replace(/=/g, "");
  return `${payloadB64}.${sigHex}`;
}

async function verifyUnlockToken(req: Request, targetShareId: string): Promise<boolean> {
  const tokenHeader = req.headers.get("x-share-unlock-token") || req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (!tokenHeader || !tokenHeader.includes(".")) return false;

  const [payloadB64, sigHex] = tokenHeader.split(".");
  if (!payloadB64 || !sigHex) return false;

  try {
    const payloadStr = atob(payloadB64);
    const payload = JSON.parse(payloadStr) as { shareId: string; exp: number };
    if (!payload.shareId || !payload.exp) return false;
    if (payload.shareId !== targetShareId || payload.exp < Date.now()) return false;

    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(SERVICE_ROLE_KEY),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"]
    );
    const sigBytes = new Uint8Array(sigHex.match(/.{1,2}/g)?.map((byte) => parseInt(byte, 16)) || []);
    return await crypto.subtle.verify("HMAC", key, sigBytes, encoder.encode(payloadStr));
  } catch {
    return false;
  }
}

// ---- Server-Side Magic Byte Content Inspection -----------------------------

async function inspectAndValidateFileContent(
  bytes: Uint8Array,
  path: string,
  declaredMime: string
): Promise<{ valid: boolean; detectedMime: string; reason?: string }> {
  // Convert first 4096 bytes to text for signature scanning
  const headerText = new TextDecoder("utf-8", { fatal: false }).decode(bytes.slice(0, 4096)).toLowerCase();

  // Reject malicious HTML / SVG / JS / XML / Executable content signatures
  if (
    headerText.includes("<html") ||
    headerText.includes("<!doctype") ||
    headerText.includes("<svg") ||
    headerText.includes("<script") ||
    headerText.includes("javascript:") ||
    headerText.includes("onload=") ||
    headerText.includes("onerror=") ||
    headerText.includes("<iframe") ||
    headerText.includes("<embed") ||
    headerText.includes("<object") ||
    headerText.includes("<xml") ||
    headerText.includes("<?xml")
  ) {
    return { valid: false, detectedMime: "text/html", reason: "Forbidden executable or markup content detected in file bytes." };
  }

  // Check binary executable headers
  if (
    (bytes[0] === 0x4d && bytes[1] === 0x5a) || // MZ executable
    (bytes[0] === 0x7f && bytes[1] === 0x45 && bytes[2] === 0x4c && bytes[3] === 0x46) || // ELF binary
    headerText.startsWith("#!/") // Shell script
  ) {
    return { valid: false, detectedMime: "application/x-msdownload", reason: "Executable binary or shell script detected." };
  }

  let detectedMime = "application/octet-stream";

  // PDF magic bytes: %PDF-
  if (bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46 && bytes[4] === 0x2d) {
    detectedMime = "application/pdf";
  }
  // JPEG magic bytes: FF D8 FF
  else if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    detectedMime = "image/jpeg";
  }
  // PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
  else if (
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47 &&
    bytes[4] === 0x0d && bytes[5] === 0x0a && bytes[6] === 0x1a && bytes[7] === 0x0a
  ) {
    detectedMime = "image/png";
  }
  // WEBP magic bytes: RIFF....WEBP
  else if (
    bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
    bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50
  ) {
    detectedMime = "image/webp";
  }
  // OLE Composite Document (DOC, XLS, PPT legacy Office format): D0 CF 11 E0 A1 B1 1A E1
  else if (
    bytes[0] === 0xd0 && bytes[1] === 0xcf && bytes[2] === 0x11 && bytes[3] === 0xe0 &&
    bytes[4] === 0xa1 && bytes[5] === 0xb1 && bytes[6] === 0x1a && bytes[7] === 0xe1
  ) {
    const ext = path.split(".").pop()?.toLowerCase() ?? "";
    if (ext === "xls") detectedMime = "application/vnd.ms-excel";
    else if (ext === "ppt") detectedMime = "application/vnd.ms-powerpoint";
    else detectedMime = "application/msword";
  }
  // OOXML Zip Container (DOCX, XLSX, PPTX Office format): PK\x03\x04
  else if (bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 0x03 && bytes[3] === 0x04) {
    const ext = path.split(".").pop()?.toLowerCase() ?? "";
    if (ext === "xlsx") detectedMime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    else if (ext === "pptx") detectedMime = "application/vnd.openxmlformats-officedocument.presentationml.presentation";
    else detectedMime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  } else {
    // Fallback based on extension if clean
    detectedMime = mimeFromPath(path);
  }

  if (!ALLOWED_MIME_TYPES.has(detectedMime)) {
    return { valid: false, detectedMime, reason: `MIME type '${detectedMime}' is not permitted.` };
  }

  return { valid: true, detectedMime };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: SECURE_HEADERS });

  const clientIp = getClientIp(req);
  if (!checkIpRateLimit(clientIp)) {
    console.warn(`[share] Rate limit exceeded for IP=${clientIp}`);
    return json({ status: "too_many_requests", message: "Too many requests. Please try again later." }, 429);
  }

  try {
    const url = new URL(req.url);
    const parts = url.pathname.replace(/^\/+/, "").split("/").filter(Boolean);
    const i = parts.indexOf("share");
    const tail = i >= 0 ? parts.slice(i + 1) : parts;

    const shareId = tail[0];
    if (!shareId) return renderShare("not_found", req, null, []);

    // ---- View-once namespace: /share/v/<token>[/claim|/file] --------------
    if (shareId === "v") {
      const token = tail[1];
      if (!token || !/^[0-9a-zA-Z]{6,32}$/.test(token)) {
        return json({ status: "not_found", message: VO_MESSAGES.not_found }, 404);
      }
      if (tail[2] === "claim") return await claimViewOnce(token, req);
      if (tail[2] === "file") return await serveViewOnceFile(token, url.searchParams.get("k"));
      return await peekViewOnce(token, req);
    }

    if (!isValidShareRef(shareId)) {
      console.warn(`[share] rejected malformed shareId=${shareId} from IP=${clientIp}`);
      return renderShare("not_found", req, null, []);
    }

    // ---- POST /share/:shareId/unlock endpoint -----------------------------
    if (tail[1] === "unlock") {
      if (req.method !== "POST") {
        return json({ status: "method_not_allowed", message: "Use POST to unlock share." }, 405);
      }
      return await handleUnlockShare(shareId, req, clientIp);
    }

    if (tail[1] === "file" && tail[2] !== undefined) {
      return await serveFile(
        shareId,
        tail[2],
        url.searchParams.get("mode") ?? "view",
        req
      );
    }
    return await serveShare(shareId, req);
  } catch (e) {
    console.error("[share] FATAL:", e);
    return renderShare("error", req, null, []);
  }
});

// ---- Validation -------------------------------------------------------------

const SHARE_ID_RE = /^(?:share_[0-9a-zA-Z]{6,32}|[0-9a-zA-Z]{6,32})$/;

export function isValidShareRef(value: string | null | undefined): boolean {
  return typeof value === "string" && SHARE_ID_RE.test(value);
}

async function loadShare(idOrToken: string): Promise<LoadResult> {
  if (!isValidShareRef(idOrToken)) {
    return { kind: "not_found" };
  }

  const COLS =
    "share_id, token, owner_id, document_ids, status, expires_at, views_count, downloads_count, " +
    "processed_paths, processed_names, processed_mimes, view_only, password_hash";

  let { data, error } = await admin
    .from("document_shares")
    .select(COLS)
    .eq("token", idOrToken)
    .limit(1);

  if (!error && (!data || data.length === 0)) {
    ({ data, error } = await admin
      .from("document_shares")
      .select(COLS)
      .eq("share_id", idOrToken)
      .limit(1));
  }

  if (error) {
    console.error(`[share] load error id/token=${idOrToken}:`, error);
    return { kind: "error" };
  }
  const row = data && data.length > 0 ? data[0] : null;
  if (!row) return { kind: "not_found" };
  const share = row as unknown as ShareRow;

  if (share.status === "revoked") return { kind: "revoked" };

  const expired = share.status === "expired" || new Date(share.expires_at).getTime() <= Date.now();
  if (expired) {
    if (share.status !== "expired") {
      await admin.from("document_shares").update({ status: "expired" }).eq("share_id", share.share_id);
    }
    return { kind: "expired" };
  }

  // Security Hardening (H3): Legacy shares with non-bcrypt hashes must NEVER become public/unprotected.
  // Fail closed by treating any legacy hash share as revoked.
  if (share.password_hash && !share.password_hash.startsWith("$2")) {
    return { kind: "revoked" };
  }

  return { kind: "active", share };
}

function fileKind(path: string | null): { kind: "pdf" | "image" | "other"; mime: string } {
  const ext = (path && path.includes(".") ? path.split(".").pop() : "")?.toLowerCase() ?? "";
  if (ext === "pdf") return { kind: "pdf", mime: "application/pdf" };
  if (["png", "jpg", "jpeg", "webp"].includes(ext)) {
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

/** Verifies password using bcrypt (`crypt(p_password, gen_salt('bf'))`). Only bcrypt hashes are accepted. */
async function passwordAccepted(share: ShareRow, provided: string | null): Promise<boolean> {
  const expected = (share.password_hash ?? "").trim();
  if (!expected) return true;
  if (!provided) return false;
  const raw = provided.trim();
  if (!raw) return false;

  // Enforce bcrypt hash format ($2a$, $2b$, $2y$, or generally $2)
  if (expected.startsWith("$2a$") || expected.startsWith("$2b$") || expected.startsWith("$2y$") || expected.startsWith("$2")) {
    try {
      return bcrypt.compareSync(raw, expected);
    } catch {
      return false;
    }
  }

  // Strictly reject non-bcrypt hashes: NO plain equality, NO hash replay, NO SHA-256 fallback
  return false;
}

function passwordDenied(req: Request, wrong: boolean, locked = false): Response {
  const message = locked
    ? "Too many failed password attempts. Please try again in 15 minutes."
    : wrong
    ? "Incorrect password."
    : "This document is password protected.";
  const status = locked ? 429 : 401;
  return json({ status: locked ? "too_many_requests" : "password_required", message }, status);
}

async function handleUnlockShare(shareId: string, req: Request, clientIp: string): Promise<Response> {
  const res = await loadShare(shareId);
  if (res.kind !== "active") return json({ status: res.kind, message: MESSAGES[res.kind] }, STATUS[res.kind]);
  const share = res.share;

  if (await isPasswordLocked(clientIp, share.share_id)) {
    return passwordDenied(req, true, true);
  }

  let bodyPassword = "";
  try {
    const jsonBody = await req.json();
    bodyPassword = String(jsonBody.password ?? "");
  } catch {
    bodyPassword = "";
  }

  const accepted = await passwordAccepted(share, bodyPassword);
  if (!accepted) {
    await recordPasswordFailure(clientIp, share.share_id);
    const lockedNow = await isPasswordLocked(clientIp, share.share_id);
    return passwordDenied(req, true, lockedNow);
  }

  await clearPasswordFailures(clientIp, share.share_id);
  const unlockToken = await createUnlockToken(share.share_id);
  const cards = await loadCards(share);

  return json(
    {
      status: "active",
      unlockToken,
      shareId: share.share_id,
      count: cards.length,
      expiresAt: share.expires_at,
      viewOnly: Boolean(share.view_only),
      documents: cards.map((c) => ({
        id: String(c.index),
        name: c.name,
        type: c.type,
        kind: c.kind,
        mime: c.mime,
      })),
    },
    200
  );
}

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
  interface DocRow {
    id: string;
    name: string;
    category?: string | null;
    file_path: string;
  }
  const { data, error } = await admin
    .from("documents")
    .select("id, name, category, file_path")
    .in("id", share.document_ids);
  if (error) {
    console.error(`[share] documents error share_id=${share.share_id}:`, error);
    throw error;
  }
  const byId = new Map((data ?? []).map((d: any) => [(d as DocRow).id, d as DocRow]));
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

// ---- Share Endpoint ---------------------------------------------------------

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
  const clientIp = getClientIp(req);

  if (share.password_hash) {
    const isUnlocked = await verifyUnlockToken(req, share.share_id);
    if (!isUnlocked) {
      const locked = await isPasswordLocked(clientIp, share.share_id);
      return passwordDenied(req, false, locked);
    }
  }

  let cards: Card[];
  try {
    cards = await loadCards(share);
  } catch {
    return renderShare("error", req, null, []);
  }

  if (shouldRecordView(clientIp, share.share_id)) {
    await admin.from("share_views").insert({ share_id: share.share_id });
    await admin
      .from("document_shares")
      .update({ views_count: (share.views_count ?? 0) + 1, last_accessed_at: new Date().toISOString() })
      .eq("share_id", share.share_id);
  }

  return renderShare("active", req, share.expires_at, cards, shareId, {
    viewOnly: Boolean(share.view_only),
  });
}

function renderShare(
  kind: Kind,
  req: Request,
  expiresAt: string | null,
  cards: Card[],
  shareId?: string,
  opts?: { viewOnly?: boolean }
): Response {
  const asJson = wantsJson(req);
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
        200
      );
    }
    return json({ status: kind, message: MESSAGES[kind] }, STATUS[kind]);
  }
  const html = kind === "active"
    ? viewerHtml(cards, expiresAt, shareId ?? "", Boolean(opts?.viewOnly))
    : statusHtml(kind);
  return htmlResponse(html, STATUS[kind]);
}

// ---- File Proxy (Hardened Bytes Stream) -------------------------------------

async function serveFile(
  shareId: string,
  handle: string,
  mode: string,
  req: Request
): Promise<Response> {
  const res = await loadShare(shareId);
  if (res.kind !== "active") return json({ error: "Share is not active." }, STATUS[res.kind]);
  const share = res.share;

  if (share.password_hash) {
    const isUnlocked = await verifyUnlockToken(req, share.share_id);
    if (!isUnlocked) {
      return json({ error: "Password unlock token required." }, 401);
    }
  }

  const requestedDownload = mode === "download";
  if (share.view_only && requestedDownload) {
    return json({ error: "This document is view-only." }, 403);
  }

  const index = Number.parseInt(handle, 10);
  if (!Number.isInteger(index) || index < 0 || index >= shareFileCount(share)) {
    return json({ error: "Document not found." }, 404);
  }

  let objectPath: string;
  let filename: string;
  let documentId: string | null = null;

  if (hasProcessedCopies(share)) {
    objectPath = share.processed_paths![index];
    if (!objectPath) return json({ error: "Document not found." }, 404);
    filename = downloadName(
      share.processed_names?.[index] ?? `document-${index + 1}`,
      objectPath
    );
  } else {
    documentId = share.document_ids[index];
    const { data: docData, error } = await admin
      .from("documents")
      .select("id, name, category, file_path, auth_user_id")
      .eq("id", documentId)
      .maybeSingle();

    if (error || !docData) return json({ error: "Document not found." }, 404);
    const doc = docData as DocRow;

    if (doc.auth_user_id !== share.owner_id) {
      console.warn(`[share] ownership mismatch index=${index} share=${shareId}`);
      return json({ error: "Access denied." }, 403);
    }
    if (!doc.file_path) return json({ error: "Document not found." }, 404);
    objectPath = doc.file_path;
    filename = downloadName(doc.name, doc.file_path);
  }

  const { data: signed, error: signErr } = await admin.storage
    .from(BUCKET)
    .createSignedUrl(objectPath, SIGNED_URL_TTL);
  if (signErr || !signed?.signedUrl) {
    console.error(`[share] createSignedUrl error index=${index}:`, signErr);
    return json({ error: "Failed to generate file token." }, 500);
  }

  const upstream = await fetch(signed.signedUrl);
  if (!upstream.ok || !upstream.body) {
    console.error(`[share] upstream fetch failed index=${index} status=${upstream.status}`);
    return json({ error: "Upstream storage fetch failed." }, 502);
  }

  // Buffer file bytes for content inspection
  const rawBytes = new Uint8Array(await upstream.arrayBuffer());
  const declaredMime = upstream.headers.get("content-type") ?? mimeFromPath(objectPath);

  // Server-side content inspection & strict MIME validation
  const validation = await inspectAndValidateFileContent(rawBytes, objectPath, declaredMime);
  if (!validation.valid) {
    console.warn(`[share] REJECTED file share_id=${shareId} index=${index} reason=${validation.reason}`);
    return json({ error: "Security Error: Malicious or unsupported file type detected." }, 415);
  }

  if (requestedDownload) {
    if (documentId) {
      await admin.from("share_downloads").insert({ share_id: share.share_id, document_id: documentId });
    }
    await admin
      .from("document_shares")
      .update({ downloads_count: (share.downloads_count ?? 0) + 1, last_accessed_at: new Date().toISOString() })
      .eq("share_id", share.share_id);
  }

  const finalMime = validation.detectedMime;

  // Strictly enforce INLINE disposition only for PDF and safe image types
  const canInline = finalMime === "application/pdf" || finalMime.startsWith("image/");
  const finalDisposition = canInline && !requestedDownload ? "inline" : "attachment";

  return new Response(rawBytes, {
    status: 200,
    headers: {
      ...SECURE_HEADERS,
      "content-type": finalMime,
      "cache-control": "no-store",
      "content-disposition": formatContentDisposition(finalDisposition, filename),
    },
  });
}

// ---- View Once --------------------------------------------------------------

type VoStatus = "ready" | "viewed" | "expired" | "revoked" | "not_found" | "error";

const VO_MESSAGES: Record<VoStatus, string> = {
  ready: "",
  viewed: "This document has already been viewed or has expired.",
  expired: "This document has already been viewed or has expired.",
  revoked: "This link has been revoked by the sender.",
  not_found: "This document has already been viewed or has expired.",
  error: "Something went wrong. Please try again.",
};

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

async function ipHash(req: Request): Promise<string | null> {
  const raw = getClientIp(req);
  if (!raw || raw === "unknown") return null;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(raw));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

async function peekViewOnce(token: string, req: Request): Promise<Response> {
  const { data, error } = await admin.rpc("peek_view_once_share", { p_token: token });
  if (error) {
    return json({ status: "error", message: VO_MESSAGES.error }, 500);
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
          viewSeconds: Number(payload.viewSeconds ?? 0),
        },
        200
      );
    }
    return json({ status, message: VO_MESSAGES[status] }, VO_STATUS[status]);
  }

  if (status === "ready") {
    return htmlResponse(
      viewOnceHtml(token, String(payload.name ?? "Document"), String(payload.type ?? "Document")),
      200
    );
  }
  return htmlResponse(viewOnceStatusHtml(status), VO_STATUS[status]);
}

async function claimViewOnce(token: string, req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return json({ status: "error", message: "Use POST to open this document." }, 405);
  }
  const { data, error } = await admin.rpc("claim_view_once_share", {
    p_token: token,
    p_ip_hash: await ipHash(req),
  });
  if (error) {
    return json({ status: "error", message: VO_MESSAGES.error }, 500);
  }

  const payload = (data ?? {}) as Record<string, unknown>;
  if (payload.status !== "claimed") {
    const status = voStatusOf(payload);
    return json({ status, message: VO_MESSAGES[status] }, VO_STATUS[status]);
  }

  const accessKey = String(payload.accessKey ?? "");
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

  return json(
    {
      status: "claimed",
      accessKey,
      accessExpiresAt: payload.accessExpiresAt ?? null,
      viewedAt: payload.viewedAt ?? null,
      name: payload.name ?? "Document",
      type: payload.type ?? "Document",
      viewSeconds: Number(payload.viewSeconds ?? 0),
      kind,
      mime,
    },
    200
  );
}

async function serveViewOnceFile(token: string, accessKey: string | null): Promise<Response> {
  if (!accessKey) return json({ status: "not_found", message: VO_MESSAGES.not_found }, 404);

  const { data, error } = await admin.rpc("resolve_view_once_file", {
    p_token: token,
    p_access_key: accessKey,
  });
  if (error) {
    return json({ status: "error", message: VO_MESSAGES.error }, 500);
  }
  const payload = (data ?? {}) as { status?: string; filePath?: string; name?: string };
  if (payload.status !== "ok" || !payload.filePath) {
    return json({ status: "expired", message: VO_MESSAGES.expired }, 410);
  }

  const { data: signed, error: signErr } = await admin.storage
    .from(BUCKET)
    .createSignedUrl(payload.filePath, SIGNED_URL_TTL);
  if (signErr || !signed?.signedUrl) {
    return json({ status: "error", message: VO_MESSAGES.error }, 500);
  }

  const upstream = await fetch(signed.signedUrl);
  if (!upstream.ok || !upstream.body) {
    return json({ status: "error", message: VO_MESSAGES.error }, 502);
  }

  const rawBytes = new Uint8Array(await upstream.arrayBuffer());
  const validation = await inspectAndValidateFileContent(rawBytes, payload.filePath, mimeFromPath(payload.filePath));
  if (!validation.valid) {
    return json({ error: "Security Error: Malicious file detected." }, 415);
  }

  const filename = downloadName(payload.name ?? "document", payload.filePath);
  return new Response(rawBytes, {
    status: 200,
    headers: {
      ...SECURE_HEADERS,
      "content-type": validation.detectedMime,
      "cache-control": "no-store, no-cache, must-revalidate, private",
      "content-disposition": formatContentDisposition("inline", filename),
    },
  });
}

function viewOnceStatusHtml(kind: VoStatus): string {
  const map: Record<string, { emoji: string; bg: string; title: string; msg: string }> = {
    viewed: { emoji: "👁️", bg: "rgba(239,83,80,.15)", title: "This document has already been viewed", msg: "View-once links open exactly one time." },
    expired: { emoji: "⏳", bg: "rgba(245,165,36,.15)", title: "This document has expired", msg: "Ask the sender for a new link." },
    revoked: { emoji: "🚫", bg: "rgba(239,83,80,.15)", title: "This link has been revoked", msg: "The sender has turned off access." },
    not_found: { emoji: "🔍", bg: "rgba(148,163,184,.18)", title: "Link not found", msg: "This link doesn’t exist." },
    error: { emoji: "⚠️", bg: "rgba(148,163,184,.18)", title: "Something went wrong", msg: "Please try again." },
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

function viewOnceHtml(token: string, name: string, type: string): string {
  const base = escapeAttr(token);
  const body = `${brandTop()}
    <div class="wrap">
      <div class="card" id="gate">
        <div class="row">
          <div class="ic">👁️</div>
          <div class="info"><b>${escapeHtml(name)}</b><span>${escapeHtml(type)} · view once</span></div>
        </div>
        <div class="warn">⚠️ This document can be opened <b>only once</b>.</div>
        <div class="acts">
          <button class="btn view" id="open" type="button">${ICON_VIEW}Open once</button>
        </div>
      </div>
      <div id="stage" class="vo-stage" hidden></div>
      <div class="foot">🔒 One-time secure view via INO</div>
    </div>`;
  return shell(body);
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...SECURE_HEADERS, "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function htmlResponse(html: string, status: number): Response {
  return new Response(html, {
    status,
    headers: {
      ...SECURE_HEADERS,
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

const MESSAGES: Record<Kind, string> = {
  active: "",
  expired: "This share link has expired",
  revoked: "This share link has been revoked",
  not_found: "This share link doesn’t exist",
  error: "Something went wrong. Please try again.",
};

function shell(bodyInner: string, headExtra = ""): string {
  return `<!doctype html><html lang="en"><head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<meta name="robots" content="noindex,nofollow"/>
<meta name="referrer" content="no-referrer"/>
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
  viewOnly: boolean
): string {
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
          ${viewOnly ? "" : `<a class="btn dl" href="${base}/file/${c.index}?mode=download">${ICON_DL}Download</a>`}
        </div>
      </div>`
    )
    .join("");

  const count = `${cards.length} document${cards.length === 1 ? "" : "s"}`;
  const pill = expiresAt
    ? `<span class="pill" id="countdown">🔒 Active</span>`
    : "";

  const body = `${brandTop()}
    <div class="wrap">
      <div class="head">
        <h1>Shared Documents</h1>
        <div class="meta"><span class="count">${count}</span>${pill}</div>
      </div>
      ${cards.length ? items : `<div class="card"><div class="info"><b>No documents</b><span>This share has no documents.</span></div></div>`}
      <div class="foot">🔒 Shared securely via INO · private & protected</div>
    </div>`;
  return shell(body);
}

function statusHtml(kind: Kind): string {
  const map: Record<string, { emoji: string; bg: string; title: string; msg: string }> = {
    expired: { emoji: "⏳", bg: "rgba(220,38,38,.1)", title: "Link Expired", msg: "This share link is no longer valid." },
    revoked: { emoji: "🚫", bg: "rgba(220,38,38,.1)", title: "Link Revoked", msg: "The owner has turned off access." },
    not_found: { emoji: "🔍", bg: "rgba(100,116,139,.12)", title: "Link not found", msg: "This shared link doesn’t exist." },
    error: { emoji: "⚠️", bg: "rgba(217,119,6,.12)", title: "Something went wrong", msg: "Please try again." },
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

export function formatContentDisposition(disposition: string, filename: string): string {
  const extMatch = filename.match(/\.([a-z0-9]{1,5})$/i);
  const ext = extMatch ? `.${extMatch[1]}` : "";

  let safeAscii = filename.replace(/[^\x20-\x7E]/g, "_").replace(/["\\]/g, "").trim();
  const asciiBase = safeAscii.replace(/\.[a-z0-9]{1,5}$/i, "").replace(/^_+$/, "").trim();
  if (!asciiBase) {
    safeAscii = `document${ext}`;
  }

  const encodedUtf8 = encodeURIComponent(filename)
    .replace(/['()]/g, escape)
    .replace(/\*/g, "%2A");

  return `${disposition}; filename="${safeAscii}"; filename*=UTF-8''${encodedUtf8}`;
}

function mimeFromPath(path: string): string {
  const ext = (path.includes(".") ? path.split(".").pop() : "")?.toLowerCase() ?? "";
  switch (ext) {
    case "pdf": return "application/pdf";
    case "png": return "image/png";
    case "jpg":
    case "jpeg": return "image/jpeg";
    case "webp": return "image/webp";
    case "doc": return "application/msword";
    case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    case "xls": return "application/vnd.ms-excel";
    case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    case "ppt": return "application/vnd.ms-powerpoint";
    case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
    default: return "application/octet-stream";
  }
}
