/* bookmarker — Quick File's dial, on the web.
 *
 * One more tap after a save. Seven likely topics sit on a ring: the best guess
 * at twelve o'clock and in the middle, the next six clockwise, More… at half
 * past ten. The ring never turns. A coral bead runs round the rim to whichever
 * segment is highlighted, and whatever the middle shows is exactly what a tap
 * on it files. The scroll wheel, a trackpad, the arrow keys, J and K, or a
 * finger dragged round the ring turn it; a tap on a segment files that one;
 * 1–7 file by rank; 8 or / opens every topic; Esc keeps the guess.
 *
 *   QuickFileDial.mount(host, { ranking, topic, mode, onConfirm, onMore,
 *                               onLater, input })
 *     → { offer(r), turn(n), confirm(), focus(), destroy(), touched, highlighted }
 *
 *   ranking      FilingSuggest.rank()'s answer
 *   topic(id)    → { id, name, hue, art, subs? }; art is a URL, a list of URLs
 *                  to try in order, or null for a lettered disc
 *   mode         "sheet" (the Add dialog, the demo) or "triage"
 *   onConfirm(c, how)   c is a FilingCandidate (subcategory already refined
 *                       when a chip was used); how says which gesture filed it
 *   input        optional, the FilingInput the ranking came from; the reason
 *                line needs its URL to name a website
 *
 * Late answers (the preview, the model) arrive through offer(). A dial nobody
 * has touched crossfades to the new order; a touched one never moves under the
 * thumb and only badges the newcomer, or offers it as "Also likely". A tap on
 * the middle within 350 ms of a late change files what the middle showed
 * before it changed.
 *
 * Colours come from window.Palette, the port of the iPhone's CategoryPalette,
 * so a topic is the colour it is in the app. Plan 2 §A1 is the spec. Nothing
 * here touches the network; the only storage is a three-use counter for the
 * "Tap to file" hint. `quickfile:turn` and `quickfile:confirm` DOM events
 * fire on the host for anyone listening (the lab page's tick).
 */
"use strict";

