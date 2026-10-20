#!/usr/bin/env node
/**
 * Tests for the Memory Palace (docs/palace/).
 *
 *     node Scripts/test_palace.mjs
 *
 * palace-data.js is loaded into a bare vm context after docs/taxonomy.js,
 * exactly as the page loads them, and layout.js is pure numbers, so nothing
 * here needs a GPU or a DOM. What's checked is what the renderer takes on
 * trust: signs fit their walls and never overlap, cards stay inside their
 * alcoves, the tour visits every room without walking through a wall, and a
 * signed-in visitor's library is read with GETs only, under the app's
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
const { DIM, at, computeLayout, roomAt, views, tourPlan, routeBetween } =
  await import(`data:text/javascript;base64,${Buffer.from(read("docs/palace/layout.js")).toString("base64")}`);

/* ── Demo library ── */
const demo = plain(D.demoModel(ctx.TAXONOMY));
assert.equal(demo.total, 149);
assert.equal(demo.shown, 149);
assert.equal(demo.demo, true);
assert.deepEqual(demo.rooms.map((r) => r.id), ["ai", "recipes", "fitness", "travel", "art", "coding", "business", "tech"]);
const titles = new Set();
for (const room of demo.rooms) {
  const topic = TAXONOMY.find((t) => t.id === room.id);
  assert.ok(topic, `${room.id} is a real topic`);
  assert.equal(room.name, topic.name);
  assert.equal(room.hue, topic.hue);
  assert.ok(room.shelves.length >= 3 && room.shelves.length <= 5, `${room.name} has 3–5 shelves`);
  for (const shelf of room.shelves) {
    assert.ok(topic.subs.includes(shelf.name), `${shelf.name} is a ${topic.name} subtopic`);
    assert.ok(shelf.cards.length >= 3 && shelf.cards.length <= 6);
    for (const card of shelf.cards) {
      assert.ok(["x", "youtube", "reddit", "web"].includes(card.source), card.source);
      assert.ok(!titles.has(card.title), `duplicate title ${card.title}`);
      titles.add(card.title);
      assert.ok(!/@\w/.test(card.title), "no handles in demo titles");
      // Demo links are searches, never a particular person's post or profile.
      assert.match(card.url, /^https:\/\/(www\.youtube\.com\/results\?search_query=|x\.com\/search\?q=|www\.reddit\.com\/r\/\w+\/search\/\?q=|duckduckgo\.com\/\?q=)/);
    }
  }
}
assert.ok(new Set(demo.rooms.flatMap((r) => r.shelves.flatMap((s) => s.cards.map((c) => c.source)))).size === 4);

/* ── Grouping a real library ── */
const day = (d) => new Date(Date.UTC(2026, 0, d)).toISOString();
const rows = [];
for (let t = 0; t < 12; t++) for (let i = 0; i < 12 - t; i++) {
  rows.push({ id: `${t}-${i}`, url: `https://example.com/${t}/${i}`, title: `Topic ${t} item ${i}`, platform: "web", category_id: TAXONOMY[t].id, subcategory: `Sub ${i % 7}`, saved_at: day(1 + i) });
}
rows.push({ id: "gone", url: "https://example.com/gone", category_id: TAXONOMY[0].id, deleted_at: day(2) }, { id: "no-url", url: "" });
const big = plain(D.buildModel(rows, { taxonomy: ctx.TAXONOMY }));
assert.equal(big.total, 78);
assert.equal(big.rooms.length, 10);
assert.equal(big.rooms[0].name, TAXONOMY[0].name);
assert.equal(big.rooms[9].name, "More topics");
assert.equal(big.rooms[9].total, 3 + 2 + 1);
for (const room of big.rooms) {
  assert.ok(room.shelves.length <= 5);
  assert.equal(room.shelves.reduce((n, s) => n + s.total, 0), room.total);
  for (const shelf of room.shelves) {
    assert.ok(shelf.cards.length <= 6);
    assert.ok(shelf.cards.every((c, i, a) => !i || a[i - 1].id.split("-")[1] * 1 > c.id.split("-")[1] * 1), "newest first");
  }
}
assert.equal(big.rooms[0].shelves.at(-1).name, "Everything else");
assert.equal(big.shown, big.rooms.reduce((n, r) => n + r.shelves.reduce((m, s) => m + s.cards.length, 0), 0));

