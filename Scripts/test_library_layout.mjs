import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
const c = vm.createContext({});
vm.runInContext(fs.readFileSync("docs/library-presentation.js", "utf8") + ";globalThis.rules=LibraryPresentation", c);
for (const width of [320, 390, 430, 760]) assert.equal(c.rules.columns(width), 2);
assert.equal(c.rules.columns(1280), 5);
const rows = [
  {id:1, subcategory:"Zulu",platform:"x",tags:["z","a"]},
  {id:2, subcategory:"Alpha",platform:"x",tags:["z","a"]},
  {id:3, subcategory:"Alpha",platform:"web",tags:["z"]}
];
assert.equal(JSON.stringify(c.rules.subtopics(rows)), '["Alpha","Zulu"]');
assert.equal(c.rules.filter(rows, {sub:"Alpha",source:"x",tag:"a"})[0].id, 2);
assert.equal(c.rules.filter(rows, {sub:"Alpha",source:"web",tag:"a"}).length, 0);
assert.equal(JSON.stringify(c.rules.tags(rows.slice(0,2))), '[["a",2],["z",2]]');
const html=fs.readFileSync("docs/index.html","utf8");
for(const match of html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)) new vm.Script(match[1]);
const tabs=html.slice(html.indexOf('<nav class="tabbar"'),html.indexOf('<!-- Add -->'));
assert.ok(tabs.indexOf('data-tab-link="revisit"') < tabs.indexOf('data-tab-link="you"'));
assert.match(html,/density: feedDensity/);
assert.match(html,/No borks match these filters/);
console.log("Responsive feed rules, refinements, navigation and script syntax passed.");
