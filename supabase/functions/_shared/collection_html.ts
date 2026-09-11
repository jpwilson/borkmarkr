// bookmarker — the HTML of a shared collection page.
//
// Pure: no Deno, no fetch, no clock, no randomness. Everything that varies is
// an argument, so `Scripts/test_collection_page.mjs` can run this exact file
// under node and assert what a stranger's browser will actually receive. The
// Edge Function (`collection-page/index.ts`) does the network and the headers;
// this does the bytes.
//
// Everything here is **owner-controlled text on a page we serve to the public**
// — a collection name, a note, a bork's title, an author handle, a URL. So:
//
//   * every interpolation goes through `esc`, without exception;
//   * every `href` goes through `safeHref`, which will only emit http(s) — a
//     saved `javascript:` URL renders as inert text rather than a link;
//   * every `<img src>` goes through `shareableImage`, which allows our own
//     storage plus a short list of hosts known to serve permanent thumbnails,
//     and nothing else. That is stricter than "any https image" on purpose:
//     without it, a collection could be assembled to make every viewer's
//     browser call a host of the owner's choosing;
//   * the page's own CSP is the backstop for all three, with a per-response
//     nonce so there is not one inline handler or `style=` attribute to allow.
//
// The types are deliberately simple — signature annotations and plain
// interfaces only — because the node test strips them with a small regex.
//
// Type declarations ────────────────────────────────────────────────────────
export interface CollectionItem {
  id: string;
  url: string;
  title: string;
  author: string | null;
  platform: string;
  kind: string;
  category_id: string | null;
  subcategory: string | null;
  tags: string[];
  image_url: string | null;
  duration_seconds: number | null;
  body_text: string | null;
}

export interface Collection {
  id: string;
  name: string;
  note: string | null;
  owner_name: string;
  updated_at: string;
  expires_at: string | null;
  items: CollectionItem[];
}

export interface RenderOptions {
  origin: string;
  slug: string;
  nonce: string;
}

export interface Topic {
  name: string;
  hue: number;
}
// ──────────────────────────────────────────────────────────────────────────

const SITE = "https://bookmarker.lol";
const APP_ID = "6799805479";
/** The page's one job is to get the app installed: the primary button goes
 *  straight to the listing, not through /get, so an iPhone is one tap from
 *  the store and nothing else is in the way. */
const APP_STORE = "https://apps.apple.com/app/id" + APP_ID;
const FALLBACK_IMAGE = "/img/share-v2.jpg";

/** Our own Supabase project: the thumbs and topic-art buckets. */
const STORAGE = "https://pcjuxnhqxyfvgagnblzv.supabase.co";

/** Public project token by design, same as docs/index.html; disclosed in the
 *  privacy policy. The loader pulls its script from the `-assets` host and
 *  posts events to the api host, so the CSP has to name both. */
const PH_TOKEN = "phc_o34s8vv6TWjzDemdh39CAW8d4R52qFzVt2RZCnQEEKqx";
const PH_HOST = "https://us.i.posthog.com";
const PH_ASSETS = "https://us-assets.i.posthog.com";

const FONTS_CSS = "https://fonts.googleapis.com";
const FONTS_FILES = "https://fonts.gstatic.com";

/** Hosts whose thumbnail URLs are permanent. Instagram and TikTok are absent
 *  because everything they hand out expires — 0008 mirrors those into our own
 *  bucket, which is the first entry. */
const IMAGE_HOSTS = [
  STORAGE,
  "https://i.ytimg.com",
  "https://img.youtube.com",
  "https://pbs.twimg.com",
  "https://i.pinimg.com",
];

/** id:name:hue for the 50 built-in topics, from Core/Taxonomy.swift by way of
 *  docs/taxonomy.js. Kept as one string so the whole map costs ~1KB. */
const TOPICS_RAW =
  "fashion:Fashion:326|grooming:Hair & grooming:332|relationships:Relationships:338|beauty:Beauty:344|" +
  "health:Health:352|mentalhealth:Mental health:358|truecrime:True crime:4|cars:Cars & motors:11|" +
  "crafts:Crafts & making:18|diy:DIY & repairs:24|home:Home & interiors:30|fooddrink:Food & drink:36|" +
  "recipes:Recipes:42|history:History:48|trades:Trades & skills:54|comedy:Comedy:60|pets:Pets:66|" +
  "cleaning:Cleaning & organising:72|homestead:Homestead:88|garden:Garden:96|outdoors:Outdoors:106|" +
  "nature:Nature:116|parenting:Parenting:128|babyprep:Pregnancy & baby:138|nutrition:Nutrition:146|" +
  "fitness:Fitness:152|investing:Investing:160|money:Money:168|crypto:Crypto:174|business:Business:180|" +
  "science:Science:186|marketing:Marketing:192|tech:Tech:197|travel:Travel:202|sports:Sports:208|" +
  "photovideo:Photo & video:214|creator:Creator:220|coding:Coding:226|news:News & politics:232|" +
  "career:Career & work:238|learning:Learning:248|ai:AI:256|gaming:Gaming:264|wellness:Wellness:272|" +
  "anime:Anime & comics:280|music:Music:288|filmtv:Film & TV:296|beliefs:Beliefs:304|books:Books:312|" +
  "art:Art & design:320";

