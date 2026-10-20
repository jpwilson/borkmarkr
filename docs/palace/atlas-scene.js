/* The viewport: landscape, draped data, markers, labels, the flat 2D map and
   the camera rig. Nothing in here invents a number — positions come from
   atlas-layout.js and colours come from the model. */
import * as THREE from "three";
import { MAP, libraryBounds } from "./atlas-layout.js";
import {
  buildHeightField, buildTerrain, buildWater, buildSky,
  scatterTrees, scatterRocks, scatterScrub, drapeDisc, ribbon,
} from "./atlas-terrain.js";

const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
export const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

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
    this.quality = { pixelRatio: Math.min(capture ? 1 : 1.6, window.devicePixelRatio || 1), shadows: true, forest: 1 };
    this.frameTimes = [];
    this.hovered = null;
    this.markerScale = 1;
    this.width = 1;
    this.height = 1;
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
    trackMaterial(this.terrain.material);
    this.water = buildWater();
    trackMaterial(this.water.material);
    this.forest = scatterTrees(this.field, { count: 120000 });
    this.forest.traverse((o) => { if (o.material) trackMaterial(o.material); });
    this.rocks = scatterRocks(this.field, { count: 3200 });
    trackMaterial(this.rocks.material);
    this.scrub = scatterScrub(this.field, { count: 150000 });
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
      const fill = new THREE.Mesh(
        drapeDisc(region.x, region.z, region.boundary, this.field, { lift: 0.9, rings: 22 }),
        trackMaterial(new THREE.MeshBasicMaterial({
          color, vertexColors: true, transparent: true, opacity: 0.24, depthWrite: false, side: THREE.FrontSide,
          polygonOffset: true, polygonOffsetFactor: -4, polygonOffsetUnits: -4,
        })),
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
          ribbon(district.boundary, this.field, { width: 0.9, lift: 1.6, closed: true, dash: 6, gap: 5 }),
          trackMaterial(new THREE.MeshBasicMaterial({
            color: color.clone().multiplyScalar(0.62), transparent: true, opacity: 0.8, depthWrite: false,
            side: THREE.DoubleSide, polygonOffset: true, polygonOffsetFactor: -9, polygonOffsetUnits: -9,
          })),
        );
        dash.renderOrder = 3;
        dgroup.add(dash);
      }
      this.edges.add(dgroup);
      this.regionNodes.set(region.id, { fill, line, dgroup, region });
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
  }

  /* Dashed reading trail with arrowheads and dated pins, drawn with a pale
     halo underneath so it stays readable on sand and on forest alike. */
  buildTrail(pins) {
    if (this.trail) { this.world.remove(this.trail); disposeTree(this.trail); }
    if (this.flatTrail) { this.map2d.remove(this.flatTrail); disposeTree(this.flatTrail); this.flatTrail = null; }
    this.trail = new THREE.Group();
    this.trailPins = pins || [];
    this.world.add(this.trail);
    if (!pins || pins.length < 2) { this.trailPath = []; return; }

    // Catmull-Rom through the pins: a smooth path reads as a route, and the
    // chase camera that follows it stops snapping at every corner.
    const curve = new THREE.CatmullRomCurve3(pins.map((p) => new THREE.Vector3(p.x, 0, p.z)), false, "catmullrom", 0.35);
    const path = curve.getPoints(Math.max(32, pins.length * 14)).map((v) => [v.x, v.z]);
    this.trailPath = path;
    this.trailCurve = curve;

    const halo = new THREE.Mesh(
      ribbon(path, this.field, { width: 4.2, lift: 1.5, dash: 9, gap: 7 }),
      trackMaterial(new THREE.MeshBasicMaterial({ color: "#F3EEE2", depthWrite: false, transparent: true, opacity: 0.75, side: THREE.DoubleSide })),
    );
    halo.renderOrder = 5;
    const line = new THREE.Mesh(
      ribbon(path, this.field, { width: 2.4, lift: 1.8, dash: 9, gap: 7 }),
      trackMaterial(new THREE.MeshBasicMaterial({ color: "#D9482B", depthWrite: false, transparent: true, opacity: 0.98, side: THREE.DoubleSide })),
    );
    line.renderOrder = 6;
    this.trail.add(halo, line);

    const head = new THREE.ConeGeometry(2.1, 5.8, 4).rotateX(Math.PI / 2);
    const mat = trackMaterial(new THREE.MeshBasicMaterial({ color: "#D9482B", depthWrite: false, transparent: true, opacity: 0.98 }));
    for (let i = 3; i < path.length - 1; i += 12) {
      const [x0, z0] = path[i], [x1, z1] = path[Math.min(path.length - 1, i + 1)];
      const arrow = new THREE.Mesh(head, mat);
      arrow.position.set(x0, this.field.sample(x0, z0) + 3.4, z0);
      arrow.rotation.y = Math.atan2(x1 - x0, z1 - z0);
      arrow.renderOrder = 7;
      this.trail.add(arrow);
    }
    const postGeo = new THREE.CylinderGeometry(0.4, 0.4, 1, 5);
    postGeo.translate(0, 0.5, 0);
    const postMat = trackMaterial(new THREE.MeshBasicMaterial({ color: "#1E1C19" }));
    for (const pin of pins) {
      const post = new THREE.Mesh(postGeo, postMat);
      post.position.set(pin.x, this.field.sample(pin.x, pin.z), pin.z);
      post.scale.y = 15;
      this.trail.add(post);
    }

    // the same route, flat, for the 2D map
    const flat = { sample: () => 0, slope: () => 0 };
    this.flatTrail = new THREE.Group();
    this.flatTrail.add(
      new THREE.Mesh(ribbon(path, flat, { width: 3.2, lift: 0.5, dash: 8, gap: 6 }),
        trackMaterial(new THREE.MeshBasicMaterial({ color: "#F6F2E7", transparent: true, opacity: 0.9 }))),
      new THREE.Mesh(ribbon(path, flat, { width: 1.6, lift: 0.7, dash: 8, gap: 6 }),
        trackMaterial(new THREE.MeshBasicMaterial({ color: "#D9482B" }))),
    );
    for (let i = 3; i < path.length - 1; i += 12) {
      const [ax, az] = path[i], [bx, bz] = path[Math.min(path.length - 1, i + 1)];
      const a2 = new THREE.Mesh(new THREE.ConeGeometry(2.2, 6, 4).rotateX(Math.PI / 2),
        trackMaterial(new THREE.MeshBasicMaterial({ color: "#D9482B" })));
      a2.position.set(ax, 0.9, az);
      a2.rotation.y = Math.atan2(bx - ax, bz - az);
      this.flatTrail.add(a2);
    }
    this.map2d.add(this.flatTrail);
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
    const MONTH = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    (this.trailPins || []).forEach((pin, i) => {
      if (pin.at == null) return;
      const d = new Date(pin.at);
      const txt = `${MONTH[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
      this.addLabel("date", pin.x, this.field.sample(pin.x, pin.z) + 21, pin.z, (node) => {
        const span = document.createElement("span");
        span.className = "pill";
        span.textContent = txt;
        node.appendChild(span);
        const stem = document.createElement("span");
        stem.className = "stem";
        node.appendChild(stem);
      }, { trailIndex: i, at: pin.at });
    });
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
    this.rocks.visible = on("terrain") && !flat;
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

    for (const [id, node] of this.regionNodes) {
      const key = `reg:${id}`;
      const hidden = this.state.hidden.has(key);
      const groupOp = this.state.groupOpacity.get(key) ?? 1;
      const modeDim = this.state.mode === "sources" ? 0.5 : 1;
      const focusDim = this.state.focus && this.state.focus !== id ? 0.42 : 1;
      node.fill.visible = !hidden;
      node.line.visible = !hidden;
      node.dgroup.visible = !hidden && on("edges");
      setOpacity(node.fill, op("tints") * groupOp * modeDim * focusDim);
      setOpacity(node.line, op("tints") * groupOp * (this.state.focus && this.state.focus !== id ? 0.45 : 1));
      setOpacity(node.dgroup, op("edges") * groupOp * focusDim);
      const m2 = this.map2dRegions.get(id);
      if (m2) {
        m2.node.visible = !hidden;
        setOpacity(m2.fill, op("tints") * groupOp * focusDim);
        setOpacity(m2.line, op("tints") * groupOp);
        m2.dgroup.visible = on("edges");
        setOpacity(m2.dgroup, op("edges") * groupOp * focusDim);
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
    this.updateForestLOD();
  }

  /* Distance detail for the woods: far tiles thin out instead of the whole
     forest being cut to a stub when a frame runs long. */
  updateForestLOD() {
    const cam = this.camera.position;
    const q = this.quality.forest;
    for (const tile of this.forest.children) {
      const c = tile.userData.centre;
      const d = Math.hypot(cam.x - c.x, cam.z - c.y);
      const keep = d < 900 ? 1 : d < 1600 ? 0.8 : d < 2400 ? 0.5 : 0.25;
      tile.count = Math.max(1, Math.round(tile.userData.full * keep * q));
    }
    // ground cover only matters close up; past a few hundred metres it is
    // sub-pixel and costs a draw call for nothing
    for (const tile of this.scrub.children) {
      const c = tile.userData.centre;
      const d = Math.hypot(cam.x - c.x, cam.z - c.y);
      const keep = d < 460 ? 1 : d < 820 ? 0.7 : d < 1400 ? 0.3 : 0.08;
      tile.count = Math.max(1, Math.round(tile.userData.full * keep * q));
    }
  }

  activeCamera() { return this.state.dim === "2d" ? this.ortho : this.camera; }

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

  selectMarker(marker) {
    if (!marker) { this.selectRing.visible = false; return; }
    this.selectRing.visible = true;
    this.selectRing.scale.setScalar(this.markerScale);
    this.selectRing.position.set(marker.x, marker.y + 1.2, marker.z);
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
      if (l.kind.includes("date")) show = show && this.trail.visible && (l.at == null || l.at <= (this.timeCut ?? Infinity));
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
    this.renderer.render(this.scene, this.activeCamera());
    this.updateLabels();
  }

  /* Drop pixel ratio, then shadows, then forest density, if the page can't
     hold ~48fps. Never in capture mode, where frames must be identical. */
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
      this.renderer.shadowMap.needsUpdate = true;
    } else if (this.quality.forest > 0.3) {
      this.quality.forest = Math.max(0.3, this.quality.forest - 0.25);
    }
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
