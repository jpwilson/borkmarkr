const QuestBriefClient = {
  request(quest, rows) {
    return {
      id:quest.id, title:quest.title.trim().slice(0,140),
      topic:quest.topic || null, titles:rows.slice(0,12).map(r=>SavedContent.title(r.title,r.body_text,r.platform).slice(0,140)),
      sources:rows.slice(0,12).map(r=>({id:r.id,title:SavedContent.title(r.title,r.body_text,r.platform).slice(0,300),text:(SavedContent.excerpt(r.body_text)||"").slice(0,1600)})),
      todos:(quest.todos || []).slice(0,8).map(t=>({title:(t.text || t.title || "").slice(0,140),done:!!t.done}))
    };
  },
  parse(raw, input) {
    if (raw?.version !== 2 || typeof raw.summary !== "string" || !raw.summary.trim()) return null;
    const ids=new Set(input.sources.map(s=>s.id));
    return {summary:raw.summary.slice(0,320), steps:[...new Set((Array.isArray(raw.steps)?raw.steps:[]).filter(s=>typeof s==="string" && s.trim() && s.length<=80))].slice(0,3),
      source_ids:[...new Set((Array.isArray(raw.source_ids)?raw.source_ids:[]).filter(id=>ids.has(id)))],
      basis:["saved_text","titles_only","goal_only"].includes(raw.basis)?raw.basis:"titles_only",version:2,inputKey:JSON.stringify(input)};
  },
  label(brief) {
    if (brief.version !== 2) return "Earlier AI draft — refresh to see its sources.";
    return brief.basis === "saved_text" ? "AI draft from saved excerpts — check the originals."
      : brief.basis === "goal_only" ? "AI draft from your goal, not saved evidence."
      : "AI draft from titles only — source details may be missing.";
  }
};
