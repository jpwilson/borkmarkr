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
import { clamp, mix, sstep, noise2, fbm, coastField, riverSample, zoneField, ISLAND_R, CAMP_CLEAR, CAMP_FADE } from "./island-layout.js";

const mixc = (a, b, t) => [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];

/* ── blob geometry: a squashed, dented ball of leaves ───────────────────── */
/* `lobes` is what stops a crown reading as a toy: instead of one ball, the
   radius picks up a handful of smooth bulges pointing in fixed directions,
   so the silhouette breaks into overlapping masses the way a broadleaf crown
   does. Three seeds give three shapes, which is enough variety at any
   distance you can tell one tree from another. */
function blobGeometry({ bands = 3, segs = 9, squash = 0.74, dent = 0.3, seed = 1, pinch = 0.55, lobes = 0 } = {}) {
  const pos = [], nrm = [], col = [], idx = [];
  const rows = [];
  // lobe directions, spread over the upper hemisphere by the golden angle
  const lobeDirs = [];
  for (let k = 0; k < lobes; k++) {
    const t = (k + 0.5) / lobes;
    const phi = Math.acos(1 - 0.92 * t);
    const th = k * 2.3999632 + seed * 2.1;
    lobeDirs.push({
      x: Math.sin(phi) * Math.cos(th), y: Math.cos(phi), z: Math.sin(phi) * Math.sin(th),
      amp: 0.33 + 0.38 * Math.abs(noise2(k * 1.7 + seed, 3.3)),
      w: 0.62 + 0.34 * Math.abs(noise2(k * 2.9 - seed, 5.1)),
    });
  }
  for (let b = 0; b <= bands + 1; b++) {
    const phi = (b / (bands + 1)) * Math.PI;
    const row = [];
    for (let s = 0; s < segs; s++) {
      const th = (s / segs) * Math.PI * 2;
      // sample the lumps in the sphere's own space: smooth across the surface,
      // so a crown reads as a billow of leaves rather than a spiky star
      const sx = Math.sin(phi) * Math.cos(th), sy = Math.cos(phi), sz = Math.sin(phi) * Math.sin(th);
      let r = 1 + dent * (noise2(sx * 1.15 + seed * 3.1, sz * 1.15 + sy * 1.15)
                        + 0.5 * noise2(sx * 2.6 - seed, sz * 2.6 + sy * 2.2));
      let lobeAt = 0;
      for (const L of lobeDirs) {
        const d = sx * L.x + sy * L.y + sz * L.z;              // cosine to the lobe
        const bump = Math.exp(-Math.pow((1 - d) / L.w, 2) * 2.4) * L.amp;
        lobeAt = Math.max(lobeAt, bump);
        r += bump * 0.45;
      }
      r *= 1 - pinch * Math.pow(clamp((phi - Math.PI * 0.55) / (Math.PI * 0.45), 0, 1), 1.6);
      const x = Math.sin(phi) * Math.cos(th) * r;
      const z = Math.sin(phi) * Math.sin(th) * r;
      const y = Math.cos(phi) * r * squash;
      const up = clamp(y * 0.5 + 0.55, 0, 1.2);
      // dark underside, sunlit crown, a touch of yellow in the highlights; the
      // saddles between lobes keep the shadow even where the crown faces up
      const lit = Math.pow(up, 1.8) * (0.52 + 0.48 * clamp(lobeAt / 0.36, 0, 1));
      const c = mixc(mixc([0.011, 0.020, 0.008], [0.082, 0.163, 0.034], lit), [0.21, 0.27, 0.062], Math.pow(up, 5.5) * 0.55);
      const l = Math.hypot(x, y, z) || 1;
      row.push(pos.length / 3);
      pos.push(x, y + 0.26, z); nrm.push(x / l, y / l, z / l); col.push(c[0], c[1], c[2]);
    }
    rows.push(row);
  }
  for (let b = 0; b < rows.length - 1; b++) for (let s = 0; s < segs; s++) {
    const a = rows[b][s], c = rows[b][(s + 1) % segs];
    const d = rows[b + 1][s], e = rows[b + 1][(s + 1) % segs];
    idx.push(a, c, d, c, e, d);
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
    idx.push(rings[s][i], rings[s][j], rings[s + 1][i], rings[s][j], rings[s + 1][j], rings[s + 1][i]);
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
  const trunk = new THREE.CylinderGeometry(0.06, 0.12, 0.5, 6, 1, true);
  trunk.translate(0, 0.25, 0);
  const tp = trunk.getAttribute("position");
  const tc = [];
  for (let i = 0; i < tp.count; i++) {
    const t = tp.getY(i);
    const c = mixc([0.13, 0.1, 0.07], [0.3, 0.25, 0.16], 0.3 + 0.4 * t);
    tc.push(c[0], c[1], c[2]);
  }
  trunk.setAttribute("color", new THREE.Float32BufferAttribute(tc, 3));
  const crown = blobGeometry({ bands: 3, segs: 10, squash: 0.74, dent: 0.18, seed: 5.5, pinch: 0.42, lobes: 4 });
  crown.scale(0.92, 0.58, 0.92);
  crown.translate(0, 0.42, 0);
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
  const crown = blobGeometry({ bands: 3, segs: 9, squash: 0.5, dent: 0.3, seed: 2.2, pinch: 0.4, lobes: 3 });
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
      varying float vUp;
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
        // where this vertex sits in its own crown: 0 underside, 1 sunlit top
        vUp = clamp(p.y * 0.62 + 0.42, 0.0, 1.0);
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      uniform sampler2D uDetail;
      varying vec3 vNormal; varying vec3 vColor; varying vec3 vLit; varying float vUp;
      void main() {
        vec3 n = normalize(vNormal);
        vec3 viewDir = normalize(cameraPosition - vWorld);
        // leaf clumps: a crown is not a smooth surface, it is a few hundred
        // sprays of leaves. Two world-space octaves break the normal up so the
        // shading stops reading as moulded plastic.
        // fade it out with distance: at a kilometre it is only aliasing
        float near = 1.0 - smoothstep(260.0, 1500.0, length(vWorld - cameraPosition));
        vec2 ca = vWorld.xz * 0.17 + vWorld.y * 0.06;
        vec2 cb = vWorld.zy * 0.52 - vWorld.x * 0.05;
        float c1 = texture2D(uDetail, ca).r - 0.5;
        float c2 = texture2D(uDetail, cb).g - 0.5;
        float c3 = texture2D(uDetail, ca * 3.1 + 0.31).b - 0.5;
        n = normalize(n + vec3(c1 + c3 * 0.6, (c1 + c2) * 0.28, c2 + c3 * 0.6) * mix(0.16, 0.52, near));

        float shade = vLit.x, ao = vLit.y;
        // ambient occlusion by height: the holes between crowns go dark, which
        // is what gives an aerial its texture instead of a field of highlights
        float deep = mix(0.26, 1.0, pow(vUp, 1.35));
        float ndl = dot(n, uSunDir);
        float sun = pow(clamp(ndl * 0.56 + 0.44, 0.0, 1.0), 1.5) * mix(0.13, 1.0, shade) * mix(0.42, 1.0, vUp);
        vec3 light = uSunColor * sun;
        light += uSkyColor * (0.30 + 0.26 * n.y) * ao * deep;
        light += uGroundColor * 0.13 * ao * deep;
        // leaves glow where the low sun comes through them
        float trans = pow(clamp(dot(viewDir, -uSunDir), 0.0, 1.0), 2.2) * clamp(0.6 - ndl, 0.0, 1.0);
        light += uSunColor * trans * 0.6 * shade * vUp;
        vec3 color = vColor * light;
        // a thin hot edge where a crown turns away into the sun
        float rim = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 2.6) * clamp(ndl * 0.6 + 0.4, 0.0, 1.0);
        color += uSunColor * rim * 0.26 * shade * vUp;
        vec3 hv = normalize(uSunDir + viewDir);
        color += uSunColor * pow(max(dot(n, hv), 0.0), 26.0) * 0.06 * shade;
        color = applyAtmos(color, vWorld, -viewDir);
        gl_FragColor = vec4(color * uExposure, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
    vertexColors: true,
    side: THREE.DoubleSide,
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

/* A stand of jungle is not one plant. Most crowns are plain green; a tenth
   are the pale yellow-green of new growth, a tenth the blue-green of the
   shade species, and a rare few are flowering — the red specks that stop an
   aerial from reading as a single colour. */
function species(u) {
  if (u < 0.11) return [1.40, 1.05, 0.46];
  if (u < 0.23) return [0.62, 0.97, 1.06];
  if (u < 0.255) return [1.62, 0.70, 0.50];
  return [1, 1, 1];
}

/* How much jungle a spot can hold, 0..1. The biome differences people read
   from the air — bare ash, pale karst, open temple plaza, marsh, dunes — are
   mostly this function saying no. */
function canopyDensity(field, x, z, h, slope, moist, zone, temple, camps) {
  if (h < 3.5 || h > 820) return 0;
  if (slope > 2.0) return 0;
  let d = 0.25 + 0.95 * moist;
  d *= clamp(1.4 - slope * 0.42, 0.22, 1);
  d *= sstep(3.5, 16, h);
  d *= 1 - 0.8 * sstep(560, 760, h);
  const vd = Math.hypot(x - VOLCANO.x, z - VOLCANO.z);
  d *= clamp(sstep(250, 560, vd), 0.0, 1);                       // ash cone is bare
  if (temple) d *= clamp(sstep(110, 250, Math.hypot(x - temple.x, z - temple.z)), 0.06, 1);
  const beach = sstep(80, 20, coastField(x, z)) * sstep(24, 8, h);
  d *= 1 - 0.9 * beach;
  // the river keeps its corridor open, so the valley reads from the air
  const riv = riverSample(x, z);
  d *= clamp(sstep(42, 115, riv.d), 0.0, 1);
  // natural clearings: grass shelves, slips, outcrops
  d *= clamp(0.55 + 1.1 * fbm(x * 0.0034 + 41.2, z * 0.0034 - 7.8, 2), 0, 1);
  if (zone.gap < 40 && slope < 1.15) d *= 0.05 + 0.9 * sstep(14, 40, zone.gap);                   // keep the trail open
  // a camp stands in a clearing, the way a camp does — and the camera relies
  // on it: island-layout's canopyTopAt cuts the same hole, to the metre
  if (camps) for (const c of camps) {
    const cd = Math.hypot(x - c.x, z - c.z);
    if (cd < CAMP_CLEAR) return 0;
    if (cd < CAMP_FADE) d *= sstep(CAMP_CLEAR, CAMP_FADE, cd);
  }
  return clamp(d, 0, 1);
}

export function buildFlora(field, layout, uniforms, stacks) {
  const sites = field.sites;
  const temple = layout.zones.find((z) => z.siteId === "temple") || null;
  const canopy = [], emergent = [], palms = [], mangroves = [], scrub = [];
  // one clearing per camp, not per marker: markers cluster tightly
  const camps = layout.clearings || [];
  const R = ISLAND_R + 60;
  const CLUSTERS = 23000;
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
    if (marshD < 430 && h > 1 && h < 30) {
      const n = 1 + Math.floor(r() * 2);
      for (let k = 0; k < n; k++) {
        const s = 7 + 6 * r();
        mangroves.push({ x: cx + (r() - 0.5) * 30, z: cz + (r() - 0.5) * 30, y: h - 1.5, s, yaw: r() * 6.28,
          tint: [0.6 + 0.25 * r(), 0.72 + 0.25 * r(), 0.5 + 0.3 * r()], shade, ao });
      }
      continue;
    }

    const d = canopyDensity(field, cx, cz, h, slope, moist, zone, temple, camps);
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
    const n = 1 + Math.floor(d * 3.4 * (0.6 + 0.8 * r()));
    const spreadR = 12 + 20 * r();
    for (let k = 0; k < n; k++) {
      const ka = r() * 6.283, kr = spreadR * Math.sqrt(r());
      const x = cx + Math.cos(ka) * kr, z = cz + Math.sin(ka) * kr;
      const y = groundAt(field, x, z);
      if (y < 2.5) continue;
      // size: mostly small, with a long tail of big crowns. A rainforest seen
      // from above is a few giants among a mass of ordinary trees, not a tray
      // of equal balls.
      const s = (5.5 + 34 * Math.pow(r(), 2.4)) * (0.78 + 0.45 * d);
      const wet = clamp(moist + 0.25 * (r() - 0.5), 0, 1);
      // tint: wetter is deeper and bluer, drier is olive and yellow
      // large-scale mottling: whole stands of canopy go dark or bright,
      // which is what stops an aerial reading as one flat green
      const mot = 0.46 + 1.05 * clamp(0.5 + 0.75 * fbm(x * 0.0021 + 17.3, z * 0.0021 - 9.1, 3), 0, 1);
      const v = mot * (0.66 + 0.68 * r());
      const hue = species(r());
      const tint = [
        v * hue[0] * (mix(1.26, 0.74, wet) + 0.26 * (r() - 0.5)),
        v * hue[1] * (mix(0.95, 1.08, wet) + 0.20 * (r() - 0.5)),
        v * hue[2] * (mix(0.56, 0.9, wet) + 0.18 * (r() - 0.5)),
      ];
      canopy.push({ x, z, y: y - s * 0.16, s, yaw: r() * 6.28, tint, shade, ao, moist: wet, variant: (r() * 3) | 0 });
    }
    // understory: small dark crowns filling the gaps between the big ones
    if (d > 0.3 && r() < 0.55) {
      const un = 1 + Math.floor(r() * 2);
      for (let k = 0; k < un; k++) {
        const ka = r() * 6.283, kr = spreadR * 1.3 * Math.sqrt(r());
        const x = cx + Math.cos(ka) * kr, z = cz + Math.sin(ka) * kr;
        const y = groundAt(field, x, z);
        if (y < 2.5) continue;
        scrub.push({ x, z, y, s: 3.5 + 6 * r(), yaw: r() * 6.28,
          tint: [0.5 + 0.2 * r(), 0.72 + 0.2 * r(), 0.42 + 0.2 * r()], shade: shade * 0.8, ao: ao * 0.75, moist });
      }
    }
    // the tall ones that break the canopy line
    if (r() < 0.095 * d && h > 30 && h < 640) {
      const s = 27 + 24 * r();
      const hue = species(r() * 0.9);
      emergent.push({ x: cx, z: cz, y: h - 1, s, yaw: r() * 6.28,
        tint: [hue[0] * (0.66 + 0.24 * r()), hue[1] * (0.84 + 0.16 * r()), hue[2] * (0.56 + 0.2 * r())],
        shade, ao, moist });
    }
  }

  // crowns clinging to the limestone towers
  for (const st of (stacks || [])) {
    const topY = st.sea ? -26 + st.h : st.h;
    const n = 14 + Math.floor(r() * 10);
    for (let k = 0; k < n; k++) {
      const a = r() * 6.283, rr = st.r * 0.8 * Math.sqrt(r());
      canopy.push({ x: st.x + Math.cos(a) * rr, z: st.z + Math.sin(a) * rr, y: topY + 2,
        s: 5 + 8 * r(), yaw: r() * 6.28, tint: [0.8 + 0.2 * r(), 1.0, 0.72 + 0.2 * r()], shade: 1, ao: 0.95, moist: 0.5 });
    }
    // growth clinging to the ledges, all the way down the flanks
    for (let k = 0; k < 20; k++) {
      const a = r() * 6.283, t = 0.12 + 0.78 * r();
      const rr = st.r * (0.84 - 0.12 * t) * (0.9 + 0.2 * r());
      canopy.push({ x: st.x + Math.cos(a) * rr, z: st.z + Math.sin(a) * rr, y: topY - st.h * (1 - t),
        s: 4 + 9 * r(), yaw: r() * 6.28,
        tint: [0.55 + 0.3 * r(), 0.8 + 0.25 * r(), 0.45 + 0.25 * r()], shade: 0.75 + 0.25 * r(), ao: 0.7, moist: 0.65 });
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
      const sq = 0.7 + 0.6 * ((i * 37) % 100) / 100;
      s.set(it.s * (0.86 + 0.28 * ((i * 53) % 100) / 100), it.s * flatten * sq, it.s * (0.86 + 0.28 * ((i * 71) % 100) / 100));
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

  // three crown shapes, each a different arrangement of lobes
  const crowns = [
    blobGeometry({ bands: 4, segs: 10, squash: 0.62, dent: 0.14, seed: 1.1, pinch: 0.3, lobes: 4 }),
    blobGeometry({ bands: 4, segs: 10, squash: 0.70, dent: 0.16, seed: 4.7, pinch: 0.26, lobes: 3 }),
    blobGeometry({ bands: 3, segs: 9, squash: 0.55, dent: 0.19, seed: 8.3, pinch: 0.34, lobes: 5 }),
  ];
  const scrubGeo = blobGeometry({ bands: 2, segs: 7, squash: 0.58, dent: 0.2, seed: 7.3, pinch: 0.55, lobes: 2 });
  crowns.forEach((geo, k) => add(`canopy-${k}`, geo, canopy.filter((c) => (c.variant ?? 0) === k), 7717 + k * 131, 1));
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
