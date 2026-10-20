#!/usr/bin/env node
/**
 * Tests for the Library Atlas (docs/palace/).
 *
 *     node Scripts/test_palace.mjs
 *
 * palace-data.js is loaded into a bare vm context after docs/taxonomy.js,
 * exactly as the page loads them, and atlas-layout.js is pure numbers, so
 * nothing here needs a GPU or a DOM. What's checked is what the renderer
 * takes on trust: every count and date on screen is derived from the rows,
 * regions never overlap, districts stay inside their region and markers
 * inside their district, the scripted tour covers every beat, a library with
 * no timestamps produces no timeline rather than a fabricated one, and a
 * signed-in visitor's library is read with GETs only under the app's
 * bm.session contract.
 */
import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const read = (p) => fs.readFileSync(p, "utf8");
const plain = (x) => JSON.parse(JSON.stringify(x));
const ctx = vm.createContext({ URL, console });
vm.runInContext(`${read("docs/taxonomy.js")}\n${read("docs/palace/palace-data.js")}\n;globalThis.TAXONOMY = TAXONOMY; globalThis.PalaceData = PalaceData;`, ctx);
const { PalaceData: D } = ctx;
const TAXONOMY = plain(ctx.TAXONOMY);
const L = await import(`data:text/javascript;base64,${Buffer.from(read("docs/palace/atlas-layout.js")).toString("base64")}`);
const { MAP, computeLayout, tourPlan, readingTrail, boundary, BOUND_MAX, BOUND_MIN, MARKER_IN, TOUR_BEATS } = L;

const DAY = 86_400_000;
const sum = (xs) => xs.reduce((a, b) => a + b, 0);

/* ── The demo library ───────────────────────────────────────────────────── */
const demo = plain(D.demoAtlas(ctx.TAXONOMY));
assert.equal(demo.demo, true);
assert.equal(demo.label, "Demo library", "the demo library says so in the UI");
assert.equal(demo.total, 149);
assert.equal(demo.items.length, demo.total);
assert.equal(sum(demo.regions.map((r) => r.total)), demo.total, "region totals add up to the library");
assert.deepEqual(demo.regions.map((r) => r.id), ["ai", "recipes", "fitness", "travel", "art", "coding", "business", "tech"]);
assert.equal(demo.stats.subtopics, new Set(demo.regions.flatMap((r) => r.districts.map((d) => `${r.id}/${d.name}`))).size);

const titles = new Set();
for (const region of demo.regions) {
  const topic = TAXONOMY.find((t) => t.id === region.id);
  assert.ok(topic, `${region.id} is a real topic`);
  assert.equal(region.name, topic.name);
  assert.equal(region.total, sum(region.districts.map((d) => d.total)));
  assert.equal(region.items.length, region.total);
  assert.ok(region.districts.length >= 3 && region.districts.length <= 6, `${region.name} has 3–6 districts`);
  assert.ok(Math.abs(region.share - region.total / demo.total) < 1e-9);
  for (const district of region.districts) {
    assert.ok(topic.subs.includes(district.name), `${district.name} is a ${topic.name} subtopic`);
    assert.equal(district.items.length, district.total);
    for (const item of district.items) {
      assert.ok(["x", "youtube", "reddit", "web"].includes(item.source), item.source);
      assert.ok(!titles.has(item.title), `duplicate title ${item.title}`);
      titles.add(item.title);
      assert.ok(!/@\w/.test(item.title), "no handles in demo titles");
      // Demo links are searches, never a particular person's post or profile.
      assert.match(item.url, /^https:\/\/(www\.youtube\.com\/results\?search_query=|x\.com\/search\?q=|www\.reddit\.com\/r\/\w+\/search\/\?q=|duckduckgo\.com\/\?q=)/);
      assert.equal(item.regionId, region.id);
      assert.equal(item.district, district.name);
    }
    // districts carry their items oldest first, which is the order the trail reads
    assert.ok(district.items.every((it, i, a) => !i || a[i - 1].at <= it.at), "items are chronological");
  }
}
assert.equal(new Set(demo.items.map((i) => i.source)).size, 4);

