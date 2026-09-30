const QuestPresentation = {
  art(title = "", category = "", subtopic = "", builtins = {}) {
    const blob = [title, subtopic, category].join(" ").toLowerCase();
    const words = blob.split(/[^\p{L}\p{N}-]+/u);
    const has = (...stems) => stems.some(stem => stem.includes(" ") ? blob.includes(stem) : words.some(word => word.startsWith(stem)));
    const groups = [
      ["rabbit", ["rabbit","conspirac","cover-up","unsolved","truecrime","beliefs"]],
      ["market", ["market","social","audience","hook","megaphone","creator"]],
      ["business", ["startup","founder","venture","business","shop","storefront","profit"]],
      ["run", ["run","marathon","5k","10k","mobility","stretch","fitness","hip","hamstring","tendon","sports"]],
      ["create", ["potter","ceramic","clay"]],
      ["cook", ["recipe","cook","meal","food","kitchen","nutrition"]],
      ["create", ["draw","paint","camera","photo","video","art","crafts"]],
      ["learn", ["read","book","learn","study","course"]],
      ["money", ["money","invest","crypto","budget","spend"]]
    ];
    for (const [scene, stems] of groups) if (has(...stems)) return `/img/quests/${scene}.jpg`;
    if (builtins[category]) return `/img/topics/${category}.jpg`;
    const families = [
      ["mentalhealth", ["anxiet","stress","burnout","therap","depress","adhd","grief","panic","overthink"]],
      ["wellness", ["breath","meditat","mindful","journal","gratitude","morning person","routine","habit","cold plunge","sauna","detox","wellness","calm","focus"]],
      ["health", ["sleep","health","doctor","symptom","pain","injur","gut","hormone","longevity","bloodwork","immun","allerg","dental"]]
    ];
    for (const [topic, stems] of families) if (has(...stems)) return `/img/topics/${topic}.jpg`;
    return "/img/quests/compass.jpg";
  },
  candidates(rows, attached, topic, query, fold) {
    const tokens = fold(query).split(/\s+/).filter(Boolean);
    return rows.filter(r => !r.deleted_at && !attached.includes(r.id)
      && (!topic || r.category_id === topic)
      && tokens.every(t => fold([r.title,r.body_text,r.note_text,r.subcategory,...(r.tags || [])].join(" ")).includes(t)));
  }
};
