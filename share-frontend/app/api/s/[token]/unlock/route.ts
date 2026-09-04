import { FUNCTIONS_URL } from "@/lib/config";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Proxies password unlock request via POST to Supabase `share` Edge Function. */
export async function POST(
  req: Request,
  { params }: { params: { token: string } }
) {
  try {
    const body = await req.json();
    const upstream = `${FUNCTIONS_URL}/share/${encodeURIComponent(params.token)}/unlock`;

    const r = await fetch(upstream, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
      },
      body: JSON.stringify(body),
      cache: "no-store",
    });

    const data = await r.json();

    return new Response(JSON.stringify(data), {
      status: r.status,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      },
    });
  } catch {
    return new Response(
      JSON.stringify({ status: "error", message: "Failed to unlock share." }),
      {
        status: 500,
        headers: { "Content-Type": "application/json; charset=utf-8" },
      }
    );
  }
}
