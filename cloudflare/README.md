# Cloudflare in front of bookmarker.lol

**What this buys.** One route: `bookmarker.lol/c/<slug>` → the `collection-page`
Edge Function. That is the whole reason Cloudflare enters the picture, and it
is worth being blunt about why nothing cheaper works.

A shared collection has to be a `bookmarker.lol` URL, because a link is an
invitation and an invitation from `pcjuxnhqxyfvgagnblzv.supabase.co` is not one
anybody accepts. And it has to be **server-rendered at that URL**, because the
thing that decides whether a shared link gets tapped is the card that Messages,
WhatsApp, Slack and X draw for it — and every one of those scrapers reads the
HTML the server returned and runs no JavaScript at all. The site is GitHub
Pages: a static host that cannot proxy, cannot rewrite and cannot render. So
something has to sit in front of the domain. A Worker on the free plan is the
smallest thing that can, it changes nothing else about the site, and it is
reversible in one step (put the nameservers back).

The alternatives, and why not:

- **Pre-render each collection into `docs/c/<slug>.html` and commit it.** Every
  edit to a collection becomes a git push, a stale page is the default state,
  and turning a link off means a deploy. A shared page has to be able to go
  dark in a minute.
- **Move the site to Vercel/Netlify/Cloudflare Pages.** Bigger change, more to
  break, and it moves a landing page that works today in order to add one
  route. If the site ever moves for its own reasons, this Worker is deleted and
  the route becomes a rewrite rule — that is the migration, and it is small.
- **Serve the page from the function's own URL and link to that.** Ugly link,
  no brand, and it hands our distribution to a Supabase subdomain.

Until this is switched on, `docs/404.html` fetches the same function from the
browser, so links work for people **today**. Only the unfurls wait.

---

## Runbook

Roughly twenty minutes, most of it waiting for a nameserver change.

### 0. Before you touch anything

Write down what the domain looks like now, so a rollback is a fact and not a
memory. As of writing, `bookmarker.lol` is on Porkbun's nameservers and points
at GitHub Pages:

| Type  | Name | Value |
|-------|------|-------|
| A     | `@`  | `185.199.108.153` |
| A     | `@`  | `185.199.109.153` |
| A     | `@`  | `185.199.110.153` |
| A     | `@`  | `185.199.111.153` |
| AAAA  | `@`  | `2606:50c0:8000::153` |
| AAAA  | `@`  | `2606:50c0:8001::153` |
| AAAA  | `@`  | `2606:50c0:8002::153` |
| AAAA  | `@`  | `2606:50c0:8003::153` |
| CNAME | `www`| `jpwilson.github.io` |

Confirm for yourself before you start — GitHub has changed these before:

```sh
dig +short A bookmarker.lol
dig +short AAAA bookmarker.lol
dig +short CNAME www.bookmarker.lol
dig +short NS bookmarker.lol          # → *.ns.porkbun.com today
```

Also note anything else on the domain that is not in the table — an MX record
for mail, a TXT for a verification, a `_domainkey`. Cloudflare's scan usually
finds them, but you are the one who knows they exist. `hello@bookmarker.lol`
sends through Resend, so **check for its MX/TXT/DKIM records and make sure they
come across** — losing those breaks the notify emails, not the site.

### 1. Add the site to Cloudflare

1. Sign up / log in at <https://dash.cloudflare.com> → **Add a site** →
   `bookmarker.lol` → **Free** plan.
2. Cloudflare scans the existing DNS. **Check every row against the table
   above** and add anything it missed. The four A records, the four AAAA
   records and the `www` CNAME must all be there.
3. Set the proxy status:
   - `@` (the four A and four AAAA records) → **Proxied** (orange cloud). This
     is what puts the Worker in the path.
   - `www` → **Proxied** as well, so the redirect keeps working.
   - Anything that is mail (MX, DKIM, SPF) → **DNS only** (grey cloud). Mail is
     not HTTP and must not be proxied.

### 2. SSL mode: Full

**SSL/TLS → Overview → Full.** Not Flexible, not Full (strict).

- *Flexible* would make Cloudflare talk to GitHub Pages over plain HTTP. That
  is a downgrade on the leg you cannot see, and it breaks GitHub's redirect.
- *Full* encrypts both legs and does not require the origin certificate to
  match the hostname — which is exactly the GitHub Pages case, where the origin
  presents a certificate for `*.github.io`.
- *Full (strict)* would fail for that reason.

Leave **Always Use HTTPS** on.

