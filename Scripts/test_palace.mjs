#!/usr/bin/env node
/**
 * Tests for Library Island (docs/palace/).
 *
 *     node Scripts/test_palace.mjs
 *
 * palace-data.js is loaded into a bare vm context after docs/taxonomy.js,
 * exactly as the page loads them; island-layout.js and island-tour.js are
 * pure numbers, so nothing here needs a GPU or a DOM. What's checked is what
 * the renderer takes on trust: every count on screen comes out of the rows,
 * every topic owns exactly one zone, the zones tile the island without
 * overlapping, every bookmark's marker stands inside its own zone and above
 * the waterline, the scripted flight is a pure function of t that visits
 * every beat, and a signed-in visitor's library is read with GETs only.
 */
import fs from "node:fs";
import vm from "node:vm";
import assert from "node:assert/strict";

const read = (p) => fs.readFileSync(p, "utf8");
const plain = (x) => JSON.parse(JSON.stringify(x));
const sum = (xs) => xs.reduce((a, b) => a + b, 0);

const ctx = vm.createContext({ URL, console });
vm.runInContext(`${read("docs/taxonomy.js")}\n${read("docs/palace/palace-data.js")}\n;globalThis.TAXONOMY = TAXONOMY; globalThis.PalaceData = PalaceData;`, ctx);
const { PalaceData: D } = ctx;
const TAXONOMY = plain(ctx.TAXONOMY);

/* The two world modules import each other by relative path, which a data:
   URL cannot resolve — so the layout is inlined into the tour's import. */
const b64 = (src) => `data:text/javascript;base64,${Buffer.from(src).toString("base64")}`;
const layoutSrc = read("docs/palace/island-layout.js");
const layoutUrl = b64(layoutSrc);
const L = await import(layoutUrl);
const T = await import(b64(read("docs/palace/island-tour.js").replace('"./island-layout.js"', JSON.stringify(layoutUrl))));

/* ── the demo library ───────────────────────────────────────────────────── */
const demo = plain(D.demoAtlas(ctx.TAXONOMY));
assert.equal(demo.demo, true);
assert.equal(demo.label, "Demo library", "the demo library says so in the UI");
assert.equal(demo.total, 149);
assert.equal(demo.items.length, demo.total);
assert.equal(sum(demo.regions.map((r) => r.total)), demo.total, "region totals add up to the library");
assert.deepEqual(demo.regions.map((r) => r.id), ["ai", "recipes", "fitness", "travel", "art", "coding", "business", "tech"]);
for (const region of demo.regions) {
  const topic = TAXONOMY.find((t) => t.id === region.id);
  assert.ok(topic, `${region.id} is a real topic`);
  assert.equal(region.name, topic.name);
  assert.equal(region.total, sum(region.districts.map((d) => d.total)));
  for (const district of region.districts) {
    assert.ok(topic.subs.includes(district.name), `${district.name} is a ${topic.name} subtopic`);
    for (const item of district.items) assert.ok(item.at > 0 && item.at <= Date.parse("2026-10-18T12:00:00Z"));
  }
}

/* ── one zone per topic, in the order the topics rank ───────────────────── */
const island = L.computeIsland(demo);
assert.equal(island.zones.length, demo.regions.length, "every topic gets a zone");
assert.deepEqual(island.zones.map((z) => z.id), demo.regions.map((r) => r.id));
assert.deepEqual(island.zones.map((z) => z.siteId), L.SITES.slice(0, demo.regions.length).map((s) => s.id),
  "topics claim the island's places in rank order, so the biggest topic is the volcano");
assert.equal(new Set(island.zones.map((z) => z.siteId)).size, island.zones.length, "no two topics share a place");
for (const zone of island.zones) {
  const region = demo.regions.find((r) => r.id === zone.id);
  assert.equal(zone.total, region.total, "the zone count is the topic count, not an invention");
  assert.equal(zone.name, region.name);
  assert.ok(zone.biome && zone.place && zone.note, "a zone names its biome for the legend");
}
assert.equal(sum(island.zones.map((z) => z.total)), demo.total);

