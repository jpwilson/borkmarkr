#!/usr/bin/env node
/**
 * Tests for docs/picker.js — what the topic picker matches, and the order it
 * puts the matches in.
 *
 *     node Scripts/test_picker.mjs
 *
 * The ordering is a cross-platform contract like BrowseSort's labels: the row
 * at the top of a search is the row people tap without reading, so it has to
 * be the same row on both platforms. These are the JavaScript half of
 * `Scripts/test_topic_picker.swift`, plus the tier rule iOS 1.1.1 adds — a
 * topic whose own name answers the query outranks one that only matched
 * through a subtopic, whoever made either of them.
 *
 * Same shape as Scripts/test_browse.mjs and Scripts/test_revisit.mjs: the file
 * is loaded into a vm context exactly as the browser loads it, and nothing here
 * touches a DOM. The real taxonomy is read out of docs/taxonomy.js so the
 * checks are about topics that actually ship.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => fs.readFileSync(p, "utf8");

const ctx = vm.createContext({ console });
vm.runInContext(read(path.join(ROOT, "docs", "taxonomy.js")), ctx, { filename: "taxonomy.js" });
vm.runInContext(read(path.join(ROOT, "docs", "picker.js")), ctx, { filename: "picker.js" });
const { TopicPickerQuery: Q, TAXONOMY } = vm.runInContext("({ TopicPickerQuery, TAXONOMY })", ctx);

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

const topic = (id) => {
  const t = TAXONOMY.find(x => x.id === id);
  if (!t) throw new Error(`missing topic ${id}`);
  return t;
};
const fitness = topic("fitness"), gaming = topic("gaming"), marketing = topic("marketing");
/* What the picker hands `order`: the shipped 50 plus whatever the person made,
   each one carrying its own subtopics. `custom` rides along untouched. */
const entry = (t) => ({ id: t.id, name: t.name, subs: t.subs, custom: !!t.custom });
const mine = (name, subs = []) => ({ id: `c-${name.toLowerCase()}`, name, subs, custom: true });
const names = (list) => list.map(x => x.name);

/* ══ Matching: unchanged from 1.0, and the reason this file exists ═══════ */

group("A query matches a topic by its name or by one of its subtopics", () => {
  eq(Q.tier(fitness.name, fitness.subs, "run"), Q.SUB, "run reaches Fitness through Running");
  eq(Q.tier(gaming.name, gaming.subs, "run"), Q.NONE, "run does not reach Gaming through Speedruns");
  eq(Q.tier(gaming.name, gaming.subs, "speed"), Q.SUB, "speed reaches Gaming through Speedruns");
  eq(Q.tier(gaming.name, gaming.subs, "game"), Q.NAME, "game matches Gaming by its own name");
  eq(Q.tier(marketing.name, marketing.subs, "brand"), Q.SUB, "brand reaches Marketing through Branding");
  eq(Q.tier(fitness.name, fitness.subs, ""), Q.NAME, "an empty query matches everything");
  eq(Q.tier(fitness.name, fitness.subs, "   "), Q.NAME, "and so does one that is only spaces");
  eq(Q.tier("Fitness", [], "zzz"), Q.NONE, "nonsense matches nothing");
});

group("The tier numbers are the cross-platform half", () => {
  eq([Q.NAME, Q.SUB, Q.NONE], [2, 1, 0], "2 name, 1 subtopic, 0 none — the numbers iOS uses");
  ok(Q.NAME > Q.SUB && Q.SUB > Q.NONE, "higher is better, so the tier can be compared directly");
});

group("Subtopic matching stays token-prefix, never mid-word", () => {
  ok(Q.matchingSubs(fitness.subs, "run").has("Running"), "Running lights up for run");
  eq([...Q.matchingSubs(gaming.subs, "run")], [], "no Gaming subtopic is a run- token");
  eq([...Q.matchingSubs(fitness.subs, "")], [], "an empty query lights nothing up");
  ok(Q.matchingSubs(["Zone 2"], "zone").has("Zone 2"), "a two-word subtopic matches on its first word");
});

group("Folding is case- and accent-blind", () => {
  eq(Q.fold("Índex"), "index", "accents come off and case comes down");
  eq(Q.tier("Índex", [], "index"), Q.NAME, "so “index” finds “Índex”");
  eq(Q.tokens("Food & Drink"), ["food", "drink"], "punctuation splits words");
  eq(Q.stem("gaming"), "gam", "‑ing comes off a long enough word");
  eq(Q.stem("run"), "run", "and a short one is left alone");
});

/* ══ Ordering — the iOS 1.1.1 rule ══════════════════════════════════════ */

