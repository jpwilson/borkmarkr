/* Procedural canvas art for the palace: stone, marble, coffers, signage and
   bookmark cards. Everything is drawn at load time, so the page ships no
   image assets. Text always goes through fitText(): it shrinks, wraps and
   finally ellipsizes, so a label can never spill past its plaque. */

export const INK = "#191510", INK2 = "#6E655A", PAPER = "#F6F3EE", CORAL = "#FF5A2D", CORAL_DEEP = "#C93A12";
export const HEAD = '"Bricolage Grotesque", "Helvetica Neue", Helvetica, Arial, sans-serif';
export const BODY = '"Instrument Sans", -apple-system, "Segoe UI", Helvetica, Arial, sans-serif';

export function rng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function topicColor(hue, s = 65, l = 55) { return `hsl(${hue} ${s}% ${l}%)`; }

export function canvas(w, h, { readback = false } = {}) {
  const c = document.createElement("canvas");
  c.width = w; c.height = h;
  const g = c.getContext("2d", readback ? { willReadFrequently: true } : undefined);
  return { c, g };
}

function roundRect(g, x, y, w, h, r) {
  g.beginPath();
  g.moveTo(x + r, y);
  g.arcTo(x + w, y, x + w, y + h, r);
  g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r);
  g.arcTo(x, y, x + w, y, r);
  g.closePath();
}

function setFont(g, weight, size, family, spacing = 0) {
  g.font = `${weight} ${size}px ${family}`;
  if ("letterSpacing" in g) g.letterSpacing = `${spacing * size}px`;
}

function wrap(g, text, maxW) {
  const words = text.split(/\s+/).filter(Boolean);
  const lines = [];
  let line = "";
  for (const word of words) {
    const test = line ? `${line} ${word}` : word;
    if (g.measureText(test).width <= maxW) { line = test; continue; }
    if (line) lines.push(line);
    if (g.measureText(word).width <= maxW) { line = word; continue; }
    let part = "";
    for (const ch of word) {
      if (g.measureText(part + ch).width > maxW && part) { lines.push(part); part = ch; } else part += ch;
    }
    line = part;
  }
  if (line) lines.push(line);
  return lines;
}

/* Largest size in [min, max] whose wrapped lines fit maxW × maxLines; at the
   minimum size the overflow is ellipsized instead of clipped. */
export function fitText(g, text, { maxW, maxLines = 1, max, min, weight = 700, family = HEAD, spacing = 0, maxH = Infinity, lineH = 1.12 }) {
  for (let size = max; size >= min; size--) {
    setFont(g, weight, size, family, spacing);
    const lines = wrap(g, text, maxW);
    if (lines.length <= maxLines && lines.length * size * lineH <= maxH) return { size, lines, lineH };
  }
  setFont(g, weight, min, family, spacing);
  let lines = wrap(g, text, maxW);
  const cap = Math.max(1, Math.min(maxLines, Math.floor(maxH / (min * lineH)) || 1));
  if (lines.length > cap) {
    lines = lines.slice(0, cap);
    let last = lines[cap - 1];
    while (last && g.measureText(`${last}…`).width > maxW) last = last.slice(0, -1).trimEnd();
    lines[cap - 1] = `${last}…`;
  }
  return { size: min, lines, lineH };
}

/* ── Surfaces ── */

function grain(g, w, h, amount, seed, alpha = 0.05) {
  const r = rng(seed);
  for (let i = 0; i < amount; i++) {
    const x = r() * w, y = r() * h, s = 1 + r() * 3;
    g.fillStyle = r() < 0.5 ? `rgba(255,250,240,${alpha * r()})` : `rgba(60,40,25,${alpha * r()})`;
    g.fillRect(x, y, s, s);
  }
}

function clouds(g, w, h, seed, colors, count = 60, alpha = 0.08) {
  const r = rng(seed);
  for (let i = 0; i < count; i++) {
    const x = r() * w, y = r() * h, rad = (0.08 + r() * 0.3) * Math.max(w, h);
    const grad = g.createRadialGradient(x, y, 0, x, y, rad);
    const col = colors[Math.floor(r() * colors.length)];
    grad.addColorStop(0, col.replace("A", String(alpha * (0.4 + r()))));
    grad.addColorStop(1, col.replace("A", "0"));
    g.fillStyle = grad;
    g.fillRect(0, 0, w, h);
  }
}

