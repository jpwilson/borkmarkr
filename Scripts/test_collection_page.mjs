#!/usr/bin/env node
/**
 * Tests for the shared-collection page — supabase/functions/_shared/collection_html.ts.
 *
 *     node Scripts/test_collection_page.mjs
 *
 * That module is the page a stranger sees when someone sends them a bookmarker
 * link, and every string on it is written by the person who made the
 * collection: the name, the note, a bork's title, an author handle, a URL, a
 * thumbnail host. So most of what follows is about what the renderer refuses to
 * emit rather than what it emits.
 *
 * Same shape as Scripts/test_browse.mjs: the real file is loaded into a vm
 * context, so these assertions are about the bytes that actually ship. The one
 * difference is that this file is TypeScript, and node cannot run TypeScript —
 * so the loader strips the type syntax first. The renderer is written to keep
 * that honest: types appear only in `interface` blocks and in single-line
 * exported signatures, and nothing else in the file is TypeScript at all. If
 * that ever stops being true this loader throws rather than silently testing
 * something other than what Deno runs.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SOURCE = path.join(ROOT, "supabase", "functions", "_shared", "collection_html.ts");

/** Strip the two forms of TypeScript the renderer is allowed to use. */
function stripTypes(src) {
  const out = src
    // whole `export interface Foo { … }` blocks — opened at column 0, closed
    // by a lone `}` at column 0
    .replace(/^export (?:interface|type) [\s\S]*?^}\n/gm, "")
    .split("\n")
    .map((line) => {
      if (!/^(?:export )?function [A-Za-z_$]/.test(line)) return line;
      return line
        .replace(/\)\s*:\s*[^{]+\{\s*$/, ") {")                       // return type
        .replace(/([A-Za-z_$][\w$]*)\s*:\s*[^,)]+(?=[,)])/g, "$1");   // parameters
    })
    .join("\n")
    .replace(/^export /gm, "");

  const leftovers = out.split("\n").filter((l) => /^\s*(?:export |interface |type )/.test(l));
  if (leftovers.length) throw new Error(`type syntax survived stripping:\n${leftovers.join("\n")}`);
  return out;
}

const ctx = vm.createContext({ console, URL, Map, Set, Date, Number, String, Array, isNaN, localStorage: undefined });
vm.runInContext(stripTypes(fs.readFileSync(SOURCE, "utf8")), ctx, { filename: "collection_html.ts" });
const { renderCollectionPage, esc, safeHref, isExpiringThumb, shareableImage, topicFor, formatDate } =
  vm.runInContext(
    "({ renderCollectionPage, esc, safeHref, isExpiringThumb, shareableImage, topicFor, formatDate })",
    ctx,
  );

/* ── Tiny runner ── */
let failures = 0, checks = 0;
function ok(cond, message) {
  checks++;
  if (cond) return;
  failures++;
  console.log(`FAIL ${message}`);
}
function eq(actual, expected, message) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  ok(a === b, `${message}\n     expected ${b}\n     got      ${a}`);
}
function group(name, fn) { console.log(`\n${name}`); fn(); }

/* ── Fixtures ── */
const OPTS = { origin: "https://bookmarker.lol", slug: "abcd1234efgh", nonce: "TESTNONCE" };
const STORAGE = "https://pcjuxnhqxyfvgagnblzv.supabase.co";

function item(over) {
  return Object.assign({
    id: "youtube.com/watch?v=aaa",
    url: "https://youtube.com/watch?v=aaa",
    title: "A perfectly ordinary title",
    author: "@someone",
    platform: "youtube",
    kind: "video",
    category_id: "fitness",
    subcategory: null,
    tags: [],
    image_url: null,
    duration_seconds: null,
    body_text: null,
  }, over || {});
}

function collection(over) {
  return Object.assign({
    id: "aaaaaaaa-0000-0000-0000-000000000001",
    name: "Marathon prep",
    note: "The twelve that actually helped.",
    owner_name: "Jean-Paul",
    updated_at: "2026-09-07T12:00:00Z",
    items: [item()],
  }, over || {});
}

const render = (data, over) => renderCollectionPage(data, Object.assign({}, OPTS, over || {}));

