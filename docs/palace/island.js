/* island.js — entry point.

   Loads the library, builds the island, drives one state object, and in
   ?capture mode exposes window.palace: a deterministic hook set where
   renderAt(t) alone decides the camera, the selection, the HUD and every
   animated thing in the frame. No wall clock runs in capture mode. */
import * as THREE from "three";
import { computeIsland, zoneById, clamp, mix, heightAt } from "./island-layout.js";
import { sampleGrid, groundAt } from "./island-terrain.js";
import { IslandScene } from "./island-scene.js";
import { IslandUI } from "./island-ui.js";
import { Tour, overviewPose, zonePose, markerPose, approachPose, mapPose, heroMarker } from "./island-tour.js";

const params = new URLSearchParams(location.search);
const CAPTURE = params.has("capture");
const STRESS = params.has("stress");
const REDUCED = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
const el = (id) => document.getElementById(id);

const state = {
  atlas: null, layout: null,
  tour: { playing: false, t: 0 },
  focus: null,
  selection: null,
  flight: null,
};
let scene, ui, tour;
let orbit = null;

/* ── data ───────────────────────────────────────────────────────────────── */
const loadDemo = () => (STRESS ? PalaceData.stressAtlas(TAXONOMY) : PalaceData.demoAtlas(TAXONOMY));

async function loadMine() {
  const { rows, customTopics, truncated, email } = await PalaceData.loadOwnLibrary({
    storage: localStorage, fetch: window.fetch.bind(window),
  });
  return PalaceData.buildAtlas(rows, {
    taxonomy: TAXONOMY, customTopics, demo: false, truncated, label: email || "My library",
  });
}

/* ── camera ─────────────────────────────────────────────────────────────── */
function viewFromOrbit(o) {
  const sinPol = Math.sin(o.pol);
  return {
    pos: {
      x: o.target.x + Math.cos(o.az) * sinPol * o.dist,
      y: o.target.y + Math.cos(o.pol) * o.dist,
      z: o.target.z + Math.sin(o.az) * sinPol * o.dist,
    },
    target: { ...o.target }, fov: o.fov, roll: 0,
  };
}
function orbitFromView(view) {
  const dx = view.pos.x - view.target.x, dy = view.pos.y - view.target.y, dz = view.pos.z - view.target.z;
  const dist = Math.max(28, Math.hypot(dx, dy, dz));
  return {
    target: { ...view.target }, dist,
    pol: Math.acos(clamp(dy / dist, -1, 1)),
    az: Math.atan2(dz, dx), fov: view.fov,
  };
}
const lerpView = (a, b, u) => ({
  pos: { x: mix(a.pos.x, b.pos.x, u), y: mix(a.pos.y, b.pos.y, u), z: mix(a.pos.z, b.pos.z, u) },
  target: { x: mix(a.target.x, b.target.x, u), y: mix(a.target.y, b.target.y, u), z: mix(a.target.z, b.target.z, u) },
  fov: mix(a.fov, b.fov, u), roll: mix(a.roll || 0, b.roll || 0, u),
});

function applyView(view) {
  scene.setView(view);
  const s = scene.sunScreen();
  const bloom = el("sunbloom");
  if (bloom) {
    bloom.style.left = `${s.x}%`;
    bloom.style.top = `${s.y}%`;
    bloom.style.opacity = s.front ? "1" : "0";
  }
  ui?.setCompass(Math.atan2(view.target.z - view.pos.z, view.target.x - view.pos.x) + Math.PI / 2);
  ui?.setCamDot(view.pos.x, view.pos.z);
}

function flyTo(view, ms = 1500) {
  if (CAPTURE || REDUCED) { orbit = orbitFromView(view); applyView(view); return; }
  state.flight = { from: scene.view ? { ...scene.view } : view, to: view, start: performance.now(), ms };
}

