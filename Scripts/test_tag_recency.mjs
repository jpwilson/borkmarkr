#!/usr/bin/env node
/**
 * Tests for the web tag-recency rank — TagRecency in docs/import.js.
 *
 *     node Scripts/test_tag_recency.mjs
 *
 * The JS twin of Scripts/test_tag_recency.swift: same fixture, same
 * expectations, so the tags the Add sheet offers on the web are the tags the
 * phone would have offered. Everything below the divider is web-only ground the
 * Swift test doesn't need to cover — the `at` field arrives as an ISO string
 * off the wire and as a Date in the tests, and the two are not comparable as
 * text.
 *
 * Loaded the way the browser loads it: docs/import.js in a vm context stocked
 * with the handful of helpers it borrows from docs/index.html itself, so this
 * fails loudly if the page's identity rules move. Same shape as
 * Scripts/test_importers.mjs.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => fs.readFileSync(p, "utf8");

function pageHelpers() {
  const html = read(path.join(ROOT, "docs", "index.html"));
  const from = html.indexOf("const ENT = {");
  const to = html.indexOf("/* ── Session ── */");
  if (from < 0 || to < 0 || to < from) {
    throw new Error("docs/index.html: couldn't find the helper block (const ENT … /* ── Session ── */). "
      + "If it moved, update this test — import.js depends on those helpers.");
  }
  return html.slice(from, to);
}

const ctx = vm.createContext({ TextDecoder, Response, URL, console });
vm.runInContext(read(path.join(ROOT, "docs", "taxonomy.js")), ctx, { filename: "taxonomy.js" });
vm.runInContext(pageHelpers(), ctx, { filename: "index.html helpers" });
vm.runInContext(read(path.join(ROOT, "docs", "import.js")), ctx, { filename: "import.js" });
const { TagRecency } = vm.runInContext("({ TagRecency })", ctx);

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

/* ── Fixture: Scripts/test_tag_recency.swift's, to the hour ── */
const DAY = 86_400_000;
const NOW = Date.now();
const items = [
  { categoryID: "marketing", subcategory: "Ads", tags: ["ugc", "instagram"], at: new Date(NOW - DAY) },
  { categoryID: "marketing", subcategory: "Ads", tags: ["hook"], at: new Date(NOW) },
  { categoryID: "marketing", subcategory: "SEO", tags: ["audit"], at: new Date(NOW - 2 * DAY) },
  { categoryID: "fitness", subcategory: "Running", tags: ["goata"], at: new Date(NOW - 30 * DAY) },
  { categoryID: "fitness", subcategory: "Running", tags: ["tempo"], at: new Date(NOW - DAY) },
  { categoryID: "fitness", subcategory: "Yoga", tags: ["injuries"], at: new Date(NOW - 3600_000) },
];
const suggest = (opts) => TagRecency.suggestions(items, opts);

group("Parity with Scripts/test_tag_recency.swift", () => {
  const ads = suggest({ categoryID: "marketing", subcategory: "Ads", limit: 2 });
  ok(ads[0] === "hook", "most recent Ads tag wins");
  ok(ads.includes("ugc"), "older Ads tag still appears");
  ok(!ads.includes("instagram"), "platform names are dropped");
  ok(!ads.includes("audit"), "SEO-only tag is not in the Ads exact pair");
  ok(!ads.includes("goata"), "Fitness tags stay out of Marketing › Ads");

  const adsFilled = suggest({ categoryID: "marketing", subcategory: "Ads", limit: 8 });
  ok(adsFilled.includes("audit"), "thin Ads row fills from Marketing");

  eq(suggest({ categoryID: null, subcategory: null }), [], "no topic → no suggestions");

  eq(suggest({ categoryID: "marketing", subcategory: "Ads", prefix: "h" }), ["hook"], "prefix filter keeps hook");

  ok(!suggest({ categoryID: "marketing", subcategory: "Ads", excluding: ["hook"] }).includes("hook"),
    "already-applied tags are excluded");

  const running = suggest({ categoryID: "fitness", subcategory: "Running", limit: 2 });
  ok(running[0] === "tempo", "recency beats an older tag");
  ok(!running.includes("injuries"), "Yoga injuries is not an exact Running tag");
});

/* ── Web-only ground ── */
group("Rows as the web actually holds them", () => {
  // Supabase hands back "…+00:00"; this browser writes "….000Z". Comparing
  // those as strings puts the wrong tag first, which is why `at` is parsed.
  const mixed = [
    { categoryID: "fitness", subcategory: "Running", tags: ["older"], at: "2026-09-01T10:00:00+00:00" },
    { categoryID: "fitness", subcategory: "Running", tags: ["newer"], at: "2026-09-02T09:00:00.000Z" },
  ];
  eq(TagRecency.suggestions(mixed, { categoryID: "fitness", subcategory: "Running" }), ["newer", "older"],
    "ISO strings in either format sort by the instant they name");

  eq(TagRecency.suggestions([{ categoryID: "fitness", tags: ["a"], at: "not a date" }],
    { categoryID: "fitness" }), ["a"], "an unparseable stamp is old, not fatal");

  const missing = [{ categoryID: "fitness", subcategory: null, at: new Date(NOW) }];
  eq(TagRecency.suggestions(missing, { categoryID: "fitness" }), [], "a row with no tags array is skipped");
});

group("Case, the topic itself, and the shape of the answer", () => {
  const cased = [
    { categoryID: "fitness", subcategory: "Running", tags: ["Tempo", "tempo", "TEMPO"], at: new Date(NOW) },
  ];
  eq(TagRecency.suggestions(cased, { categoryID: "fitness", subcategory: "Running" }), ["tempo"],
    "one tag, lowercased, however it was typed");

  const echoes = [
    { categoryID: "fitness", subcategory: "Running", tags: ["fitness", "running", "tempo"], at: new Date(NOW) },
  ];
  eq(TagRecency.suggestions(echoes, { categoryID: "fitness", subcategory: "Running" }), ["tempo"],
    "a tag that only repeats the topic or subtopic says nothing");

  eq(TagRecency.suggestions(cased, { categoryID: "fitness", subcategory: "running" }), ["tempo"],
    "the subtopic matches whatever case it was saved in");

  const many = Array.from({ length: 20 }, (_, i) => (
    { categoryID: "fitness", subcategory: "Running", tags: [`tag${i}`], at: new Date(NOW - i * 60_000) }));
  ok(TagRecency.suggestions(many, { categoryID: "fitness", subcategory: "Running" }).length === TagRecency.limit,
    `never more than ${TagRecency.limit} chips`);

  const tied = [
    { categoryID: "fitness", subcategory: "Running", tags: ["zulu", "alpha"], at: new Date(NOW) },
  ];
  eq(TagRecency.suggestions(tied, { categoryID: "fitness", subcategory: "Running" }), ["alpha", "zulu"],
    "same instant → alphabetical, so the row doesn't shuffle between renders");

  const noSub = [
    { categoryID: "fitness", subcategory: "Yoga", tags: ["injuries"], at: new Date(NOW) },
    { categoryID: "fitness", subcategory: "Running", tags: ["tempo"], at: new Date(NOW - DAY) },
  ];
  eq(TagRecency.suggestions(noSub, { categoryID: "fitness" }), ["injuries", "tempo"],
    "no subtopic → the whole topic, newest first");
});

console.log(`\n${checks - failures}/${checks} checks passed`);
if (failures) process.exit(1);
