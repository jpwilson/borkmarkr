/* bookmarker — Quick File's dial, on the web.
 *
 * One more tap after a save. Seven likely topics sit on a ring: the best guess
 * at twelve o'clock and in the middle, the next six clockwise, More… at half
 * past ten. The ring never turns. The highlighted slab fills with its topic's
 * deep colour and lifts, and whatever the middle shows is exactly what a tap
 * on it files. The scroll wheel, a trackpad, the arrow keys, J and K, or a
 * finger dragged round the ring turn it; a tap on a segment files that one;
 * 1–7 file by rank; 8 or / opens every topic; Esc keeps the guess.
 *
 *   QuickFileDial.mount(host, { ranking, topic, mode, onConfirm, onMore,
 *                               onLater, input, refine, chosen })
 *     → { offer(r), turn(n), confirm(), focus(), destroy(), touched, highlighted,
 *         choose(c, how), setSub(sub), suggestedSubs(id), chosen }
 *
 *   ranking      FilingSuggest.rank()'s answer
 *   topic(id)    → { id, name, hue, art, subs? }; art is a URL, a list of URLs
 *                  to try in order, or null for a lettered disc
 *   mode         "sheet" (the Add dialog, the demo) or "triage"
 *   onConfirm(c, how)   c is a FilingCandidate (subcategory already refined
 *                       when a chip was used); how says which gesture filed it
 *   input        optional, the FilingInput the ranking came from; the reason
 *                line needs its URL to name a website
 *   refine       the Add sheet's "pick, refine, done": a tap chooses and the
 *                ring stays live, so another topic re-chooses and the host's
 *                panel sets the subtopic. Off (triage, the lab) a tap files
 *                and the ring folds, exactly as before.
 *   chosen       refine only: a candidate that is already yours (a re-save of
 *                a bork you filed). The dial opens chosen, and says nothing.
 *
 * Late answers (the preview, the model) arrive through offer(). A dial nobody
 * has touched crossfades to the new order; a touched one never moves under the
 * thumb and only badges the newcomer, or offers it as "Also likely". A tap on
 * the middle within 350 ms of a late change files what the middle showed
 * before it changed.
 *
 * Colours come from window.Palette, the port of the iPhone's CategoryPalette,
 * so a topic is the colour it is in the app; a topic with no hue is Sand
 * (Palette.neutral). The look is "Quiet clay" direction B (design/SYSTEM.md,
 * B-QuickFile.dc.html): clay-tint slabs each carrying the topic's art, the lit
 * slab in its deep colour and lifted, a raised white hub with the art and a
 * deep check badge. Nothing
 * here touches the network; the only storage is a three-use counter for the
 * "Tap to file" hint. `quickfile:turn` and `quickfile:confirm` DOM events
 * fire on the host for anyone listening (the lab page's tick).
 */
"use strict";

