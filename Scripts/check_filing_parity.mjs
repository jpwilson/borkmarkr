#!/usr/bin/env node
/**
 * Holds the web's Quick File ranking to the iPhone's.
 *
 *     node Scripts/check_filing_parity.mjs
 *
 * Scripts/fixtures/filing_suggest_cases.json is what Core/FilingSuggest.swift,
 * Core/FilingMemory.swift and Categorizer.scores answer, written by
 * Scripts/gen_filing_fixture.swift --write. This runs docs/filing-suggest.js
 * and Filer.scores (docs/import.js) over the same inputs and compares every
 * field: creator keys, cleaned on-screen text, keyword scores, the memory built
 * from the rows, the ranking and each reason line, plus the constants both
 * sides must share.
 *
 * Loaded the way the browser loads them: taxonomy.js, the page's helper block
 * (const ENT … Session, cut out of docs/index.html itself), import.js and
 * filing-suggest.js, in one vm context. One line per case; exits 1 on any
 * drift. It changes nothing.
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
  if (from < 0 || to < 0 || to < from) {
    throw new Error("docs/index.html: couldn't find the helper block (const ENT … /* ── Session ── */). "
      + "If it moved, update this script: filing-suggest.js needs detectPlatform and PLATFORM from it.");
  }
  return html.slice(from, to);
}

const ctx = vm.createContext({ TextDecoder, URL, console });
vm.runInContext(read("docs/taxonomy.js"), ctx, { filename: "taxonomy.js" });
vm.runInContext(pageHelpers(), ctx, { filename: "index.html helpers" });
vm.runInContext(read("docs/import.js"), ctx, { filename: "import.js" });
vm.runInContext(read("docs/filing-suggest.js"), ctx, { filename: "filing-suggest.js" });
const { Filer, FilingKeys, FilingMemory, FilingSuggest } =
  vm.runInContext("({ Filer, FilingKeys, FilingMemory, FilingSuggest })", ctx);

const doc = JSON.parse(read("Scripts/fixtures/filing_suggest_cases.json"));

/* Swift leaves a nil key out of what it encodes and the JS writes null, so
   nulls inside objects are dropped before comparing; nulls in arrays stay. */
function canon(value) {
  if (Array.isArray(value)) return value.map(canon);
  if (value && typeof value === "object") {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      if (value[key] !== null && value[key] !== undefined) out[key] = canon(value[key]);
    }
    return out;
  }
  return value;
}
const J = (v) => JSON.stringify(canon(v));
const same = (a, b) => J(a) === J(b);
const clip = (s, n = 400) => (s.length > n ? s.slice(0, n) + "…" : s);

let failures = 0, checks = 0;
function check(ok, message) {
  checks++;
  if (ok) return;
  failures++;
  console.log(`FAIL ${message}`);
}

/* ── Constants both sides must share ── */
check(same(FilingSuggest.WEIGHTS, doc.weights), `weights\n  Swift ${J(doc.weights)}\n  JS    ${J(FilingSuggest.WEIGHTS)}`);
check(same(FilingMemory.LIMITS, doc.limits), `limits\n  Swift ${J(doc.limits)}\n  JS    ${J(FilingMemory.LIMITS)}`);
check(same(FilingMemory.RECENCY, doc.recency), `recency\n  Swift ${J(doc.recency)}\n  JS    ${J(FilingMemory.RECENCY)}`);
check(same([...FilingSuggest.STARTERS], doc.starters), `starters (Taxonomy.onboardingInterests)\n  Swift ${J(doc.starters)}\n  JS    ${J(FilingSuggest.STARTERS)}`);
check(same([...FilingSuggest.FURNITURE], doc.furniture), `OCR furniture words\n  Swift ${J(doc.furniture)}\n  JS    ${J(FilingSuggest.FURNITURE)}`);
check(FilingSuggest.RING_SIZE === doc.ringSize, `ring size: Swift ${doc.ringSize}, JS ${FilingSuggest.RING_SIZE}`);

/* ── Creator and domain keys ── */
for (const k of doc.keys) {
  const author = k.author ?? null;
  const got = {
    creator: FilingKeys.creator(author, k.url),
    creatorLabel: FilingKeys.creatorLabel(author, k.url),
    domain: FilingKeys.domain(k.url),
  };
  check(k.expect.some((e) => same(e, got)),
    `keys: ${k.url} (author ${JSON.stringify(author)})\n  Swift ${J(k.expect)}\n  JS    ${J(got)}`);
}

/* ── On-screen text cleanup ── */
for (const o of doc.ocr) {
  const got = FilingSuggest.cleanOCR(o.lines);
  check(o.expect.some((e) => e === got),
    `cleanOCR ${clip(JSON.stringify(o.lines), 120)}\n  Swift ${JSON.stringify(o.expect)}\n  JS    ${JSON.stringify(got)}`);
}

/* ── Ranking cases ── */
const describe = (ranking, lines) => {
  const top = ranking.candidates.slice(0, 3).map((c) =>
    `${c.categoryID}${c.subcategory ? " › " + c.subcategory : ""} ${c.score} [${c.reasons.join(",")}]`).join(" | ");
  return `${top} · ${ranking.evidence}${ranking.preselect === 0 ? "" : " (no preselect)"} · ${lines[0] ?? "—"}`;
};

console.log(`Quick File ranking parity (${doc.cases.length} cases, now ${doc.now})`);
for (const c of doc.cases) {
  const raw = c.input;
  const ocrText = Array.isArray(raw.ocrLines) ? FilingSuggest.cleanOCR(raw.ocrLines) : null;
  const input = {
    url: raw.url,
    title: raw.title ?? "",
    text: raw.text ?? null,
    description: raw.description ?? null,
    author: raw.author ?? null,
    ocrText,
  };
  let memory = FilingMemory.build(FilingSuggest.historyFromRows(doc.memories[c.memory] || []), { now: doc.now });
  if (c.adding) memory = FilingMemory.adding(memory, FilingSuggest.historyFromRows(c.adding), { now: doc.now });
  const ranking = FilingSuggest.rank(input, memory, {
    ai: c.ai ?? null,
    pinned: c.pinned ?? null,
    taxonomyOrder: c.taxonomyOrder ?? null,
    now: doc.now,
    limit: c.limit ?? FilingSuggest.RING_SIZE,
  });
  const got = {
    creatorKey: FilingKeys.creator(input.author, input.url),
    creatorLabel: FilingKeys.creatorLabel(input.author, input.url),
    domain: FilingKeys.domain(input.url),
    ocrText,
    keywordScores: Filer.scores(input.url, input.title, input.text, { description: input.description, author: input.author }),
    ocrScores: ocrText ? Filer.scores(null, "", ocrText, {}) : [],
    memory,
    ranking,
    reasonLines: ranking.candidates.map((cand) => FilingSuggest.reasonLine(cand, input)),
  };

  const hit = c.expect.some((e) => same(e, got));
  console.log(`${hit ? "ok  " : "FAIL"} ${c.name}: ${describe(ranking, got.reasonLines)}`);
  checks++;
  if (hit) continue;
  failures++;
  const want = c.expect[0];
  for (const key of Object.keys(got)) {
    if (!same(want[key], got[key])) {
      console.log(`     ${key}\n       Swift ${clip(J(want[key]))}\n       JS    ${clip(J(got[key]))}`);
    }
  }
}

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