function veins(g, x0, y0, w, h, seed, color, count, width = 1.4) {
  const r = rng(seed);
  g.save();
  g.beginPath(); g.rect(x0, y0, w, h); g.clip();
  for (let i = 0; i < count; i++) {
    let x = x0 + r() * w, y = y0 + r() * h;
    const ang = -0.6 + r() * 0.5;
    g.beginPath();
    g.moveTo(x, y);
    const segs = 6 + Math.floor(r() * 6);
    for (let s = 0; s < segs; s++) {
      const step = (0.05 + r() * 0.12) * Math.max(w, h);
      const nx = x + Math.cos(ang + (r() - 0.5) * 1.1) * step, ny = y + Math.sin(ang + (r() - 0.5) * 1.1) * step;
      g.quadraticCurveTo((x + nx) / 2 + (r() - 0.5) * step * 0.5, (y + ny) / 2 + (r() - 0.5) * step * 0.5, nx, ny);
      x = nx; y = ny;
    }
    g.strokeStyle = color.replace("A", String(0.05 + r() * 0.18));
    g.lineWidth = width * (0.4 + r() * 1.4);
    g.stroke();
  }
  g.restore();
}

function marbleTile(g, x, y, w, h, base, seed, veinColor = "rgba(90,70,55,A)") {
  g.fillStyle = base;
  g.fillRect(x, y, w, h);
  g.save();
  g.beginPath(); g.rect(x, y, w, h); g.clip();
  const r = rng(seed);
  for (let i = 0; i < 10; i++) {
    const cx = x + r() * w, cy = y + r() * h, rad = (0.2 + r() * 0.5) * w;
    const grad = g.createRadialGradient(cx, cy, 0, cx, cy, rad);
    const dark = r() < 0.5;
    grad.addColorStop(0, dark ? "rgba(120,95,75,0.07)" : "rgba(255,252,246,0.10)");
    grad.addColorStop(1, "rgba(0,0,0,0)");
    g.fillStyle = grad;
    g.fillRect(x, y, w, h);
  }
  g.restore();
  veins(g, x, y, w, h, seed * 7 + 3, veinColor, 5, w / 300);
}

/* Room floors: a diagonal chequer of cream and greige marble, 1.6 m tiles. */
export function floorTexture() {
  const S = 1024, { c, g } = canvas(S, S);
  const n = 4, t = S / n;
  for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
    const light = (i + j) % 2 === 0;
    marbleTile(g, i * t, j * t, t, t, light ? "#EEE6D9" : "#B9A893", i * 31 + j * 7 + 1, light ? "rgba(130,105,85,A)" : "rgba(70,52,40,A)");
  }
  g.strokeStyle = "rgba(60,42,30,0.55)";
  g.lineWidth = 2.2;
  for (let i = 0; i <= n; i++) {
    g.beginPath(); g.moveTo(i * t, 0); g.lineTo(i * t, S); g.stroke();
    g.beginPath(); g.moveTo(0, i * t); g.lineTo(S, i * t); g.stroke();
  }
  for (let i = 0; i <= n; i++) for (let j = 0; j <= n; j++) {
    g.save();
    g.translate(i * t, j * t);
    g.rotate(Math.PI / 4);
    g.fillStyle = "#7A3A22";
    g.fillRect(-9, -9, 18, 18);
    g.restore();
  }
  grain(g, S, S, 9000, 11, 0.06);
  return c;
}

/* The rotunda floor: concentric marble bands, an N-point star aligned to the
   doorways, an inscription ring and the coral bookmark medallion. */
