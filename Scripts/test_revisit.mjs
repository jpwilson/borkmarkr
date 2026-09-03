#!/usr/bin/env node
/**
 * Tests for the Revisit arithmetic — docs/revisit.js.
 *
 *     node Scripts/test_revisit.mjs
 *
 * buildRevisit is the whole point of that file being separate: it is pure, it
 * takes its clock as an argument, and it returns plain objects. So it is
 * testable without a DOM — loaded into a vm context stocked with the one thing
 * it borrows from the page (TOPIC_BY_ID, built from the real taxonomy), and run
 * over a synthetic library whose every row is placed relative to a fixed NOW.
 *
 * Same shape as Scripts/test_importers.mjs.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => fs.readFileSync(p, "utf8");

/* ── Load docs/revisit.js the way the browser does ── */
const ctx = vm.createContext({ console });
vm.runInContext(read(path.join(ROOT, "docs", "taxonomy.js")), ctx, { filename: "taxonomy.js" });
// index.html's one line, so the names in this test are the real topic names.
vm.runInContext("const TOPIC_BY_ID = Object.fromEntries(TAXONOMY.map(t => [t.id, t]));", ctx, { filename: "TOPIC_BY_ID" });
vm.runInContext(read(path.join(ROOT, "docs", "revisit.js")), ctx, { filename: "revisit.js" });
const { buildRevisit, Revisit } = vm.runInContext("({ buildRevisit, Revisit })", ctx);

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

/* ── Fixture ──────────────────────────────────────────────────────────────
   A library placed around a fixed NOW. `d` is days ago, `o` is times opened. */
const DAY = 86_400_000;
const NOW = Date.parse("2026-09-03T12:00:00.000Z");
let seq = 0;
const bork = ({ d, topic = null, sub = null, tags = [], platform = "web", o = 0, openedD = null, deleted = false }) => {
  const id = `b${++seq}`;
  return {
    id, url: `https://example.com/${id}`, title: `Bork ${id}`, platform, kind: "article",
    category_id: topic, subcategory: sub, tags,
    saved_at: new Date(NOW - d * DAY).toISOString(),
    updated_at: new Date(NOW - d * DAY).toISOString(),
    deleted_at: deleted ? new Date(NOW).toISOString() : null,
    open_count: o,
    last_opened_at: o ? new Date(NOW - (openedD ?? 1) * DAY).toISOString() : null,
  };
};

const ROWS = [
  // ── This week (7): 3 Instagram, 2 X, 2 YouTube
  bork({ d: 0.5, topic: "fitness", platform: "instagram", o: 3, openedD: 0.2 }),
  bork({ d: 1, topic: "fitness", platform: "instagram", sub: "Mobility", tags: ["running"] }),
  bork({ d: 2, topic: "fitness", platform: "youtube", o: 9, openedD: 3 }),
  bork({ d: 3, topic: "recipes", platform: "instagram" }),
  bork({ d: 4, topic: "recipes", platform: "x" }),
  bork({ d: 5, topic: "travel", platform: "x", o: 3, openedD: 0.1 }),
  bork({ d: 6, topic: "history", platform: "youtube" }),
  // ── Last week (3): fitness had one, recipes none
  bork({ d: 8, topic: "fitness", platform: "x" }),
  bork({ d: 9, topic: "history", platform: "x", o: 1 }),
  bork({ d: 10, topic: "travel", platform: "web" }),
  // ── Older, inside 30 days
  bork({ d: 16, topic: "fitness", platform: "instagram" }),
  bork({ d: 20, topic: "recipes", platform: "instagram" }),
  bork({ d: 24, topic: "fitness", platform: "youtube" }),
  bork({ d: 27, topic: "travel", platform: "tiktok" }),
  // ── A month ago today (28–35): three of them, plus one just outside
  bork({ d: 29, topic: "art", platform: "x" }),
  bork({ d: 31, topic: "crypto", platform: "x" }),
  bork({ d: 34, topic: "crypto", platform: "youtube" }),
  bork({ d: 36, topic: "crypto", platform: "x" }),   // 36 days: outside "a month ago"
  // ── The 30 days before that
  bork({ d: 40, topic: "crypto", platform: "x" }),
  bork({ d: 44, topic: "investing", platform: "youtube" }),
  bork({ d: 48, topic: "investing", platform: "x" }),
  bork({ d: 52, topic: "history", platform: "web" }),
  // ── Never counted: a tombstone
  bork({ d: 12, topic: "fitness", platform: "x", deleted: true }),
];

