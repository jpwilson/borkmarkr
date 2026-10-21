/* island-flora.js — the jungle.

   Tens of thousands of instanced clumps: lumpy broadleaf canopy in clustered
   masses, emergent trees breaking the canopy line, palms on the sand,
   mangroves in the marsh, dry scrub on the ash and the summits, and crowns on
   the limestone towers. Every instance carries the terrain's baked sun
   visibility, so a ridge shadow falls across the trees as well as the ground.

   Instance order is shuffled once, deterministically, so dropping quality
   thins the forest evenly across the island instead of deleting a stripe. */
import * as THREE from "three";
import { sampleGrid, groundAt, PAL, ATMOS_PARS } from "./island-terrain.js";
import { clamp, mix, sstep, noise2, fbm, coastField, riverSample, zoneField, ISLAND_R } from "./island-layout.js";

const mixc = (a, b, t) => [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];

/* ── blob geometry: a squashed, dented ball of leaves ───────────────────── */
function blobGeometry({ bands = 3, segs = 9, squash = 0.74, dent = 0.3, seed = 1, pinch = 0.55 } = {}) {
  const pos = [], nrm = [], col = [], idx = [];
  const rows = [];
  for (let b = 0; b <= bands + 1; b++) {
    const phi = (b / (bands + 1)) * Math.PI;
    const row = [];
    for (let s = 0; s < segs; s++) {
      const th = (s / segs) * Math.PI * 2;
      let r = 1 + dent * noise2(Math.cos(th) * 1.7 + seed * 3.1, Math.sin(th) * 1.7 + phi * 2.3);
      r *= 1 - pinch * Math.pow(clamp((phi - Math.PI * 0.55) / (Math.PI * 0.45), 0, 1), 1.6);
      const x = Math.sin(phi) * Math.cos(th) * r;
      const z = Math.sin(phi) * Math.sin(th) * r;
      const y = Math.cos(phi) * r * squash;
      const up = clamp(y * 0.5 + 0.55, 0, 1.2);
      // dark underside, sunlit crown, a touch of yellow in the highlights
      const c = mixc(mixc([0.030, 0.052, 0.018], [0.14, 0.27, 0.052], Math.pow(up, 1.45)), [0.37, 0.42, 0.10], Math.pow(up, 4.5) * 0.55);
      const l = Math.hypot(x, y, z) || 1;
      row.push(pos.length / 3);
      pos.push(x, y + 0.26, z); nrm.push(x / l, y / l, z / l); col.push(c[0], c[1], c[2]);
    }
    rows.push(row);
  }
  for (let b = 0; b < rows.length - 1; b++) for (let s = 0; s < segs; s++) {
    const a = rows[b][s], c = rows[b][(s + 1) % segs];
    const d = rows[b + 1][s], e = rows[b + 1][(s + 1) % segs];
    idx.push(a, d, c, c, d, e);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute("color", new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  return g;
}

/* ── a palm: tapered trunk and a crown of drooping fronds ───────────────── */
function palmGeometry() {
  const pos = [], nrm = [], col = [], idx = [];
  const push = (x, y, z, n, c) => { pos.push(x, y, z); nrm.push(n[0], n[1], n[2]); col.push(c[0], c[1], c[2]); return pos.length / 3 - 1; };
  const bark = [0.17, 0.13, 0.08], barkLit = [0.3, 0.24, 0.14];
  const H = 1, R = 0.055;
  const SEG = 5, STEPS = 4;
  const rings = [];
  for (let s = 0; s <= STEPS; s++) {
    const t = s / STEPS;
    const y = t * H;
    const lean = t * t * 0.13;
    const r = R * (1 - t * 0.45);
    const row = [];
    for (let i = 0; i < SEG; i++) {
      const a = (i / SEG) * Math.PI * 2;
      row.push(push(Math.cos(a) * r + lean, y, Math.sin(a) * r,
        [Math.cos(a), 0.15, Math.sin(a)], mixc(bark, barkLit, 0.3 + 0.5 * Math.cos(a - 2.2) * 0.5 + 0.3 * t)));
    }
    rings.push(row);
  }
  for (let s = 0; s < STEPS; s++) for (let i = 0; i < SEG; i++) {
    const j = (i + 1) % SEG;
    idx.push(rings[s][i], rings[s + 1][i], rings[s][j], rings[s][j], rings[s + 1][i], rings[s + 1][j]);
  }
  const top = [0.13 + 0.13, H, 0];
  for (let f = 0; f < 7; f++) {
    const a = (f / 7) * Math.PI * 2 + 0.4;
    const dx = Math.cos(a), dz = Math.sin(a);
    const L = 0.46 + 0.1 * noise2(f * 2.1, 1.3);
    const droop = 0.2 + 0.16 * noise2(f, 4.4);
    const mid = [top[0] + dx * L * 0.55, top[1] + 0.1 - droop * 0.1, top[2] + dz * L * 0.55];
    const tip = [top[0] + dx * L, top[1] - droop, top[2] + dz * L];
    const w = 0.085;
    const px = -dz * w, pz = dx * w;
    const n = [0, 1, 0];
    const cBase = [0.14, 0.26, 0.07], cTip = [0.3, 0.44, 0.1];
    const a0 = push(top[0], top[1] + 0.02, top[2], n, cBase);
    const m1 = push(mid[0] + px, mid[1], mid[2] + pz, n, mixc(cBase, cTip, 0.5));
    const m2 = push(mid[0] - px, mid[1], mid[2] - pz, n, mixc(cBase, cTip, 0.5));
    const t1 = push(tip[0] + px * 0.3, tip[1], tip[2] + pz * 0.3, n, cTip);
    const t2 = push(tip[0] - px * 0.3, tip[1], tip[2] - pz * 0.3, n, cTip);
    idx.push(a0, m1, m2, m1, t1, t2, m1, t2, m2);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute("color", new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  return g;
}

/* ── an emergent tree: bare trunk, flat wide crown ──────────────────────── */
function emergentGeometry() {
  const trunk = new THREE.CylinderGeometry(0.035, 0.07, 1.0, 5, 1, true);
  trunk.translate(0, 0.5, 0);
  const tp = trunk.getAttribute("position");
  const tc = [];
  for (let i = 0; i < tp.count; i++) {
    const t = tp.getY(i);
    const c = mixc([0.13, 0.1, 0.07], [0.3, 0.25, 0.16], 0.3 + 0.4 * t);
    tc.push(c[0], c[1], c[2]);
  }
  trunk.setAttribute("color", new THREE.Float32BufferAttribute(tc, 3));
  const crown = blobGeometry({ bands: 3, segs: 9, squash: 0.42, dent: 0.34, seed: 5.5, pinch: 0.3 });
  crown.scale(0.52, 0.5, 0.52);
  crown.translate(0, 0.96, 0);
  return mergeGeos([trunk.toNonIndexed(), crown.toNonIndexed()]);
}

function mergeGeos(list) {
  const pos = [], nrm = [], col = [];
  for (const g of list) {
    const p = g.getAttribute("position"), n = g.getAttribute("normal"), c = g.getAttribute("color");
    for (let i = 0; i < p.count; i++) {
      pos.push(p.getX(i), p.getY(i), p.getZ(i));
      nrm.push(n.getX(i), n.getY(i), n.getZ(i));
      col.push(c.getX(i), c.getY(i), c.getZ(i));
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute("color", new THREE.Float32BufferAttribute(col, 3));
  return g;
}

/* ── mangrove: dark crown over a cone of stilt roots ────────────────────── */
function mangroveGeometry() {
  const crown = blobGeometry({ bands: 2, segs: 8, squash: 0.5, dent: 0.36, seed: 2.2, pinch: 0.4 });
  crown.scale(1, 0.8, 1);
  crown.translate(0, 0.55, 0);
  const roots = new THREE.ConeGeometry(0.55, 0.62, 7, 1, true);
  roots.translate(0, 0.31, 0);
  const rp = roots.getAttribute("position"), rc = [];
  for (let i = 0; i < rp.count; i++) rc.push(0.1, 0.085, 0.055);
  roots.setAttribute("color", new THREE.Float32BufferAttribute(rc, 3));
  return mergeGeos([roots.toNonIndexed(), crown.toNonIndexed()]);
}

/* ── the foliage shader ─────────────────────────────────────────────────── */
export function floraMaterial(uniforms, { sway = 1 } = {}) {
  return new THREE.ShaderMaterial({
    uniforms,
    vertexShader: /* glsl */`
      attribute vec3 ilit;
      uniform float uTime, uSway;
      varying vec3 vWorld; varying vec3 vNormal; varying vec3 vColor; varying vec3 vLit;
      void main() {
        vec3 p = position;
        vec4 wp = modelMatrix * instanceMatrix * vec4(p, 1.0);
        float phase = wp.x * 0.012 + wp.z * 0.009;
        float gust = sin(uTime * 0.55 + phase) * 0.6 + sin(uTime * 1.23 + phase * 2.1) * 0.4;
        wp.xz += gust * uSway * max(0.0, p.y) * 0.85;
        vWorld = wp.xyz;
        vNormal = normalize(mat3(instanceMatrix) * normal);
        vColor = color * instanceColor;
        vLit = ilit;
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      varying vec3 vNormal; varying vec3 vColor; varying vec3 vLit;
      void main() {
        vec3 n = normalize(vNormal);
        vec3 viewDir = normalize(cameraPosition - vWorld);
        float shade = vLit.x, ao = vLit.y;
        float ndl = dot(n, uSunDir);
        float sun = pow(clamp((ndl + 0.4) / 1.4, 0.0, 1.0), 1.3) * mix(0.16, 1.0, shade);
        vec3 light = uSunColor * sun;
        light += uSkyColor * (0.33 + 0.26 * n.y) * ao;
        light += uGroundColor * 0.14 * ao;
        // leaves glow where the low sun comes through them
        float trans = pow(clamp(dot(viewDir, -uSunDir), 0.0, 1.0), 2.2) * clamp(0.6 - ndl, 0.0, 1.0);
        light += uSunColor * trans * 0.55 * shade;
        vec3 color = vColor * light;
        vec3 hv = normalize(uSunDir + viewDir);
        color += uSunColor * pow(max(dot(n, hv), 0.0), 26.0) * 0.07 * shade;
        color = applyAtmos(color, vWorld, -viewDir);
        gl_FragColor = vec4(color * uExposure, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
    vertexColors: true,
  });
}

/* ── scatter ────────────────────────────────────────────────────────────── */
function rng(seed) {
  let s = seed >>> 0;
  return () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296);
}
function shuffled(list, seed) {
  const r = rng(seed);
  for (let i = list.length - 1; i > 0; i--) {
    const j = Math.floor(r() * (i + 1));
    const t = list[i]; list[i] = list[j]; list[j] = t;
  }
  return list;
}

const VOLCANO = { x: -150, z: -330 };

/* How much jungle a spot can hold, 0..1. The biome differences people read
   from the air — bare ash, pale karst, open temple plaza, marsh, dunes — are
   mostly this function saying no. */
function canopyDensity(field, x, z, h, slope, moist, zone, temple) {
  if (h < 3.5 || h > 820) return 0;
  if (slope > 2.0) return 0;
  let d = 0.25 + 0.95 * moist;
  d *= clamp(1.4 - slope * 0.42, 0.22, 1);
  d *= sstep(3.5, 16, h);
  d *= 1 - 0.8 * sstep(560, 760, h);
  const vd = Math.hypot(x - VOLCANO.x, z - VOLCANO.z);
  d *= clamp(sstep(110, 340, vd), 0.0, 1);                       // ash cone is bare
  if (temple) d *= clamp(sstep(72, 170, Math.hypot(x - temple.x, z - temple.z)), 0.08, 1);
  const beach = sstep(80, 20, coastField(x, z)) * sstep(24, 8, h);
  d *= 1 - 0.9 * beach;
  if (zone.gap < 14 && slope < 0.8) d *= 0.12;                   // keep the trail open
  return clamp(d, 0, 1);
}

export function buildFlora(field, layout, uniforms, stacks) {
  const sites = field.sites;
  const temple = layout.zones.find((z) => z.siteId === "temple") || null;
  const canopy = [], emergent = [], palms = [], mangroves = [], scrub = [];
  const R = ISLAND_R + 60;
  const CLUSTERS = 21000;
  const r = rng(99173);

  for (let i = 0; i < CLUSTERS; i++) {
    // jittered golden-angle disc: even coverage, no grid artefacts
    const a = i * 2.3999632;
    const rad = R * Math.sqrt((i + 0.5) / CLUSTERS) * (0.985 + 0.03 * r());
    const cx = Math.cos(a) * rad + (r() - 0.5) * 26;
    const cz = Math.sin(a) * rad + (r() - 0.5) * 26;
    const h = groundAt(field, cx, cz);
    const slope = sampleGrid(field, field.slope, cx, cz);
    const moist = sampleGrid(field, field.moist, cx, cz);
    const zone = zoneField(cx, cz, sites);
    const shade = clamp(sampleGrid(field, field.shade, cx, cz), 0, 1);
    const ao = clamp(sampleGrid(field, field.ao, cx, cz), 0, 1);

    // beaches and spits get palms
    const coast = coastField(cx, cz);
    if (h > 2.2 && h < 26 && coast < 110 && slope < 0.33) {
      if (r() < 0.5) {
        const s = 8 + 7 * r();
        palms.push({ x: cx, z: cz, y: h - 0.5, s, yaw: r() * 6.28, tint: [0.85 + 0.3 * r(), 0.9 + 0.25 * r(), 0.8 + 0.3 * r()], shade, ao });
      }
      if (r() < 0.25) scrub.push({ x: cx, z: cz, y: h, s: 2.2 + 2 * r(), yaw: r() * 6.28, tint: [1.0, 0.98, 0.72], shade, ao, dry: 1 });
      continue;
    }
    // marsh: mangroves standing in the shallows
    const marshD = Math.hypot(cx + 740, cz - 520);
    if (marshD < 420 && h > 1 && h < 20) {
      const n = 1 + Math.floor(r() * 2);
      for (let k = 0; k < n; k++) {
        const s = 7 + 6 * r();
        mangroves.push({ x: cx + (r() - 0.5) * 30, z: cz + (r() - 0.5) * 30, y: h - 1.5, s, yaw: r() * 6.28,
          tint: [0.6 + 0.25 * r(), 0.72 + 0.25 * r(), 0.5 + 0.3 * r()], shade, ao });
      }
      continue;
    }

    const d = canopyDensity(field, cx, cz, h, slope, moist, zone, temple);
    if (d <= 0.02) {
      // bare ground still gets dry scrub, which keeps the ash and the summits
      // from reading as empty polygons
      if (h > 6 && h < 860 && slope < 2.2 && r() < 0.55) {
        const dry = clamp(1 - moist, 0, 1);
        scrub.push({ x: cx, z: cz, y: h, s: 2.4 + 3.4 * r(), yaw: r() * 6.28,
          tint: [0.85 + 0.5 * dry, 0.8 + 0.3 * dry, 0.45 + 0.2 * dry], shade, ao, dry });
      }
      continue;
    }
    // a clump of 1–5 crowns, so the canopy is lumpy rather than evenly dotted
    const n = 2 + Math.floor(d * 5.2 * (0.6 + 0.8 * r()));
    const spreadR = 9 + 15 * r();
    for (let k = 0; k < n; k++) {
      const ka = r() * 6.283, kr = spreadR * Math.sqrt(r());
      const x = cx + Math.cos(ka) * kr, z = cz + Math.sin(ka) * kr;
      const y = groundAt(field, x, z);
      if (y < 2.5) continue;
      const s = (5.5 + 9.5 * r()) * (0.8 + 0.45 * d);
      const wet = clamp(moist + 0.25 * (r() - 0.5), 0, 1);
      // tint: wetter is deeper and bluer, drier is olive and yellow
      const tint = [mix(1.18, 0.78, wet) + 0.16 * (r() - 0.5), mix(0.92, 1.05, wet) + 0.14 * (r() - 0.5), mix(0.62, 0.88, wet) + 0.12 * (r() - 0.5)];
      canopy.push({ x, z, y: y - s * 0.16, s, yaw: r() * 6.28, tint, shade, ao, moist: wet });
    }
    // the tall ones that break the canopy line
    if (r() < 0.05 * d && h > 40 && h < 620) {
      const s = 22 + 20 * r();
      emergent.push({ x: cx, z: cz, y: h - 1, s, yaw: r() * 6.28,
        tint: [0.82 + 0.2 * r(), 0.95 + 0.15 * r(), 0.7 + 0.2 * r()], shade, ao, moist });
    }
  }

  // crowns clinging to the limestone towers
  for (const st of (stacks || [])) {
    const topY = st.sea ? -26 + st.h : st.h;
    const n = 7 + Math.floor(r() * 7);
    for (let k = 0; k < n; k++) {
      const a = r() * 6.283, rr = st.r * 0.32 * Math.sqrt(r());
      canopy.push({ x: st.x + Math.cos(a) * rr, z: st.z + Math.sin(a) * rr, y: topY + 2,
        s: 9 + 11 * r(), yaw: r() * 6.28, tint: [0.8 + 0.2 * r(), 1.0, 0.72 + 0.2 * r()], shade: 1, ao: 0.95, moist: 0.5 });
    }
    // ledge growth down the flanks
    for (let k = 0; k < 6; k++) {
      const a = r() * 6.283, t = 0.25 + 0.6 * r();
      const rr = st.r * (0.75 - 0.3 * t);
      canopy.push({ x: st.x + Math.cos(a) * rr, z: st.z + Math.sin(a) * rr, y: topY - st.h * (1 - t),
        s: 6 + 7 * r(), yaw: r() * 6.28, tint: [0.7, 0.95, 0.6], shade: 0.8, ao: 0.7, moist: 0.6 });
    }
  }

  const group = new THREE.Group();
  group.name = "flora";
  const made = [];
  const add = (name, geo, list, seed, sway, flatten = 1) => {
    if (!list.length) return;
    shuffled(list, seed);
    const mesh = new THREE.InstancedMesh(geo, floraMaterial(uniforms, {}), list.length);
    const lit = new Float32Array(list.length * 3);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), s = new THREE.Vector3();
    const col = new THREE.Color();
    list.forEach((it, i) => {
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), it.yaw);
      p.set(it.x, it.y, it.z);
      s.set(it.s, it.s * flatten * (0.85 + 0.3 * ((i * 37) % 100) / 100), it.s);
      m.compose(p, q, s);
      mesh.setMatrixAt(i, m);
      col.setRGB(it.tint[0], it.tint[1], it.tint[2]);
      mesh.setColorAt(i, col);
      lit[i * 3] = it.shade; lit[i * 3 + 1] = it.ao; lit[i * 3 + 2] = it.moist ?? 0.4;
    });
    mesh.geometry.setAttribute("ilit", new THREE.InstancedBufferAttribute(lit, 3));
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    mesh.name = name;
    mesh.frustumCulled = true;
    mesh.userData.full = list.length;
    mesh.userData.tris = (geo.index ? geo.index.count : geo.getAttribute("position").count) / 3 * list.length;
    group.add(mesh);
    made.push(mesh);
  };

  const canopyGeo = blobGeometry({ bands: 3, segs: 9, squash: 0.66, dent: 0.44, seed: 1.1, pinch: 0.3 });
  const scrubGeo = blobGeometry({ bands: 2, segs: 7, squash: 0.62, dent: 0.4, seed: 7.3, pinch: 0.5 });
  add("canopy", canopyGeo, canopy, 7717, 1);
  add("emergent", emergentGeometry(), emergent, 3391, 1);
  add("palm", palmGeometry(), palms, 5519, 1);
  add("mangrove", mangroveGeometry(), mangroves, 8821, 1);
  add("scrub", scrubGeo, scrub, 2203, 1);

  group.userData.meshes = made;
  group.userData.total = canopy.length + emergent.length + palms.length + mangroves.length + scrub.length;
  group.userData.counts = { canopy: canopy.length, emergent: emergent.length, palm: palms.length, mangrove: mangroves.length, scrub: scrub.length };
  return group;
}

/* Thin every layer by the same fraction; order is already shuffled, so the
   thinning is spatially even. */
export function setFloraDensity(group, frac) {
  for (const mesh of group.userData.meshes) {
    mesh.count = Math.max(1, Math.round(mesh.userData.full * frac));
  }
}