const TOPICS = new Map(
  TOPICS_RAW.split("|").map((row) => {
    const parts = row.split(":");
    return [parts[0], { name: parts[1], hue: Number(parts[2]) }];
  }),
);

/** Simple Icons paths, the same seven the web app inlines. Anything else gets
 *  the two-or-three letter fallback, so a new platform never renders blank. */
const GLYPHS = {
  x: "M14.234 10.162 22.977 0h-2.072l-7.591 8.824L7.251 0H.258l9.168 13.343L.258 24H2.33l8.016-9.318L16.749 24h6.993zm-2.837 3.299-.929-1.329L3.076 1.56h3.182l5.965 8.532.929 1.329 7.754 11.09h-3.182z",
  instagram: "M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.205-.012 3.584-.069 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zM12 0C8.741 0 8.333.014 7.053.072 2.695.272.273 2.69.073 7.052.014 8.333 0 8.741 0 12c0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98C8.333 23.986 8.741 24 12 24c3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98C15.668.014 15.259 0 12 0zm0 5.838a6.162 6.162 0 1 0 0 12.324 6.162 6.162 0 0 0 0-12.324zM12 16a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm6.406-11.845a1.44 1.44 0 1 0 0 2.881 1.44 1.44 0 0 0 0-2.881z",
  tiktok: "M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z",
  youtube: "M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z",
  shorts: "m18.931 9.99-1.441-.601 1.717-.913a4.48 4.48 0 0 0 1.874-6.078 4.506 4.506 0 0 0-6.09-1.874L4.792 5.929a4.504 4.504 0 0 0-2.402 4.193 4.521 4.521 0 0 0 2.666 3.904c.036.012 1.442.6 1.442.6l-1.706.901a4.51 4.51 0 0 0-2.369 3.967A4.528 4.528 0 0 0 6.93 24c.725 0 1.437-.174 2.08-.508l10.21-5.406a4.494 4.494 0 0 0 2.39-4.192 4.525 4.525 0 0 0-2.678-3.904ZM9.597 15.19V8.824l6.007 3.184z",
  threads: "M18.263 11.097c-.03-3.486-1.92-5.586-5.111-5.586-2.13 0-3.922.963-4.863 2.499l2.062 1.438c.535-.843 1.272-1.543 2.628-1.543 1.528 0 2.318.85 2.544 2.431a15 15 0 0 0-2.236-.173c-4.125 0-6.068 1.867-6.068 4.336s1.943 3.99 4.804 3.99c3.139 0 5.013-2.115 5.781-4.735.798.361 1.348 1.204 1.348 2.47 0 3.387-3.907 5.232-7.22 5.232-4.885 0-8.077-3.207-8.077-8.424 0-6.392 4.223-10.487 9.9-10.487 3.808 0 5.69 1.671 6.97 3.914l2.108-1.475C21.44 2.078 18.331 0 13.663 0 6.227 0 1.168 5.277 1.168 12.934c0 7 4.953 11.066 10.856 11.066 4.878 0 9.809-2.846 9.809-7.716 0-2.545-1.46-4.231-3.569-5.187m-6.33 4.855c-1.077 0-2.026-.512-2.026-1.453 0-1.483 1.822-1.934 3.606-1.934.678 0 1.34.045 1.927.173-.422 1.927-1.671 3.215-3.508 3.214Z",
  pinterest: "M12.017 0C5.396 0 .029 5.367.029 11.987c0 5.079 3.158 9.417 7.618 11.162-.105-.949-.199-2.403.041-3.439.219-.937 1.406-5.957 1.406-5.957s-.359-.72-.359-1.781c0-1.663.967-2.911 2.168-2.911 1.024 0 1.518.769 1.518 1.688 0 1.029-.653 2.567-.992 3.992-.285 1.193.6 2.165 1.775 2.165 2.128 0 3.768-2.245 3.768-5.487 0-2.861-2.063-4.869-5.008-4.869-3.41 0-5.409 2.562-5.409 5.199 0 1.033.394 2.143.889 2.741.099.12.112.225.085.345-.09.375-.293 1.199-.334 1.363-.053.225-.172.271-.401.165-1.495-.69-2.433-2.878-2.433-4.646 0-3.776 2.748-7.252 7.92-7.252 4.158 0 7.392 2.967 7.392 6.923 0 4.135-2.607 7.462-6.233 7.462-1.214 0-2.354-.629-2.758-1.379l-.749 2.848c-.269 1.045-1.004 2.352-1.498 3.146 1.123.345 2.306.535 3.55.535 6.607 0 11.985-5.365 11.985-11.987C23.97 5.39 18.592.026 11.985.026L12.017 0z",
  web: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm6.93 6h-2.95a15.65 15.65 0 0 0-1.38-3.56A8.03 8.03 0 0 1 18.93 8zM12 4.04c.83 1.2 1.48 2.53 1.91 3.96h-3.82c.43-1.43 1.08-2.76 1.91-3.96zM4.26 14A7.9 7.9 0 0 1 4 12c0-.69.1-1.36.26-2h3.38a16.5 16.5 0 0 0 0 4H4.26zm.81 2h2.95c.32 1.25.78 2.45 1.38 3.56A7.99 7.99 0 0 1 5.07 16zM8.03 8H5.07a7.99 7.99 0 0 1 4.33-3.56A15.65 15.65 0 0 0 8.03 8zM12 19.96c-.83-1.2-1.48-2.53-1.91-3.96h3.82c-.43 1.43-1.08 2.76-1.91 3.96zM14.34 14H9.66a14.7 14.7 0 0 1 0-4h4.68a14.7 14.7 0 0 1 0 4zm.25 5.56c.6-1.11 1.06-2.31 1.38-3.56h2.95a8.03 8.03 0 0 1-4.33 3.56zM16.36 14a16.5 16.5 0 0 0 0-4h3.38c.16.64.26 1.31.26 2s-.1 1.36-.26 2h-3.38z",
};