/* Colours: one per region and one per source, all from the shared palette. */
assert.ok(D.DATA_COLORS.length <= 9);
assert.equal(new Set(demo.regions.map((r) => r.color)).size, demo.regions.length, "every region has its own colour");
for (const r of demo.regions) assert.ok(D.DATA_COLORS.includes(r.color));
for (const s of demo.sources) assert.ok(D.DATA_COLORS.includes(s.color));

/* ── The demo timeline is a real, deterministic spread ──────────────────── */
assert.deepEqual(plain(D.demoRows()), plain(D.demoRows()), "the demo library is the same every run");
const months = (demo.range.end - demo.range.start) / DAY / 30.44;
assert.ok(months >= 12 && months <= 18, `demo history spans ${months.toFixed(1)} months`);
assert.equal(demo.stats.undated, 0);
assert.equal(demo.stats.dated, demo.total);
assert.ok(demo.items.every((i, k, a) => !k || a[k - 1].at <= i.at), "the library reads oldest first");
assert.equal(sum(demo.weeks.map((w) => w.count)), demo.total, "the weekly series is the whole library");
assert.ok(demo.weeks.length >= 52 && demo.weeks.length <= 80);
assert.ok(demo.weeks.every((w, i, a) => !i || w.t - a[i - 1].t === 7 * DAY), "weeks are contiguous");
for (const w of demo.weeks) {
  assert.equal(sum(Object.values(w.byRegion)), w.count);
  assert.equal(sum(Object.values(w.bySource)), w.count);
}
for (const r of demo.regions) {
  assert.equal(sum(demo.weeks.map((w) => w.byRegion[r.id] || 0)), r.total, `${r.name} adds up across weeks`);
  assert.ok(r.first >= demo.range.start && r.last <= demo.range.end);
}
for (const s of demo.sources) {
  assert.equal(s.count, demo.items.filter((i) => i.source === s.id).length);
  assert.equal(sum(demo.weeks.map((w) => w.bySource[s.id] || 0)), s.count);
}
assert.deepEqual(demo.sources.map((s) => s.count), [...demo.sources.map((s) => s.count)].sort((a, b) => b - a));
// Topics open on different days, which is what makes a "new topic" moment real.
assert.ok(new Set(demo.regions.map((r) => r.first)).size === demo.regions.length);

/* Key moments are computed, never written down. */
assert.ok(demo.moments.length >= 4 && demo.moments.length <= 6);
assert.ok(demo.moments.every((m, i, a) => !i || a[i - 1].at <= m.at), "moments are in order");
const moment = (id) => demo.moments.find((m) => m.id === id);
assert.equal(moment("first").at, demo.range.start);
assert.equal(moment("first").detail, demo.items[0].title);
assert.equal(moment("latest").at, demo.range.end);
const dayOf = (ms) => D.dayStart(ms);
const biggest = moment("biggest-day");
const dayCount = demo.items.filter((i) => dayOf(i.at) === dayOf(biggest.at)).length;
assert.equal(biggest.detail, `${dayCount} saves`);
assert.ok(demo.items.every((i) => demo.items.filter((j) => dayOf(j.at) === dayOf(i.at)).length <= dayCount), "no day beats the biggest day");
const busiest = moment("busiest-week");
assert.equal(busiest.detail, `${Math.max(...demo.weeks.map((w) => w.count))} saves`);
const newTopic = demo.moments.find((m) => m.id.startsWith("new-"));
assert.ok(newTopic, "a late-starting topic is called out");
const newRegion = demo.regions.find((r) => `new-${r.id}` === newTopic.id);
assert.equal(newTopic.at, newRegion.first);
assert.equal(newTopic.label, `New topic: ${newRegion.name}`);
assert.equal(newTopic.color, newRegion.color);

