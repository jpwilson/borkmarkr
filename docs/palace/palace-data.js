/* Memory Palace data: the built-in demo library, the grouping that turns a
   library into rooms and shelves, and the read-only loader for a signed-in
   visitor's own bookmarks. Plain script, no DOM — Scripts/test_palace.mjs
   runs it in a bare vm context. */
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
     with a reddit.com URL, exactly as the app files it. */
  function demoRows() {
    const rows = [];
    const newest = Date.UTC(2026, 9, 18, 9, 30);
    let n = 0;
    for (const room of DEMO) {
      for (const [shelf, items] of room.shelves) {
        for (const [title, source, community] of items) {
          n++;
          const h = hash(title);
          rows.push({
            id: `demo-${String(n).padStart(3, "0")}`,
            title,
            url: demoUrl(source, title, community),
            platform: source === "reddit" ? "web" : source,
            category_id: room.topic,
            subcategory: shelf,
            saved_at: new Date(newest - n * 5.3e6).toISOString(),
            duration_seconds: source === "youtube" ? 240 + (h % 1500) : null,
            meta: source === "web" ? `Article · ${3 + (h % 11)} min read` : source === "x" ? (h % 3 ? "Thread" : "Post") : null,
            deleted_at: null,
          });
        }
      }
    }
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

  function byNewest(a, b) {
    return (Date.parse(b.saved_at) || 0) - (Date.parse(a.saved_at) || 0) || String(a.id).localeCompare(String(b.id));
  }

  function toCard(row, room, shelf) {
    const source = sourceOf(row);
    return {
      id: row.id, title: titleOf(row), url: row.url || "",
      source, sourceLabel: SOURCES[source]?.label || "Web", meta: metaOf(row, source),
      room: room.name, shelf, hue: room.hue,
    };
  }

  function shelvesFrom(groups, room, maxShelves, maxCards) {
    const sorted = [...groups].sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]));
    const keep = sorted.length > maxShelves ? sorted.slice(0, maxShelves - 1) : sorted;
    if (sorted.length > maxShelves) {
      const rest = sorted.slice(maxShelves - 1).flatMap(([, rows]) => rows);
      keep.push(["Everything else", rest]);
    }
    return keep.map(([name, rows]) => {
      rows.sort(byNewest);
      return { name, total: rows.length, cards: rows.slice(0, maxCards).map((r) => toCard(r, room, name)) };
    });
  }

  /* Library → rooms (top-level topics) → shelves (subtopics) → cards.
     Caps keep the palace walkable: past maxRooms the smallest topics share a
     "More topics" room, past maxShelves a room's smallest subtopics share one
     shelf, and a shelf shows its newest maxCards while counting all of them. */
  function buildModel(rows, opts = {}) {
    const { taxonomy = [], customTopics = [], order = null, maxRooms = 10, maxShelves = 5, maxCards = 6 } = opts;
    const resolve = topicResolver(taxonomy, customTopics);
    const rooms = new Map();
    let total = 0;
    for (const row of rows || []) {
      if (!row || row.deleted_at || !row.url) continue;
      total++;
      const topic = resolve(row.category_id) || UNFILED;
      if (!rooms.has(topic.id)) rooms.set(topic.id, { topic, rows: [] });
      rooms.get(topic.id).rows.push(row);
    }
    let list = [...rooms.values()];
    if (order) {
      const rank = new Map(order.map((id, i) => [id, i]));
      list.sort((a, b) => (rank.get(a.topic.id) ?? 1e9) - (rank.get(b.topic.id) ?? 1e9));
    } else {
      list.sort((a, b) => (a.topic.id === "unfiled") - (b.topic.id === "unfiled") || b.rows.length - a.rows.length || a.topic.name.localeCompare(b.topic.name));
    }
    let overflow = [];
    if (list.length > maxRooms) {
      overflow = list.slice(maxRooms - 1);
      list = list.slice(0, maxRooms - 1);
    }
    const built = list.map(({ topic, rows: own }) => {
      const room = { id: topic.id, name: topic.name, hue: topic.hue, total: own.length };
      const groups = new Map();
      for (const row of own) {
        const name = topic.id === "unfiled"
          ? (SOURCES[sourceOf(row)]?.label || "Web")
          : (String(row.subcategory || "").trim() || "General");
        if (!groups.has(name)) groups.set(name, []);
        groups.get(name).push(row);
      }
      room.shelves = shelvesFrom(groups, room, maxShelves, maxCards);
      return room;
    });
    if (overflow.length) {
      const room = { id: "more", name: "More topics", hue: 30, total: overflow.reduce((n, g) => n + g.rows.length, 0) };
      const groups = new Map(overflow.map((g) => [g.topic.name, g.rows]));
      room.shelves = shelvesFrom(groups, room, maxShelves, maxCards);
      built.push(room);
    }
    const shown = built.reduce((n, r) => n + r.shelves.reduce((m, s) => m + s.cards.length, 0), 0);
    return { rooms: built, total, shown, demo: !!opts.demo };
  }

  function demoModel(taxonomy) {
    return buildModel(demoRows(), { taxonomy, order: DEMO.map((r) => r.topic), demo: true });
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
    demoRows, demoModel, buildModel, sourceOf,
    readSession, validSession, loadOwnLibrary, bookmarksPath,
  };
})();
