/* The viewport: landscape, draped data, markers, labels, the flat 2D map and
   the camera rig. Nothing in here invents a number — positions come from
   atlas-layout.js and colours come from the model. */
import * as THREE from "three";
import { MAP, libraryBounds } from "./atlas-layout.js";
import {
  buildHeightField, buildTerrain, buildWater, buildSky,
  scatterTrees, scatterRocks, scatterScrub, drapeDisc, ribbon,
  applyDetailNormals, setDetailStrength, spreadMaterial, frontRing,
} from "./atlas-terrain.js";

const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
export const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

/* Where each stop sits along the route, as an arc-length fraction. Bookmarks
   are not evenly spaced, so this is the only honest way to turn a ride
   position into a stop — and the camera, the HUD and the selection all read
   it, which is what keeps them pointing at the same place. */
export function routeStops(curve, pins) {
  if (!curve || !pins || pins.length < 2) return pins && pins.length ? [0] : [];
  const SAMPLES = 400;
  const pts = [];
  for (let i = 0; i <= SAMPLES; i++) pts.push(curve.getPointAt(i / SAMPLES));
  return pins.map((pin) => {
    let best = 0, bestD = Infinity;
    for (let i = 0; i <= SAMPLES; i++) {
      const d = (pts[i].x - pin.x) ** 2 + (pts[i].z - pin.z) ** 2;
      if (d < bestD) { bestD = d; best = i; }
    }
    return best / SAMPLES;
  });
}
export function stopAtU(stopU, u) {
  if (!stopU.length) return 0;
  let best = 0, bestD = Infinity;
  for (let i = 0; i < stopU.length; i++) {
    const d = Math.abs(stopU[i] - u);
    if (d < bestD) { bestD = d; best = i; }
  }
  return best;
}

/* Every material the layer controls can touch remembers the opacity it was
   authored with, so a slider scales it instead of replacing it. */