/* ── A real library: caps, overflow and derived stats ───────────────────── */
const day = (n) => new Date(Date.UTC(2026, 0, 1) + n * DAY).toISOString();
const rows = [];
for (let t = 0; t < 12; t++) {
  for (let i = 0; i < 12 - t; i++) {
    rows.push({ id: `${t}-${i}`, url: `https://example.com/${t}/${i}`, title: `Topic ${t} item ${i}`, platform: "web", category_id: TAXONOMY[t].id, subcategory: `Sub ${i % 8}`, saved_at: day(t * 9 + i) });
  }
}
rows.push({ id: "gone", url: "https://example.com/gone", category_id: TAXONOMY[0].id, deleted_at: day(2) }, { id: "no-url", url: "" });
const big = plain(D.buildAtlas(rows, { taxonomy: ctx.TAXONOMY }));
assert.equal(big.total, 78);
assert.equal(big.label, "My library");
assert.equal(big.demo, false);
assert.equal(big.regions.length, 9, "nine regions at most");
assert.equal(big.regions.at(-1).name, "More topics");
assert.equal(big.regions.at(-1).total, 4 + 3 + 2 + 1);
assert.equal(sum(big.regions.map((r) => r.total)), big.total);
for (const region of big.regions) {
  assert.ok(region.districts.length <= 6, `${region.name} has ${region.districts.length} districts`);
  assert.equal(sum(region.districts.map((d) => d.total)), region.total);
}
assert.equal(big.regions[0].districts.at(-1).name, "Everything else");
assert.deepEqual(big.regions.at(-1).districts.map((d) => d.name).sort(), [TAXONOMY[8].name, TAXONOMY[9].name, TAXONOMY[10].name, TAXONOMY[11].name].sort());
assert.equal(big.stats.topRegion.id, big.regions[0].id);
assert.equal(big.stats.topSource.count, big.total);
assert.equal(big.range.start, Math.min(...big.items.map((i) => i.at)));
assert.equal(big.range.end, Math.max(...big.items.map((i) => i.at)));

const custom = plain(D.buildAtlas([
  { id: "a", url: "https://x.com/someone/status/1", platform: "x", category_id: "custom.home-lab", subcategory: "Racks", saved_at: day(3) },
  { id: "b", url: "https://www.reddit.com/r/selfhosted/comments/abc", platform: "web", category_id: "custom.home-lab", subcategory: " ", saved_at: day(2) },
  { id: "c", url: "https://youtu.be/xyz", platform: "web", category_id: null, duration_seconds: 754, saved_at: day(1) },
  { id: "d", url: "https://example.org/a", platform: "web", category_id: "custom.old-stuff", title: "", saved_at: day(1) },
], { taxonomy: ctx.TAXONOMY, customTopics: [{ id: "custom.home-lab", name: "Home lab", hue: 200 }] }));
assert.deepEqual(custom.regions.map((r) => r.name), ["Home lab", "Old stuff", "Unfiled"]);
assert.deepEqual(custom.regions[0].districts.map((d) => d.name).sort(), ["General", "Racks"]);
const item = (id) => custom.items.find((i) => i.id === id);
assert.equal(item("b").source, "reddit");
assert.equal(item("b").meta, "r/selfhosted");
assert.equal(item("c").source, "youtube");
assert.equal(item("c").meta, "12:34");
assert.equal(custom.regions[2].districts[0].name, "YouTube");
assert.equal(item("d").title, "Saved from example.org");

/* ── A library with no timestamps says so, it doesn't invent one ────────── */
const undated = plain(D.buildAtlas([
  { id: "u1", url: "https://example.com/1", title: "One", category_id: TAXONOMY[0].id },
  { id: "u2", url: "https://example.com/2", title: "Two", category_id: TAXONOMY[0].id, saved_at: "not a date" },
], { taxonomy: ctx.TAXONOMY }));
assert.equal(undated.total, 2);
assert.equal(undated.range, null, "no dates means no range");
assert.deepEqual(undated.weeks, []);
assert.deepEqual(undated.moments, []);
assert.equal(undated.stats.undated, 2);
assert.equal(undated.stats.dated, 0);
assert.equal(undated.stats.last30, 0);
assert.ok(undated.items.every((i) => i.at === null));

/* ── The map: packing, containment, determinism ─────────────────────────── */
const fake = (regions, districts, items) => plain(D.buildAtlas(
  Array.from({ length: regions * districts * items }, (_, n) => {
    const r = Math.floor(n / (districts * items));
    const d = Math.floor(n / items) % districts;
    return { id: `f${n}`, url: `https://example.com/${n}`, title: `Item ${n}`, platform: "web", category_id: TAXONOMY[r].id, subcategory: `Sub ${d}`, saved_at: day(n % 400) };
  }), { taxonomy: ctx.TAXONOMY }));

