/* bookmarker — how Browse orders itself, and what "share a topic" sends.
 *
 * Ports of `Core/BrowseSort.swift` and `Core/TopicShare.swift`. Both are the
 * kind of thing two platforms must agree on to the character: a chip labelled
 * "Most borks" on one and "By count" on the other is two apps, and a share
 * message that reads differently depending on which device sent it is worse
 * still, because that one is seen by people who don't have the app yet.
 *
 * Pure by design — values in, values out, no DOM, no clock, no library — so
 * `Scripts/test_browse.mjs` exercises the parts worth testing (the ordering,
 * the truncation, the links, the count line) in node, and a weekly digest or
 * a share extension could one day build the same message.
 *
 * Dates are epoch milliseconds here rather than Date objects: the wire gives
 * the web ISO strings, every call site already parses them once, and `null`
 * for "never" compares the way Swift's `Date?` does in the sort below.
 */
"use strict";

/* ── How Browse orders what it is listing ─────────────────────────────────
   One table for topics, sources and side quests, because it is the same three
   questions on each of them: which has the most in it, which did I touch last,
   where is it in the alphabet. */
const BrowseSort = (() => {
  /* Chip labels. Identical on iOS — changing one here means changing
     `BrowseSort.title` there. That is an en dash in A–Z. */
  const TITLES = { borks: "Most borks", recent: "Most recent", alpha: "A–Z" };
  const ALL = ["borks", "recent", "alpha"];
  const FALLBACK = "borks";

  /** Persisted per segment: "what am I looking for" is a different question on
      Topics than on Sources, and picking A–Z once to find a platform should
      not permanently reorder the topic grid. */
  const KEY = {
    topics: "bm.browseSort.topics",
    sources: "bm.browseSort.sources",
    quests: "bm.browseSort.quests",
  };

  /** An unknown persisted value falls back rather than throwing. */
  const named = (raw) => (ALL.includes(raw) ? raw : FALLBACK);
  const title = (option) => TITLES[named(option)];

  /* Locale-aware and digit-aware: "Zone 2" sorts before "Zone 10", and an
     accented name lands where a reader expects it rather than after Z. Custom
     topics go through this same comparison as the built-ins, so they mix into
     the list instead of clumping at one end. */
  const byName = (a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });

  /**
   * One row of any of the three lists, reduced to what an ordering can depend
   * on: `{ id, name, count, recent, pinned, rank }`.
   *
   * `recent` is the newest `saved_at` inside, in epoch ms, or `null` when
   * there is nothing in it — a topic you just made, a source you have never
   * saved from — and those sort *last* under "Most recent" rather than
   * pretending to be ancient. `pinned` is honoured by "Most borks" only; an
   * A–Z that isn't alphabetical is not A–Z. `rank` is the list's own canonical
   * order (taxonomy order, PLATFORM order, newest quest) and every branch that
   * cannot decide falls through to it, so equal rows keep a stable, meaningful
   * order instead of reshuffling on every redraw.
   */
  function compare(option, a, b) {
    switch (named(option)) {
      case "recent": {
        const left = a.recent == null ? null : a.recent;
        const right = b.recent == null ? null : b.recent;
        if (left !== right) {
          if (left == null) return 1;
          if (right == null) return -1;
          return right - left;
        }
        break;
      }
      case "alpha": {
        const order = byName(a.name || "", b.name || "");
        if (order !== 0) return order;
        break;
      }
      default: {
        if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1;
        if (a.count !== b.count) return b.count - a.count;
        break;
      }
    }
    return (a.rank || 0) - (b.rank || 0);
  }

  const order = (option, entries) => (entries || []).slice().sort((a, b) => compare(option, a, b));
  const orderedIDs = (option, entries) => order(option, entries).map(e => e.id);

  return { ALL, FALLBACK, KEY, TITLES, named, title, order, orderedIDs, compare, byName };
})();

/* ── What "share a topic" actually sends ──────────────────────────────────
   A share is an invitation, not an archive: titles only, never body text; ten
   of them, newest first; a count line that says how many there really are; and
   one link to the app at the end. Someone who wants all four hundred can
   install it. */
