/* island-ui.js — the overlay. Every number on screen is read off the library;
   every string a bookmark supplies goes in as text, never as markup. */
const el = (id) => document.getElementById(id);
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

const ZONE_TINT = ["#e2703c", "#d6b25a", "#6fa88a", "#c98a5e", "#7fa8c4", "#b0894f", "#8fae5a", "#c9705f", "#8e92b8"];

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
export function fmtDate(ms) {
  if (ms == null) return "—";
  const d = new Date(ms);
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
}
const fmtMonth = (ms) => (ms == null ? "—" : `${MONTHS[new Date(ms).getUTCMonth()]} ${new Date(ms).getUTCFullYear()}`);

export class IslandUI {
  constructor({ atlas, layout, actions }) {
    this.atlas = atlas;
    this.layout = layout;
    this.actions = actions;
    this.rows = [];
    this.bound = [];
  }

  on(node, type, fn) { node.addEventListener(type, fn); this.bound.push([node, type, fn]); }

  build() {
    this.subtitle();
    this.zones();
    this.on(el("tour"), "click", () => this.actions.toggleTour());
    const seek = el("seek");
    this.on(seek, "input", () => this.actions.seek(Number(seek.value) / Number(seek.max)));
    this.on(el("card-close"), "click", () => this.actions.select(null));
    this.on(el("mine"), "click", () => this.actions.mine());
    this.on(el("log-toggle"), "click", () => {
      const b = el("log-toggle");
      b.setAttribute("aria-expanded", b.getAttribute("aria-expanded") === "true" ? "false" : "true");
    });
    /* The log is a sidebar on a laptop and half the screen on a phone, so it
       starts closed on a narrow viewport — and follows the viewport, rather
       than being decided once at load. Rotating a phone used to leave the
       list covering the island. */
    this.narrow = window.matchMedia("(max-width: 820px)");
    const fit = () => {
      if (document.activeElement === el("log-toggle")) return;   // the visitor chose
      el("log-toggle").setAttribute("aria-expanded", this.narrow.matches ? "false" : "true");
    };
    fit();
    this.onNarrow = fit;
    this.narrow.addEventListener("change", fit);
    return this;
  }

  destroy() {
    this.narrow?.removeEventListener("change", this.onNarrow);
    for (const [node, type, fn] of this.bound) node.removeEventListener(type, fn);
    this.bound = [];
    el("log-list").textContent = "";
    el("subtitle").textContent = "";
    el("log-sum").textContent = "";
    this.rows = [];
  }

  subtitle() {
    const host = el("subtitle");
    host.textContent = "";
    const badge = document.createElement("span");
    badge.className = "badge";
    const dot = document.createElement("i");
    badge.append(dot, document.createTextNode(this.atlas.label));
    const span = document.createElement("span");
    const r = this.atlas.range;
    const range = r ? `${fmtMonth(r.start)} – ${fmtMonth(r.end)}` : "no dates yet";
    span.textContent = `${this.atlas.total} saves · ${this.layout.zones.length} zones · ${range}`;
    host.append(badge, span);
    // Only MARKER_CAP bookmarks per zone become camps. Showing the library
    // total next to a sample of it, with nothing said, is a lie by omission.
    const drawn = this.layout.markers.length;
    if (drawn < this.atlas.total) {
      const note = document.createElement("span");
      note.className = "sub-note";
      note.textContent = `showing ${drawn} of ${this.atlas.total} camps`;
      note.title = "Each zone draws its oldest saves; the counts are the whole library.";
      host.append(note);
    }
    if (this.atlas.truncated) {
      const note = document.createElement("span");
      note.className = "sub-note";
      note.textContent = `first ${this.atlas.total} saves read`;
      note.title = "Your library is larger than one read; the oldest saves are mapped.";
      host.append(note);
    }
    el("log-sum").textContent = `${this.layout.zones.length} zones · ${this.atlas.total} saves`;
  }

  zones() {
    const list = el("log-list");
    list.textContent = "";
    this.rows = [];
    const max = Math.max(...this.layout.zones.map((z) => z.total), 1);
    this.layout.zones.forEach((zone, i) => {
      const li = document.createElement("li");
      const b = document.createElement("button");
      b.type = "button";
      b.className = "zone-row";
      const dot = document.createElement("span");
      dot.className = "dot";
      dot.style.color = ZONE_TINT[i % ZONE_TINT.length];
      dot.style.background = ZONE_TINT[i % ZONE_TINT.length];
      const box = document.createElement("span");
      const name = document.createElement("b");
      name.textContent = zone.name;
      const sub = document.createElement("small");
      sub.textContent = `${zone.place} · ${zone.biome}`;
      const bar = document.createElement("span");
      bar.className = "bar";
      bar.style.width = `${Math.round(22 + 78 * (zone.total / max))}%`;
      bar.style.color = ZONE_TINT[i % ZONE_TINT.length];
      box.append(name, sub, bar);
      const n = document.createElement("span");
      n.className = "n";
      n.textContent = String(zone.total);
      b.append(dot, box, n);
      this.on(b, "click", () => this.actions.flyToZone(zone));
      li.appendChild(b);
      list.appendChild(li);
      this.rows.push(b);
    });
  }

  setFocus(index) {
    this.rows.forEach((row, i) => row.classList.toggle("is-focus", i === index));
  }