const models = { demo, big, custom, wide: fake(9, 6, 7), tiny: fake(1, 1, 1), slim: fake(3, 2, 2) };
for (const [name, model] of Object.entries(models)) {
  const layout = computeLayout(model);
  assert.equal(layout.regions.length, model.regions.length, `${name}: one region per topic`);
  assert.equal(layout.markerCount, model.total, `${name}: one marker per bookmark`);
  assert.deepEqual(plain(computeLayout(model).regions.map((r) => [r.x, r.z, r.r])),
    plain(layout.regions.map((r) => [r.x, r.z, r.r])), `${name}: the map is deterministic`);

  for (let i = 0; i < layout.regions.length; i++) {
    const A = layout.regions[i];
    assert.ok(A.r > 0 && A.r <= MAP.R_MAX + 1e-6, `${name}: ${A.id} radius in range`);
    assert.ok(Math.hypot(A.x, A.z) + A.rMax <= MAP.OUTER + 1e-6, `${name}: ${A.id} stays on the map`);
    // bigger topics get bigger regions
    for (const B of layout.regions) if (B.total > A.total) assert.ok(B.r >= A.r - 1e-9, `${name}: ${B.id} should not be smaller than ${A.id}`);
    for (let j = i + 1; j < layout.regions.length; j++) {
      const B = layout.regions[j];
      const gap = Math.hypot(A.x - B.x, A.z - B.z) - A.rMax - B.rMax;
      assert.ok(gap >= -1e-6, `${name}: ${A.id} and ${B.id} overlap by ${(-gap).toFixed(2)}`);
    }
    // the outline never leaves the circle the packing reserved for it
    for (const [bx, bz] of A.boundary) {
      const d = Math.hypot(bx - A.x, bz - A.z);
      assert.ok(d <= A.r * BOUND_MAX + 1e-6 && d >= A.r * BOUND_MIN - 1e-6, `${name}: ${A.id} outline out of bounds`);
    }
    for (let a = 0; a < A.districts.length; a++) {
      const d1 = A.districts[a];
      assert.ok(Math.hypot(d1.x - A.x, d1.z - A.z) + d1.rMax <= A.r * BOUND_MIN + 1e-6,
        `${name}: district ${d1.name} pokes out of ${A.id}`);
      for (let b = a + 1; b < A.districts.length; b++) {
        const d2 = A.districts[b];
        const gap = Math.hypot(d1.x - d2.x, d1.z - d2.z) - d1.rMax - d2.rMax;
        assert.ok(gap >= -1e-6, `${name}: districts ${d1.name}/${d2.name} overlap in ${A.id}`);
      }
      for (const m of d1.markers) {
        assert.ok(Math.hypot(m.x - d1.x, m.z - d1.z) <= d1.r * MARKER_IN + 1e-6, `${name}: marker ${m.id} outside district ${d1.name}`);
        assert.ok(Math.hypot(m.x - A.x, m.z - A.z) <= A.r * BOUND_MIN - 1e-6, `${name}: marker ${m.id} outside region ${A.id}`);
        assert.equal(m.regionId, A.id);
        assert.ok(m.height > 0);
      }
    }
    assert.equal(A.markers.length, A.total);
    assert.equal(sum(A.districts.map((d) => d.markers.length)), A.total);
  }
  // marker height encodes recency, so the newest save is never the shortest
  const dated = layout.regions.flatMap((r) => r.markers).filter((m) => m.at != null).sort((a, b) => a.at - b.at);
  if (dated.length > 1) assert.ok(dated.at(-1).height >= dated[0].height, `${name}: newer markers stand taller`);
}

