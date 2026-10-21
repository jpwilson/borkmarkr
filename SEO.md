# Discoverability — how bookmarker.lol is set up to be found

Covers both halves of the same job: ranking in Google and Bing, and being
quotable by the answer engines (ChatGPT, Claude, Gemini, Perplexity, Copilot,
Grok). They are not separate disciplines — every answer engine retrieves from
a search index and then quotes pages that are crawlable, plainly written and
well linked. So the work is: be in every index, be readable as plain HTML,
state facts on pages that match the questions people actually ask.

Last reviewed: 21 October 2026.

---

## 1. How the site is served (there is no prerender, and that is the point)

`docs/` is a folder of hand-written HTML served directly by GitHub Pages
(`docs/CNAME` → bookmarker.lol, `docs/.nojekyll` so nothing is transformed).
There is no bundler, no SSR and no prerender step, which means the bytes in the
repo are exactly the bytes a crawler receives. Nothing is user-agent sniffed,
so there is no cloaking risk and bots that do not run JavaScript — GPTBot,
ClaudeBot, PerplexityBot and most AI fetchers — see the full text.

One page needs an explanation: **`/` is the web app**, not a brochure. Its
marketing copy lives in two sections of `docs/index.html`:

- `#auth` — the signed-out pitch and the sign-in card, and
- `#home-about` — the explainer below the fold: what bookmarker is, the
  features, the three-step flow, what it costs, five common questions, and
  links to every written page.

Both are plain HTML, always present in the document, and `render()` in
`docs/index.html` hides them (and shows `#app`) the moment you are signed in or
in demo mode — the same one line that has always hidden `#auth`:

```js
$("auth").hidden = !!s || demoMode;
$("home-about").hidden = !!s || demoMode;
```

A crawler is a signed-out visitor, so it gets what a signed-out visitor gets.

**GitHub Pages serves extensionless URLs.** A request for `/faq` returns
`docs/faq.html` with a 200, and `/faq.html` also works. The canonical form
everywhere — canonicals, sitemap, internal links — is the extensionless one.
Directories (`/app/`, `/press/`, `/palace/`, `/get/`) 301 to the trailing
slash, so those canonicals carry the slash. Unknown paths return a real 404
with `docs/404.html` (which is `noindex`); nothing soft-404s.

## 2. What is on each page

Every public page carries a unique `<title>` and meta description, exactly one
`<h1>`, an absolute self-referencing `<link rel="canonical">` on
`https://bookmarker.lol`, Open Graph and Twitter card tags, and `lang="en"`.

JSON-LD mirrors the visible text and nothing more:

| Page | Structured data |
|---|---|
| `/` | WebSite, Organization, MobileApplication, WebApplication, FAQPage |
| `/app/` | MobileApplication, Organization, BreadcrumbList |
| `/what-is-bookmarker` | MobileApplication, Organization, BreadcrumbList, Article |
| `/faq` | FAQPage, MobileApplication, BreadcrumbList |
| `/alternatives`, `/vs-*` | BreadcrumbList, Article, MobileApplication |
| `/how-to-*` | BreadcrumbList, HowTo, Article, MobileApplication |
| `/press/` | Organization, BreadcrumbList |

**Rules that must not be broken when editing any of this:**

- The only price that may appear is the real one. The app is free on the App
  Store (`price: "0"`, USD), confirmed against the live iTunes lookup for app
  id `6799805479`. The `$30` on `/lifetime` is a *reservation* for a future
  paid version — payments are not switched on and no card is taken — so it is
  never an `Offer`.
- **No `aggregateRating`, ever.** The App Store listing has a single rating.
  Inventing or scraping one is a manual-action risk.
- No invented users, customers, testimonials or statistics appear anywhere.
- Competitor claims are quoted from the competitor's own site, linked, dated
  ("checked on 21 October 2026") and paired with where that competitor is
  better than bookmarker. If a detail cannot be confirmed, it is left out.

### Claims that were wrong and are now fixed

