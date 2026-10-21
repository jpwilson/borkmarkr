/* The landscape: a ridged heightfield, its vertex colouring, the water, the
   forests, and the draped overlays (region tints, outlines, trails) that sit
   on top of it. Everything samples one cached height grid, so a marker, a
   dashed trail and a tree all stand on exactly the surface that is drawn. */
import * as THREE from "three";
import { MAP } from "./atlas-layout.js";

/* ── Noise ──────────────────────────────────────────────────────────────── */
const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);
const clamp01 = (v) => Math.min(1, Math.max(0, v));

function gradient(ix, iz, seed) {
  let h = (seed ^ Math.imul(ix, 374761393) ^ Math.imul(iz, 668265263)) >>> 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177) >>> 0;
  const a = ((h ^ (h >>> 16)) >>> 0) * 1.4629180792671596e-9; // 2π / 2^32
  return [Math.cos(a), Math.sin(a)];
}

/* Classic gradient noise, -1..1. */
function perlin(x, z, seed) {
  const x0 = Math.floor(x), z0 = Math.floor(z);
  const fx = x - x0, fz = z - z0;
  const u = fade(fx), v = fade(fz);
  const dot = (ix, iz, dx, dz) => { const g = gradient(ix, iz, seed); return g[0] * dx + g[1] * dz; };
  const n00 = dot(x0, z0, fx, fz), n10 = dot(x0 + 1, z0, fx - 1, fz);
  const n01 = dot(x0, z0 + 1, fx, fz - 1), n11 = dot(x0 + 1, z0 + 1, fx - 1, fz - 1);
  return (n00 + (n10 - n00) * u) + ((n01 + (n11 - n01) * u) - (n00 + (n10 - n00) * u)) * v;
}

function fbm(x, z, seed, octaves = 5, lac = 2.03, gain = 0.5) {
  let sum = 0, amp = 1, norm = 0, f = 1;
  for (let o = 0; o < octaves; o++) {
    sum += perlin(x * f, z * f, seed + o * 7919) * amp;
    norm += amp; amp *= gain; f *= lac;
  }
  return sum / norm;
}

/* Ridged multifractal: the sharp crests and V-shaped valleys the reference
   terrain is made of. */
function ridged(x, z, seed, octaves = 8, lac = 2.0, gain = 0.58) {
  let sum = 0, amp = 1, norm = 0, f = 1, prev = 1;
  for (let o = 0; o < octaves; o++) {
    let n = 1 - Math.abs(perlin(x * f, z * f, seed + o * 104729) * 1.9);
    n = Math.max(0, n);
    n *= n;
    sum += n * amp * prev;
    prev = 0.55 + 0.45 * n;
    norm += amp; amp *= gain; f *= lac;
  }
  return sum / norm;
}

/* ── Height field ───────────────────────────────────────────────────────── */
export const GRID = 560;                 // cells across the terrain plate
const CELL = (MAP.PLATE * 2) / GRID;
const F = 1 / 1150;                      // first ridge octave ≈ 1150 m across

/* Ridged noise sits around 0.45 with little contrast; stretching it is what
   turns soft hills into crests and V-shaped valleys. */
const crest = (v) => Math.min(1.35, Math.max(-0.4, (v - 0.33) * 2.25));