const custom = plain(D.buildModel([
  { id: "a", url: "https://x.com/someone/status/1", platform: "x", category_id: "custom.home-lab", subcategory: "Racks", saved_at: day(3) },
  { id: "b", url: "https://www.reddit.com/r/selfhosted/comments/abc", platform: "web", category_id: "custom.home-lab", subcategory: " ", saved_at: day(2) },
  { id: "c", url: "https://youtu.be/xyz", platform: "web", category_id: null, duration_seconds: 754, saved_at: day(1) },
  { id: "d", url: "https://example.org/a", platform: "web", category_id: "custom.old-stuff", title: "", saved_at: day(1) },
], { taxonomy: ctx.TAXONOMY, customTopics: [{ id: "custom.home-lab", name: "Home lab", hue: 200 }] }));
assert.deepEqual(custom.rooms.map((r) => [r.name, r.hue === 200]), [["Home lab", true], ["Old stuff", false], ["Unfiled", false]]);
assert.deepEqual(custom.rooms[0].shelves.map((s) => s.name).sort(), ["General", "Racks"]);
const card = (id) => custom.rooms.flatMap((r) => r.shelves.flatMap((s) => s.cards)).find((c) => c.id === id);
assert.equal(card("b").source, "reddit");
assert.equal(card("b").meta, "r/selfhosted");
assert.equal(card("c").source, "youtube");
assert.equal(card("c").meta, "12:34");
assert.equal(custom.rooms[2].shelves[0].name, "YouTube");
assert.equal(card("d").title, "Saved from example.org");

/* ── Signed-in visitors: bm.session, refresh write-back, read-only loading ── */
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

/* ── Floor plan: signs and cards ── */
const fake = (rooms, shelves, cards) => ({
  total: rooms * shelves * cards, shown: rooms * shelves * cards,
  rooms: Array.from({ length: rooms }, (_, r) => ({
    id: `r${r}`, name: `Room ${r}`, hue: r * 36, total: shelves * cards,
    shelves: Array.from({ length: shelves }, (_, s) => ({ name: `Shelf ${s}`, total: cards, cards: Array.from({ length: cards }, (_, c) => ({ id: `${r}-${s}-${c}`, title: "t" })) })),
  })),
});
const models = { demo, full: fake(10, 5, 6), sparse: fake(1, 1, 1), wide: fake(7, 3, 6), mixed: plain(D.buildModel(rows, { taxonomy: ctx.TAXONOMY })) };
const eps = 1e-9;
for (const [name, model] of Object.entries(models)) {
  const L = computeLayout(model);
  assert.ok(L.N >= 6 && L.N <= 10, `${name}: ${L.N} rooms`);
  assert.equal(L.rooms.filter((r) => r.data).length, Math.min(model.rooms.length, 10));
  for (const room of L.rooms) {
    const label = `${name} room ${room.index}`;
    assert.ok(room.title.w <= room.usable - 1, `${label}: title fits the wall`);
    assert.ok(room.title.y + room.title.h / 2 < DIM.cutHero, `${label}: title stays below the section cut`);
    const ins = room.inscription;
    assert.ok(ins.y - ins.h / 2 > DIM.doorH + 0.4, `${label}: inscription clears the door arch`);
    assert.ok(ins.y + ins.h / 2 < DIM.cutHero, `${label}: inscription stays below the section cut`);
    const facet = 2 * L.R1 * L.tanH, colAngle = L.alpha / 2 - 0.78 / L.colR;
    assert.ok(ins.w < facet - 2 && Math.atan(ins.w / 2 / L.R1) < colAngle - Math.asin(DIM.colR / L.colR), `${label}: columns don't hide the inscription`);
    room.shelves.forEach((sh, i) => {
      const p = sh.plaque, spring = DIM.nicheTop - Math.min(sh.nicheW / 2, DIM.nicheRise);
      assert.ok(p.s - p.w / 2 >= -room.usable / 2 - eps && p.s + p.w / 2 <= room.usable / 2 + eps, `${label}: plaque ${i} on the wall`);
      assert.ok(p.y - p.h / 2 > DIM.nicheTop && p.y + p.h / 2 < room.title.y - room.title.h / 2, `${label}: plaque ${i} between niche and title`);
      assert.ok(sh.nicheW <= sh.pitch - 0.5, `${label}: niches ${i} keep a pier`);
      if (i) {
        const q = room.shelves[i - 1].plaque;
        assert.ok(q.s + q.w / 2 + 0.2 <= p.s - p.w / 2 + eps, `${label}: plaques ${i - 1}/${i} don't touch`);
      }
      for (const c of sh.cards) {
        assert.ok(Math.abs(c.s - sh.s) + DIM.card.w / 2 <= sh.nicheW / 2 + eps, `${label}: card inside niche ${i}`);
        assert.ok(c.y - DIM.card.h / 2 >= DIM.sill + 0.3 && c.y + DIM.card.h / 2 <= spring, `${label}: card between sill and arch`);
      }
      for (let a = 0; a < sh.cards.length; a++) for (let b = a + 1; b < sh.cards.length; b++) {
        const A = sh.cards[a], B = sh.cards[b];
        assert.ok(Math.abs(A.s - B.s) >= DIM.card.w + 0.15 || Math.abs(A.y - B.y) >= DIM.card.h + 0.15, `${label}: cards ${a}/${b} overlap`);
      }
    });
  }
}