export function rotundaFloorTexture(N, total) {
  const S = 2048, { c, g } = canvas(S, S), C = S / 2, R = S / 2;
  marbleTile(g, 0, 0, S, S, "#EFE8DC", 5);
  const ring = (r0, r1, color) => {
    g.beginPath(); g.arc(C, C, r1 * R, 0, Math.PI * 2); g.arc(C, C, r0 * R, 0, Math.PI * 2, true);
    g.fillStyle = color; g.fill("evenodd");
  };
  const line = (r, w, color) => { g.beginPath(); g.arc(C, C, r * R, 0, Math.PI * 2); g.lineWidth = w; g.strokeStyle = color; g.stroke(); };
  ring(0.885, 1.0, "#3A2A21");
  veins(g, 0, 0, S, S, 77, "rgba(240,225,205,A)", 40, 1.6);
  ring(0.0, 0.885, "#EFE8DC");
  marbleTile(g, C - 0.885 * R, C - 0.885 * R, 1.77 * R, 1.77 * R, "rgba(0,0,0,0)", 9);
  line(0.885, 7, CORAL_DEEP);
  line(0.86, 3, "#3A2A21");
  const points = N * 2, rOut = 0.83, rIn = 0.42;
  for (let i = 0; i < points; i++) {
    const a0 = (i / points) * Math.PI * 2 - Math.PI / 2, a1 = ((i + 0.5) / points) * Math.PI * 2 - Math.PI / 2, a2 = ((i + 1) / points) * Math.PI * 2 - Math.PI / 2;
    const P = (r, a) => [C + Math.cos(a) * r * R, C + Math.sin(a) * r * R];
    g.beginPath();
    g.moveTo(...P(rIn, a0)); g.lineTo(...P(rOut, a1)); g.lineTo(...P(rIn, a2)); g.lineTo(...P(0.27, a1)); g.closePath();
    g.fillStyle = i % 2 ? "#B6A28B" : "#D9CBB7";
    g.fill();
    g.lineWidth = 3; g.strokeStyle = "rgba(58,42,33,0.7)"; g.stroke();
  }
  ring(0.205, 0.27, "#3A2A21");
  line(0.27, 5, CORAL_DEEP);
  line(0.205, 5, CORAL_DEEP);
  const words = `BOOKMARKER · MEMORY PALACE · ${total} BOOKMARKS · `;
  setFont(g, 800, 46, HEAD, 0.18);
  g.fillStyle = "#EADBC4";
  g.textAlign = "center"; g.textBaseline = "middle";
  const chars = [...words.repeat(2)];
  const arc = (0.2375 * R);
  let ang = -Math.PI / 2;
  const full = chars.reduce((s, ch) => s + g.measureText(ch).width, 0);
  const scale = (Math.PI * 2 * arc) / full;
  for (const ch of chars) {
    const w = g.measureText(ch).width * scale;
    ang += w / arc / 2;
    g.save(); g.translate(C + Math.cos(ang) * arc, C + Math.sin(ang) * arc); g.rotate(ang + Math.PI / 2); g.fillText(ch, 0, 0); g.restore();
    ang += w / arc / 2;
  }
  const grad = g.createRadialGradient(C, C - 0.05 * R, 0, C, C, 0.2 * R);
  grad.addColorStop(0, "#FF7A4C"); grad.addColorStop(1, "#E2471C");
  g.beginPath(); g.arc(C, C, 0.2 * R, 0, Math.PI * 2); g.fillStyle = grad; g.fill();
  drawBookmark(g, C, C + 0.008 * R, 0.21 * R, PAPER);
  grain(g, S, S, 30000, 3, 0.05);
  return c;
}

export function drawBookmark(g, cx, cy, h, color) {
  const w = h * 0.66, r = w * 0.16, top = cy - h / 2, left = cx - w / 2, notch = h * 0.24;
  g.beginPath();
  g.moveTo(left + r, top);
  g.lineTo(left + w - r, top);
  g.quadraticCurveTo(left + w, top, left + w, top + r);
  g.lineTo(left + w, top + h - r * 0.4);
  g.quadraticCurveTo(left + w, top + h, left + w - r * 0.9, top + h - r * 0.55);
  g.lineTo(cx + r * 0.5, top + h - notch + r * 0.3);
  g.quadraticCurveTo(cx, top + h - notch, cx - r * 0.5, top + h - notch + r * 0.3);
  g.lineTo(left + r * 0.9, top + h - r * 0.55);
  g.quadraticCurveTo(left, top + h, left, top + h - r * 0.4);
  g.lineTo(left, top + r);
  g.quadraticCurveTo(left, top, left + r, top);
  g.closePath();
  g.fillStyle = color;
  g.fill();
}