function trackMaterial(mat) {
  mat.userData.baseOpacity = mat.opacity;
  mat.userData.baseTransparent = mat.transparent;
  return mat;
}
function setOpacity(root, value) {
  if (!root) return;
  const apply = (mat) => {
    if (!mat || mat.userData.baseOpacity == null) return;
    mat.opacity = mat.userData.baseOpacity * value;
    mat.transparent = mat.userData.baseTransparent || value < 0.999;
    mat.depthWrite = mat.userData.baseTransparent ? false : value > 0.55;
  };
  root.traverse((o) => {
    if (!o.material) return;
    (Array.isArray(o.material) ? o.material : [o.material]).forEach(apply);
  });
  if (root.isMaterial) apply(root);
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function stamp(ms) {
  const d = new Date(ms);
  return `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
}

function disposeTree(root) {
  root.traverse((o) => {
    if (o.geometry) o.geometry.dispose();
    if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach((m) => {
      for (const key of Object.keys(m)) {
        const v = m[key];
        if (v && v.isTexture) v.dispose();
      }
      m.dispose();
    });
  });
}

export class AtlasScene {
  constructor({ canvas, labelHost, atlas, layout, state, capture = false }) {
    Object.assign(this, { canvas, labelHost, atlas, layout, state, capture });
    this.labels = [];
    this.markers = layout.regions.flatMap((r) => r.markers);
    this.bounds = libraryBounds(layout);
    this.cam = { tx: 0, ty: 150, tz: 0, dist: 1000, az: 0.6, pol: 1.15 };
    this.quality = { tier: 0, pixelRatio: Math.min(capture ? 1 : 1.6, window.devicePixelRatio || 1), shadows: true, forest: 1, scrub: 1, rocks: true };
    this.frameTimes = [];
    this.hovered = null;
    this.markerScale = 1;
    this.width = 1;
    this.height = 1;
    this.follow = { on: false, u: 0, view: "eye", heading: 0, alt: 0, pitch: -12, elev: 0, point: new THREE.Vector3(), stop: 0 };
    // save times per region, sorted, so the spreading front can be found by
    // binary search every frame instead of a scan
    this.regionTimes = new Map(layout.regions.map((r) => [
      r.id, r.markers.map((m) => m.at).filter((t) => t != null).sort((a, b) => a - b),
    ]));
  }

  /* ── build ──────────────────────────────────────────────────────────── */
  init() {
    const renderer = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, alpha: false, powerPreference: "high-performance" });
    renderer.setPixelRatio(this.quality.pixelRatio);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.08;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer = renderer;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color("#ccd3d2");
    this.fog = new THREE.Fog("#ccd3d2", 1400, 3700);
    scene.fog = this.fog;
    this.scene = scene;

    this.camera = new THREE.PerspectiveCamera(42, 16 / 9, 2, 26000);
    this.ortho = new THREE.OrthographicCamera(-600, 600, 400, -400, -4000, 8000);
    // the reader cam: a narrower lens riding the reading trail, plus a plan
    // view straight down over the same point
    this.followCam = new THREE.PerspectiveCamera(34, 1.6, 1, 26000);
    this.followPlan = new THREE.OrthographicCamera(-120, 120, 80, -80, 1, 4000);

    // A low fill and one strong warm sun: the reference's value range comes
    // from real shadow, not from lifting everything into the midtones.
    const hemi = new THREE.HemisphereLight("#dbe5ea", "#8f8469", 0.6);
    scene.add(hemi);
    const sun = new THREE.DirectionalLight("#fff0d8", 3.6);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.bias = -0.0011;
    sun.shadow.normalBias = 0.5;
    sun.shadow.camera.near = 10;
    sun.shadow.camera.far = 3200;
    scene.add(sun, sun.target);
    this.sun = sun;
    scene.add(new THREE.AmbientLight("#e4e0d4", 0.17));

    this.field = buildHeightField(this.layout);
    this.world = new THREE.Group();
    scene.add(this.world);

    this.sky = buildSky();
    scene.add(this.sky);
    this.terrain = buildTerrain(this.field);
    applyDetailNormals(this.terrain.material, { scale: 1 / 4.6, strength: 0.6 });
    trackMaterial(this.terrain.material);
    this.water = buildWater();
    trackMaterial(this.water.material);
    this.forest = scatterTrees(this.field, { max: 120000 });
    this.forest.traverse((o) => { if (o.material) trackMaterial(o.material); });
    this.rocks = scatterRocks(this.field, { count: 3200 });
    trackMaterial(this.rocks.material);
    this.scrub = scatterScrub(this.field, { count: 110000 });
    this.scrub.traverse((o) => { if (o.material) trackMaterial(o.material); });
    this.world.add(this.terrain, this.water, this.forest, this.rocks, this.scrub);

    this.buildOverlays();
    this.buildMarkers();
    this.buildTrail([]);
    this.buildMap2D();
    this.buildLabels();
    this.applyLayers();
    this.setColorMode(this.state.mode === "sources" ? "sources" : "topics");
    this.setTimeFilter(this.state.time);
    this.setDim(this.state.dim);
    return this;
  }

  /* Translucent region tints, perimeter outlines and dashed district edges —
     fine lines laid on the ground, not tape floating above it. */
  buildOverlays() {
    this.tints = new THREE.Group();
    this.edges = new THREE.Group();
    this.world.add(this.tints, this.edges);
    this.regionNodes = new Map();

    for (const region of this.layout.regions) {
      const color = new THREE.Color(region.color);
      // the tint is a spreading front: clipped to how much of this region had
      // been saved by the date on the timeline cursor
      const spread = spreadMaterial(color);
      const fill = new THREE.Mesh(
        drapeDisc(region.x, region.z, region.boundary, this.field, { lift: 0.9, rings: 26 }),
        spread,
      );
      fill.renderOrder = 2;
      const line = new THREE.Mesh(
        ribbon(region.boundary, this.field, { width: 1.9, lift: 1.5, closed: true }),
        trackMaterial(new THREE.MeshBasicMaterial({
          color: color.clone().multiplyScalar(0.78), transparent: true, opacity: 0.95, depthWrite: false,
          side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -8, polygonOffsetUnits: -8,
        })),
      );
      line.renderOrder = 3;
      this.tints.add(fill, line);

      const dgroup = new THREE.Group();
      for (const district of region.districts) {
        const dash = new THREE.Mesh(
          ribbon(district.boundary, this.field, { width: 0.7, lift: 1.6, closed: true, dash: 6, gap: 5 }),
          trackMaterial(new THREE.MeshBasicMaterial({
            color: color.clone().multiplyScalar(0.62), transparent: true, opacity: 0.5, depthWrite: false,
            side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -9, polygonOffsetUnits: -9,
          })),
        );
        dash.renderOrder = 3;
        dgroup.add(dash);
      }
      this.edges.add(dgroup);
      this.regionNodes.set(region.id, { fill, line, dgroup, region, spread });
    }
    this.frontRings = new THREE.Group();
    this.frontMarks = [];
    this.world.add(this.frontRings);
  }

  /* Dashed perimeters for the dates this region was a third and two thirds
     full, with the date on a pin — the atlas equivalent of the reference's
     fire perimeter by hour. Only ever drawn for the region in focus. */
  buildFrontRings(regionId) {
    disposeTree(this.frontRings);
    this.frontRings.clear();
    this.frontMarks = [];
    this.frontRegion = regionId || null;
    const node = regionId ? this.regionNodes.get(regionId) : null;
    if (!node) return;
    const region = node.region;
    const times = this.regionTimes.get(regionId) || [];
    if (times.length < 6) return;
    const color = new THREE.Color(region.color);
    for (const share of [1 / 3, 2 / 3]) {
      const at = times[Math.max(0, Math.floor(times.length * share) - 1)];
      // the same outline the fill is clipped from, pulled in by sqrt(share),
      // so the ring sits exactly on the front it marks
      const ring = frontRing(region.x, region.z, region.boundary, share);
      const mesh = new THREE.Mesh(
        ribbon(ring, this.field, { width: 0.9, lift: 1.9, closed: true, dash: 5, gap: 5 }),
        trackMaterial(new THREE.MeshBasicMaterial({
          color: color.clone().multiplyScalar(1.15), transparent: true, opacity: 0.85, depthWrite: false,
          side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -10, polygonOffsetUnits: -10,
        })),
      );
      mesh.renderOrder = 4;
      mesh.userData.at = at;
      this.frontRings.add(mesh);
      this.frontMarks.push({ at, x: ring[14][0], z: ring[14][1], color: region.color });
    }
  }

  /* A historical perimeter only exists once the timeline has passed its
     date, and only while its region is actually being drawn. */
  updateFrontRings() {
    const id = this.frontRegion;
    const node = id ? this.regionNodes.get(id) : null;
    const key = id ? `reg:${id}` : null;
    const groupOp = key ? (this.state.groupOpacity.get(key) ?? 1) : 0;
    const live = !!node
      && this.state.layers.tints.on
      && this.state.layers.tints.opacity > 0.02
      && this.state.dim !== "2d"
      && !this.state.hidden.has(key)
      && groupOp > 0.02;
    this.frontRings.visible = live;
    const cut = this.timeCut ?? Infinity;
    for (const ring of this.frontRings.children) ring.visible = live && ring.userData.at <= cut;
    for (const l of this.labels) {
      if (l.kind.includes("front")) l.hiddenByFocus = !live || l.at > cut;
    }
  }

  /* One pin per bookmark: a thin stem with a small pale cap. Height is
     recency; undated saves get a squat grey stub instead. */
  buildMarkers() {
    const n = Math.max(1, this.markers.length);
    const body = new THREE.CylinderGeometry(0.85, 1.25, 1, 6, 1, false);
    body.translate(0, 0.5, 0);
    const cap = new THREE.SphereGeometry(1.75, 8, 6);
    cap.scale(1, 0.72, 1);

    this.markerMesh = new THREE.InstancedMesh(body, trackMaterial(new THREE.MeshStandardMaterial({ roughness: 0.55, metalness: 0, flatShading: true })), n);
    this.capMesh = new THREE.InstancedMesh(cap, trackMaterial(new THREE.MeshStandardMaterial({ color: "#F2EDE1", roughness: 0.5, metalness: 0, flatShading: true })), n);
    this.markerMesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(n * 3), 3);
    this.capMesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(n * 3), 3);
    for (const m of [this.markerMesh, this.capMesh]) {
      m.castShadow = true;
      m.receiveShadow = false;
      m.frustumCulled = false;
      m.renderOrder = 4;
    }
    this.markers.forEach((m) => { m.y = this.field.sample(m.x, m.z); });
    this.world.add(this.markerMesh, this.capMesh);

    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(4.6, 0.42, 6, 32).rotateX(-Math.PI / 2),
      trackMaterial(new THREE.MeshBasicMaterial({ color: "#D9482B", depthTest: false, transparent: true, opacity: 0.95 })),
    );
    ring.renderOrder = 9;
    ring.visible = false;
    this.selectRing = ring;
    this.world.add(ring);
  }

  setColorMode(mode) {
    this.colorMode = mode;
    const srcColor = new Map(this.atlas.sources.map((s) => [s.id, new THREE.Color(s.color)]));
    const undatedCap = new THREE.Color("#B9B2A3");
    const pale = new THREE.Color("#F2EDE1");
    const c = new THREE.Color();
    this.markers.forEach((m, i) => {
      if (m.undated) c.set("#8E887C");
      else c.copy(mode === "sources" ? (srcColor.get(m.source) || new THREE.Color("#6E685E")) : new THREE.Color(m.color));
      this.markerMesh.instanceColor.setXYZ(i, c.r, c.g, c.b);
      const cap = m.undated ? undatedCap : pale;
      this.capMesh.instanceColor.setXYZ(i, cap.r, cap.g, cap.b);
      if (this.dots) this.dots.instanceColor.setXYZ(i, c.r, c.g, c.b);
    });
    this.markerMesh.instanceColor.needsUpdate = true;
    this.capMesh.instanceColor.needsUpdate = true;
    if (this.dots) this.dots.instanceColor.needsUpdate = true;
  }

  /* Topic and source are both live filters: a marker is drawn only when
     neither of its groups has been switched off. */
  markerHidden(marker) {
    return this.state.hidden.has(`src:${marker.source}`) || this.state.hidden.has(`reg:${marker.regionId}`);
  }

  /* Markers appear as the timeline reaches their save date. Their world size
     is tied to the camera distance so a pin stays a pin at every zoom. */
  setTimeFilter(frac) {
    const r = this.atlas.range;
    const cut = r ? r.start + (r.end - r.start) * frac : Infinity;
    this.timeCut = cut;
    const k = this.markerScale;
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), s = new THREE.Vector3();
    let shown = 0, undated = 0;
    this.markers.forEach((m, i) => {
      const inTime = m.undated ? frac >= 0.999 : m.at <= cut;
      const visible = inTime && !this.markerHidden(m);
      if (visible) { shown++; if (m.undated) undated++; }
      const appear = m.undated || m.at == null ? 1 : clamp((cut - m.at) / (6 * 86_400_000), 0, 1);
      const h = visible ? m.height * k * (0.35 + 0.65 * appear) : 0;
      p.set(m.x, m.y - 0.4, m.z);
      s.set(visible ? k : 0, Math.max(0.001, h), visible ? k : 0);
      m4.compose(p, q, s);
      this.markerMesh.setMatrixAt(i, m4);
      p.set(m.x, m.y - 0.4 + h, m.z);
      s.set(visible ? k : 0, visible ? k * (m.undated ? 0.6 : 1) : 0, visible ? k : 0);
      m4.compose(p, q, s);
      this.capMesh.setMatrixAt(i, m4);
      if (this.dots) {
        p.set(m.x, 1.2, m.z);
        s.set(visible ? 1 : 0, visible ? 1 : 0, visible ? 1 : 0);
        m4.compose(p, q, s);
        this.dots.setMatrixAt(i, m4);
      }
    });
    this.markerMesh.instanceMatrix.needsUpdate = true;
    this.capMesh.instanceMatrix.needsUpdate = true;
    if (this.dots) this.dots.instanceMatrix.needsUpdate = true;
    this.shownMarkers = shown;
    this.shownUndated = undated;
    this.advanceFronts(cut);
  }

  /* How far each region has filled up by `cut`: the share of its saves that
     have happened, as a radius, so the tint grows by area. */
  advanceFronts(cut) {
    for (const [id, node] of this.regionNodes) {
      const times = this.regionTimes.get(id) || [];
      let lo = 0, hi = times.length;
      while (lo < hi) { const mid = (lo + hi) >> 1; if (times[mid] <= cut) lo = mid + 1; else hi = mid; }
      const share = times.length ? lo / times.length : 1;
      node.spread.uniforms.uFront.value = share <= 0 ? 0 : Math.max(0.16, Math.sqrt(share));
    }
  }

  /* The reading trail: a hairline dashed polyline that follows the ground,
     with an arrowhead only where the route starts and ends and a small
     marker ring at each dated stop. Thin on purpose — at overview scale it
     should read as a drawn line, not as a ribbon of tape. */
  buildTrail(pins) {
    if (this.trail) { this.world.remove(this.trail); disposeTree(this.trail); }
    if (this.flatTrail) { this.map2d.remove(this.flatTrail); disposeTree(this.flatTrail); this.flatTrail = null; }
    this.trail = new THREE.Group();
    this.trailPins = pins || [];
    this.world.add(this.trail);
    if (!pins || pins.length < 2) { this.trailPath = []; this.trailCurve = null; return; }

    // Catmull-Rom through the pins: a smooth path reads as a route, and the
    // cameras that follow it stop snapping at every corner.
    const curve = new THREE.CatmullRomCurve3(pins.map((p) => new THREE.Vector3(p.x, 0, p.z)), false, "catmullrom", 0.35);
    const path = curve.getPoints(Math.max(48, pins.length * 18)).map((v) => [v.x, v.z]);
    this.trailPath = path;
    this.trailCurve = curve;
    this.stopU = routeStops(curve, pins);

    // A thin dark casing instead of a cream one: the old halo read as a row
    // of white rectangles under the dashes. This reads as a drawn line.
    const halo = new THREE.Mesh(
      ribbon(path, this.field, { width: 1.7, lift: 1.4, dash: 6, gap: 4.5 }),
      trackMaterial(new THREE.MeshBasicMaterial({ color: "#3A2F1C", depthWrite: false, transparent: true, opacity: 0.4, side: THREE.DoubleSide })),
    );
    halo.renderOrder = 5;
    const line = new THREE.Mesh(
      ribbon(path, this.field, { width: 0.95, lift: 1.7, dash: 6, gap: 4.5 }),
      trackMaterial(new THREE.MeshBasicMaterial({ color: "#D18D16", depthWrite: false, transparent: true, opacity: 1, side: THREE.DoubleSide })),
    );
    line.renderOrder = 6;
    this.trail.add(halo, line);

    // arrowheads only at the two ends of the route
    const head = new THREE.ConeGeometry(1.2, 3.4, 5).rotateX(Math.PI / 2);
    const headMat = trackMaterial(new THREE.MeshBasicMaterial({ color: "#C9861B", depthWrite: false, transparent: true, opacity: 1 }));
    for (const i of [2, path.length - 2]) {
      const [x0, z0] = path[i], [x1, z1] = path[Math.min(path.length - 1, i + 1)];
      const arrow = new THREE.Mesh(head, headMat);
      arrow.position.set(x0, this.field.sample(x0, z0) + 2.6, z0);
      arrow.rotation.y = Math.atan2(x1 - x0, z1 - z0);
      arrow.renderOrder = 7;
      this.trail.add(arrow);
    }

    // a small ring on the ground at each dated stop, under its pin
    const ringGeo = new THREE.TorusGeometry(1.6, 0.26, 5, 20).rotateX(-Math.PI / 2);
    const ringMat = trackMaterial(new THREE.MeshBasicMaterial({ color: "#C9861B", depthWrite: false, transparent: true, opacity: 1 }));
    const postGeo = new THREE.CylinderGeometry(0.22, 0.22, 1, 4);
    postGeo.translate(0, 0.5, 0);
    const postMat = trackMaterial(new THREE.MeshBasicMaterial({ color: "#6E685E", depthWrite: false, transparent: true, opacity: 0.85 }));
    for (const pin of pins) {
      const y = this.field.sample(pin.x, pin.z);
      const ring = new THREE.Mesh(ringGeo, ringMat);
      ring.position.set(pin.x, y + 1.9, pin.z);
      ring.renderOrder = 7;
      const post = new THREE.Mesh(postGeo, postMat);
      post.position.set(pin.x, y, pin.z);
      post.scale.y = 8;
      this.trail.add(ring, post);
    }

    // the same route, flat, for the 2D map
    const flat = { sample: () => 0, slope: () => 0 };
    this.flatTrail = new THREE.Group();
    this.flatTrail.add(
      new THREE.Mesh(ribbon(path, flat, { width: 2.4, lift: 0.5, dash: 6, gap: 4.5 }),
        trackMaterial(new THREE.MeshBasicMaterial({ color: "#F6F2E7", transparent: true, opacity: 0.9 }))),
      new THREE.Mesh(ribbon(path, flat, { width: 1.3, lift: 0.7, dash: 6, gap: 4.5 }),
        trackMaterial(new THREE.MeshBasicMaterial({ color: "#A8660D" }))),
    );
    for (const i of [2, path.length - 2]) {
      const [ax, az] = path[i], [bx, bz] = path[Math.min(path.length - 1, i + 1)];
      const a2 = new THREE.Mesh(new THREE.ConeGeometry(1.8, 5, 4).rotateX(Math.PI / 2),
        trackMaterial(new THREE.MeshBasicMaterial({ color: "#A8660D" })));
      a2.position.set(ax, 0.9, az);
      a2.rotation.y = Math.atan2(bx - ax, bz - az);
      this.flatTrail.add(a2);
    }
    this.map2d.add(this.flatTrail);
    this.setFollow(this.follow.u);
  }

  /* ── flat map ───────────────────────────────────────────────────────── */

  /* Hillshade and contours generated from the same heightfield as the 3D
     terrain, so the flat view is the same country seen from straight up —
     not a bubble diagram on a plate. */
  buildMap2DRelief() {
    const STEP = 4;                                 // sample every 4th cell
    const n = this.field.n, cells = Math.floor((n - 1) / STEP);
    const geo = new THREE.PlaneGeometry(MAP.PLATE * 2, MAP.PLATE * 2, cells, cells).rotateX(-Math.PI / 2);
    const count = (cells + 1) * (cells + 1);
    const heights = new Float32Array(count);
    const shade = new Float32Array(count);
    const lx = -0.6, lz = -0.55, ly = 0.58;         // light from the north-west
    for (let j = 0; j <= cells; j++) {
      for (let i = 0; i <= cells; i++) {
        const x = -MAP.PLATE + (i * STEP) * this.field.cell;
        const z = -MAP.PLATE + (j * STEP) * this.field.cell;
        const h = this.field.sample(x, z);
        const e = this.field.cell * STEP;
        const dx = this.field.sample(x + e, z) - this.field.sample(x - e, z);
        const dz = this.field.sample(x, z + e) - this.field.sample(x, z - e);
        const len = Math.hypot(-dx, 2 * e, -dz) || 1;
        const k = (-dx * lx + 2 * e * ly + -dz * lz) / len;
        const idx = j * (cells + 1) + i;
        heights[idx] = h;
        shade[idx] = clamp(0.35 + 0.95 * k, 0, 1.35);
      }
    }
    geo.setAttribute("aHeight", new THREE.BufferAttribute(heights, 1));
    geo.setAttribute("aShade", new THREE.BufferAttribute(shade, 1));
    const mat = new THREE.ShaderMaterial({
      uniforms: {
        interval: { value: 40 },
        water: { value: MAP.WATER },
        low: { value: new THREE.Color("#E6DFCB") },
        high: { value: new THREE.Color("#D6C8A8") },
        sea: { value: new THREE.Color("#C2CCCB") },
        ink: { value: new THREE.Color("#A89B7E") },
      },
      vertexShader: `attribute float aHeight; attribute float aShade;
        varying float vH; varying float vS;
        void main(){ vH = aHeight; vS = aShade;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
      fragmentShader: `varying float vH; varying float vS;
        uniform float interval; uniform float water;
        uniform vec3 low; uniform vec3 high; uniform vec3 sea; uniform vec3 ink;
        void main(){
          if (vH < water) { gl_FragColor = vec4(sea, 1.0); return; }
          vec3 base = mix(low, high, clamp(vH / 260.0, 0.0, 1.0));
          base *= mix(0.86, 1.08, clamp(vS, 0.0, 1.0));
          float band = vH / interval;
          float d = abs(fract(band - 0.5) - 0.5) / max(fwidth(band), 1e-4);
          float line = 1.0 - min(d, 1.0);
          float index = abs(fract(vH / (interval * 5.0) - 0.5) - 0.5) / max(fwidth(vH / (interval * 5.0)), 1e-4);
          float major = 1.0 - min(index, 1.0);
          vec3 c = mix(base, ink, line * 0.30 + major * 0.3);
          gl_FragColor = vec4(c, 1.0);
        }`,
    });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.y = -6;
    mesh.name = "relief2d";
    return mesh;
  }

  buildMap2D() {
    const g = new THREE.Group();
    g.visible = false;
    this.map2d = g;
    this.scene.add(g);

    this.relief = this.buildMap2DRelief();
    g.add(this.relief);

    // a restrained graticule in synthetic map units, not a metric grid
    const grid = new THREE.GridHelper(MAP.PLATE * 2, 20, 0xb6ab93, 0xc6bca6);
    grid.material.transparent = true;
    grid.material.opacity = 0.35;
    grid.material.depthWrite = false;
    trackMaterial(grid.material);
    grid.position.y = -5;
    g.add(grid);

    const flat = { sample: () => 0, slope: () => 0 };
    this.map2dRegions = new Map();
    for (const region of this.layout.regions) {
      const color = new THREE.Color(region.color);
      const shape = new THREE.Shape(region.boundary.map(([x, z]) => new THREE.Vector2(x, z)));
      const fill = new THREE.Mesh(new THREE.ShapeGeometry(shape).rotateX(Math.PI / 2),
        trackMaterial(new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.2, side: THREE.DoubleSide, depthWrite: false })));
      fill.position.y = -4;
      const line = new THREE.Mesh(ribbon(region.boundary, flat, { width: 2.2, lift: -3.4, closed: true }),
        trackMaterial(new THREE.MeshBasicMaterial({ color: color.clone().multiplyScalar(0.78), transparent: true, opacity: 0.95, depthWrite: false })));
      const node = new THREE.Group();
      node.add(fill, line);
      const dgroup = new THREE.Group();
      for (const district of region.districts) {
        const dLine = new THREE.Mesh(ribbon(district.boundary, flat, { width: 0.9, lift: -3.2, closed: true, dash: 5, gap: 4 }),
          trackMaterial(new THREE.MeshBasicMaterial({ color: color.clone().multiplyScalar(0.66), transparent: true, opacity: 0.9, depthWrite: false })));
        dgroup.add(dLine);
      }
      node.add(dgroup);
      g.add(node);
      this.map2dRegions.set(region.id, { node, fill, line, dgroup });
    }

    const n = Math.max(1, this.markers.length);
    const disc = new THREE.CylinderGeometry(2.6, 2.6, 0.6, 10);
    this.dots = new THREE.InstancedMesh(disc, trackMaterial(new THREE.MeshBasicMaterial({ transparent: true, opacity: 1 })), n);
    this.dots.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(n * 3), 3);
    this.dots.frustumCulled = false;
    this.dots.position.y = -2;
    g.add(this.dots);
  }

  /* ── labels ─────────────────────────────────────────────────────────── */

  /* Labels are built as elements, never as markup: a bookmark title, a topic
     name or a subtopic name is always assigned through textContent. */
  addLabel(kind, x, y, z, build, data = {}) {
    const node = document.createElement("div");
    node.className = `pin ${kind}`;
    build(node);
    this.labelHost.appendChild(node);
    const label = { node, pos: new THREE.Vector3(x, y, z), kind, ...data };
    this.labels.push(label);
    return label;
  }

  buildLabels() {
    this.labelHost.textContent = "";
    this.labels = [];
    const pill = (text, color, tail) => (node) => {
      const span = document.createElement("span");
      span.className = "pill";
      if (color) {
        const chip = document.createElement("i");
        chip.style.background = color;
        span.appendChild(chip);
      }
      span.appendChild(document.createTextNode(text));
      if (tail) {
        const u = document.createElement("u");
        u.textContent = ` · ${tail}`;
        span.appendChild(u);
      }
      node.appendChild(span);
      const stem = document.createElement("span");
      stem.className = "stem";
      node.appendChild(stem);
    };

    for (const region of this.layout.regions) {
      let top = -Infinity;
      for (let a = 0; a < 8; a++) {
        const th = (a / 8) * Math.PI * 2;
        for (const k of [0, 0.4, 0.75]) {
          top = Math.max(top, this.field.sample(region.x + Math.cos(th) * region.r * k, region.z + Math.sin(th) * region.r * k));
        }
      }
      this.addLabel("region", region.x, top + 46, region.z, pill(region.name, region.color, region.total), { regionId: region.id });
      for (const district of region.districts) {
        this.addLabel("sm district", district.x, this.field.sample(district.x, district.z) + 15, district.z,
          pill(`${district.name} · ${district.total}`, null, null), { regionId: region.id });
      }
    }
  }

  rebuildTrailLabels() {
    for (const l of this.labels.filter((l) => l.kind.includes("date"))) l.node.remove();
    this.labels = this.labels.filter((l) => !l.kind.includes("date"));
    const datePill = (txt, color) => (node) => {
      const span = document.createElement("span");
      span.className = "pill";
      const dot = document.createElement("i");
      dot.style.background = color;
      span.append(dot, document.createTextNode(txt));
      node.appendChild(span);
      const stem = document.createElement("span");
      stem.className = "stem";
      node.appendChild(stem);
    };
    (this.trailPins || []).forEach((pin, i) => {
      if (pin.at == null) return;
      this.addLabel("date", pin.x, this.field.sample(pin.x, pin.z) + 19, pin.z,
        datePill(stamp(pin.at), "#C9861B"), { trailIndex: i, at: pin.at });
    });
    // and the dated perimeters of the region in focus
    for (const mark of this.frontMarks || []) {
      this.addLabel("date front", mark.x, this.field.sample(mark.x, mark.z) + 15, mark.z,
        datePill(stamp(mark.at), mark.color), { at: mark.at });
    }
  }

  /* ── layers / focus ─────────────────────────────────────────────────── */

  /* One contract for both render modes: every layer the inspector lists has
     a visibility flag and an opacity, and both are applied here. */
  applyLayers() {
    const L = this.state.layers;
    const on = (k) => L[k].on;
    const op = (k) => (L[k].on ? L[k].opacity : 0);
    const flat = this.state.dim === "2d";

    this.terrain.visible = on("terrain") && !flat;
    this.rocks.visible = on("terrain") && !flat && this.quality.rocks !== false;
    this.scrub.visible = on("terrain") && !flat;
    setOpacity(this.scrub, op("terrain"));
    this.water.visible = on("terrain") && !flat;
    setOpacity(this.terrain, op("terrain"));
    setOpacity(this.rocks, op("terrain"));
    this.relief.visible = on("terrain") && flat;

    this.forest.visible = on("forest") && !flat;
    setOpacity(this.forest, op("forest"));

    this.tints.visible = on("tints") && !flat;
    this.edges.visible = on("edges") && !flat;
    this.markerMesh.visible = on("markers") && !flat;
    this.capMesh.visible = on("markers") && !flat;
    setOpacity(this.markerMesh, op("markers"));
    setOpacity(this.capMesh, op("markers"));
    this.trail.visible = on("trail") && !flat && this.state.time > 0.999;
    setOpacity(this.trail, op("trail"));
    if (this.flatTrail) {
      this.flatTrail.visible = on("trail") && flat && this.state.time > 0.999;
      setOpacity(this.flatTrail, op("trail"));
    }
    if (this.dots) {
      this.dots.visible = on("markers") && flat;
      setOpacity(this.dots, op("markers"));
    }
    this.labelHost.style.display = on("labels") ? "" : "none";
    this.labelHost.style.opacity = String(op("labels"));
    this.updateFrontRings();

    for (const [id, node] of this.regionNodes) {
      const key = `reg:${id}`;
      const hidden = this.state.hidden.has(key);
      const groupOp = this.state.groupOpacity.get(key) ?? 1;
      const modeDim = this.state.mode === "sources" ? 0.55 : 1;
      // One region at a time carries the frame. The region in focus is drawn
      // saturated with a crisp leading edge; the rest drop right back so it
      // reads, exactly as the reference does with its active fire.
      const focused = this.state.focus === id;
      const quiet = this.state.focus && !focused;
      node.fill.visible = !hidden;
      node.line.visible = !hidden;
      node.dgroup.visible = !hidden && on("edges") && !quiet;
      node.spread.uniforms.uOpacity.value = op("tints") * groupOp * modeDim * (focused ? 0.52 : quiet ? 0.1 : 0.26);
      node.spread.uniforms.uEdge.value = focused ? 0.055 : 0.1;
      setOpacity(node.line, op("tints") * groupOp * (focused ? 1 : quiet ? 0.3 : 0.85));
      node.line.scale.setScalar(1);
      setOpacity(node.dgroup, op("edges") * groupOp * (focused ? 1 : 0.5));
      const m2 = this.map2dRegions.get(id);
      if (m2) {
        m2.node.visible = !hidden;
        setOpacity(m2.fill, op("tints") * groupOp * (focused ? 1.3 : quiet ? 0.4 : 1));
        setOpacity(m2.line, op("tints") * groupOp);
        m2.dgroup.visible = on("edges");
        setOpacity(m2.dgroup, op("edges") * groupOp * (quiet ? 0.45 : 1));
      }
    }
    for (const l of this.labels) {
      if (l.kind.includes("district")) l.hiddenByFocus = !flat && this.state.focus !== l.regionId;
      else if (l.kind === "region") l.hiddenByFocus = this.state.hidden.has(`reg:${l.regionId}`);
    }
  }

  setDim(dim) {
    const flat = dim === "2d";
    this.world.visible = !flat;
    this.sky.visible = !flat;
    this.map2d.visible = flat;
    this.scene.fog = flat ? null : this.fog;
    this.scene.background = new THREE.Color(flat ? "#D7DCD4" : "#ccd3d2");
    this.applyLayers();
  }

  /* ── camera ─────────────────────────────────────────────────────────── */
  groundAt(x, z) { return this.field.sample(x, z); }

  heightRange() {
    let lo = Infinity, hi = -Infinity;
    for (const v of this.field.data) { if (v < lo) lo = v; if (v > hi) hi = v; }
    return [Math.round(lo), Math.round(hi)];
  }

  /* The distance at which the whole library fills the frame, given the
     current viewport shape. */
  frameDistance(margin = 1.1) {
    const vFov = (this.camera.fov * Math.PI) / 180;
    const aspect = this.width / Math.max(1, this.height);
    const hFov = 2 * Math.atan(Math.tan(vFov / 2) * aspect);
    const need = (this.bounds * margin) / Math.tan(Math.min(vFov, hFov) / 2);
    return clamp(need, 320, 2400);
  }

  setCamera(pose) {
    Object.assign(this.cam, pose);
    this.cam.pol = clamp(this.cam.pol, 0.12, 1.47);
    this.cam.dist = clamp(this.cam.dist, 28, 3000);
  }

  applyCamera() {
    const c = this.cam;
    const target = new THREE.Vector3(c.tx, c.ty, c.tz);
    const pos = new THREE.Vector3(
      c.tx + Math.sin(c.pol) * Math.sin(c.az) * c.dist,
      c.ty + Math.cos(c.pol) * c.dist,
      c.tz + Math.sin(c.pol) * Math.cos(c.az) * c.dist,
    );
    const floor = this.groundAt(pos.x, pos.z) + 42;
    if (pos.y < floor) pos.y = floor;
    this.camera.position.copy(pos);
    this.camera.lookAt(target);
    this.camera.updateMatrixWorld();
    this.camera.updateProjectionMatrix();

    const aspect = this.width / Math.max(1, this.height);
    const span = clamp(c.dist * 0.40, 110, 1400);
    this.ortho.left = -span * aspect; this.ortho.right = span * aspect;
    this.ortho.top = span; this.ortho.bottom = -span;
    this.ortho.position.set(c.tx, 1400, c.tz + 0.001);
    this.ortho.up.set(0, 0, -1);
    this.ortho.lookAt(c.tx, 0, c.tz);
    this.ortho.updateProjectionMatrix();
    this.ortho.updateMatrixWorld();

    const size = clamp(c.dist * 0.60, 170, 1000);
    const s = this.sun.shadow.camera;
    s.left = -size; s.right = size; s.top = size; s.bottom = -size;
    s.far = size * 6 + 600;
    s.updateProjectionMatrix();
    this.sun.position.set(c.tx - size * 1.5, c.ty + size * 1.9, c.tz + size * 1.25);
    this.sun.target.position.set(c.tx, c.ty, c.tz);
    this.sun.target.updateMatrixWorld();

    // Pins keep a steady screen size. Interactively the rebuild is throttled,
    // but in capture mode the scale is exact: a hysteresis band would make a
    // frame depend on which poses were rendered before it.
    const want = clamp(Math.pow(c.dist / 620, 0.72), 0.42, 2.1);
    const slack = this.capture ? 0 : 0.08;
    if (Math.abs(want - this.markerScale) / this.markerScale > slack) {
      this.markerScale = want;
      this.setTimeFilter(this.state.time);
    }
    this.placeSelectRing();
    this.updateForestLOD();
  }

  /* Distance detail for the woods: far tiles thin out instead of the whole
     forest being cut to a stub when a frame runs long. */
  updateForestLOD() {
    const cam = this.camera.position;
    // the reader cam draws the same scene, so a tile has to be good enough
    // for whichever camera is closest to it
    const pip = this.follow.on && this.state.dim !== "2d" ? this.followCam.position : null;
    const q = this.quality.forest;
    const near = (c) => {
      const d = Math.hypot(cam.x - c.x, cam.z - c.y);
      return pip ? Math.min(d, Math.hypot(pip.x - c.x, pip.z - c.y)) : d;
    };
    for (const tile of this.forest.children) {
      const d = near(tile.userData.centre);
      const keep = d < 900 ? 1 : d < 1600 ? 0.8 : d < 2400 ? 0.5 : 0.25;
      tile.count = Math.max(1, Math.round(tile.userData.full * keep * q));
    }
    // ground cover only matters close up; past a few hundred metres it is
    // sub-pixel and costs a draw call for nothing
    const qs = this.quality.scrub;
    for (const tile of this.scrub.children) {
      const d = near(tile.userData.centre);
      const keep = d < 460 ? 1 : d < 820 ? 0.7 : d < 1400 ? 0.3 : 0.08;
      tile.count = Math.max(1, Math.round(tile.userData.full * keep * qs));
    }
  }

  activeCamera() { return this.state.dim === "2d" ? this.ortho : this.camera; }

  /* ── reader cam ─────────────────────────────────────────────────────── */

  /* Where the picture-in-picture sits, in CSS pixels inside the viewport.
     The HUD overlay is positioned from the same numbers. */
  /* One layout for the renderer's scissor and the HUD overlay, clamped to
     whatever viewport we actually have. */
  pipRect() {
    const w = Math.round(clamp(this.width * 0.42, 220, Math.max(160, this.width - 36)));
    const h = Math.round(Math.min(w * 0.605, Math.max(120, this.height - 160)));
    return { x: Math.round(this.width - w - 18), y: 18, w, h };
  }

  /* The PiP only exists when there is a route to ride and a 3D view to ride
     it in. The HUD uses the same predicate. */
  pipLive() {
    return !!(this.follow.on && this.state.dim !== "2d" && this.trailCurve);
  }

  /* Ride the reading trail: the camera sits behind and above the current
     point and looks along the route, so the PiP shows what a reader walking
     their own library would see. */
  setFollow(u) {
    const c = this.trailCurve;
    this.follow.u = clamp(u, 0, 1);
    if (!c) return;
    const t = clamp(u, 0, 0.9995);
    const p = c.getPointAt(t);
    const tan = c.getTangentAt(t).normalize();
    const gy = this.groundAt(p.x, p.z);
    // high and well back: the reader cam is a survey aircraft, so terrain is
    // the subject and the markers under it stay small
    const eye = new THREE.Vector3(p.x - tan.x * 120, gy + 108, p.z - tan.z * 120);
    const floor = this.groundAt(eye.x, eye.z) + 48;
    if (eye.y < floor) eye.y = floor;
    const ax = p.x + tan.x * 150, az = p.z + tan.z * 150;
    this.followCam.position.copy(eye);
    this.followCam.lookAt(ax, this.groundAt(ax, az) + 6, az);
    this.followCam.updateMatrixWorld();
    this.follow.heading = (Math.atan2(tan.x, tan.z) + Math.PI * 2) % (Math.PI * 2);
    this.follow.alt = eye.y - gy;
    this.follow.point.copy(p);
    this.follow.pitch = -(Math.atan2(eye.y - (this.groundAt(ax, az) + 10), 150) * 180) / Math.PI;
    this.follow.elev = gy;
    const span = 190;
    this.followPlan.left = -span; this.followPlan.right = span;
    this.followPlan.top = span * 0.605; this.followPlan.bottom = -span * 0.605;
    this.followPlan.position.set(p.x, gy + 900, p.z + 0.001);
    this.followPlan.up.set(Math.sin(this.follow.heading), 0, Math.cos(this.follow.heading));
    this.followPlan.lookAt(p.x, gy, p.z);
    this.followPlan.updateProjectionMatrix();
    this.followPlan.updateMatrixWorld();
    this.follow.stop = stopAtU(this.stopU || [], t);
  }

  /* A third-person shot of the reader: used for the main view while the PiP
     carries the reader's own eye line. */
  followPose(u) {
    const c = this.trailCurve;
    if (!c) return { tx: 0, ty: this.groundAt(0, 0) + 55, tz: 0, dist: 500, pol: 1.1, az: 0.4 };
    const t = clamp(u, 0, 0.9995);
    const p = c.getPointAt(t);
    const tan = c.getTangentAt(t).normalize();
    return {
      tx: p.x, ty: this.groundAt(p.x, p.z) + 26, tz: p.z,
      az: Math.atan2(tan.x, tan.z) + Math.PI * 0.78,
      dist: 420, pol: 1.0,
    };
  }

  setFollowOn(on) {
    this.follow.on = !!on;
    this.applyLayers();
  }

  /* ── picking ────────────────────────────────────────────────────────── */
  pick(px, py) {
    const flat = this.state.dim === "2d";
    const target = flat ? this.dots : this.markerMesh;
    if (!target || !target.visible) return null;
    const ndc = new THREE.Vector2((px / this.width) * 2 - 1, -(py / this.height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, this.activeCamera());
    const hits = ray.intersectObject(target, false);
    if (!hits.length) return null;
    const id = hits[0].instanceId;
    return id == null ? null : this.markers[id];
  }

  markerById(id) { return this.markers.find((m) => m.id === id) || null; }

  /* The ride position that puts the camera at stop `i`. */
  uForStop(i) {
    const u = (this.stopU || [])[clamp(i, 0, (this.stopU || []).length - 1)];
    return u == null ? 0 : u;
  }

  selectMarker(marker) {
    this.selected = marker || null;
    this.placeSelectRing();
  }

  /* The ring is sized with the pins, so it has to be placed after the camera
     has settled the marker scale — otherwise its size depended on whatever
     was rendered before it. */
  placeSelectRing() {
    const m = this.selected;
    this.selectRing.visible = !!m;
    if (!m) return;
    this.selectRing.scale.setScalar(this.markerScale);
    this.selectRing.position.set(m.x, m.y + 1.2, m.z);
  }

  /* ── render ─────────────────────────────────────────────────────────── */
  resize(width, height) {
    this.width = width; this.height = height;
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / Math.max(1, height);
    this.camera.updateProjectionMatrix();
  }

  /* Project a world point with the camera that is about to draw, so a
     tooltip never lags a frame behind the pose that produced it. */
  project(x, y, z) {
    this.applyCamera();
    const v = new THREE.Vector3(x, y, z).project(this.activeCamera());
    return { x: (v.x * 0.5 + 0.5) * this.width, y: (-v.y * 0.5 + 0.5) * this.height, behind: v.z > 1 };
  }

  updateLabels() {
    const cam = this.activeCamera();
    const v = new THREE.Vector3();
    const camPos = cam.position;
    const placed = [];
    const flat = this.state.dim === "2d";
    const pip = this.follow.on && !flat ? this.pipRect() : null;
    const order = { region: 0, date: 1 };
    const sorted = this.labels.slice().sort((a, b) => (order[a.kind] ?? 2) - (order[b.kind] ?? 2));
    // Hidden labels keep their box: measuring offsetWidth on a display:none
    // node returns 0, which would make the collision packing depend on which
    // frame was drawn before this one.
    for (const l of sorted) {
      if (l.hiddenByFocus) { l.node.style.visibility = "hidden"; continue; }
      v.copy(l.pos).project(cam);
      const behind = v.z > 1 || v.z < -1;
      const x = (v.x * 0.5 + 0.5) * this.width;
      const y = (-v.y * 0.5 + 0.5) * this.height;
      const dist = camPos.distanceTo(l.pos);
      const half = (l.node.offsetWidth || 90) / 2;
      let show = !behind && x - half > 2 && x + half < this.width - 2 && y > 8 && y < this.height - 4;
      if (l.kind.includes("district")) show = show && (flat ? this.ortho.top < 520 : dist < 760);
      if (l.kind === "region") show = show && (flat || dist < 2600);
      if (l.kind === "date") show = show && this.trail.visible && (l.at == null || l.at <= (this.timeCut ?? Infinity));
      if (show && pip && x > pip.x - half - 8 && x < pip.x + pip.w + 8 && y > pip.y - 26 && y < pip.y + pip.h + 8) show = false;
      if (show) {
        const h2 = l.node.offsetHeight || 20;
        const box = [x - half, y - h2, x + half, y];
        if (placed.some((q) => box[0] < q[2] + 6 && box[2] > q[0] - 6 && box[1] < q[3] + 4 && box[3] > q[1] - 4)) show = false;
        else placed.push(box);
      }
      l.node.style.visibility = show ? "visible" : "hidden";
      if (show) {
        l.node.style.left = `${x.toFixed(1)}px`;
        l.node.style.top = `${y.toFixed(1)}px`;
      }
    }
  }

  render() {
    this.applyCamera();
    const r = this.renderer;
    // one shadow pass per frame, shared by the main view and the inset
    if (this.quality.shadows) {
      r.shadowMap.autoUpdate = false;
      r.shadowMap.needsUpdate = true;
    }
    r.setViewport(0, 0, this.width, this.height);
    r.setScissorTest(false);
    r.render(this.scene, this.activeCamera());

    // second pass into the picture-in-picture: the same world, the reader's
    // own camera, scissored to the HUD frame
    if (this.pipLive()) {
      const p = this.pipRect();
      const y = this.height - p.y - p.h;
      const pipCam = this.follow.view === "plan" ? this.followPlan : this.followCam;
      this.followCam.aspect = p.w / Math.max(1, p.h);
      this.followCam.updateProjectionMatrix();
      r.autoClear = false;
      r.setViewport(p.x, y, p.w, p.h);
      r.setScissor(p.x, y, p.w, p.h);
      r.setScissorTest(true);
      r.clear(true, true, false);
      // the inset is a fifth of the pixels; it does not need the full
      // per-fragment detail noise
      const detail = this.terrain.material.userData.detail;
      const full = detail ? detail.strength.value : 0;
      if (detail) detail.strength.value = full * 0.45;
      r.render(this.scene, pipCam);
      if (detail) detail.strength.value = full;
      r.setScissorTest(false);
      r.setViewport(0, 0, this.width, this.height);
      r.autoClear = true;
    }
    this.updateLabels();
  }

  /* Four quality tiers. Each one drops real work — resolution, the shadow
     pass, instance counts and the detail-normal noise — so the low tier is
     meaningfully cheaper rather than cosmetically smaller. */
  setQuality(tier) {
    const t = Math.round(clamp(tier, 0, 3));
    const dpr = window.devicePixelRatio || 1;
    const tiers = [
      { pr: Math.min(this.capture ? 1 : 1.6, dpr), shadows: true, forest: 1, scrub: 1, detail: 0.6 },
      { pr: 1, shadows: true, forest: 0.7, scrub: 0.5, detail: 0.5 },
      { pr: 1, shadows: false, forest: 0.45, scrub: 0.18, detail: 0.3 },
      { pr: 0.75, shadows: false, forest: 0.24, scrub: 0.05, detail: 0 },
    ];
    const q = tiers[t];
    this.quality.tier = t;
    this.quality.forest = q.forest;
    this.quality.scrub = q.scrub;
    if (this.quality.pixelRatio !== q.pr) {
      this.quality.pixelRatio = q.pr;
      this.renderer.setPixelRatio(q.pr);
      this.resize(this.width, this.height);
    }
    if (this.quality.shadows !== q.shadows) {
      this.quality.shadows = q.shadows;
      this.renderer.shadowMap.enabled = q.shadows;
      this.renderer.shadowMap.needsUpdate = true;
      for (const tile of this.forest.children) tile.castShadow = q.shadows;
    }
    setDetailStrength(this.terrain.material, q.detail);
    this.quality.rocks = t < 3;
    this.applyLayers();
    this.updateForestLOD();
    return this.quality;
  }

  /* Step down a tier when the page can't hold ~48fps. Never in capture mode,
     where frames must be identical every run. */
  measure(dt) {
    if (this.capture) return;
    this.frameTimes.push(dt);
    if (this.frameTimes.length < 60) return;
    const avg = this.frameTimes.reduce((a, b) => a + b, 0) / this.frameTimes.length;
    this.frameTimes = [];
    if (avg < 1000 / 48 || this.quality.tier >= 3) return;
    this.setQuality(this.quality.tier + 1);
  }

  dispose() {
    this.labelHost.textContent = "";
    this.labels = [];
    disposeTree(this.scene);
    this.scene.clear();
    this.renderer.dispose();
    this.renderer.forceContextLoss?.();
  }
}
