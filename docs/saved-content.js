/* Captured-text presentation only; no generated or invented content. */
(function (root) {
  const excerpt = raw => {
    const value = String(raw || "").replace(/\s+/g, " ").trim();
    if (value.length < 6 || /^(log in to|sign in to|join instagram|see instagram photos|create an account|javascript is not available)/i.test(value)) return null;
    return value.slice(0, 4000);
  };
  const title = (raw, body, platform) => {
    const clean = String(raw || "").trim();
    const match = / on (?:Instagram|X(?: \(formerly Twitter\))?|Threads):\s*(.*)$/i.exec(clean);
    const caption = match && excerpt(match[1].replace(/^[\s"“”]+|[\s"“”]+$/g, ""));
    if (caption) return caption.slice(0, 180);
    const generic = !clean || /^http/.test(clean) || / on (X|Instagram|Threads)( \(formerly Twitter\))?$/i.test(clean) || /^(status|reel|post|instagram|x)$/i.test(clean);
    return generic && excerpt(body) ? excerpt(body).slice(0, 180) : clean || "Saved post";
  };
  const breadcrumb = (topic, subtopic) => [topic, subtopic].map(x => String(x || "").trim()).filter(Boolean).join(" › ");
  root.SavedContent = { excerpt, title, breadcrumb };
})(globalThis);
