/* The palace architecture, built from a layout (docs/palace/layout.js).
   Static geometry is merged per material so the whole building is a few
   dozen draw calls. A single clipping plane makes the section cut used by
   the map and hero views; back faces exposed by the cut render in coral
   ("poché"), so cut walls read as solid. */
import * as THREE from "three";
import { mergeGeometries } from "three/addons/utils/BufferGeometryUtils.js";
import { DIM, at, wallPoint } from "./layout.js";
import * as ART from "./art.js";

const UP = new THREE.Vector3(0, 1, 0);
const V = (a) => new THREE.Vector3(a[0], a[1], a[2]);

function basis(right, normal, origin) {
  const m = new THREE.Matrix4().makeBasis(V(right), UP, V(normal));
  m.setPosition(origin[0], origin[1], origin[2]);
  return m;
}

function archPts(cx, w, spring, rise, seg = 22) {
  const half = w / 2;
  const R = (half * half + rise * rise) / (2 * rise);
  const cy = spring + rise - R;
  const a0 = Math.atan2(spring - cy, -half), a1 = Math.atan2(spring - cy, half);
  const pts = [];
  for (let i = 0; i <= seg; i++) {
    const a = a0 + (a1 - a0) * (i / seg);
    pts.push([cx + Math.cos(a) * R, cy + Math.sin(a) * R]);
  }
  return pts;
}

/* A wall elevation W × H centred on x = 0. Openings that start at the floor
   are notched into the outline; raised ones (niches) become holes. */
function wallShape(W, H, openings) {
  const shape = new THREE.Shape();
  shape.moveTo(-W / 2, 0);
  for (const o of openings.filter((o) => o.y0 <= 1e-3).sort((a, b) => a.s - b.s)) {
    shape.lineTo(o.s - o.w / 2, 0);
    shape.lineTo(o.s - o.w / 2, o.spring);
    for (const [x, y] of archPts(o.s, o.w, o.spring, o.rise).slice(1)) shape.lineTo(x, y);
    shape.lineTo(o.s + o.w / 2, 0);
  }
  shape.lineTo(W / 2, 0);
  shape.lineTo(W / 2, H);
  shape.lineTo(-W / 2, H);
  shape.closePath();
  for (const o of openings.filter((o) => o.y0 > 1e-3)) {
    const hole = new THREE.Path();
    hole.moveTo(o.s - o.w / 2, o.y0);
    hole.lineTo(o.s - o.w / 2, o.spring);
    for (const [x, y] of archPts(o.s, o.w, o.spring, o.rise).slice(1)) hole.lineTo(x, y);
    hole.lineTo(o.s + o.w / 2, o.y0);
    hole.closePath();
    shape.holes.push(hole);
  }
  return shape;
}

function extrude(shape, depth) {
  return new THREE.ExtrudeGeometry(shape, { depth, bevelEnabled: false, curveSegments: 1, steps: 1 });
}

