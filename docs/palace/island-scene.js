/* island-scene.js — assembles the world and draws it.

   Owns the renderer, the one shared uniform block every shader reads, the
   build/dispose cycle (a library switch tears down every geometry, material
   and texture it made), the HTML zone labels projected into the frame, marker
   picking, and the quality ladder used outside capture mode. */
import * as THREE from "three";
import { buildField, buildTerrain, detailTexture, groundAt, sampleGrid, SUN_AZ, SUN_EL } from "./island-terrain.js";
import { buildStacks, buildTemple, buildBoulders } from "./island-props.js";
import { buildFlora, setFloraDensity } from "./island-flora.js";
import { buildOcean, buildInland, buildFalls, depthTexture } from "./island-water.js";
import { buildSky, buildMist, buildSmoke, buildSpray } from "./island-sky.js";
import { buildMarkers, buildSelectRing } from "./island-markers.js";
import { TERRAIN_HALF, STACKS, clamp, mix, zoneBySite } from "./island-layout.js";

/* THREE.ColorManagement is on, so `new THREE.Color(hex)` already lands in the
   renderer's linear working space; converting again here used to darken every
   light and every fog colour by a second gamma. */
const lin = (hex, scale = 1) => new THREE.Color(hex).multiplyScalar(scale);

export class IslandScene {
  constructor({ canvas, labelHost, layout, capture = false }) {
    this.canvas = canvas;
    this.labelHost = labelHost;
    this.layout = layout;
    this.capture = capture;
    this.width = 1; this.height = 1;
    this.quality = { pixelRatio: 1, flora: 1, tier: "high" };
    this.labels = [];
    this.selected = null;
    this.disposables = [];
  }

  init() {
    const renderer = new THREE.WebGLRenderer({
      canvas: this.canvas, antialias: !this.capture, alpha: false,
      powerPreference: "high-performance", stencil: false,
    });
    renderer.setPixelRatio(this.capture ? 1 : Math.min(window.devicePixelRatio || 1, 2));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.0;
    renderer.setClearColor(0x9fb0b4, 1);
    this.renderer = renderer;

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(40, 16 / 9, 2, 120000);

    const sun = new THREE.Vector3(
      Math.cos(SUN_AZ) * Math.cos(SUN_EL), Math.sin(SUN_EL), Math.sin(SUN_AZ) * Math.cos(SUN_EL),
    ).normalize();
    this.sun = sun;

    this.detail = detailTexture(256);
    this.uniforms = {
      uSunDir: { value: sun },
      uSunColor: { value: lin("#ffeeda", 1.72) },
      uSkyColor: { value: lin("#8ab6dc", 0.56) },
      uSkyMid: { value: lin("#86aec6", 1.0) },
      uZenith: { value: lin("#0e3860", 1.0) },
      uGroundColor: { value: lin("#35402a", 0.2) },
      uFogColor: { value: lin("#93a8ad", 1.0) },
      uHazeColor: { value: lin("#e4e0d2", 1.0) },
      uSunHaze: { value: lin("#ffd6a2", 1.0) },
      uFogDensity: { value: 0.000058 },
      uFogHeight: { value: 390 },
      uTime: { value: 0 },
      uExposure: { value: 0.70 },
      uDetail: { value: this.detail },
      uHalf: { value: TERRAIN_HALF },
      uDeep: { value: lin("#04171f", 1) },
      uShallow: { value: lin("#29b0a0", 1) },
      uFoam: { value: lin("#e9efe9", 1) },
      uSway: { value: 0.9 },
      uDepth: { value: null },
    };
    this.build();
    this.buildLabels();
    return this;
  }