The earlier AI-discovery pass (PR #89) asserted things the product does not do.
If you are editing copy, these are the traps:

- bookmarker does **not** do full-text search of the page behind a link — it
  never fetches an article body, a PDF or a transcript. But it does search the
  post text it happens to hold, so "it does not index the inside of posts" is
  too strong and has been removed from every page.
  `Core/Bookmark.swift:rebuildSearchBlob()` builds the haystack from title,
  author, `text`, note, subcategory, tags, category name, platform name and
  URL — and `text` is real post text: the `og:description` excerpt stored by
  `App/PreviewFetcher.swift`, or the whole `full_text` of an X post imported
  from a data export (`Core/Importers.swift:parseXArchive`, and `body_text` in
  `docs/import.js`). `Core/SearchScope.swift` adds the Topics / Subtopics /
  Tags scoping. Terms are ANDed; there is no quoted-phrase or operator syntax.
- Filing is **not** purely on-device and **not** purely keyword-based, and no
  page may say it is. `Core/Categorizer.swift` is the offline keyword pass and
  always runs first. `Core/SmartCategorizer.swift` then posts the link, title,
  author, post text, `og:description`, hashtags and the user's own tags to the
  `categorize` Supabase Edge Function, which asks a language model — but only
  when the offline pass was unconfident **and** there is a session
  (`App/Screens/AddSheet.swift`, `App/PreviewFetcher.swift`, and
  `suggestTopicFor()` in `docs/index.html` for the web). Notes are never sent,
  low-confidence answers are dropped server-side, and signed out it never
  fires. `docs/privacy.html` already described this correctly; the written
  pages claimed "not a language model", which is the contradiction not to
  reintroduce.
- Competitor copy must not turn "you do not have to" into "you cannot". mymind
  tells people they need not file, label or tag anything, but its own Spaces
  guide documents user tags, Smart Spaces and adding an item to a Space by
  hand — so the pages say "AI-assisted organisation, with optional user tags
  and Smart Spaces", not "no tags by design".
- There is **no iCloud sync**. Signing in (email + six-digit code) backs the
  library up and makes it readable on the web.
- There is **no premium tier**. `APPSTORE.md` is explicit: "There is no paid
  tier and nothing in the app costs money."
- bookmarker is **not iOS-only** — there is an iPhone app and a web app that
  runs in any browser, including on Android and on a desktop. "No Android app
  and no browser extension" is true and is a different statement: a comparison
  page may say a rival ships native Android and desktop apps and extensions,
  but it may not imply bookmarker is unusable in those browsers.

## 3. Crawlers

`docs/robots.txt` allows everything public and names each crawler explicitly,
because several of them only read the group that names them: OAI-SearchBot,
ChatGPT-User, GPTBot, Claude-SearchBot, Claude-User, ClaudeBot, anthropic-ai,
PerplexityBot, Perplexity-User, Googlebot, Googlebot-Image, Google-Extended,
bingbot, Applebot, Applebot-Extended, DuckAssistBot, meta-externalagent,
meta-externalfetcher, CCBot, Amazonbot, Bytespider, cohere-ai, YouBot.

Training bots are allowed on purpose: a model that has read the site is a model
that can recommend it.

Only two paths are closed:

- `/c/` — shared collections. Other people's content, with its own link and an
  expiry, served by the Cloudflare Worker in `cloudflare/collection-proxy.js`.
- `/web/` — a redirect stub that already carries `noindex`.

`docs/sitemap.xml` lists the 16 canonical, indexable, 200-returning URLs with
`lastmod`. Redirect stubs (`/get/`, `/web/`) and `/c/<slug>` are deliberately
absent.

## 4. llms.txt and llms-full.txt

`docs/llms.txt` is a short, accurate summary — what bookmarker is, what it
does, **what it deliberately does not do**, what it costs, and the absolute URL
of every key page. `docs/llms-full.txt` is the plain text of every public page.

Worth knowing: large studies (Ahrefs, SE Ranking) find no measurable citation
benefit from llms.txt and that almost no one fetches it. It is here because it
is cheap and coding agents do read it — not because it moves rankings. Do not
spend real effort on it. What it must never be is a placeholder or the SPA
shell; `/llms-full.txt` used to return the 404 page, which is worse than a 404.

Both are `.txt` files, so GitHub Pages serves them as `text/plain`.

Regenerate after changing any public page:

```bash
python3 Scripts/gen_llms_full.py
```

## 5. Verification (owner steps — these need you to sign in)

Nothing fake has been added to the repo. No verification meta tags, no
placeholder tokens. When you are ready:

**Google Search Console** — https://search.google.com/search-console

1. Add a **Domain** property for `bookmarker.lol` (covers every subdomain and
   both schemes). This needs a DNS `TXT` record at your registrar; Google shows
   you the exact value.
2. If you would rather not touch DNS, add a **URL prefix** property for
   `https://bookmarker.lol/` and use the HTML tag method — paste the
   `<meta name="google-site-verification" content="…">` tag into the `<head>`
   of `docs/index.html`, commit, wait for Pages to deploy, then click Verify.
3. Submit `https://bookmarker.lol/sitemap.xml` under **Sitemaps**.
4. Check **Settings → Search generative AI** is left at its default (included),
   and watch the Generative AI performance report.

**Bing Webmaster Tools** — https://www.bing.com/webmasters

1. Sign in and choose **Import from Google Search Console** — it carries the
   verification and the sitemap across in one step.
2. Otherwise verify with the XML file or the meta tag, then submit the sitemap.
3. Bing matters more than its market share suggests: it feeds Copilot,
   DuckDuckGo and part of ChatGPT's search.

**Apple** — nothing to do; Applebot is allowed and `/app/` already carries the
`apple-itunes-app` meta tag with app id `6799805479`.

## 6. IndexNow

The key is hosted at
`https://bookmarker.lol/d38c259473bfbc5ad6c60ed9ff497121.txt`, and the file
contains the key itself — that is how IndexNow proves you control the host. It
is public by design and is not a secret.

```bash
node Scripts/indexnow.mjs --dry-run   # print the URLs that would be submitted
node Scripts/indexnow.mjs             # submit to api.indexnow.org
```

Run it **after** the change is live on bookmarker.lol, not before — it tells
Bing, Yandex, Seznam and Naver to come and look. Google does not accept
IndexNow; for Google, publish and let Googlebot find it, or request indexing in
Search Console.

> It has never been run against the live API from this repo. The first real run
> is yours to make.

## 7. Adding a new page

1. Write the content into `Scripts/seo-pages/` — `tpl.py` holds the shared
   head, header nav and footer; the `pages_*.py` files hold the copy. Then:

   ```bash
   python3 Scripts/seo-pages/pages_core.py     # or whichever file you edited
   ```

   The output is committed static HTML in `docs/`, resolved from `tpl.py`'s own
   location, so this works in any checkout. (You can equally hand-write a page;
   the generator exists so the shared furniture has one definition.)

2. Add the page to the header nav and the footer in `tpl.py` and re-run every
   `pages_*.py`, so the new page is linked from all the others.
3. Add it to `docs/sitemap.xml` with today's `lastmod`.
4. Add it to the `PAGES` list in `Scripts/gen_llms_full.py` and to the key-pages
   list in `docs/llms.txt`, then regenerate `llms-full.txt`.
5. Add it to `PAGES` (and `MARKETING`, if it is a sales page) in
   `Scripts/check-seo.mjs`.
6. Link to it from `#home-about` in `docs/index.html` and from the footer of
   `docs/app/index.html`.
7. Run the checks below.

Content rules for anything new: the first sentence says what it is and who it
is for, in plain words; the `<h1>` carries the brand and the category; one page
per real intent, not per keyword variant (mass-producing near-duplicate pages
is "scaled content abuse" and Google says so explicitly); and every claim has
to be traceable to this repo, the live site, or a dated quote from a
competitor's own site.

## 8. Checks

```bash
node Scripts/check-seo.mjs    # 402 assertions over the committed HTML
npm install && npm run test:sync
node Scripts/test_palace.mjs
for t in Scripts/test_*.mjs; do node "$t" >/dev/null || echo "FAIL $t"; done
```

`check-seo.mjs` asserts, per page: a unique title and description, one `<h1>`,
an absolute self-referencing canonical, OG and Twitter tags, JSON-LD that
parses and declares schema.org, no `aggregateRating`, more than 300 words of
JavaScript-free text, and links to the hub pages. Site-wide it asserts the
robots.txt bot groups and `Sitemap:` line, that the sitemap is complete,
canonical-form and duplicate-free, that `llms.txt` and `llms-full.txt` are real
text rather than the HTML shell, and that the IndexNow key file and the script
agree.

Run it before every push that touches `docs/`.

## 9. Measuring whether any of this worked

- Search Console → Generative AI performance report, and Bing Webmaster → AI
  performance.
- `utm_source=chatgpt.com` and similar referrers in PostHog.
- Once a month, ask the engines directly: "best app for organising saved
  Instagram and TikTok posts", "how do I search my X bookmarks",
  "bookmarker vs Raindrop" — in ChatGPT, Claude, Perplexity, Gemini and Grok,
  and note whether bookmarker.lol is cited.

The biggest remaining lever is off-site and not in this repo: directory
listings, "best of" roundups, Reddit and Hacker News threads, and posts on X
(Grok searches X directly). Pages this good still need someone else to link to
them.