> **The Pages custom-domain HTTPS check keeps working behind Cloudflare in Full
> mode.** GitHub validates the domain by resolving it and fetching over HTTPS;
> proxied through Cloudflare it still resolves, still answers on 443, and still
> serves the `CNAME` file's domain. The one thing that does break it is
> Flexible mode, and the "Enforce HTTPS" checkbox in the GitHub Pages settings
> may need un-ticking and re-ticking once after the cutover if it complains.

### 3. Change the nameservers at Porkbun

Cloudflare gives you two, of the form `xxx.ns.cloudflare.com`.

Porkbun → **Domain Management** → `bookmarker.lol` → **Authoritative
Nameservers** → replace the four `*.ns.porkbun.com` entries with Cloudflare's
two → save.

Propagation is usually minutes and can be a few hours. Cloudflare emails you
when the zone is active. Nothing about the site changes while you wait — the
records are the same records.

```sh
dig +short NS bookmarker.lol           # → *.ns.cloudflare.com when it has moved
curl -sI https://bookmarker.lol/ | head -n 12    # should still be the landing page
```

### 4. Deploy the Worker

Dashboard: **Workers & Pages → Create → Worker**, name it `collection-proxy`,
**Deploy**, then **Edit code**, paste `cloudflare/collection-proxy.js` over
whatever is there, and **Deploy** again.

Or, from this directory:

```sh
npx wrangler deploy collection-proxy.js --name collection-proxy --compatibility-date 2026-09-01
```

### 5. Add the route

**Workers & Pages → collection-proxy → Settings → Domains & Routes → Add
route:**

- Route: `bookmarker.lol/c/*`
- Zone: `bookmarker.lol`

One route, nothing else. Every other path never reaches the Worker.

### 6. Verify

```sh
# A real collection: 200, HTML, and the collection's own <title>.
curl -sI https://bookmarker.lol/c/<a-real-slug>
curl -s  https://bookmarker.lol/c/<a-real-slug> | grep -E '<title>|og:image|og:url'

# A slug that does not exist: the branded 404 page, status 404.
curl -sI https://bookmarker.lol/c/test
curl -sI https://bookmarker.lol/c/aaaaaaaaaaaa

# The rest of the site is untouched.
curl -sI https://bookmarker.lol/
curl -sI https://bookmarker.lol/privacy
curl -sI https://bookmarker.lol/get
curl -sI https://www.bookmarker.lol/
```

What you want to see on `/c/<slug>`:

- `HTTP/2 200` (or `404` for an unknown slug — `curl -I` on `/c/test` should be
  a 404 with `content-type: text/html`, **not** a GitHub Pages 404).
- `cache-control: public, max-age=0, s-maxage=60`
- `cf-cache-status: MISS` on the first call, `HIT` on the second within a
  minute.

Then paste a real collection link into Messages (or
<https://cards-dev.twitter.com/validator>) and confirm the card shows the
collection's name and a cover rather than the generic bookmarker image.

### 7. Rollback

Put the four Porkbun nameservers back on the domain:

```
curitiba.ns.porkbun.com
fortaleza.ns.porkbun.com
maceio.ns.porkbun.com
salvador.ns.porkbun.com
```

Everything reverts to the GitHub Pages A/AAAA records that were there all
along, and `/c/<slug>` falls back to `docs/404.html`, which still fetches the
function client-side. Nothing is lost but the unfurls. Deleting the Worker or
the route is the smaller rollback if the problem is only the `/c/*` path.

## Part two changed nothing here

Since `0012_collection_expiry.sql` the page can carry a `Link open until …`
line and hands Safari's smart banner `bookmarker://c/<slug>` as its
`app-argument` (the scheme the iPhone app registers), and its primary button
goes straight to the App Store. All of that is inside the HTML the function
returns; the Worker still proxies bytes and sets one header. Nothing to
redeploy on this side — only `collection-page` itself, after the migration.

## Why the Worker sets the content type itself

Supabase's `*.supabase.co` functions domain serves HTML bodies as `text/plain`
with a `Content-Security-Policy: default-src 'none'; sandbox` header on GET
(verified 7 Sep 2026 — it is an anti-phishing rule for their shared domain).
That is fine for `docs/404.html`, which reads the text and writes it into the
document itself, but a scraper hitting the Worker must see `text/html`. The
Worker therefore sets `Content-Type: text/html; charset=utf-8` and drops the
upstream CSP header; the page's own CSP lives in a `<meta>` tag.
