/* Library Atlas entry point: load the library, lay it out, build the scene
   and the shell, and drive both from one state object. ?capture exposes a
   deterministic hook set (window.palace) so the marketing frames can be
   rendered headless without any clocks running. */
import * as THREE from "three";
import { computeLayout, readingTrail, regionById, libraryBounds } from "./atlas-layout.js";
import { AtlasScene } from "./atlas-scene.js";
import { AtlasUI } from "./atlas-ui.js";
import { Tour } from "./atlas-tour.js";

const params = new URLSearchParams(location.search);
const CAPTURE = params.has("capture");
const STRESS = params.has("stress");
const el = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const REDUCED = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

const state = {
  mode: "topics",
  tab: "layers",
  dim: "3d",
  time: 1,
  playing: false,
  speed: 1,
  selection: null,
  focus: null,
  moment: null,
  hidden: new Set(),
  groupOpacity: new Map(),
  layers: {
    terrain: { on: true, opacity: 1 },
    forest: { on: true, opacity: 1 },
    tints: { on: true, opacity: 1 },
    edges: { on: true, opacity: 0.85 },
    markers: { on: true, opacity: 1 },
    trail: { on: true, opacity: 0.95 },
    labels: { on: true, opacity: 1 },
  },
  tour: { active: false, t: 0 },
  follow: { on: false, u: 0, view: "eye" },
};

let atlas, layout, scene, ui, tour;
let canvasAbort = null;
let flight = null;

/* ── data ───────────────────────────────────────────────────────────────── */
const loadDemo = () => (STRESS ? PalaceData.stressAtlas(TAXONOMY) : PalaceData.demoAtlas(TAXONOMY));

async function loadMine() {
  const { rows, customTopics, truncated, email } = await PalaceData.loadOwnLibrary({
    storage: localStorage, fetch: window.fetch.bind(window),
  });
  return PalaceData.buildAtlas(rows, {
    taxonomy: TAXONOMY, customTopics, demo: false, truncated,
    label: email || "My library",
  });
}

/* ── menus (built as elements; a label is never parsed as markup) ───────── */
let openMenu = null;
function menu(anchor, items) {
  closeMenu();
  const box = document.createElement("div");
  box.className = "menu";
  box.setAttribute("role", "menu");
  for (const it of items) {
    if (it.divider) {
      const d = document.createElement("div");
      d.className = "menu-div";
      box.appendChild(d);
      continue;
    }
    const b = document.createElement("button");
    b.type = "button";
    b.setAttribute("role", "menuitem");
    const label = document.createElement("span");
    label.textContent = it.label;
    b.appendChild(label);
    if (it.note) {
      const note = document.createElement("small");
      note.textContent = it.note;
      b.appendChild(note);
    }
    b.addEventListener("click", () => { closeMenu(); it.onPick && it.onPick(); });
    box.appendChild(b);
  }
  document.body.appendChild(box);
  const r = anchor.getBoundingClientRect();
  box.style.left = `${Math.min(r.left, innerWidth - box.offsetWidth - 8)}px`;
  box.style.top = `${r.bottom + 4}px`;
  box.querySelector("button")?.focus();
  openMenu = box;
  setTimeout(() => document.addEventListener("pointerdown", closeMenu, { once: true }), 0);
}
function closeMenu() { if (openMenu) { openMenu.remove(); openMenu = null; } }

function toast(text) {
  const t = document.createElement("div");
  t.className = "toast";
  t.setAttribute("role", "status");
  t.textContent = text;
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3600);
}

