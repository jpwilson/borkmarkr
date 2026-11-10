#!/usr/bin/env node
/**
 * Tests for the refine panel's order on the web — QuickFileDial.refine in
 * docs/quick-file.js.
 *
 *     node Scripts/test_quick_file_refine.mjs
 *
 * The JS twin of Scripts/test_quick_file_refine.swift: the same fixture
 * (Scripts/fixtures/quick_file_refine_cases.json), so the subtopic and tag
 * chips under the dial come in the order the phone shows them, and a typed
 * tag is cleaned the same way. docs/import.js is loaded first for
 * Filer.isSiteName, as the page loads it. Below the divider: the dial's
 * refine mode itself is DOM-bound, so only its pure parts are checked here.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => fs.readFileSync(path.join(ROOT, p), "utf8");

function pageHelpers() {
  const html = read("docs/index.html");
  const from = html.indexOf("const ENT = {");
  const to = html.indexOf("/* ── Session ── */");
  if (from < 0 || to < 0 || to < from) throw new Error("docs/index.html: couldn't find the helper block import.js needs.");
  return html.slice(from, to);
}

const ctx = vm.createContext({ TextDecoder, Response, URL, console });
vm.runInContext(read("docs/taxonomy.js"), ctx, { filename: "taxonomy.js" });
vm.runInContext(pageHelpers(), ctx, { filename: "index.html helpers" });
vm.runInContext(read("docs/import.js"), ctx, { filename: "import.js" });
vm.runInContext(read("docs/quick-file.js"), ctx, { filename: "quick-file.js" });
const { QuickFileDial } = vm.runInContext("({ QuickFileDial })", ctx);
const R = QuickFileDial.refine;
const cases = JSON.parse(read("Scripts/fixtures/quick_file_refine_cases.json"));

let failures = 0, checks = 0;
function eq(actual, expected, message) {
  checks++;
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a === b) return;
  failures++;
  console.log(`FAIL ${message}\n     expected ${b}\n     got      ${a}`);
}

for (const c of cases.subtopics) eq(R.subtopicChips(c.all, c.suggested, c.used), c.expect, `subtopics: ${c.name}`);
for (const c of cases.tags) eq(R.tagChips(c.chosen, c.suggested, c.recent), c.expect, `tags: ${c.name}`);
for (const c of cases.clean) eq(R.cleanTag(c.raw), c.expect, `cleanTag(${JSON.stringify(c.raw)})`);

/* ── Web only ── */
eq(Object.isFrozen(R), true, "the refine helpers are frozen like the rest of the dial");
eq(R.subtopicChips(null, null, null), [], "missing lists are empty lists");
eq(R.tagChips(undefined, ["run"]), [{ tag: "run", on: false }], "chosen defaults to none");
eq(R.cleanTag(null), null, "cleanTag(null)");

console.log(`Quick File refine: ${checks - failures}/${checks} checks passed (${cases.subtopics.length} subtopic, ${cases.tags.length} tag, ${cases.clean.length} clean cases).`);
if (failures) process.exit(1);
