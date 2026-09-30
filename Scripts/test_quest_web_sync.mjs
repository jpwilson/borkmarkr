import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
const html = fs.readFileSync("docs/index.html", "utf8");
const code = html.slice(html.indexOf("function absorbMissions("), html.indexOf("/* ── Clay art for the topics"));
const storage = new Map();
let offline = true;
const server = new Map();
function client(owner = "owner") {
  const c = vm.createContext({
    missions: new Map(), store: { session: { user_id: owner } },
    lsGet: key => storage.get(key), lsSet: (key, value) => storage.set(key, value),
    localStorage: { setItem: (key, value) => storage.set(key, value) },
    validSession: async () => ({ user_id: owner }), render() {}, toast() {}, humanError: String,
    api: async (path, options = {}) => {
      if (offline) throw new Error("offline");
      if (options.method === "POST") {
        for (const row of options.body) server.set(row.id, row);
        return options.body;
      }
      return [...server.values()];
    },
  });
  vm.runInContext(code, c);
  return c;
}
let c = client();
assert.equal(await c.commitMission({ id: "q", title: "Offline quest", todos: [{id:"t", text:"A step", done:true}] }), null);
assert.equal(JSON.parse(storage.get("bm.moutbox")).rows.length, 1);
c = client(); // reload must not lose unsent changes
offline = false;
await c.pullMissions();
assert.equal(server.get("q").title, "Offline quest");
assert.equal(server.get("q").todos[0].done, true);
assert.equal(JSON.parse(storage.get("bm.moutbox")).rows.length, 0);
c.absorbMissions([{id:"legacy", updated_at:"2026-09-12", todos:[{id:"t",title:"Old native spelling",done:true}]}]);
assert.equal(c.missions.get("legacy").todos[0].text, "Old native spelling");
storage.set("bm.moutbox", JSON.stringify({owner:"someone-else", rows:[{id:"private", title:"Never upload"}]}));
c = client();
await c.pullMissions();
assert.equal(server.has("private"), false);
console.log("Web quests: offline outbox survives reload, retries, preserves steps and isolates owners.");