group("A topic's own name beats a topic that only matched through a subtopic", () => {
  // The bug this fixes: typing "runn" put Fitness (which has a Running in it)
  // above the person's own topic called Running.
  const list = Q.order([entry(fitness), mine("Running", ["Trail", "Track"])], "runn");
  eq(names(list), ["Running", "Fitness"], "Running first, Fitness second");
  eq(list[0].custom, true, "and being a topic of yours is not what put it there");

  const both = Q.order([entry(fitness), { id: "running", name: "Running", subs: [] }], "runn");
  eq(names(both), ["Running", "Fitness"], "a built-in Running would rank the same way");
});

group("Inside a tier: the whole name, then a prefix, then anywhere else, then A–Z", () => {
  const list = Q.order([
    { name: "Long running", subs: [] },     // prefix on a later word
    { name: "Running", subs: [] },          // the query itself
    { name: "Trail running", subs: [] },    // prefix on a later word, later A–Z
    { name: "Rerunning", subs: [] },        // the query is in there somewhere
  ], "running");
  eq(names(list), ["Running", "Long running", "Trail running", "Rerunning"],
    "exact, then the two prefixes A–Z, then the substring");
});

group("Subtopic matches are ranked among themselves too", () => {
  const list = Q.order([
    { name: "Zebra", subs: ["Running shoes"] },   // token prefix
    { name: "Alpha", subs: ["Running"] },         // the query itself
  ], "running");
  eq(names(list), ["Alpha", "Zebra"], "the subtopic that is the query comes first");
  eq(names(Q.order([{ name: "Zebra", subs: ["Running"] }, { name: "Alpha", subs: ["Running"] }], "running")),
    ["Alpha", "Zebra"], "and an even match falls back to A–Z");
});

group("Nothing that does not match comes back", () => {
  const list = Q.order(TAXONOMY.map(entry), "run");
  ok(list.some(t => t.id === "fitness"), "run lists Fitness");
  ok(!list.some(t => t.id === "gaming"), "run does not list Gaming");
  ok(list.every(t => Q.tier(t.name, t.subs, "run") !== Q.NONE), "every row returned actually matched");
  eq(Q.order(TAXONOMY.map(entry), "zzzzz"), [], "and a query nothing answers returns nothing");
});

group("No query is no ranking: every topic, A–Z", () => {
  const all = Q.order(TAXONOMY.map(entry), "");
  eq(all.length, TAXONOMY.length, "nothing is dropped");
  eq(names(all), names(all.slice().sort((a, b) =>
    a.name.localeCompare(b.name, undefined, { numeric: true, sensitivity: "base" }))), "A–Z");
  eq(names(Q.order([mine("apple"), { name: "Banana", subs: [] }, mine("Cherry")], "")),
    ["apple", "Banana", "Cherry"], "yours and the shipped ones sort together, case-insensitively");
});

group("`order` does not mutate or reshape what it was given", () => {
  const input = [entry(gaming), entry(fitness)];
  const before = names(input);
  const out = Q.order(input, "run");
  eq(names(input), before, "the array it was handed is left alone");
  ok(out[0] === input[1], "and the entries come back by reference, extras and all");
});

/* ══ Subtopics are drawn A–Z, never in taxonomy order ═══════════════════ */

group("A topic's subtopics come out alphabetical, built-in and yours together", () => {
  // JP's report: Health read Conditions, Medications, Symptoms, Sleep, Heart &
  // BP, Diabetes… — the authored order — in the 1.0.1 picker.
  const health = topic("health");
  const az = health.subs.slice().sort((a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" }));
  eq(Q.alphabetical(health.subs), az, "Health's subtopics are drawn A–Z");
  ok(JSON.stringify(az) !== JSON.stringify(health.subs), "…which is not the order the taxonomy authored");
  eq(Q.alphabetical(["Zone 10", "bouldering", "Zone 2", "Mobility"]), ["bouldering", "Mobility", "Zone 2", "Zone 10"],
    "a person's own subtopics sort in with the built-ins, case-insensitively and numerically");
  const input = ["b", "a"];
  Q.alphabetical(input);
  eq(input, ["b", "a"], "and the taxonomy data itself is never reordered");
});

/* ══ "Can I add that?" — the affordances under the matches ══════════════ */

group("Adding a topic or a subtopic", () => {
  ok(Q.canAdd("Run", fitness.subs), "Run is a new Fitness subtopic");
  ok(!Q.canAdd("Running", fitness.subs), "Running already exists");
  ok(!Q.canAdd("running", fitness.subs), "and case does not make a second one");
  ok(!Q.canAdd("r", []), "single-letter names are refused");
  ok(!Q.canAdd("  ", []), "and so is whitespace");
  ok(Q.canAdd("Juice", []), "with nothing to clash with, anything long enough is fine");
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
