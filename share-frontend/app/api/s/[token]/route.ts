import { FUNCTIONS_URL } from "@/lib/config";
import { getProxyHeaders } from "@/lib/client-ip";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Proxies share metadata so the browser can fetch documents with an unlock token header. */
export async function GET(
  req: Request,
  { params }: { params: { token: string } }
) {
  const unlockToken = req.headers.get("x-share-unlock-token") ?? "";
  const qs = new URLSearchParams({ format: "json" });

  const headers: Record<string, string> = {
    accept: "application/json",
    ...getProxyHeaders(req.headers),
  };
  if (unlockToken) {
    headers["x-share-unlock-token"] = unlockToken;
  }

  const r = await fetch(
    `${FUNCTIONS_URL}/share/${encodeURIComponent(params.token)}?${qs.toString()}`,
    {
      headers,
      cache: "no-store",
    }
  );

  return new Response(r.body, {
    status: r.status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Referrer-Policy": "no-referrer",
    },
  });
}
