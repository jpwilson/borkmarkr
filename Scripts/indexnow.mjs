#!/usr/bin/env node
/**
 * Pings IndexNow with every URL in docs/sitemap.xml.
 *
 * IndexNow is Bing, Yandex, Seznam and Naver — and Bing is what feeds Copilot,
 * DuckDuckGo and part of ChatGPT's search, so this is the cheapest way to get
 * a new or changed page noticed. Google does not accept IndexNow; for Google,
 * publish and let Googlebot find it (or request indexing in Search Console).
 *
 * Usage, from the repo root, AFTER the change is live on bookmarker.lol:
 *
 *     node Scripts/indexnow.mjs --dry-run     # print what would be sent
 *     node Scripts/indexnow.mjs               # actually submit
 *
 * The key below is hosted at https://bookmarker.lol/${KEY}.txt, which is how
 * IndexNow verifies that whoever is submitting controls the host. It is public
 * by design — it is not a secret and does not belong in .env.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const KEY = "d38c259473bfbc5ad6c60ed9ff497121";
const HOST = "bookmarker.lol";
const ENDPOINT = "https://api.indexnow.org/indexnow";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const sitemap = readFileSync(join(root, "docs", "sitemap.xml"), "utf8");
const urlList = [...sitemap.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/g)].map((m) => m[1]);

if (urlList.length === 0) {
  console.error("No <loc> entries in docs/sitemap.xml — nothing to submit.");
  process.exit(1);
}

const payload = { host: HOST, key: KEY, keyLocation: `https://${HOST}/${KEY}.txt`, urlList };
const dryRun = process.argv.includes("--dry-run");

console.log(`${dryRun ? "Would submit" : "Submitting"} ${urlList.length} URLs to ${ENDPOINT}`);
for (const u of urlList) console.log("  " + u);

if (dryRun) process.exit(0);

const res = await fetch(ENDPOINT, {
  method: "POST",
  headers: { "Content-Type": "application/json; charset=utf-8" },
  body: JSON.stringify(payload),
});
// 200 = accepted, 202 = accepted but the key is still being validated.
console.log(`${res.status} ${res.statusText}`);
const body = await res.text();
if (body) console.log(body);
process.exit(res.ok ? 0 : 1);