/* ── Escaping ─────────────────────────────────────────────────────────── */
group("escaping — every field is owner-controlled", () => {
  const evil = "<script>alert(1)</script>";
  const html = render(collection({
    name: `Marathon ${evil}`,
    note: `note ${evil}`,
    owner_name: `owner ${evil}`,
    items: [item({ title: `title ${evil}`, author: `author ${evil}`, body_text: `body ${evil}` })],
  }));

  ok(!html.includes("<script>alert(1)</script>"), "a <script> in any field is never emitted raw");
  eq(html.split("<script").length - 1, 2, "exactly the page's own two script tags survive");
  ok(html.includes("&lt;script&gt;alert(1)&lt;/script&gt;"), "it is emitted escaped instead");
  ok(html.includes("<title>Marathon &lt;script&gt;"), "the title escapes it too");
  ok(html.includes('property="og:title" content="Marathon &lt;script&gt;'), "so does the OG card");

  // A name that tries to break out of an attribute.
  const quoted = render(collection({ name: 'x" onload="alert(1)' }));
  ok(!quoted.includes('onload="alert(1)"'), "a quote in the name cannot open an attribute");
  ok(quoted.includes("&quot; onload=&quot;"), "the quotes are escaped");

  eq(esc(null), "", "esc(null) is empty, not the string 'null'");
  eq(esc(undefined), "", "esc(undefined) is empty");
  eq(esc("a & b"), "a &amp; b", "ampersands escape");
});

/* ── Links ────────────────────────────────────────────────────────────── */
group("hrefs — only http(s) ever reaches an anchor", () => {
  eq(safeHref("javascript:alert(1)"), "", "javascript: is refused");
  eq(safeHref("JaVaScRiPt:alert(1)"), "", "…in any case");
  eq(safeHref("data:text/html,<script>alert(1)</script>"), "", "data: is refused");
  eq(safeHref("//evil.example.com"), "", "protocol-relative is refused");
  eq(safeHref("  https://ok.example.com/x  "), "https://ok.example.com/x", "surrounding space is trimmed");
  eq(safeHref("https://ok.example.com/a?b=1&c=2#frag"), "https://ok.example.com/a?b=1&c=2#frag",
     "a normal URL with query and fragment survives intact");
  eq(safeHref("http://ok.example.com/x"), "http://ok.example.com/x", "http is allowed");
  eq(safeHref(null), "", "null is refused");

  const html = render(collection({ items: [item({ url: "javascript:alert(1)" })] }));
  ok(!html.includes("javascript:"), "a javascript: bork never appears in the page at all");
  ok(html.includes("Link unavailable"), "it renders as a card you cannot click");

  const good = render(collection());
  ok(good.includes('rel="noopener noreferrer nofollow"'), "real links open detached from this page");
  ok(good.includes('target="_blank"'), "…in a new tab");
});

/* ── Images ───────────────────────────────────────────────────────────── */
group("images — expiring and unknown hosts never get requested", () => {
  ok(isExpiringThumb("https://scontent-lhr8-1.cdninstagram.com/v/t51/x.jpg"), "instagram CDN expires");
  ok(isExpiringThumb("https://p16-sign.tiktokcdn-us.com/x.jpeg"), "tiktok CDN expires");
  ok(isExpiringThumb("https://video.xx.fbcdn.net/v/x.jpg"), "fbcdn expires");
  ok(isExpiringThumb("https://pbs.twimg.com/card_img/123/abc"), "a twitter card image expires");
  ok(isExpiringThumb("https://example.com/x.jpg?x-expires=1700000000"), "an x-expires query expires");
  ok(!isExpiringThumb(`${STORAGE}/storage/v1/object/public/thumbs/a/b.jpg`), "our own copy never expires");
  ok(!isExpiringThumb("https://i.ytimg.com/vi/aaa/hqdefault.jpg"), "a youtube thumbnail does not expire");

  eq(shareableImage("https://i.ytimg.com/vi/aaa/hq.jpg"), "https://i.ytimg.com/vi/aaa/hq.jpg",
     "an allowed host passes through");
  eq(shareableImage("https://evil.example.com/beacon.gif"), "", "an unknown host is dropped");
  eq(shareableImage("https://pbs.twimg.com/card_img/1/x"), "", "an allowed host with an expiring path is dropped");
  eq(shareableImage("javascript:alert(1)"), "", "a non-http image is dropped");
  eq(shareableImage("https://pbs.twimg.com/profile_images/1/x.jpg"), "",
     "an X avatar is not a cover — it is a 48px face stretched over a card");

  const beacon = render(collection({ items: [item({ image_url: "https://evil.example.com/beacon.gif" })] }));
  ok(!beacon.includes("evil.example.com"), "an unknown image host is nowhere in the page");
  ok(beacon.includes("cover-glyph"), "the platform glyph shows through instead");
});

