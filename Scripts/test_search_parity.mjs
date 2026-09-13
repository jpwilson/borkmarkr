import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
const html = fs.readFileSync("docs/index.html", "utf8");
const fold = s => String(s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();
const c = vm.createContext({ fold, topicFor: id => ({ name: id }) });
vm.runInContext(html.slice(html.indexOf("const SCOPES ="), html.indexOf("/* ── Opens")), c);
const row = { _blob: "hip strength mobility cafe", tags: ["mobility"], subcategory: null };
for (const query of ["hip mobility", "MOBILITY  hip", "café", ""]) {
  assert.equal(c.matchesQuery(row, fold(query).split(/\s+/).filter(Boolean), new Set()), true);
}
assert.equal(c.matchesQuery(row, ["hip", "mobility"], new Set(["tags"])), false);
assert.equal(c.matchesQuery(row, ["hip", "unknown"], new Set()), false);
const selector = {};
c.esc = x => x;
c.TAXONOMY = [{id:"z",name:"Zulu"},{id:"a",name:"Alpha"}];
c.myTopics = () => [{id:"custom.b",name:"Beta"}];
vm.runInContext(html.slice(html.indexOf("function fillTopicSelect("), html.indexOf("function openAdd(")), c);
c.fillTopicSelect(selector, "custom.b");
assert.ok(selector.innerHTML.indexOf(">Alpha<") < selector.innerHTML.indexOf(">Beta<"));
assert.ok(selector.innerHTML.indexOf(">Beta<") < selector.innerHTML.indexOf(">Zulu<"));
assert.match(selector.innerHTML, /custom.b" selected/);
console.log("Search parity and mixed custom/built-in A–Z selector passed.");