function prep(geo) {
  const g = geo.index ? geo.toNonIndexed() : geo;
  for (const name of Object.keys(g.attributes)) if (!["position", "normal", "uv"].includes(name)) g.deleteAttribute(name);
  if (!g.attributes.uv) g.setAttribute("uv", new THREE.Float32BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
  return g;
}

function merged(list) {
  const geos = list.map(prep);
  const out = mergeGeometries(geos, false);
  for (const g of geos) g.dispose();
  return out;
}

/* Fluted shaft with entasis: 20 concave flutes with sharp arrises. */
function flutedShaft(r, h) {
  const radial = 120, rows = 8, flutes = 20;
  const pos = [], uv = [], idx = [];
  for (let iy = 0; iy <= rows; iy++) {
    const v = iy / rows, y = v * h, taper = 1 - 0.11 * Math.pow(v, 1.4);
    for (let ix = 0; ix <= radial; ix++) {
      const u = ix / radial, th = u * Math.PI * 2;
      const f = Math.sin(Math.PI * ((u * flutes) % 1));
      const rr = r * taper * (1 - 0.055 * f);
      pos.push(Math.sin(th) * rr, y, Math.cos(th) * rr);
      uv.push(u * 2, v * 4);
    }
  }
  for (let iy = 0; iy < rows; iy++) for (let ix = 0; ix < radial; ix++) {
    const a = iy * (radial + 1) + ix, b = a + radial + 1;
    idx.push(a, a + 1, b, b, a + 1, b + 1);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  g.computeVertexNormals();
  return g;
}

function column(r, h) {
  const base = 0.55, cap = 0.95;
  const shaft = flutedShaft(r, h - base - cap);
  shaft.translate(0, base, 0);
  const plinth = new THREE.BoxGeometry(r * 2.8, 0.3, r * 2.8); plinth.translate(0, 0.15, 0);
  const torus = new THREE.TorusGeometry(r * 1.1, r * 0.2, 10, 44); torus.rotateX(Math.PI / 2); torus.translate(0, 0.42, 0);
  const astragal = new THREE.TorusGeometry(r * 0.93, r * 0.09, 8, 44); astragal.rotateX(Math.PI / 2); astragal.translate(0, h - cap + 0.05, 0);
  const echinus = new THREE.LatheGeometry([
    new THREE.Vector2(r * 0.9, 0), new THREE.Vector2(r * 1.02, 0.12), new THREE.Vector2(r * 1.22, 0.3), new THREE.Vector2(r * 1.42, 0.5), new THREE.Vector2(r * 1.46, 0.6),
  ], 44);
  echinus.translate(0, h - cap + 0.05, 0);
  const abacus = new THREE.BoxGeometry(r * 3.0, 0.32, r * 3.0); abacus.translate(0, h - 0.16, 0);
  return { shaft, trim: [plinth, torus, astragal, echinus, abacus] };
}

function ringGeo(rIn, rOut, y0, h, seg = 128) {
  const s = new THREE.Shape(); s.absarc(0, 0, rOut, 0, Math.PI * 2, false);
  const hole = new THREE.Path(); hole.absarc(0, 0, rIn, 0, Math.PI * 2, true);
  s.holes.push(hole);
  const g = new THREE.ExtrudeGeometry(s, { depth: h, bevelEnabled: false, curveSegments: seg });
  g.rotateX(-Math.PI / 2);
  g.translate(0, y0, 0);
  return g;
}

function polygonXZ(points) {
  const s = new THREE.Shape();
  points.forEach(([x, , z], i) => (i ? s.lineTo(x, -z) : s.moveTo(x, -z)));
  s.closePath();
  return s;
}

function texture(c, { repeat = 1, aniso = 8, wrap = true } = {}) {
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = aniso;
  if (wrap) { t.wrapS = t.wrapT = THREE.RepeatWrapping; t.repeat.set(repeat, repeat); }
  return t;
}

const SHAFT_VERT = /* glsl */`
  varying vec2 vUv; varying vec3 vN; varying vec3 vV;
  #include <common>
  #include <fog_pars_vertex>
  void main() {
    vUv = uv;
    vec4 mvPosition = modelViewMatrix * vec4(position, 1.0);
    vN = normalize(normalMatrix * normal);
    vV = normalize(-mvPosition.xyz);
    gl_Position = projectionMatrix * mvPosition;
    #include <fog_vertex>
  }`;
const SHAFT_FRAG = /* glsl */`
  uniform vec3 uColor; uniform float uIntensity; uniform float uTime;
  varying vec2 vUv; varying vec3 vN; varying vec3 vV;
  #include <common>
  #include <fog_pars_fragment>
  void main() {
    float edge = pow(abs(dot(normalize(vN), normalize(vV))), 2.2);
    float along = smoothstep(0.0, 0.45, vUv.y) * (0.45 + 0.55 * vUv.y);
    float a = vUv.x * 6.28318;
    float streak = 0.72 + 0.28 * sin(a * 9.0 + uTime * 0.21) * sin(a * 4.0 - uTime * 0.13 + vUv.y * 3.0);
    vec3 col = uColor * edge * along * streak * uIntensity;
    #ifdef USE_FOG
      #ifdef FOG_EXP2
        col *= exp(-fogDensity * fogDensity * vFogDepth * vFogDepth);
      #endif
    #endif
    gl_FragColor = vec4(col, 1.0);
  }`;
const DUST_VERT = /* glsl */`
  attribute vec4 aSeed;
  uniform float uTime; uniform float uScale; uniform vec3 uFrom; uniform vec3 uTo; uniform float uRadius;
  varying float vA;
  void main() {
    float k = fract(aSeed.x + uTime * (0.006 + aSeed.w * 0.01));
    vec3 axis = uTo - uFrom;
    vec3 side = normalize(cross(axis, vec3(1.0, 0.0, 0.0)));
    vec3 side2 = normalize(cross(axis, side));
    float ang = aSeed.y * 6.28318 + uTime * 0.05 * (aSeed.w - 0.5);
    float rad = sqrt(aSeed.z) * uRadius;
    vec3 p = uFrom + axis * k + (side * cos(ang) + side2 * sin(ang)) * rad;
    vec4 mv = modelViewMatrix * vec4(p, 1.0);
    gl_Position = projectionMatrix * mv;
    gl_PointSize = uScale * (0.6 + aSeed.w) / -mv.z;
    vA = smoothstep(0.0, 0.15, k) * smoothstep(1.0, 0.8, k) * (0.5 + 0.5 * sin(uTime * 1.3 + aSeed.y * 40.0));
  }`;
const DUST_FRAG = /* glsl */`
  uniform float uIntensity; varying float vA;
  void main() {
    vec2 c = gl_PointCoord - 0.5;
    float d = dot(c, c);
    if (d > 0.25) discard;
    gl_FragColor = vec4(vec3(1.0, 0.82, 0.6) * (1.0 - d * 4.0) * vA * uIntensity, 1.0);
  }`;

export function buildWorld(L, { tier, renderer }) {
  const { N, alpha, R1, A, T, cosH, tanH } = L;
  const half = alpha / 2;
  const root = new THREE.Group();
  const mirror = new THREE.Group();
  mirror.scale.y = -1;
  root.add(mirror);
  const disposables = [];
  const keep = (x) => { disposables.push(x); return x; };
  const aniso = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  const cut = new THREE.Plane(new THREE.Vector3(0, -1, 0), 1000);
  const clip = { clippingPlanes: [cut], clipShadows: true };

  /* ── Materials ── */
  const stoneTex = keep(texture(ART.stoneTexture(), { repeat: 0.25, aniso }));
  const floorTex = keep(texture(ART.floorTexture(), { repeat: 1 / 6.4, aniso }));
  const rotTex = keep(texture(ART.rotundaFloorTexture(N, L.total), { wrap: false, aniso }));
  rotTex.center.set(0.5, 0.5);
  rotTex.rotation = Math.PI - L.rooms[N - 1].phi;
  const colTex = keep(texture(ART.columnTexture(), { repeat: 1, aniso }));
  const cofTex = keep(texture(ART.cofferTexture(), { aniso, wrap: true }));
  const ceilTex = keep(texture(ART.ceilingTexture(), { repeat: 1 / 6.4, aniso }));
  const nicheTex = keep(texture(ART.nicheTexture(), { wrap: false }));

  const mats = {
    stone: new THREE.MeshStandardMaterial({ map: stoneTex, color: 0xE2D7C8, roughness: 0.88, ...clip }),
    trim: new THREE.MeshStandardMaterial({ color: 0xE2D6C5, roughness: 0.62, ...clip }),
    column: new THREE.MeshStandardMaterial({ map: colTex, roughness: 0.3, metalness: 0.02, ...clip }),
    floor: new THREE.MeshStandardMaterial({ map: floorTex, roughness: 0.22, transparent: true, opacity: 0.86, ...clip }),
    rotunda: new THREE.MeshStandardMaterial({ map: rotTex, roughness: 0.2, transparent: true, opacity: 0.86, ...clip }),
    ceiling: new THREE.MeshStandardMaterial({ map: ceilTex, roughness: 0.9, ...clip }),
    domeIn: new THREE.MeshStandardMaterial({ map: cofTex, roughness: 0.85, side: THREE.BackSide, ...clip }),
    domeOut: new THREE.MeshStandardMaterial({ color: 0x8F7B67, roughness: 0.7, ...clip }),
    dark: new THREE.MeshStandardMaterial({ color: 0x2A1F19, roughness: 0.5, metalness: 0.3, ...clip }),
    ground: new THREE.MeshStandardMaterial({ color: 0x1F1713, roughness: 0.95 }),
    poche: new THREE.MeshBasicMaterial({ color: new THREE.Color(0xFF5A2D).multiplyScalar(0.78), side: THREE.BackSide, ...clip }),
    glow: new THREE.MeshBasicMaterial({ color: new THREE.Color(1.0, 0.8, 0.58).multiplyScalar(2.6), ...clip }),
    coral: new THREE.MeshBasicMaterial({ color: new THREE.Color(0xFF5A2D).multiplyScalar(1.55), ...clip }),
    sky: new THREE.MeshBasicMaterial({ color: new THREE.Color(1.0, 0.9, 0.75).multiplyScalar(5), fog: false, ...clip }),
  };
  mats.glowMirror = new THREE.MeshBasicMaterial({ color: mats.glow.color.clone().multiplyScalar(0.16) });
  mats.coralMirror = new THREE.MeshBasicMaterial({ color: mats.coral.color.clone().multiplyScalar(0.35) });
  /* Unlit stand-ins for reflected walls: barely visible through the floor,
     but they hide reflections of things the camera can't actually see. */
  mats.stoneMirror = new THREE.MeshBasicMaterial({ map: stoneTex, color: new THREE.Color(0xE2D7C8).multiplyScalar(0.34) });
  mats.ceilingMirror = new THREE.MeshBasicMaterial({ color: new THREE.Color(0x6B5A4A).multiplyScalar(0.3) });
  mats.floor.polygonOffset = true; mats.floor.polygonOffsetFactor = 1; mats.floor.polygonOffsetUnits = 1;
  for (const m of Object.values(mats)) keep(m);

  const lists = { stone: [], trim: [], column: [], ceiling: [], dark: [], glow: [], coral: [], lamp: [], base: [] };
  const occluders = [];
  const wall = (geo, mat = "stone") => {
    lists[mat].push(geo);
    occluders.push(geo);
  };

  /* ── Rotunda ── */
  const Wr = 2 * (R1 + T) * tanH;
  const doorSpring = DIM.doorH - DIM.doorW / 2;
  for (const room of L.rooms) {
    const g = extrude(wallShape(Wr, DIM.drumH, [{ s: 0, w: DIM.doorW, y0: 0, spring: doorSpring, rise: DIM.doorW / 2 }]), T);
    g.applyMatrix4(basis(room.right, room.normal, at(R1 + T, room.phi)));
    wall(g);
    const local = basis(room.right, room.normal, at(R1, room.phi));
    const add = (geo, mat) => { geo.applyMatrix4(local); lists[mat].push(geo); };
    const arch = new THREE.TorusGeometry(DIM.doorW / 2 + 0.22, 0.17, 10, 40, Math.PI); arch.translate(0, doorSpring, 0.06); add(arch, "trim");
    for (const sx of [-1, 1]) {
      const jamb = new THREE.BoxGeometry(0.4, doorSpring, 0.26); jamb.translate(sx * (DIM.doorW / 2 + 0.22), doorSpring / 2, 0.05); add(jamb, "trim");
      const line = new THREE.BoxGeometry(0.05, doorSpring, 0.05); line.translate(sx * (DIM.doorW / 2 + 0.5), doorSpring / 2, 0.03); add(line, "coral");
    }
    const key = new THREE.BoxGeometry(0.5, 0.62, 0.3); key.translate(0, doorSpring + DIM.doorW / 2 + 0.04, 0.08); add(key, "trim");
    const glowArc = new THREE.TorusGeometry(DIM.doorW / 2 + 0.5, 0.028, 6, 56, Math.PI); glowArc.translate(0, doorSpring, 0.03); add(glowArc, "coral");
    const skirt = new THREE.BoxGeometry(Wr, 0.3, 0.1); skirt.translate(0, 0.15, 0.05); add(skirt, "trim");
    const frame = new THREE.BoxGeometry(room.inscription.w + 0.2, room.inscription.h + 0.16, 0.1);
    frame.translate(0, room.inscription.y, 0.03); add(frame, "trim");
  }
  const colR = L.colR, eps = 0.78 / colR;
  const colParts = column(DIM.colR, DIM.colH);
  for (const room of L.rooms) {
    for (const d of [-eps, eps]) {
      const th = room.phi + half + d;
      const [x, , z] = at(colR, th);
      const sh = colParts.shaft.clone(); sh.translate(x, 0, z); lists.column.push(sh);
      for (const t of colParts.trim) { const c = t.clone(); c.translate(x, 0, z); lists.trim.push(c); }
    }
  }
  lists.trim.push(ringGeo(colR - 0.85, R1 + 0.1, DIM.colH, DIM.entH * 0.62));
  lists.trim.push(ringGeo(colR - 1.0, R1 + 0.1, DIM.colH + DIM.entH * 0.62, DIM.entH * 0.38));
  lists.trim.push(ringGeo(R1 - 0.55, R1 / cosH + 0.8, DIM.drumH - 0.5, 0.75));
  const cove = new THREE.TorusGeometry(colR - 0.92, 0.05, 6, 160); cove.rotateX(Math.PI / 2); cove.translate(0, DIM.colH + DIM.entH + 0.06, 0);
  lists.glow.push(cove);

  const Rd = R1 / cosH + 0.25, oc = 0.17;
  const domeIn = new THREE.SphereGeometry(Rd, 72, 28, 0, Math.PI * 2, oc, Math.PI / 2 - oc);
  {
    const uv = domeIn.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setY(i, (uv.getY(i) - 0.5) / (1 - oc / Math.PI - 0.5));
  }
  domeIn.translate(0, DIM.drumH, 0);
  const domeOut = new THREE.SphereGeometry(Rd + 0.6, 56, 18, 0, Math.PI * 2, oc + 0.02, Math.PI / 2 - oc - 0.02);
  domeOut.translate(0, DIM.drumH, 0);
  const ocR = Rd * Math.sin(oc), ocY = DIM.drumH + Rd * Math.cos(oc);
  const ocRing = new THREE.TorusGeometry(ocR + 0.05, 0.3, 10, 48); ocRing.rotateX(Math.PI / 2); ocRing.translate(0, ocY + 0.1, 0);
  lists.trim.push(ocRing);
  const sky = new THREE.CircleGeometry(ocR + 0.6, 48); sky.rotateX(Math.PI / 2); sky.translate(0, ocY + 0.9, 0);

  /* ── Rooms ── */
  const Wo = 2 * (A + T) * tanH, Wb = 2 * (A + T + DIM.backSlab) * tanH;
  const nicheMats = [];
  const signs = [];
  const nicheList = [];
  const r0 = R1 / cosH + 0.45, r1 = (A + T) / cosH;
  const pathR = L.pathR;
  for (const room of L.rooms) {
    const shelves = room.shelves.length ? room.shelves : [-1, 0, 1].map((k) => ({ s: k * room.usable / 3, nicheW: room.usable / 3 - 1, empty: true }));
    const openings = shelves.map((sh) => {
      const rise = Math.min(sh.nicheW / 2, DIM.nicheRise);
      return { s: sh.s, w: sh.nicheW, y0: DIM.sill, spring: DIM.nicheTop - rise, rise };
    });
    const front = extrude(wallShape(Wo, DIM.roomH, openings), T);
    front.applyMatrix4(basis(room.right, room.normal, at(A + T, room.phi)));
    wall(front);
    const back = extrude(wallShape(Wb, DIM.roomH, []), DIM.backSlab);
    back.applyMatrix4(basis(room.right, room.normal, at(A + T + DIM.backSlab, room.phi)));
    wall(back);

    const local = basis(room.right, room.normal, room.center);
    const add = (geo, mat) => { geo.applyMatrix4(local); lists[mat].push(geo); };
    const cornice = new THREE.BoxGeometry(Wo, 0.42, 0.32); cornice.translate(0, DIM.roomH - 0.55, 0.16); add(cornice, "trim");
    const skirt = new THREE.BoxGeometry(Wo, 0.32, 0.07); skirt.translate(0, 0.16, 0.035); add(skirt, "trim");
    const hue = room.data ? room.data.hue : 30;
    const deep = new THREE.Color().setHSL(hue / 360, 0.42, 0.13, THREE.SRGBColorSpace);
    const lit = new THREE.Color().setHSL(hue / 360, 0.6, 0.5, THREE.SRGBColorSpace).lerp(new THREE.Color(1, 0.8, 0.62), 0.45);
    const nm = keep(new THREE.MeshStandardMaterial({ color: deep, emissive: lit, emissiveMap: nicheTex, emissiveIntensity: 0.3, roughness: 0.92, ...clip }));
    nicheMats.push(nm);
    const panels = [];
    openings.forEach((o) => {
      const p = new THREE.PlaneGeometry(o.w + 0.02, DIM.nicheTop - DIM.sill + 0.02);
      p.translate(o.s, (DIM.nicheTop + DIM.sill) / 2, -T + 0.02);
      p.applyMatrix4(local);
      panels.push(p);
      const half = o.w / 2, Ra = (half * half + o.rise * o.rise) / (2 * o.rise), cy = o.spring + o.rise - Ra;
      const a0 = Math.atan2(o.spring - cy, -half), a1 = Math.atan2(o.spring - cy, half);
      const strip = new THREE.TorusGeometry(Ra - 0.07, 0.026, 6, 56, a0 - a1);
      strip.rotateZ(a1);
      strip.translate(o.s, cy, -0.09);
      add(strip, "glow");
      const shelfBoard = new THREE.BoxGeometry(o.w, 0.08, T - 0.04); shelfBoard.translate(o.s, DIM.sill + 0.04, -T / 2); add(shelfBoard, "dark");
    });
    const nicheGeo = merged(panels);
    const nicheMesh = new THREE.Mesh(nicheGeo, nm);
    nicheMesh.receiveShadow = true;
    root.add(nicheMesh);
    mirror.add(new THREE.Mesh(nicheGeo, nm));
    nicheList.push(nicheGeo);

    const psi = room.phi - half;
    const W = r1 - r0, c = (r0 + r1) / 2;
    const radial = extrude(wallShape(W, DIM.roomH, [{ s: pathR - c, w: DIM.enfW, y0: 0, spring: DIM.enfH - DIM.enfW / 2, rise: DIM.enfW / 2 }]), T);
    const rr = [-Math.cos(psi), 0, Math.sin(psi)];
    const o = at(c, psi);
    radial.applyMatrix4(new THREE.Matrix4().makeBasis(V(at(1, psi)), UP, V(rr)).setPosition(o[0] - rr[0] * T / 2, 0, o[2] - rr[2] * T / 2));
    wall(radial);

    const rIn = (R1 + T) / cosH, rOut = (A + T + DIM.backSlab) / cosH;
    const ceil = extrude(polygonXZ([at(rIn, room.phi - half), at(rOut, room.phi - half), at(rOut, room.phi + half), at(rIn, room.phi + half)]), DIM.roofT);
    ceil.rotateX(-Math.PI / 2);
    ceil.translate(0, DIM.roomH, 0);
    lists.ceiling.push(ceil);
    occluders.push(ceil);

    const lightAt = room.light;
    const ring = new THREE.TorusGeometry(1.35, 0.05, 8, 72); ring.rotateX(Math.PI / 2); ring.translate(lightAt[0], DIM.cutHero + 0.2, lightAt[2]); lists.lamp.push(ring);
    const ring2 = new THREE.TorusGeometry(0.7, 0.04, 8, 48); ring2.rotateX(Math.PI / 2); ring2.translate(lightAt[0], DIM.cutHero + 0.22, lightAt[2]); lists.lamp.push(ring2);
    for (let k = 0; k < 3; k++) {
      const a = (k / 3) * Math.PI * 2;
      const rod = new THREE.CylinderGeometry(0.012, 0.012, DIM.roomH - DIM.cutHero - 0.2, 4);
      rod.translate(lightAt[0] + Math.cos(a) * 1.35, (DIM.roomH + DIM.cutHero + 0.2) / 2, lightAt[2] + Math.sin(a) * 1.35);
      lists.dark.push(rod);
    }

    if (room.data) {
      const sub = `${room.data.total} bookmark${room.data.total === 1 ? "" : "s"} · ${room.shelves.length} shel${room.shelves.length === 1 ? "f" : "ves"}`;
      signs.push({ kind: "title", room, canvas: ART.titleCanvas(room.data.name, sub, room.title.w, room.title.h, hue), w: room.title.w, h: room.title.h, at: wallPoint(room, 0, room.title.y, 0.025), right: room.right, normal: room.normal });
      signs.push({ kind: "inscription", room, canvas: ART.inscriptionCanvas(room.data.name, room.inscription.w, room.inscription.h), w: room.inscription.w, h: room.inscription.h, at: [...at(R1 + 0.0, room.phi, room.inscription.y)].map((v, i) => v + room.normal[i] * 0.09), right: room.right, normal: room.normal });
      for (const sh of room.shelves) {
        const p = sh.plaque;
        signs.push({ kind: "plaque", room, shelf: sh, canvas: ART.plaqueCanvas(sh.shelf.name, sh.shelf.total, p.w, p.h, hue), w: p.w, h: p.h, at: wallPoint(room, p.s, p.y, 0.05), right: room.right, normal: room.normal });
      }
    } else {
      signs.push({ kind: "title", room, canvas: ART.titleCanvas("Room to grow", "Save a new topic to fill it", room.title.w, room.title.h, 30), w: room.title.w, h: room.title.h, at: wallPoint(room, 0, room.title.y, 0.025), right: room.right, normal: room.normal });
    }
  }

  /* ── Floors, plinth, ground ── */
  const roomFloors = [];
  for (const room of L.rooms) {
    const rIn = (R1 + T) / cosH - 0.02, rOut = A / cosH + 0.3;
    const g = new THREE.ShapeGeometry(polygonXZ([at(rIn, room.phi - half), at(rOut, room.phi - half), at(rOut, room.phi + half), at(rIn, room.phi + half)]));
    g.rotateX(-Math.PI / 2);
    roomFloors.push(g);
  }
  const floorGeo = merged(roomFloors);
  const floor = new THREE.Mesh(floorGeo, mats.floor);
  floor.receiveShadow = true; floor.renderOrder = -1;
  const rotGeo = new THREE.CircleGeometry(R1 / cosH + 0.3, 128); rotGeo.rotateX(-Math.PI / 2); rotGeo.translate(0, 0.004, 0);
  const rotFloor = new THREE.Mesh(rotGeo, mats.rotunda);
  rotFloor.receiveShadow = true; rotFloor.renderOrder = -1;
  root.add(floor, rotFloor);
  keep(floorGeo); keep(rotGeo);

  const outerR = L.radius + 2.4, innerR = L.radius - 0.4, plinthH = 0.9;
  const ringShape = new THREE.Shape();
  for (let i = 0; i <= N; i++) { const p = at(outerR / 1, -i * alpha - half); i ? ringShape.lineTo(p[0], -p[2]) : ringShape.moveTo(p[0], -p[2]); }
  const hole = new THREE.Path();
  for (let i = 0; i <= N; i++) { const p = at(innerR, -i * alpha - half); i ? hole.lineTo(p[0], -p[2]) : hole.moveTo(p[0], -p[2]); }
  ringShape.holes.push(hole);
  const plinth = extrude(ringShape, plinthH); plinth.rotateX(-Math.PI / 2); plinth.translate(0, -plinthH, 0);
  lists.base.push(plinth);
  const groundShape = new THREE.Shape();
  groundShape.moveTo(-500, -500); groundShape.lineTo(500, -500); groundShape.lineTo(500, 500); groundShape.lineTo(-500, 500); groundShape.closePath();
  const gHole = new THREE.Path();
  for (let i = 0; i <= N; i++) { const p = at(outerR - 0.2, -i * alpha - half); i ? gHole.lineTo(p[0], -p[2]) : gHole.moveTo(p[0], -p[2]); }
  groundShape.holes.push(gHole);
  const groundGeo = keep(new THREE.ShapeGeometry(groundShape)); groundGeo.rotateX(-Math.PI / 2); groundGeo.translate(0, -plinthH, 0);
  const ground = new THREE.Mesh(groundGeo, mats.ground);
  ground.receiveShadow = true;
  root.add(ground);

  /* ── Merge static geometry ── */
  /* Chandeliers ("lamp") hang above the section cut, so they are never
     mirrored: their reflections would show up with nothing above them. The
     plinth ("base") sits below the floor, so its mirror image would poke
     up through it. */
  const meshes = {};
  const drawn = { lamp: mats.glow, base: mats.trim };
  for (const [name, list] of Object.entries(lists)) {
    if (!list.length) continue;
    const geo = keep(merged(list));
    const emissive = ["glow", "coral", "lamp"].includes(name);
    const mesh = new THREE.Mesh(geo, drawn[name] || mats[name]);
    mesh.castShadow = !emissive;
    mesh.receiveShadow = !emissive;
    root.add(mesh);
    meshes[name] = mesh;
    if (["glow", "coral"].includes(name)) mirror.add(new THREE.Mesh(geo, mats[`${name}Mirror`]));
    if (["stone", "trim", "column"].includes(name)) mirror.add(new THREE.Mesh(geo, mats.stoneMirror));
    if (name === "ceiling") mirror.add(new THREE.Mesh(geo, mats.ceilingMirror));
    if (["stone", "trim", "column"].includes(name)) {
      const poche = new THREE.Mesh(geo, mats.poche);
      poche.visible = false;
      root.add(poche);
      meshes[`${name}Poche`] = poche;
    }
  }
  const domeInGeo = keep(domeIn), domeOutGeo = keep(domeOut), skyGeo = keep(sky);
  const domeInMesh = new THREE.Mesh(domeInGeo, mats.domeIn); domeInMesh.receiveShadow = true;
  const domeOutMesh = new THREE.Mesh(domeOutGeo, mats.domeOut); domeOutMesh.castShadow = true;
  const skyMesh = new THREE.Mesh(skyGeo, mats.sky);
  root.add(domeInMesh, domeOutMesh, skyMesh);
  mirror.add(new THREE.Mesh(skyGeo, mats.sky));

  /* ── Signage ── */
  const signMeshes = [];
  for (const s of signs) {
    const tex = keep(texture(s.canvas, { wrap: false, aniso }));
    const transparent = s.kind === "title";
    const mat = keep(new THREE.MeshStandardMaterial({
      map: tex, emissiveMap: tex, emissive: 0xffffff,
      emissiveIntensity: s.kind === "inscription" ? 0.42 : s.kind === "plaque" ? 0.36 : 0.08,
      roughness: 0.55, transparent, alphaTest: transparent ? 0.02 : 0, depthWrite: !transparent, ...clip,
    }));
    const geo = keep(new THREE.PlaneGeometry(s.w, s.h));
    const mesh = new THREE.Mesh(geo, mat);
    mesh.matrixAutoUpdate = false;
    mesh.matrix.copy(basis(s.right, s.normal, s.at));
    mesh.receiveShadow = s.kind !== "title";
    root.add(mesh);
    signMeshes.push({ mesh, sign: s });
  }

  /* ── Lights ── */
  const lights = [];
  const hemi = new THREE.HemisphereLight(0xFFE7CF, 0x2B1C14, 0.5);
  root.add(hemi);
  const sun = new THREE.DirectionalLight(0xFFDDB5, 9);
  sun.castShadow = tier !== "low";
  const reach = L.radius + 4;
  Object.assign(sun.shadow.camera, { left: -reach, right: reach, top: reach, bottom: -reach, near: 1, far: 220 });
  sun.shadow.mapSize.set(tier === "high" ? 4096 : 2048, tier === "high" ? 4096 : 2048);
  sun.shadow.bias = -0.0005;
  sun.shadow.normalBias = 0.04;
  root.add(sun, sun.target);
  const rotLight = new THREE.PointLight(0xFFC796, tier === "low" ? 240 : 150, 40, 2);
  rotLight.position.set(0, 9.5, 0);
  root.add(rotLight);
  lights.push(rotLight);
  if (tier !== "low") {
    for (const room of L.rooms) {
      const hue = room.data ? room.data.hue : 30;
      const col = new THREE.Color().setHSL(hue / 360, 0.5, 0.6, THREE.SRGBColorSpace).lerp(new THREE.Color(1, 0.76, 0.54), 0.78);
      const pl = new THREE.PointLight(col, room.data ? 125 : 60, 30, 2);
      pl.position.set(room.light[0], room.light[1], room.light[2]);
      root.add(pl);
      lights.push(pl);
    }
  }

  /* ── Oculus sun shaft and dust ── */
  const sunDirInterior = new THREE.Vector3(0, ocY, 0).sub(new THREE.Vector3(...at(4.6, 0, 0))).normalize();
  const shaftFrom = new THREE.Vector3(...at(4.6, 0, 0)), shaftTo = new THREE.Vector3(0, ocY, 0);
  const shaftLen = shaftFrom.distanceTo(shaftTo);
  const shaftGeo = keep(new THREE.CylinderGeometry(ocR * 1.0, ocR * 1.3, shaftLen, 64, 1, true));
  const shaftMat = keep(new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, { uColor: { value: new THREE.Color(1.0, 0.8, 0.58) }, uIntensity: { value: 0.6 }, uTime: { value: 0 } }]),
    vertexShader: SHAFT_VERT, fragmentShader: SHAFT_FRAG, fog: true,
    transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
  }));
  const shaft = new THREE.Mesh(shaftGeo, shaftMat);
  shaft.position.copy(shaftFrom).add(shaftTo).multiplyScalar(0.5);
  shaft.quaternion.setFromUnitVectors(UP, sunDirInterior);
  shaft.renderOrder = 3;
  root.add(shaft);

  const dustN = tier === "low" ? 120 : 340;
  const dustGeo = keep(new THREE.BufferGeometry());
  const seeds = new Float32Array(dustN * 4);
  const dr = ART.rng(99);
  for (let i = 0; i < dustN * 4; i++) seeds[i] = dr();
  dustGeo.setAttribute("aSeed", new THREE.BufferAttribute(seeds, 4));
  dustGeo.setAttribute("position", new THREE.BufferAttribute(new Float32Array(dustN * 3), 3));
  const dustMat = keep(new THREE.ShaderMaterial({
    uniforms: { uTime: { value: 0 }, uScale: { value: 60 }, uFrom: { value: shaftFrom.clone() }, uTo: { value: shaftTo.clone() }, uRadius: { value: ocR * 1.05 }, uIntensity: { value: 1.6 } },
    vertexShader: DUST_VERT, fragmentShader: DUST_FRAG, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending,
  }));
  const dust = new THREE.Points(dustGeo, dustMat);
  dust.frustumCulled = false;
  dust.renderOrder = 4;
  root.add(dust);

  const occluderMeshes = occluders.map((g) => new THREE.Mesh(g, mats.stone));
  for (const m of occluderMeshes) m.updateMatrixWorld(true);
  for (const g of occluders) keep(g);

  return {
    root, mats, cut, sun, hemi, lights, shaft, dust, signs: signMeshes, occluders: occluderMeshes,
    sunInterior: sunDirInterior, oculusY: ocY,
    setCut(y) {
      cut.constant = y;
      const open = y < 60;
      for (const k of ["stonePoche", "trimPoche", "columnPoche"]) if (meshes[k]) meshes[k].visible = open;
      mirror.visible = !open;
    },
    setPixelRatio(pr) { dustMat.uniforms.uScale.value = 60 * pr; },
    update(t) {
      shaftMat.uniforms.uTime.value = t;
      dustMat.uniforms.uTime.value = t;
    },
    setShaft(k) {
      shaftMat.uniforms.uIntensity.value = 0.6 * k;
      dustMat.uniforms.uIntensity.value = 1.6 * k;
      shaft.visible = dust.visible = k > 0.01;
    },
    dispose() {
      root.traverse((o) => { if (o.isMesh && o.geometry && !disposables.includes(o.geometry)) o.geometry.dispose(); });
      for (const d of disposables) d.dispose?.();
      for (const g of nicheList) g.dispose();
      for (const m of nicheMats) m.dispose();
    },
  };
}
