/**
 * bookmarker — bookmarker.lol/c/<slug> → the `collection-page` Edge Function.
 *
 * A shared collection has to live at a bookmarker.lol URL. Not because it is
 * prettier: because a link scraper — Messages, WhatsApp, Slack, X — reads the
 * HTML the server returns and does not run JavaScript, so a shared link that
 * is served by GitHub Pages (a static host with no server-side anything) can
 * only ever unfurl as a blank card. GitHub Pages cannot proxy, cannot rewrite,
 * and cannot render. This Worker is the smallest thing that can.
 *
 * Everything that is not /c/<slug> is passed straight through to the origin,
 * untouched, so the rest of the site is exactly as it is today.
 *
 * Deploy: see cloudflare/README.md. Route: bookmarker.lol/c/*
 */

const FUNCTION = "https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/collection-page";

/** Same shape as the `collections.slug` check in 0011. Anything else is not a
 *  collection link and belongs to the origin — which will serve docs/404.html. */
const SLUG = /^\/c\/([a-z0-9]{8,16})\/?$/;

/** 60 seconds at Cloudflare's edge. The function says the same thing; this
 *  re-asserts it on the way out so a change upstream cannot quietly turn a
 *  shared page into a permanently cached one. Turning a link off has to take
 *  effect in about a minute — the privacy policy says so. */
const CACHE = "public, max-age=0, s-maxage=60";

/** Response headers that are the transport's, not the page's. */
const HOP_BY_HOP = ["connection", "keep-alive", "transfer-encoding", "upgrade", "content-encoding", "content-length"];

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const match = SLUG.exec(url.pathname);
    if (!match) return fetch(request);

    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }

    let upstream;
    try {
      upstream = await fetch(`${FUNCTION}?slug=${match[1]}`, {
        // HEAD upstream would give us no body to hand back on a GET-shaped
        // cache fill; ask for GET and drop the body below instead.
        method: "GET",
        headers: {
          // Pass nothing of the reader's along. The function does not want it,
          // and a shared page should not carry a viewer's fingerprint upstream.
          Accept: request.headers.get("Accept") || "text/html",
          "Accept-Language": request.headers.get("Accept-Language") || "en",
          "User-Agent": request.headers.get("User-Agent") || "bookmarker-proxy",
        },
        cf: { cacheTtl: 60, cacheEverything: true },
      });
    } catch (e) {
      // Upstream is unreachable. Fall through to the origin, which serves
      // docs/404.html — and that page fetches the function itself, so the
      // reader still has a chance of seeing the collection.
      console.log("collection-page upstream failed", e && e.message);
      return fetch(request);
    }

    const headers = new Headers();
    for (const [name, value] of upstream.headers) {
      if (HOP_BY_HOP.indexOf(name.toLowerCase()) < 0) headers.set(name, value);
    }
    headers.set("Cache-Control", CACHE);
    // The page is being served from bookmarker.lol now; nothing needs to read
    // it cross-origin from here.
    headers.delete("Access-Control-Allow-Origin");
    // Supabase's default functions domain refuses to serve HTML as HTML: on a
    // GET it rewrites the type to text/plain and adds a sandboxing CSP header
    // (an anti-phishing measure for *.supabase.co). Verified 2026-09-07. We
    // are not that domain — the page carries its own CSP in a <meta> tag and
    // is served from bookmarker.lol — so the type and the header are ours.
    headers.set("Content-Type", "text/html; charset=utf-8");
    headers.delete("Content-Security-Policy");
    headers.set("X-Frame-Options", "DENY");
    headers.set("Referrer-Policy", "no-referrer");

    return new Response(request.method === "HEAD" ? null : upstream.body, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers,
    });
  },
};
