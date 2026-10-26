/* island-post.js — the grade.

   The world shaders write linear light. When a render target is bound,
   three.js compiles every material with NoToneMapping and a linear output
   colour space (WebGLPrograms.getParameters), so the scene lands in a
   half-float buffer as unclamped radiance with no code change in any
   material — and when post is off the very same materials tone-map straight
   to the canvas as they always did.

   On top of that: a bright pass at quarter resolution, a separable blur for
   bloom, a radial blur from the sun for god rays, then one full-resolution
   composite that does ACES, a teal/orange grade with lifted blacks, a
   vignette and an ordered dither.

   Everything here is a pure function of the frame and the sun's screen
   position, so ?capture stays deterministic. */
import * as THREE from "three";

function quadGeometry() {
  const QUAD = new THREE.BufferGeometry();
  QUAD.setAttribute("position", new THREE.Float32BufferAttribute([-1, -1, 0, 3, -1, 0, -1, 3, 0], 3));
  QUAD.setAttribute("uv", new THREE.Float32BufferAttribute([0, 0, 2, 0, 0, 2], 2));
  return QUAD;
}

/* Narkowicz's ACES fit, in the renderer's own form, so turning post on does
   not change the tone curve the scene was lit for. */
const ACES = /* glsl */`
  vec3 aces(vec3 x) {
    const mat3 m1 = mat3(0.59719, 0.07600, 0.02840, 0.35458, 0.90834, 0.13383, 0.04823, 0.01566, 0.83777);
    const mat3 m2 = mat3(1.60475, -0.10208, -0.00327, -0.53108, 1.10813, -0.07276, -0.07367, -0.00605, 1.07602);
    vec3 v = m1 * x;
    vec3 a = v * (v + 0.0245786) - 0.000090537;
    vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
    return clamp(m2 * (a / b), 0.0, 1.0);
  }
`;

function pass(geometry, uniforms, fragmentShader) {
  const mat = new THREE.RawShaderMaterial({
    uniforms,
    glslVersion: THREE.GLSL3,
    vertexShader: `in vec3 position; in vec2 uv; out vec2 vUv;
      void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`,
    fragmentShader: `precision highp float; precision highp int;
      in vec2 vUv; out vec4 fragColor;
      ${fragmentShader}`,
    depthTest: false, depthWrite: false,
  });
  return new THREE.Mesh(geometry, mat);
}

export class Post {
  constructor(renderer, { capture = false } = {}) {
    this.renderer = renderer;
    this.capture = capture;
    this.enabled = true;
    this.scale = 1;
    this.geometry = quadGeometry();
    this.width = 1; this.height = 1;
    this.quad = new THREE.Scene();
    this.cam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);

    const rt = (w, h, depth) => {
      const t = new THREE.WebGLRenderTarget(w, h, {
        type: THREE.HalfFloatType, format: THREE.RGBAFormat,
        minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter,
        depthBuffer: !!depth, stencilBuffer: false,
        colorSpace: THREE.LinearSRGBColorSpace,
      });
      return t;
    };
    this.rt = { scene: rt(2, 2, true), bright: rt(2, 2), tmp: rt(2, 2), rays: rt(2, 2) };

    this.u = {
      bright: {
        uTex: { value: null }, uTexel: { value: new THREE.Vector2() },
        uThreshold: { value: 1.06 }, uSun: { value: new THREE.Vector2(0.5, 0.5) },
        uSunOn: { value: 1 },
      },
      blur: { uTex: { value: null }, uDir: { value: new THREE.Vector2() } },
      rays: {
        uTex: { value: null }, uSun: { value: new THREE.Vector2(0.5, 0.5) },
        uDensity: { value: 0.62 }, uDecay: { value: 0.955 }, uWeight: { value: 0.62 },
      },
      comp: {
        uScene: { value: null }, uBloom: { value: null }, uRays: { value: null },
        uBloomAmt: { value: 0.52 }, uRayAmt: { value: 0.0 },
        uSun: { value: new THREE.Vector2(0.5, 0.5) }, uSunTint: { value: new THREE.Color(1, 0.74, 0.44) },
        // three's ACESFilmicToneMapping scales by toneMappingExposure / 0.6
        // before the fit; matching it keeps post-on and post-off the same
        // brightness, so the low tier is not a different-looking page
        uExposure: { value: 1 / 0.6 }, uVignette: { value: 0.42 }, uGrade: { value: 1.0 },
        uTexel: { value: new THREE.Vector2() },
      },
    };

