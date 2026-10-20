/* The viewport: landscape, draped data, markers, labels, the flat 2D map and
   the camera rig. Nothing in here invents a number — positions come from
   atlas-layout.js and colours come from the model. */
import * as THREE from "three";
import { MAP, boundary } from "./atlas-layout.js";
import {
  buildHeightField, buildTerrain, buildWater, buildSky,
  scatterTrees, scatterRocks, drapeDisc, ribbon,
} from "./atlas-terrain.js";

const UP = new THREE.Vector3(0, 1, 0);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
export const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

export class AtlasScene {
  constructor({ canvas, labelHost, atlas, layout, state, capture = false }) {
    Object.assign(this, { canvas, labelHost, atlas, layout, state, capture });
    this.labels = [];
    this.markers = layout.regions.flatMap((r) => r.markers);
    this.markerIndex = new Map(this.markers.map((m, i) => [m.id, i]));
    this.cam = { tx: 0, ty: 150, tz: 0, dist: 1100, az: 0.6, pol: 1.21 };
    this.quality = { pixelRatio: Math.min(capture ? 1 : 1.6, window.devicePixelRatio || 1), shadows: true };
    this.frameTimes = [];
    this.hovered = null;
  }

  /* ── build ──────────────────────────────────────────────────────────── */
  init() {
    const renderer = new THREE.WebGLRenderer({ canvas: this.canvas, antialias: true, alpha: false, powerPreference: "high-performance" });
    renderer.setPixelRatio(this.quality.pixelRatio);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.12;
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.renderer = renderer;

    const scene = new THREE.Scene();
    scene.background = new THREE.Color("#ccd3d2");
    scene.fog = new THREE.Fog("#ccd3d2", 1900, 4400);
    this.scene = scene;

    this.camera = new THREE.PerspectiveCamera(42, 16 / 9, 2, 26000);
    this.ortho = new THREE.OrthographicCamera(-600, 600, 400, -400, -4000, 8000);

    const hemi = new THREE.HemisphereLight("#dde6ea", "#978b73", 0.68);
    scene.add(hemi);
    const sun = new THREE.DirectionalLight("#fff1dc", 3.2);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.bias = -0.0012;
    sun.shadow.normalBias = 0.6;
    sun.shadow.camera.near = 10;
    sun.shadow.camera.far = 3200;
    scene.add(sun, sun.target);
    this.sun = sun;
    scene.add(new THREE.AmbientLight("#e4e0d4", 0.2));

    this.field = buildHeightField(this.layout);
    this.world = new THREE.Group();
    scene.add(this.world);

    this.sky = buildSky();
    scene.add(this.sky);
    this.terrain = buildTerrain(this.field);
    this.water = buildWater();
    this.forest = scatterTrees(this.field, { count: 115000 });
    this.rocks = scatterRocks(this.field, { count: 3600 });
    this.world.add(this.terrain, this.water, this.forest, this.rocks);

    this.buildOverlays();
    this.buildMarkers();
    this.buildTrail([]);
    this.buildMap2D();
    this.buildLabels();
    this.applyLayers();
    this.setColorMode(this.state.mode === "sources" ? "sources" : "topics");
    this.setTimeFilter(this.state.time);
    return this;
  }

  /* Translucent region tints, perimeter outlines and dashed district edges —
     the equivalent of the reference's draped fire perimeter. */
  buildOverlays() {
    this.tints = new THREE.Group();
    this.edges = new THREE.Group();
    this.world.add(this.tints, this.edges);
    this.regionNodes = new Map();

    for (const region of this.layout.regions) {
      const color = new THREE.Color(region.color);
      const fill = new THREE.Mesh(
        drapeDisc(region.x, region.z, region.boundary, this.field, { lift: 5.5, rings: 20 }),
        new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.34, depthWrite: false, side: THREE.FrontSide, polygonOffset: true, polygonOffsetFactor: -6, polygonOffsetUnits: -6 }),
      );
      fill.renderOrder = 2;
      const line = new THREE.Mesh(
        ribbon(region.boundary, this.field, { width: 4.6, lift: 6, closed: true }),
        new THREE.MeshBasicMaterial({ color: color.clone().multiplyScalar(0.8), transparent: true, opacity: 0.95, depthWrite: false, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -8, polygonOffsetUnits: -8 }),
      );
      line.renderOrder = 3;
      this.tints.add(fill, line);