/* Bigger topics get more island, but never a distorted amount of it. */
const weights = island.zones.map((z) => z.weight);
assert.ok(Math.min(...weights) >= 0.86 && Math.max(...weights) <= 1.2);
const ai = island.zones.find((z) => z.id === "ai"), business = island.zones.find((z) => z.id === "business");
assert.ok(ai.weight > business.weight, "24 saves claim more ground than 15");

/* ── the zones tile the island: no gaps, no overlaps ────────────────────── */
{
  const area = new Map(island.zones.map((z) => [z.index, 0]));
  let land = 0, unclaimed = 0;
  for (let x = -L.ISLAND_R - 100; x <= L.ISLAND_R + 100; x += 18) {
    for (let z = -L.ISLAND_R - 100; z <= L.ISLAND_R + 100; z += 18) {
      if (L.heightAt(x, z) <= 0) continue;
      land++;
      // the field answers with exactly one zone for any point, by construction
      const f = L.zoneField(x, z, island.sites);
      if (!area.has(f.zone)) { unclaimed++; continue; }
      assert.ok(f.gap >= 0, "the nearest site is the nearest site");
      area.set(f.zone, area.get(f.zone) + 1);
    }
  }
  assert.ok(land > 8000, `the island has land (${land} samples)`);
  assert.equal(unclaimed, 0, "every square of land belongs to a zone");
  assert.equal(sum([...area.values()]), land, "and to exactly one");
  for (const [index, n] of area) assert.ok(n > land * 0.02, `zone ${index} is a real place, not a sliver`);
  // the ranking of zone areas follows the ranking of saves
  const first = area.get(0), last = area.get(island.zones.length - 1);
  assert.ok(first > 0 && last > 0);
}

/* ── one marker per bookmark, in its own zone, above the waterline ──────── */
assert.equal(island.markers.length, demo.total, "every bookmark is a marker");
assert.equal(new Set(island.markers.map((m) => m.id)).size, island.markers.length, "no bookmark twice");
const KINDS = new Set(["camp", "totem", "banner", "torch", "cairn"]);
for (const m of island.markers) {
  const zone = island.zones[m.zone];
  assert.ok(zone, "a marker knows its zone");
  assert.equal(L.zoneField(m.x, m.z, island.sites).zone, m.zone, `${m.id} stands inside ${zone.name}`);
  assert.ok(L.heightAt(m.x, m.z) > 0, `${m.id} stands above the sea`);
  assert.ok(Math.abs(m.y - L.heightAt(m.x, m.z)) < 1e-6, "a marker stands on the ground, not above it");
  assert.ok(KINDS.has(m.kind), m.kind);
  assert.ok(zone.districts.some((d) => d.name === m.district), "its camp is its subtopic's camp");
  assert.equal(m.item.regionId, zone.id);
}
for (const zone of island.zones) {
  assert.equal(zone.markers.length, Math.min(zone.total, L.MARKER_CAP));
  const camps = new Set(zone.markers.map((m) => m.camp));
  assert.equal(camps.size, Math.min(zone.districts.length, zone.markers.length), "one camp per subtopic");
}

/* A big library caps the markers it draws without lying about the count. */
{
  const rows = [];
  for (let i = 0; i < 900; i++) {
    rows.push({ id: `x-${i}`, title: `Saved item ${i}`, url: `https://example.com/${i}`,
      platform: "web", category_id: "ai", subcategory: "Tools",
      saved_at: new Date(Date.UTC(2026, 1, 1 + (i % 300))).toISOString(), deleted_at: null });
  }
  const big = plain(D.buildAtlas(rows, { taxonomy: ctx.TAXONOMY, demo: true }));
  const bigIsland = L.computeIsland(big);
  assert.equal(bigIsland.zones[0].total, 900, "the count stays honest");
  assert.equal(bigIsland.zones[0].markers.length, L.MARKER_CAP, "the drawing is capped");
}

