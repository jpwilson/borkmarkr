#!/usr/bin/env node
/**
 * Tests for the web importer — docs/import.js.
 *
 *     node Scripts/test_importers.mjs
 *
 * Two halves:
 *
 *  1. **Parsers.** Every format in Core/Importers.swift plus the web-only ones
 *     (Pinterest, Takeout JSON, zip), run over the synthetic fixtures in
 *     Scripts/fixtures/. No real personal data — these are hand-written files
 *     shaped like the real exports.
 *
 *  2. **Categorizer parity.** Scripts/fixtures/categorizer_cases.json holds what
 *     the *Swift* Categorizer answers for a set of real-world links; the JS port
 *     has to give the same topic, subtopic and tags.
 *
 * import.js is a plain browser script, so it is loaded into a vm context stocked
 * with the four helpers it borrows from the page. Those come out of
 * docs/index.html itself rather than a copy, so the test fails loudly if the
 * page's identity rules move.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const FIXTURES = path.join(ROOT, "Scripts", "fixtures");
const read = (p) => fs.readFileSync(p, "utf8");

/* ── Load docs/import.js the way the browser does ── */

function pageHelpers() {
  const html = read(path.join(ROOT, "docs", "index.html"));
  // The block that defines decodeEntities, stableID, PLATFORM and
  // detectPlatform. Nothing in it touches the DOM at load time.
  const from = html.indexOf("const ENT = {");
  const to = html.indexOf("/* ── Session ── */");
  if (from < 0 || to < 0 || to < from) {
    throw new Error("docs/index.html: couldn't find the helper block (const ENT … /* ── Session ── */). "
      + "If it moved, update this test — import.js depends on those helpers.");
  }
  return html.slice(from, to);
}

const ctx = vm.createContext({ TextDecoder, Response, DecompressionStream, Blob, URL, console });
vm.runInContext(read(path.join(ROOT, "docs", "taxonomy.js")), ctx, { filename: "taxonomy.js" });
vm.runInContext(pageHelpers(), ctx, { filename: "index.html helpers" });
vm.runInContext(read(path.join(ROOT, "docs", "import.js")), ctx, { filename: "import.js" });
const { Importer, Filer, Zip } = vm.runInContext("({ Importer, Filer, Zip })", ctx);

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
  ok(a === b, `${message}\n       expected ${b}\n       got      ${a}`);
}
function group(name, fn) { console.log(`\n── ${name}`); fn(); }

const fixture = (name) => read(path.join(FIXTURES, name));
const parse = (name) => Importer.parseText(fixture(name), name);
const urls = (out) => out.candidates.map(c => c.url);
const iso = (d) => (d ? new Date(d).toISOString() : null);

/* ══ Parsers ══════════════════════════════════════════════════════════════ */

group("Instagram", () => {
  const out = parse("instagram_saved_posts.json");
  eq(out.format, "instagram", "format is instagram");
  eq(urls(out), [
    "https://www.instagram.com/p/five-hip-mobility-drills/",
    "https://www.instagram.com/reel/sourdough-starter-guide/",
    "https://www.instagram.com/p/sheet-pan-dinners/",
  ], "takes the href out of string_map_data whatever the localised key is");
  eq(out.skipped, 2, "rows without an href are skipped, not guessed at");
  eq(out.candidates[0].author, "@stretchtheory", "the entry title is the handle");
  eq(iso(out.candidates[0].savedAt), "2024-07-01T00:00:00.000Z", "unix timestamp becomes the saved date");
  ok(urls(out).includes("https://www.instagram.com/p/sheet-pan-dinners/"),
    "saved_saved_collections (plural) is read too — Meta ships both spellings");
});

