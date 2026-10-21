#!/usr/bin/env node
/**
 * Asserts the discoverability basics on every public page in docs/.
 *
 * There is no build step on this site — docs/ is what GitHub Pages serves — so
 * this reads the committed HTML directly. Everything it checks is something a
 * crawler that runs no JavaScript can see.
 *
 *     node Scripts/check-seo.mjs
 *
 * For each page: a unique <title> and meta description, one <h1>, an absolute
 * self-referencing canonical on the production host, OG + Twitter tags, a lang
 * attribute, JSON-LD that parses, and more than 300 words of text with the
 * scripts stripped out. Plus the site-level files: robots.txt, sitemap.xml,
 * llms.txt, llms-full.txt and the IndexNow key.
 */
import { readFileSync, existsSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const DOCS = join(ROOT, "docs");
const SITE = "https://bookmarker.lol";

/** Public pages, and the canonical URL each one must claim.
 *  index.html is the web app; its marketing copy lives in #auth and
 *  #home-about, which are in the HTML for everyone and only hidden by JS once
 *  you are signed in. */
const PAGES = [
  { file: "index.html", path: "/" },
  { file: "what-is-bookmarker.html", path: "/what-is-bookmarker" },
  { file: "app/index.html", path: "/app/" },
  { file: "faq.html", path: "/faq" },
  { file: "alternatives.html", path: "/alternatives" },
  { file: "vs-twitter-bookmarks.html", path: "/vs-twitter-bookmarks" },
  { file: "vs-raindrop.html", path: "/vs-raindrop" },
  { file: "vs-twillot.html", path: "/vs-twillot" },
  { file: "vs-mymind.html", path: "/vs-mymind" },
  { file: "how-to-organize-twitter-bookmarks.html", path: "/how-to-organize-twitter-bookmarks" },
  { file: "how-to-search-twitter-bookmarks.html", path: "/how-to-search-twitter-bookmarks" },
  { file: "lifetime.html", path: "/lifetime" },
  { file: "palace/index.html", path: "/palace/" },
  { file: "press/index.html", path: "/press/" },
  { file: "privacy.html", path: "/privacy" },
  { file: "terms.html", path: "/terms" },
];

/** Pages that must carry the full marketing checklist: OG/Twitter cards,
 *  JSON-LD, 300+ words. Legal pages are public but are not sales pages. */
const MARKETING = new Set([
  "/", "/what-is-bookmarker", "/app/", "/faq", "/alternatives",
  "/vs-twitter-bookmarks", "/vs-raindrop", "/vs-twillot", "/vs-mymind",
  "/how-to-organize-twitter-bookmarks", "/how-to-search-twitter-bookmarks",
]);

let failures = 0;
let checks = 0;

function ok(cond, label, detail) {
  checks++;
  if (!cond) {
    failures++;
    console.log(`  FAIL  ${label}${detail ? " — " + detail : ""}`);
  }
}

/** Text a crawler that runs no JavaScript would see. */
function visibleText(html) {
  let s = html.replace(/<(script|style|noscript|svg|template)\b[\s\S]*?<\/\1>/gi, " ");
  s = s.replace(/<!--[\s\S]*?-->/g, " ");
  s = s.replace(/<head\b[\s\S]*?<\/head>/gi, " ");
  s = s.replace(/<[^>]+>/g, " ");
  return s.replace(/&[a-z#0-9]+;/gi, " ");
}

function words(text) {
  return text.split(/\s+/).filter((w) => /[\p{L}\p{N}]/u.test(w)).length;
}

/** <h1>s outside <script>/<style>/comments — the ones a crawler counts. */
function staticH1s(html) {
  const s = html
    .replace(/<(script|style|noscript|svg|template)\b[\s\S]*?<\/\1>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ");
  return [...s.matchAll(/<h1\b[^>]*>([\s\S]*?)<\/h1>/gi)].map((m) => m[1]);
}

const titles = new Map();
const descriptions = new Map();

console.log("Pages\n");
for (const { file, path } of PAGES) {
  const full = join(DOCS, file);
  console.log(`${path}  (docs/${file})`);
  if (!existsSync(full)) {
    failures++;
    console.log("  FAIL  file is missing");
    continue;
  }
  const html = readFileSync(full, "utf8");
  const url = SITE + path;
  const isMarketing = MARKETING.has(path);

  ok(/<html[^>]+lang="en"/i.test(html), "lang attribute");

  const title = (html.match(/<title>([\s\S]*?)<\/title>/i) || [])[1]?.trim();
  ok(!!title, "has a <title>");
  if (title) {
    ok(!titles.has(title), "title is unique", titles.get(title) && `also used by ${titles.get(title)}`);
    titles.set(title, path);
    ok(title.length <= 75, "title is not over-long", `${title.length} chars`);
  }

  const desc = (html.match(/<meta\s+name="description"\s+content="([^"]*)"/i) || [])[1]?.trim();
  ok(!!desc && desc.length > 50, "has a meta description", desc ? `${desc.length} chars` : "missing");
  if (desc) {
    ok(!descriptions.has(desc), "description is unique", descriptions.get(desc) && `also used by ${descriptions.get(desc)}`);
    descriptions.set(desc, path);
  }

  const canonical = (html.match(/<link\s+rel="canonical"\s+href="([^"]*)"/i) || [])[1];
  ok(canonical === url, "canonical is absolute and self-referencing", `got ${canonical || "nothing"}, want ${url}`);

  const h1s = staticH1s(html);
  ok(h1s.length === 1, "exactly one <h1>", `found ${h1s.length}`);

  if (isMarketing) {
    for (const tag of ["og:title", "og:description", "og:url", "og:image", "og:type"]) {
      ok(new RegExp(`<meta\\s+property="${tag}"\\s+content="[^"]+"`, "i").test(html), `has ${tag}`);
    }
    ok(/<meta\s+name="twitter:card"\s+content="summary_large_image"/i.test(html), "has twitter:card");
    ok(/<meta\s+name="twitter:(title|description|image)"/i.test(html), "has twitter card fields");
    ok(new RegExp(`<meta\\s+property="og:url"\\s+content="${url}"`, "i").test(html), "og:url matches the canonical");
  }

  const blocks = [...html.matchAll(/<script[^>]*type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi)];
  if (isMarketing) ok(blocks.length > 0, "has JSON-LD");
  const types = [];
  for (const [i, b] of blocks.entries()) {
    try {
      const parsed = JSON.parse(b[1]);
      types.push(parsed["@type"]);
      ok(parsed["@context"] === "https://schema.org", `JSON-LD block ${i + 1} declares schema.org`);
      // A rating we have not earned is a manual-action risk, so it must never appear.
      ok(!/aggregateRating/i.test(b[1]), `JSON-LD block ${i + 1} claims no aggregateRating`);
    } catch (e) {
      failures++;
      checks++;
      console.log(`  FAIL  JSON-LD block ${i + 1} does not parse — ${e.message}`);
    }
  }

  const wordCount = words(visibleText(html));
  if (isMarketing) ok(wordCount > 300, "over 300 words without JavaScript", `${wordCount} words`);

  // Internal linking: every marketing page reaches the hub pages.
  if (isMarketing) {
    for (const href of ["/faq", "/alternatives"]) {
      ok(html.includes(`href="${href}"`), `links to ${href}`);
    }
  }

  console.log(`  ok    ${wordCount} words, ${blocks.length} JSON-LD block(s)${types.length ? " [" + types.join(", ") + "]" : ""}`);
}

console.log("\nSite files\n");

const robots = readFileSync(join(DOCS, "robots.txt"), "utf8");
for (const bot of [
  "OAI-SearchBot", "ChatGPT-User", "GPTBot", "Claude-SearchBot", "Claude-User", "ClaudeBot",
  "PerplexityBot", "Perplexity-User", "Google-Extended", "Googlebot", "bingbot", "Applebot",
  "Applebot-Extended", "DuckAssistBot", "meta-externalagent", "CCBot",
]) {
  ok(new RegExp(`^User-agent: ${bot}$`, "mi").test(robots), `robots.txt names ${bot}`);
}
ok(/^Sitemap: https:\/\/bookmarker\.lol\/sitemap\.xml$/mi.test(robots), "robots.txt has an absolute Sitemap line");
ok(/^Disallow: \/c\/$/mi.test(robots), "robots.txt keeps shared collections out");
ok(!/^Disallow: \/$/mi.test(robots), "robots.txt does not block the site");

const sitemap = readFileSync(join(DOCS, "sitemap.xml"), "utf8");
const locs = [...sitemap.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
ok(new Set(locs).size === locs.length, "sitemap has no duplicate URLs");
for (const { path } of PAGES) {
  ok(locs.includes(SITE + path), `sitemap lists ${path}`);
}
for (const loc of locs) {
  ok(loc.startsWith(SITE + "/"), `sitemap URL is absolute: ${loc}`);
  ok(!/\.html$/.test(loc), `sitemap URL matches the canonical form: ${loc}`);
}
ok(/<lastmod>\d{4}-\d{2}-\d{2}<\/lastmod>/.test(sitemap), "sitemap has real lastmod dates");

for (const f of ["llms.txt", "llms-full.txt"]) {
  const p = join(DOCS, f);
  ok(existsSync(p), `${f} exists`);
  if (existsSync(p)) {
    const body = readFileSync(p, "utf8");
    ok(!/^\s*<!DOCTYPE/i.test(body), `${f} is text, not the HTML shell`);
    ok(body.length > 1000, `${f} has real content`, `${body.length} bytes`);
  }
}
ok(readFileSync(join(DOCS, "llms-full.txt"), "utf8").includes("/what-is-bookmarker"),
   "llms-full.txt covers the new pages");

const keyFiles = readdirSync(DOCS).filter((f) => /^[0-9a-f]{32}\.txt$/.test(f));
ok(keyFiles.length === 1, "exactly one IndexNow key file", `found ${keyFiles.length}`);
if (keyFiles.length === 1) {
  const key = keyFiles[0].replace(/\.txt$/, "");
  ok(readFileSync(join(DOCS, keyFiles[0]), "utf8").trim() === key, "IndexNow key file contains its own key");
  ok(readFileSync(join(ROOT, "Scripts", "indexnow.mjs"), "utf8").includes(key),
     "Scripts/indexnow.mjs uses the hosted key");
}

ok(/noindex/i.test(readFileSync(join(DOCS, "404.html"), "utf8")), "404.html is noindex");

console.log(`\n${checks - failures}/${checks} checks passed`);
if (failures) {
  console.log(`${failures} FAILED`);
  process.exit(1);
}
console.log("All good.");