/* Limestone ashlar: 4 m × 4 m per repeat, 0.8 m courses. */
export function stoneTexture() {
  const S = 1024, { c, g } = canvas(S, S);
  g.fillStyle = "#E7DDCE";
  g.fillRect(0, 0, S, S);
  clouds(g, S, S, 21, ["rgba(255,250,240,A)", "rgba(150,120,95,A)"], 70, 0.07);
  const rows = 5, rh = S / rows;
  const r = rng(4);
  g.strokeStyle = "rgba(95,72,55,0.30)";
  g.lineWidth = 2;
  for (let i = 0; i < rows; i++) {
    const y = i * rh;
    g.beginPath(); g.moveTo(0, y + 0.5); g.lineTo(S, y + 0.5); g.stroke();
    const blocks = 3 + (i % 2);
    const off = (i % 2) * (S / blocks / 2);
    for (let b = 0; b <= blocks; b++) {
      const x = (off + b * S / blocks) % S;
      g.beginPath(); g.moveTo(x, y); g.lineTo(x, y + rh); g.stroke();
    }
    for (let b = 0; b < 6; b++) {
      g.fillStyle = `rgba(${r() < 0.5 ? "255,250,242" : "120,95,75"},${0.025 + r() * 0.04})`;
      g.fillRect(r() * S, y, S / 4 * r(), rh);
    }
  }
  grain(g, S, S, 22000, 8, 0.07);
  return c;
}

/* Polished coral-terracotta marble for the columns. */
export function columnTexture() {
  const W = 512, H = 1024, { c, g } = canvas(W, H);
  const grad = g.createLinearGradient(0, 0, W, 0);
  grad.addColorStop(0, "#B9573A"); grad.addColorStop(0.5, "#C8664A"); grad.addColorStop(1, "#B9573A");
  g.fillStyle = grad;
  g.fillRect(0, 0, W, H);
  clouds(g, W, H, 13, ["rgba(255,215,190,A)", "rgba(90,30,15,A)"], 60, 0.12);
  veins(g, 0, 0, W, H, 41, "rgba(255,236,220,A)", 26, 2.2);
  veins(g, 0, 0, W, H, 42, "rgba(70,25,12,A)", 14, 1.6);
  return c;
}

/* Dome coffers in (azimuth, elevation) space; rows shrink towards the oculus. */
export function cofferTexture(cols = 32, rowsN = 7) {
  const W = 2048, H = 1024, { c, g } = canvas(W, H);
  g.fillStyle = "#D9CCB8";
  g.fillRect(0, 0, W, H);
  const cw = W / cols, rh = H / rowsN;
  for (let i = 0; i < cols; i++) for (let j = 0; j < rowsN; j++) {
    const x = i * cw, y = j * rh, m = cw * 0.12, m2 = cw * 0.2;
    g.fillStyle = "#B8A58C";
    g.fillRect(x + m, y + m, cw - 2 * m, rh - 2 * m);
    g.fillStyle = "#8E785F";
    g.fillRect(x + m2, y + m2, cw - 2 * m2, rh - 2 * m2);
    const grad = g.createLinearGradient(x, y + m2, x, y + rh - m2);
    grad.addColorStop(0, "rgba(40,25,15,0.35)"); grad.addColorStop(1, "rgba(255,240,220,0.08)");
    g.fillStyle = grad;
    g.fillRect(x + m2, y + m2, cw - 2 * m2, rh - 2 * m2);
    g.beginPath(); g.arc(x + cw / 2, y + rh / 2, Math.min(cw, rh) * 0.09, 0, Math.PI * 2);
    g.fillStyle = "#E9B66A"; g.fill();
  }
  grain(g, W, H, 20000, 5, 0.06);
  return c;
}

