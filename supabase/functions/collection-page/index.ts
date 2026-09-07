// bookmarker — the page at the end of a shared link.
//
// `bookmarker.lol/c/<slug>` is the whole distribution strategy in one URL: it
// has to open, look like bookmarker, and unfurl with a real card in Messages
// and on X for someone who has never heard of us. That rules out rendering it
// in the browser — a link scraper does not run JavaScript, and a page that
// unfurls as a blank rectangle is a link nobody opens. So the HTML is built
// here, on the server, complete.
//
// Two things reach this function:
//   * Cloudflare, rewriting bookmarker.lol/c/<slug> (cloudflare/README.md).
//     That is the real path, and the only one where unfurls work.
//   * docs/404.html, fetching this directly until the Worker is live, so the
//     links work for people today.
// Hence the CORS header: a browser on bookmarker.lol has to be allowed to
// read this response.
//
// `verify_jwt = false` in config.toml — the reader is a stranger with a link,
// and there is no token to check. The slug is the credential, and
// `collection_by_slug` (0011) is the only thing it opens: a security-definer
// RPC returning a fixed shape, called with the anon key. A wrong slug, a
// revoked link and a deleted collection are one answer — `null` — and one
// page, so nothing here can be used to find out which.
//
// The bytes are in ../_shared/collection_html.ts, which is pure and tested by
// Scripts/test_collection_page.mjs. This file is the network and the headers.

import { type Collection, renderCollectionPage } from "../_shared/collection_html.ts";

const SITE = "https://bookmarker.lol";
const SLUG = /^[a-z0-9]{8,16}$/;

/** 60 seconds at the edge. Long enough that a link doing numbers costs one
 *  database round trip a minute; short enough that "turn the link off" means
 *  what the privacy policy says it means. `max-age=0` keeps browsers honest
 *  about it — only the shared cache holds a copy. */
const CACHE = "public, max-age=0, s-maxage=60";

const html = (body: string, status: number, cache: string): Response =>
  new Response(body, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": cache,
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      // The page's own CSP cannot carry this — `frame-ancestors` is ignored in
      // a <meta> tag — so it is a header, and this is the header for it.
      "X-Frame-Options": "DENY",
      // docs/404.html reads this response cross-origin. Nothing here is
      // private — it is a public page — and no credentials are involved.
      "Access-Control-Allow-Origin": "*",
    },
  });

/** Per-response, so the page's CSP can name its two scripts by nonce and
 *  allow no inline anything else. */
function nonce(): string {
  return crypto.randomUUID().replace(/-/g, "");
}

addEventListener("unhandledrejection", (e) => { console.error("unhandled", e.reason); e.preventDefault(); });

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
        "Access-Control-Allow-Headers": "content-type",
        "Access-Control-Max-Age": "86400",
      },
    });
  }
  if (req.method !== "GET" && req.method !== "HEAD") {
    return html(renderCollectionPage(null, { origin: SITE, slug: "", nonce: nonce() }), 405, "no-store");
  }

  const slug = new URL(req.url).searchParams.get("slug") ?? "";
  const opts = { origin: SITE, slug, nonce: nonce() };

  // A malformed slug never reaches the database — same page, same status, so
  // a scanner learns nothing from the difference between "bad shape" and
  // "no such collection".
  if (!SLUG.test(slug)) return html(renderCollectionPage(null, opts), 404, CACHE);

  const base = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!base || !anonKey) {
    console.error("missing SUPABASE_* environment");
    return html(renderCollectionPage(null, opts), 500, "no-store");
  }

  let data: unknown = null;
  try {
    const r = await fetch(`${base}/rest/v1/rpc/collection_by_slug`, {
      method: "POST",
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${anonKey}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({ p_slug: slug }),
    });
    const text = await r.text();
    if (!r.ok) {
      console.error("collection_by_slug", r.status, text.slice(0, 200));
      // Do not cache a failure as if it were a missing collection: a minute of
      // "this link is dead" for a link that is alive is the one wrong answer
      // this page can give.
      return html(renderCollectionPage(null, opts), 502, "no-store");
    }
    data = text ? JSON.parse(text) : null;
  } catch (e) {
    console.error("collection_by_slug", e);
    return html(renderCollectionPage(null, opts), 502, "no-store");
  }

  if (data === null || typeof data !== "object") {
    return html(renderCollectionPage(null, opts), 404, CACHE);
  }

  const collection = data as Collection;
  console.log(JSON.stringify({ slug, items: Array.isArray(collection.items) ? collection.items.length : 0 }));
  return html(renderCollectionPage(collection, opts), 200, CACHE);
});
