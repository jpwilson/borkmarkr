/* Pure feed presentation rules, shared by the UI and regression fixtures. */
const LibraryPresentation = {
  columns(width) { return width < 761 ? 2 : Math.max(3, Math.floor(Math.min(width, 1280) / 250)); },
  /* The feed's three densities. Anything else (an old or hand-typed value)
     is Grid, which is what "cards" has always meant. */
  density(value) { return value === "list" || value === "compact" ? value : "cards"; },
  /* Columns from the grid's own width, so the rail and the gutters are
     already paid for: Grid cards are 200px or wider (2 to 6), Compact tiles
     about 140px (3 to 8), List is one column. The +14/+10 is one gap, since
     n columns need only n-1 of them. */
  gridColumns(width, density) {
    const w = Math.max(0, Number(width) || 0);
    if (density === "list") return 1;
    if (density === "compact") return Math.min(8, Math.max(3, Math.floor((w + 10) / 150)));
    return Math.min(6, Math.max(2, Math.floor((w + 14) / 214)));
  },
  /* One post saved from two apps, shown once. Rows (newest first) join when
     they share a picture, or, on different platforms, the same creator and
     the same 20+ characters of title, or the same 40+ characters of title.
     A picture or title that many rows share is a site's default, not a
     cross-post, so it joins nothing. The main card is the member with a
     picture, else the newest; each group sits where its newest member was.
     Display only: nothing stored changes, and stableID is untouched.
     → [{ row, also: [rows] }] */
  crossPosts(rows, { titleOf = (r) => r.title, creatorOf = () => null, imageOf = () => null, platformOf = (r) => r.platform } = {}) {
    const clean = (t) => String(t || "").normalize("NFD").replace(/\p{M}/gu, "").toLowerCase()
      .replace(/https?:\/\/\S+/g, " ").replace(/[#@][\p{L}\p{N}_]+/gu, " ")
      .replace(/[^\p{L}\p{N}]+/gu, " ").trim();
    const parent = rows.map((_, i) => i);
    const find = (i) => { while (parent[i] !== i) i = parent[i] = parent[parent[i]]; return i; };
    const join = (a, b) => { a = find(a); b = find(b); if (a !== b) parent[Math.max(a, b)] = Math.min(a, b); };
    const buckets = new Map();
    rows.forEach((r, i) => {
      // A creator is folded on its own: the title's cleaning drops @handles, which is all a creator is.
      const title = clean(titleOf(r)), image = imageOf(r);
      const who = String(creatorOf(r) || "").normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().replace(/[^\p{L}\p{N}]+/gu, "");
      if (image) (buckets.get("i " + image) || buckets.set("i " + image, { cross: false, at: [] }).get("i " + image)).at.push(i);
      if (who && title.length >= 20) { const k = "c " + who + " " + title.slice(0, 60); (buckets.get(k) || buckets.set(k, { cross: true, at: [] }).get(k)).at.push(i); }
      if (title.length >= 40) { const k = "t " + title.slice(0, 80); (buckets.get(k) || buckets.set(k, { cross: true, at: [] }).get(k)).at.push(i); }
    });
    for (const { cross, at } of buckets.values()) {
      if (at.length < 2 || at.length > 4) continue;
      for (let a = 0; a < at.length; a++) for (let b = a + 1; b < at.length; b++)
        if (!cross || platformOf(rows[at[a]]) !== platformOf(rows[at[b]])) join(at[a], at[b]);
    }
    const groups = new Map();
    rows.forEach((r, i) => { const g = find(i); if (!groups.has(g)) groups.set(g, []); groups.get(g).push(r); });
    const out = [];
    for (const members of groups.values()) {
      const row = members.find(imageOf) || members[0];
      out.push({ row, also: members.filter(m => m !== row) });
    }
    return out;
  },
  filter(rows, refinement) {
    return rows.filter(r => (!refinement.sub || r.subcategory === refinement.sub)
      && (!refinement.source || r.platform === refinement.source)
      && (!refinement.tag || (r.tags || []).includes(refinement.tag)));
  },
  subtopics(rows) {
    return [...new Set(rows.map(r => r.subcategory).filter(Boolean))]
      .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }));
  },
  tags(rows, sub) {
    const counts = new Map();
    for (const r of rows.filter(r => !sub || r.subcategory === sub))
      for (const tag of new Set(r.tags || [])) counts.set(tag, (counts.get(tag) || 0) + 1);
    return [...counts].filter(([, n]) => n >= 2)
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).slice(0, 6);
  }
};