const TopicShare = (() => {
  const listLimit = 10;   // how many the message lists before it starts counting instead
  const cardLimit = 6;    // how many fit on the image card without it becoming a wall of text in picture form
  const linkLimit = 48;   // longest a shortened link may be before the real URL is used instead
  const titleLimit = 72;  // longest a title may be before it is cut — roughly one line in Messages
  const getURL = "https://bookmarker.lol/get";

  /* Grapheme-ish: counting and cutting by code point rather than by UTF-16
     unit, so an emoji in a caption is never sliced in half. */
  const chars = (s) => Array.from(String(s ?? ""));

  /** Core/Copy.swift's countedBorks. "1 bork", "8 borks". */
  const countedBorks = (n) => `${n} bork${n === 1 ? "" : "s"}`;

  /** "Fitness › Strength", or just "Fitness" when no subtopic is selected. */
  function heading(topic, subtopic) {
    const sub = String(subtopic ?? "").trim();
    return sub ? `${topic} › ${sub}` : String(topic ?? "");
  }

  /** The first line: names the slice, says how big the whole slice is — not
      how many got listed — and says who saved them. */
  const countLine = (topic, subtopic, count) =>
    `${heading(topic, subtopic)} — ${countedBorks(count)} I saved with bookmarker`;

  /** Most recently saved first. Ties break on title so the same library always
      produces the same message. */
  const newestFirst = (items) => (items || []).slice().sort((a, b) => {
    const at = a.savedAt || 0, bt = b.savedAt || 0;
    if (at !== bt) return bt - at;
    return BrowseSort.byName(a.title || "", b.title || "");
  });

  /**
   * A title on one line.
   *
   * Newlines and runs of whitespace collapse — a caption captured as a title
   * arrives with both — and anything past `limit` is cut at the last word
   * boundary in the back half, so the ellipsis never lands mid-word.
   */
  function shortTitle(raw, limit = titleLimit) {
    const flat = String(raw ?? "").split(/\s+/).filter(Boolean).join(" ");
    const cp = chars(flat);
    if (cp.length <= limit || limit <= 0) return flat;
    const cut = cp.slice(0, limit).join("");
    const space = cut.lastIndexOf(" ");
    if (space > -1 && chars(cut.slice(0, space)).length > limit / 2) {
      return cut.slice(0, space).replace(/\s+$/, "") + "…";
    }
    return cut.replace(/\s+$/, "") + "…";
  }

  /**
   * The link as it should read: no `https://`, no `www.`, no trailing slash.
   * `instagram.com/reel/abc` — which Messages, Mail and Notes all still detect
   * and make tappable.
   *
   * `null` when shortening would change where the link *goes*: a query string
   * carrying the identity (`youtube.com/watch?v=…`), a fragment, or a path long
   * enough that it would have to be truncated. A truncated URL is not a link,
   * and the whole point of sharing is that the other person can tap it.
   */
  function shortLink(raw, limit = linkLimit) {
    const trimmed = String(raw ?? "").trim();
    let u;
    try { u = new URL(trimmed); } catch { return null; }
    const host = (u.hostname || "").toLowerCase();
    if (!host || u.search || u.hash) return null;
    const short = (host.startsWith("www.") ? host.slice(4) : host) + u.pathname.replace(/\/+$/, "");
    return chars(short).length <= limit ? short : null;
  }

  /** Short where short is still a working link, the real URL where it isn't. */
  const linkLine = (raw, limit = linkLimit) => shortLink(raw, limit) || String(raw ?? "").trim();

  /** The same link for a surface where nothing is tappable — the image card.
      Nothing to protect there, so this one always fits. */
  function displayURL(raw, limit = linkLimit) {
    const trimmed = String(raw ?? "").trim();
    let u;
    try { u = new URL(trimmed); } catch { return chars(trimmed).slice(0, limit).join(""); }
    const host = (u.hostname || "").toLowerCase();
    if (!host) return chars(trimmed).slice(0, limit).join("");
    let short = (host.startsWith("www.") ? host.slice(4) : host) + u.pathname.replace(/\/+$/, "");
    if (u.search) short += "?…";
    const cp = chars(short);
    if (cp.length <= limit || limit <= 1) return short;
    return cp.slice(0, limit - 1).join("") + "…";
  }

  /**
   * The whole message.
   *
   *     Fitness › Strength — 8 borks I saved with bookmarker
   *
   *     1. Hip strength for runners
   *        instagram.com/reel/abc
   *     2. …
   *     + 3 more
   *
   *     bookmarker.lol/get
   */
  function message({ topic, subtopic = null, items = [], limit = listLimit } = {}) {
    const ordered = newestFirst(items);
    const shown = ordered.slice(0, Math.max(0, limit));
    const lines = [countLine(topic, subtopic, ordered.length), ""];
    shown.forEach((item, i) => {
      lines.push(`${i + 1}. ${shortTitle(item.title)}`);
      lines.push(`   ${linkLine(item.url)}`);
    });
    const remaining = ordered.length - shown.length;
    if (remaining > 0) lines.push(`+ ${remaining} more`);
    lines.push("", footer());
    return lines.join("\n");
  }

  /** `bookmarker.lol/get` — shortened by the same rule as every other link in
      the message, so the last line doesn't look like a different app wrote it. */
  const footer = () => shortLink(getURL) || getURL;

  /** The six the image card shows, already flattened and cut. */
  const cardTitles = (items, limit = 52) =>
    newestFirst(items).slice(0, cardLimit).map(i => shortTitle(i.title, limit));

  return { listLimit, cardLimit, linkLimit, titleLimit, getURL, footer, countedBorks,
           heading, countLine, newestFirst, shortTitle, shortLink, linkLine, displayURL,
           message, cardTitles };
})();

/* Node (Scripts/test_browse.mjs) rather than a browser. */
if (typeof module === "object" && module.exports) module.exports = { BrowseSort, TopicShare };
