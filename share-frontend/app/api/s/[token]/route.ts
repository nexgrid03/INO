import { FUNCTIONS_URL } from "@/lib/config";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Proxies share metadata so the browser can unlock a password-gated link. */
export async function GET(
  req: Request,
  { params }: { params: { token: string } },
) {
  const pw = new URL(req.url).searchParams.get("pw") ?? "";
  const qs = new URLSearchParams({ format: "json" });
  if (pw) qs.set("pw", pw);

  const r = await fetch(
    `${FUNCTIONS_URL}/share/${encodeURIComponent(params.token)}?${qs.toString()}`,
    {
      headers: { accept: "application/json" },
      cache: "no-store",
    },
  );

  return new Response(r.body, {
    status: r.status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}