/* ── The scripted tour ──────────────────────────────────────────────────── */
const layout = computeLayout(demo);
const plan = tourPlan(demo, layout);
assert.ok(plan.duration >= 45 && plan.duration <= 60, `tour is ${plan.duration}s`);
assert.equal(plan.beats.length, TOUR_BEATS.length);
assert.equal(plan.beats[0].start, 0);
assert.equal(plan.beats.at(-1).end, plan.duration);
plan.beats.forEach((b, i) => {
  assert.ok(b.end > b.start, `${b.id} has no length`);
  if (i) assert.equal(b.start, plan.beats[i - 1].end, `${b.id} leaves a gap`);
  assert.ok(b.label && b.label.length <= 60, `${b.id} caption stays short`);
});
for (const id of ["orbit-in", "timeline", "region", "detail", "sources", "trail", "map2d", "orbit-out"]) {
  assert.ok(plan.beats.some((b) => b.id === id), `tour is missing the ${id} beat`);
}
for (const t of [0, 0.5, 7.9, 8, 23, 41, 49, plan.duration - 0.01, plan.duration, plan.duration + 5]) {
  const at = plan.at(t);
  assert.ok(at.beat, `no beat at ${t}`);
  assert.ok(at.local >= 0 && at.local <= 1, `local out of range at ${t}`);
}
assert.equal(plan.focusRegion, "recipes");
const focus = layout.regions.find((r) => r.id === plan.focusRegion);
assert.ok(focus.markers.some((m) => m.id === plan.marker), "the tour selects a marker in the region it flew to");
assert.ok(plan.trail.length >= 2 && plan.trail.length <= 8);
const trail = readingTrail(layout, { regionId: plan.focusRegion, count: 8 });
assert.deepEqual(trail.map((m) => m.id), plan.trail);
assert.ok(trail.every((m, i, a) => !i || a[i - 1].at <= m.at), "the reading trail follows save order");
assert.ok(trail.every((m) => m.regionId === plan.focusRegion));
assert.ok(readingTrail(layout, { count: 10 }).length >= 2, "there is a whole-library trail too");
assert.deepEqual(readingTrail(computeLayout(undated), { count: 8 }), [], "no dates, no trail");