  build() {
    const t0 = performance.now();
    const u = this.uniforms;
    const field = buildField(this.layout, this.capture ? 449 : 449);
    this.field = field;
    u.uDepth.value = depthTexture(field, STACKS);
    this.disposables.push(u.uDepth.value);

    const root = new THREE.Group();
    root.name = "island";
    this.root = root;

    this.sky = buildSky(u);
    this.terrain = buildTerrain(field, u, this.layout.clearings);
    this.stacks = buildStacks(field, u);
    this.boulders = buildBoulders(field, this.layout, u);
    const templeZone = zoneBySite(this.layout, "temple");
    this.temple = buildTemple(field, u, templeZone || { x: 150, z: 450 });
    this.flora = buildFlora(field, this.layout, u, this.stacks.userData.list);
    this.oceanFar = buildOcean(field, u, { inner: false });
    this.oceanNear = buildOcean(field, u, { inner: true });
    this.inland = buildInland(field, u);
    this.falls = buildFalls(field, u);
    this.mist = buildMist(field, this.layout, u, (x, z) => groundAt(field, x, z));
    const volcanoZone = zoneBySite(this.layout, "volcano");
    this.smoke = buildSmoke(u, volcanoZone || { x: -150, z: -330 });
    this.spray = buildSpray(u);
    this.markers = buildMarkers(field, this.layout, u);
    this.selectRing = buildSelectRing(u);

    for (const o of [this.sky, this.oceanFar, this.oceanNear, this.terrain, this.stacks, this.boulders,
      this.temple, this.flora, this.inland, this.falls, this.markers, this.selectRing,
      this.mist, this.spray, this.smoke]) root.add(o);
    this.scene.add(root);

    this.stats = {
      buildMs: Math.round(performance.now() - t0),
      tris: Math.round((this.terrain.userData.tris + this.stacks.userData.tris + this.boulders.userData.tris
        + this.temple.userData.tris + this.flora.userData.total * 40) / 1000),
      flora: this.flora.userData.counts,
      markers: this.layout.markers.length,
    };
  }

  dispose() {
    const seen = new Set();
    this.root?.traverse((o) => {
      if (o.geometry && !seen.has(o.geometry)) { seen.add(o.geometry); o.geometry.dispose(); }
      const mats = Array.isArray(o.material) ? o.material : o.material ? [o.material] : [];
      for (const m of mats) if (!seen.has(m)) { seen.add(m); m.dispose(); }
    });
    if (this.root) this.scene.remove(this.root);
    for (const d of this.disposables) d.dispose?.();
    this.disposables = [];
    this.clearLabels();
  }

  destroy() {
    this.dispose();
    this.detail?.dispose();
    this.renderer?.dispose();
  }

  /* ── labels ───────────────────────────────────────────────────────────── */
  buildLabels() {
    this.clearLabels();
    if (!this.labelHost) return;
    for (const zone of this.layout.zones) {
      const el = document.createElement("div");
      el.className = "zone-label";
      el.dataset.zone = zone.id;
      const name = document.createElement("span");
      name.className = "zl-name";
      name.textContent = zone.name;
      const count = document.createElement("span");
      count.className = "zl-count";
      count.textContent = String(zone.total);
      const place = document.createElement("small");
      place.textContent = zone.place;
      el.append(name, count, place);
      el.addEventListener("click", () => this.onLabelClick?.(zone));
      this.labelHost.appendChild(el);
      this.labels.push({ el, zone, pos: new THREE.Vector3(zone.x, zone.labelY, zone.z) });
    }
  }
  clearLabels() {
    for (const l of this.labels) l.el.remove();
    this.labels = [];
  }

  updateLabels() {
    const cam = this.camera;
    const p = new THREE.Vector3();
    // biggest zones place first; a label that would collide steps aside
    const order = [...this.labels].sort((a, b) => b.zone.total - a.zone.total);
    const taken = [];
    for (const l of order) {
      p.copy(l.pos).project(cam);
      const behind = p.z > 1;
      const x = (p.x * 0.5 + 0.5) * this.width;
      const y = (-p.y * 0.5 + 0.5) * this.height;
      const dist = l.pos.distanceTo(cam.position);
      const inside = x > 40 && x < this.width - 40 && y > 30 && y < this.height - 30;
      let show = !behind && inside && dist < 6800 && this.showLabels !== false
        && (this.onlyZone == null || this.onlyZone === l.zone.index);
      if (show) {
        const w = Math.max(96, l.el.offsetWidth), h = Math.max(26, l.el.offsetHeight);
        const box = { x0: x - w / 2, x1: x + w / 2, y0: y - h, y1: y + 4 };
        const hits = (o) => !(box.x1 < o.x0 - 6 || box.x0 > o.x1 + 6 || box.y1 < o.y0 - 4 || box.y0 > o.y1 + 4);
        if (taken.some(hits)) show = false; else taken.push(box);
      }
      l.el.style.display = show ? "" : "none";
      if (!show) continue;
      const fade = clamp(1 - (dist - 3400) / 2600, 0.15, 1) * clamp((dist - 90) / 160, 0, 1);
      l.el.style.transform = `translate(-50%, -100%) translate(${Math.round(x)}px, ${Math.round(y)}px)`;
      l.el.style.opacity = fade.toFixed(3);
      l.el.classList.toggle("is-focus", this.focusZone === l.zone.index);
    }
  }