export function buildHeightField(layout) {
  const n = GRID + 1;
  const data = new Float32Array(n * n);
  const regions = layout.regions;

  for (let j = 0; j < n; j++) {
    const z = -MAP.PLATE + j * CELL;
    for (let i = 0; i < n; i++) {
      const x = -MAP.PLATE + i * CELL;
      // warp the lattice so crests wander instead of running in straight lines
      const wx = x + fbm(x * F * 0.7, z * F * 0.7, 311, 3) * 380 + fbm(x * F * 3.4, z * F * 3.4, 1811, 2) * 48;
      const wz = z + fbm(x * F * 0.7 + 40, z * F * 0.7 - 40, 733, 3) * 380 + fbm(x * F * 3.4 + 9, z * F * 3.4 + 3, 1933, 2) * 48;
      const main = crest(ridged(wx * F, wz * F, 1337, 7, 2.0, 0.43));
      const cross = crest(ridged(wz * F * 1.81 + 11, wx * F * 1.81 - 7, 7717, 4, 2.0, 0.43));
      // Surface texture, not another ridged octave: three smooth bands, the
      // finest still four cells wide, so hillsides have grain without the
      // field of identical pyramids that aliasing produces.
      const grain = fbm(x * F * 8.5, z * F * 8.5, 4409, 3);
      const fine = fbm(x * F * 19, z * F * 19, 6421, 3);
      const micro = fbm(x * F * 44, z * F * 44, 7717, 2);
      // The close-up frames look at a patch ~150 units wide, so the only
      // detail that can read there lives at the grid's own resolution: two
      // more bands at roughly 22 m and 14 m, the finest the cell can carry.
      const rough = fbm(x * F * 52, z * F * 52, 1559, 2);
      const nano = fbm(x * F * 82, z * F * 82, 3301, 2);
      const broad = fbm(x * F * 0.42, z * F * 0.42, 5521, 4);

      // every region is a massif: high ground with the ridges still running
      // over it, so topics read as named ranges rather than separate pimples
      let lift = 0, mask = 0;
      for (const r of regions) {
        const d = Math.hypot(x - r.x, z - r.z) / (r.rMax * 1.3);
        if (d > 1.5) continue;
        const f = Math.exp(-d * d * 1.9);
        lift += f * (46 + 54 * (r.r / MAP.R_MAX));
        mask = Math.max(mask, f);
      }

      const amp = 126 + 76 * mask + 52 * broad;
      let h = 18 + broad * 70 + lift + main * amp + cross * amp * 0.42;
      // Ease the ridges where a region sits, so districts stand on ground
      // rather than on a cliff. The flattening is applied to the ridge system
      // only — the surface grain below is added afterwards, so a plateau still
      // has texture instead of turning into a sheet of clay.
      if (mask > 0.38) {
        const k = Math.min(0.62, (mask - 0.38) * 1.1);
        h = h * (1 - k) + (lift + 78 + broad * 30) * k;
      }
      h += grain * 26 + fine * 17 + micro * 8 + rough * 7 + nano * 4;

      // coast: a ragged shoreline well out past the atlas, then open water
      const rad = Math.hypot(x, z) + fbm(x * F * 1.1, z * F * 1.1, 9173, 3) * 190;
      if (rad > MAP.SHORE) {
        const t = Math.min(1, (rad - MAP.SHORE) / 330);
        h = h * (1 - t * t) + (MAP.WATER - 48) * (t * t);
      }
      data[j * n + i] = h;
    }
  }

  const sample = (x, z) => {
    const fx = (x + MAP.PLATE) / CELL, fz = (z + MAP.PLATE) / CELL;
    const i = Math.min(n - 2, Math.max(0, Math.floor(fx))), j = Math.min(n - 2, Math.max(0, Math.floor(fz)));
    const tx = Math.min(1, Math.max(0, fx - i)), tz = Math.min(1, Math.max(0, fz - j));
    const a = data[j * n + i], b = data[j * n + i + 1], c = data[(j + 1) * n + i], d = data[(j + 1) * n + i + 1];
    return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * tz;
  };
  const slope = (x, z) => {
    const e = CELL;
    const dx = sample(x + e, z) - sample(x - e, z);
    const dz = sample(x, z + e) - sample(x, z - e);
    return Math.hypot(dx, dz) / (2 * e);
  };
  return { data, n, cell: CELL, sample, slope };
}

/* ── Terrain mesh ───────────────────────────────────────────────────────── */
const C = {
  shallow: new THREE.Color("#93a09f"),
  beach: new THREE.Color("#ded0b2"),
  sand: new THREE.Color("#d8c8a4"),
  meadow: new THREE.Color("#9aa275"),
  sage: new THREE.Color("#73855a"),
  ochre: new THREE.Color("#c7ad80"),
  tan: new THREE.Color("#bca684"),
  rock: new THREE.Color("#8f877a"),
  cliff: new THREE.Color("#79736a"),
  scree: new THREE.Color("#c3bba9"),
  clay: new THREE.Color("#b59a74"),
};