/* ── The OG card ──────────────────────────────────────────────────────── */
group("og image selection", () => {
  const none = render(collection());
  ok(none.includes('property="og:image" content="https://bookmarker.lol/img/share-v2.jpg"'),
     "no usable cover falls back to the brand image");

  const good = render(collection({
    items: [item({ image_url: "https://scontent.cdninstagram.com/x.jpg" }), item({ image_url: "https://i.ytimg.com/vi/b/hq.jpg" })],
  }));
  ok(good.includes('property="og:image" content="https://i.ytimg.com/vi/b/hq.jpg"'),
     "the first *usable* cover wins, skipping the expiring one");

  const mine = render(collection({ items: [item({ image_url: `${STORAGE}/storage/v1/object/public/thumbs/a/b.jpg` })] }));
  ok(mine.includes(`content="${STORAGE}/storage/v1/object/public/thumbs/a/b.jpg"`),
     "our own mirrored thumbnail is used");

  ok(none.includes('name="twitter:card" content="summary_large_image"'), "the twitter card is a large image");
  ok(none.includes('property="og:url" content="https://bookmarker.lol/c/abcd1234efgh"'),
     "og:url is the pretty bookmarker.lol URL, not the function's");
  ok(none.includes('property="og:description" content="The twelve that actually helped."'),
     "the note is the description when there is one");

  const noNote = render(collection({ note: null, items: [item(), item()] }));
  ok(noNote.includes('content="2 links from Jean-Paul · bookmarker"'),
     "with no note the description counts the links");
  const one = render(collection({ note: null }));
  ok(one.includes('content="1 link from Jean-Paul · bookmarker"'), "…and says 'link' for one of them");
});

/* ── The 404 state ────────────────────────────────────────────────────── */
group("a link that is off, deleted, or never existed", () => {
  const html = render(null);
  ok(html.includes("This collection isn’t available"), "says so plainly");
  ok(html.includes('property="og:image" content="https://bookmarker.lol/img/share-v2.jpg"'),
     "unfurls as the generic brand card");
  ok(!html.includes("Marathon"), "no trace of any collection");
  ok(html.includes('name="robots" content="noindex, nofollow"'), "still noindex");
  ok(!html.includes("posthog.init"), "and it does not measure a 404 — the page has no scripts at all");
  ok(!html.includes("<script"), "…none");
  ok(html.includes('href="https://bookmarker.lol"'), "offers a way home");
});

/* ── The empty state ──────────────────────────────────────────────────── */
group("a collection with nothing in it", () => {
  const html = render(collection({ items: [] }));
  ok(html.includes("Nothing here yet"), "says so");
  ok(!html.includes("Save these to my library"), "does not offer to save nothing");
  ok(html.includes("Get the app"), "still offers the app");
  ok(html.includes("collection_viewed',{items:0}"), "reports zero items");
  ok(html.includes("0 borks"), "counts honestly");
});

/* ── The CTA ──────────────────────────────────────────────────────────── */
group("the call to action", () => {
  const html = render(collection());
  ok(html.includes('href="https://bookmarker.lol/#save=abcd1234efgh"'), "save points at the web app with the slug");
  ok(html.includes(">Save these to my library<"), "…with the words the brief asked for");
  ok(html.includes('href="https://bookmarker.lol/get"'), "and the app link goes to /get");
});

/* ── Head and CSP ─────────────────────────────────────────────────────── */
group("the head", () => {
  const html = render(collection());
  const csp = /<meta http-equiv="Content-Security-Policy" content="([^"]+)"/.exec(html)[1];

  ok(csp.includes("default-src &#39;none&#39;"), "everything is denied before anything is allowed");
  ok(csp.includes("script-src &#39;nonce-TESTNONCE&#39; https://us-assets.i.posthog.com"),
     "scripts are the nonce and PostHog's loader, nothing else");
  ok(!csp.includes("unsafe-inline"), "no unsafe-inline anywhere");
  ok(!csp.includes("unsafe-eval"), "no unsafe-eval");
  ok(csp.includes("https://i.ytimg.com"), "images name the allowed hosts");
  ok(!csp.includes("img-src &#39;self&#39; data: https:;"), "img-src is a list, not `https:`");
  ok(csp.includes("font-src https://fonts.gstatic.com"), "fonts are allowed to load");

  ok(html.includes('name="robots" content="noindex, nofollow"'), "an unlisted link is not published");
  ok(html.includes('name="referrer" content="no-referrer"'), "no referrer leaves this page");
  ok(html.includes('name="apple-itunes-app" content="app-id=6799805479, app-argument=https://bookmarker.lol/c/abcd1234efgh"'),
     "the smart banner carries the collection as its argument");
  ok(html.includes("<title>Marathon prep — bookmarker</title>"), "the title is the collection's");
  ok(html.includes('<link rel="canonical" href="https://bookmarker.lol/c/abcd1234efgh">'), "canonical is the pretty URL");

  // Nothing on the page may need a policy we did not grant.
  ok(!/ style="/.test(html), "not one inline style attribute (style-src is nonce-only)");
  ok(!/ on[a-z]+="/.test(html), "not one inline event handler (script-src is nonce-only)");
  eq((html.match(/<script nonce="TESTNONCE">/g) || []).length, 2, "both scripts carry the nonce");
});

