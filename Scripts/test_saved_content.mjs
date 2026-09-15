import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
const c = vm.createContext({});
vm.runInContext(fs.readFileSync("docs/saved-content.js", "utf8"), c);
for (const f of JSON.parse(fs.readFileSync("Scripts/fixtures/saved_content.json", "utf8"))) {
  assert.equal(c.SavedContent.title(f.raw, f.body, f.platform), f.want, f.raw);
}
assert.equal(c.SavedContent.breadcrumb("Health", "Green light"), "Health › Green light");
assert.equal(c.SavedContent.excerpt("Sign in to continue"), null);
assert.equal(c.SavedContent.excerpt("  a useful\ncaption  "), "a useful caption");
console.log("Saved content: shared fixtures and breadcrumbs passed.");