/* ── Signed-in visitors: bm.session, refresh write-back, read-only loading ─ */
const NOW = 1_800_000_000_000;
const now = () => NOW;
function storage(session) {
  const m = new Map(session ? [[D.SESSION_KEY, JSON.stringify(session)]] : []);
  return { m, getItem: (k) => (m.has(k) ? m.get(k) : null), setItem: (k, v) => m.set(k, String(v)), removeItem: (k) => m.delete(k) };
}
const session = (over = {}) => ({ access_token: "A1", refresh_token: "R1", expires_at: NOW + 3_600_000, user_id: "user-1", email: "me@example.com", ...over });
function server({ refresh = 200, pages = [[]], topics = [], status = 200 } = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    calls.push({ url, method: init.method || "GET", headers: init.headers || {}, body: init.body });
    const json = (body, code = 200) => ({ ok: code < 300, status: code, json: async () => body });
    if (url.includes("/auth/v1/token")) return json({ access_token: "A2", refresh_token: "R2", expires_in: 3600, user: { id: "user-1", email: "me@example.com" } }, refresh);
    if (status !== 200) return json({}, status);
    if (url.includes("/rest/v1/bookmarks")) return json(pages[Number(/offset=(\d+)/.exec(url)[1]) / 1000] || []);
    if (url.includes("/rest/v1/custom_topics")) return json(topics);
    return json({}, 404);
  };
  return { fetch, calls };
}
assert.equal(D.SESSION_KEY, "bm.session");
assert.equal(D.readSession(storage(null)), null);
assert.equal(D.readSession({ getItem: () => "{not json" }), null);
assert.equal(D.readSession(storage({ access_token: "A1" })), null);
{
  const s = storage(session()), api = server();
  assert.equal((await D.validSession({ storage: s, fetch: api.fetch, now })).access_token, "A1");
  assert.equal(api.calls.length, 0, "a fresh session is used as-is");
}
{
  const s = storage(session({ expires_at: NOW + 30_000 })), api = server();
  const next = await D.validSession({ storage: s, fetch: api.fetch, now });
  assert.equal(api.calls[0].method, "POST");
  assert.equal(JSON.parse(api.calls[0].body).refresh_token, "R1");
  const stored = JSON.parse(s.getItem("bm.session"));
  assert.deepEqual(Object.keys(stored).sort(), ["access_token", "email", "expires_at", "refresh_token", "user_id"]);
  assert.deepEqual([stored.access_token, stored.refresh_token, stored.expires_at, stored.user_id], ["A2", "R2", NOW + 3_600_000, "user-1"]);
  assert.equal(next.access_token, "A2");
}
{
  const s = storage(session({ expires_at: NOW - 1 })), api = server({ refresh: 400 });
  assert.equal(await D.validSession({ storage: s, fetch: api.fetch, now }), null);
  assert.equal(JSON.parse(s.getItem("bm.session")).refresh_token, "R1", "a failed refresh never signs the app out");
}
{
  const s = storage(session({ expires_at: NOW - 1 }));
  const api = server({ refresh: 400 });
  const raced = { ...api, fetch: async (url, init) => { s.setItem("bm.session", JSON.stringify(session({ access_token: "A3", refresh_token: "R3" }))); return api.fetch(url, init); } };
  assert.equal((await D.validSession({ storage: s, fetch: raced.fetch, now })).access_token, "A3", "another tab's refresh wins");
}
{
  const page0 = Array.from({ length: 1000 }, (_, i) => ({ id: `p${i}`, url: `https://example.com/${i}` }));
  const api = server({ pages: [page0, [{ id: "last", url: "https://example.com/last" }]], topics: [{ id: "custom.a", name: "A" }] });
  const out = plain(await D.loadOwnLibrary({ storage: storage(session()), fetch: api.fetch, now }));
  assert.equal(out.rows.length, 1001);
  assert.equal(out.customTopics[0].name, "A");
  assert.ok(api.calls.every((c) => c.method === "GET"), "loading never writes");
  assert.ok(api.calls.every((c) => c.headers.Authorization === "Bearer A1"));
  const books = api.calls.filter((c) => c.url.includes("/rest/v1/bookmarks"));
  assert.equal(books.length, 2);
  assert.ok(books.every((c) => c.url.includes("owner_id=eq.user-1") && c.url.includes("deleted_at=is.null")));
  assert.match(books[1].url, /offset=1000/);
  assert.match(D.bookmarksPath("a b", 2), /owner_id=eq\.a%20b&deleted_at=is\.null&.*limit=1000&offset=2000$/);
}
await assert.rejects(D.loadOwnLibrary({ storage: storage(null), fetch: server().fetch, now }), (e) => e.status === 401);
await assert.rejects(D.loadOwnLibrary({ storage: storage(session()), fetch: server({ status: 401 }).fetch, now }), (e) => e.status === 401);

/* The whole page is static, and the only write anywhere is the refresh
   write-back above. Nothing in docs/palace/ may POST, PATCH or DELETE. */
const sources = fs.readdirSync("docs/palace").filter((f) => f.endsWith(".js")).map((f) => [f, read(`docs/palace/${f}`)]);
for (const [file, body] of sources) {
  const methods = [...body.matchAll(/method:\s*"(\w+)"/g)].map((m) => m[1]);
  for (const method of methods) {
    assert.ok(method === "GET" || (file === "palace-data.js" && method === "POST"),
      `${file} uses ${method} — the atlas is read-only`);
  }
  if (file !== "palace-data.js") assert.ok(!/\bfetch\s*\(/.test(body) || file === "atlas.js", `${file} talks to the network directly`);
  assert.ok(!/rest\/v1\/[a-z_]+\?[^"'`]*\b(upsert|on_conflict)/.test(body), `${file} looks like it writes`);
}
/* The demo library has to announce itself wherever a visitor can see it. */
assert.match(read("docs/palace/index.html"), /Demo library/);
assert.match(read("docs/palace/atlas-ui.js"), /Demo library/);

console.log("Library Atlas: all checks passed");
console.log(`  demo: ${demo.total} bookmarks, ${demo.regions.length} regions, ${demo.stats.subtopics} districts,`
  + ` ${demo.weeks.length} weeks (${months.toFixed(1)} months), ${demo.moments.length} key moments`);
console.log(`  map: ${layout.markerCount} markers packed inside ${layout.regions.length} regions, tour ${plan.duration}s in ${plan.beats.length} beats`);