/* ── Analytics ────────────────────────────────────────────────────────── */
group("what the page measures", () => {
  const html = render(collection({ items: [item(), item(), item()] }));
  ok(html.includes("persistence:'memory'"), "no cookie and no localStorage identity");
  ok(html.includes("disable_session_recording:true"), "no session replay");
  ok(html.includes("capture_pageview:false"), "no pageview");
  ok(html.includes("autocapture:false"), "no autocapture");
  ok(html.includes("posthog.capture('collection_viewed',{items:3})"), "one event, with a count");
  ok(!html.includes("posthog.identify"), "a viewer is never identified");
});

/* ── Content ──────────────────────────────────────────────────────────── */
group("what a reader actually gets", () => {
  const html = render(collection({
    items: [
      item({ title: "First", category_id: "fitness" }),
      item({ id: "b", url: "https://x.com/i/status/1", title: "Second", platform: "x", kind: "thread",
             category_id: "custom.looksmaxxing", body_text: "a thread body" }),
    ],
  }));
  ok(html.indexOf("First") < html.indexOf("Second"), "items keep the order the RPC returned");
  ok(html.includes("Fitness"), "a built-in topic gets its real name");
  ok(html.includes("Looksmaxxing"), "a topic somebody invented gets a readable one");
  ok(html.includes("a thread body"), "a text bork shows its snippet");
  ok(html.includes("card card-text"), "…as a text card, with no gradient rectangle above it");

  const media = render(collection({ items: [item({ kind: "reel", platform: "instagram" })] }));
  ok(media.includes("cover tall"), "a reel is portrait even with no picture");
  const avatarOnly = render(collection({
    items: [item({ kind: "thread", platform: "x", image_url: "https://pbs.twimg.com/profile_images/1/x.jpg" })],
  }));
  ok(avatarOnly.includes("card-text"), "an X thread carrying only an avatar is still a text card");
  ok(!avatarOnly.includes("profile_images"), "…and the avatar is not requested");
  ok(html.includes('id="p-x"') && html.includes('id="p-youtube"'), "only the platforms present get a glyph");
  ok(!html.includes('id="p-pinterest"'), "…and no others");
  ok(html.includes("by <b>Jean-Paul</b>"), "the curator is credited");
  ok(html.includes("2 borks"), "the count is right");
  ok(html.includes("updated 7 September 2026"), "the date reads as a date");

  eq(formatDate("2026-01-01T00:00:00Z"), "1 January 2026", "dates are UTC, not wherever this runs");
  eq(formatDate("nonsense"), "", "an unparseable date is simply absent");
  eq(topicFor(null), null, "no topic means no chip");
  eq(topicFor("nope"), null, "an unknown built-in id means no chip");
  eq(topicFor("custom.a-b").name, "A b", "a custom id becomes a name");
  eq(topicFor("custom.a-b").hue, topicFor("custom.a-b").hue, "…with a stable hue");
});

/* ── Shape ────────────────────────────────────────────────────────────── */
group("the document", () => {
  const html = render(collection());
  ok(html.startsWith("<!DOCTYPE html>"), "is a document");
  ok(html.includes('<html lang="en">') && html.trimEnd().endsWith("</html>"), "…that closes");
  ok(!html.includes("undefined"), "no stray undefined anywhere");
  ok(!html.includes("[object Object]"), "nothing stringified by accident");

  const missingFields = render({ id: "x", name: "Bare", note: null, owner_name: "", updated_at: null, items: null });
  ok(missingFields.includes("Nothing here yet"), "a null items array is an empty collection, not a crash");
  ok(missingFields.includes("by <b>Someone</b>"), "a missing owner name falls back");
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
