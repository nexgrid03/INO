// Server-side config. SUPABASE_FUNCTIONS_URL is never sent to the browser —
// the frontend proxies the Edge Function so tokens/paths stay hidden.
export const FUNCTIONS_URL =
  process.env.SUPABASE_FUNCTIONS_URL ??
  "https://ilfzppryyojoponkomrw.functions.supabase.co";

export type ShareKind = "pdf" | "image" | "other";

export interface SharedDoc {
  id: string; // opaque position index used in file URLs
  name: string;
  type: string;
  kind: ShareKind;
  mime: string;
}

export interface ShareData {
  status: "active" | "expired" | "revoked" | "not_found" | "error";
  count: number;
  expiresAt: string | null;
  documents: SharedDoc[];
  message?: string;
}

/** Fetches share metadata (JSON) from the Edge Function, server-side. */
export async function fetchShare(token: string): Promise<ShareData> {
  try {
    const res = await fetch(`${FUNCTIONS_URL}/share/${encodeURIComponent(token)}?format=json`, {
      headers: { accept: "application/json" },
      cache: "no-store",
    });
    const json = await res.json();
    return {
      status: json.status ?? "error",
      count: json.count ?? (json.documents?.length ?? 0),
      expiresAt: json.expiresAt ?? null,
      documents: Array.isArray(json.documents) ? json.documents : [],
      message: json.message,
    };
  } catch {
    return { status: "error", count: 0, expiresAt: null, documents: [] };
  }
}