/* ── determinism: the same library builds the same island ──────────────── */
{
  const a = L.computeIsland(plain(D.demoAtlas(ctx.TAXONOMY)));
  const b = L.computeIsland(plain(D.demoAtlas(ctx.TAXONOMY)));
  assert.deepEqual(a.zones.map((z) => [z.id, z.siteId, z.biome, Math.round(z.weight * 1e6)]),
    b.zones.map((z) => [z.id, z.siteId, z.biome, Math.round(z.weight * 1e6)]), "biomes are assigned deterministically");
  const pos = (isl) => isl.markers.map((m) => [m.id, Math.round(m.x * 1e3), Math.round(m.z * 1e3), m.kind]);
  assert.deepEqual(pos(a), pos(b), "markers land in the same places every build");
}

/* ── the scripted flight ────────────────────────────────────────────────── */
const tour = new T.Tour(island);
assert.ok(tour.duration >= 48 && tour.duration <= 56, `tour is ${tour.duration}s`);
{
  const ids = tour.plan.beats.map((b) => b.id);
  assert.ok(ids.includes("approach"), "it comes in off the sea");
  assert.ok(ids.includes("overview"), "it shows the whole island");
  assert.ok(ids.filter((id) => id.startsWith("zone-")).length >= 3, "it visits at least three zones");
  assert.ok(ids.includes("marker"), "it lands on a bookmark");
  assert.ok(ids.includes("pullout"), "and pulls back out");
  // the beats tile the running time, in order, with no gap
  let t = 0;
  for (const beat of tour.plan.beats) {
    assert.equal(beat.start, t);
    assert.ok(beat.length > 0);
    t = beat.end;
  }
  assert.equal(t, tour.duration);
}
{
  // renderAt(t) must not depend on what was asked for before it
  const forward = [];
  const steps = Math.floor(tour.duration / 0.37);
  for (let i = 0; i <= steps; i++) forward.push(plain(tour.stateAt(i * 0.37)));
  const fresh = new T.Tour(L.computeIsland(demo));
  const scrambled = new Map();
  const order = forward.map((_, i) => i).sort((a, b) => ((a * 7919) % 101) - ((b * 7919) % 101));
  for (const i of order) scrambled.set(i, plain(fresh.stateAt(i * 0.37)));
  forward.forEach((state, i) => assert.deepEqual(scrambled.get(i), state, `frame at ${(i * 0.37).toFixed(2)}s is not path-dependent`));
}
{
  // the flight never goes through the island, and the card opens on the way down
  let sawCard = false;
  const zonesSeen = new Set();
  for (let t = 0; t <= tour.duration; t += 0.25) {
    const s = tour.stateAt(t);
    assert.ok(s.pos.y >= L.heightAt(s.pos.x, s.pos.z) + 15, `camera clears the ground at ${t}s`);
    assert.ok(s.fov > 20 && s.fov < 70);
    if (s.marker) {
      sawCard = true;
      assert.ok(island.byId.has(s.marker), "the open card is a real bookmark");
    }
    if (s.zone != null) zonesSeen.add(s.zone);
  }
  assert.ok(sawCard, "a bookmark card opens during the flight");
  assert.ok(zonesSeen.size >= 3, "and the flight holds on at least three zones");
  assert.equal(tour.stateAt(-5).t, 0);
  assert.equal(tour.stateAt(1e6).t, tour.duration);
}
{
  // the poses the capture harness uses are framings of real places
  const hero = T.heroMarker(island);
  assert.ok(hero && island.byId.has(hero.id));
  for (const zone of island.zones) {
    const p = T.zonePose(island, zone);
    assert.ok(p.pos.y > L.heightAt(p.pos.x, p.pos.z), `${zone.place} is framed from the air`);
    assert.ok(Math.hypot(p.target.x - zone.x, p.target.z - zone.z) < 1, "and framed on its own site");
  }
  const over = T.overviewPose(island);
  assert.ok(Math.hypot(over.pos.x, over.pos.z) > L.ISLAND_R * 2, "the overview stands off the island");
  assert.ok(T.approachPose(island, 0).pos.y < 120, "the approach comes in low");
  assert.ok(T.mapPose(island).top === true, "the map looks straight down");
}

