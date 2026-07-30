import { FUNCTIONS_URL } from "@/lib/config";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * Burns a one-time link and returns the short-lived access key.
 *
 * POST-only on purpose: a GET must never be able to destroy a share, so no
 * crawler, prefetch or accidental navigation can consume it. The browser only
 * ever sees this same-origin URL, so the Supabase functions host stays hidden.
 */
export async function POST(_req: Request, { params }: { params: { token: string } }) {
  const upstream = `${FUNCTIONS_URL}/share/v/${encodeURIComponent(params.token)}/claim`;

  const r = await fetch(upstream, {
    method: "POST",
    headers: { accept: "application/json" },
    cache: "no-store",
  });

  const body = await r.text();
  return new Response(body, {
    status: r.status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}