/* ── Camera: free space, poses, tour, routes ── */
/* True when a camera at p can't be inside a wall, column or ceiling. Above
   the section-cut trigger the building is clipped away, so anything goes. */
function free(L, [x, y, z], m = 0.3) {
  if (y > DIM.cutHero - 0.4) return true;
  if (y < 0.4) return false;
  const r = Math.hypot(x, z), th = Math.atan2(x, z);
  const room = roomAt(L, th);
  const a = Math.atan2(Math.sin(th - room.phi), Math.cos(th - room.phi));
  const u = r * Math.cos(a), v = r * Math.sin(a);
  const arch = (w, h, off) => off < w / 2 && y < h - w / 2 + Math.sqrt(Math.max(0, (w / 2) ** 2 - off * off));
  if (u < L.R1 - m) {
    return L.rooms.every((rm) => [-1, 1].every((e) => {
      const c = at(L.colR, rm.phi + L.alpha / 2 + e * 0.78 / L.colR);
      return Math.hypot(x - c[0], z - c[2]) > DIM.colR + m;
    }));
  }
  if (u <= L.R1 + L.T + m) return arch(DIM.doorW - 2 * m, DIM.doorH - m, Math.abs(v));
  if (u >= L.A - m) return false;
  const half = L.alpha / 2;
  if (r * Math.sin(half - Math.abs(a)) > L.T / 2 + m) return true;
  return arch(DIM.enfW - 2 * m, DIM.enfH - m, Math.abs(r * Math.cos(half - Math.abs(a)) - L.pathR));
}
const lerp3 = (p, q, t) => p.map((v, i) => v + (q[i] - v) * t);
function walk(L, pts, label) {
  for (let i = 0; i < pts.length; i++) {
    assert.ok(free(L, pts[i]), `${label}: point ${i} ${pts[i].map((v) => v.toFixed(2))} is inside the building`);
    if (i) for (let k = 1; k < 16; k++) {
      const p = lerp3(pts[i - 1], pts[i], k / 16);
      assert.ok(free(L, p), `${label}: segment ${i - 1}→${i} passes through ${p.map((v) => v.toFixed(2))}`);
    }
  }
}
const inRoom = (L, j, [x, y, z]) => {
  const room = L.rooms[j], th = Math.atan2(x, z);
  const a = Math.atan2(Math.sin(th - room.phi), Math.cos(th - room.phi));
  const u = Math.hypot(x, z) * Math.cos(a);
  return Math.abs(a) < L.alpha / 2 && u > L.R1 + L.T && u < L.A && y < DIM.roomH;
};

