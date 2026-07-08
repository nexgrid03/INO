// ============================================================================
// INO — Share page proxy (Cloudflare Worker)
// ----------------------------------------------------------------------------
// WHY THIS EXISTS:
// The Supabase Edge Runtime, on the shared *.functions.supabase.co domain,
// forcibly rewrites `Content-Type: text/html` → `text/plain` and injects
// `X-Content-Type-Options: nosniff` + `Content-Security-Policy: sandbox`
// (an anti-abuse measure). That makes browsers show the share page as SOURCE
// instead of rendering it. JSON and file bytes are NOT downgraded — only HTML.
//
// This Worker sits on a domain YOU control (e.g. share.yourdomain.com), proxies
// to the `share` Edge Function, and re-serves the share page as real text/html
// so browsers render it. File byte endpoints stream straight through.
//
// DEPLOY (free):
//   1. Cloudflare → Workers & Pages → Create Worker → paste this.
//   2. Add a route/custom domain, e.g. share.yourdomain.com/*  → this Worker.
//   3. In lib/config/share_config.dart set:
//        customBaseUrlOverride = 'https://share.yourdomain.com/share'
//      so NEW QR codes encode your domain.
//   4. (Optional) add your domain's host to the App Links intent-filter and
//      host /.well-known/assetlinks.json on it (see DEEP_LINKING.md).
// ============================================================================

const SUPABASE_FUNCTIONS = "https://ilfzppryyojoponkomrw.functions.supabase.co";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const upstream = SUPABASE_FUNCTIONS + url.pathname + url.search;

    // File byte endpoints (…/share/<id>/file/<index>) already return correct
    // types (image/*, application/pdf, …) — stream them straight through.
    if (url.pathname.includes("/file/")) {
      return fetch(upstream, {
        method: request.method,
        headers: { accept: request.headers.get("accept") ?? "*/*" },
        redirect: "manual",
      });
    }

    // The share page: ask the function for HTML, read the bytes, and re-serve
    // them as REAL text/html on this domain (Supabase's downgrade doesn't apply
    // here). Drop the sandbox CSP / nosniff so the browser renders normally.
    const resp = await fetch(upstream, { headers: { accept: "text/html" } });
    const body = await resp.text();
    return new Response(body, {
      status: resp.status,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      },
    });
  },
};