  /* ── bookmark card ────────────────────────────────────────────────────── */
  showCard(marker) {
    if (!marker) { el("card").hidden = true; return; }
    const it = marker.item;
    const zone = this.layout.zones[marker.zone];
    el("card-zone").textContent = `${zone.place} · ${zone.biome}`;
    el("card-title").textContent = it.title;
    el("card-meta").textContent = `${it.sourceLabel} · ${it.meta}`;
    el("card-topic").textContent = zone.name;
    el("card-sub").textContent = marker.district;
    el("card-date").textContent = fmtDate(it.at);
    const link = el("card-link");
    if (it.hasLink) {
      link.href = it.url;
      link.hidden = false;
    } else {
      link.hidden = true;
      link.removeAttribute("href");
    }
    el("card").hidden = false;
  }

  showTip(marker, x, y) {
    const tip = el("tip");
    if (!marker) { tip.hidden = true; return; }
    tip.textContent = "";
    const b = document.createElement("b");
    b.textContent = marker.item.title;
    const s = document.createElement("small");
    s.textContent = `${marker.item.sourceLabel} · ${this.layout.zones[marker.zone].name}`;
    tip.append(b, s);
    tip.style.left = `${Math.round(x)}px`;
    tip.style.top = `${Math.round(y)}px`;
    tip.hidden = false;
  }

  /* ── transport ────────────────────────────────────────────────────────── */
  setTour({ playing, t, duration, label, detail }) {
    document.body.classList.toggle("is-touring", !!playing);
    el("tour-label").textContent = playing ? "Pause" : "Fly the tour";
    const btn = el("tour");
    // the accessible name has to track the state, or a screen reader offers
    // "Play the tour" on a button that will pause it
    btn.setAttribute("aria-label", playing ? "Pause the tour" : "Play the tour");
    btn.setAttribute("aria-pressed", playing ? "true" : "false");
    const frac = duration > 0 ? clamp01(t / duration) : 0;
    el("track-fill").style.width = `${(frac * 100).toFixed(2)}%`;
    const seek = el("seek");
    if (seek && document.activeElement !== seek) seek.value = String(Math.round(frac * Number(seek.max)));
    if (seek) seek.setAttribute("aria-valuetext", label ? `${label}, ${Math.round(t)} of ${Math.round(duration)} seconds` : `${Math.round(t)} seconds`);
    el("beat-label").textContent = label || "";
    el("beat-detail").textContent = detail || "";
  }

  setCompass(az) {
    const n = document.getElementById("needle");
    if (n) n.setAttribute("transform", `rotate(${(-az * 180 / Math.PI).toFixed(1)} 17 17)`);
  }

  /* ── the parchment inset ──────────────────────────────────────────────── */
  drawMiniMap(field, sample) {
    const cv = el("minimap");
    if (!cv) return;
    const ctx = cv.getContext("2d");
    const W = cv.width, H = cv.height, R = 1700;
    const img = ctx.createImageData(W, H);
    const tints = this.layout.zones.map((z, i) => {
      const c = ZONE_TINT[i % ZONE_TINT.length];
      return [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
    });
    for (let j = 0; j < H; j++) for (let i = 0; i < W; i++) {
      const x = ((i + 0.5) / W * 2 - 1) * R, z = ((j + 0.5) / H * 2 - 1) * R;
      const s = sample(x, z);
      const k = (j * W + i) * 4;
      let r, g, b, a = 255;
      if (s.h < 0.5) {
        const deep = Math.min(1, -s.h / 110);
        r = 18 + 10 * (1 - deep); g = 40 + 22 * (1 - deep); b = 46 + 20 * (1 - deep); a = 215;
      } else {
        const t = tints[s.zone] || [190, 170, 130];
        const relief = 0.52 + 0.5 * s.shade + Math.min(0.35, s.h / 900);
        r = Math.min(255, (58 + t[0] * 0.42) * relief);
        g = Math.min(255, (56 + t[1] * 0.42) * relief);
        b = Math.min(255, (44 + t[2] * 0.42) * relief);
        if (s.gap < 26) { r *= 1.3; g *= 1.22; b *= 1.0; }
      }
      img.data[k] = r; img.data[k + 1] = g; img.data[k + 2] = b; img.data[k + 3] = a;
    }
    ctx.putImageData(img, 0, 0);
    // markers as fine warm dots
    ctx.fillStyle = "rgba(255, 208, 150, .9)";
    for (const m of this.layout.markers) {
      const i = ((m.x / R) * 0.5 + 0.5) * W, j = ((m.z / R) * 0.5 + 0.5) * H;
      ctx.fillRect(i - 0.5, j - 0.5, 1.4, 1.4);
    }
    this.mapR = R;
  }

  setCamDot(x, z) {
    const dot = el("mm-cam"), cv = el("minimap");
    if (!dot || !cv || !this.mapR) return;
    const u = (x / this.mapR) * 0.5 + 0.5, v = (z / this.mapR) * 0.5 + 0.5;
    const inside = u > -0.1 && u < 1.1 && v > -0.1 && v < 1.1;
    dot.style.display = inside ? "" : "none";
    dot.style.transform = `translate(${(Math.max(0, Math.min(1, u)) * cv.clientWidth).toFixed(1)}px, ${(Math.max(0, Math.min(1, v)) * cv.clientHeight).toFixed(1)}px)`;
  }

  toast(text) {
    const t = document.createElement("div");
    t.className = "toast";
    t.setAttribute("role", "status");
    t.textContent = text;
    el("toast-host").appendChild(t);
    setTimeout(() => t.remove(), 4200);
  }
}