export function ceilingTexture() {
  const S = 1024, { c, g } = canvas(S, S), n = 4, t = S / n;
  g.fillStyle = "#D8CBB6"; g.fillRect(0, 0, S, S);
  for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
    const x = i * t, y = j * t;
    g.fillStyle = "#BCA98F"; g.fillRect(x + 18, y + 18, t - 36, t - 36);
    g.fillStyle = "#9C866B"; g.fillRect(x + 34, y + 34, t - 68, t - 68);
    g.beginPath(); g.arc(x + t / 2, y + t / 2, 12, 0, Math.PI * 2); g.fillStyle = "#E3AE63"; g.fill();
  }
  grain(g, S, S, 9000, 6, 0.06);
  return c;
}

/* Soft vertical wash for the back of each shelf niche: brighter under the
   picture light, falling into the room colour below. */
export function nicheTexture() {
  const { c, g } = canvas(64, 256);
  const grad = g.createLinearGradient(0, 0, 0, 256);
  grad.addColorStop(0, "#ffffff"); grad.addColorStop(0.18, "#d8d8d8"); grad.addColorStop(0.6, "#7a7a7a"); grad.addColorStop(1, "#4a4a4a");
  g.fillStyle = grad; g.fillRect(0, 0, 64, 256);
  const side = g.createLinearGradient(0, 0, 64, 0);
  side.addColorStop(0, "rgba(0,0,0,0.45)"); side.addColorStop(0.25, "rgba(0,0,0,0)"); side.addColorStop(0.75, "rgba(0,0,0,0)"); side.addColorStop(1, "rgba(0,0,0,0.45)");
  g.fillStyle = side; g.fillRect(0, 0, 64, 256);
  return c;
}

export function glowTexture() {
  const { c, g } = canvas(128, 128);
  const grad = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  grad.addColorStop(0, "rgba(255,255,255,1)"); grad.addColorStop(0.25, "rgba(255,255,255,0.45)"); grad.addColorStop(1, "rgba(255,255,255,0)");
  g.fillStyle = grad; g.fillRect(0, 0, 128, 128);
  return c;
}

/* ── Signage ── */

const PX_PER_M = 220;

/* Gilded name over a rotunda doorway, on a dark panel. */
export function inscriptionCanvas(name, wM, hM) {
  const W = Math.round(wM * PX_PER_M), H = Math.round(hM * PX_PER_M), { c, g } = canvas(W, H);
  const grad = g.createLinearGradient(0, 0, 0, H);
  grad.addColorStop(0, "#2E221B"); grad.addColorStop(1, "#1E1612");
  roundRect(g, 0, 0, W, H, H * 0.12); g.fillStyle = grad; g.fill();
  roundRect(g, 8, 8, W - 16, H - 16, H * 0.09); g.lineWidth = 3; g.strokeStyle = "rgba(233,190,120,0.75)"; g.stroke();
  const fit = fitText(g, name.toUpperCase(), { maxW: W - H * 1.1, max: Math.round(H * 0.52), min: Math.round(H * 0.24), weight: 800, family: HEAD, spacing: 0.14 });
  g.fillStyle = "#F4DFB8"; g.textAlign = "center"; g.textBaseline = "middle";
  g.shadowColor = "rgba(255,190,110,0.55)"; g.shadowBlur = H * 0.08;
  g.fillText(fit.lines[0], W / 2 + fit.size * 0.07, H / 2 + fit.size * 0.04);
  return c;
}

/* Room title painted on the shelf wall: the name, then a quiet count line. */
export function titleCanvas(name, sub, wM, hM, hue) {
  const W = Math.round(wM * PX_PER_M), H = Math.round(hM * PX_PER_M), { c, g } = canvas(W, H);
  const nameFit = fitText(g, name, { maxW: W * 0.96, max: Math.round(H * 0.6), min: Math.round(H * 0.3), weight: 800, family: HEAD, spacing: -0.01 });
  const subFit = fitText(g, sub, { maxW: W * 0.9, max: Math.round(H * 0.2), min: Math.round(H * 0.12), weight: 600, family: BODY, spacing: 0.12 });
  g.textAlign = "center"; g.textBaseline = "alphabetic";
  setFont(g, 800, nameFit.size, HEAD, -0.01);
  g.fillStyle = INK;
  g.fillText(nameFit.lines[0], W / 2, H * 0.62);
  setFont(g, 600, subFit.size, BODY, 0.12);
  g.fillStyle = topicColor(hue, 55, 34);
  g.fillText(subFit.lines[0].toUpperCase(), W / 2, H * 0.93);
  return c;
}

