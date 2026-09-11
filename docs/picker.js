/* bookmarker — how the topic picker answers what you typed.
 *
 * Port of `Core/TopicPickerQuery.swift`, and the same kind of contract as
 * docs/browse.js: both apps must put the same topic at the top of the same
 * search, because the row you expect is the row you tap without reading it.
 *
 * Its own file for the reason revisit.js and browse.js are — `Scripts/
 * test_picker.mjs` runs the ranking in node, and index.html keeps the DOM and
 * nothing else. Pure by design: names and needles in, an order out. No DOM, no
 * taxonomy, no clock.
 *
 * Matching is token-prefix, never mid-word `contains`, on subtopics: "run"
 * must find Running under Fitness and must not find Speedruns under Gaming.
 */
"use strict";

const TopicPickerQuery = (() => {
  /* One folding for every text match in the app — search, the search blob and
     this. Case- and accent-blind, so "index" finds "índex". index.html takes
     its `fold` from here so there is exactly one of them. */
  const fold = (s) => String(s ?? "").toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
  const tokens = (s) => fold(s).split(/[^\p{L}\p{N}]+/u).filter(Boolean);

  /* Crude stem so "game" hits Gaming (the e drops before -ing) without also
     letting "run" hit Speedruns. */
  function stem(w) {
    if (w.length > 4 && w.endsWith("ing")) w = w.slice(0, -3);
    if (w.length > 3 && w.endsWith("e")) w = w.slice(0, -1);
    return w;
  }
  function tokenMatches(token, needle) {
    if (token.startsWith(needle)) return true;
    const ns = stem(needle), ts = stem(token);
    if (ns.length >= 3 && token.startsWith(ns)) return true;
    return ns.length >= 3 && ts.length >= 3 && ts === ns;
  }

  /* Which tier a topic lands in. The numbers are the cross-platform half:
     iOS 1.1.1's TopicPickerQuery uses the same three, and higher is better so
     that "does its own name answer this?" is the first thing compared.

     NAME beats SUB because a topic *called* Running is a better answer to
     "runn" than Fitness, which merely has a Running inside it — and that is
     true whoever made either of them, so custom topics are ranked by this and
     not by being custom. */
  const NAME = 2, SUB = 1, NONE = 0;

  /* How well one name answers the query, lower being better:
     0 the name is the query · 1 the name, or a word in it, starts with it ·
     2 it is in there somewhere · null not at all. */
  function nameScore(name, needle) {
    const f = fold(name);
    if (f === needle) return 0;
    if (f.startsWith(needle) || tokens(name).some(x => tokenMatches(x, needle))) return 1;
    return f.includes(needle) ? 2 : null;
  }
  /* The best any subtopic manages. Token-prefix only — no mid-word `contains`
     — or "run" drags Gaming in through Speedruns, which is the thing this file
     exists to stop. */
  function subScore(subs, needle) {
    let best = null;
    for (const sub of subs || []) {
      if (!tokens(sub).some(x => tokenMatches(x, needle))) continue;
      const f = fold(sub);
      const s = f === needle ? 0 : (f.startsWith(needle) ? 1 : 2);
      if (best === null || s < best) best = s;
    }
    return best;
  }

  /** NAME (2), SUB (1) or NONE (0) for one topic. An empty query matches
      everything, so it is NAME. */
  function tier(name, subs, needle) {
    const q = fold(String(needle ?? "").trim());
    if (!q) return NAME;
    if (nameScore(name, q) !== null) return NAME;
    return subScore(subs, q) !== null ? SUB : NONE;
  }

  const az = (a, b) =>
    String(a.name ?? "").localeCompare(String(b.name ?? ""), undefined, { numeric: true, sensitivity: "base" });

  /** Subtopics A–Z — built-in and the person's own in one run — at the point
      of drawing, never in the taxonomy data. Finder's comparison, like iOS's
      `localizedStandardCompare`: case-blind and numeric, so "Zone 2" sorts
      before "Zone 10". A copy comes back; the list handed in is left alone. */
  const alphabetical = (list) => Array.from(list || [])
    .sort((a, b) => String(a).localeCompare(String(b), undefined, { numeric: true, sensitivity: "base" }));

  /** Everything that answers `needle`, best first, and nothing that doesn't.
      `entries` are `{ name, subs, … }` and come back untouched, so a caller
      can hang whatever it likes off them.

      The order: tier first (a name match before a subtopic-only match), then
      strength inside the tier (the whole name, then a prefix, then anywhere
      else), then A–Z. No query means no ranking to do — every topic, A–Z. */
  function order(entries, needle) {
    const q = fold(String(needle ?? "").trim());
    const list = Array.from(entries || []);
    if (!q) return list.sort(az);
    const scored = [];
    for (const e of list) {
      const n = nameScore(e.name, q);
      if (n !== null) { scored.push({ e, tier: NAME, strength: n }); continue; }
      const s = subScore(e.subs, q);
      if (s !== null) scored.push({ e, tier: SUB, strength: s });
    }
    scored.sort((a, b) => (b.tier - a.tier) || (a.strength - b.strength) || az(a.e, b.e));
    return scored.map(x => x.e);
  }

  /** The subtopics a query lit up, so the sheet can mark them. */
  function matchingSubs(subs, needle) {
    const q = fold(String(needle ?? "").trim());
    return new Set(q ? (subs || []).filter(sub => tokens(sub).some(x => tokenMatches(x, q))) : []);
  }

  /** Is `raw` worth offering as a new topic or subtopic? Two characters, and
      not one you already have. */
  function canAdd(raw, existing) {
    const c = String(raw ?? "").trim().toLowerCase();
    return c.length >= 2 && !(existing || []).some(x => String(x).toLowerCase() === c);
  }

  return { NAME, SUB, NONE, fold, tokens, stem, tokenMatches, nameScore, subScore,
           tier, order, alphabetical, matchingSubs, canAdd };
})();

/* Node (Scripts/test_picker.mjs) rather than a browser. */
if (typeof module === "object" && module.exports) module.exports = { TopicPickerQuery };