/** Short labels for platforms with no glyph, mirroring PLATFORM in the web app. */
const SHORT = { grok: "GK", reddit: "RDT", linkedin: "IN", facebook: "FB", substack: "SUB" };

/** Kinds that are a picture by definition and always get a cover, portrait or
 *  landscape, exactly as `KIND_ASPECT` decides in the web app. Everything else
 *  — a thread, an article — is a text card unless it brought a picture. */
const TALL_KINDS = ["reel", "short", "clip", "pin", "story"];
const WIDE_KINDS = ["video", "post"];

const MONTHS = ["January", "February", "March", "April", "May", "June", "July",
  "August", "September", "October", "November", "December"];

// ── Escaping and URL safety ───────────────────────────────────────────────

/** HTML-escapes text and attribute values alike. Both quote characters are
 *  escaped so one function is safe in both positions. */
export function esc(value: unknown): string {
  return String(value === null || value === undefined ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** An href we are willing to emit. Anything that is not plainly http(s) —
 *  `javascript:`, `data:`, a protocol-relative `//evil`, whitespace-smuggled
 *  schemes — comes back empty and the caller renders text instead of a link. */
export function safeHref(raw: unknown): string {
  const url = String(raw === null || raw === undefined ? "" : raw).trim();
  if (!/^https?:\/\/[^\s/?#]+/i.test(url)) return "";
  if (/[ -]/.test(url)) return "";
  return url;
}

/** Port of `thumb_is_expiring` (0008): a URL that will 403 in a few days.
 *  Kept character-for-character in step with the SQL, because the two answer
 *  the same question — is this thumbnail worth pointing anything at. */
export function isExpiringThumb(raw: unknown): boolean {
  const url = String(raw === null || raw === undefined ? "" : raw);
  if (url.length === 0) return false;
  if (url.startsWith(STORAGE + "/")) return false;
  if (/^https?:\/\/[^/?#]*\.(cdninstagram\.com|fbcdn\.net|tiktokcdn(-[a-z0-9]+)?\.com)([/?#]|$)/i.test(url)) return true;
  if (url.startsWith("https://pbs.twimg.com/card_img/")) return true;
  if (/[?&](oe|oh|x-expires|x-amz-expires)=/i.test(url)) return true;
  return false;
}

/** An X save carries one of two pictures: the post's own media, or the
 *  poster's avatar. This page has no avatars on it, and a 48px profile picture
 *  stretched across a card is worse than no picture at all. */
const X_AVATAR = /^https:\/\/pbs\.twimg\.com\/profile_images\//;

/** The image URL we will actually put on the page, or "".
 *  Three gates: it must not expire, it must not be an avatar, and it must live
 *  on a host we allow in the CSP. Anything else falls through to the topic
 *  gradient, which is a fine cover and cannot phone anywhere. */
export function shareableImage(raw: unknown): string {
  const url = safeHref(raw);
  if (url === "") return "";
  if (isExpiringThumb(url)) return "";
  if (X_AVATAR.test(url)) return "";
  for (const host of IMAGE_HOSTS) {
    if (url.startsWith(host + "/")) return url;
  }
  return "";
}

// ── Small helpers ─────────────────────────────────────────────────────────

/** Topic name and hue for a category id. Built-ins come from the taxonomy;
 *  a topic somebody invented (`custom.looksmaxxing`) gets its name from the
 *  slug and a hue from it, so the same topic is the same colour every time. */
export function topicFor(categoryID: string | null): Topic | null {
  const id = String(categoryID === null || categoryID === undefined ? "" : categoryID);
  if (id === "") return null;
  const known = TOPICS.get(id);
  if (known) return known;
  if (!id.startsWith("custom.")) return null;
  const words = id.slice(7).replace(/-/g, " ").trim();
  if (words === "") return null;
  let hash = 0;
  for (let i = 0; i < id.length; i++) hash = (hash * 31 + id.charCodeAt(i)) % 360;
  return { name: words.charAt(0).toUpperCase() + words.slice(1), hue: hash };
}

/** "7 September 2026", built from UTC parts so it does not depend on where
 *  the function happens to be running. */
export function formatDate(iso: string | null): string {
  const at = new Date(String(iso === null || iso === undefined ? "" : iso));
  if (isNaN(at.getTime())) return "";
  return at.getUTCDate() + " " + MONTHS[at.getUTCMonth()] + " " + at.getUTCFullYear();
}

function plural(n, one, many) {
  return n + " " + (n === 1 ? one : many);
}

function glyph(platform) {
  const path = GLYPHS[platform];
  if (path) return '<svg class="pg" aria-hidden="true"><use href="#p-' + esc(platform) + '"/></svg>';
  const short = SHORT[platform] || "WWW";
  return '<span class="pg-txt" aria-hidden="true">' + esc(short) + "</span>";
}

function items(data) {
  return Array.isArray(data.items) ? data.items : [];
}

// ── Head ──────────────────────────────────────────────────────────────────

/** One place for the policy, so nothing can be added to the page that quietly
 *  needs it widened. `default-src 'none'` means every directive below is an
 *  explicit opt-in, and the nonce means there is no `'unsafe-inline'` at all
 *  for scripts — no inline handler, no `style=` attribute anywhere in here. */
function csp(nonce) {
  return [
    "default-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
    // No `frame-ancestors` here on purpose: browsers ignore it in a <meta>
    // CSP. It is sent as a real header by collection-page/index.ts instead.
    "img-src 'self' data: " + SITE + " " + IMAGE_HOSTS.join(" "),
    "style-src 'nonce-" + nonce + "' " + FONTS_CSS,
    "font-src " + FONTS_FILES,
    "script-src 'nonce-" + nonce + "' " + PH_ASSETS,
    "connect-src " + PH_HOST + " " + PH_ASSETS,
  ].join("; ");
}

function head(h) {
  const title = h.title, description = h.description, image = h.image;
  const canonical = h.canonical, nonce = h.nonce;
  return [
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<meta http-equiv="Content-Security-Policy" content="' + esc(csp(nonce)) + '">',
    '<meta name="theme-color" content="#F6F3EE">',
    // Safari's own banner on iPhone, pointed at this collection: someone who
    // already has the app opens the collection in it rather than in a tab.
    '<meta name="apple-itunes-app" content="app-id=' + APP_ID +
      (h.appArgument ? ", app-argument=" + esc(h.appArgument) : "") + '">',
    // A shared link is unlisted, not published: it should not turn up in a
    // search for someone's name. And no referrer, so the platforms a viewer
    // clicks through to never learn which collection sent them.
    '<meta name="robots" content="noindex, nofollow">',
    '<meta name="referrer" content="no-referrer">',
    "<title>" + esc(title) + "</title>",
    '<meta name="description" content="' + esc(description) + '">',
    '<link rel="canonical" href="' + esc(canonical) + '">',
    '<meta property="og:type" content="website">',
    '<meta property="og:site_name" content="bookmarker">',
    '<meta property="og:url" content="' + esc(canonical) + '">',
    '<meta property="og:title" content="' + esc(title) + '">',
    '<meta property="og:description" content="' + esc(description) + '">',
    '<meta property="og:image" content="' + esc(image) + '">',
    '<meta name="twitter:card" content="summary_large_image">',
    '<meta name="twitter:title" content="' + esc(title) + '">',
    '<meta name="twitter:description" content="' + esc(description) + '">',
    '<meta name="twitter:image" content="' + esc(image) + '">',
    '<link rel="icon" href="' + esc(SITE) + '/favicon.png">',
    '<link rel="preconnect" href="' + FONTS_CSS + '">',
    '<link rel="preconnect" href="' + FONTS_FILES + '" crossorigin>',
    '<link href="' + FONTS_CSS +
      '/css2?family=Bricolage+Grotesque:opsz,wght@12..96,700;12..96,800&family=Instrument+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">',
    '<style nonce="' + esc(nonce) + '">' + baseCSS() + (h.style || "") + "</style>",
    h.imageFix ? imageFix(nonce) : "",
  ].join("\n");
}

/** The site's tokens, same values as docs/privacy.html and the iOS
 *  DesignSystem, so a shared page looks like the app it came from. */
function baseCSS() {
  return [
    ":root{--paper:#F6F3EE;--surface:#FFFFFF;--ink:#191510;--ink-2:#5B554D;--meta:#8A8378;",
    "--faint:#A39A8D;--hairline:#EAE4DA;--coral:#FF5A2D;--accent-text:#C93A12;--tint:#FFE9E1;",
    "--radius:18px;--shadow-card:0 1px 2px rgba(25,21,16,.04),0 10px 26px -14px rgba(25,21,16,.16);",
    '--font-head:"Bricolage Grotesque","Helvetica Neue",Helvetica,Arial,sans-serif;',
    '--font-body:"Instrument Sans",-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}',
    "*{box-sizing:border-box}html{color-scheme:light}",
    "body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.6 var(--font-body)}",
    "a{color:var(--accent-text);text-decoration:none}",
    "h1,h2{font-family:var(--font-head);letter-spacing:-.02em;line-height:1.1}",
    ":focus-visible{outline:2px solid var(--coral);outline-offset:2px}",
    ".pg{width:12px;height:12px;fill:currentColor;display:inline-block;vertical-align:-1px;flex:0 0 auto}",
    ".pg-txt{font-size:10px;font-weight:800;letter-spacing:.04em}",
    ".sprite{display:none}",
    ".nav{position:sticky;top:0;z-index:30;background:color-mix(in srgb,var(--paper) 84%,transparent);",
    "backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);border-bottom:1px solid var(--hairline)}",
    ".nav-in{display:flex;align-items:center;gap:12px;height:60px;max-width:1180px;margin:0 auto;padding:0 clamp(14px,3vw,28px)}",
    ".brand{display:flex;align-items:center;gap:9px;font-family:var(--font-head);font-weight:800;font-size:19px;color:var(--ink)}",
    ".brand img{width:28px;height:28px;border-radius:8px}",
    ".spacer{flex:1}",
    ".btn{display:inline-flex;align-items:center;justify-content:center;height:44px;padding:0 20px;border-radius:999px;font-weight:700;font-size:15px;white-space:nowrap}",
    ".btn-sm{height:38px;padding:0 16px;font-size:14px}",
    ".btn-coral{background:var(--coral);color:#fff}",
    ".btn-plain{background:var(--surface);color:var(--ink);border:1px solid var(--hairline)}",
    "main{max-width:1180px;margin:0 auto;padding:32px clamp(14px,3vw,28px) 56px}",
    ".eyebrow{color:var(--faint);font-size:13px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;margin:0 0 8px}",
    "h1{font-size:clamp(28px,5vw,42px);margin:0 0 10px;overflow-wrap:anywhere}",
    ".note{color:var(--ink-2);font-size:17px;margin:0 0 12px;max-width:52ch;overflow-wrap:anywhere}",
    ".by{color:var(--meta);font-size:14px;margin:0 0 22px}",
    ".by b{color:var(--ink-2)}",
    // "Link open until …" — the same meta grey as the by-line, date in ink.
    ".until{color:var(--meta);font-size:14px;margin:-14px 0 22px}.until b{color:var(--ink-2)}",
    // The pitch band: the web app's tinted note card (.import-note) with the
    // page's radius, holding the primary button and the secondary one.
    ".get{background:var(--tint);border-radius:var(--radius);padding:18px 20px 20px;margin:0 0 30px}",
    ".get-h{font-family:var(--font-head);font-weight:800;font-size:20px;letter-spacing:-.02em;line-height:1.15;margin:0 0 5px;color:var(--ink)}",
    ".get-p{color:var(--ink-2);font-size:15px;margin:0 0 14px;max-width:58ch}",
    ".cta{display:flex;flex-wrap:wrap;gap:10px;margin:0}",
    ".btn-big{height:52px;padding:0 26px;font-size:16px}",
    "@media (max-width:480px){.cta .btn-big{flex:1 1 100%}}",
    ".grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:16px;align-items:start}",
    ".card{display:block;background:var(--surface);border:1px solid var(--hairline);border-radius:var(--radius);",
    "overflow:hidden;box-shadow:var(--shadow-card);color:inherit}",
    ".cover{position:relative;width:100%;aspect-ratio:16/9;background:var(--tint);overflow:hidden}",
    ".cover.tall{aspect-ratio:4/5}",
    ".cover img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;border:0}",
    ".cover-glyph{position:absolute;inset:0;display:grid;place-items:center;color:rgba(255,255,255,.5)}",
    '.cover-glyph::before{content:"";position:absolute;inset:0;background:radial-gradient(130% 95% at 18% 0%,rgba(255,255,255,.30),transparent 58%)}',
    ".cover-glyph .pg,.cover-glyph .pg-txt{width:40px;height:40px;position:relative}",
    ".cover-glyph .pg-txt{font-size:20px;display:grid;place-items:center;width:auto}",
    ".badge{position:absolute;left:10px;top:10px;width:26px;height:26px;display:grid;place-items:center;",
    "background:rgba(25,21,16,.66);color:#fff;border-radius:8px}",
    ".badge .pg{width:13px;height:13px}.badge .pg-txt{font-size:9px}",
    ".body{padding:11px 13px 13px}",
    ".author{display:flex;align-items:center;gap:5px;color:var(--meta);font-size:11.5px;font-weight:600;margin-bottom:3px;min-width:0}",
    ".author span{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}",
    ".card-text .title{-webkit-line-clamp:5;font-size:14.5px}",
    ".title{font-weight:700;font-size:14px;line-height:1.32;display:-webkit-box;-webkit-line-clamp:3;",
    "-webkit-box-orient:vertical;overflow:hidden;overflow-wrap:anywhere;color:var(--ink)}",
    ".snippet{color:var(--ink-2);font-size:12.5px;line-height:1.45;margin-top:5px;display:-webkit-box;",
    "-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden;overflow-wrap:anywhere}",
    ".chips{display:flex;align-items:center;gap:7px;flex-wrap:wrap;margin-top:9px}",
    ".chip{font-size:11px;font-weight:700;border-radius:7px;padding:2.5px 7px}",
    ".dead{color:var(--meta);font-size:11px}",
    ".empty{border:1px dashed #D7CDBD;border-radius:var(--radius);padding:44px 20px;text-align:center;color:var(--ink-2)}",
    ".empty h2{font-size:19px;margin:0 0 6px}",
    ".mid{max-width:34rem;margin:0 auto;padding:64px clamp(14px,3vw,28px);text-align:center}",
    ".mid h1{font-size:28px}.mid p{color:var(--ink-2)}",
    "footer{border-top:1px solid var(--hairline);margin-top:44px}",
    ".foot{max-width:1180px;margin:0 auto;padding:18px clamp(14px,3vw,28px) 44px;color:var(--faint);",
    "font-size:13px;display:flex;flex-wrap:wrap;gap:6px 18px}",
    ".foot a{color:var(--ink-2);font-weight:600}",
    "@media (prefers-reduced-motion:no-preference){.card{transition:transform .18s cubic-bezier(.2,.7,.2,1)}",
    ".card:hover{transform:translateY(-2px)}}",
  ].join("");
}

function shell(inner, tail) {
  return [
    "<!DOCTYPE html>",
    '<html lang="en">',
    "<head>",
    inner.head,
    "</head>",
    "<body>",
    inner.sprite,
    '<header class="nav"><div class="nav-in">',
    '<a class="brand" href="' + SITE + '"><img src="' + SITE + '/img/mark-192.png" alt=""><span>bookmarker</span></a>',
    '<span class="spacer"></span>',
    '<a class="btn btn-sm btn-plain" href="' + SITE + '/get">Get the app</a>',
    "</div></header>",
    inner.main,
    "<footer><div class=\"foot\">",
    '<a href="' + SITE + '">bookmarker.lol</a>',
    '<a href="' + SITE + '/privacy">Privacy</a>',
    "<span>A shared collection shows only the borks its owner picked.</span>",
    "</div></footer>",
    tail,
    "</body>",
    "</html>",
    "",
  ].join("\n");
}

// ── The page ──────────────────────────────────────────────────────────────

/** The whole page for one collection — or, when `data` is null, the page a
 *  wrong, revoked or deleted link gets. The two are one function because they
 *  have to be one answer: nothing about the 404 may hint at which it was. */
export function renderCollectionPage(data: Collection | null, opts: RenderOptions): string {
  const origin = (opts && opts.origin) || SITE;
  const slug = (opts && opts.slug) || "";
  // No nonce means the CSP matches no script, which is a page that renders
  // fine and simply does not measure itself. Never a page that runs anything.
  const nonce = (opts && opts.nonce) || "";

  if (!data) return renderMissing(origin, nonce);

  const rows = items(data);
  const url = origin + "/c/" + slug;
  const name = String(data.name || "Untitled collection");
  const owner = String(data.owner_name || "Someone");
  const note = data.note ? String(data.note) : "";
  const until = formatDate(data.expires_at || null);
  const description = note !== ""
    ? note
    : plural(rows.length, "link", "links") + " from " + owner + " · bookmarker";

  // The first cover we would be willing to render is the card image. A page
  // whose covers are all gradients falls back to the brand image rather than
  // unfurling as a blank rectangle.
  let image = origin + FALLBACK_IMAGE;
  for (const row of rows) {
    const candidate = shareableImage(row.image_url);
    if (candidate !== "") { image = candidate; break; }
  }

  const hues = new Map();
  const platforms = new Set();
  for (const row of rows) {
    const topic = topicFor(row.category_id);
    if (topic) hues.set(topic.hue, true);
    platforms.add(String(row.platform || "web"));
  }
  hues.set(24, true);                    // the no-topic default

  let style = "";
  for (const hue of hues.keys()) {
    style += ".h" + hue + "{background:linear-gradient(135deg,hsl(" + hue + " 65% 62%),hsl(" + hue + " 72% 44%))}";
    style += ".c" + hue + "{background:hsl(" + hue + " 70% 92%);color:hsl(" + hue + " 60% 28%)}";
  }

  const main = [
    "<main>",
    '<p class="eyebrow">A collection on bookmarker</p>',
    "<h1>" + esc(name) + "</h1>",
    note !== "" ? '<p class="note">' + esc(note) + "</p>" : "",
    '<p class="by">by <b>' + esc(owner) + "</b> · " + esc(plural(rows.length, "bork", "borks")) +
      (formatDate(data.updated_at) !== "" ? " · updated " + esc(formatDate(data.updated_at)) : "") + "</p>",
    // A link that closes itself says so, in the same words the owner chose it
    // by. Past the date the RPC answers null and this page is never built.
    until !== "" ? '<p class="until">Link open until <b>' + esc(until) + "</b></p>" : "",
    // The page's job is distribution. The app is the primary action, and the
    // secondary one — the web app reads `#save=<slug>`, signs the visitor in
    // if it has to, and calls `collection_save` — only when there is
    // something to save.
    '<section class="get">',
    '<p class="get-h">Keep these — and everything else you scroll past.</p>',
    '<p class="get-p">bookmarker saves any reel, thread or video from any app in two taps, files it by topic, and finds it again. Free on iPhone.</p>',
    '<div class="cta">',
    '<a class="btn btn-big btn-coral" href="' + esc(APP_STORE) + '">Get bookmarker</a>',
    rows.length > 0
      ? '<a class="btn btn-big btn-plain" href="' + esc(origin + "/#save=" + slug) + '">Save these to my library</a>'
      : "",
    "</div>",
    "</section>",
    rows.length === 0
      ? '<div class="empty"><h2>Nothing here yet</h2><p>' + esc(owner) +
        " hasn’t put any borks in this collection. The link keeps working — try it again later.</p></div>"
      : '<div class="grid">' + rows.map(card).join("") + "</div>",
    "</main>",
  ].join("\n");

  return shell({
    head: head({
      title: name + " — bookmarker",
      description: description,
      image: image,
      canonical: url,
      // The app registers `bookmarker://c/<slug>`; Safari's banner hands this
      // to it, so someone who already has the app lands on the collection
      // inside it rather than in a tab.
      appArgument: "bookmarker://c/" + slug,
      nonce: nonce,
      style: style,
      imageFix: true,
    }),
    sprite: sprite(platforms),
    main: main,
  }, scripts(nonce, rows.length));
}

function renderMissing(origin, nonce) {
  const title = "This collection isn’t available — bookmarker";
  return shell({
    // Generic everything. A revoked link, a deleted collection and a typo are
    // the same page and the same card, so an unfurl can never confirm that a
    // collection was ever there.
    head: head({
      title: title,
      description: "Every save, one library.",
      image: origin + FALLBACK_IMAGE,
      canonical: origin + "/",
      nonce: nonce,
      style: "",
    }),
    sprite: "",
    main: [
      '<main class="mid">',
      "<h1>This collection isn’t available</h1>",
      "<p>The link may have been turned off, or it may never have been a link. " +
        'Nothing is wrong on your end.</p><p><a class="btn btn-coral" href="' + esc(origin) +
        '">Open bookmarker</a></p>',
      "</main>",
    ].join("\n"),
  }, "");
}

function sprite(platforms) {
  const used = [];
  for (const name of platforms) {
    if (GLYPHS[name]) used.push('<symbol id="p-' + esc(name) + '" viewBox="0 0 24 24"><path d="' + GLYPHS[name] + '"/></symbol>');
  }
  if (used.length === 0) return "";
  return '<svg class="sprite" width="0" height="0" aria-hidden="true" focusable="false">' +
    used.join("") + "</svg>";
}

function card(row) {
  const href = safeHref(row.url);
  const platform = String(row.platform || "web");
  const topic = topicFor(row.category_id);
  const hue = topic ? topic.hue : 24;
  const cover = shareableImage(row.image_url);
  const title = String(row.title || "").trim();
  const author = row.author ? String(row.author) : "";
  const snippet = row.body_text ? String(row.body_text).slice(0, 240) : "";
  const kind = String(row.kind || "");
  const tall = TALL_KINDS.indexOf(kind) >= 0;
  const hasCover = tall || WIDE_KINDS.indexOf(kind) >= 0 || cover !== "";

  const media = !hasCover ? "" : [
    '<div class="cover' + (tall ? " tall" : "") + " h" + hue + '">',
    // The glyph sits under the image, so an image that never arrives simply
    // reveals it; `bork-img` is what the one inline script removes on error.
    '<span class="cover-glyph">' + glyph(platform) + "</span>",
    cover !== "" ? '<img class="bork-img" src="' + esc(cover) + '" alt="" loading="lazy" decoding="async">' : "",
    '<span class="badge">' + glyph(platform) + "</span>",
    "</div>",
  ].join("");

  const body = [
    '<div class="body">',
    author !== "" || !hasCover
      ? '<div class="author">' + glyph(platform) + "<span>" + esc(author || platformName(platform)) + "</span></div>"
      : "",
    '<div class="title">' + (title !== "" ? esc(title) : esc(hostOf(href) || "Untitled")) + "</div>",
    snippet !== "" ? '<div class="snippet">' + esc(snippet) + "</div>" : "",
    topic ? '<div class="chips"><span class="chip c' + hue + '">' + esc(topic.name) + "</span></div>" : "",
    "</div>",
  ].join("");

  const cls = "card" + (hasCover ? "" : " card-text");
  if (href === "") {
    // A bork whose URL we will not emit still belongs on the page — as a card
    // you cannot click, rather than a hole in the collection.
    return '<div class="' + cls + '">' + media + body + '<div class="body dead">Link unavailable</div></div>';
  }
  return '<a class="' + cls + '" href="' + esc(href) + '" target="_blank" rel="noopener noreferrer nofollow">' +
    media + body + "</a>";
}

/** What to call a platform when a bork has no author — "X", not "x". */
function platformName(platform) {
  if (platform === "x") return "X";
  if (platform === "web" || !platform) return "Web";
  return platform.charAt(0).toUpperCase() + platform.slice(1);
}

function hostOf(href) {
  const match = /^https?:\/\/([^/?#]+)/i.exec(href || "");
  if (!match) return "";
  return match[1].replace(/^www\./i, "");
}

/** What an inline `onerror=` on every cover would have done, without the
 *  `'unsafe-inline'` that would let anything else inline run too: one
 *  capture-phase listener drops a cover that failed to load, and the topic
 *  gradient underneath becomes the cover.
 *
 *  It sits in the HEAD, and that placement is the whole point — at the end of
 *  the body it is registered after the images have already tried and failed,
 *  and the reader gets Chrome's broken-image icon instead of the gradient.
 *  (Observed, not theorised.) The `load` sweep is the belt to that braces: it
 *  catches anything that failed before even this ran. */
function imageFix(nonce) {
  return '<script nonce="' + esc(nonce) + '">' +
    'document.addEventListener("error",function(e){var t=e.target;' +
    'if(t&&t.tagName==="IMG"&&t.classList.contains("bork-img"))t.remove();},true);' +
    'addEventListener("load",function(){' +
    'var a=document.querySelectorAll("img.bork-img"),i;' +
    "for(i=0;i<a.length;i++)if(a[i].complete&&!a[i].naturalWidth)a[i].remove();});" +
    "</" + "script>";
}

/** PostHog, configured down to the one thing worth knowing: how many people
 *  opened a shared link. `persistence: 'memory'` means no cookie and no
 *  localStorage, so a viewer is not given an identity that follows them to
 *  bookmarker.lol; no replay, no autocapture, no pageview, no identify. */
function scripts(nonce, count) {
  const tag = '<script nonce="' + esc(nonce) + '">';
  const posthog = tag +
    "!function(t,e){var o,n,p,r;e.__SV||(window.posthog=e,e._i=[],e.init=function(i,s,a){function g(t,e){var o=e.split(\".\");2==o.length&&(t=t[o[0]],e=o[1]),t[e]=function(){t.push([e].concat(Array.prototype.slice.call(arguments,0)))}}(p=t.createElement(\"script\")).type=\"text/javascript\",p.crossOrigin=\"anonymous\",p.async=!0,p.src=s.api_host.replace(\".i.posthog.com\",\"-assets.i.posthog.com\")+\"/static/array.js\",(r=t.getElementsByTagName(\"script\")[0]).parentNode.insertBefore(p,r);var u=e;for(void 0!==a?u=e[a]=[]:a=\"posthog\",u.people=u.people||[],u.toString=function(t){var e=\"posthog\";return\"posthog\"!==a&&(e+=\".\"+a),t||(e+=\" (stub)\"),e},u.people.toString=function(){return u.toString(1)+\".people (stub)\"},o=\"init capture register register_once unregister opt_in_capturing opt_out_capturing has_opted_out_capturing reset get_distinct_id debug\".split(\" \"),n=0;n<o.length;n++)g(u,o[n]);e._i.push([i,s,a])},e.__SV=1)}(document,window.posthog||[]);\n" +
    "posthog.init('" + PH_TOKEN + "',{api_host:'" + PH_HOST + "',persistence:'memory'," +
    "disable_session_recording:true,capture_pageview:false,capture_pageleave:false,autocapture:false});\n" +
    "try{if(localStorage.getItem('bm.internal'))posthog.opt_out_capturing();}catch(e){}\n" +
    "posthog.capture('collection_viewed',{items:" + Number(count) + "});" +
    "</" + "script>";
  return posthog;
}