/* ── the page reads, and never writes, a visitor's library ─────────────── */
{
  const src = read("docs/palace/palace-data.js");
  const posts = src.match(/method:\s*"POST"/g) || [];
  assert.equal(posts.length, 1, "exactly one POST exists");
  const refresh = src.slice(src.indexOf("async function validSession"), src.indexOf("async function getJSON"));
  assert.ok(refresh.includes('method: "POST"'), "and it is the single-use token refresh");
  assert.ok(!/method:\s*"(PUT|PATCH|DELETE)"/.test(src), "nothing is written back");
  assert.match(D.bookmarksPath("me", 0), /^\/rest\/v1\/bookmarks\?select=/);
  assert.ok(D.bookmarksPath("me", 1).includes("offset=1000"));

  // one setItem, and only to hand the app its refreshed session
  const sets = src.match(/storage\.setItem/g) || [];
  assert.equal(sets.length, 1);
}
{
  // no bookmark string is ever parsed as markup
  for (const file of fs.readdirSync("docs/palace").filter((f) => f.endsWith(".js"))) {
    const src = read(`docs/palace/${file}`);
    assert.ok(!/\.innerHTML\s*=/.test(src), `${file} sets innerHTML`);
    assert.ok(!/insertAdjacentHTML/.test(src), `${file} uses insertAdjacentHTML`);
  }
  const ui = read("docs/palace/island-ui.js");
  assert.ok(ui.includes("textContent"), "the shell writes text, not markup");
}
{
  // a hostile row cannot produce a clickable link or markup
  const stress = plain(D.stressAtlas(ctx.TAXONOMY));
  const nasty = stress.items.find((i) => i.title.includes("<img"));
  assert.ok(nasty, "the stress library keeps its hostile title");
  assert.equal(nasty.title, '<img src=x onerror="alert(1)">', "and keeps it as text");
  assert.ok(stress.items.every((i) => !i.url || /^https?:\/\//.test(i.url)), "every link is http(s) or nothing");
  const stressIsland = L.computeIsland(stress);
  assert.equal(stressIsland.markers.length, Math.min(stress.total, stressIsland.zones.length * L.MARKER_CAP));
  for (const m of stressIsland.markers) assert.ok(L.heightAt(m.x, m.z) > 0);
}

/* ── a library with no dates still builds an island ─────────────────────── */
{
  const rows = plain(D.demoRows()).map((r) => { const n = { ...r }; delete n.saved_at; return n; });
  const atlas = plain(D.buildAtlas(rows, { taxonomy: ctx.TAXONOMY, demo: true }));
  assert.equal(atlas.range, null, "no dates means no date range, not a made-up one");
  const isl = L.computeIsland(atlas);
  assert.equal(isl.markers.length, atlas.total);
  const t2 = new T.Tour(isl);
  assert.ok(t2.duration >= 48 && t2.duration <= 56);
}

/* ── a one-topic library is still a whole island ────────────────────────── */
{
  const rows = plain(D.demoRows()).filter((r) => r.category_id === "recipes");
  const atlas = plain(D.buildAtlas(rows, { taxonomy: ctx.TAXONOMY, demo: true }));
  const isl = L.computeIsland(atlas);
  assert.equal(isl.zones.length, 1);
  assert.equal(isl.zones[0].siteId, "volcano", "the only topic takes the volcano");
  for (let x = -600; x <= 600; x += 60) for (let z = -600; z <= 600; z += 60) {
    if (L.heightAt(x, z) <= 0) continue;
    assert.equal(L.zoneField(x, z, isl.sites).zone, 0, "and owns all of it");
  }
  assert.ok(new T.Tour(isl).plan.beats.length >= 6);
}

console.log("test_palace: ok");