/* Height picks the band, slope pulls it towards bare rock, and a mottling
   noise keeps a band from reading as one flat wash. */
function terrainColor(h, s, m, out) {
  let c;
  if (h < MAP.WATER + 4) c = C.shallow.clone().lerp(C.beach, Math.max(0, (h - MAP.WATER + 16) / 22));
  else if (h < 30) c = C.beach.clone().lerp(C.meadow, Math.min(1, Math.max(0, (h - MAP.WATER - 4) / 40)));
  else if (h < 92) c = C.meadow.clone().lerp(C.ochre, Math.min(1, (h - 30) / 62));
  else if (h < 160) c = C.ochre.clone().lerp(C.tan, Math.min(1, (h - 92) / 68));
  else if (h < 215) c = C.tan.clone().lerp(C.rock, Math.min(1, (h - 160) / 55));
  else c = C.rock.clone().lerp(C.scree, Math.min(1, (h - 215) / 80));
  if (s > 0.32) c.lerp(C.cliff, Math.min(0.88, (s - 0.32) * 1.35));
  if (h > 4 && h < 180) c.lerp(C.sage, Math.max(0, m - 0.5) * 1.0 * (1 - Math.min(1, s)));
  if (m < 0.42) c.lerp(C.clay, (0.42 - m) * 0.9);
  const k = 0.9 + 0.2 * m;
  out.setRGB(c.r * k, c.g * k, c.b * k);
  return out;
}

/* How much forest wants to grow at a point: broad connected masses with a
   soft fringe, so a wood covers a whole hillside instead of speckling it. */
export function canopyAt(x, z) {
  const broad = 0.5 + 0.5 * fbm(x * F * 1.75, z * F * 1.75, 8111, 4);
  const grain = 0.5 + 0.5 * fbm(x * F * 5.5, z * F * 5.5, 2287, 3);
  // The field is narrow around 0.5, so it is stretched about its own mean:
  // a chunk of the country is full canopy, a chunk is bare ridge and scree,
  // and the rest is the fringe in between.
  const v = (broad * 0.72 + grain * 0.28 - 0.5) / 0.105;
  return clamp01(v * 0.85 + 0.34);
}

/* Trees need the canopy field, a height band between the shore and the
   treeline, and ground they can hold on to. Ridges and screes stay bare,
   which is what gives the dark masses their edges. */
export function treeFitness(field, x, z) {
  const h = field.sample(x, z);
  if (h < 8 || h > 252) return 0;
  const band = h < 30 ? (h - 8) / 22 : h > 196 ? Math.max(0, (252 - h) / 56) : 1;
  const sl = field.slope(x, z);
  if (sl > 1.32) return 0;
  const hold = sl > 0.92 ? 1 - (sl - 0.92) * 1.6 : 1;
  return canopyAt(x, z) * band * Math.max(0, hold);
}