/* ── actions the shell calls back into ──────────────────────────────────── */
const actions = {
  setMode(mode) {
    state.mode = mode;
    const follow = mode === "follow";
    if (state.follow.on !== follow) {
      state.follow.on = follow;
      scene.setFollowOn(follow);
      if (follow) {
        if (!state.focus) actions.focusRegion(tour.region ? tour.region.id : layout.regions[0].id);
        scene.setFollow(state.follow.u);
        flyTo(scene.followPose(state.follow.u), 1400);
      } else {
        flyTo(overviewPose());
      }
    }
    if (mode === "timeline") state.tab = "overview";
    if (follow) state.tab = "follow";
    else if (state.tab === "follow") state.tab = "layers";
    scene.setColorMode(mode === "sources" ? "sources" : "topics");
    scene.setTimeFilter(state.time);
    scene.applyLayers();
    ui.chartCache = null;
    ui.refresh();
    if (mode === "timeline" && !CAPTURE && !REDUCED) { actions.setTime(0); actions.togglePlay(); }
  },
  setTab(tab) { state.tab = tab; ui.refresh(); },
  setDim(dim) { state.dim = dim; scene.setDim(dim); ui.refresh(); },
  setTime(frac) {
    state.time = clamp(frac, 0, 1);
    scene.setTimeFilter(state.time);
    scene.applyLayers();          // the trail only exists once time has run out
    ui.refresh();
  },
  togglePlay() {
    if (!atlas.range) return;
    state.playing = !state.playing;
    if (state.playing && state.time >= 0.999) state.time = 0;
    ui.refresh();
  },
  cycleSpeed() {
    state.speed = state.speed === 1 ? 2 : state.speed === 2 ? 4 : 1;
    ui.refresh();
  },
  stepMoment(dir) {
    if (!atlas.moments.length) return;
    const next = state.moment == null ? (dir > 0 ? 0 : atlas.moments.length - 1) : state.moment + dir;
    actions.goToMoment(clamp(next, 0, atlas.moments.length - 1));
  },
  goToMoment(i) {
    const m = atlas.moments[i];
    if (!m) return;
    state.moment = i;
    state.playing = false;
    actions.setTime(ui.frac(m.at));
  },
  setLayerVisible(id, on) {
    state.layers[id].on = on;
    scene.applyLayers();
    ui.syncLayers();
  },
  setLayerOpacity(id, v) {
    state.layers[id].opacity = v;
    state.layers[id].on = v > 0.02;
    scene.applyLayers();
    ui.syncLayers();
  },
  setGroupVisible(key, on) {
    if (on) state.hidden.delete(key); else state.hidden.add(key);
    scene.setTimeFilter(state.time);
    scene.applyLayers();
    ui.syncLayers();
  },
  setGroupOpacity(key, v) {
    state.groupOpacity.set(key, v);
    if (v <= 0.02) state.hidden.add(key); else state.hidden.delete(key);
    scene.setTimeFilter(state.time);
    scene.applyLayers();
    ui.syncLayers();
  },
  focusRegion(id) {
    state.focus = id;
    ui.chartCache = null;
    if (id) {
      const r = regionById(layout, id);
      scene.buildTrail(readingTrail(layout, { regionId: id, count: 8 }));
      scene.buildFrontRings(id);
      scene.rebuildTrailLabels();
      scene.applyLayers();
      if (r) flyTo({ tx: r.x, ty: scene.groundAt(r.x, r.z) + 20, tz: r.z, dist: Math.max(230, r.r * 3.1), pol: 1.1, az: Math.atan2(r.x, r.z) - 0.35 });
    } else {
      scene.buildTrail(readingTrail(layout, { count: 7 }));
      scene.buildFrontRings(null);
      scene.rebuildTrailLabels();
      scene.applyLayers();
      flyTo(overviewPose());
    }
    ui.refresh();
  },
  select(marker) {
    state.selection = marker ? marker.item : null;
    scene.selectMarker(marker);
    ui.refresh();
  },
  selectById(id, { fly = false } = {}) {
    const m = scene.markerById(id);
    if (!m) return;
    state.focus = m.regionId;
    ui.chartCache = null;
    scene.applyLayers();
    actions.select(m);
    if (fly) actions.flyToSelection();
  },
  flyToSelection() {
    const sel = state.selection;
    if (!sel) return;
    const m = scene.markerById(sel.id);
    if (m) flyTo({ tx: m.x, ty: scene.groundAt(m.x, m.z) + 8, tz: m.z, dist: 235, pol: 1.05, az: scene.cam.az });
  },
  stops() { return scene.trailPins || []; },
  goToStop(i) {
    const stops = scene.trailPins || [];
    if (!stops.length) return;
    const u = stops.length < 2 ? 0 : clamp(i, 0, stops.length - 1) / (stops.length - 1);
    state.follow.u = u;
    scene.setFollow(u);
    actions.select(stops[Math.round(u * (stops.length - 1))]);
    flyTo(scene.followPose(u), 1200);
  },
  setFollowView(view) {
    state.follow.view = view === "plan" ? "plan" : "eye";
    scene.follow.view = state.follow.view;
    ui.refresh();
  },
  /* Everything the reader-cam HUD prints, derived from the route. */
  followInfo() {
    const stops = scene.trailPins || [];
    const f = scene.follow;
    const curve = scene.trailCurve;
    const length = curve ? curve.getLength() : 0;
    const dated = stops.filter((m) => m.at != null);
    const rideSeconds = tour ? tour.beatLength("follow") : 8;
    return {
      on: state.follow.on,
      u: f.u,
      view: state.follow.view,
      stop: f.stop,
      stops,
      heading: f.heading,
      pitch: f.pitch,
      alt: f.alt,
      elev: f.elev,
      x: f.point.x,
      z: f.point.z,
      length,
      speed: rideSeconds ? length / rideSeconds : 0,
      elapsed: f.u * rideSeconds,
      zoom: state.follow.view === "plan" ? 1 : 1.4,
      spanDays: dated.length > 1 ? Math.round((dated[dated.length - 1].at - dated[0].at) / 86_400_000) : null,
      rect: scene.pipRect(),
    };
  },
  resetView() {
    state.focus = null;
    ui.chartCache = null;
    scene.applyLayers();
    flyTo({ ...overviewPose(), az: 0.5 });
    ui.refresh();
  },
};