const MISSIONS = [
  { id: "m1", title: "Train for running", category_id: "fitness", bookmark_ids: ["b1"],
    todos: [{ id: "t1", text: "Book a 10k", done: true }, { id: "t2", text: "Buy shoes", done: false }],
    is_archived: false, deleted_at: null, updated_at: "2026-09-01T00:00:00.000Z" },
  { id: "m2", title: "Learn pottery", category_id: "crafts", bookmark_ids: [],
    todos: [{ id: "t3", text: "Find a studio", done: true }],
    is_archived: false, deleted_at: null, updated_at: "2026-09-01T00:00:00.000Z" },   // nothing left
  { id: "m3", title: "Archived", category_id: null, bookmark_ids: [],
    todos: [{ id: "t4", text: "x", done: false }],
    is_archived: true, deleted_at: null, updated_at: "2026-09-01T00:00:00.000Z" },
  { id: "m4", title: "Deleted", category_id: null, bookmark_ids: [],
    todos: [{ id: "t5", text: "x", done: false }],
    is_archived: false, deleted_at: "2026-09-02T00:00:00.000Z", updated_at: "2026-09-02T00:00:00.000Z" },
];

const D = buildRevisit(ROWS, MISSIONS, NOW);

group("Shape", () => {
  eq(D.total, ROWS.length - 1, "tombstones are not part of the library");
  eq(D.thin, false, "22 borks is not a thin library");
  eq(Object.keys(D).sort(), ["monthAgo", "never", "quests", "repeat", "shifting", "thin", "total", "week"],
    "every section has a slot, empty or not");
});

group("1 · Saved this week", () => {
  eq(D.week.n, 7, "seven saved in the last seven days");
  eq(D.week.platforms, [{ key: "instagram", n: 3 }, { key: "x", n: 2 }, { key: "youtube", n: 2 }],
    "sources split, biggest first");
  eq(D.week.rising.map(t => [t.name, t.delta]), [["Fitness", 2], ["Recipes", 2]],
    "topics that grew on last week, biggest jump first — a topic that held steady is not growth");
  ok(D.week.rising.length <= 3, "at most three rising topics");
  ok(D.week.rising.every(t => t.id && t.name), "a rising topic carries the id goTopic needs, and its name");

  const quiet = buildRevisit(ROWS.filter(r => Date.parse(r.saved_at) < NOW - 7 * DAY), MISSIONS, NOW);
  eq(quiet.week, null, "a week with nothing saved has no section at all");
});

group("2 · You keep coming back to", () => {
  eq(D.repeat.rows.map(r => r.open_count), [9, 3, 3, 1], "most-opened first");
  ok(D.repeat.rows.length <= 5, "five at most");
  // b6 (travel) and b1 (fitness) are both on 3; b6 was opened more recently.
  eq(D.repeat.rows.slice(1, 3).map(r => r.id), ["b6", "b1"], "ties break on the most recent open");
  ok(D.repeat.rows.every(r => r.open_count > 0), "a bork you never opened is not one you come back to");

  const unopened = buildRevisit(ROWS.map(r => ({ ...r, open_count: 0, last_opened_at: null })), MISSIONS, NOW);
  eq(unopened.repeat, null, "no opens, no section");
});

