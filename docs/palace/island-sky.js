/* island-sky.js — sky, sun, and everything made of soft particles: the mist
   banks that stack the island into layers, the smoke leaving the caldera and
   the spray at the foot of the falls. All motion is a function of uTime. */
import * as THREE from "three";
import { ATMOS_PARS, sampleGrid } from "./island-terrain.js";
import { clamp, mix, noise2, FALLS, heightAt } from "./island-layout.js";

/* ── sky dome ───────────────────────────────────────────────────────────── */
export function buildSky(uniforms) {
  const geo = new THREE.SphereGeometry(52000, 48, 24);
  const mat = new THREE.ShaderMaterial({
    uniforms,
    side: THREE.BackSide,
    depthWrite: false,
    vertexShader: `varying vec3 vDir; varying vec3 vWorld;
      void main(){ vDir = normalize(position); vWorld = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      uniform sampler2D uDetail;
      varying vec3 vDir;
      void main() {
        vec3 d = normalize(vDir);
        float h = d.y;
        vec3 color = skyAt(d);
        float toSun = max(0.0, dot(d, uSunDir));
        // the disc itself, flattened and reddened by the haze it sits in
        float disc = smoothstep(0.99930, 0.99972, toSun);
        color = mix(color, uSunColor * 3.4, disc * clamp(h * 10.0, 0.0, 1.0));

        /* Three cloud layers, not one band. A high sheet catching the sun
           from underneath, a mid deck drifting the other way, and the long
           low bank sitting on the horizon that gives the sea somewhere to
           end. Each is the same noise read at a different scale and speed,
           which is cheap and reads as weather. */
        vec2 p = vec2(atan(d.z, d.x) * 0.42, d.y * 2.6);
        float lo = texture2D(uDetail, p * vec2(0.5, 1.2) + vec2(uTime * 0.0012, 0.0)).r
                 + texture2D(uDetail, p * vec2(1.6, 2.4) - vec2(uTime * 0.0021, 0.0)).g * 0.6;
        float band = smoothstep(0.78, 1.26, lo) * smoothstep(0.34, 0.02, abs(h - 0.055));
        vec3 lowCloud = mix(uHazeColor * 0.62, uSunHaze * 1.45, pow(toSun, 1.6) * 0.85 + 0.15);
        color = mix(color, lowCloud, band * 0.78);

        float md = texture2D(uDetail, p * vec2(0.26, 0.55) + vec2(uTime * 0.0007, 0.02)).b
                 + texture2D(uDetail, p * vec2(0.9, 1.5) - vec2(uTime * 0.0013, 0.0)).r * 0.5;
        float deck = smoothstep(0.86, 1.34, md) * smoothstep(0.02, 0.22, h) * smoothstep(0.62, 0.18, h);
        // lit from below by a sun that is nearly on the horizon
        vec3 midCloud = mix(uFogColor * 0.72, uSunHaze * 1.25, pow(toSun, 1.2) * 0.7 + 0.12);
        color = mix(color, midCloud, deck * 0.52);

        float hi = texture2D(uDetail, p * vec2(0.14, 0.3) + vec2(uTime * 0.00035, 0.0)).g;
        float veil = smoothstep(0.58, 0.9, hi) * smoothstep(0.16, 0.7, h);
        color = mix(color, mix(uHazeColor, uSunHaze, pow(toSun, 2.0)) * 0.9, veil * 0.22);

        gl_FragColor = vec4(color * uExposure, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = "sky";
  mesh.frustumCulled = false;
  mesh.renderOrder = -1;
  return mesh;
}

/* ── soft particles ─────────────────────────────────────────────────────── */
/* One draw call per system. Each puff is a quad billboarded in the vertex
   shader; kind 0 drifts (mist), 1 rises and recycles (smoke), 2 bursts
   upward and fades fast (spray). */
function puffSystem(uniforms, list, { kind = 0, color = [1, 1, 1], opacity = 0.5, flat = 2.1, name = "puffs", order = 6 }) {
  const n = list.length;
  const pos = new Float32Array(n * 4 * 3);
  const corner = new Float32Array(n * 4 * 2);
  const params = new Float32Array(n * 4 * 4);
  const floor = new Float32Array(n * 4);
  const idx = [];
  const corners = [[-1, -1], [1, -1], [1, 1], [-1, 1]];
  list.forEach((p, i) => {
    for (let c = 0; c < 4; c++) {
      const v = i * 4 + c;
      pos[v * 3] = p.x; pos[v * 3 + 1] = p.y; pos[v * 3 + 2] = p.z;
      corner[v * 2] = corners[c][0]; corner[v * 2 + 1] = corners[c][1];
      params[v * 4] = p.s; params[v * 4 + 1] = p.seed; params[v * 4 + 2] = p.speed ?? 1; params[v * 4 + 3] = p.rise ?? 1;
      floor[v] = p.floor ?? -1e4;
    }
    const b = i * 4;
    idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
  });
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  g.setAttribute("corner", new THREE.BufferAttribute(corner, 2));
  g.setAttribute("params", new THREE.BufferAttribute(params, 4));
  g.setAttribute("floorY", new THREE.BufferAttribute(floor, 1));
  g.setIndex(idx);
  g.computeBoundingSphere();
  if (g.boundingSphere) g.boundingSphere.radius += 400;

  const mat = new THREE.ShaderMaterial({
    uniforms: { ...uniforms, uKind: { value: kind }, uTint: { value: new THREE.Color(...color) }, uOpacity: { value: opacity }, uFlat: { value: flat } },
    transparent: true,
    depthWrite: false,
    vertexShader: /* glsl */`
      attribute vec2 corner; attribute vec4 params; attribute float floorY;
      uniform float uTime, uKind, uFlat;
      varying vec3 vWorld; varying vec2 vUv; varying float vSeed; varying float vFade; varying float vFloor;
      void main() {
        vec3 c = position;
        float size = params.x, seed = params.y, speed = params.z, rise = params.w;
        float fade = 1.0;
        if (uKind < 0.5) {
          // mist: slow horizontal drift, wrapped so it never runs out
          float span = 2600.0;
          c.x = mod(c.x + uTime * speed * 7.0 + 4000.0, span) - span * 0.5 + sin(seed * 3.1) * 40.0;
          c.z += sin(uTime * 0.07 * speed + seed * 6.3) * 55.0;
          c.y += sin(uTime * 0.11 + seed * 2.7) * 9.0;
          size *= 1.0 + 0.09 * sin(uTime * 0.19 + seed);
        } else if (uKind < 1.5) {
          // smoke: a column that recycles, growing and thinning as it climbs
          float age = fract(uTime * 0.035 * speed + seed);
          c.y += age * rise;
          // the plume lies over, hard, the way a plume in a sea breeze does
          c.x += age * age * 430.0 + sin(seed * 9.1 + age * 3.0) * 70.0 * age;
          c.z += age * age * 190.0 + cos(seed * 5.5 + age * 2.4) * 64.0 * age;
          size *= 0.35 + age * 3.4;
          fade = smoothstep(0.0, 0.10, age) * (1.0 - smoothstep(0.30, 0.95, age));
        } else {
          // spray: short-lived, tight to the source
          float age = fract(uTime * 0.33 * speed + seed);
          c.y += age * rise;
          c.x += sin(seed * 12.0) * age * 18.0;
          c.z += cos(seed * 8.0) * age * 18.0;
          size *= 0.5 + age * 1.5;
          fade = (1.0 - age) * smoothstep(0.0, 0.1, age);
        }
        vec3 right = vec3(viewMatrix[0][0], viewMatrix[1][0], viewMatrix[2][0]);
        vec3 up = vec3(viewMatrix[0][1], viewMatrix[1][1], viewMatrix[2][1]);
        up = normalize(mix(up, vec3(0.0, 1.0, 0.0), 0.25));
        vec3 world = c + right * corner.x * size * uFlat + up * corner.y * size;
        vWorld = world; vUv = corner; vSeed = seed; vFade = fade; vFloor = floorY;
        gl_Position = projectionMatrix * viewMatrix * vec4(world, 1.0);
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      uniform sampler2D uDetail;
      uniform vec3 uTint; uniform float uOpacity, uKind;
      varying vec2 vUv; varying float vSeed; varying float vFade; varying float vFloor;
      void main() {
        float r = length(vUv);
        float soft = smoothstep(1.0, 0.1, r);
        vec2 q = vUv * 0.33 + vec2(vSeed * 3.7, vSeed * 1.9) + vec2(uTime * 0.0015, 0.0);
        float n = texture2D(uDetail, q).r * 0.7 + texture2D(uDetail, q * 2.7 + 0.21).b * 0.5;
        float alpha = soft * smoothstep(0.22, 0.95, n + soft * 0.55) * uOpacity * vFade;
        if (alpha < 0.004) discard;
        vec3 viewDir = normalize(cameraPosition - vWorld);
        float toSun = max(0.0, dot(normalize(-viewDir), uSunDir));
        /* Mist is lit from behind by a low sun: that is the whole effect.
           The warm term is strongly directional, so a bank between the
           camera and the sun goes almost white and one behind the camera
           stays a cold blue — which is what layers the valleys. */
        vec3 color = uTint * (uSkyColor * 0.72 + uSunHaze * (0.07 + pow(toSun, 2.6) * 0.72)
                              + uSunColor * pow(toSun, 10.0) * 0.45);
        float dist = length(vWorld - cameraPosition);
        // a bank only reads as a bank from outside it
        alpha *= smoothstep(90.0, 820.0, dist);
        /* The quad is flat and the hillside is not, so where they cross the
           intersection draws a hard line. Fading the bottom of a bank out
           as it approaches the ground beneath it hides the seam and, as a
           bonus, is exactly how mist behaves: it thins where it touches. */
        alpha *= smoothstep(0.0, 26.0, vWorld.y - vFloor);
        color = applyAtmos(color, vWorld, -viewDir);
        gl_FragColor = vec4(color * uExposure, alpha);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
  });
  const mesh = new THREE.Mesh(g, mat);
  mesh.name = name;
  mesh.renderOrder = order;
  mesh.frustumCulled = false;
  return mesh;
}

const rnd = (seed) => {
  let s = seed >>> 0;
  return () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296);
};

/* Mist sits where mist sits: in the valleys, against the windward slopes and
   out over the water between the sea stacks. */
export function buildMist(field, layout, uniforms, groundAt) {
  const r = rnd(4242);
  const low = [], mid = [], high = [];
  /* Mist sits where mist sits. The low banks go into the hollows — the
     field's own sky-occlusion tells us where those are — the mid layer
     wraps the shoulders of the ridges at the height a cloud base would sit,
     and the high layer caps the volcano and the plateau. Three layers at
     three heights is what reads as weather; one even wash reads as a dirty
     lens, which is what the old single band was. */
  for (let i = 0; i < 2600 && low.length < 108; i++) {
    const a = r() * Math.PI * 2;
    const rad = 260 + 1640 * Math.sqrt(r());
    const x = Math.cos(a) * rad, z = Math.sin(a) * rad;
    const g = groundAt(x, z);
    const hollow = field ? sampleGrid(field, field.ao, x, z) : 0.5;
    if (g > 6 && hollow > 0.78) continue;
    /* Thick where it collects and nothing where it does not: the hollower
       the ground, the lower and fatter the bank. An even scatter of equal
       puffs is a dirty lens; a few deep banks lying in the valleys is
       weather. */
    const depth = 1 - clamp((hollow - 0.5) / 0.4, 0, 1);
    const base = Math.max(4, g) + 10 + r() * 46 * (1.2 - depth * 0.6);
    low.push({ x, y: base, z, s: 150 + 300 * r() * (0.7 + depth), seed: r(), speed: 0.45 + 0.9 * r(), floor: Math.max(0, g) - 4 });
  }
  // banks lying on the water out among the sea stacks, where the reference
  // picture has them: thick, low, and hiding the feet of the towers
  for (let i = 0; i < 44; i++) {
    const x = 700 + 1600 * r(), z = -1400 + 2800 * r();
    low.push({ x, y: 8 + 62 * r(), z, s: 220 + 360 * r(), seed: r(), speed: 0.3 + 0.8 * r(), floor: -40 });
  }
  // and over the marsh, which is the one place on the island that steams
  for (let i = 0; i < 26; i++) {
    const a = r() * Math.PI * 2, rad = 380 * Math.sqrt(r());
    const x = -740 + Math.cos(a) * rad, z = 520 + Math.sin(a) * rad;
    low.push({ x, y: 10 + 26 * r(), z, s: 110 + 200 * r(), seed: r(), speed: 0.25 + 0.5 * r(), floor: 0 });
  }
  // the cloud base: a layer wrapping the ridges at two or three hundred metres
  for (let i = 0; i < 1400 && mid.length < 46; i++) {
    const a = r() * Math.PI * 2;
    const rad = 150 + 1250 * Math.sqrt(r());
    const x = Math.cos(a) * rad, z = Math.sin(a) * rad;
    const g = groundAt(x, z);
    if (g < 70) continue;
    mid.push({ x, y: g * 0.62 + 150 + r() * 90, z, s: 260 + 360 * r(), seed: r(), speed: 0.3 + 0.7 * r(), floor: g - 60 });
  }
  // cloud clinging to the volcano and the plateau
  for (const peak of [[-150, -330, 620], [430, -800, 420], [-820, -180, 380], [-130, -830, 400]]) {
    for (let i = 0; i < 11; i++) {
      const a = r() * Math.PI * 2, rad = 90 + 340 * Math.sqrt(r());
      high.push({ x: peak[0] + Math.cos(a) * rad, y: peak[2] + (r() - 0.4) * 150, z: peak[1] + Math.sin(a) * rad,
        s: 230 + 330 * r(), seed: r(), speed: 0.25 + 0.5 * r(), floor: -1e4 });
    }
  }
  for (let i = 0; i < 24; i++) {
    const a = r() * Math.PI * 2;
    const rad = 300 + 1200 * Math.sqrt(r());
    const x = Math.cos(a) * rad, z = Math.sin(a) * rad;
    const g = groundAt(x, z);
    high.push({ x, y: Math.max(170, g * 0.78 + 200) + r() * 140, z, s: 340 + 460 * r(), seed: r(), speed: 0.3 + 0.6 * r(), floor: -1e4 });
  }
  const group = new THREE.Group();
  group.name = "mist";
  // opacity stays low per quad: these are layers that separate the ridges,
  // not weather. Stacked three or four deep they read as a bank.
  group.add(puffSystem(uniforms, low, { kind: 0, color: [1, 0.96, 0.9], opacity: 0.062, flat: 2.6, name: "mist-low", order: 6 }));
  group.add(puffSystem(uniforms, mid, { kind: 0, color: [1, 0.95, 0.88], opacity: 0.040, flat: 2.6, name: "mist-mid", order: 7 }));
  group.add(puffSystem(uniforms, high, { kind: 0, color: [1, 0.95, 0.9], opacity: 0.030, flat: 2.7, name: "mist-high", order: 8 }));
  return group;
}

export function buildSmoke(uniforms, site) {
  const r = rnd(1717);
  const list = [];
  const base = heightAt(site.x, site.z);
  for (let i = 0; i < 40; i++) {
    list.push({
      x: site.x + (r() - 0.5) * 90, y: base + 10, z: site.z + (r() - 0.5) * 90,
      s: 32 + 36 * r(), seed: r(), speed: 0.5 + 0.8 * r(), rise: 380 + 360 * r(), floor: -1e4,
    });
  }
  return puffSystem(uniforms, list, { kind: 1, color: [0.72, 0.63, 0.58], opacity: 0.26, flat: 1.3, name: "smoke", order: 9 });
}

export function buildSpray(uniforms) {
  const r = rnd(3131);
  const list = [];
  for (const f of FALLS) {
    const base = 2;
    for (let i = 0; i < 34; i++) {
      list.push({
        x: f.x + (r() - 0.5) * f.w * 3.6, y: base + r() * 34, z: f.z + (r() - 0.5) * f.w * 3.6,
        s: 26 + 38 * r(), seed: r(), speed: 0.55 + 0.6 * r(), rise: 110 + 150 * r(), floor: -1e4,
      });
    }
  }
  return puffSystem(uniforms, list, { kind: 2, color: [1, 1, 1], opacity: 0.44, flat: 1.5, name: "spray", order: 10 });
}