    this.mBright = pass(this.geometry, this.u.bright, /* glsl */`
      uniform sampler2D uTex; uniform vec2 uTexel, uSun; uniform float uThreshold, uSunOn;
      void main() {
        // a 4-tap box on the way down: the quarter-res buffer is what both
        // the bloom and the shafts are built from, so it must not sparkle
        vec3 c = texture(uTex, vUv + uTexel * vec2(-1.0, -1.0)).rgb
               + texture(uTex, vUv + uTexel * vec2( 1.0, -1.0)).rgb
               + texture(uTex, vUv + uTexel * vec2(-1.0,  1.0)).rgb
               + texture(uTex, vUv + uTexel * vec2( 1.0,  1.0)).rgb;
        c *= 0.25;
        float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
        vec3 b = c * max(0.0, l - uThreshold) / max(l, 1e-4);
        // the shafts only come from what is near the sun on screen, which is
        // what stops a bright lagoon on the far side throwing rays sideways
        float near = (1.0 - smoothstep(0.12, 0.95, length((vUv - uSun) * vec2(1.0, 0.56))));
        fragColor = vec4(b, near * uSunOn);
      }`);

    this.mBlur = pass(this.geometry, this.u.blur, /* glsl */`
      uniform sampler2D uTex; uniform vec2 uDir;
      void main() {
        vec4 s = texture(uTex, vUv) * 0.227027;
        s += (texture(uTex, vUv + uDir * 1.3846) + texture(uTex, vUv - uDir * 1.3846)) * 0.316216;
        s += (texture(uTex, vUv + uDir * 3.2308) + texture(uTex, vUv - uDir * 3.2308)) * 0.070270;
        fragColor = s;
      }`);

    this.mRays = pass(this.geometry, this.u.rays, /* glsl */`
      uniform sampler2D uTex; uniform vec2 uSun; uniform float uDensity, uDecay, uWeight;
      void main() {
        vec2 d = (vUv - uSun) * uDensity / 24.0;
        vec2 p = vUv;
        float w = uWeight, total = 0.0;
        vec3 acc = vec3(0.0);
        for (int i = 0; i < 24; i++) {
          p -= d;
          vec4 s = texture(uTex, p);
          acc += s.rgb * s.a * w;
          total += w;
          w *= uDecay;
        }
        fragColor = vec4(acc / max(total, 1e-4), 1.0);
      }`);

    this.mComp = pass(this.geometry, this.u.comp, /* glsl */`
      ${ACES}
      uniform sampler2D uScene, uBloom, uRays;
      uniform vec2 uSun, uTexel;
      uniform vec3 uSunTint;
      uniform float uBloomAmt, uRayAmt, uExposure, uVignette, uGrade;
      void main() {
        vec3 c = texture(uScene, vUv).rgb;
        c += texture(uBloom, vUv).rgb * uBloomAmt;
        c += texture(uRays, vUv).rgb * uSunTint * uRayAmt;
        c *= uExposure;
        c = aces(c);

        /* The grade. Teal in the shadows, amber in the highlights, a gentle
           S through the midtones and a real push on saturation — ACES on its
           own leaves a jungle looking like a rainy afternoon. */
        float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
        vec3 shadow = vec3(0.016, 0.040, 0.054);
        vec3 highl  = vec3(1.075, 1.005, 0.900);
        vec3 graded = mix(c * 0.93 + shadow, c * highl, smoothstep(0.03, 0.66, l));
        // contrast: a smoothstep pivoted on the midtones, mixed back in part
        vec3 contrast = graded * graded * (3.0 - 2.0 * clamp(graded, 0.0, 1.0));
        graded = mix(graded, contrast, 0.34);
        float gl = dot(graded, vec3(0.2126, 0.7152, 0.0722));
        graded = mix(vec3(gl), graded, 1.30);
        c = mix(c, graded, uGrade);

        // vignette, and a warm lift right around the sun
        vec2 q = vUv - 0.5;
        float vig = 1.0 - uVignette * dot(q, q) * 1.9;
        c *= clamp(vig, 0.0, 1.0);
        float halo = (1.0 - smoothstep(0.0, 0.62, length((vUv - uSun) * vec2(1.0, 0.62))));
        c += uSunTint * halo * halo * 0.055 * uRayAmt;

        /* The canvas is sRGB and nothing in this pass is a three.js material,
           so the encode is ours to do. Writing linear straight to an sRGB
           drawing buffer is what turns a golden hour into a night scene. */
        c = max(c, 0.0);
        vec3 srgb = mix(pow(c, vec3(0.41666)) * 1.055 - 0.055, c * 12.92, step(c, vec3(0.0031308)));

        // ordered dither: a 4x4 Bayer pattern, so the sky gradient does not band
        vec2 ip = mod(floor(gl_FragCoord.xy), 4.0);
        float bayer = mod(ip.x * 5.0 + ip.y * 3.0, 16.0) / 16.0;
        srgb += (bayer - 0.5) / 255.0;

        fragColor = vec4(max(srgb, 0.0), 1.0);
      }`);