      const dgroup = new THREE.Group();
      for (const district of region.districts) {
        const dash = new THREE.Mesh(
          ribbon(district.boundary, this.field, { width: 2.2, lift: 7, closed: true, dash: 9, gap: 8 }),
          new THREE.MeshBasicMaterial({ color: color.clone().multiplyScalar(0.68), transparent: true, opacity: 0.85, depthWrite: false, side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -9, polygonOffsetUnits: -9 }),
        );
        dash.renderOrder = 3;
        dgroup.add(dash);
      }
      this.edges.add(dgroup);
      this.regionNodes.set(region.id, { fill, line, dgroup, region });
    }
  }

  /* One short pillar per bookmark, white-capped, height = recency. */
  buildMarkers() {
    const n = this.markers.length;
    const body = new THREE.CylinderGeometry(1.9, 2.5, 1, 6, 1, false);
    body.translate(0, 0.5, 0);
    const cap = new THREE.CylinderGeometry(3.0, 3.0, 1.4, 7);
    cap.translate(0, 0.7, 0);

    this.markerMesh = new THREE.InstancedMesh(body, new THREE.MeshStandardMaterial({ roughness: 0.6, metalness: 0, flatShading: true }), Math.max(1, n));
    this.capMesh = new THREE.InstancedMesh(cap, new THREE.MeshStandardMaterial({ color: "#EFE9DA", roughness: 0.6, metalness: 0, flatShading: true }), Math.max(1, n));
    this.markerMesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(Math.max(1, n) * 3), 3);
    for (const m of [this.markerMesh, this.capMesh]) {
      m.castShadow = true;
      m.receiveShadow = false;
      m.frustumCulled = false;
      m.renderOrder = 4;
    }
    this.markers.forEach((m) => { m.y = this.field.sample(m.x, m.z); });
    this.world.add(this.markerMesh, this.capMesh);

    const ring = new THREE.Mesh(
      new THREE.TorusGeometry(7, 0.75, 6, 30).rotateX(-Math.PI / 2),
      new THREE.MeshBasicMaterial({ color: "#D9482B", depthTest: false, transparent: true, opacity: 0.95 }),
    );
    ring.renderOrder = 9;
    ring.visible = false;
    this.selectRing = ring;
    this.world.add(ring);
  }

  setColorMode(mode) {
    this.colorMode = mode;
    const srcColor = new Map(this.atlas.sources.map((s) => [s.id, new THREE.Color(s.color)]));
    const c = new THREE.Color();
    this.markers.forEach((m, i) => {
      c.copy(mode === "sources" ? (srcColor.get(m.source) || new THREE.Color("#6E685E")) : new THREE.Color(m.color));
      this.markerMesh.instanceColor.setXYZ(i, c.r, c.g, c.b);
      if (this.dots) this.dots.instanceColor.setXYZ(i, c.r, c.g, c.b);
    });
    this.markerMesh.instanceColor.needsUpdate = true;
    if (this.dots) this.dots.instanceColor.needsUpdate = true;
  }

  /* Markers appear as the timeline reaches their save date. */
  setTimeFilter(frac) {
    const r = this.atlas.range;
    const cut = r ? r.start + (r.end - r.start) * frac : Infinity;
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), s = new THREE.Vector3();
    let shown = 0;
    this.markers.forEach((m, i) => {
      const key = `${this.state.mode === "sources" ? "src:" + m.source : "reg:" + m.regionId}`;
      const visible = (m.at == null || m.at <= cut) && !this.state.hidden.has(key);
      if (visible) shown++;
      const appear = m.at == null ? 1 : clamp((cut - m.at) / (6 * 86_400_000), 0, 1);
      const h = visible ? m.height * (0.35 + 0.65 * appear) : 0;
      p.set(m.x, m.y - 0.6, m.z);
      s.set(visible ? 1 : 0, Math.max(0.001, h), visible ? 1 : 0);
      m4.compose(p, q, s);
      this.markerMesh.setMatrixAt(i, m4);
      p.set(m.x, m.y - 0.6 + h, m.z);
      s.set(visible ? 1 : 0, visible ? 1 : 0, visible ? 1 : 0);
      m4.compose(p, q, s);
      this.capMesh.setMatrixAt(i, m4);
      if (this.dots) {
        p.set(m.x, 1.2, m.z);
        s.set(visible ? 1 : 0, visible ? 1 : 0, visible ? 1 : 0);
        m4.compose(p, q, s);
        this.dots.setMatrixAt(i, m4);
      }
    });
    this.timeCut = cut;
    this.markerMesh.instanceMatrix.needsUpdate = true;
    this.capMesh.instanceMatrix.needsUpdate = true;
    if (this.dots) this.dots.instanceMatrix.needsUpdate = true;
    this.shownMarkers = shown;
  }

  /* Dashed reading trail with arrowheads and dated pins. */
  buildTrail(pins) {
    if (this.trail) { this.world.remove(this.trail); disposeTree(this.trail); }
    this.trail = new THREE.Group();
    this.trailPins = pins;
    this.world.add(this.trail);
    if (this.flatTrail) { this.map2d.remove(this.flatTrail); disposeTree(this.flatTrail); this.flatTrail = null; }
    if (!pins || pins.length < 2) { this.trailPath = []; return; }

    const path = [];
    for (let i = 0; i < pins.length - 1; i++) {
      const a = pins[i], b = pins[i + 1];
      const steps = 10;
      for (let s = 0; s < steps; s++) {
        const t = s / steps;
        // a gentle arc so consecutive pins don't read as one straight ruler line
        const mx = (a.x + b.x) / 2, mz = (a.z + b.z) / 2;
        const nx = -(b.z - a.z) * 0.1, nz = (b.x - a.x) * 0.1;
        const bend = Math.sin(t * Math.PI);
        path.push([lerp(a.x, b.x, t) + nx * bend * 0.6 + (mx - mx), lerp(a.z, b.z, t) + nz * bend * 0.6]);
      }
    }
    path.push([pins[pins.length - 1].x, pins[pins.length - 1].z]);
    this.trailPath = path;

    const line = new THREE.Mesh(
      ribbon(path, this.field, { width: 3.0, lift: 6.5, dash: 13, gap: 10 }),
      new THREE.MeshBasicMaterial({ color: "#D9482B", depthWrite: false, transparent: true, opacity: 0.95, side: THREE.DoubleSide }),
    );
    line.renderOrder = 5;
    this.trail.add(line);

    const head = new THREE.ConeGeometry(3.1, 8.4, 4).rotateX(Math.PI / 2);
    const mat = new THREE.MeshBasicMaterial({ color: "#D9482B", depthWrite: false, transparent: true, opacity: 0.95 });
    for (let i = 2; i < path.length - 1; i += 9) {
      const [x0, z0] = path[i], [x1, z1] = path[Math.min(path.length - 1, i + 1)];
      const a = Math.atan2(x1 - x0, z1 - z0);
      const arrow = new THREE.Mesh(head, mat);
      arrow.position.set(x0, this.field.sample(x0, z0) + 6.5, z0);
      arrow.rotation.y = a;
      arrow.renderOrder = 6;
      this.trail.add(arrow);
    }
    if (this.flatTrail) { this.map2d.remove(this.flatTrail); disposeTree(this.flatTrail); }
    const flat = { sample: () => 0, slope: () => 0 };
    this.flatTrail = new THREE.Group();
    const flatLine = new THREE.Mesh(ribbon(path, flat, { width: 2.4, lift: 0.4, dash: 11, gap: 8 }),
      new THREE.MeshBasicMaterial({ color: "#D9482B" }));
    this.flatTrail.add(flatLine);
    for (let i = 2; i < path.length - 1; i += 9) {
      const [ax, az] = path[i], [bx, bz] = path[Math.min(path.length - 1, i + 1)];
      const a2 = new THREE.Mesh(new THREE.ConeGeometry(3.4, 9, 4).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color: "#D9482B" }));
      a2.position.set(ax, 0.6, az);
      a2.rotation.y = Math.atan2(bx - ax, bz - az);
      this.flatTrail.add(a2);
    }
    this.map2d.add(this.flatTrail);

    const postGeo = new THREE.CylinderGeometry(0.55, 0.55, 1, 5);
    postGeo.translate(0, 0.5, 0);
    for (const pin of pins) {
      const post = new THREE.Mesh(postGeo, new THREE.MeshBasicMaterial({ color: "#1E1C19" }));
      post.position.set(pin.x, this.field.sample(pin.x, pin.z), pin.z);
      post.scale.y = 21;
      this.trail.add(post);
    }
  }

  /* ── flat map ───────────────────────────────────────────────────────── */
  buildMap2D() {
    const g = new THREE.Group();
    g.visible = false;
    this.map2d = g;
    this.scene.add(g);

    const sea = new THREE.Mesh(new THREE.PlaneGeometry(5200, 5200).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: "#C9CFCB" }));
    sea.position.y = -4;
    g.add(sea);
    const land = new THREE.Mesh(new THREE.CircleGeometry(MAP.OUTER * 1.62, 96).rotateX(-Math.PI / 2), new THREE.MeshBasicMaterial({ color: "#E8E3D4" }));
    land.position.y = -3;
    g.add(land);

    const grid = new THREE.GridHelper(MAP.OUTER * 3.2, 16, 0xcfc8b8, 0xcfc8b8);
    grid.material.transparent = true;
    grid.material.opacity = 0.5;
    grid.position.y = -2.5;
    g.add(grid);

    const flat = { sample: () => 0, slope: () => 0 };
    this.map2dRegions = new Map();
    for (const region of this.layout.regions) {
      const color = new THREE.Color(region.color);
      const shape = new THREE.Shape(region.boundary.map(([x, z]) => new THREE.Vector2(x, z)));
      const fill = new THREE.Mesh(new THREE.ShapeGeometry(shape).rotateX(Math.PI / 2), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.22, side: THREE.DoubleSide }));
      fill.position.y = -2;
      const line = new THREE.Mesh(ribbon(region.boundary, flat, { width: 2.6, lift: -1.4, closed: true }),
        new THREE.MeshBasicMaterial({ color: color.clone().multiplyScalar(0.8) }));
      const node = new THREE.Group();
      node.add(fill, line);
      for (const district of region.districts) {
        const dFill = new THREE.Mesh(new THREE.ShapeGeometry(new THREE.Shape(district.boundary.map(([x, z]) => new THREE.Vector2(x, z)))).rotateX(Math.PI / 2),
          new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.2, side: THREE.DoubleSide }));
        dFill.position.y = -1.6;
        const dLine = new THREE.Mesh(ribbon(district.boundary, flat, { width: 1.1, lift: -1.2, closed: true, dash: 6, gap: 6 }),
          new THREE.MeshBasicMaterial({ color: color.clone().multiplyScalar(0.72), transparent: true, opacity: 0.85 }));
        node.add(dFill, dLine);
      }
      g.add(node);
      this.map2dRegions.set(region.id, node);
    }

    const n = Math.max(1, this.markers.length);
    const disc = new THREE.CylinderGeometry(3.4, 3.4, 0.6, 10);
    this.dots = new THREE.InstancedMesh(disc, new THREE.MeshBasicMaterial({ vertexColors: false }), n);
    this.dots.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(n * 3), 3);
    this.dots.frustumCulled = false;
    g.add(this.dots);
  }

  /* ── labels ─────────────────────────────────────────────────────────── */
  addLabel(kind, x, y, z, html, data = {}) {
    const node = document.createElement("div");
    node.className = `pin ${kind}`;
    node.innerHTML = html;
    this.labelHost.appendChild(node);
    const label = { node, pos: new THREE.Vector3(x, y, z), kind, ...data };
    this.labels.push(label);
    return label;
  }

  buildLabels() {
    this.labelHost.textContent = "";
    this.labels = [];
    for (const region of this.layout.regions) {
      let top = -Infinity;
      for (let a = 0; a < 8; a++) {
        const th = (a / 8) * Math.PI * 2;
        for (const k of [0, 0.4, 0.75]) {
          top = Math.max(top, this.field.sample(region.x + Math.cos(th) * region.r * k, region.z + Math.sin(th) * region.r * k));
        }
      }
      this.addLabel("region", region.x, top + 54, region.z,
        `<span class="pill"><i style="background:${region.color}"></i>${region.name} <u>· ${region.total}</u></span><span class="stem"></span>`,
        { regionId: region.id });
      for (const district of region.districts) {
        this.addLabel("sm district", district.x, this.field.sample(district.x, district.z) + 19, district.z,
          `<span class="pill">${district.name} · ${district.total}</span>`,
          { regionId: region.id });
      }
    }
  }

  rebuildTrailLabels() {
    for (const l of this.labels.filter((l) => l.kind.includes("date"))) l.node.remove();
    this.labels = this.labels.filter((l) => !l.kind.includes("date"));
    (this.trailPins || []).forEach((pin, i) => {
      if (pin.at == null) return;
      const d = new Date(pin.at);
      const txt = `${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
      this.addLabel("date", pin.x, this.field.sample(pin.x, pin.z) + 25, pin.z, `<span class="pill">${txt}</span><span class="stem"></span>`, { trailIndex: i, at: pin.at });
    });
  }

  /* ── layers / focus ─────────────────────────────────────────────────── */
  applyLayers() {
    const L = this.state.layers;
    const on = (k) => L[k].on;
    const op = (k) => L[k].opacity;
    this.terrain.visible = on("terrain");
    this.rocks.visible = on("terrain");
    this.forest.visible = on("forest");
    this.forest.material.opacity = op("forest");
    this.forest.material.transparent = op("forest") < 1;
    this.tints.visible = on("tints");
    this.edges.visible = on("edges");
    this.markerMesh.visible = on("markers");
    this.capMesh.visible = on("markers");
    // The trail is the whole reading order, so it only makes sense once the
    // timeline has played out; part-way through it would show future saves.
    this.trail.visible = on("trail") && this.state.time > 0.999;
    if (this.flatTrail) this.flatTrail.visible = this.trail.visible;
    this.labelHost.style.display = on("labels") ? "" : "none";

    for (const [id, node] of this.regionNodes) {
      const key = `reg:${id}`;
      const hidden = this.state.hidden.has(key);
      const groupOp = this.state.groupOpacity.get(key) ?? 1;
      const dim = this.state.mode === "sources" ? 0.55 : 1;
      node.fill.visible = !hidden;
      node.line.visible = !hidden;
      node.dgroup.visible = !hidden;
      node.fill.material.opacity = 0.34 * op("tints") * groupOp * dim * (this.state.focus && this.state.focus !== id ? 0.5 : 1);
      node.line.material.opacity = 0.95 * op("tints") * groupOp * (this.state.focus && this.state.focus !== id ? 0.45 : 1);
      const m2 = this.map2dRegions.get(id);
      if (m2) m2.visible = !hidden;
    }
    for (const l of this.labels) {
      if (l.kind.includes("district")) l.hiddenByFocus = this.state.focus !== l.regionId;
      else if (l.kind === "region") l.hiddenByFocus = this.state.hidden.has(`reg:${l.regionId}`);
    }
  }

  setDim(dim) {
    const flat = dim === "2d";
    this.world.visible = !flat;
    this.sky.visible = !flat;
    this.map2d.visible = flat;
    this.scene.fog = flat ? null : new THREE.Fog("#ccd3d2", 1900, 4400);
    this.scene.background = new THREE.Color(flat ? "#DCE0DA" : "#cdd4d4");
  }

  /* ── camera ─────────────────────────────────────────────────────────── */
  groundAt(x, z) { return this.field.sample(x, z); }

  heightRange() {
    let lo = Infinity, hi = -Infinity;
    for (const v of this.field.data) { if (v < lo) lo = v; if (v > hi) hi = v; }
    return [Math.round(lo), Math.round(hi)];
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

    // flat map: look straight down, framed on the same target
    const aspect = this.width / Math.max(1, this.height);
    const span = clamp(c.dist * 0.40, 110, 900);
    this.ortho.left = -span * aspect; this.ortho.right = span * aspect;
    this.ortho.top = span; this.ortho.bottom = -span;
    this.ortho.position.set(c.tx, 1400, c.tz + 0.001);
    this.ortho.up.set(0, 0, -1);
    this.ortho.lookAt(c.tx, 0, c.tz);
    this.ortho.updateProjectionMatrix();
    this.ortho.updateMatrixWorld();

    // shadow frustum follows the view so close-ups keep crisp tree shadows
    const size = clamp(c.dist * 0.62, 180, 1000);
    const s = this.sun.shadow.camera;
    s.left = -size; s.right = size; s.top = size; s.bottom = -size;
    s.far = size * 6 + 600;
    s.updateProjectionMatrix();
    this.sun.position.set(c.tx - size * 1.5, c.ty + size * 1.9, c.tz + size * 1.25);
    this.sun.target.position.set(c.tx, c.ty, c.tz);
    this.sun.target.updateMatrixWorld();
  }

  activeCamera() { return this.state.dim === "2d" ? this.ortho : this.camera; }

  /* ── picking ────────────────────────────────────────────────────────── */
  pick(px, py) {
    if (!this.markerMesh.visible) return null;
    const ndc = new THREE.Vector2((px / this.width) * 2 - 1, -(py / this.height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(ndc, this.activeCamera());
    ray.params.Mesh = { threshold: 0 };
    const target = this.state.dim === "2d" ? this.dots : this.markerMesh;
    const hits = ray.intersectObject(target, false);
    if (!hits.length) return null;
    const id = hits[0].instanceId;
    return id == null ? null : this.markers[id];
  }

  selectMarker(marker) {
    if (!marker) { this.selectRing.visible = false; return; }
    this.selectRing.visible = true;
    this.selectRing.position.set(marker.x, marker.y + 1.5, marker.z);
  }

  /* ── render ─────────────────────────────────────────────────────────── */
  resize(width, height) {
    this.width = width; this.height = height;
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / Math.max(1, height);
    this.camera.updateProjectionMatrix();
  }

  updateLabels() {
    const cam = this.activeCamera();
    const v = new THREE.Vector3();
    const camPos = cam.position;
    const placed = [];
    // Region pins matter most, then dated trail pins, then districts; anything
    // that would land on top of an already-placed pill is dropped.
    const order = { region: 0, date: 1 };
    const sorted = this.labels.slice().sort((a, b) => (order[a.kind] ?? 2) - (order[b.kind] ?? 2));
    for (const l of sorted) {
      if (l.hiddenByFocus) { l.node.style.display = "none"; continue; }
      v.copy(l.pos).project(cam);
      const behind = v.z > 1 || v.z < -1;
      const x = (v.x * 0.5 + 0.5) * this.width;
      const y = (-v.y * 0.5 + 0.5) * this.height;
      const dist = camPos.distanceTo(l.pos);
      const half = (l.node.offsetWidth || 90) / 2;
      // a pill that would be clipped by the viewport edge is dropped, not cropped
      let show = !behind && x - half > 2 && x + half < this.width - 2 && y > 8 && y < this.height - 4;
      if (l.kind.includes("district")) show = show && dist < 760;
      if (l.kind.includes("date")) show = show && this.trail.visible && (l.at == null || l.at <= (this.timeCut ?? Infinity));
      if (l.kind === "region") show = show && dist < 2600;
      if (show) {
        const h2 = l.node.offsetHeight || 20;
        const box = [x - half, y - h2, x + half, y];
        if (placed.some((q) => box[0] < q[2] + 6 && box[2] > q[0] - 6 && box[1] < q[3] + 4 && box[3] > q[1] - 4)) show = false;
        else placed.push(box);
      }
      l.node.style.display = show ? "" : "none";
      if (show) {
        l.node.style.left = `${x.toFixed(1)}px`;
        l.node.style.top = `${y.toFixed(1)}px`;
      }
    }
  }

  render() {
    this.applyCamera();
    this.renderer.render(this.scene, this.activeCamera());
    this.updateLabels();
  }

  /* Drop pixel ratio, then shadows, if the page can't hold ~48fps. Never in
     capture mode, where frames must be identical every run. */
  measure(dt) {
    if (this.capture) return;
    this.frameTimes.push(dt);
    if (this.frameTimes.length < 60) return;
    const avg = this.frameTimes.reduce((a, b) => a + b, 0) / this.frameTimes.length;
    this.frameTimes = [];
    if (avg < 1000 / 48) return;
    if (this.quality.pixelRatio > 1) {
      this.quality.pixelRatio = 1;
      this.renderer.setPixelRatio(1);
      this.resize(this.width, this.height);
    } else if (this.quality.shadows) {
      this.quality.shadows = false;
      this.renderer.shadowMap.enabled = false;
      this.forest.castShadow = false;
      this.renderer.shadowMap.needsUpdate = true;
    } else if (this.forest.count > 7000) {
      this.forest.count = 7000;
    }
  }
}

function disposeTree(root) {
  root.traverse((o) => {
    if (o.geometry) o.geometry.dispose();
    if (o.material) (Array.isArray(o.material) ? o.material : [o.material]).forEach((m) => m.dispose());
  });
}
