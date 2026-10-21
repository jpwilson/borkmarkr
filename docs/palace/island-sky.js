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
        // the disc itself, flattened by the haze it sits in
        float disc = smoothstep(0.99955, 0.99985, toSun);
        color = mix(color, uSunColor * 2.6, disc * clamp(h * 14.0, 0.0, 1.0));

        // long low cloud banks, drifting
        vec2 p = vec2(atan(d.z, d.x) * 0.42, d.y * 2.6);
        float n = texture2D(uDetail, p * vec2(0.5, 1.2) + vec2(uTime * 0.0012, 0.0)).r
                + texture2D(uDetail, p * vec2(1.6, 2.4) - vec2(uTime * 0.0021, 0.0)).g * 0.6;
        float band = smoothstep(0.80, 1.3, n) * smoothstep(0.42, 0.04, abs(h - 0.085));
        vec3 cloud = mix(uHazeColor * 0.7, uSunHaze * 1.2, pow(toSun, 2.0) * 0.8 + 0.2);
        color = mix(color, cloud, band * 0.62);

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
  const idx = [];
  const corners = [[-1, -1], [1, -1], [1, 1], [-1, 1]];
  list.forEach((p, i) => {
    for (let c = 0; c < 4; c++) {
      const v = i * 4 + c;
      pos[v * 3] = p.x; pos[v * 3 + 1] = p.y; pos[v * 3 + 2] = p.z;
      corner[v * 2] = corners[c][0]; corner[v * 2 + 1] = corners[c][1];
      params[v * 4] = p.s; params[v * 4 + 1] = p.seed; params[v * 4 + 2] = p.speed ?? 1; params[v * 4 + 3] = p.rise ?? 1;
    }
    const b = i * 4;
    idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
  });
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  g.setAttribute("corner", new THREE.BufferAttribute(corner, 2));
  g.setAttribute("params", new THREE.BufferAttribute(params, 4));
  g.setIndex(idx);
  g.computeBoundingSphere();
  if (g.boundingSphere) g.boundingSphere.radius += 400;

  const mat = new THREE.ShaderMaterial({
    uniforms: { ...uniforms, uKind: { value: kind }, uTint: { value: new THREE.Color(...color) }, uOpacity: { value: opacity }, uFlat: { value: flat } },
    transparent: true,
    depthWrite: false,
    vertexShader: /* glsl */`
      attribute vec2 corner; attribute vec4 params;
      uniform float uTime, uKind, uFlat;
      varying vec3 vWorld; varying vec2 vUv; varying float vSeed; varying float vFade;
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
          c.x += age * age * 230.0 + sin(seed * 9.1 + age * 3.0) * 34.0 * age;
          c.z += age * 26.0 + cos(seed * 5.5 + age * 2.4) * 30.0 * age;
          size *= 0.35 + age * 2.6;
          fade = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(0.45, 1.0, age));
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
        vWorld = world; vUv = corner; vSeed = seed; vFade = fade;
        gl_Position = projectionMatrix * viewMatrix * vec4(world, 1.0);
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      uniform sampler2D uDetail;
      uniform vec3 uTint; uniform float uOpacity, uKind;
      varying vec2 vUv; varying float vSeed; varying float vFade;
      void main() {
        float r = length(vUv);
        float soft = smoothstep(1.0, 0.1, r);
        vec2 q = vUv * 0.33 + vec2(vSeed * 3.7, vSeed * 1.9) + vec2(uTime * 0.0015, 0.0);
        float n = texture2D(uDetail, q).r * 0.7 + texture2D(uDetail, q * 2.7 + 0.21).b * 0.5;
        float alpha = soft * smoothstep(0.22, 0.95, n + soft * 0.55) * uOpacity * vFade;
        if (alpha < 0.004) discard;
        vec3 viewDir = normalize(cameraPosition - vWorld);
        float toSun = max(0.0, dot(normalize(-viewDir), uSunDir));
        // mist is lit from behind by a low sun: that is the whole effect
        vec3 color = uTint * (uSkyColor * 0.85 + uSunColor * (0.10 + pow(toSun, 3.0) * 0.55));
        float dist = length(vWorld - cameraPosition);
        // a bank only reads as a bank from outside it
        alpha *= smoothstep(60.0, 520.0, dist);
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
  const low = [], high = [];
  // low mist collects where the ground is concave: valleys, basins, the bay
  for (let i = 0; i < 900 && low.length < 130; i++) {
    const a = r() * Math.PI * 2;
    const rad = 300 + 1600 * Math.sqrt(r());
    const x = Math.cos(a) * rad, z = Math.sin(a) * rad;
    const g = groundAt(x, z);
    const hollow = field ? sampleGrid(field, field.ao, x, z) : 0.5;
    if (g > 6 && hollow > 0.80) continue;
    const base = Math.max(4, g) + 12 + r() * 70;
    low.push({ x, y: base, z, s: 130 + 240 * r(), seed: r(), speed: 0.5 + r() });
  }
  // banks lying on the water out among the sea stacks
  for (let i = 0; i < 60; i++) {
    const x = 760 + 1500 * r(), z = -1300 + 2600 * r();
    low.push({ x, y: 10 + 70 * r(), z, s: 180 + 300 * r(), seed: r(), speed: 0.35 + 0.8 * r() });
  }
  for (let i = 0; i < 46; i++) {
    const a = r() * Math.PI * 2;
    const rad = 300 + 1100 * Math.sqrt(r());
    const x = Math.cos(a) * rad, z = Math.sin(a) * rad;
    const g = groundAt(x, z);
    high.push({ x, y: Math.max(150, g * 0.78 + 170) + r() * 120, z, s: 320 + 420 * r(), seed: r(), speed: 0.35 + 0.6 * r() });
  }
  const group = new THREE.Group();
  group.name = "mist";
  // opacity is deliberately low: these are layers that separate the ridges,
  // not weather. Stacked three or four deep they still read as a bank.
  group.add(puffSystem(uniforms, low, { kind: 0, color: [1, 0.97, 0.92], opacity: 0.075, flat: 2.3, name: "mist-low", order: 6 }));
  group.add(puffSystem(uniforms, high, { kind: 0, color: [1, 0.96, 0.9], opacity: 0.042, flat: 2.6, name: "mist-high", order: 7 }));
  return group;
}

export function buildSmoke(uniforms, site) {
  const r = rnd(1717);
  const list = [];
  const base = heightAt(site.x, site.z);
  for (let i = 0; i < 26; i++) {
    list.push({
      x: site.x + (r() - 0.5) * 70, y: base + 10, z: site.z + (r() - 0.5) * 70,
      s: 42 + 40 * r(), seed: r(), speed: 0.6 + 0.8 * r(), rise: 520 + 420 * r(),
    });
  }
  return puffSystem(uniforms, list, { kind: 1, color: [0.84, 0.8, 0.78], opacity: 0.22, flat: 1.25, name: "smoke", order: 8 });
}

export function buildSpray(uniforms) {
  const r = rnd(3131);
  const list = [];
  for (const f of FALLS) {
    const base = 2;
    for (let i = 0; i < 16; i++) {
      list.push({
        x: f.x + (r() - 0.5) * f.w * 2.4, y: base + r() * 14, z: f.z + (r() - 0.5) * f.w * 2.4,
        s: 16 + 20 * r(), seed: r(), speed: 0.7 + 0.6 * r(), rise: 60 + 70 * r(),
      });
    }
  }
  return puffSystem(uniforms, list, { kind: 2, color: [1, 1, 1], opacity: 0.3, flat: 1.4, name: "spray", order: 9 });
}