export function buildTerrain(field) {
  const n = field.n;
  const geo = new THREE.PlaneGeometry(MAP.PLATE * 2, MAP.PLATE * 2, GRID, GRID);
  geo.rotateX(-Math.PI / 2);
  const pos = geo.attributes.position;
  const colors = new Float32Array(pos.count * 3);
  const tmp = new THREE.Color();
  const H = (i, j) => field.data[Math.min(n - 1, Math.max(0, j)) * n + Math.min(n - 1, Math.max(0, i))];
  for (let j = 0; j < n; j++) {
    for (let i = 0; i < n; i++) {
      const k = j * n + i;
      const h = field.data[k];
      pos.setY(k, h);
      const x = -MAP.PLATE + i * field.cell, z = -MAP.PLATE + j * field.cell;
      const mottle = clamp01(0.5 + 0.55 * fbm(x * F * 5.2, z * F * 5.2, 4211, 3)
        + 0.2 * fbm(x * F * 17, z * F * 17, 9311, 2)
        + 0.26 * fbm(x * F * 70, z * F * 70, 4441, 2));
      terrainColor(h, field.slope(x, z), mottle, tmp);
      // Concave ground is in shadow far more often than convex ground; baking
      // that in is what turns a smooth hillside into readable gullies.
      const curve = h - (H(i - 1, j) + H(i + 1, j) + H(i, j - 1) + H(i, j + 1)) / 4;
      const ao = Math.max(0.52, Math.min(1.16, 1 + curve * 0.06));
      // Woodland floor. The canopy is painted into the ground as well as
      // instanced, so a hillside stays a dark mass when distance thins the
      // trees out, and the two always agree on where the wood is.
      const wood = treeFitness(field, x, z);
      const r = tmp.r * ao, g = tmp.g * ao, b = tmp.b * ao;
      const k1 = wood * 0.56, k2 = wood * 0.46, k3 = wood * 0.62;
      colors[k * 3] = r * (1 - k1) + 0.175 * k1;
      colors[k * 3 + 1] = g * (1 - k2) + 0.238 * k2;
      colors[k * 3 + 2] = b * (1 - k3) + 0.135 * k3;
    }
  }
  geo.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  geo.computeVertexNormals();
  // Smooth normals, not flat shading: at this cell size flat shading turns
  // every hillside into a mosaic of plates. The faceting that remains comes
  // from the heightfield itself.
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.96, metalness: 0, flatShading: false });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  mesh.castShadow = true;
  mesh.name = "terrain";
  return mesh;
}

export function buildWater() {
  const geo = new THREE.PlaneGeometry(26000, 26000, 1, 1).rotateX(-Math.PI / 2);
  const mat = new THREE.MeshStandardMaterial({ color: "#879aa3", roughness: 0.35, metalness: 0.08 });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.y = MAP.WATER;
  mesh.receiveShadow = false;
  mesh.name = "water";
  return mesh;
}

/* A pale gradient dome: cool at the zenith, warm haze at the horizon. No sun
   disc, no bloom — the sky is only here to give the ridges something to fade
   into. */
export function buildSky() {
  const geo = new THREE.SphereGeometry(11000, 32, 20);
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: {
      top: { value: new THREE.Color("#c0ccd2") },
      mid: { value: new THREE.Color("#ccd3d2") },
      bottom: { value: new THREE.Color("#d6d8d1") },
    },
    vertexShader: "varying float vH; void main(){ vec4 w = modelMatrix * vec4(position,1.0); vH = normalize(w.xyz).y; gl_Position = projectionMatrix * viewMatrix * w; }",
    fragmentShader: `varying float vH; uniform vec3 top; uniform vec3 mid; uniform vec3 bottom;
      void main(){ float h = clamp(vH, -1.0, 1.0);
        vec3 c = h > 0.0 ? mix(mid, top, pow(h, 0.55)) : mix(mid, bottom, pow(-h, 1.4));
        gl_FragColor = vec4(c, 1.0); }`,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = "sky";
  mesh.renderOrder = -1;
  return mesh;
}

/* ── Forests and rocks ──────────────────────────────────────────────────── */
function coneGeometry(r, h, seg) {
  const g = new THREE.ConeGeometry(r, h, seg, 2);
  g.translate(0, h / 2, 0);
  return g;
}

/* Thousands of conifers on the slopes that would actually hold trees: above
   the beach, below the scree line, off the cliffs, and clumped by a density
   noise so the forest has edges and clearings. */
/* A deterministic 0..1 stream — the forests must look identical on every
   run so captured frames match. */