/* Shelf plaque: subtopic in caps, count in a coral roundel. */
export function plaqueCanvas(name, count, wM, hM, hue) {
  const W = Math.round(wM * 300), H = Math.round(hM * 300), { c, g } = canvas(W, H);
  roundRect(g, 0, 0, W, H, H * 0.18); g.fillStyle = "#211813"; g.fill();
  roundRect(g, 5, 5, W - 10, H - 10, H * 0.14); g.lineWidth = 2.5; g.strokeStyle = "rgba(233,190,120,0.6)"; g.stroke();
  g.fillStyle = topicColor(hue, 70, 58);
  roundRect(g, H * 0.32, H * 0.3, H * 0.1, H * 0.4, H * 0.05); g.fill();
  const dot = H * 0.36, label = String(count);
  const fit = fitText(g, name.toUpperCase(), { maxW: W - H * 0.62 - dot * 2 - H * 0.45, max: Math.round(H * 0.42), min: Math.round(H * 0.22), weight: 700, family: HEAD, spacing: 0.09 });
  g.fillStyle = "#F3E6D2"; g.textAlign = "left"; g.textBaseline = "middle";
  g.fillText(fit.lines[0], H * 0.62, H * 0.53);
  g.beginPath(); g.arc(W - H * 0.3 - dot, H / 2, dot, 0, Math.PI * 2); g.fillStyle = CORAL; g.fill();
  setFont(g, 800, Math.round(dot * (label.length > 2 ? 0.8 : 1.05)), HEAD);
  g.fillStyle = "#fff"; g.textAlign = "center";
  g.fillText(label, W - H * 0.3 - dot, H / 2 + dot * 0.06);
  return c;
}

/* ── Bookmark cards ── */

export const CARD_PX = { w: 512, h: 336 };

function badge(g, source, x, y, s) {
  const r = s * 0.24;
  if (source === "youtube") {
    roundRect(g, x, y + s * 0.12, s, s * 0.76, r); g.fillStyle = "#FF0033"; g.fill();
    g.beginPath(); g.moveTo(x + s * 0.4, y + s * 0.33); g.lineTo(x + s * 0.68, y + s * 0.5); g.lineTo(x + s * 0.4, y + s * 0.67); g.closePath(); g.fillStyle = "#fff"; g.fill();
    return;
  }
  if (source === "x") {
    roundRect(g, x, y, s, s, r); g.fillStyle = "#0F0F0F"; g.fill();
    g.strokeStyle = "#fff"; g.lineCap = "butt";
    g.lineWidth = s * 0.1;
    g.beginPath(); g.moveTo(x + s * 0.27, y + s * 0.24); g.lineTo(x + s * 0.73, y + s * 0.76); g.stroke();
    g.lineWidth = s * 0.06;
    g.beginPath(); g.moveTo(x + s * 0.72, y + s * 0.24); g.lineTo(x + s * 0.28, y + s * 0.76); g.stroke();
    return;
  }
  if (source === "reddit") {
    g.beginPath(); g.arc(x + s / 2, y + s / 2, s / 2, 0, Math.PI * 2); g.fillStyle = "#FF4500"; g.fill();
    g.fillStyle = "#fff";
    g.beginPath(); g.ellipse(x + s / 2, y + s * 0.6, s * 0.3, s * 0.2, 0, 0, Math.PI * 2); g.fill();
    g.beginPath(); g.arc(x + s * 0.68, y + s * 0.25, s * 0.07, 0, Math.PI * 2); g.fill();
    g.lineWidth = s * 0.045; g.strokeStyle = "#fff";
    g.beginPath(); g.moveTo(x + s * 0.5, y + s * 0.42); g.lineTo(x + s * 0.56, y + s * 0.24); g.lineTo(x + s * 0.66, y + s * 0.25); g.stroke();
    g.fillStyle = "#FF4500";
    g.beginPath(); g.arc(x + s * 0.4, y + s * 0.58, s * 0.05, 0, Math.PI * 2); g.arc(x + s * 0.6, y + s * 0.58, s * 0.05, 0, Math.PI * 2); g.fill();
    return;
  }
  if (source === "web") {
    g.beginPath(); g.arc(x + s / 2, y + s / 2, s / 2, 0, Math.PI * 2); g.fillStyle = "#2B211B"; g.fill();
    g.strokeStyle = "#F6E7D6"; g.lineWidth = s * 0.06;
    g.beginPath(); g.arc(x + s / 2, y + s / 2, s * 0.3, 0, Math.PI * 2); g.stroke();
    g.beginPath(); g.ellipse(x + s / 2, y + s / 2, s * 0.13, s * 0.3, 0, 0, Math.PI * 2); g.stroke();
    g.beginPath(); g.moveTo(x + s * 0.2, y + s / 2); g.lineTo(x + s * 0.8, y + s / 2); g.stroke();
    return;
  }
  roundRect(g, x, y, s, s, r); g.fillStyle = INK; g.fill();
  const short = { instagram: "IG", tiktok: "TT", threads: "@", pinterest: "P", grok: "GK" }[source] || "•";
  setFont(g, 800, s * 0.42, HEAD); g.fillStyle = "#fff"; g.textAlign = "center"; g.textBaseline = "middle";
  g.fillText(short, x + s / 2, y + s * 0.53);
}

