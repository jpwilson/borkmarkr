/* bookmarker — bulk import of the saves you already have.
 *
 * The cold-start fix, on the web. Every platform is legally required to hand
 * you your own data; these are the formats those exports actually arrive in.
 * Nothing here scrapes, uses an API key, or touches a login — it reads a file
 * you downloaded yourself, in your own browser. The file never leaves it.
 *
 * Ports two pieces of the iPhone app so a link filed on the web lands in the
 * same place it would have on the phone:
 *   Core/Importers.swift   → Importer  (format sniffing + parsers)
 *   Core/Categorizer.swift → Filer     (offline filing from the taxonomy)
 * Plus a minimal zip reader, because on a computer these exports arrive zipped
 * and "unzip it first" is a step people don't take.
 *
 * Depends on four things the page defines (referenced at call time only, so
 * load order doesn't matter): TAXONOMY, stableID, detectPlatform, PLATFORM,
 * decodeEntities. No third-party code, no network.
 */
"use strict";

/* ══ Zip ═══════════════════════════════════════════════════════════════════
 * Reads the central directory and inflates single members with the platform's
 * own DecompressionStream. Everything goes through Blob.slice, so a 6 GB
 * Instagram archive costs a few kilobytes of memory, not six gigabytes.
 */
const Zip = (() => {
  const SIG_EOCD = 0x06054b50, SIG_EOCD64 = 0x06064b50, SIG_LOC64 = 0x07064b50;
  const SIG_CEN = 0x02014b50, SIG_LOC = 0x04034b50;

  const slice = async (blob, start, end) =>
    new Uint8Array(await blob.slice(start, end).arrayBuffer());
  const view = (u8) => new DataView(u8.buffer, u8.byteOffset, u8.byteLength);

  /** `PK\x03\x04` (or an empty / spanned archive's variants). */
  async function looksLikeZip(file) {
    if (file.size < 4) return false;
    const head = view(await slice(file, 0, 4)).getUint32(0, true);
    return head === SIG_LOC || head === SIG_EOCD || head === 0x08074b50;
  }

  /** Every member: name, compression method, sizes, local header offset. */
  async function entries(file) {
    const size = file.size;
    if (size < 22) throw new Error("empty file");
    // The end-of-central-directory record sits within 64K of the end (its
    // comment is the only thing that can follow it).
    const tail = await slice(file, Math.max(0, size - 65_557), size);
    const tv = view(tail);
    let at = -1;
    for (let i = tail.length - 22; i >= 0; i--) {
      if (tv.getUint32(i, true) === SIG_EOCD) { at = i; break; }
    }
    if (at < 0) throw new Error("not a zip file");

    let count = tv.getUint16(at + 10, true);
    let dirAt = tv.getUint32(at + 16, true);
    // Zip64: the 32-bit fields are pinned at their max and the real values live
    // in a second record. Media-heavy Instagram and X archives get there.
    if (count === 0xffff || dirAt === 0xffffffff) {
      const loc = at - 20;
      if (loc >= 0 && tv.getUint32(loc, true) === SIG_LOC64) {
        const z64At = Number(tv.getBigUint64(loc + 8, true));
        const z64 = await slice(file, z64At, z64At + 56);
        const zv = view(z64);
        if (zv.getUint32(0, true) === SIG_EOCD64) {
          count = Number(zv.getBigUint64(32, true));
          dirAt = Number(zv.getBigUint64(48, true));
        }
      }
    }

    const dir = await slice(file, dirAt, size);
    const dv = view(dir);
    const utf8 = new TextDecoder("utf-8");
    const out = [];
    let p = 0;
    for (let i = 0; i < count && p + 46 <= dir.length; i++) {
      if (dv.getUint32(p, true) !== SIG_CEN) break;
      const method = dv.getUint16(p + 10, true);
      const nameLen = dv.getUint16(p + 28, true);
      const extraLen = dv.getUint16(p + 30, true);
      const commentLen = dv.getUint16(p + 32, true);
      let compressed = dv.getUint32(p + 20, true);
      let inflated = dv.getUint32(p + 24, true);
      let offset = dv.getUint32(p + 42, true);
      const name = utf8.decode(dir.subarray(p + 46, p + 46 + nameLen));

      // Zip64 extra field: 8-byte replacements, in field order, only for the
      // ones that overflowed.
      if (inflated === 0xffffffff || compressed === 0xffffffff || offset === 0xffffffff) {
        let e = p + 46 + nameLen;
        const end = e + extraLen;
        while (e + 4 <= end) {
          const id = dv.getUint16(e, true), len = dv.getUint16(e + 2, true);
          if (id === 0x0001) {
            let q = e + 4;
            if (inflated === 0xffffffff) { inflated = Number(dv.getBigUint64(q, true)); q += 8; }
            if (compressed === 0xffffffff) { compressed = Number(dv.getBigUint64(q, true)); q += 8; }
            if (offset === 0xffffffff) { offset = Number(dv.getBigUint64(q, true)); q += 8; }
            break;
          }
          e += 4 + len;
        }
      }
      out.push({ name, method, compressed, inflated, offset });
      p += 46 + nameLen + extraLen + commentLen;
    }
    return out;
  }

  /** Inflates one member. Stored and deflate only — that is all zip writers use. */
  async function read(file, entry) {
    const head = await slice(file, entry.offset, entry.offset + 30);
    const hv = view(head);
    if (hv.getUint32(0, true) !== SIG_LOC) throw new Error(`corrupt entry ${entry.name}`);
    // The local header carries its own extra-field length, routinely different
    // from the central directory's. Trusting the wrong one lands mid-file.
    const dataAt = entry.offset + 30 + hv.getUint16(26, true) + hv.getUint16(28, true);
    const body = file.slice(dataAt, dataAt + entry.compressed);
    if (entry.method === 0) return new Uint8Array(await body.arrayBuffer());
    if (entry.method !== 8) throw new Error(`${entry.name} uses an unsupported compression method`);
    const out = await new Response(body.stream().pipeThrough(new DecompressionStream("deflate-raw"))).arrayBuffer();
    return new Uint8Array(out);
  }

  return { looksLikeZip, entries, read };
})();