group("X archive", () => {
  const likes = parse("x_like.js");
  eq(likes.format, "x", "format is x");
  eq(urls(likes), [
    "https://twitter.com/i/web/status/1000000000000000001",
    "https://x.com/i/status/1000000000000000002",
  ], "expandedUrl wins, tweetId is the fallback");
  eq(likes.skipped, 1, "an entry with neither is skipped");
  eq(likes.candidates[0].title.length, 120, "the post body is the title, clipped to 120");
  ok(likes.candidates[0].text.length > 120, "…but the full body is kept as body text");

  const tweets = parse("x_tweets.js");
  eq(urls(tweets), [
    "https://www.youtube.com/watch?v=zone2primer",
    "https://x.com/i/status/2000000000000000002",
  ], "tweets.js: the linked URL, else the post itself via id_str");

  const marks = parse("x_bookmark.js");
  eq(urls(marks), [
    "https://twitter.com/i/web/status/1000000000000000001",
    "https://x.com/i/status/3000000000000000003",
  ], "bookmark.js: expandedUrl wins, tweet_id is the fallback");
  eq(marks.skipped, 1, "chrome:// is not a link anyone saved");

  // Likes and bookmarks overlap constantly; dedupe is what stops the double-up.
  const both = Importer.dedupe([...likes.candidates, ...marks.candidates]);
  eq(both.length, 3, "likes + bookmarks dedupe on stableID across files");
});

group("TikTok", () => {
  const out = parse("tiktok_user_data.json");
  eq(out.format, "tiktok", "format is tiktok");
  eq(urls(out), [
    "https://www.tiktokv.com/share/video/7231000000000000001/",
    "https://www.tiktok.com/@mudandfire/video/7231000000000000002",
    "https://www.tiktok.com/@wanderfrugal/video/7231000000000000003",
    "https://www.tiktok.com/@mudandfire/video/7231000000000000002",
  ], "favourites then likes, both key spellings");
  eq(out.skipped, 1, "the empty Link is skipped");
  eq(iso(out.candidates[0].savedAt), "2024-05-02T09:15:22.000Z", "TikTok's dates are UTC with no marker");
  eq(Importer.dedupe(out.candidates).length, 3, "a video in both lists lands once");
});

group("Google Takeout", () => {
  const csv = parse("takeout_playlist.csv");
  eq(csv.format, "youtube", "format is youtube");
  eq(urls(csv), [
    "https://www.youtube.com/watch?v=zone2primer",
    "https://www.youtube.com/watch?v=knifeskills101",
  ], "video ids become watch URLs, past the playlist metadata block above the header");
  eq(iso(csv.candidates[0].savedAt), "2024-02-01T09:00:00.000Z", "the playlist timestamp is the saved date");
  eq(csv.skipped, 1, "the row with no video id is skipped");

  const json = parse("takeout_watch_history.json");
  eq(urls(json), ["https://www.youtube.com/watch?v=deadliftform"], "titleUrl entries only");
  eq(json.candidates[0].title, "Why your deadlift stalls at 100kg — form breakdown", "the 'Watched ' prefix is Takeout's, not a title");
  eq(json.candidates[0].author, "Squat Mechanics", "the channel is the author");
});

group("Pinterest", () => {
  const out = parse("pinterest_pins.csv");
  eq(out.format, "pinterest", "format is pinterest");
  eq(urls(out), [
    "https://www.pinterest.com/pin/1000000000000001/",
    "https://www.pinterest.com/pin/1000000000000002/",
  ], "the pin is what you saved, not the site it points at");
  eq(out.candidates[0].title, "Small living room ideas, ranked",
    "a quoted comma inside a title does not shift every column after it");
  eq(out.candidates[0].author, "Home", "the board is the author");
});

group("Browser bookmarks", () => {
  const out = parse("bookmarks.html");
  eq(out.format, "browserBookmarks", "format is browserBookmarks");
  eq(urls(out), [
    "https://example.com/search?q=index+funds&sort=new",
    "https://www.bbc.co.uk/news/articles/election-results",
    "https://www.youtube.com/watch?v=zone2primer",
  ], "&amp; in an href is decoded, javascript: and chrome:// are dropped");
  eq(out.skipped, 2, "the two junk rows are counted as skipped");
  eq(out.candidates[1].title, "Election results & what the numbers mean", "entities in titles are decoded");
  eq(iso(out.candidates[0].savedAt), "2023-11-14T22:15:23.000Z", "ADD_DATE is the saved date");
  eq(out.candidates[2].savedAt, null, "no ADD_DATE, no invented date");
});