function rng(seed) {
  let t = (seed | 0) + 0x6d2b79f5;
  return () => {
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* Three conifer silhouettes so a wood isn't one shape repeated: a narrow
   spire, a broader fir and a squat one. All small — a tree is texture here,
   not a landmark. */
function treeGeometries() {
  const spire = new THREE.ConeGeometry(2.5, 9.4, 5, 2);
  spire.translate(0, 4.7, 0);
  const fir = new THREE.ConeGeometry(3.3, 7.2, 6, 2);
  fir.translate(0, 3.6, 0);
  const squat = new THREE.ConeGeometry(3.6, 5.2, 5, 1);
  squat.translate(0, 2.6, 0);
  return [spire, fir, squat];
}

/* Forests on a jittered grid rather than by rejection sampling: inside a
   canopy mass every cell gets a tree, so the crowns close up into a
   continuous dark surface, and the mass has a soft fringe where the field
   falls away. Tiled into cullable instanced meshes with distance LOD. */
export function scatterTrees(field, { spacing = 5.2, seed = 17, tiles = 10, max = 190000 } = {}) {
  const reach = MAP.PLATE - 40;
  const span = (reach * 2) / tiles;
  const geos = treeGeometries();
  const mats = geos.map(() => new THREE.MeshStandardMaterial({ roughness: 0.93, metalness: 0, flatShading: true }));
  const deep = new THREE.Color("#30432a"), mid = new THREE.Color("#44593a"), dusty = new THREE.Color("#67764e");

  const buckets = [];
  for (let ty = 0; ty < tiles; ty++) for (let tx = 0; tx < tiles; tx++) buckets.push({ tx, ty, list: [[], [], []] });
  const r = rng(seed);
  const col = new THREE.Color();
  const steps = Math.floor((reach * 2) / spacing);
  let placed = 0;
  for (let gz = 0; gz < steps && placed < max; gz++) {
    for (let gx = 0; gx < steps && placed < max; gx++) {
      const x = -reach + (gx + 0.5) * spacing + (r() - 0.5) * spacing * 0.92;
      const z = -reach + (gz + 0.5) * spacing + (r() - 0.5) * spacing * 0.92;
      const fit = treeFitness(field, x, z);
      // hard core, soft fringe: almost every cell inside a wood is taken
      if (fit < 0.04) continue;
      if (fit < 0.5 && r() > fit * 1.9) continue;
      const h = field.sample(x, z);
      const kind = r() < 0.5 ? 0 : r() < 0.78 ? 1 : 2;
      const tall = 0.72 + 0.62 * Math.pow(r(), 1.3) * (h > 170 ? 0.8 : 1);
      const wide = tall * (0.82 + 0.34 * r());
      const tx = Math.min(tiles - 1, Math.floor((x + reach) / span));
      const ty = Math.min(tiles - 1, Math.floor((z + reach) / span));
      const t = r();
      col.copy(deep).lerp(t > 0.88 ? dusty : mid, t * (h > 130 ? 0.92 : 0.62));
      buckets[ty * tiles + tx].list[kind].push([x, h - 0.7, z, wide, tall, r() * Math.PI * 2, col.r, col.g, col.b]);
      placed++;
    }
  }

  const group = new THREE.Group();
  group.name = "forest";
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), sc = new THREE.Vector3();
  const axis = new THREE.Vector3(0, 1, 0);
  for (const bucket of buckets) {
    bucket.list.forEach((list, kind) => {
      if (!list.length) return;
      const mesh = new THREE.InstancedMesh(geos[kind], mats[kind], list.length);
      mesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 3), 3);
      list.forEach((t, i) => {
        p.set(t[0], t[1], t[2]);
        sc.set(t[3], t[4], t[3]);
        q.setFromAxisAngle(axis, t[5]);
        m.compose(p, q, sc);
        mesh.setMatrixAt(i, m);
        mesh.instanceColor.setXYZ(i, t[6], t[7], t[8]);
      });
      mesh.instanceMatrix.needsUpdate = true;
      mesh.instanceColor.needsUpdate = true;
      mesh.castShadow = true;
      mesh.receiveShadow = false;
      mesh.computeBoundingSphere();
      mesh.userData.full = list.length;
      mesh.userData.centre = new THREE.Vector2((bucket.tx + 0.5) * span - reach, (bucket.ty + 0.5) * span - reach);
      group.add(mesh);
    });
  }
  group.userData.total = placed;
  return group;
}

