// Server-side config. SUPABASE_FUNCTIONS_URL is never sent to the browser -
// the frontend proxies the Edge Function so tokens/paths stay hidden.
export const FUNCTIONS_URL =
  process.env.SUPABASE_FUNCTIONS_URL ??
  "https://ilfzppryyojoponkomrw.functions.supabase.co";

export const SUPABASE_URL =
  process.env.SUPABASE_URL ?? "https://ilfzppryyojoponkomrw.supabase.co";

export const SUPABASE_ANON_KEY =
  process.env.SUPABASE_ANON_KEY ??
  "sb_publishable_AkYUQB5-mxBJkY_tZQu6EQ_JprMvI97";

export type ShareKind = "pdf" | "image" | "other";

export interface SharedDoc {
  id: string; // opaque position index used in file URLs
  name: string;
  type: string;
  kind: ShareKind;
  mime: string;
}

export interface ShareData {
  status: "active" | "expired" | "revoked" | "not_found" | "error" | "password_required";
  count: number;
  expiresAt: string | null;
  documents: SharedDoc[];
  message?: string;
  viewOnly?: boolean;
}

// ---- View Once --------------------------------------------------------------

export type ViewOnceStatus = "ready" | "viewed" | "expired" | "revoked" | "not_found" | "error";

export interface ViewOncePeek {
  status: ViewOnceStatus;
  name: string;
  type: string;
  expiresAt: string | null;
  message?: string;
}

import { SHARE_PROXY_SECRET } from "./client-ip";

/**
 * NON-CONSUMING status check for a one-time link. Rendering the page must never
 * burn the share - only the recipient pressing "Open once" does (which POSTs to
 * `/api/v/<token>/claim`). That keeps chat-app link-preview crawlers, refreshes
 * and accidental taps from destroying it.
 */
export async function peekViewOnce(token: string, clientIp?: string): Promise<ViewOncePeek> {
  try {
    const headers: Record<string, string> = { accept: "application/json" };
    if (clientIp) {
      headers["x-real-ip"] = clientIp;
      headers["x-forwarded-for"] = clientIp;
      headers["x-ino-proxy-token"] = SHARE_PROXY_SECRET;
    }
    const res = await fetch(`${FUNCTIONS_URL}/share/v/${encodeURIComponent(token)}?format=json`, {
      headers,
      cache: "no-store",
    });
    const json = await res.json();
    return {
      status: (json.status ?? "error") as ViewOnceStatus,
      name: json.name ?? "Document",
      type: json.type ?? "Document",
      expiresAt: json.expiresAt ?? null,
      message: json.message,
    };
  } catch {
    return { status: "error", name: "Document", type: "Document", expiresAt: null };
  }
}

/** Fetches share metadata (JSON) from the Edge Function, server-side. */
export async function fetchShare(token: string, pw?: string | null, clientIp?: string): Promise<ShareData> {
  try {
    const qs = new URLSearchParams({ format: "json" });
    if (pw) qs.set("pw", pw);
    const headers: Record<string, string> = { accept: "application/json" };
    if (clientIp) {
      headers["x-real-ip"] = clientIp;
      headers["x-forwarded-for"] = clientIp;
      headers["x-ino-proxy-token"] = SHARE_PROXY_SECRET;
    }
    const res = await fetch(
      `${FUNCTIONS_URL}/share/${encodeURIComponent(token)}?${qs.toString()}`,
      {
        headers,
        cache: "no-store",
      },
    );
    const json = await res.json();
    return {
      status: json.status ?? "error",
      count: json.count ?? (json.documents?.length ?? 0),
      expiresAt: json.expiresAt ?? null,
      documents: Array.isArray(json.documents) ? json.documents : [],
      message: json.message,
      viewOnly: Boolean(json.viewOnly),
    };
  } catch {
    return { status: "error", count: 0, expiresAt: null, documents: [] };
  }
}