group("3 · Saved, never opened", () => {
  ok(D.never.rows.every(r => !r.open_count), "every row is unopened");
  ok(D.never.rows.every(r => Date.parse(r.saved_at) < NOW - 7 * DAY), "nothing saved this week is called ignored");
  eq(D.never.n, 14, "fourteen saved and never looked at");
  eq(D.never.shown, 12, "twelve on screen");
  eq(D.never.more, 2, "and two more behind the button");
  const dates = D.never.rows.map(r => r.saved_at);
  eq([...dates].sort().reverse(), dates, "newest first");

  const small = buildRevisit(ROWS.slice(0, 12).map(r => ({ ...r, open_count: 0 })), MISSIONS, NOW);
  eq(small.never.more, 0, "under twelve, there is nothing more to show");
});

group("4 · A month ago today", () => {
  eq(D.monthAgo.rows.map(r => r.id), ["b15", "b16", "b17"], "28–35 days back, newest first");
  ok(D.monthAgo.rows.length <= 3, "three at most");
  const none = buildRevisit(ROWS.filter(r => Date.parse(r.saved_at) > NOW - 28 * DAY), MISSIONS, NOW);
  eq(none.monthAgo, null, "no month-old saves, no section");
});

group("5 · Side quests in progress", () => {
  eq(D.quests.missions.map(m => m.id), ["m1"], "only quests with a to-do left — never archived or deleted ones");
  eq(buildRevisit(ROWS, [], NOW).quests, null, "no quests, no section");
  eq(buildRevisit(ROWS, null, NOW).quests, null, "missing quests are not a crash");
});

group("6 · What's shifting", () => {
  eq(D.shifting.line, "Less Crypto, more Fitness, less Investing", "the sentence, biggest move first");
  eq(D.shifting.items.map(i => i.direction), ["down", "up", "down"], "each move carries which way it went");
  ok(!D.shifting.items.some(i => i.id === "history"), "a topic that barely moved is not a shift");
  ok(D.shifting.items.length <= 3, "three at most");
  ok(D.shifting.items[0].prevShare > D.shifting.items[0].share, "\"less\" means a smaller share than before");

  const thin = ROWS.slice(0, 12);
  eq(buildRevisit(thin, MISSIONS, NOW).shifting, null, "under 20 borks across both windows, we don't claim a trend");
  const onlyNew = ROWS.filter(r => Date.parse(r.saved_at) > NOW - 30 * DAY);
  eq(buildRevisit([...onlyNew, ...onlyNew.map((r, i) => ({ ...r, id: `dup${i}` }))], MISSIONS, NOW).shifting, null,
    "no 'before' window is not a trend either");
});

group("Thin library", () => {
  const few = buildRevisit(ROWS.slice(0, 9), MISSIONS, NOW);
  eq(few.total, 9, "nine borks");
  eq(few.thin, true, "under ten is thin");
  eq(buildRevisit(ROWS.slice(0, 10), MISSIONS, NOW).thin, false, "ten is not");
  eq(buildRevisit([], [], NOW).total, 0, "an empty library is a number, not an exception");
});

group("Purity", () => {
  const before = JSON.stringify(ROWS);
  buildRevisit(ROWS, MISSIONS, NOW);
  eq(JSON.stringify(ROWS), before, "buildRevisit never touches the rows it is given");
  const shuffled = [...ROWS].reverse();
  eq(JSON.stringify(buildRevisit(shuffled, MISSIONS, NOW)), JSON.stringify(D), "the answer does not depend on input order");
  eq(JSON.stringify(buildRevisit(ROWS, MISSIONS, NOW)), JSON.stringify(D), "same input, same answer");
  ok(Revisit.NEVER_SHOWN === 12, "twelve is the fold");
});

group("Junk in", () => {
  const messy = [null, undefined, { id: "x" }, { id: "y", saved_at: "not a date", open_count: "3" }];
  const d = buildRevisit(messy, [null, { id: "q" }], NOW);
  eq(d.total, 2, "rows that are not rows are dropped, the rest are counted");
  eq(d.never, null, "a bork with no saved date is not evidence of anything");
  eq(d.quests, null, "a quest with no to-dos is not in progress");
  eq(buildRevisit(null, null, null).total, 0, "no rows at all is 0, not a throw");
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
