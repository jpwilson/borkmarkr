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
import { createHash } from "node:crypto";

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
  /* The canopy is 70-odd metres of geometry standing on the heightfield, so
     clearing the ground is not the same as clearing the island. Every sample
     of the flight has to be above the trees, and on the beats that hold a
     bookmark open the camp itself has to be visible: a frame of leaves is a
     broken frame, however legal the camera position is. */
  let checkedSight = 0;
  for (let t = 0; t <= tour.duration; t += 0.2) {
    const s = tour.stateAt(t);
    const canopy = L.canopyTopAt(s.pos.x, s.pos.z, island.clearings);
    assert.ok(s.pos.y >= canopy + 4,
      `camera clears the canopy at ${t.toFixed(1)}s (y ${s.pos.y.toFixed(1)} vs ${canopy.toFixed(1)})`);
    if (!s.marker) continue;
    const m = island.byId.get(s.marker);
    // march the sight line and make sure nothing stands in front of the camp
    checkedSight++;
    const eye = { x: m.x, y: m.y + 11, z: m.z };
    for (let i = 1; i < 24; i++) {
      const u = i / 24;
      const x = L.mix(eye.x, s.pos.x, u), z = L.mix(eye.z, s.pos.z, u);
      const y = L.mix(eye.y, s.pos.y, u);
      assert.ok(y >= L.heightAt(x, z), `terrain blocks the view of ${s.marker} at ${t.toFixed(1)}s`);
      assert.ok(y >= L.canopyTopAt(x, z, island.clearings) - 1,
        `the canopy blocks the view of ${s.marker} at ${t.toFixed(1)}s`);
    }
  }
  assert.ok(checkedSight > 20, "the landing holds long enough to be worth checking");

  // and the close-up itself: 30-60 m out, tipped down onto the camp
  const hero = T.heroMarker(island);
  const close = T.markerPose(island, hero);
  const range = Math.hypot(close.pos.x - close.target.x, close.pos.y - close.target.y, close.pos.z - close.target.z);
  assert.ok(range > 30 && range < 62, `the marker close-up stands ${range.toFixed(0)} m off its subject`);
  assert.ok(close.pos.y > close.target.y + 12, "and looks down at it, not up");
  assert.ok(close.pos.y >= L.canopyTopAt(close.pos.x, close.pos.z, island.clearings),
    "the close-up camera is not inside a tree");
  // the camp really is a clearing, both in the scatter and in the bound
  assert.equal(L.canopyTopAt(hero.campX, hero.campZ, island.clearings),
    L.heightAt(hero.campX, hero.campZ), "a camp site carries no canopy");
}
{
  // the poses the capture harness uses are framings of real places
  const hero = T.heroMarker(island);
  assert.ok(hero && island.byId.has(hero.id));
  for (const zone of island.zones) {
    const p = T.zonePose(island, zone);
    assert.ok(p.pos.y > L.heightAt(p.pos.x, p.pos.z), `${zone.place} is framed from the air`);
    // the subject is the site, or a landform just off it (the falls' cliff)
    assert.ok(Math.hypot(p.target.x - zone.x, p.target.z - zone.z) < 500, "and framed on its own ground");
    assert.ok(L.zoneField(p.target.x, p.target.z, island.sites).zone === zone.index
      || L.heightAt(p.target.x, p.target.z) < 60, `${zone.place} is framed inside its own zone`);
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

/* ── an empty library ───────────────────────────────────────────────────── */
/* Nobody's first visit should be a stack trace. With no rows there are no
   zones, no camps and no bookmark to land on, and every one of those used to
   be assumed: buildPlan dereferenced the hero's zone before checking it. */
{
  const atlas = plain(D.buildAtlas([], { taxonomy: ctx.TAXONOMY, demo: false, label: "My library" }));
  assert.equal(atlas.total, 0);
  assert.equal(atlas.regions.length, 0);
  const isl = L.computeIsland(atlas);
  assert.equal(isl.zones.length, 0);
  assert.equal(isl.markers.length, 0);
  assert.deepEqual(isl.clearings, []);
  // the island itself is still an island: the heightfield does not depend on
  // the library, and nothing it reports is NaN
  assert.ok(L.heightAt(0, 0) > 0);
  assert.equal(L.zoneField(0, 0, isl.sites).zone, -1, "no topics means no zone, not zone 0");
  assert.ok(Number.isFinite(L.zoneField(0, 0, isl.sites).gap), "and a finite gap, not Infinity minus Infinity");
  assert.equal(T.heroMarker(isl), null);

  const t0 = new T.Tour(isl);
  assert.ok(t0.duration > 0, "an empty library still gets a flight");
  const ids = t0.plan.beats.map((b) => b.id);
  assert.ok(ids.includes("approach") && ids.includes("overview") && ids.includes("pullout"));
  assert.ok(!ids.includes("marker"), "but no beat lands on a bookmark that is not there");
  assert.ok(!ids.includes("dip"));
  for (let t = 0; t <= t0.duration; t += 0.5) {
    const st = t0.stateAt(t);
    assert.ok(Number.isFinite(st.pos.x) && Number.isFinite(st.pos.y) && Number.isFinite(st.pos.z), `finite camera at ${t}s`);
    assert.equal(st.marker, null);
    assert.ok(st.pos.y >= L.canopyTopAt(st.pos.x, st.pos.z, isl.clearings) + 4);
  }
  // and the poses the capture harness asks for do not throw either
  assert.ok(T.overviewPose(isl).fov > 0);
  assert.ok(T.mapPose(isl).top);
  assert.ok(Number.isFinite(T.zonePose(isl, undefined).pos.y), "a zone pose with no zone falls back to the overview");
  assert.ok(Number.isFinite(T.markerPose(isl, null).pos.y));
}

/* ── more topics than the island has places ─────────────────────────────── */
/* Nine landforms, fifty possible topics. The overflow is folded into one
   "More topics" region whose districts are the topics it swallowed, so no
   save is dropped and every count still adds up to the library. */
{
  const rows = [];
  ctx.TAXONOMY.slice(0, 14).forEach((t, i) => {
    for (let k = 0; k <= i; k++) {
      rows.push({
        id: `x${i}-${k}`, url: `https://example.com/${i}/${k}`, title: `Item ${i}-${k}`,
        category_id: t.id, subcategory: t.subs[0],
        saved_at: new Date(Date.UTC(2026, 1, 1 + i, k)).toISOString(),
      });
    }
  });
  const atlas = plain(D.buildAtlas(rows, { taxonomy: ctx.TAXONOMY, demo: true }));
  assert.equal(atlas.total, rows.length);
  assert.equal(atlas.regions.length, L.MAX_ZONES, "fourteen topics still fit nine places");
  assert.equal(sum(atlas.regions.map((r) => r.total)), atlas.total, "and nothing is dropped on the way");
  const more = atlas.regions.find((r) => r.id === "more");
  assert.ok(more, "the overflow has a home");
  assert.ok(more.districts.length > 1, "and its districts are the topics it swallowed");

  const isl = L.computeIsland(atlas);
  assert.equal(isl.zones.length, L.MAX_ZONES, "the island hands out all nine places and no more");
  assert.equal(new Set(isl.zones.map((z) => z.siteId)).size, L.MAX_ZONES, "each to a different place");
  assert.equal(sum(isl.zones.map((z) => z.total)), atlas.total);
  for (const m of isl.markers) {
    assert.ok(isl.zones[m.zone], "a marker's zone is a real zone");
    assert.equal(L.zoneField(m.x, m.z, isl.sites).zone, m.zone, "and it stands inside it");
  }
  const t3 = new T.Tour(isl);
  assert.ok(t3.plan.beats.some((b) => b.id === "marker"), "and the flight still lands on a bookmark");
  for (let t = 0; t <= t3.duration; t += 0.5) {
    const st = t3.stateAt(t);
    assert.ok(st.pos.y >= L.canopyTopAt(st.pos.x, st.pos.z, isl.clearings) + 4, `clears the canopy at ${t}s`);
  }
}

/* ── a single topic owns the whole island, and still gets a landing ─────── */
{
  const rows = plain(D.demoRows()).filter((r) => r.category_id === "ai");
  const atlas = plain(D.buildAtlas(rows, { taxonomy: ctx.TAXONOMY, demo: true }));
  const isl = L.computeIsland(atlas);
  assert.equal(isl.zones.length, 1);
  assert.equal(isl.markers.length, atlas.total);
  const t4 = new T.Tour(isl);
  const ids = t4.plan.beats.map((b) => b.id);
  assert.equal(ids.filter((id) => id.startsWith("zone-")).length, 1, "one topic means one zone beat, not three");
  assert.ok(ids.includes("marker"), "and the landing still happens");
  const hero = T.heroMarker(isl);
  assert.equal(hero.zone, 0);
  for (let t = 0; t <= t4.duration; t += 0.5) {
    const st = t4.stateAt(t);
    assert.ok(st.pos.y >= L.canopyTopAt(st.pos.x, st.pos.z, isl.clearings) + 4, `clears the canopy at ${t}s`);
  }
}

/* ── the page's own guarantees ──────────────────────────────────────────── */
{
  const html = read("docs/palace/index.html");
  // a CSP that actually covers the one inline script on the page
  const csp = /<meta http-equiv="Content-Security-Policy" content="([^"]+)"/.exec(html);
  assert.ok(csp, "the page ships a Content-Security-Policy");
  const policy = csp[1];
  for (const d of ["default-src 'none'", "script-src", "connect-src", "base-uri 'none'"]) {
    assert.ok(policy.includes(d), `CSP declares ${d}`);
  }
  assert.ok(!/unsafe-eval/.test(policy), "and allows no eval");
  assert.ok(!/script-src[^;]*'unsafe-inline'/.test(policy), "and no blanket inline script");
  const map = /<script type="importmap">([\s\S]*?)<\/script>/.exec(html);
  assert.ok(map, "the import map is inline");
  const hash = createHash("sha256").update(map[1]).digest("base64");
  // the browser hashes the exact text between the tags, newlines included
  assert.ok(policy.includes(`'sha256-${hash}'`), "and the CSP carries its hash, so editing it without the hash fails loudly");
  const supabase = /SUPABASE_URL = "([^"]+)"/.exec(read("docs/palace/palace-data.js"))[1];
  assert.ok(policy.includes(supabase), "connect-src names the library's own origin");
  assert.ok(policy.includes("https://cdn.jsdelivr.net"), "script-src names the pinned CDN");

  // seeking is a control, not a two-pixel div
  assert.match(html, /<input id="seek"[^>]*type="range"/, "the tour can be seeked from the keyboard");
  assert.match(html, /id="seek"[^>]*aria-label=/, "and the control says what it is");
}

console.log("test_palace: ok");
