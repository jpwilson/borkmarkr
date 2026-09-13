import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
const c = vm.createContext({});
vm.runInContext(fs.readFileSync("docs/open-signals.js", "utf8"), c);
const server = new Map();
const client = (device, storage = new Map()) => new c.OpenSignalStore({
  device, session:() => ({user_id:"owner"}), read:key => storage.get(key),
  write:(key,v) => storage.set(key,v),
  request:async (_,req = {}) => {
    if (req.method === "POST") {
      for (const r of req.body) server.set(r.id, {...r,open_count:Math.max(server.get(r.id)?.open_count || 0,r.open_count)});
      return req.body.map(r => server.get(r.id));
    }
    return [...server.values()];
  },
});
const a = client("phone"), b = client("web");
a.bump("post"); a.bump("post"); b.bump("post");
await a.sync(); await b.sync(); await a.sync();
assert.equal(a.aggregate("post").n, 3);
assert.equal(b.aggregate("post").n, 3);
await a.sync(); await b.sync();
assert.equal(a.aggregate("post").n, 3, "retries do not count twice");
const storage = new Map(), offline = client("offline", storage);
offline.bump("post");
const reloaded = client("offline", storage);
await reloaded.sync(); await b.sync();
assert.equal(b.aggregate("post").n, 4);
const legacy = client("legacy");
legacy.seed("post", 8, "2026-09-01T00:00:00Z");
legacy.seed("post", 8, "2026-09-01T00:00:00Z");
legacy.bump("post");
assert.equal(legacy.aggregate("post").n, 9);
console.log("Open signals: concurrent devices, offline reload, legacy backfill and retry idempotency passed.");
