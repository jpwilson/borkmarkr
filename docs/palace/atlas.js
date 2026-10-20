/* Library Atlas entry point: load the library, lay it out, build the scene
   and the shell, and drive both from one state object. ?capture exposes a
   deterministic hook set (window.palace) so the marketing frames can be
   rendered headless without any clocks running. */
import * as THREE from "three";
import { computeLayout, readingTrail, regionById } from "./atlas-layout.js";
import { AtlasScene } from "./atlas-scene.js";
import { AtlasUI, fmtDate } from "./atlas-ui.js";
import { Tour } from "./atlas-tour.js";

const params = new URLSearchParams(location.search);
const CAPTURE = params.has("capture");
const el = (id) => document.getElementById(id);

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
    trail: { on: true, opacity: 0.9 },
    labels: { on: true, opacity: 1 },
  },
  tour: { active: false, t: 0 },
};

let atlas, layout, scene, ui, tour;

/* ── data ───────────────────────────────────────────────────────────────── */
function loadDemo() {
  return PalaceData.demoAtlas(TAXONOMY);
}

async function loadMine() {
  const { rows, customTopics, email } = await PalaceData.loadOwnLibrary({ storage: localStorage, fetch: window.fetch.bind(window) });
  return PalaceData.buildAtlas(rows, { taxonomy: TAXONOMY, customTopics, demo: false, label: email || "My library" });
}

/* ── menus ──────────────────────────────────────────────────────────────── */
let openMenu = null;
function menu(anchor, items) {
  closeMenu();
  const box = document.createElement("div");
  box.style.cssText = "position:fixed;z-index:40;min-width:190px;padding:4px;border-radius:8px;background:#ECE8DF;border:1px solid #CFC8B8;box-shadow:0 10px 30px -12px rgba(30,28,25,.45);font-size:12.5px";
  for (const it of items) {
    if (it.divider) {
      const d = document.createElement("div");
      d.style.cssText = "height:1px;background:#CFC8B8;margin:4px 2px";
      box.appendChild(d);
      continue;
    }
    const b = document.createElement("button");
    b.type = "button";
    b.style.cssText = "display:flex;width:100%;align-items:center;gap:8px;height:28px;padding:0 9px;border:0;border-radius:5px;background:transparent;cursor:pointer;text-align:left";
    b.innerHTML = `<span style="flex:1 1 auto">${it.label}</span>${it.note ? `<small style="color:#6E685E">${it.note}</small>` : ""}`;
    b.addEventListener("mouseenter", () => { b.style.background = "#E2DDD0"; });
    b.addEventListener("mouseleave", () => { b.style.background = "transparent"; });
    b.addEventListener("click", () => { closeMenu(); it.onPick && it.onPick(); });
    box.appendChild(b);
  }
  document.body.appendChild(box);
  const r = anchor.getBoundingClientRect();
  box.style.left = `${Math.min(r.left, innerWidth - box.offsetWidth - 8)}px`;
  box.style.top = `${r.bottom + 4}px`;
  openMenu = box;
  setTimeout(() => document.addEventListener("pointerdown", closeMenu, { once: true }), 0);
}
function closeMenu() { if (openMenu) { openMenu.remove(); openMenu = null; } }

function toast(text) {
  const t = document.createElement("div");
  t.textContent = text;
  t.style.cssText = "position:fixed;left:50%;bottom:28px;transform:translateX(-50%);z-index:50;padding:8px 14px;border-radius:8px;background:#1E1C19;color:#F3EFE6;font-size:12.5px;box-shadow:0 10px 30px -12px rgba(0,0,0,.5)";
  document.body.appendChild(t);
  setTimeout(() => t.remove(), 3200);
}