export function scatterScrub(field, { count = 150000, seed = 404, tiles = 8 } = {}) {
  // only over the atlas itself: this is close-up texture, and nothing ever
  // flies low over the scenery beyond it
  const reach = 640;
  const span = (reach * 2) / tiles;
  const geo = new THREE.IcosahedronGeometry(1, 0);
  geo.scale(1, 0.55, 1);
  const mat = new THREE.MeshStandardMaterial({ roughness: 1, metalness: 0, flatShading: true });
  const shrub = new THREE.Color("#44512f"), stone = new THREE.Color("#938872"), dry = new THREE.Color("#72653f");
  const buckets = Array.from({ length: tiles * tiles }, () => []);
  const r = rng(seed);
  const col = new THREE.Color();
  let placed = 0, tries = 0;
  while (placed < count && tries < count * 8) {
    tries++;
    const x = (r() * 2 - 1) * reach, z = (r() * 2 - 1) * reach;
    const h = field.sample(x, z);
    if (h < 2 || h > 290) continue;
    const sl = field.slope(x, z);
    const open = 1 - treeFitness(field, x, z) * 0.85;
    if (r() > 0.22 + 0.5 * open) continue;
    const scale = 1.5 + 3.4 * Math.pow(r(), 1.7);
    const t = r();
    if (t < 0.62 && sl < 1.0) col.copy(shrub).lerp(dry, r() * 0.7);
    else col.copy(stone).lerp(dry, r() * 0.6);
    const tx = Math.min(tiles - 1, Math.floor((x + reach) / span));
    const ty = Math.min(tiles - 1, Math.floor((z + reach) / span));
    buckets[ty * tiles + tx].push([x, h - scale * 0.3, z, scale * (0.8 + 0.6 * r()), scale, r() * 3, col.r, col.g, col.b]);
    placed++;
  }
  const group = new THREE.Group();
  group.name = "scrub";
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), sc = new THREE.Vector3();
  const axis = new THREE.Vector3(0, 1, 0);
  buckets.forEach((list, i) => {
    if (!list.length) return;
    const mesh = new THREE.InstancedMesh(geo, mat, list.length);
    mesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(list.length * 3), 3);
    list.forEach((t, k) => {
      p.set(t[0], t[1], t[2]);
      sc.set(t[3], t[4], t[3]);
      q.setFromAxisAngle(axis, t[5]);
      m.compose(p, q, sc);
      mesh.setMatrixAt(k, m);
      mesh.instanceColor.setXYZ(k, t[6], t[7], t[8]);
    });
    mesh.instanceMatrix.needsUpdate = true;
    mesh.instanceColor.needsUpdate = true;
    mesh.castShadow = false;
    mesh.receiveShadow = false;
    mesh.computeBoundingSphere();
    mesh.userData.full = list.length;
    const tx = i % tiles, ty = Math.floor(i / tiles);
    mesh.userData.centre = new THREE.Vector2((tx + 0.5) * span - reach, (ty + 0.5) * span - reach);
    group.add(mesh);
  });
  group.userData.total = placed;
  return group;
}

export function scatterRocks(field, { count = 2600, seed = 91 } = {}) {
  const geo = new THREE.IcosahedronGeometry(1.9, 1);
  const mat = new THREE.MeshStandardMaterial({ color: "#8c8478", roughness: 1, metalness: 0, flatShading: true });
  const mesh = new THREE.InstancedMesh(geo, mat, count);
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
  const r = rng(seed);
  const reach = MAP.PLATE - 40;
  let placed = 0, tries = 0;
  while (placed < count && tries < count * 40) {
    tries++;
    const x = (r() * 2 - 1) * reach, z = (r() * 2 - 1) * reach;
    const h = field.sample(x, z);
    if (h < 10) continue;
    const sl = field.slope(x, z);
    if (sl < 0.55 && h < 150) continue;
    const scale = 0.45 + 1.4 * r();
    p.set(x, h - 1.5, z);
    s.set(scale * 1.4, scale * 0.75, scale);
    q.setFromEuler(new THREE.Euler(r() * 3, r() * 3, r() * 3));
    m.compose(p, q, s);
    mesh.setMatrixAt(placed++, m);
  }
  mesh.count = placed;
  mesh.instanceMatrix.needsUpdate = true;
  mesh.castShadow = true;
  mesh.name = "rocks";
  mesh.frustumCulled = false;
  return mesh;
}