    this.quad.add(this.mComp);
    this.current = this.mComp;
  }

  setSize(w, h) {
    this.width = Math.max(1, Math.round(w));
    this.height = Math.max(1, Math.round(h));
    const pr = this.renderer.getPixelRatio();
    const fw = Math.max(1, Math.round(this.width * pr)), fh = Math.max(1, Math.round(this.height * pr));
    this.rt.scene.setSize(this.enabled ? fw : 1, this.enabled ? fh : 1);
    const qw = Math.max(2, Math.round(fw * this.scale / 4)), qh = Math.max(2, Math.round(fh * this.scale / 4));
    this.rt.bright.setSize(this.enabled ? qw : 1, this.enabled ? qh : 1);
    this.rt.tmp.setSize(this.enabled ? qw : 1, this.enabled ? qh : 1);
    this.rt.rays.setSize(this.enabled ? qw : 1, this.enabled ? qh : 1);
    this.u.bright.uTexel.value.set(1 / fw, 1 / fh);
    this.u.comp.uTexel.value.set(1 / fw, 1 / fh);
    this.qw = qw; this.qh = qh;
  }

  /* Swap the full-screen mesh under the ortho camera: one scene, one child. */
  blit(mesh, target) {
    if (this.current !== mesh) {
      this.quad.remove(this.current);
      this.quad.add(mesh);
      this.current = mesh;
    }
    this.renderer.setRenderTarget(target || null);
    this.renderer.render(this.quad, this.cam);
  }

  /* `sun` is {x, y} in 0..1 screen space with y measured from the bottom,
     plus `front` — whether the sun is in front of the camera at all. */
  render(scene, camera, sun, opts = {}) {
    const r = this.renderer;
    if (!this.enabled) {
      r.setRenderTarget(null);
      r.render(scene, camera);
      this.info = { triangles: r.info.render.triangles, calls: r.info.render.calls };
      return;
    }
    r.setRenderTarget(this.rt.scene);
    r.render(scene, camera);
    // renderer.info counts the last draw, and the last draw is a blit: snap
    // the world's numbers here or stats() reports one triangle
    this.info = { triangles: r.info.render.triangles, calls: r.info.render.calls };

    const u = this.u;
    const sx = Math.min(1.4, Math.max(-0.4, sun.x)), sy = Math.min(1.4, Math.max(-0.4, sun.y));
    u.bright.uSun.value.set(sx, sy);
    u.bright.uSunOn.value = sun.front ? 1 : 0;
    u.rays.uSun.value.set(sx, sy);
    u.comp.uSun.value.set(sx, sy);
    // the shafts fade out as the sun leaves the frame, rather than snapping
    const off = Math.max(0, Math.max(Math.abs(sx - 0.5), Math.abs(sy - 0.5)) - 0.5);
    u.comp.uRayAmt.value = (sun.front ? 1 : 0) * (opts.rays ?? 0.9) * Math.max(0, 1 - off * 2.4);

    u.bright.uTex.value = this.rt.scene.texture;
    this.blit(this.mBright, this.rt.bright);

    if (u.comp.uRayAmt.value > 0.001) {
      u.rays.uTex.value = this.rt.bright.texture;
      this.blit(this.mRays, this.rt.rays);
    }

    // two separable taps over the quarter buffer: a wide, soft halo
    u.blur.uTex.value = this.rt.bright.texture;
    u.blur.uDir.value.set(1.6 / this.qw, 0);
    this.blit(this.mBlur, this.rt.tmp);
    u.blur.uTex.value = this.rt.tmp.texture;
    u.blur.uDir.value.set(0, 1.6 / this.qh);
    this.blit(this.mBlur, this.rt.bright);
    if (this.scale >= 1) {
      u.blur.uTex.value = this.rt.bright.texture;
      u.blur.uDir.value.set(3.4 / this.qw, 0);
      this.blit(this.mBlur, this.rt.tmp);
      u.blur.uTex.value = this.rt.tmp.texture;
      u.blur.uDir.value.set(0, 3.4 / this.qh);
      this.blit(this.mBlur, this.rt.bright);
    }

    u.comp.uScene.value = this.rt.scene.texture;
    u.comp.uBloom.value = this.rt.bright.texture;
    u.comp.uRays.value = this.rt.rays.texture;
    this.blit(this.mComp, null);
  }

  dispose() {
    this.geometry.dispose();
    for (const t of Object.values(this.rt)) t.dispose();
    for (const m of [this.mBright, this.mBlur, this.mRays, this.mComp]) m.material.dispose();
  }
}
