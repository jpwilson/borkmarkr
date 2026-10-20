/* Library Atlas data: the built-in demo library, the grouping that turns a
   library into map regions, districts and markers, the time series behind the
   timeline and charts, and the read-only loader for a signed-in visitor's own
   bookmarks. Plain script, no DOM — Scripts/test_palace.mjs runs it in a bare
   vm context. */
const PalaceData = (() => {
  const SUPABASE_URL = "https://pcjuxnhqxyfvgagnblzv.supabase.co";
  const ANON_KEY = "sb_publishable_z0wBO4NZrMW3T0ZywSDfJA_UoFRHMKb"; // same public key as the web app; RLS is the lock
  const SESSION_KEY = "bm.session";
  const CUSTOM_PREFIX = "custom.";
  const COLUMNS = "id,url,title,platform,category_id,subcategory,saved_at,duration_seconds,deleted_at";
  const PAGE = 1000, MAX_PAGES = 10;

  const SOURCES = {
    x: { label: "X", kind: "Post" },
    youtube: { label: "YouTube", kind: "Video" },
    reddit: { label: "Reddit", kind: "Thread" },
    web: { label: "Web", kind: "Article" },
    instagram: { label: "Instagram", kind: "Reel" },
    tiktok: { label: "TikTok", kind: "Clip" },
    threads: { label: "Threads", kind: "Post" },
    pinterest: { label: "Pinterest", kind: "Pin" },
    grok: { label: "Grok", kind: "Post" },
  };

  /* The demo palace: eight rooms in tour order, 3–5 real taxonomy subtopics
     each, 149 generic titles. Reddit items carry their community; nothing
     here names or quotes a real person. */
  const DEMO = [
    { topic: "ai", shelves: [
      ["Prompting", [["GPT-4 Prompting Techniques", "youtube"], ["Prompt Engineering Masterclass", "youtube"], ["Five prompt patterns that fix vague answers", "x"], ["Chain-of-thought prompting, explained simply", "web"], ["System prompts that actually stick", "reddit", "PromptEngineering"]]],
      ["Agents", [["The Future of AI Agents", "x"], ["How AI agents plan multi-step tasks", "youtube"], ["Agent memory: what works and what doesn't", "web"], ["Building a research agent in 20 minutes", "youtube"], ["AI Ethics and Safety", "web"]]],
      ["Image generation", [["Midjourney Tips for Beginners", "reddit", "midjourney"], ["Stable Diffusion Tutorial", "youtube"], ["Consistent characters across AI images", "x"], ["Lighting prompts for product shots", "reddit", "StableDiffusion"], ["Upscaling AI art without artifacts", "web"]]],
      ["Coding with AI", [["Building Chatbots with LangChain", "youtube"], ["AI Code Review Tools Comparison", "web"], ["Fine-tuning vs RAG Explained", "x"], ["Pair programming with an AI assistant", "youtube"], ["Writing tests with AI, the right way", "web"]]],
      ["Tools", [["Local LLM Setup Guide", "reddit", "LocalLLaMA"], ["The AI tools I use every day", "youtube"], ["Best free AI note-taking apps", "web"], ["Speech-to-text tools compared", "reddit", "productivity"]]],
    ]},
    { topic: "recipes", shelves: [
      ["Quick meals", [["Easy Weeknight Pasta", "youtube"], ["Quick Breakfast Ideas", "reddit", "EatCheapAndHealthy"], ["Air Fryer Chicken Wings", "x"], ["Fifteen-minute garlic noodles", "youtube"]]],
      ["Desserts", [["Chocolate Chip Cookie Recipe", "web"], ["Three-ingredient chocolate mousse", "x"], ["No-bake cheesecake bars", "youtube"], ["Brown butter, explained", "web"], ["Lemon tart for beginners", "web"]]],
      ["Meal prep", [["Meal Prep for the Week", "youtube"], ["Sheet Pan Dinner Ideas", "web"], ["Protein-Packed Smoothies", "youtube"], ["Five lunches from one grocery run", "x"]]],
      ["Baking", [["Sourdough Starter Guide", "reddit", "Sourdough"], ["Focaccia with a crackly crust", "youtube"], ["Why your bread is dense (and how to fix it)", "web"], ["Laminated dough without a stand mixer", "reddit", "Breadit"]]],
      ["Vegetarian", [["Vegetarian Chili Recipe", "web"], ["One-Pot Curry Recipe", "youtube"], ["Crispy tofu every single time", "reddit", "vegetarian"], ["High-protein lentil bowls", "web"]]],
    ]},
    { topic: "fitness", shelves: [
      ["Running", [["How to Start Running", "web"], ["Marathon Training Plan", "web"], ["Zone 2 training, explained", "youtube"], ["Fix your running cadence", "x"], ["First 10K in eight weeks", "reddit", "running"]]],
      ["Mobility", [["Yoga for Lower Back Pain", "youtube"], ["Best Foam Rolling Techniques", "reddit", "flexibility"], ["Morning Mobility Routine", "youtube"], ["Recovery Tips for Athletes", "web"], ["Hip openers for desk workers", "reddit", "yoga"]]],
      ["HIIT", [["30-Min HIIT Workout", "youtube"], ["Home Workout Equipment Guide", "web"], ["Twenty-minute EMOM finisher", "x"], ["Tabata vs HIIT: what's the difference?", "web"], ["Kettlebell circuits for beginners", "youtube"]]],
      ["Strength", [["Progressive Overload Explained", "x"], ["Strength Training for Beginners", "reddit", "Fitness"], ["Deadlift form check, step by step", "youtube"], ["Push-pull-legs for busy weeks", "web"]]],
    ]},
    { topic: "travel", shelves: [
      ["Destinations", [["Tokyo Travel Guide", "youtube"], ["Best Hotels in Bali", "web"], ["Travel Photography Guide", "youtube"], ["Hidden Gems in Italy", "web"], ["Iceland ring road highlights", "x"], ["Best time to visit Patagonia", "web"]]],
      ["Itineraries", [["48 Hours in NYC", "web"], ["Solo Travel Safety", "reddit", "solotravel"], ["Weekend Getaway Ideas", "x"], ["Ten days in Portugal by train", "web"], ["A perfect day in Kyoto", "youtube"]]],
      ["Budget travel", [["Budget Backpacking Europe", "reddit", "backpacking"], ["Packing Light Tips", "x"], ["Flight Booking Strategies", "reddit", "travel"], ["Carry-on only for two weeks", "youtube"], ["Hostels that feel like hotels", "web"]]],
    ]},
    { topic: "art", shelves: [
      ["Graphic design", [["Color Theory Basics", "youtube"], ["Typography Best Practices", "web"], ["Icon Design Tutorial", "youtube"], ["Layout Composition Tips", "x"]]],
      ["UI/UX", [["Figma to Production Workflow", "x"], ["UI Animation Principles", "youtube"], ["Design System Guide", "web"], ["Dark Mode Design Patterns", "reddit", "UI_Design"]]],
      ["Drawing", [["Procreate Illustration", "reddit", "procreate"], ["Gesture drawing in five minutes a day", "youtube"], ["How to draw hands that look right", "reddit", "learnart"], ["Ink shading techniques", "x"], ["Perspective drawing for beginners", "web"]]],
      ["Inspiration", [["Portfolio Website Examples", "web"], ["Brutalist web design gallery", "web"], ["Poster designs from the 1960s", "x"], ["Moodboards that guide a project", "youtube"], ["Packaging design that stands out", "reddit", "graphic_design"]]],
    ]},
    { topic: "coding", shelves: [
      ["Backend", [["Node.js Performance Tips", "x"], ["Python for Data Science", "youtube"], ["API Design Principles", "youtube"], ["Database Schema Design", "reddit", "Database"], ["Caching strategies that scale", "web"]]],
      ["Web dev", [["React Best Practices", "web"], ["CSS grid layouts in ten minutes", "youtube"], ["Build a static site with no framework", "web"], ["Accessible forms checklist", "reddit", "webdev"]]],
      ["DevOps", [["Git Workflow Guide", "web"], ["Docker for Beginners", "youtube"], ["Testing Strategies", "web"], ["Code Review Checklist", "x"]]],
      ["Debugging", [["Debugging Techniques", "x"], ["Reading a stack trace like a pro", "web"], ["Rubber duck debugging works", "x"], ["Finding memory leaks in the browser", "youtube"]]],
      ["Mobile", [["SwiftUI layout tricks", "youtube"], ["Offline-first mobile apps", "web"], ["Shipping your first app to the store", "reddit", "iOSProgramming"]]],
    ]},
    { topic: "business", shelves: [
      ["Startups", [["Y Combinator Application Tips", "web"], ["Product-Market Fit Guide", "youtube"], ["Business Plan Template", "web"], ["Hiring Your First Employee", "reddit", "startups"], ["Talking to customers before you build", "youtube"]]],
      ["Strategy", [["Building a Remote Team", "web"], ["SaaS Pricing Strategies", "reddit", "SaaS"], ["Customer Retention Tactics", "web"], ["Marketing on a Budget", "youtube"], ["Positioning when you're the underdog", "x"]]],
      ["Finance", [["Startup Fundraising 101", "x"], ["Startup Metrics That Matter", "x"], ["Reading a cash-flow statement", "youtube"], ["Bootstrapping vs raising money", "reddit", "Entrepreneur"], ["Unit economics on one page", "web"]]],
    ]},
    { topic: "tech", shelves: [
      ["Gadgets", [["Best Wireless Earbuds 2026", "web"], ["Monitor Buying Guide", "web"], ["Mechanical Keyboard Guide", "reddit", "MechanicalKeyboards"], ["Ergonomic Desk Setup", "youtube"], ["Tech Deals This Week", "x"]]],
      ["Phones", [["iPhone 15 Pro Review", "youtube"], ["Getting more battery life from your phone", "web"], ["Phone camera settings worth changing", "youtube"], ["Which budget phone should you buy?", "reddit", "Android"]]],
      ["Laptops", [["M3 MacBook Air Impressions", "x"], ["Gaming Laptop Recommendations", "reddit", "GamingLaptops"], ["Linux on a laptop: what to know first", "web"], ["Laptop vs desktop for creative work", "youtube"]]],
      ["Smart home", [["Smart Home Setup Guide", "youtube"], ["Cable Management Tips", "x"], ["Automations that save time every morning", "reddit", "homeautomation"]]],
    ]},
  ];

  function hash(text) {
    let h = 2166136261;
    for (let i = 0; i < text.length; i++) h = Math.imul(h ^ text.charCodeAt(i), 16777619);
    return h >>> 0;
  }

  function demoUrl(source, title, community) {
    const q = encodeURIComponent(title);
    if (source === "youtube") return `https://www.youtube.com/results?search_query=${q}`;
    if (source === "x") return `https://x.com/search?q=${q}&f=top`;
    if (source === "reddit") return `https://www.reddit.com/r/${community}/search/?q=${q}&restrict_sr=1`;
    return `https://duckduckgo.com/?q=${q}`;
  }

  /* Rows shaped like the app's `bookmarks` table. Reddit is stored as "web"
     with a reddit.com URL, exactly as the app files it.

     Dates are spread over DEMO_DAYS so the atlas has a real time axis: each
     topic starts on its own day (so "new topic" moments exist), items inside
     a topic lean recent, and a couple of seeded binge days give the weekly
     chart its spikes. Everything is derived from the title hash, so two runs
     build the same library. */
  const DEMO_END = Date.UTC(2026, 9, 18, 11, 0);
  const DEMO_DAYS = 512;
  const DAY = 86_400_000;

  function demoRows() {
    const rows = [];
    const K = DEMO.length;
    let n = 0;
    DEMO.forEach((room, k) => {
      const items = room.shelves.flatMap(([shelf, list]) => list.map((item) => [shelf, item]));
      // Topics open at staggered dates; the shuffle keeps that order off the list order.
      const startDay = Math.round((((k * 7) % K) / K) * 0.62 * DEMO_DAYS);
      const bingeDay = Math.round(startDay + (DEMO_DAYS - startDay) * 0.58);
      items.forEach(([shelf, [title, source, community]], i) => {
        n++;
        const h = hash(title);
        const u = (i + 0.5) / items.length;
        let day = startDay + (DEMO_DAYS - startDay) * Math.pow(u, 0.8) + ((h >> 3) % 11) - 5;
        if (h % 9 === 0) day = bingeDay;
        if (h % 23 === 0) day = DEMO_DAYS - 37;
        day = Math.min(DEMO_DAYS, Math.max(startDay, Math.round(day)));
        const at = DEMO_END - (DEMO_DAYS - day) * DAY + (7 + (h % 16)) * 3_600_000 + ((h >> 7) % 60) * 60_000;
        rows.push({
          id: `demo-${String(n).padStart(3, "0")}`,
          title,
          url: demoUrl(source, title, community),
          platform: source === "reddit" ? "web" : source,
          category_id: room.topic,
          subcategory: shelf,
          saved_at: new Date(Math.min(at, DEMO_END)).toISOString(),
          duration_seconds: source === "youtube" ? 240 + (h % 1500) : null,
          meta: source === "web" ? `Article · ${3 + (h % 11)} min read` : source === "x" ? (h % 3 ? "Thread" : "Post") : null,
          deleted_at: null,
        });
      });
    });
    return rows;
  }

  function hostOf(url) {
    try { return new URL(url).hostname.toLowerCase().replace(/^(www|m|mobile|old)\./, ""); } catch { return ""; }
  }

  function sourceOf(row) {
    const p = String(row.platform || "web").toLowerCase();
    const host = hostOf(row.url);
    if (p === "x" || p === "twitter" || /(^|\.)(x|twitter)\.com$/.test(host)) return "x";
    if (p === "youtube" || p === "shorts" || /(^|\.)youtube\.com$|^youtu\.be$/.test(host)) return "youtube";
    if (p === "reddit" || /(^|\.)reddit\.com$|^redd\.it$/.test(host)) return "reddit";
    if (SOURCES[p]) return p;
    return "web";
  }

  function clock(seconds) {
    const s = Math.max(0, Math.round(seconds));
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), r = s % 60;
    const pad = (v) => String(v).padStart(2, "0");
    return h ? `${h}:${pad(m)}:${pad(r)}` : `${m}:${pad(r)}`;
  }

  function metaOf(row, source) {
    if (row.meta) return row.meta;
    if (source === "youtube" && row.duration_seconds) return clock(row.duration_seconds);
    if (source === "reddit") {
      const m = /\/r\/([^/?#]+)/i.exec(String(row.url || ""));
      if (m) return `r/${m[1]}`;
    }
    const host = hostOf(row.url);
    return host || SOURCES[source]?.kind || "Link";
  }

  function titleOf(row) {
    const t = String(row.title || "").replace(/\s+/g, " ").trim();
    if (t) return t;
    const host = hostOf(row.url);
    return host ? `Saved from ${host}` : "Untitled link";
  }

  /* Same derivations as docs/index.html, so a custom topic reads and colours
     the same here as it does in the app. */
  function customTopicName(id) {
    const words = id.slice(CUSTOM_PREFIX.length).replace(/-+/g, " ").trim();
    return words.charAt(0).toUpperCase() + words.slice(1);
  }
  function customHues(taxonomy) {
    const taken = taxonomy.map((t) => t.hue);
    const free = [];
    for (let step = 0; step < 52; step++) {
      const hue = (step * 7) % 360;
      if (taken.every((h) => Math.abs(h - hue) >= 3)) free.push(hue);
    }
    return free.length ? free : [24];
  }
  function customHue(id, hues) {
    let h = 2166136261;
    for (let i = 0; i < id.length; i++) h = Math.imul(h ^ id.charCodeAt(i), 16777619);
    return hues[(h >>> 0) % hues.length];
  }

  const UNFILED = { id: "unfiled", name: "Unfiled", hue: 18 };

  function topicResolver(taxonomy, customTopics) {
    const builtIn = new Map(taxonomy.map((t) => [t.id, t]));
    const custom = new Map();
    for (const t of customTopics || []) if (t && t.id && !t.deleted_at) custom.set(t.id, t);
    const hues = customHues(taxonomy);
    return (id) => {
      if (!id) return null;
      const known = builtIn.get(id);
      if (known) return { id, name: known.name, hue: known.hue };
      const saved = custom.get(id);
      if (saved) return { id, name: saved.name, hue: Number.isFinite(saved.hue) ? saved.hue : customHue(id, hues) };
      if (id.startsWith(CUSTOM_PREFIX)) return { id, name: customTopicName(id), hue: customHue(id, hues) };
      return null;
    };
  }

  /* The only saturated colours anywhere: one per region and one per source,
     assigned by rank so the legend, the map, the charts and the markers all
     agree. Nine earthy hues that stay apart for deuteranopes and read on a
     cream panel. The UI accent (#D9482B) is deliberately not in here. */
  const DATA_COLORS = ["#B4573A", "#3F7D74", "#5C6BA8", "#A8862C", "#86537F", "#3C6B91", "#75843C", "#9E4256", "#5C6A77"];
  const colorAt = (i) => DATA_COLORS[i % DATA_COLORS.length];

  const MAX_REGIONS = 9;
  const MAX_DISTRICTS = 6;

  const timeOf = (row) => {
    const t = Date.parse(row.saved_at);
    return Number.isFinite(t) ? t : null;
  };

  function toItem(row, region, district) {
    const source = sourceOf(row);
    return {
      id: String(row.id),
      title: titleOf(row),
      url: row.url || "",
      source,
      sourceLabel: SOURCES[source]?.label || "Web",
      meta: metaOf(row, source),
      regionId: region.id,
      regionName: region.name,
      district,
      at: timeOf(row),
    };
  }

  const byTime = (a, b) => (a.at ?? Infinity) - (b.at ?? Infinity) || String(a.id).localeCompare(String(b.id));

  function districtsFrom(groups, region) {
    const sorted = [...groups].sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]));
    const keep = sorted.length > MAX_DISTRICTS ? sorted.slice(0, MAX_DISTRICTS - 1) : sorted;
    if (sorted.length > MAX_DISTRICTS) keep.push(["Everything else", sorted.slice(MAX_DISTRICTS - 1).flatMap(([, r]) => r)]);
    return keep.map(([name, rows]) => {
      const items = rows.map((r) => toItem(r, region, name)).sort(byTime);
      return { name, total: items.length, items };
    });
  }

  const weekStart = (ms) => {
    const d = new Date(ms);
    const day = (d.getUTCDay() + 6) % 7; // Monday = 0
    return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() - day);
  };
  const dayStart = (ms) => {
    const d = new Date(ms);
    return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  };

  /* Weekly buckets covering the whole range, with per-region and per-source
     counts, so the three charts and the scrubber all read the same series. */
  function weeklySeries(items, range) {
    if (!range) return [];
    const weeks = [];
    const index = new Map();
    for (let t = weekStart(range.start); t <= range.end; t += 7 * DAY) {
      index.set(t, weeks.length);
      weeks.push({ t, count: 0, byRegion: {}, bySource: {} });
    }
    for (const it of items) {
      if (it.at == null) continue;
      const w = weeks[index.get(weekStart(it.at))];
      if (!w) continue;
      w.count++;
      w.byRegion[it.regionId] = (w.byRegion[it.regionId] || 0) + 1;
      w.bySource[it.source] = (w.bySource[it.source] || 0) + 1;
    }
    return weeks;
  }

  function keyMoments(items, regions, weeks) {
    const dated = items.filter((i) => i.at != null);
    if (!dated.length) return [];
    const out = [];
    const colorOf = (id) => regions.find((r) => r.id === id)?.color || "#6E685E";
    const first = dated[0], last = dated[dated.length - 1];
    out.push({ id: "first", label: "First save", detail: first.title, at: first.at, color: "#D9482B" });

    const days = new Map();
    for (const it of dated) {
      const d = dayStart(it.at);
      if (!days.has(d)) days.set(d, []);
      days.get(d).push(it);
    }
    let bigDay = null;
    for (const [d, list] of days) if (!bigDay || list.length > bigDay[1].length || (list.length === bigDay[1].length && d < bigDay[0])) bigDay = [d, list];
    if (bigDay && bigDay[1].length > 1) {
      const tally = new Map();
      for (const it of bigDay[1]) tally.set(it.regionId, (tally.get(it.regionId) || 0) + 1);
      const top = [...tally].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))[0][0];
      out.push({ id: "biggest-day", label: "Biggest day", detail: `${bigDay[1].length} saves`, at: bigDay[1][0].at, color: colorOf(top) });
    }

    const started = regions.filter((r) => r.first != null).sort((a, b) => b.first - a.first);
    for (const r of started.slice(0, 2)) {
      if (r.first > first.at) out.push({ id: `new-${r.id}`, label: `New topic: ${r.name}`, detail: `${r.total} saved since`, at: r.first, color: r.color });
    }

    const bigWeek = weeks.reduce((best, w) => (!best || w.count > best.count ? w : best), null);
    if (bigWeek && bigWeek.count > 1) out.push({ id: "busiest-week", label: "Busiest week", detail: `${bigWeek.count} saves`, at: bigWeek.t, color: "#5C6A77" });

    if (last.at > first.at) out.push({ id: "latest", label: "Latest save", detail: last.title, at: last.at, color: "#D9482B" });

    const seen = new Set();
    return out
      .filter((m) => (seen.has(m.id) ? false : seen.add(m.id)))
      .sort((a, b) => a.at - b.at);
  }

  /* Library → regions (top-level topics) → districts (subtopics) → markers.
     Past MAX_REGIONS the smallest topics share a "More topics" region, past
     MAX_DISTRICTS a region's smallest subtopics share "Everything else".
     Every count, date and series on the page comes out of here. */
  function buildAtlas(rows, opts = {}) {
    const { taxonomy = [], customTopics = [], order = null, demo = false, label = demo ? "Demo library" : "My library" } = opts;
    const resolve = topicResolver(taxonomy, customTopics);
    const groups = new Map();
    let total = 0;
    for (const row of rows || []) {
      if (!row || row.deleted_at || !row.url) continue;
      total++;
      const topic = resolve(row.category_id) || UNFILED;
      if (!groups.has(topic.id)) groups.set(topic.id, { topic, rows: [] });
      groups.get(topic.id).rows.push(row);
    }
    let list = [...groups.values()];
    if (order) {
      const rank = new Map(order.map((id, i) => [id, i]));
      list.sort((a, b) => (rank.get(a.topic.id) ?? 1e9) - (rank.get(b.topic.id) ?? 1e9));
    } else {
      list.sort((a, b) => (a.topic.id === "unfiled") - (b.topic.id === "unfiled") || b.rows.length - a.rows.length || a.topic.name.localeCompare(b.topic.name));
    }
    let overflow = [];
    if (list.length > MAX_REGIONS) {
      overflow = list.slice(MAX_REGIONS - 1);
      list = list.slice(0, MAX_REGIONS - 1);
    }
    const packs = list.map(({ topic, rows: own }) => [{ id: topic.id, name: topic.name, hue: topic.hue }, own, false]);
    if (overflow.length) packs.push([{ id: "more", name: "More topics", hue: 30 }, overflow.flatMap((g) => g.rows), true]);

    const regions = packs.map(([base, own, merged], i) => {
      const region = { ...base, color: colorAt(i), index: i, total: own.length };
      const buckets = new Map();
      for (const row of own) {
        const name = merged
          ? (resolve(row.category_id)?.name || UNFILED.name)
          : base.id === "unfiled"
            ? (SOURCES[sourceOf(row)]?.label || "Web")
            : (String(row.subcategory || "").trim() || "General");
        if (!buckets.has(name)) buckets.set(name, []);
        buckets.get(name).push(row);
      }
      region.districts = districtsFrom(buckets, region);
      region.items = region.districts.flatMap((d) => d.items).sort(byTime);
      const times = region.items.map((i2) => i2.at).filter((t) => t != null);
      region.first = times.length ? Math.min(...times) : null;
      region.last = times.length ? Math.max(...times) : null;
      region.share = total ? region.total / total : 0;
      return region;
    });

    const items = regions.flatMap((r) => r.items).sort(byTime);
    const datedItems = items.filter((i) => i.at != null);
    const range = datedItems.length
      ? { start: datedItems[0].at, end: datedItems[datedItems.length - 1].at }
      : null;

    const srcCount = new Map();
    for (const it of items) srcCount.set(it.source, (srcCount.get(it.source) || 0) + 1);
    const sources = [...srcCount]
      .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
      .map(([id, count], i) => ({ id, label: SOURCES[id]?.label || "Web", kind: SOURCES[id]?.kind || "Link", count, color: colorAt(i), share: total ? count / total : 0 }));

    const weeks = weeklySeries(items, range);
    const moments = keyMoments(datedItems, regions, weeks);

    const districtNames = new Set();
    for (const r of regions) for (const d of r.districts) districtNames.add(`${r.id}/${d.name}`);

    const last30 = range ? datedItems.filter((i) => i.at > range.end - 30 * DAY).length : 0;
    const spanWeeks = weeks.length || 1;
    const stats = {
      subtopics: districtNames.size,
      topSource: sources[0] || null,
      topRegion: regions.reduce((best, r) => (!best || r.total > best.total ? r : best), null),
      last30,
      perWeek: Math.round((datedItems.length / spanWeeks) * 10) / 10,
      dated: datedItems.length,
      undated: items.length - datedItems.length,
      oldest: datedItems[0] || null,
      newest: datedItems[datedItems.length - 1] || null,
    };

    return { demo: !!demo, label, total, regions, items, sources, range, weeks, moments, stats, colors: DATA_COLORS.slice() };
  }

  function demoAtlas(taxonomy) {
    return buildAtlas(demoRows(), { taxonomy, order: DEMO.map((r) => r.topic), demo: true });
  }

  /* ── Signed-in visitors: read-only, same session contract as docs/index.html ── */
  function readSession(storage) {
    try {
      const s = JSON.parse(storage.getItem(SESSION_KEY) || "null");
      return s && s.access_token && s.refresh_token && s.user_id ? s : null;
    } catch { return null; }
  }

  /* Refresh tokens are single-use, so a refreshed session is written straight
     back in the app's exact shape — otherwise the app tab would be holding a
     spent token. If another tab got there first, use what it stored. This
     never signs anyone out: a failed refresh leaves bm.session alone. */
  async function validSession({ storage, fetch, now = Date.now }) {
    const s = readSession(storage);
    if (!s) return null;
    if (now() < s.expires_at - 60_000) return s;
    let r;
    try {
      r = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`, {
        method: "POST",
        headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
        body: JSON.stringify({ refresh_token: s.refresh_token }),
      });
    } catch { r = null; }
    if (!r || !r.ok) {
      const latest = readSession(storage);
      if (latest && latest.refresh_token !== s.refresh_token && now() < latest.expires_at - 60_000) return latest;
      return null;
    }
    const d = await r.json();
    const next = {
      access_token: d.access_token, refresh_token: d.refresh_token,
      expires_at: now() + (d.expires_in ?? 3600) * 1000,
      user_id: d.user?.id ?? s.user_id, email: d.user?.email ?? s.email,
    };
    storage.setItem(SESSION_KEY, JSON.stringify(next));
    return next;
  }

  async function getJSON(fetch, path, session) {
    const res = await fetch(`${SUPABASE_URL}${path}`, {
      method: "GET",
      headers: { apikey: ANON_KEY, Authorization: `Bearer ${session.access_token}`, Accept: "application/json" },
    });
    if (!res.ok) {
      const err = new Error(res.status === 401 ? "Your session has expired." : `Server error (${res.status})`);
      err.status = res.status;
      throw err;
    }
    return res.json();
  }

  function bookmarksPath(userId, page) {
    return `/rest/v1/bookmarks?select=${COLUMNS}&owner_id=eq.${encodeURIComponent(userId)}&deleted_at=is.null`
      + `&order=saved_at.desc,id.asc&limit=${PAGE}&offset=${page * PAGE}`;
  }

  async function loadOwnLibrary({ storage, fetch, now = Date.now }) {
    const session = await validSession({ storage, fetch, now });
    if (!session) {
      const err = new Error("Sign in at bookmarker.lol to see your own palace.");
      err.status = 401;
      throw err;
    }
    const rows = [];
    for (let page = 0; page < MAX_PAGES; page++) {
      const batch = await getJSON(fetch, bookmarksPath(session.user_id, page), session);
      rows.push(...batch);
      if (batch.length < PAGE) break;
    }
    let customTopics = [];
    try {
      customTopics = await getJSON(fetch, `/rest/v1/custom_topics?select=id,name,hue,deleted_at&owner_id=eq.${encodeURIComponent(session.user_id)}&limit=1000`, session);
    } catch { /* names fall back to the id, as in the app */ }
    return { rows, customTopics, email: session.email || "" };
  }

  return {
    SOURCES, DEMO, SESSION_KEY,
    DATA_COLORS, DEMO_END, DEMO_DAYS,
    demoRows, demoAtlas, buildAtlas, sourceOf, weekStart, dayStart,
    readSession, validSession, loadOwnLibrary, bookmarksPath,
  };
})();