  /* ── camera ───────────────────────────────────────────────────────────── */
  setView(view) {
    const cam = this.camera;
    cam.position.set(view.pos.x, view.pos.y, view.pos.z);
    cam.up.set(0, 1, 0);
    cam.lookAt(view.target.x, view.target.y, view.target.z);
    if (view.roll) cam.rotateZ(view.roll);
    // framings are authored for a wide frame; on a narrow one, widen the
    // vertical angle so the same island still fits across the screen
    const ref = 16 / 9, aspect = this.width / Math.max(1, this.height);
    const fov = aspect >= ref ? view.fov
      : Math.min(72, 2 * Math.atan(Math.tan((view.fov * Math.PI) / 360) * Math.pow(ref / aspect, 0.55)) * (180 / Math.PI));
    if (cam.fov !== fov) cam.fov = fov;
    cam.updateProjectionMatrix();
    this.view = view;
  }

  groundAt(x, z) { return groundAt(this.field, x, z); }

  /* ── markers ──────────────────────────────────────────────────────────── */
  markerScreen(marker) {
    const p = new THREE.Vector3(marker.x, marker.worldY ?? marker.y + 8, marker.z).project(this.camera);
    return { x: (p.x * 0.5 + 0.5) * this.width, y: (-p.y * 0.5 + 0.5) * this.height, z: p.z };
  }

  pick(px, py, radius = 26) {
    let best = null, bestD = radius;
    for (const m of this.layout.markers) {
      const s = this.markerScreen(m);
      if (s.z > 1) continue;
      const d = Math.hypot(s.x - px, s.y - py);
      if (d < bestD) { bestD = d; best = m; }
    }
    return best;
  }

  setSelected(marker) {
    this.selected = marker || null;
    const ring = this.selectRing;
    if (!marker) { ring.visible = false; return; }
    ring.visible = true;
    ring.position.set(marker.x, marker.y + 1.4, marker.z);
    const s = 10;
    ring.scale.set(s, s, s);
  }

  /* ── quality ──────────────────────────────────────────────────────────── */
  setQuality(tier) {
    const tiers = {
      high: { pixelRatio: Math.min(window.devicePixelRatio || 1, 2), flora: 1 },
      mid: { pixelRatio: 1, flora: 0.68 },
      low: { pixelRatio: 0.8, flora: 0.42 },
    };
    const q = tiers[tier] || tiers.high;
    this.quality = { ...q, tier };
    this.renderer.setPixelRatio(this.capture ? 1 : q.pixelRatio);
    setFloraDensity(this.flora, this.capture ? 1 : q.flora);
    this.resize(this.width, this.height);
    return this.quality;
  }

  resize(w, h) {
    this.width = Math.max(1, w); this.height = Math.max(1, h);
    this.renderer.setSize(this.width, this.height, false);
    this.camera.aspect = this.width / this.height;
    this.camera.updateProjectionMatrix();
  }

  setTime(t) { this.uniforms.uTime.value = t; }

  /* Where the sun lands on screen, so the overlay bloom can sit on it. */
  sunScreen() {
    const p = new THREE.Vector3().copy(this.sun).multiplyScalar(40000).add(this.camera.position).project(this.camera);
    return { x: (p.x * 0.5 + 0.5) * 100, y: (-p.y * 0.5 + 0.5) * 100, front: p.z < 1 };
  }

  render() {
    this.renderer.render(this.scene, this.camera);
    this.updateLabels();
  }
}