/* ── actions the shell calls back into ──────────────────────────────────── */
const actions = {
  setMode(mode) {
    state.mode = mode;
    state.tab = mode === "timeline" ? "overview" : state.tab;
    scene.setColorMode(mode === "sources" ? "sources" : "topics");
    scene.setTimeFilter(state.time);
    scene.applyLayers();
    ui.buildLayers();
    ui.refresh();
    if (mode === "timeline" && !CAPTURE) actions.setTime(0), actions.togglePlay();
  },
  setTab(tab) { state.tab = tab; ui.refresh(); },
  setDim(dim) { state.dim = dim; scene.setDim(dim); ui.refresh(); },
  setTime(frac) {
    state.time = Math.min(1, Math.max(0, frac));
    scene.setTimeFilter(state.time);
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
    actions.goToMoment(Math.min(atlas.moments.length - 1, Math.max(0, next)));
  },
  goToMoment(i) {
    const m = atlas.moments[i];
    if (!m) return;
    state.moment = i;
    state.playing = false;
    actions.setTime(ui.frac(m.at));
  },
  toggleLayer(id) {
    state.layers[id].on = !state.layers[id].on;
    scene.applyLayers();
    ui.buildLayers();
  },
  setLayerOpacity(id, v) {
    state.layers[id].opacity = v;
    state.layers[id].on = v > 0.02;
    scene.applyLayers();
    ui.buildLayers();
  },
  toggleGroup(key) {
    if (state.hidden.has(key)) state.hidden.delete(key); else state.hidden.add(key);
    scene.setTimeFilter(state.time);
    scene.applyLayers();
    ui.buildLayers();
  },
  setGroupOpacity(key, v) {
    state.groupOpacity.set(key, v);
    if (v <= 0.02) state.hidden.add(key); else state.hidden.delete(key);
    scene.setTimeFilter(state.time);
    scene.applyLayers();
    ui.buildLayers();
  },
  focusRegion(id) {
    state.focus = id;
    scene.applyLayers();
    if (id) {
      const r = regionById(layout, id);
      scene.buildTrail(readingTrail(layout, { regionId: id, count: 8 }));
      scene.rebuildTrailLabels();
      if (r) flyTo({ tx: r.x, ty: scene.groundAt(r.x, r.z) + 24, tz: r.z, dist: Math.max(230, r.r * 2.9), pol: 1.14, az: Math.atan2(r.x, r.z) - 0.35 });
    } else {
      scene.buildTrail(readingTrail(layout, { count: 7 }));
      scene.rebuildTrailLabels();
      flyTo({ tx: 0, ty: scene.groundAt(0, 0) + 70, tz: 0, dist: 930, pol: 1.145, az: scene.cam.az });
    }
    ui.buildLayers();
    ui.refresh();
  },
  select(marker) {
    state.selection = marker ? marker.item : null;
    scene.selectMarker(marker);
    ui.refresh();
  },
  flyToSelection() {
    const sel = state.selection;
    if (!sel) return;
    const m = scene.markers.find((x) => x.id === sel.id);
    if (m) flyTo({ tx: m.x, ty: scene.groundAt(m.x, m.z) + 9, tz: m.z, dist: 190, pol: 1.06, az: scene.cam.az });
  },
  resetView() {
    state.focus = null;
    scene.applyLayers();
    ui.buildLayers();
    flyTo({ tx: 0, ty: scene.groundAt(0, 0) + 70, tz: 0, dist: 930, pol: 1.145, az: 0.5 });
  },
};

