#!/usr/bin/env node
/**
 * The web half of the clay palette: docs/palette.js against the fixture the
 * iPhone's Core/ClayPalette.swift wrote, so a topic is the same colour on both,
 * byte for byte. Plus the reference rows and both contrast rules, as the Swift
 * test checks them.
 *
 *     node Scripts/test_clay_palette.mjs
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => fs.readFileSync(path.join(ROOT, p), "utf8");

// Loaded as the page loads it: a plain script that sets globalThis.Palette.
const sandbox = {};
vm.runInNewContext(read("docs/palette.js"), sandbox, { filename: "docs/palette.js" });
const P = sandbox.Palette;
const cases = JSON.parse(read("Scripts/fixtures/clay_palette_cases.json"));
const taxonomy = read("docs/taxonomy.js");

let passed = 0, failed = 0;
const expect = (cond, msg) => { if (cond) passed++; else { failed++; console.log(`FAIL ${msg}`); } };
const same = (c, e) => c.tint === e.tint && c.mid === e.mid && c.deep === e.deep;

// 1. The fixture, exactly.
expect(cases.hues.length === 360, `fixture has 360 hues, not ${cases.hues.length}`);
for (const e of cases.hues) {
  const c = P.colours(e.hue);
  expect(same(c, e), `hue ${e.hue}: ${c.tint} ${c.mid} ${c.deep} ≠ fixture ${e.tint} ${e.mid} ${e.deep}`);
  expect(P.tint(e.hue) === e.tint && P.mid(e.hue) === e.mid && P.deep(e.hue) === e.deep && P.solid(e.hue) === e.mid,
    `hue ${e.hue}: the cached accessors agree`);
}
for (const e of cases.topics) {
  expect(same(P.colours(e.hue), e), `${e.id} (hue ${e.hue}) matches the fixture`);
  // The web's taxonomy carries the same hue as the phone's.
  const m = taxonomy.match(new RegExp(`"id":\\s*"${e.id}",\\s*"name":[^\\n]*\\n\\s*"hue":\\s*(\\d+(?:\\.\\d+)?)`));
  expect(m && Number(m[1]) === e.hue, `docs/taxonomy.js gives ${e.id} hue ${e.hue}`);
}
expect(same(P.neutral, cases.neutral), "Palette.neutral is the fixture's Sand");
expect(P.of(null) === P.neutral && P.of(undefined) === P.neutral, "Palette.of(null) is Sand");
expect(same(P.of(152), cases.hues[152]), "Palette.of(hue) is that hue's colours");
expect(P.chip(96) === `background:${P.tint(96)};color:${P.deep(96)}`, "Palette.chip is tint + deep");
expect(!/gradient\(.*,(?!\s*#)/.test(P.gradient(96)) && P.gradient(96).includes(P.tint(96)), "Palette.gradient is the flat tint");

// 2. Reference rows: within ±6 per channel; Sand exactly.
const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const dist = (a, b) => Math.max(...rgb(a).map((v, i) => Math.abs(v - rgb(b)[i])));
let worstRef = 0;
for (const ref of P.references) {
  const got = ref.topicHue === null ? P.neutral : P.colours(ref.topicHue);
  const d = ["tint", "mid", "deep"].map((k) => dist(got[k], ref.colours[k]));
  worstRef = Math.max(worstRef, ...d);
  if (ref.topicHue === null) expect(d.every((x) => x === 0), `${ref.family} is the row exactly`);
  else expect(d.every((x) => x <= 6), `${ref.family} (hue ${ref.topicHue}) within ±6 (off by ${d})`);
}

// 3. Contrast, both rules, every hue and Sand.
let worstA = [99, ""], worstB = [99, ""];
const check = (c, what) => {
  const a = P.contrast(c.deep, c.tint), b = P.contrast("#FFFFFF", c.deep);
  expect(a >= 4.5, `${what}: deep on tint ${a.toFixed(2)}:1`);
  expect(b >= 4.5, `${what}: white on deep ${b.toFixed(2)}:1`);
  if (a < worstA[0]) worstA = [a, what];
  if (b < worstB[0]) worstB = [b, what];
};
for (let h = 0; h < 360; h++) check(P.colours(h), `hue ${h}`);
check(P.neutral, "Sand");

console.log(`worst deep on tint ${worstA[0].toFixed(2)}:1 (${worstA[1]}), worst white on deep ${worstB[0].toFixed(2)}:1 (${worstB[1]}), reference rows within ${worstRef}/255`);
console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