/* ── actions ────────────────────────────────────────────────────────────── */
const actions = {
  toggleTour() {
    state.tour.playing = !state.tour.playing;
    if (state.tour.playing) {
      state.flight = null;
      if (state.tour.t >= tour.duration - 0.05) state.tour.t = 0;
    } else {
      orbit = orbitFromView(scene.view);
      ui.setTour({ playing: false, t: state.tour.t, duration: tour.duration, label: "", detail: "" });
    }
    ui.setTour({ playing: state.tour.playing, t: state.tour.t, duration: tour.duration,
      label: state.tour.playing ? tour.beatAt(state.tour.t).label : "", detail: "" });
  },
  seek(frac) {
    state.tour.t = clamp(frac, 0, 1) * tour.duration;
    state.tour.playing = true;
    applyTour(state.tour.t);
  },
  select(marker) {
    state.selection = marker || null;
    scene.setSelected(marker);
    ui.showCard(marker);
    if (marker) {
      state.focus = marker.zone;
      ui.setFocus(marker.zone);
      scene.focusZone = marker.zone;
    }
  },
  flyToZone(zone) {
    if (state.tour.playing) actions.toggleTour();
    state.focus = zone.index;
    scene.focusZone = zone.index;
    ui.setFocus(zone.index);
    flyTo(zonePose(state.layout, zone, { offset: 0.55 }), 1700);
  },
  async mine() {
    try {
      ui.toast("Reading your library…");
      swapLibrary(await loadMine());
      ui.toast("Your island is built. Nothing was written — this page only reads.");
    } catch (err) {
      ui.toast(err && err.status === 401
        ? "Sign in at bookmarker.lol first — Library Island only reads your saves."
        : (err && err.message) || "Couldn't read your library.");
    }
  },
};

/* ── tour playback ──────────────────────────────────────────────────────── */
function applyTour(t) {
  const s = tour.stateAt(t);
  applyView(s);
  scene.setTime(t);
  scene.focusZone = s.zone;
  scene.onlyZone = s.beat === "overview" || s.beat === "pullout" || s.beat === "approach" || s.beat === "rise" ? null : s.zone;
  if (s.zone != null) ui.setFocus(s.zone);
  const marker = s.marker ? state.layout.byId.get(s.marker) : null;
  if ((state.selection?.id || null) !== (marker?.id || null)) {
    state.selection = marker || null;
    scene.setSelected(marker);
    ui.showCard(marker);
  }
  if (marker) {
    const p = scene.markerScreen(marker);
    ui.showTip(marker, p.x, p.y - 14);
  } else ui.showTip(null);
  ui.setTour({ playing: state.tour.playing, t, duration: tour.duration, label: s.beatLabel, detail: s.beatDetail });
  return s;
}

/* ── build / rebuild ────────────────────────────────────────────────────── */
function build() {
  state.layout = computeIsland(state.atlas);
  tour = new Tour(state.layout);
  scene = new IslandScene({ canvas: el("scene"), labelHost: el("labels"), layout: state.layout, capture: CAPTURE }).init();
  scene.onLabelClick = (zone) => actions.flyToZone(zone);
  ui = new IslandUI({ atlas: state.atlas, layout: state.layout, actions }).build();
  ui.drawMiniMap(scene.field, (x, z) => ({
    h: groundAt(scene.field, x, z),
    zone: sampleGrid(scene.field, scene.field.h, x, z) > 0 ? scene.field.zone[zoneIndexAt(scene.field, x, z)] : -1,
    shade: sampleGrid(scene.field, scene.field.shade, x, z),
    gap: sampleGrid(scene.field, scene.field.gap, x, z),
  }));
  resize();
  orbit = orbitFromView(overviewPose(state.layout, 0));
  applyView(viewFromOrbit(orbit));
}

function zoneIndexAt(field, x, z) {
  const { res, half, step } = field;
  const i = clamp(Math.round((x + half) / step), 0, res - 1);
  const j = clamp(Math.round((z + half) / step), 0, res - 1);
  return j * res + i;
}

function swapLibrary(next) {
  state.atlas = next;
  state.selection = null; state.focus = null;
  state.tour.playing = false; state.tour.t = 0; state.flight = null;
  scene?.destroy();
  ui?.destroy();
  const fresh = document.createElement("canvas");
  fresh.id = "scene";
  el("scene").replaceWith(fresh);
  build();
}

function resize() {
  scene.resize(window.innerWidth, window.innerHeight);
}