group("Loose files", () => {
  const list = parse("links.txt");
  eq(list.format, "plainList", "format is plainList");
  eq(urls(list), [
    "https://example.com/how-to-fix-a-leaking-tap",
    "https://www.youtube.com/watch?v=knifeskills101",
    "https://example.com/a-post-about-nothing",
  ], "links out of prose, without the sentence's punctuation, and no ftp://");

  const generic = parse("generic.json");
  eq(urls(generic), [
    "https://example.com/a-quiet-page",
    "https://example.com/deep-link",
  ], "an unknown JSON shape is walked for anything that looks like a link");

  // The same walk over an arbitrary file *inside an archive* would import a
  // Takeout search history, so it is off there.
  const strict = Importer.parseText(fixture("generic.json"), "generic.json", { strict: true });
  eq(strict.candidates.length, 0, "the generic walk never runs on a zip member");
});

/* ══ Zip ═════════════════════════════════════════════════════════════════ */

/** Builds a real zip (one stored member, one deflated) so the reader is tested
    against bytes rather than a mock. */
function buildZip(files) {
  const enc = new TextEncoder();
  const locals = [], central = [];
  let offset = 0;
  for (const [name, text, store] of files) {
    const nameBytes = enc.encode(name);
    const raw = enc.encode(text);
    const body = store ? raw : zlib.deflateRawSync(raw);
    const method = store ? 0 : 8;
    const crc = zlib.crc32 ? zlib.crc32(raw) : 0;

    const local = Buffer.alloc(30 + nameBytes.length);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4); local.writeUInt16LE(0, 6);
    local.writeUInt16LE(method, 8);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(raw.length, 22);
    local.writeUInt16LE(nameBytes.length, 26); local.writeUInt16LE(0, 28);
    Buffer.from(nameBytes).copy(local, 30);
    locals.push(local, Buffer.from(body));

    const cen = Buffer.alloc(46 + nameBytes.length);
    cen.writeUInt32LE(0x02014b50, 0);
    cen.writeUInt16LE(20, 4); cen.writeUInt16LE(20, 6);
    cen.writeUInt16LE(method, 10);
    cen.writeUInt32LE(crc, 16);
    cen.writeUInt32LE(body.length, 20);
    cen.writeUInt32LE(raw.length, 24);
    cen.writeUInt16LE(nameBytes.length, 28);
    cen.writeUInt32LE(offset, 42);
    Buffer.from(nameBytes).copy(cen, 46);
    central.push(cen);
    offset += local.length + body.length;
  }
  const dir = Buffer.concat(central);
  const eocd = Buffer.alloc(22);
  eocd.writeUInt32LE(0x06054b50, 0);
  eocd.writeUInt16LE(files.length, 8);
  eocd.writeUInt16LE(files.length, 10);
  eocd.writeUInt32LE(dir.length, 12);
  eocd.writeUInt32LE(offset, 16);
  return new Blob([Buffer.concat([...locals, dir, eocd])]);
}

