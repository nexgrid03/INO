import { FUNCTIONS_URL } from "@/lib/config";

// Run on the Node runtime so we can stream arbitrary binary bodies.
export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Proxies a shared file's bytes from the Supabase `share` Edge Function.
 * The browser only ever sees this same-origin URL
 * (`/api/s/<token>/file/<index>`), so the Supabase functions host, the bucket
 * path, signed URLs and tokens are never exposed. Content-Type and
 * Content-Disposition (inline vs attachment) are passed through unchanged.
 */
export async function GET(
  req: Request,
  { params }: { params: { token: string; index: string } },
) {
  const mode = new URL(req.url).searchParams.get("mode") === "download" ? "download" : "view";
  const upstream =
    `${FUNCTIONS_URL}/share/${encodeURIComponent(params.token)}` +
    `/file/${encodeURIComponent(params.index)}?mode=${mode}`;

  const r = await fetch(upstream, { cache: "no-store" });

  const headers = new Headers();
  headers.set("Content-Type", r.headers.get("content-type") ?? "application/octet-stream");
  const disposition = r.headers.get("content-disposition");
  if (disposition) headers.set("Content-Disposition", disposition);
  headers.set("Cache-Control", "no-store");

  return new Response(r.body, { status: r.status, headers });
}
