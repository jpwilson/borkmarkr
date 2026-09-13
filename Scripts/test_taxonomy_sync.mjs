import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";
const c = vm.createContext({});
vm.runInContext(fs.readFileSync("docs/taxonomy-sync.js", "utf8"), c);
const storage = new Map(), server = {topics:new Map(), subtopics:new Map()};
let owner = "owner", offline = true;
const options = {
  session: () => ({ user_id: owner }),
  read: key => storage.get(key), write: (key,value) => storage.set(key,value),
  request: async (path, req = {}) => {
    if (offline) throw new Error("offline");
    const kind = path.includes("custom_subtopics") ? "subtopics" : "topics";
    if (req.method === "POST") {
      for (const row of req.body) server[kind].set(row.id, row);
      return req.body;
    }
    return [...server[kind].values()];
  }
};
let store = new c.TaxonomyStore(options);
store.put("topics", {id:"custom.cafe", name:"Café & ceramics", hue:77, image_url:"https://example.com/art.jpg"});
await new Promise(resolve => setImmediate(resolve));
assert.equal(store.pending.size, 1);
store = new c.TaxonomyStore(options);
assert.equal(store.topics.get("custom.cafe").name, "Café & ceramics");
offline = false;
await store.sync();
assert.equal(store.pending.size, 0);
assert.equal(server.topics.get("custom.cafe").hue, 77);
assert.equal(server.topics.get("custom.cafe").image_url, "https://example.com/art.jpg");
store.put("subtopics", {id:"custom.cafe|empty", category_id:"custom.cafe", name:"Empty subtopic"});
await new Promise(resolve => setImmediate(resolve));
await store.sync();
assert.equal(server.subtopics.size, 1);
owner = "other";
store.restore();
assert.equal(store.topics.size, 0);
assert.equal(store.pending.size, 0);
console.log("Taxonomy: exact names/colors/art, empty topics/subtopics, offline retry and owner cache isolation passed.");
const html = fs.readFileSync("docs/index.html", "utf8");
const empty = {id:"custom.empty",name:"Empty but saved",hue:77};
Object.assign(c, {
  taxonomySync: {topics:new Map([[empty.id, empty]])}, TAXONOMY:[], addedTopics:new Map(),
  isCustom:id => id.startsWith("custom."), topicFor:id => id === empty.id ? empty : null,
  sortFor:() => "alpha", BrowseSort:{byName:(a,b) => a.localeCompare(b), order:(_,rows) => rows},
});
vm.runInContext(html.slice(html.indexOf("function browseTiles("), html.indexOf("/* Every source you have actually saved")), c);
assert.equal(c.browseTiles([])[0][0], "custom.empty");
assert.equal(c.browseTiles([])[0][1], 0);
console.log("Browse includes synchronized empty topics.");