await group("Zip", async () => {
  const zip = buildZip([
    // Deflated, in the shape Meta actually ships.
    ["your_instagram_activity/saved/saved_posts.json", fixture("instagram_saved_posts.json"), false],
    // Stored, to cover method 0.
    ["data/like.js", fixture("x_like.js"), true],
    // Must be ignored: importing a Takeout search history is not "your saves".
    ["Takeout/My Activity/Search/MyActivity.json", JSON.stringify([{ url: "https://example.com/a-search-i-did" }]), false],
    ["media/posts/photo.jpg", "not really a jpeg", true],
  ]);
  zip.name = "instagram.zip";

  ok(await Zip.looksLikeZip(zip), "sniffs a zip by its local file header");
  const entries = await Zip.entries(zip);
  eq(entries.length, 4, "reads every central directory entry");

  const out = await Importer.parseZip(zip, () => {});
  eq(out.format, "instagram", "labels the archive by its strongest member");
  eq(out.files, ["your_instagram_activity/saved/saved_posts.json", "data/like.js"],
    "opens the saves and nothing else");
  eq(out.candidates.length, 5, "3 Instagram saves + 2 X likes");
  ok(!urls(out).some(u => u.includes("a-search-i-did")), "a Takeout activity dump is never imported");

  const empty = buildZip([["media/posts/photo.jpg", "x", true]]);
  empty.name = "photos.zip";
  let message = "";
  try { await Importer.parseZip(empty, () => {}); } catch (e) { message = e.message; }
  ok(message.includes("photos.zip"), "the error names the file");
  ok(/JSON/i.test(message), "…and says what was expected");
});

/* ══ Categorizer parity with Core/Categorizer.swift ═══════════════════════ */

group("Categorizer parity", () => {
  const doc = JSON.parse(fixture("categorizer_cases.json"));
  let ambiguous = 0;
  for (const c of doc.cases) {
    const title = c.title || Filer.fallbackTitle(c.url);
    eq(title, c.fallbackTitle && !c.title ? c.fallbackTitle : c.title,
      `title in: ${c.url}`);
    eq(Filer.fallbackAuthor(c.url), c.fallbackAuthor, `fallbackAuthor: ${c.url}`);

    const got = Filer.suggest(c.url, title, c.text || null);
    const mine = { score: got.score, subtopic: got.subtopic, tags: got.tags, topic: got.topic };
    const hit = c.expect.some(e => JSON.stringify(e) === JSON.stringify({
      score: mine.score, subtopic: mine.subtopic, tags: mine.tags, topic: mine.topic,
    }));
    if (c.expect.length > 1) ambiguous++;
    ok(hit, `Swift parity: ${c.url}\n       Swift ${JSON.stringify(c.expect)}\n       JS    ${JSON.stringify(mine)}`);
  }
  console.log(`     (${doc.cases.length} cases, ${ambiguous} where the Swift itself is not deterministic)`);
});

group("Categorizer internals", () => {
  eq(Filer._stem("stretches"), "stretch", "stretches → stretch, so it matches Stretching");
  eq(Filer._stem("mobility"), "mobility", "short words are left alone");
  eq(Filer._stem("movies"), "movy", "ies → y, even when the result isn't a word");
  eq(Filer._stem("trees"), "tre", "es comes off once the stem still has three letters");
  eq(Filer._stem("sets"), "sets", "four letters are left alone — the Swift's own comment claims otherwise, the code doesn't");
  eq(Filer._normalise("Five-Hip_Mobility.Drills"), " five hip mobility drill ", "slugs become tokens");
  ok(Filer.isSiteName("Twitter") && Filer.isSiteName("YouTube") && !Filer.isSiteName("kenji"),
    "site names never become tags");
  eq(Filer.suggest("https://example.com/", "asdkjh qwe zxc", null).topic, null,
    "no signal is an honest answer, not a guess");
});

group("Identity and guardrails", () => {
  eq(Importer.normaliseLink(" https://example.com/x "), "https://example.com/x", "links are trimmed");
  eq(Importer.normaliseLink("http://localhost/x"), null, "a host with no dot is not a link");
  eq(Importer.normaliseLink("javascript:alert(1)"), null, "javascript: is not a link");
  eq(Importer.normaliseLink("chrome://bookmarks"), null, "chrome:// is not a link");
  ok(Importer.MAX_RECORDS === 5000, "one import is capped at 5,000 records");

  // Identical to the add path: the same link twice is one bork.
  const dupes = Importer.dedupe([
    { url: "https://www.instagram.com/p/abc/?igshid=1" },
    { url: "https://instagram.com/p/abc" },
    { url: "https://example.com/x" },
  ]);
  eq(dupes.length, 2, "stableID collapses tracking params and host prefixes");
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