export function drawCard(g, card) {
  const { w: W, h: H } = CARD_PX;
  g.clearRect(0, 0, W, H);
  const accent = topicColor(card.hue, 68, 54);
  roundRect(g, 0, 0, W, H, 30);
  const bg = g.createLinearGradient(0, 0, 0, H);
  bg.addColorStop(0, "#FBF8F2"); bg.addColorStop(1, "#F0E9DD");
  g.fillStyle = bg; g.fill();
  g.save(); roundRect(g, 0, 0, W, H, 30); g.clip();
  g.fillStyle = accent; g.fillRect(0, 0, 12, H);
  g.restore();
  const pad = 36;
  badge(g, card.source, pad, 30, 46);
  setFont(g, 600, 25, BODY);
  g.fillStyle = INK; g.textAlign = "left"; g.textBaseline = "middle";
  const label = card.sourceLabel;
  g.fillText(label, pad + 60, 54);
  const labelW = g.measureText(label).width;
  const metaFit = fitText(g, card.meta || "", { maxW: W - pad - (pad + 60 + labelW + 20), max: 22, min: 16, weight: 500, family: BODY });
  g.fillStyle = INK2; g.textAlign = "right";
  g.fillText(metaFit.lines[0] || "", W - pad, 54);
  const fit = fitText(g, card.title, { maxW: W - pad * 2, maxLines: 3, max: 42, min: 27, weight: 700, family: HEAD, maxH: 176, lineH: 1.1 });
  g.fillStyle = INK; g.textAlign = "left"; g.textBaseline = "top";
  setFont(g, 700, fit.size, HEAD, -0.012);
  fit.lines.forEach((ln, i) => g.fillText(ln, pad, 98 + i * fit.size * fit.lineH));
  const chip = `# ${card.shelf}`;
  const chipFit = fitText(g, chip, { maxW: W - pad * 2 - 60, max: 22, min: 15, weight: 600, family: BODY });
  const cw = g.measureText(chipFit.lines[0]).width + 28;
  roundRect(g, pad, H - 64, cw, 36, 18);
  g.fillStyle = topicColor(card.hue, 70, 93); g.fill();
  g.fillStyle = topicColor(card.hue, 60, 32); g.textBaseline = "middle"; g.textAlign = "left";
  g.fillText(chipFit.lines[0], pad + 14, H - 45);
  drawBookmark(g, W - pad - 12, H - 46, 30, CORAL);
}
