const SingleShare = {
  text(row, topicName, includeNote=false) {
    const title=SavedContent.title(row.title,row.body_text,row.platform);
    const lines=["Check out this link:",title,row.url];
    const path=SavedContent.breadcrumb(topicName,row.subcategory);
    if (path) lines.push("Topic: " + path);
    if (row.tags?.length) lines.push("Tags: " + row.tags.map(t=>"#"+t).join(" · "));
    if (includeNote && row.note_text?.trim()) lines.push("\nMy note:\n"+row.note_text);
    return lines.filter(Boolean).join("\n");
  }
};