/* ── input ──────────────────────────────────────────────────────────────── */
function wire() {
  window.addEventListener("resize", () => { resize(); if (scene.view) applyView(scene.view); });
  const canvas = () => el("scene");
  let drag = null, moved = 0;
  const stage = el("stage");
  stage.addEventListener("pointerdown", (e) => {
    drag = { x: e.clientX, y: e.clientY, az: orbit.az, pol: orbit.pol };
    moved = 0;
    stage.setPointerCapture(e.pointerId);
  });
  stage.addEventListener("pointermove", (e) => {
    if (drag) {
      if (state.tour.playing) actions.toggleTour();
      moved += Math.abs(e.movementX) + Math.abs(e.movementY);
      orbit.az = drag.az - (e.clientX - drag.x) * 0.0042;
      orbit.pol = clamp(drag.pol - (e.clientY - drag.y) * 0.003, 0.12, 1.42);
      state.flight = null;
      applyView(viewFromOrbit(orbit));
      return;
    }
    const hit = scene.pick(e.clientX, e.clientY);
    stage.style.cursor = hit ? "pointer" : "grab";
    if (hit && hit !== state.selection) ui.showTip(hit, e.clientX, e.clientY - 6);
    else if (!hit) ui.showTip(state.selection && state.tour.playing ? state.selection : null);
  });
  stage.addEventListener("pointerup", (e) => {
    const wasDrag = moved > 6;
    drag = null;
    if (wasDrag) return;
    const hit = scene.pick(e.clientX, e.clientY);
    if (hit) {
      if (state.tour.playing) actions.toggleTour();
      actions.select(hit);
      flyTo(markerPose(state.layout, hit, { dist: 46 }), 1200);
    } else actions.select(null);
  });
  stage.addEventListener("wheel", (e) => {
    e.preventDefault();
    if (state.tour.playing) actions.toggleTour();
    orbit.dist = clamp(orbit.dist * (1 + Math.sign(e.deltaY) * 0.12), 42, 7200);
    state.flight = null;
    applyView(viewFromOrbit(orbit));
  }, { passive: false });
  window.addEventListener("keydown", (e) => {
    if (e.key === "Escape") actions.select(null);
    if (e.key === " " && e.target === document.body) { e.preventDefault(); actions.toggleTour(); }
  });
}

/* ── frame loop (never runs in capture mode) ────────────────────────────── */
let last = 0, slow = 0, fast = 0;
function frame(now) {
  requestAnimationFrame(frame);
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  scene.setTime(now / 1000);

  if (state.tour.playing) {
    state.tour.t += dt;
    if (state.tour.t >= tour.duration) { state.tour.t = tour.duration; state.tour.playing = false; orbit = orbitFromView(scene.view); }
    applyTour(state.tour.t);
  } else if (state.flight) {
    const u = clamp((now - state.flight.start) / state.flight.ms, 0, 1);
    const e = u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
    applyView(lerpView(state.flight.from, state.flight.to, e));
    if (u >= 1) { orbit = orbitFromView(state.flight.to); state.flight = null; }
  } else if (scene.view) {
    applyView(scene.view);
  }
  scene.render();

  // quality ladder: give up resolution and foliage before frame rate
  const fps = 1 / Math.max(dt, 1e-4);
  if (fps < 44) { slow++; fast = 0; } else if (fps > 56) { fast++; slow = 0; }
  if (slow > 24) {
    slow = 0;
    if (scene.quality.tier === "high") scene.setQuality("mid");
    else if (scene.quality.tier === "mid") scene.setQuality("low");
  }
}