/* ══ Importer ══════════════════════════════════════════════════════════════ */
const Importer = (() => {

  /** One import at a time is plenty, and it keeps a bad file from filling a library. */
  const MAX_RECORDS = 5000;
  /** Belt and braces on a zip: enough for any real export, not enough to hang a tab. */
  const ZIP_MAX_MEMBERS = 80;
  const ZIP_MAX_BYTES = 120 * 1024 * 1024;
  const PLAIN_MAX_BYTES = 250 * 1024 * 1024;

  /* Shown on the pick screen so someone can actually go and get the file.
     Ported from Importer.Format.howTo, with the bits a computer needs added. */
  const FORMATS = {
    instagram: {
      label: "Instagram saved",
      howTo: "Instagram → Settings → Accounts Centre → Your information and permissions → Download your information. Choose JSON, not HTML. It takes 15 minutes to 48 hours to arrive by email, and the download link expires after about four days — grab it when it lands. Drop the whole .zip here, or the saved_posts.json inside it.",
    },
    x: {
      label: "X archive",
      howTo: "X → Settings → Your account → Download an archive of your data. It takes about 24 hours. Drop the whole .zip here, or data/like.js, data/bookmark.js or data/tweets.js from inside it.",
    },
    tiktok: {
      label: "TikTok favourites",
      howTo: "TikTok → Settings → Account → Download your data. Choose JSON, not TXT. Drop the .zip here, or user_data.json from inside it. Favourites and likes both come across.",
    },
    youtube: {
      label: "YouTube / Google Takeout",
      howTo: "takeout.google.com → deselect all → YouTube and YouTube Music → choose playlists (that is where Watch later lives). Drop the Takeout .zip here, or a single .csv from inside it.",
    },
    pinterest: {
      label: "Pinterest",
      howTo: "Pinterest → Settings → Privacy and data → Request your data. It arrives by email as a .zip. Drop it here and your pins come across.",
    },
    browserBookmarks: {
      label: "Browser bookmarks",
      howTo: "Safari: File → Export → Bookmarks. Chrome and Edge: Bookmarks → Bookmark Manager → ⋮ → Export bookmarks. Firefox: Bookmarks → Manage bookmarks → Import and Backup → Export to HTML.",
    },
    plainList: {
      label: "A list of links",
      howTo: "Any .txt, .csv or .json with links in it. We find them and skip everything else.",
    },
  };
  const formatLabel = (id) => FORMATS[id]?.label || "Links";

  /* ── Shared ── */

  /** Rejects junk early so review isn't full of `javascript:` and `chrome://`
      rows from a browser export. Port of Importer.normalise. */
  function normaliseLink(raw) {
    const trimmed = String(raw ?? "").trim();
    if (!trimmed.startsWith("http")) return null;
    let u;
    try { u = new URL(trimmed); } catch { return null; }
    if (u.protocol !== "http:" && u.protocol !== "https:") return null;
    if (!u.hostname.includes(".")) return null;
    return u.href;
  }
  const blank = (s) => { const v = String(s ?? "").trim(); return v || null; };

  const empty = (format = null) => ({ candidates: [], format, skipped: 0 });

  /* ── Netscape bookmarks (Safari / Chrome / Firefox / Edge) ──
     The universal one. Every browser has exported this same 1990s format for
     thirty years, which makes it the single highest-coverage importer. */
  const A_TAG = /<A\s+HREF="([^"]+)"([^>]*)>([^<]*)<\/A>/gi;
  function parseBrowserBookmarks(html) {
    const out = empty("browserBookmarks");
    for (const m of html.matchAll(A_TAG)) {
      // Bookmark exports escape the query string (`?a=1&amp;b=2`); left encoded
      // it becomes a parameter literally called "amp;b".
      const url = normaliseLink(decodeEntities(m[1]));
      if (!url) { out.skipped++; continue; }
      const c = { url, title: null, author: null, savedAt: null, text: null };
      c.title = blank(decodeEntities(m[3]));
      const stamp = /ADD_DATE="([^"]+)"/i.exec(m[2] || "");
      const seconds = stamp ? Number(stamp[1]) : NaN;
      if (Number.isFinite(seconds) && seconds > 0) c.savedAt = new Date(seconds * 1000);
      out.candidates.push(c);
    }
    return out;
  }

  /* ── X archive ──
     `like.js` / `bookmark.js` / `tweets.js` are JSON arrays with a JS
     assignment glued to the front: `window.YTD.like.part0 = [ … ]`. */
  function parseXArchive(text) {
    const out = empty("x");
    const start = text.indexOf("[");
    if (start < 0) return out;
    let array;
    try { array = JSON.parse(text.slice(start)); } catch { return out; }
    if (!Array.isArray(array)) return out;

    for (const entry of array) {
      if (!entry || typeof entry !== "object") { out.skipped++; continue; }
      // The payload is nested under whichever key the file is for.
      const p = entry.like || entry.tweet || entry.bookmark || entry;
      const id = p.tweetId || p.tweet_id || p.id_str || p.id;
      const link = p.expandedUrl || p.expanded_url
        || p.entities?.urls?.[0]?.expanded_url
        || (id ? `https://x.com/i/status/${id}` : null);
      const url = normaliseLink(link);
      if (!url) { out.skipped++; continue; }
      const body = blank(p.fullText || p.full_text);
      out.candidates.push({
        url,
        // The post body makes a far better title than "i/status/123".
        title: body ? body.slice(0, 120) : null,
        author: p.screen_name ? `@${p.screen_name}` : null,
        savedAt: null,
        text: body,
      });
    }
    return out;
  }

  /* ── Instagram ──
     saved_posts.json / saved_collections.json. */
  function parseInstagram(text) {
    const out = empty("instagram");
    let root;
    try { root = JSON.parse(text); } catch { return out; }
    if (!root || typeof root !== "object") return out;

    // Meta ships `saved_saved_media` and, depending on the year and the
    // account, `saved_saved_collection` **or** the plural. Take any of them.
    const lists = Object.keys(root)
      .filter(k => k.startsWith("saved_saved_"))
      .map(k => root[k])
      .filter(Array.isArray)
      .flat();

    for (const entry of lists) {
      const map = entry && entry.string_map_data;
      if (!map || typeof map !== "object") { out.skipped++; continue; }
      // The key is localised ("Saved on" / "Guardado el"), so take the first
      // value carrying an href rather than matching on the label.
      const href = Object.values(map).find(v => v && typeof v === "object" && v.href);
      const url = normaliseLink(href?.href);
      if (!url) { out.skipped++; continue; }
      const handle = blank(entry.title);
      out.candidates.push({
        url,
        title: null,
        author: handle ? `@${handle}` : null,
        savedAt: typeof href.timestamp === "number" && href.timestamp > 0
          ? new Date(href.timestamp * 1000) : null,
        text: null,
      });
    }
    return out;
  }

  /* ── TikTok ── */
  function parseTikTok(text) {
    const out = empty("tiktok");
    let root;
    try { root = JSON.parse(text); } catch { return out; }
    if (!root || typeof root !== "object") return out;

    // Older exports nest under "Activity", newer ones under "Your Activity".
    const activity = root.Activity || root["Your Activity"] || root;
    const favourites = activity["Favorite Videos"]?.FavoriteVideoList;
    const liked = activity["Like List"]?.ItemFavoriteList;

    for (const entry of [].concat(favourites || [], liked || [])) {
      const url = normaliseLink(entry?.Link || entry?.link);
      if (!url) { out.skipped++; continue; }
      out.candidates.push({
        url, title: null, author: null,
        savedAt: tiktokDate(entry.Date || entry.date), text: null,
      });
    }
    return out;
  }
  /** TikTok writes "2024-03-01 09:15:22" in UTC, with no zone marker. */
  function tiktokDate(raw) {
    const m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/.exec(String(raw ?? ""));
    if (!m) return null;
    const t = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
    return Number.isFinite(t) ? new Date(t) : null;
  }

  /* ── CSV (Google Takeout, Pinterest, and friends) ──
     A real reader, not a split on commas: Pinterest titles contain commas, and
     a naive split shifts every column after one. */
  function csvRows(text) {
    const rows = [];
    let row = [], field = "", quoted = false;
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (quoted) {
        if (c !== '"') { field += c; continue; }
        if (text[i + 1] === '"') { field += '"'; i++; continue; }
        quoted = false;
      } else if (c === '"' && field === "") {
        quoted = true;
      } else if (c === ",") {
        row.push(field); field = "";
      } else if (c === "\n" || c === "\r") {
        if (c === "\r" && text[i + 1] === "\n") i++;
        row.push(field); field = "";
        if (row.some(x => x !== "")) rows.push(row);
        row = [];
      } else {
        field += c;
      }
    }
    row.push(field);
    if (row.some(x => x !== "")) rows.push(row);
    return rows;
  }

  const CSV_NOT_A_LINK = /image|thumbnail|avatar|profile|photo/;
  function csvColumns(cells) {
    const cols = cells.map(c => c.trim().replace(/^"|"$/g, "").toLowerCase());
    const find = (test) => { const i = cols.findIndex(test); return i < 0 ? null : i; };
    return {
      cols,
      video: find(c => c.includes("video id")),
      // Pinterest gives both the pin and the site it points at; the pin is the
      // thing you saved.
      url: find(c => c === "pin url" || c === "pin_url")
        ?? find(c => (c.includes("url") || c.includes("link")) && !CSV_NOT_A_LINK.test(c)),
      title: find(c => c.includes("title") || c === "name"),
      author: find(c => c.includes("channel") || c.includes("author") || c.includes("creator") || c.includes("board")),
      date: find(c => c.includes("timestamp") || c.includes("created") || c.includes("saved")
        || c.includes("added") || c === "date"),
    };
  }

  function parseCSV(text) {
    const rows = csvRows(text);
    // Takeout playlist CSVs put a metadata block above the real header, so the
    // first row is not always the one with the columns.
    let head = null, at = 0;
    for (let i = 0; i < Math.min(rows.length, 12); i++) {
      const c = csvColumns(rows[i]);
      if (c.video !== null || c.url !== null) { head = c; at = i + 1; break; }
    }
    const looksPinterest = head?.cols.some(c => c.includes("pin") || c === "board");
    const out = empty(looksPinterest ? "pinterest" : "youtube");
    if (!head) return out;

    for (const fields of rows.slice(at)) {
      let link = null;
      if (head.video !== null && (fields[head.video] || "").trim()) {
        link = `https://www.youtube.com/watch?v=${fields[head.video].trim()}`;
      } else if (head.url !== null) {
        link = (fields[head.url] || "").trim();
      }
      const url = normaliseLink(link);
      if (!url) { out.skipped++; continue; }
      out.candidates.push({
        url,
        title: head.title !== null ? blank(fields[head.title]) : null,
        author: head.author !== null ? blank(fields[head.author]) : null,
        savedAt: head.date !== null ? looseDate(fields[head.date]) : null,
        text: null,
      });
    }
    return out;
  }

  /** ISO stamps, Takeout's "2023-01-01T00:00:00+00:00", TikTok's space form. */
  function looseDate(raw) {
    const v = String(raw ?? "").trim();
    if (!v) return null;
    const t = Date.parse(v.includes("T") || !/^\d{4}-/.test(v) ? v : v.replace(" ", "T") + "Z");
    return Number.isFinite(t) ? new Date(t) : null;
  }

  /* ── Google Takeout YouTube JSON (watch later, playlists, history) ── */
  function parseTakeoutJSON(text) {
    const out = empty("youtube");
    let array;
    try { array = JSON.parse(text); } catch { return out; }
    if (!Array.isArray(array)) return out;
    for (const entry of array) {
      const url = normaliseLink(entry?.titleUrl);
      if (!url) { out.skipped++; continue; }
      out.candidates.push({
        url,
        // Takeout prefixes history entries with the verb: "Watched <title>".
        title: blank(String(entry.title ?? "").replace(/^(Watched|Viewed)\s+/, "")),
        author: blank(entry.subtitles?.[0]?.name),
        savedAt: looseDate(entry.time),
        text: null,
      });
    }
    return out;
  }

  /* ── Pinterest JSON ── */
  function parsePinterestJSON(text) {
    const out = empty("pinterest");
    let root;
    try { root = JSON.parse(text); } catch { return out; }
    const list = Array.isArray(root) ? root
      : [root?.pins, root?.saved_pins, root?.Pins].find(Array.isArray) || [];
    for (const p of list) {
      const url = normaliseLink(p?.pin_url || p?.pinUrl || p?.url || p?.link);
      if (!url) { out.skipped++; continue; }
      out.candidates.push({
        url,
        title: blank(p.title || p.grid_title),
        author: blank(p.board_name || p.board),
        savedAt: looseDate(p.created_at || p.created),
        text: blank(p.description),
      });
    }
    return out;
  }

  /* ── Generic ──
     Best-effort over an unknown JSON shape: walk it and take anything that
     looks like a link. Covers the long tail of exports without a parser each. */
  function parseGenericJSON(text) {
    const out = empty("plainList");
    let root;
    try { root = JSON.parse(text); } catch { return out; }
    const found = [];
    const seen = new Set();
    const walk = (node, depth) => {
      if (depth > 24 || found.length >= MAX_RECORDS * 2) return;
      if (typeof node === "string") {
        if (!node.startsWith("http")) return;
        const url = normaliseLink(node);
        if (url) found.push(url);
        return;
      }
      if (!node || typeof node !== "object") return;
      if (seen.has(node)) return;
      seen.add(node);
      for (const child of Array.isArray(node) ? node : Object.values(node)) walk(child, depth + 1);
    };
    walk(root, 0);
    out.candidates = found.map(url => ({ url, title: null, author: null, savedAt: null, text: null }));
    return out;
  }

  const BARE_URL = /https?:\/\/[^\s"'<>()\[\]{}]+/g;
  function parsePlainList(text) {
    const out = empty("plainList");
    for (const m of text.matchAll(BARE_URL)) {
      // Trailing punctuation belongs to the sentence, not the link.
      const url = normaliseLink(m[0].replace(/[.,;:!?]+$/, ""));
      if (url) out.candidates.push({ url, title: null, author: null, savedAt: null, text: null });
    }
    return out;
  }

  /* ── Entry point ──
     Sniffs the format from the content rather than the filename — exports get
     renamed, and `data.json` tells you nothing. */
  function parseText(text, filename, { strict = false } = {}) {
    const lower = String(filename || "").toLowerCase();
    const head = text.slice(0, 4096);

    if (lower.endsWith(".html") || lower.endsWith(".htm") || head.includes("<!DOCTYPE NETSCAPE-Bookmark-file-1")) {
      // Inside a zip, an .html file is far more likely to be a Takeout activity
      // dump than a bookmarks file, and importing your whole search history is
      // not what anyone asked for.
      if (strict && !/NETSCAPE-Bookmark-file-1/i.test(head)) return empty();
      return parseBrowserBookmarks(text);
    }
    if (text.startsWith("window.YTD")) return parseXArchive(text);
    if (text.includes("saved_saved_media") || text.includes("saved_saved_collection")) return parseInstagram(text);
    if (text.includes("FavoriteVideoList") || text.includes('"Favorite Videos"')) return parseTikTok(text);
    if (lower.endsWith(".csv")) return parseCSV(text);
    if (head.includes('"titleUrl"')) return parseTakeoutJSON(text);
    if (/"(pin_url|pinUrl|board_name)"/.test(head)) return parsePinterestJSON(text);
    const trimmed = text.trimStart();
    if (trimmed.startsWith("[") || trimmed.startsWith("{")) {
      // A walk-everything pass on an arbitrary file found inside a zip pulls in
      // whatever URLs happen to be in it. Only run it on a file someone chose.
      return strict ? empty() : parseGenericJSON(text);
    }
    return strict ? empty() : parsePlainList(text);
  }

  /* ── Files ── */

  const utf8 = new TextDecoder("utf-8", { fatal: true });
  const latin1 = new TextDecoder("windows-1252");
  /** Port of `String(data:encoding:.utf8) ?? .isoLatin1`. */
  function decodeText(bytes) {
    try { return utf8.decode(bytes); } catch { return latin1.decode(bytes); }
  }

  /* Which members of an archive are worth opening. Ranked, because a Takeout
     zip has hundreds of CSVs and only some of them are saves. */
  const ZIP_WANTED = [
    [/(^|\/)saved_(posts|collections)[^/]*\.json$/, 100],
    [/saved_saved_(media|collection)/, 100],
    [/(^|\/)(likes?|bookmarks?|tweets)\.js$/, 95],
    [/(^|\/)user_data[^/]*\.json$/, 90],
    [/(^|\/)(pins?|boards?|saved_pins)\.(csv|json)$/, 85],
    [/(^|\/)bookmarks[^/]*\.html?$/, 80],
    [/\/(saved|favorites?|favourites?|bookmarks?|likes?|playlists?|watch[- ]later)\//, 70],
    [/\.csv$/, 40],
    [/(^|\/)[^/]*(saved|favorite|favourite|bookmark|like|pin)[^/]*\.(json|js|csv|html?)$/, 35],
  ];
  const ZIP_SKIP = /(^|\/)(__MACOSX|media|photos|videos|images|thumbnails|profile_media)\//i;
  function rankZipEntry(name) {
    const n = name.toLowerCase();
    if (n.endsWith("/") || ZIP_SKIP.test(n)) return 0;
    let best = 0;
    for (const [re, score] of ZIP_WANTED) if (re.test(n)) best = Math.max(best, score);
    return best;
  }

  /**
   * Read a picked file into candidates. `onProgress({stage, done, total, file})`
   * runs between members so the dialog can say something true.
   */
  async function parseFile(file, onProgress = () => {}) {
    const name = file.name || "file";
    if (!file.size) throw new Error(`${name} is empty.`);

    if (await Zip.looksLikeZip(file)) {
      // Safari before 16.4 and Firefox before 113 have no DecompressionStream.
      // Say so rather than failing member by member.
      if (typeof DecompressionStream === "undefined") {
        throw new Error(`This browser can't open zip files. Unzip ${name} yourself and drop the .json, .js, .html or .csv from inside it.`);
      }
      return parseZip(file, onProgress);
    }

    // A zip is read through Blob.slice a member at a time; a loose file has to
    // come into memory whole, so it gets a ceiling.
    if (file.size > PLAIN_MAX_BYTES) {
      throw new Error(`${name} is ${Math.round(file.size / 1e6)} MB — too big to read in a browser tab. If it came out of an archive, drop the .zip itself instead.`);
    }
    onProgress({ stage: "reading", file: name, done: 0, total: 1 });
    const bytes = new Uint8Array(await file.arrayBuffer());
    const parsed = parseText(decodeText(bytes), name);
    onProgress({ stage: "parsing", file: name, done: 1, total: 1 });
    return { ...parsed, files: [name] };
  }

  async function parseZip(file, onProgress) {
    let members;
    try { members = await Zip.entries(file); }
    catch (e) { throw new Error(`${file.name}: ${e.message}. If it opens as a folder on your computer, drop the .json or .html from inside it instead.`); }

    const wanted = members
      .map(m => ({ ...m, rank: rankZipEntry(m.name) }))
      .filter(m => m.rank > 0 && m.inflated > 0)
      .sort((a, b) => b.rank - a.rank || a.inflated - b.inflated)
      .slice(0, ZIP_MAX_MEMBERS);

    if (!wanted.length) {
      throw new Error(`No saved links in ${file.name}. It has ${members.length} files, none of them a saved-posts export — check you picked JSON rather than HTML when you asked for your data.`);
    }

    const out = { candidates: [], format: null, skipped: 0, files: [] };
    let budget = ZIP_MAX_BYTES;
    let done = 0;
    for (const m of wanted) {
      done++;
      onProgress({ stage: "parsing", file: m.name, done, total: wanted.length });
      if (m.inflated > budget) continue;
      let text;
      try { text = decodeText(await Zip.read(file, m)); }
      catch { continue; }   // one unreadable member never fails the whole import
      budget -= m.inflated;
      const parsed = parseText(text, m.name, { strict: true });
      if (!parsed.candidates.length) continue;
      out.candidates.push(...parsed.candidates);
      out.skipped += parsed.skipped;
      out.files.push(m.name);
      // The label names what the archive mostly is; first hit wins because the
      // list is ranked.
      out.format ??= parsed.format;
      if (out.candidates.length > MAX_RECORDS * 3) break;
      await new Promise(r => setTimeout(r, 0));   // never hold the frame
    }
    if (!out.candidates.length) {
      throw new Error(`No saved links in ${file.name}. We opened ${wanted.length} file${wanted.length === 1 ? "" : "s"} inside it and found none.`);
    }
    return out;
  }

  /** Collapses duplicates using the same identity rule the app saves under, so
      importing likes *and* bookmarks from the same archive doesn't double up. */
  function dedupe(candidates) {
    const seen = new Set();
    const out = [];
    for (const c of candidates) {
      const id = stableID(c.url);
      if (!id || seen.has(id)) continue;
      seen.add(id);
      out.push({ ...c, id });
    }
    return out;
  }

  return { MAX_RECORDS, FORMATS, formatLabel, parseFile, parseText, parseZip, dedupe, normaliseLink };
})();