/* The pose that frames the library itself: steep enough that the viewport is
   terrain and data rather than sky, close enough that the regions fill it. */
function overviewPose(az, focusId = state.focus) {
  // When a region is in focus the wide shot leans towards it and comes in a
  // little, so the active area carries the frame instead of sitting as one
  // small blob in the middle of the scenery.
  const r = focusId ? regionById(layout, focusId) : null;
  const tx = r ? r.x * 0.46 : 0;
  const tz = r ? r.z * 0.46 : 0;
  return {
    tx, ty: scene.groundAt(tx, tz) + 55, tz,
    dist: scene.frameDistance(1.06) * (r ? 0.74 : 1), pol: 1.045,
    az: az != null ? az : scene.cam.az,
  };
}

/* ── camera easing for interactive flights ──────────────────────────────── */
function flyTo(pose, ms = 1700) {
  if (REDUCED) { scene.setCamera(pose); flight = null; return; }
  flight = { from: { ...scene.cam }, to: { ...scene.cam, ...pose }, t0: performance.now(), ms };
}
function stepFlight(now) {
  if (!flight) return;
  const u = Math.min(1, (now - flight.t0) / flight.ms);
  const e = u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
  const a = flight.from, b = flight.to;
  const dAz = (((b.az - a.az) % (Math.PI * 2)) + Math.PI * 3) % (Math.PI * 2) - Math.PI;
  scene.setCamera({
    tx: a.tx + (b.tx - a.tx) * e, ty: a.ty + (b.ty - a.ty) * e, tz: a.tz + (b.tz - a.tz) * e,
    dist: a.dist + (b.dist - a.dist) * e, pol: a.pol + (b.pol - a.pol) * e, az: a.az + dAz * e,
  });
  if (u >= 1) flight = null;
}

