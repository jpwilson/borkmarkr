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
import { buildBirds } from "./island-fauna.js";
import { Post } from "./island-post.js";
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
    this.quality = { pixelRatio: 1, flora: 1, particles: 1, post: 1, tier: "high" };
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
    /* The grade. Materials write linear radiance into its buffer; with it
       switched off they tone-map straight to the canvas instead, so the low
       tier loses the bloom and the shafts and nothing else. */
    this.post = new Post(renderer, { capture: this.capture });

    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(40, 16 / 9, 2, 120000);

    const sun = new THREE.Vector3(
      Math.cos(SUN_AZ) * Math.cos(SUN_EL), Math.sin(SUN_EL), Math.sin(SUN_AZ) * Math.cos(SUN_EL),
    ).normalize();
    this.sun = sun;

    this.detail = detailTexture(256);
    /* Golden hour, keyed hard: a hot low sun, a cool sky fill that owns the
       shadows, and a horizon haze that is nearly the colour of the sun. The
       separation between those two is the whole look — a single grey fill
       for both is what made this read as an overcast afternoon. */
    this.uniforms = {
      uSunDir: { value: sun },
      uSunColor: { value: lin("#ffd3a0", 2.45) },
      uSunDeep: { value: lin("#ff9a4e", 1.0) },
      uSkyColor: { value: lin("#74a6d8", 0.66) },
      uSkyMid: { value: lin("#86b4d8", 1.0) },
      uZenith: { value: lin("#0d2f58", 1.0) },
      uGroundColor: { value: lin("#4a3c22", 0.30) },
      uFogColor: { value: lin("#8ba3ad", 1.0) },
      uHazeColor: { value: lin("#f4dcb8", 1.0) },
      uSunHaze: { value: lin("#ffb468", 1.0) },
      uFogDensity: { value: 0.000074 },
      uFogHeight: { value: 340 },
      uTime: { value: 0 },
      uExposure: { value: 0.70 },
      uDetail: { value: this.detail },
      uHalf: { value: TERRAIN_HALF },
      uDeep: { value: lin("#031420", 1) },
      uShallow: { value: lin("#2ec6b4", 1) },
      uFoam: { value: lin("#eef4ee", 1) },
      uSway: { value: 1.0 },
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
    this.birds = buildBirds(field, this.layout, u);

    for (const o of [this.sky, this.oceanFar, this.oceanNear, this.terrain, this.stacks, this.boulders,
      this.temple, this.flora, this.inland, this.falls, this.markers, this.selectRing,
      this.birds, this.mist, this.spray, this.smoke]) root.add(o);
    this.scene.add(root);

    this.stats = {
      buildMs: Math.round(performance.now() - t0),
      // filled in from renderer.info after the first frame: an estimate that
      // guessed 40 triangles per crown while the geometry carried 120, and
      // left out the water and the markers entirely, was not worth reporting
      tris: 0,
      flora: this.flora.userData.counts,
      markers: this.layout.markers.length,
      drawn: this.layout.markers.length,
      total: this.layout.total,
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
    this.post?.dispose();
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
      // measure before deciding: an element hidden with display:none reports
      // zero, so the collision test would fall back to a guess on the first
      // frame and to the real box on the second
      const w = Math.max(96, l.el.offsetWidth), h = Math.max(26, l.el.offsetHeight);
      if (show) {
        const box = { x0: x - w / 2, x1: x + w / 2, y0: y - h, y1: y + 4 };
        const hits = (o) => !(box.x1 < o.x0 - 6 || box.x0 > o.x1 + 6 || box.y1 < o.y0 - 4 || box.y0 > o.y1 + 4);
        if (taken.some(hits)) show = false; else taken.push(box);
      }
      // visibility, not display: the box stays measurable
      l.el.classList.toggle("is-off", !show);
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
    // project() and sunScreen() both read matrixWorldInverse; without this
    // they would use the pose from the previous render, so a capture overlay
    // could belong to a different camera than the pixels under it
    cam.updateMatrixWorld(true);
    this.view = view;
  }

  groundAt(x, z) { return groundAt(this.field, x, z); }

  /* ── markers ──────────────────────────────────────────────────────────── */
  markerScreen(marker) {
    const p = new THREE.Vector3(marker.x, marker.worldY ?? marker.y + 8, marker.z).project(this.camera);
    return { x: (p.x * 0.5 + 0.5) * this.width, y: (-p.y * 0.5 + 0.5) * this.height, z: p.z };
  }

  /* Is there a mountain between the camera and this camp? March the
     heightfield along the ray; screen distance alone will happily select a
     bookmark that is not on screen at all, because it is behind a ridge. */
  visible(marker) {
    const cam = this.camera.position;
    const tx = marker.x, ty = marker.worldY ?? marker.y + 8, tz = marker.z;
    const dx = tx - cam.x, dy = ty - cam.y, dz = tz - cam.z;
    const len = Math.hypot(dx, dy, dz);
    if (len < 1) return true;
    const steps = Math.min(90, Math.max(12, Math.round(len / 24)));
    for (let i = 1; i < steps; i++) {
      const u = i / steps;
      const y = cam.y + dy * u;
      // a few metres of slack so standing on the ground does not self-occlude
      if (y < groundAt(this.field, cam.x + dx * u, cam.z + dz * u) - 4) return false;
    }
    return true;
  }

  pick(px, py, radius = 26) {
    let best = null, bestD = radius;
    for (const m of this.layout.markers) {
      const s = this.markerScreen(m);
      if (s.z > 1) continue;
      const d = Math.hypot(s.x - px, s.y - py);
      if (d >= bestD) continue;
      if (!this.visible(m)) continue;
      bestD = d; best = m;
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
    // particles are the other half of the cost: 236 large mist quads plus the
    // smoke column and the spray are all full-screen overdraw on a slow GPU,
    // and dropping them costs far less of the look than dropping the jungle
    const tiers = {
      high: { pixelRatio: Math.min(window.devicePixelRatio || 1, 2), flora: 1, particles: 1, post: 1 },
      mid: { pixelRatio: 1, flora: 0.7, particles: 0.5, post: 1 },
      low: { pixelRatio: 0.8, flora: 0.42, particles: 0, post: 0 },
    };
    const q = tiers[tier] || tiers.high;
    this.quality = { ...q, tier };
    this.renderer.setPixelRatio(this.capture ? 1 : q.pixelRatio);
    setFloraDensity(this.flora, this.capture ? 1 : q.flora);
    this.setParticles(this.capture ? 1 : q.particles);
    this.post.enabled = q.post > 0;
    if (this.birds) this.birds.visible = q.particles > 0 || q.post > 0;
    this.resize(this.width, this.height);
    return this.quality;
  }

  setParticles(level) {
    const hi = level >= 1;
    // the low banks are the ones doing the work; the mid and high layers are
    // the first thing a slow GPU can afford to lose
    for (const m of this.mist?.children || []) m.visible = level > 0 && (hi || m.name === "mist-low");
    if (this.smoke) this.smoke.visible = level > 0;
    if (this.spray) this.spray.visible = hi;
  }

  resize(w, h) {
    this.width = Math.max(1, w); this.height = Math.max(1, h);
    this.renderer.setSize(this.width, this.height, false);
    this.post.setSize(this.width, this.height);
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
    const s = this.sunScreen();
    this.post.render(this.scene, this.camera, { x: s.x / 100, y: 1 - s.y / 100, front: s.front });
    const info = this.post.info || this.renderer.info.render;
    this.stats.tris = Math.round(info.triangles / 1000);
    this.stats.calls = info.calls;
    this.updateLabels();
  }
}