/* ══ Filer — port of Core/Categorizer.swift ════════════════════════════════
 * The index is derived from the taxonomy itself: every subcategory name is
 * already a keyword ("Running", "Mobility", "Cold exposure"), so ~700 matchers
 * come for free and stay correct when categories change. On top sits a small
 * curated layer for the cases where the label isn't what people actually write.
 *
 * This exists on the web for one reason: 1,400 imported links must file
 * themselves without 1,400 calls to the categorize function, which is quota'd
 * at 200 a day per person.
 */
const Filer = (() => {

  /* Extra phrases that should hit a category but don't appear in any of its
     subcategory names. Keep this small — the derived index does the bulk. */
  const CATEGORY_HINTS = {
    fitness: ["workout", "gym", "reps", "sets", "squat", "deadlift", "bench", "pull up", "push up", "marathon", "5k", "10k", "hypertrophy", "warm up"],
    nutrition: ["protein", "calorie", "macro", "creatine", "electrolyte", "carb", "keto", "diet"],
    health: ["doctor", "clinic", "diagnos", "prescription", "blood pressure", "cholesterol", "thyroid", "inflammation", "chronic"],
    mentalhealth: ["burnout", "panic attack", "overthink", "nervous system", "cbt", "dopamine", "mental load"],
    wellness: ["routine", "ritual", "calm", "reset", "wind down", "grounding", "sauna", "ice bath"],
    recipes: ["recipe", "ingredient", "cook", "bake", "dinner", "lunch", "air fry", "sheet pan", "leftovers"],
    fooddrink: ["restaurant", "cafe", "espresso", "latte", "sourdough", "tasting", "michelin", "brew"],
    money: ["budget", "debt", "salary", "paycheck", "emergency fund", "net worth", "frugal", "cost of living"],
    investing: ["etf", "index fund", "portfolio", "s&p", "dividend", "brokerage", "compound", "bear market", "bull market"],
    crypto: ["bitcoin", "btc", "ethereum", "eth", "wallet", "blockchain", "defi", "altcoin", "on chain"],
    business: ["startup", "founder", "revenue", "mrr", "arr", "b2b", "saas", "margin", "customer"],
    marketing: ["seo", "funnel", "conversion", "copywriting", "ad spend", "roas", "landing page", "email list"],
    creator: ["algorithm", "views", "subscriber", "follower", "thumbnail", "monetiz", "brand deal", "went viral", "content strategy", "hook"],
    career: ["resume", "cv", "interview", "salary negotiation", "promotion", "manager", "linkedin", "layoff", "onboarding"],
    learning: ["study", "revision", "flashcard", "anki", "exam", "learn", "tutorial", "explained"],
    ai: ["ai", "llm", "gpt", "claude", "prompt", "agent", "model", "machine learning", "diffusion", "rag", "fine tune"],
    coding: ["code", "coding", "python", "javascript", "typescript", "swift", "react", "api", "git", "compiler", "bug", "refactor"],
    tech: ["iphone", "android", "laptop", "headphone", "usb", "router", "spec", "unboxing", "battery life"],
    photovideo: ["camera", "lens", "aperture", "iso", "shutter", "lightroom", "premiere", "davinci", "lut", "bokeh", "cinematic"],
    home: ["living room", "bedroom", "kitchen", "renovat", "interior", "floor plan", "square feet", "landlord"],
    diy: ["fix", "repair", "leak", "drill", "screw", "caulk", "stud", "wiring"],
    crafts: ["handmade", "craft", "carve", "stitch", "loom", "kiln", "epoxy", "3d print", "cnc"],
    cleaning: ["clean", "declutter", "tidy", "organis", "organiz", "stain", "mould", "mold", "vacuum"],
    trades: ["weld", "apprentice", "jobsite", "contractor", "hvac", "electrician", "plumber", "quote"],
    cars: ["car", "engine", "turbo", "brake", "tyre", "tire", "horsepower", "ev", "tesla", "mileage", "dealership", "motorbike", "f1"],
    sports: ["match", "league", "playoff", "goal", "touchdown", "tackle", "referee", "season", "transfer", "fixture"],
    outdoors: ["trail", "summit", "campsite", "tent", "backpack", "belay", "catch", "tide", "gps"],
    nature: ["species", "habitat", "migration", "ecosystem", "forest", "reef", "storm", "eclipse"],
    garden: ["soil", "plant", "seedling", "prune", "mulch", "harvest", "bloom", "weed"],
    homestead: ["chicken", "goat", "canning", "ferment", "off grid", "rainwater", "smallholding"],
    travel: ["flight", "airport", "hostel", "airbnb", "itinerary", "layover", "passport", "backpacking", "visa"],
    fashion: ["outfit", "wardrobe", "fit check", "thrift", "sneaker", "denim", "tailor", "style"],
    beauty: ["skincare", "serum", "retinol", "spf", "moisturis", "moisturiz", "foundation", "mascara", "glow"],
    grooming: ["haircut", "barber", "beard", "shave", "fade", "hairline", "shampoo"],
    relationships: ["partner", "girlfriend", "boyfriend", "husband", "wife", "argument", "attachment", "ex ", "situationship"],
    parenting: ["toddler", "kid", "child", "tantrum", "nursery", "school run", "screen time"],
    babyprep: ["pregnan", "trimester", "newborn", "breastfeed", "labour", "labor", "ultrasound", "postpartum"],
    pets: ["dog", "cat", "puppy", "kitten", "vet", "leash", "litter", "breed"],
    comedy: ["funny", "meme", "joke", "prank", "fail", "skit", "comedian", "lmao"],
    filmtv: ["movie", "film", "series", "episode", "season finale", "netflix", "trailer", "cast", "director"],
    books: ["book", "novel", "read", "author", "chapter", "booktok", "bestseller"],
    music: ["song", "album", "chord", "guitar", "piano", "beat", "mix", "vocal", "playlist", "bpm"],
    gaming: ["game", "gameplay", "boss", "loadout", "patch", "fps", "rpg", "steam", "console"],
    anime: ["anime", "manga", "shonen", "otaku", "cosplay", "webtoon", "arc"],
    art: ["draw", "sketch", "paint", "canvas", "palette", "typography", "figma", "illustration"],
    science: ["study finds", "research", "experiment", "theory", "quantum", "neuron", "galaxy", "molecul"],
    history: ["century", "ancient", "empire", "war", "medieval", "archaeolog", "historic"],
    news: ["election", "government", "policy", "parliament", "senate", "breaking", "president"],
    beliefs: ["god", "bible", "quran", "faith", "prayer", "philosoph", "meaning of life", "conspiracy"],
    truecrime: ["murder", "detective", "suspect", "trial", "verdict", "unsolved", "victim", "forensic"],
  };

  /** Words too generic to carry a signal on their own. */
  const STOP_WORDS = new Set([
    "the", "and", "for", "with", "from", "your", "you", "how", "what", "why",
    "tips", "guide", "best", "top", "new", "all", "out", "amp", "of", "in",
    "on", "to", "a", "an", "my", "is", "it", "this", "that", "at", "by",
  ]);

  /* Routing segments that appear in nearly every social URL and carry no
     topical meaning. Deliberately tight: an earlier version included "index",
     which silently ate the "index" of "index fund". */
  const URL_NOISE = new Set([
    "watch", "shorts", "video", "status", "reel", "reels", "comments",
    "blog", "html", "php", "www", "com", "net", "org", "amp", "embed",
  ]);

  /** Above this, the offline answer is worth trusting on its own. */
  const CONFIDENT_SCORE = 14;

  /* Slugs and punctuation become spaces so "/p/five-hip-mobility-drills"
     matches "mobility", then every token is stemmed. Both sides go through the
     same function, so they only have to agree with each other, not English. */
  const SEPARATORS = /[-_/.?=&+%#@:,!|()\[\]{}"'’\n\t ]/;
  function normalise(raw) {
    const lowered = String(raw ?? "").toLowerCase().normalize("NFD").replace(/\p{M}/gu, "");
    const tokens = lowered.split(SEPARATORS).filter(Boolean).map(stem);
    return " " + tokens.join(" ") + " ";
  }

  /* Deliberately crude suffix stripping — this only has to make two strings
     from the same word family collapse to the same token. */
  const SUFFIXES = ["ing", "ies", "ed", "es", "s"];
  function stem(word) {
    if (word.length <= 4) return word;
    for (const suffix of SUFFIXES) {
      if (!word.endsWith(suffix)) continue;
      // Don't strip into a stub: "sets" -> "set", but "ies" -> "ie".
      if (word.length - suffix.length >= 3) {
        const cut = word.slice(0, word.length - suffix.length);
        return suffix === "ies" ? cut + "y" : cut;
      }
      break;   // the Swift `for … where … { break }` stops at the first match
    }
    return word;
  }

  /** Same normalisation, minus the routing segments every social URL carries. */
  function normaliseURL(url) {
    let path = url.pathname, host = url.hostname;
    try { path = decodeURIComponent(path); } catch { /* keep it encoded */ }
    const tokens = normalise(`${path} ${host}`).split(" ").filter(t => t && !URL_NOISE.has(t));
    return " " + tokens.join(" ") + " ";
  }

  /* Built once, on the first suggestion — not at page load, because most
     visitors never import anything. */
  let MATCHERS = null;
  function matchers() {
    if (MATCHERS) return MATCHERS;
    const all = [];
    for (const category of TAXONOMY) {
      for (const sub of category.subs) {
        const phrase = normalise(sub);
        const trimmed = phrase.trim();
        if (trimmed.length < 3 || STOP_WORDS.has(trimmed)) continue;
        // A subcategory name is a precise signal — above a bare category hint.
        all.push({ phrase, label: sub.toLowerCase(), categoryID: category.id, subcategory: sub, weight: trimmed.length + 6 });
      }
      for (const hint of CATEGORY_HINTS[category.id] || []) {
        all.push({ phrase: normalise(hint), label: hint, categoryID: category.id, subcategory: null, weight: hint.length + 2 });
      }
    }
    // Dedupe per (category, phrase), keeping the strongest. Curated hints often
    // stem to the same token as one of their own subcategories ("paint" is both
    // Art's hint and Art's "Painting"); counting both double-scores it.
    const strongest = new Map();
    for (const m of all) {
      const key = `${m.categoryID}|${m.phrase}`;
      const existing = strongest.get(key);
      if (existing && existing.weight >= m.weight) continue;
      // Prefer the variant that carries a subcategory — it's more specific.
      if (existing && existing.subcategory && !m.subcategory) continue;
      strongest.set(key, m);
    }
    // Longest first so "index fund" wins over "fund" and "mental health" over
    // "health". Ties break on the phrase, so the web is deterministic where the
    // Swift (Dictionary order + an unstable sort) is not.
    MATCHERS = [...strongest.values()].sort((a, b) =>
      b.phrase.length - a.phrase.length
      || (a.phrase < b.phrase ? -1 : a.phrase > b.phrase ? 1 : 0)
      || (a.categoryID < b.categoryID ? -1 : a.categoryID > b.categoryID ? 1 : 0));
    return MATCHERS;
  }

  /** Site names that sneak in as "author". Port of Platform.isSiteName. */
  function isSiteName(raw) {
    const v = String(raw ?? "").trim().toLowerCase();
    if (v.includes("formerly twitter")) return true;
    if (v === "twitter" || v === "x.com") return true;
    if (v === "youtube shorts" || v === "youtu.be") return true;
    return Object.values(PLATFORM).some(p => v === p.name.toLowerCase());
  }

  /**
   * Suggests `{topic, subtopic, tags, score}` for a link, or nulls.
   *
   * It is a *suggestion* by contract: returning nothing is a valid, honest
   * answer — better than confidently filing a link under the wrong thing.
   */
  function suggest(rawURL, title, text) {
    let url;
    try { url = new URL(rawURL); } catch { return { topic: null, subtopic: null, tags: [], score: 0 }; }

    // Authored text (title, post body) is a far better signal than a URL slug,
    // so it scores at full weight and the URL at half. Without this split a
    // stray word in a path can outvote the actual headline.
    const authored = normalise([title || "", text || ""].join(" "));
    const fromURL = normaliseURL(url);

    const categoryScores = new Map();
    const subScores = new Map();
    const matchedLabels = [];

    for (const m of matchers()) {
      const inAuthored = authored.includes(m.phrase);
      const inURL = fromURL.includes(m.phrase);
      if (!inAuthored && !inURL) continue;

      const weight = inAuthored ? m.weight : Math.max(1, Math.floor(m.weight / 2));
      categoryScores.set(m.categoryID, (categoryScores.get(m.categoryID) || 0) + weight);
      matchedLabels.push(m.label);

      if (m.subcategory && weight > (subScores.get(m.categoryID)?.score ?? 0)) {
        subScores.set(m.categoryID, { sub: m.subcategory, score: weight });
      }
    }

    // Ties go to taxonomy order rather than to whatever the hash table felt like.
    let best = null, bestScore = 0;
    for (const t of TAXONOMY) {
      const score = categoryScores.get(t.id) || 0;
      if (score > bestScore) { best = t.id; bestScore = score; }
    }
    // Below this it's a coincidental substring, not a signal. Uncategorised is a
    // real state and Browse surfaces it, so nothing is lost.
    if (!best || bestScore < 6) return { topic: null, subtopic: null, tags: [], score: 0 };

    const unique = [...new Set(matchedLabels.filter(l => l.length > 3))];
    const ranked = unique.sort((a, b) => b.length - a.length || (a < b ? -1 : a > b ? 1 : 0));
    const tags = ranked.slice(0, 3).sort().filter(t => !isSiteName(t));

    return { topic: best, subtopic: subScores.get(best)?.sub ?? null, tags, score: bestScore, confident: bestScore >= CONFIDENT_SCORE };
  }

  const capitalise = (s) => s.split(" ")
    .map(w => w ? w[0].toUpperCase() + w.slice(1).toLowerCase() : w).join(" ");

  /**
   * Readable title from a URL, used only until real metadata arrives.
   *
   * Never "Status": routing segments are excluded outright, a real hyphenated
   * slug wins if there is one, and otherwise we say something honest about
   * where it came from rather than inventing a subject.
   */
  function fallbackTitle(rawURL) {
    let url;
    try { url = new URL(rawURL); } catch { return "Untitled brk"; }
    const platform = detectPlatform(rawURL);
    const segments = url.pathname.split("/").filter(Boolean).map(s => {
      try { return decodeURIComponent(s); } catch { return s; }
    });

    // A hyphen/underscore almost always means a human-readable slug.
    const slug = [...segments].reverse().find(seg =>
      (seg.includes("-") || seg.includes("_")) && seg.length > 6 && !URL_NOISE.has(seg.toLowerCase()));
    if (slug) return capitalise(slug.replace(/[-_]/g, " ").replace(/\.html/g, ""));

    // Social posts: name the author, the one thing the URL reliably tells us.
    const handle = segments.find(s => s.startsWith("@"))
      ?? segments.find(s => s.length > 1 && !URL_NOISE.has(s.toLowerCase()) && !/^\d+$/.test(s) && platform !== "web");
    if (handle) return `${handle.startsWith("@") ? handle : "@" + handle} on ${PLATFORM[platform]?.name || "the web"}`;

    const host = url.hostname.replace("www.", "");
    return host ? `Link from ${host}` : "Untitled brk";
  }

  /** Author is a handle for social posts, a hostname for the web. */
  function fallbackAuthor(rawURL) {
    try { return new URL(rawURL).hostname.replace("www.", "") || null; } catch { return null; }
  }

  return { suggest, fallbackTitle, fallbackAuthor, isSiteName, CONFIDENT_SCORE, _normalise: normalise, _stem: stem };
})();

/* Node (the parser tests) rather than a browser. */
if (typeof module === "object" && module.exports) module.exports = { Zip, Importer, Filer };