const QuickFileDial = (() => {

  /* ── Geometry: a 200-unit dial centred on 0,0 ──────────────────────────
     The centre disc is 0.42 of the diameter, the ring runs from 0.235 of it to
     the edge (a unit inside, so a lifted segment stays on the canvas). Each
     segment is stroked in its own colour with round joins, which rounds its
     corners; the path is inset by that stroke so the drawn edge lands on these
     radii, and each radial edge is pushed sideways so the paper gap between
     neighbours is the same width from the inside to the outside. */
  const SLOTS = 8, MORE = 7, NOTCH = 45;
  const R = { outer: 99, inner: 47, hub: 42, evidence: 44.6, label: 73, bead: 105, round: 3, gap: 1.25 };
  const TAP_SLOP = 10;       // px: a press that travels less than this is a tap
  const HOVER_SLOP = 6;      // px of travel inside the ring before hover counts
  const HYSTERESIS = 4;      // degrees either side of a notch's midpoint (8° in all)
  const GUARD_MS = 350;      // a centre tap this soon after a late change files the old centre
  const SLIDE_MAX = 6;       // notches a second; faster than this the centre just swaps
  const WHEEL = { line: 40, page: 800, step: 50, lock: 110, lineLock: 40, idle: 160 };
  const USES = "bm.qf-uses"; // "Tap to file" shows for the first three filings
  const SVGNS = "http://www.w3.org/2000/svg";
  let serial = 0;

  const media = (q) => (typeof matchMedia === "function" ? matchMedia(q) : { matches: false });
  const reducedMQ = media("(prefers-reduced-motion: reduce)");
  const coarseMQ = media("(pointer: coarse)");
  const fineMQ = media("(hover: hover) and (pointer: fine)");

  const NEUTRAL = { tint: () => "#EEE8DE", deep: () => "#5B554D", solid: () => "#A39A8D" };
  const palette = () => (typeof Palette === "object" && Palette) || NEUTRAL;
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const rad = (deg) => (deg * Math.PI) / 180;
  const deg = (r) => (r * 180) / Math.PI;
  const at = (radius, angle) => [radius * Math.sin(rad(angle)), -radius * Math.cos(rad(angle))];
  const fmt = (n) => Math.round(n * 100) / 100;
  const now = () => (typeof performance === "object" ? performance.now() : Date.now());

  function uses() { try { return Number(localStorage.getItem(USES)) || 0; } catch { return 99; } }
  function bumpUses() { try { localStorage.setItem(USES, String(Math.min(99, uses() + 1))); } catch { /* a hint, nothing more */ } }

  /* ── Copy shared by every place the dial appears ── */
  const HEADER = {
    strong: { icon: "✨", text: "Sorted for you" },
    thin: { icon: "🤔", text: "Our best guess — turn to change" },
    none: { icon: "📂", text: "Where does this go?" },
    yours: { icon: "✅", text: "Filed by you" },
  };
  /** The header above the dial: DECISIONS' four filing states. */
  function header(ranking, { yours = false } = {}) {
    const state = yours ? "yours" : ranking && (ranking.evidence === "strong" || ranking.evidence === "thin") ? ranking.evidence : "none";
    return { state, ...HEADER[state] };
  }
  /** "Fitness › Running", or just "Fitness". */
  function label(c, topic) {
    const name = topic?.name || c?.categoryID || "";
    return c?.subcategory ? `${name} › ${c.subcategory}` : name;
  }
  /* How sure a candidate is, for the ring round the middle: the ranking's own
     evidence for its preselected first place, otherwise the same rule applied
     to that candidate alone — 14 points and a reason about the link itself is
     strong, any real evidence is thin, a starter or a habit alone is none. */
  const ABOUT_THE_LINK = new Set(["keyword", "hashtag", "creator", "domain", "ai"]);
  const EVIDENTIAL = new Set(["keyword", "hashtag", "ocr", "creator", "domain", "ai", "yours", "guess"]);
  function evidenceOf(c, slot, ranking) {
    if (!c) return "none";
    if (slot === 0 && ranking && ranking.preselect === 0) return ranking.evidence || "thin";
    const reasons = c.reasons || [];
    if ((c.score || 0) >= 14 && reasons.some((r) => ABOUT_THE_LINK.has(r))) return "strong";
    return reasons.some((r) => EVIDENTIAL.has(r)) ? "thin" : "none";
  }

  /* One annular sector, rounded, with a constant gap either side. */
  function segmentPath(slot) {
    const centre = slot * NOTCH, half = NOTCH / 2, push = R.gap + R.round;
    const ro = R.outer - R.round, ri = R.inner + R.round;
    const dO = deg(Math.asin(push / ro)), dI = deg(Math.asin(push / ri));
    const [x1, y1] = at(ro, centre - half + dO), [x2, y2] = at(ro, centre + half - dO);
    const [x3, y3] = at(ri, centre + half - dI), [x4, y4] = at(ri, centre - half + dI);
    return `M${fmt(x1)} ${fmt(y1)}A${ro} ${ro} 0 0 1 ${fmt(x2)} ${fmt(y2)}`
      + `L${fmt(x3)} ${fmt(y3)}A${ri} ${ri} 0 0 0 ${fmt(x4)} ${fmt(y4)}Z`;
  }
  /* Where a segment's label sits, as percentages of the dial. */
  function spot(radius, slot) {
    const [x, y] = at(radius, slot * NOTCH);
    return { left: `${fmt(50 + x / 2)}%`, top: `${fmt(50 + y / 2)}%` };
  }
  /* atan2 radians (screen: 0 at three o'clock, clockwise) → segment index. */
  function slotAt(angle) {
    const d = ((deg(angle) + 90) % 360 + 360) % 360;
    return Math.round(d / NOTCH) % SLOTS;
  }

  /* Art: every URL that ever failed is skipped from then on, and images are
     warmed up when a ranking arrives so turning never waits on a download. */
  const deadArt = new Set(), warmArt = new Set();
  const artList = (art) => (Array.isArray(art) ? art : art ? [art] : []).filter((u) => typeof u === "string" && u && !deadArt.has(u));
  function warm(art) {
    const url = artList(art)[0];
    if (!url || warmArt.has(url) || typeof Image !== "function") return;
    warmArt.add(url);
    const img = new Image();
    img.decoding = "async";
    img.onerror = () => { deadArt.add(url); warmArt.delete(url); };
    img.src = url;
  }

  const MAG = `<svg class="qf-mag" viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/></svg>`;
  const CHECK = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.6l4.6 4.6L19.2 7.6"/></svg>`;

  function template(id, mode) {
    let segs = "", labels = "", options = "";
    for (let s = 0; s < SLOTS; s++) {
      segs += `<path class="qf-seg${s === MORE ? " qf-seg-more" : ""}" data-slot="${s}" style="--i:${s}" d="${segmentPath(s)}"/>`;
      const p = spot(R.label, s);
      labels += `<span class="qf-lab${s === MORE ? " qf-lab-more" : ""}" data-slot="${s}" style="left:${p.left};top:${p.top};--i:${s}"></span>`;
      options += `<div class="qf-opt" role="option" id="${id}-o${s}" data-slot="${s}" aria-selected="false"></div>`;
    }
    return `<div class="qf" data-mode="${mode}">
  <div class="qf-dial">
    <svg class="qf-ring" viewBox="-100 -100 200 200" aria-hidden="true" focusable="false">
      <defs><radialGradient id="${id}-sheen" cx="32%" cy="18%" r="85%"><stop offset="0" stop-color="#fff" stop-opacity=".34"/><stop offset=".55" stop-color="#fff" stop-opacity="0"/></radialGradient></defs>
      <g class="qf-segs">${segs}</g>
      <circle class="qf-sheen" r="${R.outer}" fill="url(#${id}-sheen)"/>
      <circle class="qf-ev" r="${R.evidence}"/>
      <g class="qf-bead-arm"><circle class="qf-bead" cx="0" cy="${-R.bead}" r="3.4"/></g>
    </svg>
    <div class="qf-labels" aria-hidden="true">${labels}</div>
    <div class="qf-list" role="listbox" tabindex="0" id="${id}-list" aria-label="Where it goes" aria-describedby="${id}-help">${options}</div>
    <button type="button" class="qf-hub">
      <span class="qf-hub-in">
        <span class="qf-art"><i class="qf-ini" aria-hidden="true"></i><img alt="" draggable="false" decoding="async" hidden>${MAG}</span>
        <span class="qf-hub-name"></span>
        <span class="qf-hub-sub"></span>
        <span class="qf-hub-tip">Tap to file</span>
      </span>
      <span class="qf-hub-done" aria-hidden="true">${CHECK}<b>Filed</b></span>
    </button>
  </div>
  <p class="qf-reason"></p>
  <div class="qf-chips" role="group" aria-label="Or pick a subtopic"></div>
  <div class="qf-also-row"></div>
  <p class="qf-help" id="${id}-help"></p>
  <p class="qf-sr" aria-live="polite"></p>
</div>`;
  }

  function mount(host, opts = {}) {
    if (!host) throw new Error("QuickFileDial.mount needs a host element");
    const id = `qf${++serial}`;
    const mode = opts.mode === "triage" ? "triage" : "sheet";
    const topicOf = (cid) => { try { return (cid && opts.topic && opts.topic(cid)) || null; } catch { return null; } };
    const input = opts.input || null;

    let ranking = { candidates: [], preselect: null, evidence: "none" }, cands = [];
    let committed = null, hover = null, touched = false, filed = null, destroyed = false;
    let badge = null, also = null, guard = null, gesture = null, hoverFrom = null;
    let beadAngle = 0, lastSlide = 0, lastBuzz = 0;
    const wheel = { acc: 0, last: 0, lockUntil: 0 };
    const timers = new Set();
    const later = (fn, ms) => { const t = setTimeout(() => { timers.delete(t); if (!destroyed) fn(); }, ms); timers.add(t); };

    host.innerHTML = template(id, mode);
    const root = host.firstElementChild;
    const q = (sel) => root.querySelector(sel);
    const dial = q(".qf-dial"), list = q(".qf-list"), hub = q(".qf-hub"), hubIn = q(".qf-hub-in");
    const ring = q(".qf-ring"), labelsEl = q(".qf-labels"), ev = q(".qf-ev"), beadArm = q(".qf-bead-arm");
    const art = q(".qf-art"), artImg = art.querySelector("img"), ini = q(".qf-ini");
    const hubName = q(".qf-hub-name"), hubSub = q(".qf-hub-sub"), hubTip = q(".qf-hub-tip");
    const reasonEl = q(".qf-reason"), chipsEl = q(".qf-chips"), alsoEl = q(".qf-also-row");
    const helpEl = q(".qf-help"), liveEl = q(".qf-sr");
    const segs = [...root.querySelectorAll(".qf-seg")];
    const labels = [...root.querySelectorAll(".qf-lab")];
    const options = [...root.querySelectorAll(".qf-opt")];

    const showTip = uses() < 3;
    const reduced = () => reducedMQ.matches || !!root.closest(".qf-reduced");
    const isList = () => ring.getClientRects().length === 0;   // the narrow layout hides the ring
    const highlighted = () => (hover !== null ? hover : committed);
    const exists = (slot) => slot === MORE || !!cands[slot];
    const emit = (name, detail) => { try { host.dispatchEvent(new CustomEvent(name, { detail })); } catch { /* old browser */ } };
    const buzz = (ms) => {
      if (!coarseMQ.matches || typeof navigator !== "object" || !navigator.vibrate) return;
      if (navigator.userActivation && !navigator.userActivation.hasBeenActive) return;   // the browser refuses until a real tap
      const t = now();
      if (t - lastBuzz < 45) return;   // a fast spin ticks, it doesn't buzz
      lastBuzz = t;
      try { navigator.vibrate(ms); } catch { /* not allowed here */ }
    };
    const announce = (text) => { liveEl.textContent = ""; later(() => { liveEl.textContent = text; }, 30); };

    helpEl.textContent = fineMQ.matches
      ? "Scroll or ← → to turn · 1–7 files · ↵ files the middle"
      : "Turn the dial, or tap a topic · tap the middle to file";
    if (!fineMQ.matches) root.classList.add("qf-touch");

    /* ── Painting ── */
    function shown() {
      if (filed) return { kind: "filed", c: filed };
      const h = highlighted();
      if (h === null) return { kind: "none" };
      if (h === MORE) return { kind: "more" };
      return { kind: "cand", c: cands[h], slot: h };
    }
    const sameView = (a, b) => a && b && a.kind === b.kind
      && (a.kind !== "cand" || (a.c.categoryID === b.c.categoryID && (a.c.subcategory ?? null) === (b.c.subcategory ?? null)));

    function paintRing() {
      const P = palette();
      const count = cands.length;
      for (let s = 0; s < SLOTS; s++) {
        const seg = segs[s], lab = labels[s], opt = options[s];
        if (s === MORE) {
          lab.innerHTML = `${MAG}<b>More…</b>`;
          opt.setAttribute("aria-label", "More topics. Every topic, and the ones you made.");
          opt.innerHTML = `<span class="qf-opt-dot qf-opt-more">${MAG}</span><span class="qf-opt-t"><b>More topics</b><small>Every topic, and yours</small></span>`;
          continue;
        }
        const c = cands[s];
        seg.classList.toggle("is-empty", !c);
        opt.hidden = !c;
        if (!c) { lab.innerHTML = ""; opt.removeAttribute("aria-label"); opt.innerHTML = ""; continue; }
        const t = topicOf(c.categoryID) || { name: c.categoryID, hue: P.NEUTRAL_HUE ?? 40 };
        const hue = t.hue ?? 40;
        seg.style.setProperty("--qf-c", P.tint(hue));
        seg.style.setProperty("--qf-on", P.deep(hue));
        lab.style.setProperty("--qf-ink", P.deep(hue));
        const name = esc(t.name);
        lab.innerHTML = (c.subcategory
          ? `<small>${name}</small><b>${esc(c.subcategory)}</b>`
          : `<b class="qf-solo">${name}</b>`) + (badge === s ? `<i class="qf-badge" title="Also likely">✨</i>` : "");
        const why = reasonFor(c);
        opt.setAttribute("aria-label", `${t.name}${c.subcategory ? ", " + c.subcategory : ""}${why ? ". " + why : ""}. ${s + 1} of ${count}`);
        opt.innerHTML = `<span class="qf-opt-dot" style="background:${P.solid(hue)}"></span>`
          + `<span class="qf-opt-t"><b>${name}${c.subcategory ? ` <span>› ${esc(c.subcategory)}</span>` : ""}</b>${why ? `<small>${esc(why)}</small>` : ""}</span>`
          + (badge === s ? `<i class="qf-badge">✨</i>` : "");
        warm(t.art);
      }
    }

    function reasonFor(c) {
      try { return (typeof FilingSuggest === "object" && FilingSuggest.reasonLine(c, input || {})) || ""; }
      catch { return ""; }
    }

    function moveBead(slot, dir, instant) {
      const target = slot * NOTCH;
      let delta = ((target - beadAngle) % 360 + 360) % 360;   // clockwise distance, 0…359
      if (dir < 0 && delta > 0) delta -= 360;
      else if (dir === 0 && delta > 180) delta -= 360;
      beadAngle += delta;
      beadArm.classList.toggle("is-instant", !!instant);
      beadArm.style.transform = `rotate(${beadAngle}deg)`;
    }

    function setArt(t) {
      const urls = artList(t && t.art);
      art.classList.remove("is-more", "is-none");
      ini.textContent = t ? (t.name || "?").trim().charAt(0).toUpperCase() : "?";
      art.style.setProperty("--qf-art-bg", palette().tint(t ? t.hue ?? 40 : 40));
      if (!urls.length) { artImg.hidden = true; artImg.removeAttribute("src"); return; }
      artImg.dataset.chain = JSON.stringify(urls);
      if (artImg.getAttribute("src") !== urls[0]) artImg.src = urls[0];
      artImg.hidden = false;
    }
    artImg.addEventListener("error", () => {
      const failed = artImg.getAttribute("src");
      if (failed) deadArt.add(failed);
      let chain = [];
      try { chain = JSON.parse(artImg.dataset.chain || "[]"); } catch { chain = []; }
      const next = chain.find((u) => !deadArt.has(u));
      if (next) artImg.src = next; else { artImg.hidden = true; artImg.removeAttribute("src"); }
    });

    function paintHub(dir, animate) {
      const view = shown();
      const P = palette();
      hub.classList.toggle("is-more", view.kind === "more");
      hub.classList.toggle("is-none", view.kind === "none");
      ev.classList.remove("is-strong", "is-thin", "is-none");
      if (view.kind === "cand") {
        const t = topicOf(view.c.categoryID) || { name: view.c.categoryID, hue: 40 };
        setArt(t);
        hubName.textContent = t.name;
        hubName.classList.toggle("is-long", (t.name || "").length > 11);
        hubSub.textContent = view.c.subcategory || "";
        hubSub.hidden = !view.c.subcategory;
        hubTip.hidden = !showTip;
        const state = evidenceOf(view.c, view.slot, ranking);
        ev.classList.add(`is-${state}`);
        ev.style.stroke = state === "none" ? "" : P.solid(t.hue ?? 40);
        hub.setAttribute("aria-label", `File under ${label(view.c, t)}`);
      } else if (view.kind === "more") {
        art.classList.add("is-more"); artImg.hidden = true; ini.textContent = "";
        art.style.setProperty("--qf-art-bg", "var(--control, #EEE8DE)");
        hubName.textContent = "More topics"; hubName.classList.remove("is-long");
        hubSub.textContent = "Search them all"; hubSub.hidden = false; hubTip.hidden = true;
        ev.classList.add("is-none"); ev.style.stroke = "";
        hub.setAttribute("aria-label", "More topics");
      } else if (view.kind === "none") {
        art.classList.add("is-none"); artImg.hidden = true; ini.textContent = "?";
        art.style.setProperty("--qf-art-bg", "var(--paper, #F6F3EE)");
        hubName.textContent = "Turn to choose"; hubName.classList.remove("is-long");
        hubSub.textContent = ""; hubSub.hidden = true; hubTip.hidden = true;
        ev.classList.add("is-none"); ev.style.stroke = "";
        hub.setAttribute("aria-label", "Nothing picked yet. Open every topic");
      }
      if (!animate || typeof hubIn.animate !== "function") return;
      if (reduced()) { hubIn.animate([{ opacity: 0.25 }, { opacity: 1 }], { duration: 120, easing: "ease-out" }); return; }
      const t = now();
      if (dir && t - lastSlide >= 1000 / SLIDE_MAX) {
        hubIn.animate([{ transform: `translateX(${dir * 6}px)`, opacity: 0.35 }, { transform: "none", opacity: 1 }],
          { duration: 140, easing: "cubic-bezier(.2,.7,.2,1)" });
      }
      lastSlide = t;
    }

    function paintBelow() {
      const view = shown();
      chipsEl.innerHTML = ""; alsoEl.innerHTML = "";
      if (view.kind === "filed") {
        reasonEl.textContent = `Filed to ${label(view.c, topicOf(view.c.categoryID))}`;
        reasonEl.classList.add("is-filed");
        return;
      }
      reasonEl.classList.remove("is-filed");
      if (view.kind === "more") reasonEl.textContent = "Every topic, and the ones you made";
      else if (view.kind === "none") reasonEl.textContent = "";   // the middle already says "Turn to choose"
      else reasonEl.textContent = reasonFor(view.c);
      if (view.kind === "cand") {
        const c = view.c, t = topicOf(c.categoryID) || { name: c.categoryID, hue: 40, subs: [] };
        const P = palette(), hue = t.hue ?? 40;
        const subs = [];
        for (const s of [...(c.altSubs || []), ...(t.subs || [])]) {
          if (subs.length >= 3) break;
          if (s && s !== c.subcategory && !subs.includes(s)) subs.push(s);
        }
        chipsEl.innerHTML = subs.map((s) =>
          `<button type="button" class="qf-chip" data-sub="${esc(s)}" style="--qf-c:${P.tint(hue)};color:${P.deep(hue)}">${esc(s)}</button>`).join("")
          + (c.subcategory ? `<button type="button" class="qf-chip qf-chip-just" data-sub="">Just ${esc(t.name)}</button>` : "");
      }
      if (also) {
        const t = topicOf(also.categoryID);
        alsoEl.innerHTML = `<button type="button" class="qf-also"><i aria-hidden="true">✨</i> Also likely: <b>${esc(label(also, t))}</b></button>`;
      }
    }

    function paintHighlight(dir = 0, { animate = true, instant = false } = {}) {
      const h = highlighted();
      for (let s = 0; s < SLOTS; s++) {
        const on = s === h;
        segs[s].classList.toggle("is-on", on);
        labels[s].classList.toggle("is-on", on);
        options[s].setAttribute("aria-selected", String(on));
      }
      if (h === null) { list.removeAttribute("aria-activedescendant"); beadArm.classList.add("is-off"); }
      else { list.setAttribute("aria-activedescendant", options[h].id); beadArm.classList.remove("is-off"); moveBead(h, dir, instant); }
      paintHub(dir, animate);
      paintBelow();
    }

    function setRanking(r) {
      ranking = r && Array.isArray(r.candidates) ? r : { candidates: [], preselect: null, evidence: "none" };
      cands = ranking.candidates.slice(0, MORE);
      committed = ranking.preselect === 0 && cands[0] ? 0 : null;
      hover = null;
      paintRing();
    }

    /* ── Turning ── */
    function touch() {
      if (touched) return;
      touched = true;
      root.classList.add("is-touched");
    }
    function nextSlot(from, dir) {
      let s = from;
      for (let i = 0; i < SLOTS; i++) {
        s = s === null ? (dir > 0 ? 0 : MORE) : ((s + dir) % SLOTS + SLOTS) % SLOTS;
        if (exists(s)) return s;
      }
      return from;
    }
    function stepBy(n, how) {
      if (filed || !n) return;
      touch();
      const dir = n > 0 ? 1 : -1;
      const before = highlighted();
      let s = before;
      for (let i = 0; i < Math.abs(n); i++) s = nextSlot(s, dir);
      hover = null; hoverFrom = null; guard = null;
      committed = s;
      if (s === before) return;
      paintHighlight(dir);
      buzz(6);
      emit("quickfile:turn", { highlighted: s, how });
    }
    function jump(slot, how) {
      if (filed || slot === null || !exists(slot)) return;
      touch();
      const before = highlighted();
      hover = null; hoverFrom = null; guard = null;
      committed = slot;
      if (before === slot) return;
      paintHighlight(0);
      emit("quickfile:turn", { highlighted: slot, how });
    }
    function setHover(slot) {
      if (slot !== null && !exists(slot)) slot = null;
      if (slot === hover) return;
      const before = highlighted();
      hover = slot;
      if (slot !== null) touch();
      if (highlighted() === before) return;
      const d = before === null || highlighted() === null ? 0
        : (((highlighted() - before) % SLOTS) + SLOTS) % SLOTS <= 4 ? 1 : -1;
      paintHighlight(d);
      if (slot !== null) emit("quickfile:turn", { highlighted: slot, how: "hover" });
    }

    /* ── Filing ── */
    function more() {
      if (filed) return;
      touch();
      if (highlighted() !== MORE) { committed = MORE; hover = null; paintHighlight(0, { animate: false }); }
      opts.onMore?.();
    }
    function confirm(c, how) {
      if (filed || destroyed || !c) return;
      const t = topicOf(c.categoryID);
      filed = c; gesture = null; hover = null; guard = null;
      root.classList.add("is-filed");
      root.style.setProperty("--qf-filled", palette().deep(t?.hue ?? 40));
      if (reduced()) root.classList.add("is-instant");
      hub.setAttribute("aria-label", `Filed under ${label(c, t)}`);
      paintBelow();
      announce(`Filed under ${label(c, t)}. Press Z to undo.`);
      buzz(12);
      bumpUses();
      emit("quickfile:confirm", { candidate: c, how });
      opts.onConfirm?.(c, how);
    }
    function fileSlot(slot, how) {
      if (filed) return;
      if (slot === MORE) { more(); return; }
      const c = cands[slot];
      if (!c) return;
      if (committed !== slot || hover !== null) { committed = slot; hover = null; paintHighlight(0, { animate: false }); }
      confirm(c, how);
    }
    function fileMiddle(how, guarded) {
      if (filed) return;
      if (guarded && guard && now() - guard.at < GUARD_MS) {
        const before = guard.view;
        guard = null;
        if (before.kind === "cand") { confirm(before.c, how); return; }
        more();
        return;
      }
      const view = shown();
      if (view.kind === "cand") confirm(view.c, how); else more();
    }

    /* ── Late answers ── */
    function offer(r) {
      if (filed || destroyed || !r || !Array.isArray(r.candidates) || !r.candidates.length) return;
      const oldBest = cands[0], best = r.candidates[0];
      const sameBest = oldBest && best && oldBest.categoryID === best.categoryID
        && (oldBest.subcategory ?? null) === (best.subcategory ?? null);
      if (!touched) {
        const before = shown();
        badge = null; also = null;
        setRanking(r);
        const after = shown();
        if (!sameView(before, after)) guard = { at: now(), view: before };
        paintHighlight(0, { animate: false, instant: true });
        if (typeof labelsEl.animate === "function") {
          const fade = [{ opacity: 0.2 }, { opacity: 1 }];
          const timing = { duration: reduced() ? 120 : 160, easing: "ease-out" };
          labelsEl.animate(fade, timing);
          if (!sameView(before, after)) hubIn.animate(fade, timing);
        }
        if (after.kind === "cand" && !sameView(before, after)) {
          const t = topicOf(after.c.categoryID);
          announce(`Suggestion updated: ${t?.name || after.c.categoryID}${after.c.subcategory ? ", " + after.c.subcategory : ""}`);
        }
        return;
      }
      // Touched: nothing on the ring moves. The newcomer gets a badge where it
      // already sits, or a chip of its own underneath.
      if (!best || sameBest) return;
      const slot = cands.findIndex((c) => c.categoryID === best.categoryID);
      if (slot >= 0) { badge = slot; also = null; } else { badge = null; also = best; }
      paintRing();
      paintHighlight(0, { animate: false, instant: true });
      const t = topicOf(best.categoryID);
      announce(`Also likely: ${label(best, t)}`);
    }

    /* ── Input: pointer ── */
    function polar(e) {
      const b = dial.getBoundingClientRect();
      const dx = e.clientX - (b.left + b.width / 2), dy = e.clientY - (b.top + b.height / 2);
      return { r: (Math.hypot(dx, dy) * 200) / (b.width || 1), a: Math.atan2(dy, dx), x: e.clientX, y: e.clientY };
    }
    function press(slot, on) {
      const seg = segs[slot];
      if (seg) seg.classList.toggle("is-pressed", on);
    }
    list.addEventListener("pointerdown", (e) => {
      if (filed || e.button > 0 || isList()) return;
      const p = polar(e);
      if (p.r > R.outer + 2 || p.r < R.hub) return;
      if (e.pointerType === "mouse") { e.preventDefault(); list.focus({ preventScroll: true }); }
      touch();
      // The paper gap round the middle belongs to the middle: a tap there files
      // the centre, never a segment the finger only grazed.
      gesture = { id: e.pointerId, x: p.x, y: p.y, last: p.a, acc: 0, notches: 0, slot: p.r < R.inner ? null : slotAt(p.a), moved: false };
      try { list.setPointerCapture(e.pointerId); } catch { /* synthetic event */ }
      press(gesture.slot, true);
    });
    list.addEventListener("pointermove", (e) => {
      if (gesture && e.pointerId === gesture.id) {
        const g = gesture, p = polar(e);
        if (!g.moved && Math.hypot(p.x - g.x, p.y - g.y) >= TAP_SLOP) { g.moved = true; press(g.slot, false); }
        if (p.r < R.hub * 0.6) { g.last = p.a; return; }   // the middle is a dead zone: angles there are noise
        let d = p.a - g.last;
        if (d > Math.PI) d -= 2 * Math.PI; else if (d < -Math.PI) d += 2 * Math.PI;
        g.last = p.a;
        g.acc += d;
        if (!g.moved) return;
        const turned = deg(g.acc);
        while (turned > (g.notches + 0.5) * NOTCH + HYSTERESIS) { g.notches++; stepBy(1, "drag"); }
        while (turned < (g.notches - 0.5) * NOTCH - HYSTERESIS) { g.notches--; stepBy(-1, "drag"); }
        return;
      }
      if (e.pointerType !== "mouse" || filed || isList()) return;
      const p = polar(e);
      if (p.r < R.inner - 2 || p.r > R.outer + 2) { hoverFrom = null; setHover(null); return; }
      if (!hoverFrom) { hoverFrom = { x: p.x, y: p.y }; return; }
      if (hover === null && Math.hypot(p.x - hoverFrom.x, p.y - hoverFrom.y) < HOVER_SLOP) return;
      setHover(slotAt(p.a));
    });
    const endGesture = (e, cancelled) => {
      if (!gesture || e.pointerId !== gesture.id) return;
      const g = gesture;
      gesture = null;
      try { list.releasePointerCapture(e.pointerId); } catch { /* already released */ }
      press(g.slot, false);
      if (cancelled || g.moved) return;
      buzz(8);
      if (g.slot === null) fileMiddle("hub", true); else fileSlot(g.slot, "segment");
    };
    list.addEventListener("pointerup", (e) => endGesture(e, false));
    list.addEventListener("pointercancel", (e) => endGesture(e, true));
    list.addEventListener("pointerleave", (e) => { if (e.pointerType === "mouse" && !gesture) { hoverFrom = null; setHover(null); } });
    list.addEventListener("click", (e) => {   // the narrow list layout: rows are taps
      if (!isList() || filed) return;
      const opt = e.target.closest("[role=option]");
      if (opt) fileSlot(Number(opt.dataset.slot), "list");
    });
    hub.addEventListener("click", () => fileMiddle("hub", true));
    chipsEl.addEventListener("click", (e) => {
      const chip = e.target.closest("[data-sub]");
      const view = shown();
      if (!chip || view.kind !== "cand") return;
      touch();
      confirm({ ...view.c, subcategory: chip.dataset.sub || null }, "chip");
    });
    alsoEl.addEventListener("click", (e) => { if (e.target.closest(".qf-also") && also) { touch(); confirm(also, "also"); } });

    /* ── Input: wheel and trackpad (only while the pointer is over the dial) ── */
    dial.addEventListener("wheel", (e) => {
      if (filed || isList()) return;
      e.preventDefault();
      const t = now();
      if (t - wheel.last > WHEEL.idle) wheel.acc = 0;
      wheel.last = t;
      if (t < wheel.lockUntil) return;          // trackpad momentum after a notch
      const k = e.deltaMode === 1 ? WHEEL.line : e.deltaMode === 2 ? WHEEL.page : 1;
      const dx = e.deltaX * k, dy = e.deltaY * k;
      const d = Math.abs(dx) > Math.abs(dy) ? dx : dy;
      if (!d) return;
      if (e.deltaMode === 1) {                  // a mouse that counts in lines: one event, one notch
        wheel.acc = 0; wheel.lockUntil = t + WHEEL.lineLock;
        stepBy(d > 0 ? 1 : -1, "wheel");
        return;
      }
      wheel.acc += d;
      if (Math.abs(wheel.acc) < WHEEL.step) return;
      const dir = wheel.acc > 0 ? 1 : -1;
      wheel.acc = 0; wheel.lockUntil = t + WHEEL.lock;
      stepBy(dir, "wheel");
    }, { passive: false });

    /* ── Input: keys (focus on the dial) ── */
    list.addEventListener("keydown", (e) => {
      if (filed || e.metaKey || e.ctrlKey || e.altKey) return;
      const k = e.key;
      let handled = true;
      if (k === "ArrowRight" || k === "ArrowDown" || k === "j" || k === "J") stepBy(1, "key");
      else if (k === "ArrowLeft" || k === "ArrowUp" || k === "k" || k === "K") stepBy(-1, "key");
      else if (k === "Home") jump(cands[0] ? 0 : MORE, "key");
      else if (k === "End") jump(MORE, "key");
      else if (/^[1-7]$/.test(k)) { const s = Number(k) - 1; if (cands[s]) { touch(); fileSlot(s, "key"); } }
      else if (k === "8" || k === "/") more();
      else if (k === "Enter" || k === " ") fileMiddle("key", true);
      else if (k === "Escape") opts.onLater?.();
      else handled = false;                      // Z, S, Backspace and the rest belong to the page
      if (handled) e.preventDefault();
    });

    /* ── Go ── */
    setRanking(opts.ranking);
    root.classList.add("is-in");
    if (reduced()) root.classList.add("is-reduced-in");
    paintHighlight(0, { animate: false, instant: true });
    later(() => root.classList.remove("is-in", "is-reduced-in"), 700);

    return {
      offer,
      turn(n) { stepBy(Math.trunc(Number(n) || 0), "api"); },
      confirm() { fileMiddle("api", false); },
      focus() { try { list.focus({ preventScroll: true }); } catch { list.focus(); } },
      destroy() {
        if (destroyed) return;
        destroyed = true;
        for (const t of timers) clearTimeout(t);
        timers.clear();
        host.innerHTML = "";
      },
      get touched() { return touched; },
      get highlighted() { return highlighted(); },
    };
  }

  return Object.freeze({ mount, header, label, evidenceOf, HEADER, SLOTS, MORE });
})();

if (typeof globalThis === "object") globalThis.QuickFileDial = QuickFileDial;
if (typeof module === "object" && module.exports) module.exports = { QuickFileDial };