/* ── pointer interaction, re-attached to every new canvas ───────────────── */
function wireCanvas() {
  canvasAbort?.abort();
  canvasAbort = new AbortController();
  const signal = canvasAbort.signal;
  const stage = el("stage"), canvas = el("scene");
  let drag = null, moved = 0;
  const add = (node, type, fn, opts) => node.addEventListener(type, fn, { ...(opts || {}), signal });

  add(canvas, "pointerdown", (ev) => {
    canvas.setPointerCapture(ev.pointerId);
    drag = { x: ev.clientX, y: ev.clientY };
    moved = 0;
    stage.classList.add("dragging");
    flight = null;
  });
  add(canvas, "pointermove", (ev) => {
    const r = canvas.getBoundingClientRect();
    if (drag) {
      const dx = ev.clientX - drag.x, dy = ev.clientY - drag.y;
      drag = { x: ev.clientX, y: ev.clientY };
      moved += Math.abs(dx) + Math.abs(dy);
      if (state.dim === "2d") {
        const k = scene.cam.dist * 0.0012;
        scene.setCamera({ tx: scene.cam.tx - dx * k, tz: scene.cam.tz - dy * k });
      } else {
        scene.setCamera({ az: scene.cam.az - dx * 0.005, pol: scene.cam.pol - dy * 0.004 });
      }
      return;
    }
    const m = scene.pick(ev.clientX - r.left, ev.clientY - r.top);
    scene.hovered = m;
    ui.setTip(m ? { x: ev.clientX - r.left, y: ev.clientY - r.top } : null, m ? m.item : null);
    canvas.style.cursor = m ? "pointer" : "";
  });
  const end = (ev) => {
    if (drag && moved < 5) {
      const r = canvas.getBoundingClientRect();
      const m = scene.pick(ev.clientX - r.left, ev.clientY - r.top);
      if (m) actions.selectById(m.id);
      else actions.select(null);
    }
    drag = null;
    stage.classList.remove("dragging");
  };
  add(canvas, "pointerup", end);
  add(canvas, "pointercancel", () => { drag = null; stage.classList.remove("dragging"); });
  add(canvas, "wheel", (ev) => {
    ev.preventDefault();
    flight = null;
    scene.setCamera({ dist: scene.cam.dist * Math.exp(ev.deltaY * 0.0011) });
  }, { passive: false });
  add(canvas, "pointerleave", () => ui.setTip(null, null));
}

/* ── shell wiring: attached once, survives a library switch ─────────────── */
function wireShell() {
  el("menu-view").addEventListener("click", (e) => menu(e.currentTarget, [
    { label: state.tour.active ? "Stop tour" : "Play tour", note: `${Math.round(tour.duration)}s`, onPick: () => toggleTour() },
    { label: "Reset camera", note: "R", onPick: () => actions.resetView() },
    { divider: true },
    { label: state.dim === "2d" ? "3D terrain" : "2D flat map", note: "M", onPick: () => actions.setDim(state.dim === "2d" ? "3d" : "2d") },
    { label: state.layers.labels.on ? "Hide labels" : "Show labels", onPick: () => actions.setLayerVisible("labels", !state.layers.labels.on) },
  ]));
  el("menu-share").addEventListener("click", (e) => menu(e.currentTarget, [
    { label: "Copy link to this atlas", onPick: () => { navigator.clipboard?.writeText(location.href); toast("Link copied"); } },
    { label: "Open bookmarker", onPick: () => { location.href = "/"; } },
  ]));
  el("library-pick").addEventListener("click", (e) => menu(e.currentTarget, [
    { label: "Demo library", note: `${PalaceData.demoRows().length}`, onPick: () => swapLibrary(loadDemo()) },
    { label: "My library", note: "read-only", onPick: () => mine() },
  ]));

  window.addEventListener("resize", resize);
  addEventListener("keydown", (ev) => {
    // shortcuts belong to the page, not to whatever control has focus
    const t = ev.target;
    const typing = t && (t.matches?.("input, textarea, select, [contenteditable]") || t.getAttribute?.("role") === "slider");
    if (typing || ev.metaKey || ev.ctrlKey || ev.altKey) return;
    if (ev.key === "t") toggleTour();
    else if (ev.key === "r") actions.resetView();
    else if (ev.key === "m") actions.setDim(state.dim === "2d" ? "3d" : "2d");
    else if (ev.key === "Escape") { closeMenu(); actions.select(null); }
    else if (ev.key === " " && !(t && t.matches?.("button, a"))) { ev.preventDefault(); actions.togglePlay(); }
  });
}