/* ── Draped overlays ────────────────────────────────────────────────────── */

/* A translucent tint that follows the ground inside a wobbly boundary. Built
   on a polar grid so it fits the outline exactly without any clipping. */
export function drapeDisc(cx, cz, boundaryPts, field, { lift = 1.4, rings = 16 } = {}) {
  const spokes = boundaryPts.length;
  const verts = [], idx = [], rgba = [], radial = [];
  for (let r = 0; r <= rings; r++) {
    const t = r / rings;
    // faint over the middle of a region, firmer towards its edge
    const a = 0.22 + 0.78 * Math.pow(t, 2.0);
    for (let s = 0; s < spokes; s++) {
      const [bx, bz] = boundaryPts[s];
      const x = cx + (bx - cx) * t, z = cz + (bz - cz) * t;
      verts.push(x, field.sample(x, z) + lift, z);
      rgba.push(1, 1, 1, a);
      radial.push(t);
    }
  }
  for (let r = 0; r < rings; r++) {
    for (let s = 0; s < spokes; s++) {
      const a = r * spokes + s, b = r * spokes + ((s + 1) % spokes);
      const c = (r + 1) * spokes + s, d = (r + 1) * spokes + ((s + 1) % spokes);
      // wound counter-clockwise seen from above, so the tint faces the camera
      idx.push(a, b, c, b, d, c);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.Float32BufferAttribute(verts, 3));
  geo.setAttribute("color", new THREE.Float32BufferAttribute(rgba, 4));
  geo.setAttribute("aT", new THREE.Float32BufferAttribute(radial, 1));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

/* A constant-width ribbon laid on the ground: the perimeter outlines, the
   district edges and the reading trail are all this. `dash` drops alternate
   chunks so a dashed line stays dashed at any camera distance. */
export function ribbon(points, field, { width = 2.6, lift = 2.0, closed = false, dash = 0, gap = 0 } = {}) {
  const pts = closed ? [...points, points[0]] : points;
  if (pts.length < 2) return new THREE.BufferGeometry();
  const verts = [], idx = [];
  let run = 0, quad = 0;
  const half = width / 2;
  for (let i = 0; i < pts.length - 1; i++) {
    const [x0, z0] = pts[i], [x1, z1] = pts[i + 1];
    const dx = x1 - x0, dz = z1 - z0;
    const len = Math.hypot(dx, dz) || 1e-6;
    const nx = -dz / len, nz = dx / len;
    const steps = Math.max(1, Math.ceil(len / 3.2));
    for (let s = 0; s < steps; s++) {
      const t0 = s / steps, t1 = (s + 1) / steps;
      const seg = len / steps;
      if (dash > 0 && (Math.floor(run / dash) % (1 + Math.max(1, Math.round(gap / dash)))) !== 0) { run += seg; continue; }
      const ax = x0 + dx * t0, az = z0 + dz * t0;
      const bx = x0 + dx * t1, bz = z0 + dz * t1;
      // Height comes from the centre line, so the ribbon stays a flat band
      // across its width and never tears apart on a steep slope.
      const ay = field.sample(ax, az) + lift, by = field.sample(bx, bz) + lift;
      const base = quad * 4;
      verts.push(
        ax + nx * half, ay, az + nz * half,
        ax - nx * half, ay, az - nz * half,
        bx + nx * half, by, bz + nz * half,
        bx - nx * half, by, bz - nz * half,
      );
      idx.push(base, base + 2, base + 1, base + 1, base + 2, base + 3);
      quad++;
      run += seg;
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.Float32BufferAttribute(verts, 3));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

export { fbm, ridged, perlin };

/* ── Surface detail without geometry ────────────────────────────────────── */

/* The heightfield can only carry detail down to its cell size; below that a
   close-up turns to clay. This perturbs the shading normal with a procedural
   noise in world space, which is what makes a hillside read as ground rather
   than as a smooth plate — no extra triangles, and it costs one texture-free
   noise in the fragment shader. */
export function applyDetailNormals(material, { scale = 1 / 5.0, strength = 0.55 } = {}) {
  material.userData.detail = { strength: { value: strength }, scale: { value: scale } };
  material.onBeforeCompile = (shader) => {
    shader.uniforms.uDetailStrength = material.userData.detail.strength;
    shader.uniforms.uDetailScale = material.userData.detail.scale;
    shader.vertexShader = shader.vertexShader
      .replace("#include <common>", "#include <common>\nvarying vec2 vDetailXZ;")
      .replace("#include <begin_vertex>", "#include <begin_vertex>\nvDetailXZ = (modelMatrix * vec4(transformed, 1.0)).xz;");
    shader.fragmentShader = shader.fragmentShader
      .replace("#include <common>", `#include <common>
varying vec2 vDetailXZ;
uniform float uDetailStrength;
uniform float uDetailScale;
float bmHash(vec2 p){ p = fract(p * vec2(127.1, 311.7)); p += dot(p, p + 42.17); return fract(p.x * p.y); }
float bmNoise(vec2 p){
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(bmHash(i), bmHash(i + vec2(1.0, 0.0)), u.x),
             mix(bmHash(i + vec2(0.0, 1.0)), bmHash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float bmField(vec2 p){ return bmNoise(p) + 0.52 * bmNoise(p * 2.13) + 0.26 * bmNoise(p * 4.41); }`)
      .replace("#include <normal_fragment_begin>", `#include <normal_fragment_begin>
if (uDetailStrength > 0.001) {
  vec2 q = vDetailXZ * uDetailScale;
  float e = 0.6;
  float n0 = bmField(q);
  float nx = bmField(q + vec2(e, 0.0));
  float nz = bmField(q + vec2(0.0, e));
  normal = normalize(normal + vec3(-(nx - n0), 0.0, -(nz - n0)) * uDetailStrength);
}`);
  };
  material.customProgramCacheKey = () => "atlas-detail-normals";
  return material;
}

export function setDetailStrength(material, strength) {
  if (material.userData.detail) material.userData.detail.strength.value = strength;
}

/* ── The spreading front ────────────────────────────────────────────────── */

/* A region's tint, clipped to how much of it has filled up by the current
   timeline date. `front` is the square root of the share of that region's
   bookmarks saved so far, so the band grows by area as saves accumulate —
   the same idea as a fire perimeter drawn at a given hour. The leading edge
   is a brighter band, never a glow. */
export function spreadMaterial(color) {
  const mat = new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    side: THREE.FrontSide,
    polygonOffset: true,
    polygonOffsetFactor: -4,
    polygonOffsetUnits: -4,
    uniforms: {
      uColor: { value: new THREE.Color(color) },
      uOpacity: { value: 0.3 },
      uFront: { value: 1 },
      uEdge: { value: 0.07 },
    },
    vertexShader: `attribute float aT; varying float vT;
      void main(){ vT = aT; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `varying float vT;
      uniform vec3 uColor; uniform float uOpacity; uniform float uFront; uniform float uEdge;
      void main(){
        if (vT > uFront) discard;
        float band = smoothstep(uFront - uEdge, uFront, vT);
        vec3 c = mix(uColor, clamp(uColor * 1.45 + 0.08, 0.0, 1.0), band);
        float a = uOpacity * (0.42 + 0.58 * pow(vT, 1.3)) + band * uOpacity * 1.25;
        gl_FragColor = vec4(c, clamp(a, 0.0, 0.92));
      }`,
  });
  mat.userData.baseOpacity = 1;
  mat.userData.baseTransparent = true;
  return mat;
}