const QuickFileDial = (() => {

  /* ── Geometry: a 200-unit dial centred on 0,0 ──────────────────────────
     Direction B's 360 px wheel, scaled by 100/180: slabs from r 76 to r 168
     (42.2 → 93.3), a 132 px hub (36.7), corners of 9 (5), a 7 px paper gap
     (half of it, 1.95, either side). Each slab is stroked in its own colour
     with round joins, which rounds its corners; the path is inset by that
     stroke so the drawn edge lands on these radii, and each radial edge is
     pushed sideways so the gap is the same width from the inside out. Labels
     sit on an ellipse (117 across, 124 up and down) as B's do, and the lit
     slab rises 5 px (2.8). */
  const SLOTS = 8, MORE = 7, NOTCH = 45;
  const R = { outer: 93.3, inner: 42.2, hub: 36.7, evidence: 39.6, labelX: 65, labelY: 68.9, round: 5, gap: 1.95 };
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

  /* A topic's { tint, mid, deep }; no hue (an unknown or unfiled topic) is Sand. */
  const colours = (hue) => (hue === null || hue === undefined || hue === "" || !Number.isFinite(Number(hue))
    ? Palette.neutral : Palette.of(Number(hue)));
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
  /* Each state's icon is an inline stroke SVG (never an emoji), drawn in
     currentColor so it takes the header's colour. Hosts set it as markup. */
  const ico = (size, body) => `<svg class="qf-ico" width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">${body}</svg>`;
  const ICON = {
    spark: '<path d="M12 3.5l1.8 5 5 1.8-5 1.8-1.8 5-1.8-5-5-1.8 5-1.8z"/><path d="M18.5 15.5v4M16.5 17.5h4"/>',
    guess: '<circle cx="12" cy="12" r="8.5"/><path d="M9.7 9.6a2.4 2.4 0 1 1 3.3 2.2c-.6.3-1 .8-1 1.4v.4"/><path d="M12 16.5v.2"/>',
    folder: '<path d="M3.5 7.5a2 2 0 0 1 2-2h3.8l2 2h7.2a2 2 0 0 1 2 2v7.5a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>',
    check: '<circle cx="12" cy="12" r="8.5"/><path d="M8.3 12.3l2.5 2.5 5-5.2"/>',
  };
  const HEADER = {
    strong: { icon: ico(16, ICON.spark), text: "Sorted for you" },
    thin: { icon: ico(16, ICON.guess), text: "Our best guess — turn to change" },
    none: { icon: ico(16, ICON.folder), text: "Where does this go?" },
    yours: { icon: ico(16, ICON.check), text: "Filed by you" },
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
  /* Where a slab's label sits, as percentages of the dial. */
  function spot(slot) {
    const a = rad(slot * NOTCH);
    const x = R.labelX * Math.sin(a), y = -R.labelY * Math.cos(a);
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

  const MAG = `<svg class="qf-mag" viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="M16 16l4 4"/></svg>`;
  const CHECK = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5.5 12.5l4 4L18.5 7.5"/></svg>`;
  const initial = (name) => esc((String(name || "?").trim().charAt(0) || "?").toUpperCase());
  /* A slab's 36 px art disc: the topic's clay art, or its letter when it has
     none (or every picture failed; see the error listener in mount). */
  function disc(t) {
    const urls = artList(t && t.art);
    if (!urls.length) return `<i class="qf-disc qf-disc-ini">${initial(t && t.name)}</i>`;
    return `<img class="qf-disc" alt="" draggable="false" decoding="async" src="${esc(urls[0])}" data-chain="${esc(JSON.stringify(urls))}" data-ini="${initial(t && t.name)}">`;
  }

  function template(id, mode) {
    let segs = "", labels = "", options = "";
    for (let s = 0; s < SLOTS; s++) {
      segs += `<path class="qf-seg${s === MORE ? " qf-seg-more" : ""}" data-slot="${s}" style="--i:${s}" d="${segmentPath(s)}"/>`;
      const p = spot(s);
      labels += `<span class="qf-lab${s === MORE ? " qf-lab-more" : ""}" data-slot="${s}" style="left:${p.left};top:${p.top};--i:${s}"></span>`;
      options += `<div class="qf-opt" role="option" id="${id}-o${s}" data-slot="${s}" aria-selected="false"></div>`;
    }
    // B's three SVG filters, in dial units: the warm drop under the resting
    // ring, the 1.5 px white top edge on every slab, and the lit slab's own
    // drop in its deep colour (--qf-lit, set on .qf as the highlight moves).
    const box = `filterUnits="userSpaceOnUse" x="-115" y="-115" width="230" height="240"`;
    const edge = `<feOffset in="SourceAlpha" dy=".83" result="o"/><feComposite in="SourceAlpha" in2="o" operator="out" result="edge"/>`
      + `<feFlood flood-color="#fff" flood-opacity=".7"/><feComposite in2="edge" operator="in" result="hl"/>`;
    return `<div class="qf" data-mode="${mode}" style="--qf-rest-f:url(#${id}-rest);--qf-edge-f:url(#${id}-edge);--qf-lit-f:url(#${id}-lit)">
  <div class="qf-dial">
    <svg class="qf-ring" viewBox="-100 -100 200 200" aria-hidden="true" focusable="false">
      <defs>
        <filter id="${id}-rest" ${box}><feDropShadow dx="0" dy="4.44" stdDeviation="5" flood-color="#785432" flood-opacity=".16"/></filter>
        <filter id="${id}-edge" ${box}>${edge}<feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="hl"/></feMerge></filter>
        <filter id="${id}-lit" ${box}>${edge}<feMerge result="lit"><feMergeNode in="SourceGraphic"/><feMergeNode in="hl"/></feMerge>
          <feDropShadow in="lit" class="qf-lit-drop" dx="0" dy="4.44" stdDeviation="3.9" flood-opacity=".28"/></filter>
      </defs>
      <g class="qf-segs">${segs}</g>
      <circle class="qf-ev" r="${R.evidence}"/>
    </svg>
    <div class="qf-labels" aria-hidden="true">${labels}</div>
    <div class="qf-list" role="listbox" tabindex="0" id="${id}-list" aria-label="Where it goes" aria-describedby="${id}-help">${options}</div>
    <button type="button" class="qf-hub">
      <span class="qf-hub-in">
        <span class="qf-art"><i class="qf-ini" aria-hidden="true"></i><img alt="" draggable="false" decoding="async" hidden>${MAG}</span>
        <span class="qf-hub-tip">Tap to file</span>
        <span class="qf-hub-name"></span>
        <span class="qf-hub-sub"></span>
      </span>
      <span class="qf-hub-done" aria-hidden="true">${CHECK}<b>Filed</b></span>
    </button>
    <span class="qf-hub-check" aria-hidden="true" hidden>${CHECK}</span>
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
    // `chosen` is what was filed. Without refine that ends the dial (folded);
    // with it the ring stays live and a later tap re-chooses.
    const refine = !!opts.refine;
    let committed = null, hover = null, touched = false, chosen = null, destroyed = false;
    let latest = null;   // the newest ranking offered, after a choice too
    const folded = () => !!chosen && !refine;
    let badge = null, also = null, guard = null, gesture = null, hoverFrom = null;
    let lastSlide = 0, lastBuzz = 0;
    const wheel = { acc: 0, last: 0, lockUntil: 0 };
    const timers = new Set();
    const later = (fn, ms) => { const t = setTimeout(() => { timers.delete(t); if (!destroyed) fn(); }, ms); timers.add(t); };

    host.innerHTML = template(id, mode);
    const root = host.firstElementChild;
    const q = (sel) => root.querySelector(sel);
    const dial = q(".qf-dial"), list = q(".qf-list"), hub = q(".qf-hub"), hubIn = q(".qf-hub-in");
    const ring = q(".qf-ring"), labelsEl = q(".qf-labels"), ev = q(".qf-ev");
    const art = q(".qf-art"), artImg = art.querySelector("img"), ini = q(".qf-ini"), hubCheck = q(".qf-hub-check");
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
      if (folded()) return { kind: "filed", c: chosen };
      const h = highlighted();
      // Chosen: the middle shows the choice unless you are pointing at
      // another topic, which a tap would choose instead.
      if (chosen && (h === null || (h !== MORE && cands[h]?.categoryID === chosen.categoryID))) return { kind: "chosen", c: chosen, slot: h };
      if (h === null) return { kind: "none" };
      if (h === MORE) return { kind: "more" };
      return { kind: "cand", c: cands[h], slot: h };
    }
    const sameView = (a, b) => a && b && a.kind === b.kind
      && (a.kind !== "cand" || (a.c.categoryID === b.c.categoryID && (a.c.subcategory ?? null) === (b.c.subcategory ?? null)));

    function paintRing() {
      const count = cands.length;
      for (let s = 0; s < SLOTS; s++) {
        const seg = segs[s], lab = labels[s], opt = options[s];
        if (s === MORE) {
          const sand = Palette.neutral;
          seg.style.setProperty("--qf-on", sand.deep);
          lab.style.setProperty("--qf-ink", sand.deep);
          lab.innerHTML = `<span class="qf-disc qf-disc-more">${MAG}</span><small>All topics</small><b>More…</b>`;
          opt.setAttribute("aria-label", "More topics. Every topic, and the ones you made.");
          opt.innerHTML = `<span class="qf-opt-dot qf-opt-more">${MAG}</span><span class="qf-opt-t"><b>More topics</b><small>Every topic, and yours</small></span>`;
          continue;
        }
        const c = cands[s];
        seg.classList.toggle("is-empty", !c);
        opt.hidden = !c;
        if (!c) { lab.innerHTML = ""; opt.removeAttribute("aria-label"); opt.innerHTML = ""; continue; }
        const t = topicOf(c.categoryID) || { name: c.categoryID, hue: null };
        const pal = colours(t.hue);
        seg.style.setProperty("--qf-c", pal.tint);
        seg.style.setProperty("--qf-on", pal.deep);
        lab.style.setProperty("--qf-ink", pal.deep);
        const name = esc(t.name);
        const big = c.subcategory || t.name || "";
        lab.classList.toggle("is-long", big.length > 13);
        lab.innerHTML = disc(t) + (c.subcategory
          ? `<small>${name}</small><b>${esc(c.subcategory)}</b>`
          : `<b class="qf-solo">${name}</b>`) + (badge === s ? `<i class="qf-badge" title="Also likely">${ico(12, ICON.spark)}</i>` : "");
        const why = reasonFor(c);
        opt.setAttribute("aria-label", `${t.name}${c.subcategory ? ", " + c.subcategory : ""}${why ? ". " + why : ""}. ${s + 1} of ${count}`);
        opt.innerHTML = `<span class="qf-opt-dot" style="background:${pal.mid}"></span>`
          + `<span class="qf-opt-t"><b>${name}${c.subcategory ? ` <span>› ${esc(c.subcategory)}</span>` : ""}</b>${why ? `<small>${esc(why)}</small>` : ""}</span>`
          + (badge === s ? `<i class="qf-badge">${ico(12, ICON.spark)}</i>` : "");
        warm(t.art);
      }
    }

    function reasonFor(c) {
      try { return (typeof FilingSuggest === "object" && FilingSuggest.reasonLine(c, input || {})) || ""; }
      catch { return ""; }
    }

    function setArt(t) {
      const urls = artList(t && t.art);
      art.classList.remove("is-more", "is-none");
      ini.textContent = t ? (t.name || "?").trim().charAt(0).toUpperCase() : "?";
      const pal = colours(t ? t.hue : null);
      art.style.setProperty("--qf-art-bg", pal.tint);
      art.style.setProperty("--qf-art-ink", pal.deep);
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

    /* A slab's picture that fails tries the next in its list, then becomes
       the topic's letter. (error doesn't bubble; capture sees it.) */
    labelsEl.addEventListener("error", (e) => {
      const img = e.target;
      if (!(img instanceof Element) || !img.classList.contains("qf-disc")) return;
      const failed = img.getAttribute("src");
      if (failed) deadArt.add(failed);
      let chain = [];
      try { chain = JSON.parse(img.dataset.chain || "[]"); } catch { chain = []; }
      const next = chain.find((u) => !deadArt.has(u));
      if (next) { img.src = next; return; }
      const i = document.createElement("i");
      i.className = "qf-disc qf-disc-ini";
      i.textContent = img.dataset.ini || "?";
      img.replaceWith(i);
    }, true);

    /* The middle shows the topic's art. Its name shows only when no slab is
       lit (a pick from More… that isn't on the ring, or nothing yet): a lit
       slab already says it. */
    function paintHub(dir, animate) {
      const view = shown();
      const lit = highlighted() !== null && !folded();
      hub.classList.toggle("is-more", view.kind === "more");
      hub.classList.toggle("is-none", view.kind === "none");
      ev.classList.remove("is-strong", "is-thin", "is-none");
      hubCheck.hidden = view.kind !== "chosen";
      if (view.kind === "cand" || view.kind === "chosen") {
        const t = topicOf(view.c.categoryID) || { name: view.c.categoryID, hue: null };
        const pal = colours(t.hue);
        setArt(t);
        hub.classList.toggle("is-named", !lit);
        hubName.textContent = t.name;
        hubName.classList.toggle("is-long", (t.name || "").length > 11);
        hubSub.textContent = view.c.subcategory || "";
        hubSub.hidden = !view.c.subcategory;
        hubTip.hidden = !showTip || view.kind === "chosen";
        hubCheck.style.setProperty("--qf-check", pal.deep);
        const state = evidenceOf(view.c, view.slot, ranking);
        ev.classList.add(`is-${state}`);
        ev.style.stroke = state === "none" ? "" : pal.mid;
        hub.setAttribute("aria-label", `${view.kind === "chosen" ? "Filed under" : "File under"} ${label(view.c, t)}`);
      } else if (view.kind === "more") {
        art.classList.add("is-more"); artImg.hidden = true; ini.textContent = "";
        art.style.setProperty("--qf-art-bg", "var(--sand, #ECE5D8)");
        art.style.setProperty("--qf-art-ink", "var(--sand-ink, #5A4E38)");
        hub.classList.remove("is-named");
        hubName.textContent = "More topics"; hubName.classList.remove("is-long");
        hubSub.textContent = "Search them all"; hubSub.hidden = false; hubTip.hidden = true;
        ev.classList.add("is-none"); ev.style.stroke = "";
        hub.setAttribute("aria-label", "More topics");
      } else if (view.kind === "none") {
        art.classList.add("is-none"); artImg.hidden = true; ini.textContent = "?";
        art.style.setProperty("--qf-art-bg", "var(--paper, #F6F3EE)");
        art.style.setProperty("--qf-art-ink", "var(--meta, #6E655A)");
        hub.classList.add("is-named");
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
      if (chosen) { reasonEl.textContent = ""; return; }   // the host's panel says where it went
      if (view.kind === "more") reasonEl.textContent = "Every topic, and the ones you made";
      else if (view.kind === "none") reasonEl.textContent = "";   // the middle already says "Turn to choose"
      else reasonEl.textContent = reasonFor(view.c);
      if (view.kind === "cand") {
        const c = view.c, t = topicOf(c.categoryID) || { name: c.categoryID, hue: null, subs: [] };
        const pal = colours(t.hue);
        const subs = [];
        for (const s of [...(c.altSubs || []), ...(t.subs || [])]) {
          if (subs.length >= 3) break;
          if (s && s !== c.subcategory && !subs.includes(s)) subs.push(s);
        }
        chipsEl.innerHTML = subs.map((s) =>
          `<button type="button" class="qf-chip" data-sub="${esc(s)}" style="--qf-c:${pal.tint};--qf-on:${pal.deep};color:${pal.deep}">${esc(s)}</button>`).join("")
          + (c.subcategory ? `<button type="button" class="qf-chip qf-chip-just" data-sub="">Just ${esc(t.name)}</button>` : "");
      }
      if (also) {
        const t = topicOf(also.categoryID);
        alsoEl.innerHTML = `<button type="button" class="qf-also"><i aria-hidden="true">${ico(14, ICON.spark)}</i> Also likely: <b>${esc(label(also, t))}</b></button>`;
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
      if (h === null) list.removeAttribute("aria-activedescendant");
      else {
        list.setAttribute("aria-activedescendant", options[h].id);
        root.style.setProperty("--qf-lit", segs[h].style.getPropertyValue("--qf-on") || Palette.neutral.deep);
      }
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
      if (folded() || !n) return;
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
      if (folded() || slot === null || !exists(slot)) return;
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
      if (folded()) return;
      touch();
      if (highlighted() !== MORE) { committed = MORE; hover = null; paintHighlight(0, { animate: false }); }
      opts.onMore?.();
    }
    function confirm(c, how) {
      if (folded() || destroyed || !c) return;
      if (refine) { choose(c, how); return; }
      const t = topicOf(c.categoryID);
      chosen = c; gesture = null; hover = null; guard = null;
      root.classList.add("is-filed");
      root.style.setProperty("--qf-filled", colours(t ? t.hue : null).deep);
      if (reduced()) root.classList.add("is-instant");
      hub.setAttribute("aria-label", `Filed under ${label(c, t)}`);
      paintBelow();
      announce(`Filed under ${label(c, t)}. Press Z to undo.`);
      buzz(12);
      bumpUses();
      emit("quickfile:confirm", { candidate: c, how });
      opts.onConfirm?.(c, how);
    }
    /* Refine: written at once and nothing folds. The same topic and subtopic
       again is nothing; the ring's highlight goes to the chosen topic, or
       nowhere for a More… or "Also likely" pick that isn't on it. */
    function choose(c, how) {
      if (destroyed || !c) return;
      if (chosen && chosen.categoryID === c.categoryID && (chosen.subcategory ?? null) === (c.subcategory ?? null)) return;
      const first = !chosen, t = topicOf(c.categoryID);
      chosen = c; gesture = null; hover = null; guard = null; also = null;
      const slot = cands.findIndex((x) => x.categoryID === c.categoryID);
      committed = slot >= 0 ? slot : null;
      root.classList.add("is-chosen");
      paintHighlight(0, { animate: false });
      announce(`Filed under ${label(c, t)}. Subtopics and tags below.`);
      buzz(first ? 12 : 6);
      if (first) bumpUses();
      emit("quickfile:confirm", { candidate: c, how });
      opts.onConfirm?.(c, how);
    }
    /* Refine: a subtopic chip under the dial. The chosen one again clears it. */
    function setSub(sub) {
      if (!refine || !chosen) return;
      const next = sub && sub !== chosen.subcategory ? sub : null;
      choose({ ...chosen, subcategory: next }, "sub");
    }
    /* The subtopics the ring suggested for a topic, then any a later answer
       adds. Never reordered, so chips drawn from it don't jump. */
    const subMemo = new Map();
    function suggestedSubs(topicID) {
      const out = subMemo.get(topicID) || [];
      const add = (x) => { if (x && !out.some((y) => y.toLowerCase() === x.toLowerCase())) out.push(x); };
      for (const r of [ranking, latest]) {
        const c = r?.candidates?.find((x) => x.categoryID === topicID);
        if (c) { add(c.subcategory); (c.altSubs || []).forEach(add); }
      }
      subMemo.set(topicID, out);
      return out.slice();
    }
    function fileSlot(slot, how) {
      if (folded()) return;
      if (slot === MORE) { more(); return; }
      const c = cands[slot];
      if (!c) return;
      // The chosen topic's own segment keeps the subtopic a chip set.
      if (chosen && c.categoryID === chosen.categoryID) {
        if (committed !== slot || hover !== null) { committed = slot; hover = null; paintHighlight(0, { animate: false }); }
        return;
      }
      if (committed !== slot || hover !== null) { committed = slot; hover = null; paintHighlight(0, { animate: false }); }
      confirm(c, how);
    }
    function fileMiddle(how, guarded) {
      if (folded()) return;
      if (guarded && guard && now() - guard.at < GUARD_MS) {
        const before = guard.view;
        guard = null;
        if (before.kind === "cand") { confirm(before.c, how); return; }
        more();
        return;
      }
      const view = shown();
      if (view.kind === "chosen") return;   // what it already is
      if (view.kind === "cand") confirm(view.c, how); else more();
    }

    /* ── Late answers ── */
    function offer(r) {
      if (folded() || destroyed || !r || !Array.isArray(r.candidates) || !r.candidates.length) return;
      latest = r;
      const oldBest = cands[0], best = r.candidates[0];
      // Chosen: a late answer never moves the choice. A topic it prefers that
      // is on the ring gets the badge; the host takes its subtopics and tags.
      if (chosen) {
        const slot = best ? cands.findIndex((c) => c.categoryID === best.categoryID) : -1;
        const next = slot >= 0 && best.categoryID !== chosen.categoryID ? slot : null;
        if (next === badge) return;
        badge = next;
        paintRing();
        paintHighlight(0, { animate: false, instant: true });
        return;
      }
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
      if (folded() || e.button > 0 || isList()) return;
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
      if (e.pointerType !== "mouse" || folded() || isList()) return;
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
      if (!isList() || folded()) return;
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
      if (folded() || isList()) return;
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
      if (folded() || e.metaKey || e.ctrlKey || e.altKey) return;
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
    if (refine && opts.chosen && opts.chosen.categoryID) {
      chosen = opts.chosen;
      const slot = cands.findIndex((x) => x.categoryID === chosen.categoryID);
      committed = slot >= 0 ? slot : null;
      root.classList.add("is-chosen");
    }
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
      choose(c, how) { if (refine) choose(c, how || "api"); else confirm(c, how || "api"); },
      setSub,
      suggestedSubs,
      get touched() { return touched; },
      get highlighted() { return highlighted(); },
      get chosen() { return chosen; },
    };
  }

  /* ── The refine panel's order (Core/QuickFile/QuickFileRefine.swift) ──
     Pure, and checked against the iPhone by Scripts/test_quick_file_refine.mjs
     over the shared fixture. */
  const key = (x) => String(x ?? "").trim().toLowerCase();
  const siteName = (t) => { try { return typeof Filer === "object" && !!Filer && Filer.isSiteName(t); } catch { return false; } };
  /** Subtopic chips: the suggested ones (only names in `all`, spelt as `all`
      spells them), then your most-used, then the rest of `all` in its order. */
  function subtopicChips(all, suggested = [], used = []) {
    const canon = new Map();
    for (const name of all || []) if (key(name) && !canon.has(key(name))) canon.set(key(name), name);
    const out = [], seen = new Set();
    for (const name of [...(suggested || []), ...(used || []), ...(all || [])]) {
      const k = key(name);
      if (!canon.has(k) || seen.has(k)) continue;
      seen.add(k);
      out.push(canon.get(k));
    }
    return out;
  }
  /** Tag chips, lowercased, each once: tags already on it that nothing
      offers (typed, or there before), then this link's suggestions, then
      your recent ones. A site name is never offered; one you have stays. */
  function tagChips(chosen = [], suggested = [], recent = []) {
    const on = new Set((chosen || []).map(key).filter(Boolean));
    const offered = [...(suggested || []), ...(recent || [])].map(key).filter((t) => t && !siteName(t));
    const offeredSet = new Set(offered);
    const own = (chosen || []).map(key).filter((t) => t && !offeredSet.has(t));
    const out = [], seen = new Set();
    for (const tag of [...own, ...offered]) {
      if (seen.has(tag)) continue;
      seen.add(tag);
      out.push({ tag, on: on.has(tag) });
    }
    return out;
  }
  /** "#Morning  Run " → "morning run": no #, trimmed, lowercase, single
      spaces, at most 30 characters. Nothing left is null. */
  function cleanTag(raw) {
    const tag = String(raw ?? "").replace(/#/g, "").trim().toLowerCase().replace(/\s+/g, " ").slice(0, 30).trim();
    return tag || null;
  }

  return Object.freeze({ mount, header, label, evidenceOf, HEADER, SLOTS, MORE,
    refine: Object.freeze({ subtopicChips, tagChips, cleanTag }) });
})();

if (typeof globalThis === "object") globalThis.QuickFileDial = QuickFileDial;
if (typeof module === "object" && module.exports) module.exports = { QuickFileDial };