for (const [name, model] of Object.entries(models)) {
  const L = computeLayout(model);
  for (const aspect of [21 / 9, 16 / 9, 16 / 10, 4 / 3, 1, 9 / 16]) {
    const V = views(L, aspect);
    for (let j = 0; j < L.N; j++) {
      assert.ok(inRoom(L, j, V.room(j).p) && free(L, V.room(j).p), `${name} @${aspect.toFixed(2)}: room ${j} pose`);
      assert.ok(free(L, V.rotunda(j).p), `${name} @${aspect.toFixed(2)}: rotunda pose ${j}`);
    }
    assert.ok(V.overview.p[1] > DIM.cutHero + 20, "the map looks down on the cut building");

    const plan = tourPlan(L, aspect);
    assert.ok(plan.keys.every((k, i) => !i || k.t > plan.keys[i - 1].t), `${name}: tour keys run forward`);
    assert.equal(plan.duration, plan.keys.at(-1).t);
    assert.ok(plan.duration > 30 && plan.duration < 60, `${name}: tour ${plan.duration.toFixed(1)} s`);
    walk(L, plan.keys.map((k) => k.p), `${name} tour @${aspect.toFixed(2)}`);
    const samples = plan.keys.flatMap((k, i) => (i ? Array.from({ length: 8 }, (_, s) => lerp3(plan.keys[i - 1].p, k.p, s / 8)) : [k.p]));
    for (let j = 0; j < L.N; j++) assert.ok(samples.some((p) => inRoom(L, j, p)), `${name}: the tour walks through room ${j}`);
    const last = plan.keys.at(-1);
    assert.ok(last.p[1] > DIM.cutHero + 20 && last.cut === DIM.cutHero && last.fov < 45, `${name}: the tour ends on the wide hero shot`);

    const caps = plan.captions;
    assert.equal(caps[0].kind, "title");
    assert.equal(caps.at(-1).kind, "end");
    assert.deepEqual(caps.filter((c) => c.kind === "room").map((c) => c.room), [...Array(L.N).keys()]);
    caps.forEach((c, i) => {
      assert.ok(c.to - c.from >= 1.5, `${name}: caption ${i} is readable`);
      if (i) assert.ok(caps[i - 1].to <= c.from + eps, `${name}: captions ${i - 1}/${i} overlap`);
    });
    assert.ok(caps.at(-1).from >= plan.craneT0 + 1, "the end card waits for the crane");

    const places = [{ kind: "overview" }, ...L.rooms.map((r) => ({ kind: "room", room: r.index })), ...L.rooms.map((r) => ({ kind: "rotunda", facing: r.index }))];
    const pose = (p) => (p.kind === "room" ? V.room(p.room) : p.kind === "rotunda" ? V.rotunda(p.facing) : V.overview).p;
    for (const from of places) for (const to of places) {
      if (from === to) continue;
      const label = `${name} @${aspect.toFixed(2)} ${JSON.stringify(from)}→${JSON.stringify(to)}`;
      const pts = [pose(from), ...routeBetween(L, from, to), pose(to)];
      walk(L, pts, label);
      /* Turning to face another doorway orbits the rotunda. Cutting straight
         across would cross the sun shaft and meet the old look target. */
      if (from.kind === "rotunda" && to.kind === "rotunda") {
        for (let i = 1; i < pts.length; i++) for (let k = 0; k <= 16; k++) {
          const p = lerp3(pts[i - 1], pts[i], k / 16);
          assert.ok(Math.hypot(p[0], p[2]) > L.R1 / 3, `${label}: crosses the middle of the rotunda`);
        }
      }
    }
  }
}
const demoPlan = tourPlan(computeLayout(demo), 16 / 9);
assert.ok(demoPlan.duration >= 35 && demoPlan.duration <= 45, `demo tour is ${demoPlan.duration.toFixed(2)} s`);

/* ── Page wiring ── */
const page = read("docs/palace/index.html"), script = read("docs/palace/palace.js");
for (const [, id] of script.matchAll(/\$\("([\w-]+)"\)/g)) assert.match(page, new RegExp(`id="${id}"`), `#${id} exists`);
assert.match(page, /"three": "https:\/\/cdn\.jsdelivr\.net\/npm\/three@0\.160\.0\/build\/three\.module\.js"/);
assert.match(page, /"three\/addons\/": "https:\/\/cdn\.jsdelivr\.net\/npm\/three@0\.160\.0\/examples\/jsm\/"/);
const order = ["/taxonomy.js", "/palace/palace-data.js", 'type="module" src="/palace/palace.js"'].map((s) => page.indexOf(s));
assert.ok(order.every((n, i) => n > 0 && (!i || n > order[i - 1])), "data scripts load before the module");
for (const mod of ["layout.js", "world.js", "cards.js", "tour.js", "art.js"]) assert.ok(fs.existsSync(`docs/palace/${mod}`), mod);
const site = read("docs/index.html");
const pitch = site.slice(site.indexOf('<section id="auth"'), site.indexOf("<!-- ─────────────── App"));
assert.match(pitch, /class="pitch-palace" href="\/palace"/, "signed-out visitors see the palace");
assert.match(site.slice(site.indexOf('<nav class="nav-tabs"')), /href="\/palace"/, "the app nav links the palace");
assert.equal((read("docs/app/index.html").match(/href="\/palace"/g) || []).length >= 2, true, "landing nav and footer link the palace");

console.log("Memory Palace: demo library, grouping caps, bm.session refresh and read-only loading, sign layout, card alcoves, tour coverage and timing, wall-free camera routes and page wiring passed.");
