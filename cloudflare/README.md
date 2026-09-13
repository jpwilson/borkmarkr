# Public collection routing

Status: reviewed code and local tests, **not a production deployment**.

GitHub Pages can return a 404 bootstrap that renders a collection in a browser,
but link-preview crawlers do not run that JavaScript. Acceptance requires
`https://bookmarker.lol/c/<live-slug>` itself to return HTTP 200 with the
collection's HTML and Open Graph metadata. A rendered page after an HTTP 404
is not success.

## Deploy only after infrastructure approval

1. Inventory current DNS and export it, including all MX, SPF, DKIM and other
   verification records. Do not reuse old nameserver values from a document.
2. Confirm the domain is an active, proxied Cloudflare zone before using the
   checked-in route. If moving nameservers is necessary, obtain owner approval
   and preserve the complete DNS export. Do not combine DNS cutover with an
   unverified app release.
3. Use Full (strict) when the origin has a valid, unexpired certificate matching
   the origin hostname. Validate GitHub Pages custom-domain HTTPS first.
   Do not downgrade certificate validation merely to make a failing setup pass.
   See [Cloudflare's Full (strict) requirements](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/full-strict/).
4. Deploy the Supabase migrations and `collection-page` function first.
5. From this directory, an authorized operator can run `npx wrangler deploy`.
   [Wrangler route configuration](https://developers.cloudflare.com/workers/wrangler/configuration/)
   is checked in as `wrangler.toml`; only `bookmarker.lol/c/*` is intercepted.
   No deployment-on-merge workflow or DNS mutation is added by this repair.

## Acceptance

Use a dedicated test collection, never publish private review screenshots.

- GET an active collection: 200, HTML, its actual title, canonical URL and
  `og:title`/`og:image` in the raw response with JavaScript disabled.
- HEAD: same status and headers, no body.
- Unknown, revoked, deleted, expired: no saved content. Test actual revocation
  after first loading the active page, allowing at most the documented 60-second
  edge cache window.
- Upstream outage: 503, `Cache-Control: no-store`, retry message. Never a cached
  “dead link.” Incoming cookies and authorization are not forwarded upstream.
- Open an actual link from Messages, Safari and a signed-out desktop browser;
  confirm original links, topic/subtopic/tags and the large app CTA.
- Home, login, privacy, app links and email DNS must remain unaffected.

Local transport tests: `node Scripts/test_collection_proxy.mjs`.
Renderer tests: `node Scripts/test_collection_page.mjs`.

## Rollback

Remove/disable only the Worker route first. The rest of the website remains on
its existing origin. Collection links return to the limited Pages bootstrap;
unfurls will fail that acceptance gate. Restore DNS only from the verified
pre-cutover export if the DNS change itself caused the problem.