async function mine() {
  try {
    toast("Reading your library…");
    swapLibrary(await loadMine());
  } catch (err) {
    toast(err.status === 401 ? "Sign in at bookmarker.lol first — the atlas only reads." : err.message || "Couldn't load your library.");
  }
}

function swapLibrary(next) {
  atlas = next;
  layout = computeLayout(atlas);
  state.focus = null; state.selection = null; state.time = 1; state.moment = null;
  state.playing = false; state.tour.active = false; state.tour.t = 0;
  state.hidden.clear(); state.groupOpacity.clear();
  flight = null;
  rebuild();
}

/* ── build / rebuild ────────────────────────────────────────────────────── */
function rebuild() {
  if (scene) scene.dispose();
  if (ui) ui.destroy();
  if (scene) {
    const fresh = document.createElement("canvas");
    fresh.id = "scene";
    el("scene").replaceWith(fresh);
  }
  scene = new AtlasScene({ canvas: el("scene"), labelHost: el("labels"), atlas, layout, state, capture: CAPTURE }).init();
  // The whole-library reading trail is on by default, so the overview carries
  // the same kind of dated path the reference draws over its terrain.
  scene.buildTrail(readingTrail(layout, { count: 7 }));
  scene.buildFrontRings(null);
  scene.rebuildTrailLabels();
  tour = new Tour({
    atlas, layout,
    ground: (x, z) => scene.groundAt(x, z),
    frameDist: (m) => scene.frameDistance(m),
    followPose: (u) => { scene.setFollow(u); return scene.followPose(u); },
  });
  ui = new AtlasUI({ atlas, state, actions });
  ui.build();
  wireCanvas();
  resize();
  scene.setDim(state.dim);
  scene.setCamera(overviewPose(0.5));
}

function resize() {
  const stage = el("stage");
  scene.resize(stage.clientWidth, stage.clientHeight);
  ui.chartCache = null;
  ui.drawCharts();
}

/* ── tour playback ──────────────────────────────────────────────────────── */
function toggleTour() {
  state.tour.active = !state.tour.active;
  state.tour.t = 0;
  if (!state.tour.active) { ui.setLower(null); actions.resetView(); }
}

let lastTourKey = "";
function applyTourState(t) {
  const s = tour.stateAt(t);
  const modeChanged = s.mode !== state.mode;
  state.mode = s.mode;
  const wantFollow = s.mode === "follow";
  if (state.follow.on !== wantFollow) { state.follow.on = wantFollow; scene.setFollowOn(wantFollow); }
  if (wantFollow) { state.follow.u = s.follow; scene.setFollow(s.follow); }
  state.tab = s.tab;
  if (state.dim !== s.dim) { state.dim = s.dim; scene.setDim(s.dim); }
  const focusChanged = state.focus !== s.focus;
  state.focus = s.focus;
  state.time = s.time;
  state.selection = s.selection ? s.selection.item : null;
  if (modeChanged) scene.setColorMode(s.mode === "sources" ? "sources" : "topics");
  if (modeChanged || focusChanged) ui.chartCache = null;
  const trailIds = s.trail.map((m) => m.id).join(",");
  if (trailIds !== scene._trailIds || focusChanged) {
    scene._trailIds = trailIds;
    scene.buildTrail(s.trail);
    scene.buildFrontRings(s.focus);
    scene.rebuildTrailLabels();
  }
  scene.setTimeFilter(state.time);
  scene.selectMarker(s.selection || null);
  scene.applyLayers();
  scene.setCamera(tour.cameraAt(t));

  // Only redo the panels when something they show has actually changed.
  const key = `${s.mode}|${s.tab}|${s.dim}|${s.focus}|${state.selection ? state.selection.id : ""}`
    + `|${Math.round(state.time * 400)}|${wantFollow ? Math.round(s.follow * 60) : ""}`;
  if (key !== lastTourKey) {
    lastTourKey = key;
    ui.refresh();
    ui.setLower(s.lower.title, s.lower.sub);
  }
  if (s.hover) {
    const p = scene.project(s.hover.x, s.hover.y + s.hover.height * scene.markerScale + 3, s.hover.z);
    ui.setTip(p.behind ? null : p, s.hover.item);
  } else {
    ui.setTip(null, null);
  }
}

