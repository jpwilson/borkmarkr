/* island-fauna.js — the birds.

   A handful of flocks turning over the ridges and the bay. Everything about
   a bird — where it is on its circle, how far it has banked, where its wings
   are in the stroke — is a function of uTime and the bird's own seed, so a
   flock is one draw call and a frame at t is the same frame whenever it is
   asked for.

   The geometry is a two-triangle V: a body point and two wings. `wing` in
   the vertex buffer is -1, 0, +1 across the span, and the vertex shader
   folds the tips up and down from that. */
import * as THREE from "three";
import { ATMOS_PARS, groundAt } from "./island-terrain.js";
import { clamp, noise2 } from "./island-layout.js";

function birdGeometry() {
  const g = new THREE.BufferGeometry();
  // body at the origin, a tail behind it, a tip either side
  const pos = [
    0, 0, 0.22, 0, 0, -0.30, -1, 0, 0.02,
    0, 0, 0.22, 1, 0, 0.02, 0, 0, -0.30,
  ];
  const wing = [0, 0, -1, 0, 1, 0];
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("wing", new THREE.Float32BufferAttribute(wing, 1));
  return g;
}

export function buildBirds(field, layout, uniforms) {
  /* Flocks sit where a bird would be: turning over a ridge on the updraught,
     working the surf line, drifting across the bay between the stacks. */
  const flocks = [];
  const addFlock = (x, z, y, r, n, speed, size) => flocks.push({ x, z, y, r, n, speed, size });
  for (const zone of layout.zones.slice(0, 6)) {
    const g = groundAt(field, zone.x, zone.z);
    addFlock(zone.x + 120, zone.z - 90, g + 150 + 120 * Math.abs(noise2(zone.index * 2.1, 1.7)),
      210 + 160 * Math.abs(noise2(zone.index, 3.3)), 9, 0.1 + 0.05 * Math.abs(noise2(zone.index, 7.1)), 3.6);
  }
  addFlock(1420, 60, 150, 420, 14, 0.07, 4.4);      // out among the sea stacks
  addFlock(820, 760, 70, 300, 12, 0.09, 3.8);       // over the lagoon
  addFlock(-980, 640, 60, 260, 10, 0.1, 3.4);       // the marsh

  const list = [];
  for (const f of flocks) {
    for (let i = 0; i < f.n; i++) {
      const u = (i + 0.5) / f.n;
      list.push({
        cx: f.x, cz: f.z, cy: f.y + (noise2(i * 1.7, f.x * 0.01) * 40),
        r: f.r * (0.55 + 0.6 * Math.abs(noise2(i * 2.3, f.z * 0.01))),
        phase: u * Math.PI * 2 + noise2(i, f.r) * 0.9,
        speed: f.speed * (0.86 + 0.3 * Math.abs(noise2(i * 3.1, 5.5))),
        size: f.size * (0.72 + 0.6 * Math.abs(noise2(i * 5.3, 2.2))),
        flap: 0.8 + 1.5 * Math.abs(noise2(i * 7.7, 9.1)),
      });
    }
  }

  const geo = new THREE.InstancedBufferGeometry().copy(birdGeometry());
  geo.instanceCount = list.length;
  const a = new Float32Array(list.length * 4), b = new Float32Array(list.length * 4);
  list.forEach((it, i) => {
    a[i * 4] = it.cx; a[i * 4 + 1] = it.cy; a[i * 4 + 2] = it.cz; a[i * 4 + 3] = it.r;
    b[i * 4] = it.phase; b[i * 4 + 1] = it.speed; b[i * 4 + 2] = it.size; b[i * 4 + 3] = it.flap;
  });
  geo.setAttribute("orbit", new THREE.InstancedBufferAttribute(a, 4));
  geo.setAttribute("beat", new THREE.InstancedBufferAttribute(b, 4));
  geo.boundingSphere = new THREE.Sphere(new THREE.Vector3(0, 200, 0), 4000);

  const mat = new THREE.ShaderMaterial({
    uniforms,
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
    vertexShader: /* glsl */`
      attribute float wing; attribute vec4 orbit; attribute vec4 beat;
      uniform float uTime;
      varying vec3 vWorld; varying float vBank; varying float vDist;
      void main() {
        float ang = beat.x + uTime * beat.y;
        vec3 centre = vec3(orbit.x + cos(ang) * orbit.w, orbit.y + sin(ang * 1.7) * 14.0, orbit.z + sin(ang) * orbit.w);
        // heading is the tangent of the circle; banking into the turn
        vec2 fwd = vec2(-sin(ang), cos(ang));
        float flap = sin(uTime * beat.w * 6.2 + beat.x * 5.0);
        vec3 p = position * beat.z;
        p.y += abs(wing) * flap * beat.z * 0.55;
        // orient: x across the span, z along the heading
        vec3 world = centre + vec3(fwd.y, 0.0, -fwd.x) * p.x + vec3(fwd.x, 0.0, fwd.y) * p.z + vec3(0.0, p.y, 0.0);
        vWorld = world;
        vBank = abs(flap);
        vDist = length(world - cameraPosition);
        gl_Position = projectionMatrix * viewMatrix * vec4(world, 1.0);
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      varying float vBank; varying float vDist;
      void main() {
        // a bird at this range is a dark mark that catches a little sun on
        // the upstroke; anything more detailed is noise at a kilometre
        vec3 color = mix(vec3(0.015, 0.016, 0.020), uSunColor * 0.14, vBank * 0.5);
        vec3 viewDir = normalize(cameraPosition - vWorld);
        color = applyAtmos(color, vWorld, -viewDir);
        float a = 0.92 * (1.0 - smoothstep(1400.0, 3200.0, vDist)) * smoothstep(16.0, 90.0, vDist);
        if (a < 0.01) discard;
        gl_FragColor = vec4(color * uExposure, a);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = "birds";
  mesh.renderOrder = 5;
  mesh.frustumCulled = false;
  mesh.userData.tris = 2 * list.length;
  mesh.userData.count = list.length;
  return mesh;
}
