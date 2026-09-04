import { FUNCTIONS_URL } from "@/lib/config";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Proxies a shared file's bytes from the Supabase `share` Edge Function.
 * Header `x-share-unlock-token` is passed upstream instead of sending passwords in URL parameters.
 */
export async function GET(
  req: Request,
  { params }: { params: { token: string; index: string } }
) {
  const mode = new URL(req.url).searchParams.get("mode") === "download" ? "download" : "view";
  const unlockToken = req.headers.get("x-share-unlock-token") ?? "";

  const qs = new URLSearchParams({ mode });
  const upstream =
    `${FUNCTIONS_URL}/share/${encodeURIComponent(params.token)}` +
    `/file/${encodeURIComponent(params.index)}?${qs.toString()}`;

  const requestHeaders: Record<string, string> = {};
  if (unlockToken) {
    requestHeaders["x-share-unlock-token"] = unlockToken;
  }

  const r = await fetch(upstream, { headers: requestHeaders, cache: "no-store" });

  const headers = new Headers();
  headers.set("Content-Type", r.headers.get("content-type") ?? "application/octet-stream");
  const disposition = r.headers.get("content-disposition");
  if (disposition) headers.set("Content-Disposition", disposition);
  headers.set("Cache-Control", "no-store");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Referrer-Policy", "no-referrer");
  headers.set("X-Frame-Options", "DENY");

  return new Response(r.body, { status: r.status, headers });
}