/* ── capture hooks ──────────────────────────────────────────────────────── */
function installCapture() {
  const api = {
    ready: false,
    sync() {
      scene.render();
      scene.renderer.getContext().finish();
      return true;
    },
    duration() { return tour.duration; },
    beats() { return tour.plan.beats.map((b) => ({ id: b.id, start: b.start, end: b.end, label: b.label })); },
    /* The only way a frame is produced in capture mode. */
    renderAt(t) {
      state.tour.playing = true;
      state.tour.t = t;
      applyTour(t);
      scene.render();
      return t;
    },
    pose(name, opts = {}) {
      const L = state.layout;
      const at = (id, f) => {
        const beat = tour.plan.beats.find((b) => b.id === id || b.id.startsWith(id));
        return beat ? beat.start + beat.length * f : 2;
      };
      state.tour.playing = false;
      let caption = { label: "Library Island", detail: `${state.atlas.total} saves · ${L.zones.length} zones` };
      const show = (view, time, { zone = null, marker = null, labels = true, only = null } = {}) => {
        scene.setTime(time);
        scene.showLabels = labels;
        scene.onlyZone = only;
        scene.focusZone = zone;
        if (zone != null) ui.setFocus(zone); else ui.setFocus(-1);
        state.selection = marker;
        scene.setSelected(marker);
        ui.showCard(marker);
        applyView(view);
        if (marker) {
          const p = scene.markerScreen(marker);
          ui.showTip(marker, p.x, p.y - 14);
        } else ui.showTip(null);
        ui.setTour({ playing: false, t: time, duration: tour.duration, label: caption.label, detail: caption.detail });
        scene.render();
      };
      if (name === "approach") {
        caption = { label: "Open sea", detail: `${state.atlas.total} saves on one island` };
        show(approachPose(L, opts.u ?? 0.62), at("approach", 0.62));
      } else if (name === "map") {
        caption = { label: "Expedition map", detail: `${L.zones.length} zones · ${L.markers.length} markers` };
        show(mapPose(L), at("overview", 0.5), { labels: true });
      } else if (name === "zone") {
        const zone = (opts.topic && zoneById(L, opts.topic)) || L.zones[0];
        caption = { label: zone.place, detail: `${zone.name} · ${zone.total} saved · ${zone.biome}` };
        show(zonePose(L, zone, opts), at(`zone-${zone.siteId}`, 0.75), { zone: zone.index, only: zone.index });
      } else if (name === "marker") {
        const marker = (opts.id && L.byId.get(opts.id)) || heroMarker(L);
        caption = { label: L.zones[marker.zone].place, detail: marker.item.title };
        show(markerPose(L, marker, opts), at("marker", 0.9), { zone: marker.zone, marker, only: marker.zone });
      } else show(overviewPose(L, opts.spin || 0), at("overview", 0.8));
      return name;
    },
    /* Everything a frame depends on, so a determinism check can name the leak. */
    debug() {
      const v = scene.view;
      const r = (n) => Math.round(n * 1e3) / 1e3;
      return {
        cam: [v.pos.x, v.pos.y, v.pos.z, v.target.x, v.target.y, v.target.z, v.fov, v.roll || 0].map(r),
        time: r(scene.uniforms.uTime.value),
        selection: state.selection ? state.selection.id : "",
        focus: scene.focusZone,
        tip: el("tip").hidden ? "" : el("tip").textContent,
        beat: el("beat-label").textContent + "|" + el("beat-detail").textContent,
        track: el("track-fill").style.width,
        labels: [...document.querySelectorAll("#labels .zone-label")].filter((n) => n.style.display !== "none").length,
        bloom: `${el("sunbloom").style.left}|${el("sunbloom").style.top}|${el("sunbloom").style.opacity}`,
      };
    },
    stats() { return { ...scene.stats, duration: tour.duration }; },
    state() {
      return {
        label: state.atlas.label, total: state.atlas.total, demo: state.atlas.demo,
        zones: state.layout.zones.map((z) => ({ id: z.id, site: z.siteId, name: z.name, biome: z.biome, total: z.total, markers: z.markers.length })),
        markers: state.layout.markers.length,
        quality: scene.quality.tier,
      };
    },
    setQuality(tier) { return scene.setQuality(tier); },
  };
  window.palace = api;
  return api;
}

/* ── boot ───────────────────────────────────────────────────────────────── */
async function boot() {
  try {
    state.atlas = loadDemo();
    build();
    wire();
    if (CAPTURE) {
      el("boot").remove();
      const api = installCapture();
      if (document.fonts && document.fonts.ready) await document.fonts.ready;
      resize();
      api.pose("overview");
      api.ready = true;
      document.documentElement.dataset.capture = "ready";
    } else {
      el("boot").classList.add("gone");
      setTimeout(() => el("boot").remove(), 800);
      requestAnimationFrame((t) => { last = t; frame(t); });
      if (!REDUCED && !params.has("still")) setTimeout(() => { if (!state.selection && !state.flight) actions.toggleTour(); }, 900);
      if (PalaceData.readSession(localStorage)) el("mine").textContent = "View my library";
    }
  } catch (err) {
    console.error(err);
    el("boot")?.remove();
    el("fallback").hidden = false;
  }
}

if (document.createElement("canvas").getContext("webgl2")) boot();
else { el("boot").remove(); el("fallback").hidden = false; }
