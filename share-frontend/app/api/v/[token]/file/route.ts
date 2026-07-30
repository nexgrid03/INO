import { FUNCTIONS_URL } from "@/lib/config";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Streams a claimed one-time document's bytes.
 *
 * Requires the `k` access key minted by `/claim` - the token alone is already
 * burned by then, so this is what lets the ONE legitimate viewer actually read
 * the document it just opened. The key expires within minutes, server-side.
 *
 * Inline only: there is no download mode for a view-once document.
 */
export async function GET(req: Request, { params }: { params: { token: string } }) {
  const key = new URL(req.url).searchParams.get("k") ?? "";
  if (!key) return new Response("Not found", { status: 404 });

  const upstream =
    `${FUNCTIONS_URL}/share/v/${encodeURIComponent(params.token)}` +
    `/file?k=${encodeURIComponent(key)}`;

  const r = await fetch(upstream, { cache: "no-store" });

  const headers = new Headers();
  headers.set("Content-Type", r.headers.get("content-type") ?? "application/octet-stream");
  headers.set("Content-Disposition", "inline");
  headers.set("Cache-Control", "no-store, no-cache, must-revalidate, private");

  return new Response(r.body, { status: r.status, headers });
}