/* ── frame loop ─────────────────────────────────────────────────────────── */
let last = performance.now();
function frame(now) {
  const dt = Math.min(64, now - last);
  last = now;
  if (state.tour.active) {
    state.tour.t += dt / 1000;
    if (state.tour.t > tour.duration) state.tour.t = 0;
    applyTourState(state.tour.t);
  } else {
    stepFlight(now);
    if (state.playing && atlas.range) {
      const weeks = Math.max(1, atlas.weeks.length);
      state.time = Math.min(1, state.time + (dt / 1000) * state.speed * (1.6 / weeks) * 14);
      scene.setTimeFilter(state.time);
      scene.applyLayers();
      ui.refresh();
      if (state.time >= 1) state.playing = false;
    }
  }
  scene.render();
  updateReadouts();
  scene.measure(dt);
  requestAnimationFrame(frame);
}

/* The scale bar measures the model, which is a synthetic place — so it is
   labelled in map units, not in metres. */
function updateReadouts() {
  const c = scene.cam;
  ui.setZoom(`${(scene.frameDistance(1.06) / c.dist).toFixed(1)}×`);
  ui.setCompass(c.az);
  const vFov = (scene.camera.fov * Math.PI) / 180;
  const perPx = state.dim === "2d"
    ? (scene.ortho.top - scene.ortho.bottom) / Math.max(1, scene.height)
    : (2 * Math.tan(vFov / 2) * c.dist) / Math.max(1, scene.height);
  const nice = [10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000];
  const want = perPx * 130;
  const pick = nice.filter((n) => n <= want).pop() || nice[0];
  ui.setScale(Math.round(pick / perPx), `${Math.round(pick / 2)}`, `${pick} u`);
}

