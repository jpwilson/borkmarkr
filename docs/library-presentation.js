/* Pure feed presentation rules, shared by the UI and regression fixtures. */
const LibraryPresentation = {
  columns(width) { return width < 761 ? 2 : Math.max(3, Math.floor(Math.min(width, 1280) / 250)); },
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