/* ── camera easing for interactive flights ──────────────────────────────── */
let flight = null;
function flyTo(pose, ms = 1700) {
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

/* ── pointer interaction ────────────────────────────────────────────────── */
function wireCanvas() {
  const stage = el("stage"), canvas = el("scene");
  let drag = null, moved = 0;
  canvas.addEventListener("pointerdown", (ev) => {
    canvas.setPointerCapture(ev.pointerId);
    drag = { x: ev.clientX, y: ev.clientY };
    moved = 0;
    stage.classList.add("dragging");
    flight = null;
  });
  canvas.addEventListener("pointermove", (ev) => {
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
      actions.select(m);
      if (m) state.focus = m.regionId, scene.applyLayers(), ui.buildLayers();
    }
    drag = null;
    stage.classList.remove("dragging");
  };
  canvas.addEventListener("pointerup", end);
  canvas.addEventListener("pointercancel", () => { drag = null; stage.classList.remove("dragging"); });
  canvas.addEventListener("wheel", (ev) => {
    ev.preventDefault();
    flight = null;
    scene.setCamera({ dist: scene.cam.dist * Math.exp(ev.deltaY * 0.0011) });
  }, { passive: false });
  canvas.addEventListener("pointerleave", () => ui.setTip(null, null));

  el("menu-view").addEventListener("click", (e) => menu(e.currentTarget, [
    { label: state.tour.active ? "Stop tour" : "Play tour", note: `${Math.round(tour.duration)}s`, onPick: () => toggleTour() },
    { label: "Reset camera", note: "R", onPick: () => actions.resetView() },
    { divider: true },
    { label: state.dim === "2d" ? "3D terrain" : "2D flat map", onPick: () => actions.setDim(state.dim === "2d" ? "3d" : "2d") },
    { label: state.layers.labels.on ? "Hide labels" : "Show labels", onPick: () => actions.toggleLayer("labels") },
  ]));
  el("menu-share").addEventListener("click", (e) => menu(e.currentTarget, [
    { label: "Copy link to this atlas", onPick: () => { navigator.clipboard?.writeText(location.href); toast("Link copied"); } },
    { label: "Open bookmarker ↗", onPick: () => { location.href = "/"; } },
  ]));
  el("library-pick").addEventListener("click", (e) => menu(e.currentTarget, [
    { label: "Demo library", note: `${PalaceData.demoRows().length}`, onPick: () => swapLibrary(loadDemo()) },
    { label: "My library", note: "read-only", onPick: () => mine() },
  ]));

  addEventListener("keydown", (ev) => {
    if (ev.key === "t") toggleTour();
    if (ev.key === "r") actions.resetView();
    if (ev.key === "m") actions.setDim(state.dim === "2d" ? "3d" : "2d");
    if (ev.key === " ") { ev.preventDefault(); actions.togglePlay(); }
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
  state.hidden.clear(); state.groupOpacity.clear();
  location.hash = "";
  rebuild();
}

/* ── build ──────────────────────────────────────────────────────────────── */
function rebuild() {
  if (scene) {
    scene.renderer.dispose();
    el("scene").replaceWith(Object.assign(document.createElement("canvas"), { id: "scene" }));
  }
  scene = new AtlasScene({ canvas: el("scene"), labelHost: el("labels"), atlas, layout, state, capture: CAPTURE }).init();
  // The whole-library reading trail is on by default, so the overview carries
  // the same kind of dated path the reference draws over its terrain.
  scene.buildTrail(readingTrail(layout, { count: 7 }));
  scene.rebuildTrailLabels();
  tour = new Tour({ atlas, layout, ground: (x, z) => scene.groundAt(x, z) });
  ui = new AtlasUI({ atlas, state, actions });
  ui.build();
  scene.setCamera(tour.cameraAt(0.0));
  scene.setCamera({ tx: 0, ty: scene.groundAt(0, 0) + 70, tz: 0, az: 0.5, dist: 930, pol: 1.145 });
  resize();
}

function resize() {
  const stage = el("stage");
  scene.resize(stage.clientWidth, stage.clientHeight);
  ui.drawCharts();
}

/* ── tour playback ──────────────────────────────────────────────────────── */
function toggleTour() {
  state.tour.active = !state.tour.active;
  state.tour.t = 0;
  if (!state.tour.active) { ui.setLower(null); actions.resetView(); }
}

function applyTourState(t) {
  const s = tour.stateAt(t);
  const modeChanged = s.mode !== state.mode;
  state.mode = s.mode;
  state.tab = s.tab;
  if (state.dim !== s.dim) { state.dim = s.dim; scene.setDim(s.dim); }
  state.focus = s.focus;
  state.time = s.time;
  state.selection = s.selection ? s.selection.item : null;
  if (modeChanged) scene.setColorMode(s.mode === "sources" ? "sources" : "topics");
  const trailIds = s.trail.map((m) => m.id).join(",");
  if (trailIds !== scene._trailIds) {
    scene._trailIds = trailIds;
    scene.buildTrail(s.trail);
    scene.rebuildTrailLabels();
  }
  scene.setTimeFilter(state.time);
  scene.selectMarker(s.selection || null);
  scene.applyLayers();
  scene.setCamera(tour.cameraAt(t));
  ui.buildLayers();
  ui.refresh();
  ui.setLower(s.lower.title, s.lower.sub);
  if (s.hover) {
    const v = new THREE.Vector3(s.hover.x, s.hover.y + s.hover.height + 4, s.hover.z).project(scene.activeCamera());
    ui.setTip({ x: (v.x * 0.5 + 0.5) * scene.width, y: (-v.y * 0.5 + 0.5) * scene.height }, s.hover.item);
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
      ui.refresh();
      if (state.time >= 1) state.playing = false;
    }
  }
  scene.render();
  updateReadouts();
  scene.measure(dt);
  requestAnimationFrame(frame);
}

function updateReadouts() {
  const c = scene.cam;
  ui.setZoom(`${(1480 / c.dist).toFixed(1)}×`);
  ui.setCompass(c.az);
  const vFov = (scene.camera.fov * Math.PI) / 180;
  const perPx = state.dim === "2d"
    ? (scene.ortho.top - scene.ortho.bottom) / Math.max(1, scene.height)
    : (2 * Math.tan(vFov / 2) * c.dist) / Math.max(1, scene.height);
  const nice = [10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000];
  const want = perPx * 130;
  const pick = nice.filter((n) => n <= want).pop() || nice[0];
  ui.setScale(Math.round(pick / perPx), `${Math.round(pick / 2)}`, `${pick} m`);
}

/* ── capture hooks ──────────────────────────────────────────────────────── */
function installCapture() {
  const api = {
    ready: false,
    sync() { scene.render(); return true; },
    duration() { return tour.duration; },
    beats() { return tour.plan.beats.map((b) => ({ id: b.id, start: b.start, end: b.end })); },
    renderAt(t) {
      state.tour.active = true;
      state.tour.t = t;
      applyTourState(t);
      scene.render();
      return t;
    },
    pose(name, opts = {}) {
      const times = { overview: 4.5, timeline: 15.5, region: 23.5, detail: 31.2, sources: 36.5, trail: 43.5, map2d: 50.5 };
      const t = times[name] != null ? times[name] : 4.5;
      api.renderAt(t);
      if (name !== "trail") ui.setLower(null);
      if (name === "overview") {
        state.time = 1;
        state.tab = "overview";
        scene.setTimeFilter(1);
        ui.setLower(null);
        // The hero framing looks down into the atlas rather than out to the
        // horizon, so the viewport is terrain and data, not sky.
        scene.setCamera({ tx: 0, ty: scene.groundAt(0, 0) + 70, tz: 0, dist: 930, pol: 1.145, az: 0.5 });
        ui.refresh();
      }
      if (name === "region" && opts.topic) {
        const r = regionById(layout, opts.topic);
        if (r) {
          state.focus = r.id;
          scene.buildTrail(readingTrail(layout, { regionId: r.id, count: 8 }));
          scene.rebuildTrailLabels();
          scene.applyLayers();
          scene.setCamera({ tx: r.x, ty: scene.groundAt(r.x, r.z) + 24, tz: r.z, dist: Math.max(250, r.r * 3.0), pol: 1.15, az: Math.atan2(r.x, r.z) - 0.4 });
          ui.buildLayers();
          ui.refresh();
        }
      }
      scene.render();
      updateReadouts();
      return name;
    },
    state() {
      return {
        mode: state.mode, tab: state.tab, dim: state.dim, focus: state.focus,
        time: state.time, markers: scene.shownMarkers,
        selection: state.selection ? state.selection.title : null,
        label: atlas.label, total: atlas.total,
        trees: scene.forest.count, rocks: scene.rocks.count,
        relief: scene.heightRange(),
      };
    },
  };
  window.palace = api;
  return api;
}

/* ── boot ───────────────────────────────────────────────────────────────── */
function boot() {
  try {
    atlas = loadDemo();
    layout = computeLayout(atlas);
    rebuild();
    wireCanvas();
    addEventListener("resize", resize);
    if (CAPTURE) el("boot").remove();
    else { el("boot").classList.add("gone"); setTimeout(() => el("boot").remove(), 600); }
    if (CAPTURE) {
      const api = installCapture();
      scene.render();
      updateReadouts();
      api.ready = true;
      document.documentElement.dataset.capture = "ready";
      el("vp-hint").hidden = true;
    } else {
      requestAnimationFrame((t) => { last = t; frame(t); });
      if (params.has("tour")) toggleTour();
      if (PalaceData.readSession(localStorage)) el("library-pick").title = "Signed in — switch to your own library";
    }
  } catch (err) {
    console.error(err);
    el("boot").remove();
    el("fallback").hidden = false;
  }
}

if (document.createElement("canvas").getContext("webgl2")) boot();
else { el("boot").remove(); el("fallback").hidden = false; }