/* ── capture hooks ──────────────────────────────────────────────────────── */
function installCapture() {
  const api = {
    ready: false,
    /* Render and wait for the GPU to actually finish, so a screenshot taken
       straight afterwards is the frame we just asked for — and so timing a
       sync() measures real work rather than queue time. */
    sync() {
      scene.render();
      scene.renderer.getContext().finish();
      return true;
    },
    duration() { return tour.duration; },
    beats() { return tour.plan.beats.map((b) => ({ id: b.id, start: b.start, end: b.end, label: b.label })); },
    renderAt(t) {
      state.tour.active = true;
      state.tour.t = t;
      lastTourKey = "";
      applyTourState(t);
      scene.render();
      return t;
    },
    pose(name, opts = {}) {
      const at = (id, f) => {
        const beat = tour.plan.beats.find((b) => b.id === id);
        return beat ? beat.start + beat.length * f : 4.5;
      };
      const times = {
        overview: at("orbit-in", 0.6), timeline: at("timeline", 0.72), region: at("region", 0.9),
        detail: at("detail", 0.85), trail: at("trail", 0.6), follow: at("follow", 0.55),
        sources: at("sources", 0.6), map2d: at("map2d", 0.5),
      };
      const t = times[name] != null ? times[name] : at("orbit-in", 0.6);
      api.renderAt(t);
      if (name !== "trail") ui.setLower(null);
      if (name === "overview") {
        state.time = 1;
        state.tab = "overview";
        // the wide shot still has a subject: the biggest region, drawn
        // saturated while the rest drop back
        const big = tour.big ? tour.big.id : null;
        if (state.focus !== big) {
          state.focus = big;
          scene.buildTrail(readingTrail(layout, { regionId: big, count: 8 }));
          scene.buildFrontRings(big);
          scene.rebuildTrailLabels();
        }
        scene.setTimeFilter(1);
        scene.applyLayers();
        scene.setCamera(overviewPose(big ? Math.atan2(tour.big.x, tour.big.z) - 0.62 : 0.5, big));
        ui.chartCache = null;
        ui.refresh();
      }
      if (name === "region" && opts.topic) {
        const r = regionById(layout, opts.topic);
        if (r) {
          state.focus = r.id;
          scene.buildTrail(readingTrail(layout, { regionId: r.id, count: 8 }));
          scene.rebuildTrailLabels();
          scene.applyLayers();
          scene.setCamera({ tx: r.x, ty: scene.groundAt(r.x, r.z) + 20, tz: r.z, dist: Math.max(250, r.r * 3.2), pol: 1.08, az: Math.atan2(r.x, r.z) - 0.4 });
          ui.chartCache = null;
          ui.refresh();
        }
      }
      scene.render();
      updateReadouts();
      return name;
    },
    /* Everything a frame depends on, so a determinism check can say which
       piece of state leaked between two capture calls. */
    debug() {
      const c = scene.cam;
      return {
        cam: [c.tx, c.ty, c.tz, c.dist, c.pol, c.az].map((v) => Math.round(v * 1e4) / 1e4),
        markerScale: Math.round(scene.markerScale * 1e4) / 1e4,
        trail: scene._trailIds || "",
        forest: scene.forest.children.map((t) => t.count).join(","),
        scrub: scene.scrub.children.map((t) => t.count).join(","),
        labels: [...document.querySelectorAll("#labels .pin")].filter((n) => n.style.display !== "none").length,
        tints: [...scene.tints.children].map((o) => (o.material ? Math.round(o.material.opacity * 1000) : -1)).join(","),
        tip: el("tip").hidden ? "" : el("tip").textContent,
        charts: [...document.querySelectorAll(".chart .now")].map((n) => n.textContent).join("|"),
      };
    },
    setQuality(tier) { return scene.setQuality(tier); },
    quality() { return { ...scene.quality }; },
    state() {
      return {
        mode: state.mode, tab: state.tab, dim: state.dim, focus: state.focus,
        follow: state.follow.on ? { u: Math.round(state.follow.u * 1000) / 1000, stop: scene.follow.stop, view: state.follow.view } : null,
        time: state.time, markers: scene.shownMarkers, undated: scene.shownUndated,
        selection: state.selection ? state.selection.title : null,
        label: atlas.label, total: atlas.total, truncated: atlas.truncated,
        trees: atlas ? scene.forest.userData.total : 0,
        relief: scene.heightRange(),
      };
    },
  };
  window.palace = api;
  return api;
}

/* ── boot ───────────────────────────────────────────────────────────────── */
async function boot() {
  try {
    atlas = loadDemo();
    layout = computeLayout(atlas);
    rebuild();
    wireShell();
    if (CAPTURE) el("boot").remove();
    else { el("boot").classList.add("gone"); setTimeout(() => el("boot").remove(), 600); }
    if (CAPTURE) {
      const api = installCapture();
      el("vp-hint").hidden = true;
      // Fonts change text metrics, which changes label collision and panel
      // truncation — a frame taken before they land isn't the real layout.
      if (document.fonts && document.fonts.ready) await document.fonts.ready;
      resize();
      scene.render();
      updateReadouts();
      api.ready = true;
      document.documentElement.dataset.capture = "ready";
    } else {
      requestAnimationFrame((t) => { last = t; frame(t); });
      if (params.has("tour") && !REDUCED) toggleTour();
      if (PalaceData.readSession(localStorage)) el("library-pick").title = "Signed in — switch to your own library";
    }
  } catch (err) {
    console.error(err);
    el("boot")?.remove();
    el("fallback").hidden = false;
  }
}

if (document.createElement("canvas").getContext("webgl2")) boot();
else { el("boot").remove(); el("fallback").hidden = false; }
