// bookmarker — server-side link preview for the web app.
//
// A browser can't read another site's Open Graph tags (CORS), so the web app
// asks us. This mirrors Core/LinkPreview.swift: oEmbed for YouTube, OG tags
// for the rest, first 64KB only, and no pretending to be a browser.
//
// Signed-in users only (verify_jwt). SSRF is the risk to take seriously: the
// URL is user-supplied, so only http(s), only default ports, and never a
// private or link-local host — checked on the input AND on the redirect
// destination.

const MAX_BYTES = 64 * 1024;
const TIMEOUT_MS = 8_000;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    },
  });

function hostIsPrivate(hostname: string): boolean {
  const h = hostname.toLowerCase();
  if (h === "localhost" || h.endsWith(".local") || h.endsWith(".internal")) return true;
  // IPv4 literals
  const m = h.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (m) {
    const [a, b] = [Number(m[1]), Number(m[2])];
    if (a === 10 || a === 127 || a === 0) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 169 && b === 254) return true;
    if (a >= 224) return true;
  }
  // IPv6 literals
  if (h.includes(":")) return true;
  return false;
}

function checkURL(raw: string): URL | null {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return null;
  if (url.port && url.port !== "80" && url.port !== "443") return null;
  if (hostIsPrivate(url.hostname)) return null;
  return url;
}

async function readCapped(res: Response): Promise<string> {
  const reader = res.body?.getReader();
  if (!reader) return "";
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (total < MAX_BYTES) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    total += value.length;
  }
  reader.cancel().catch(() => {});
  const merged = new Uint8Array(Math.min(total, MAX_BYTES));
  let offset = 0;
  for (const chunk of chunks) {
    const slice = chunk.slice(0, MAX_BYTES - offset);
    merged.set(slice, offset);
    offset += slice.length;
    if (offset >= MAX_BYTES) break;
  }
  return new TextDecoder("utf-8", { fatal: false }).decode(merged);
}

async function fetchCapped(url: URL): Promise<{ html: string; finalURL: URL } | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      redirect: "follow",
      signal: controller.signal,
      headers: { "User-Agent": "bookmarker/0.1 (+https://bookmarker.lol)", Accept: "text/html,application/json" },
    });
    const finalURL = checkURL(res.url || url.href);
    if (!finalURL) return null; // redirected somewhere we refuse to read
    if (!res.ok) return null;
    return { html: await readCapped(res), finalURL };
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

const decodeEntities = (s: string) =>
  s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&apos;/g, "'")
    .replace(/&#x27;/gi, "'").replace(/&nbsp;/g, " ").trim();

function meta(html: string, property: string): string | null {
  const p = property.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const patterns = [
    new RegExp(`<meta[^>]+(?:property|name)=["']${p}["'][^>]+content=["']([^"']+)["']`, "i"),
    new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]+(?:property|name)=["']${p}["']`, "i"),
  ];
  for (const re of patterns) {
    const m = html.match(re);
    if (m) return decodeEntities(m[1]);
  }
  return null;
}

function titleTag(html: string): string | null {
  const m = html.match(/<title[^>]*>([^<]+)<\/title>/i);
  return m ? decodeEntities(m[1]) : null;
}

function isYouTube(url: URL): boolean {
  const h = url.hostname.toLowerCase().replace(/^(www\.|m\.)/, "");
  return h === "youtube.com" || h === "youtu.be" || h === "music.youtube.com";
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return json({}, 200);
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  let body: { url?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }
  const url = checkURL(body.url ?? "");
  if (!url) return json({ error: "That doesn't look like a link we can fetch." }, 400);

  // The gateway waves the public key through, and a URL fetcher must not be
  // an open proxy — so consume the per-user quota, which fails closed for
  // anonymous callers (auth.uid() is null → false). Same design as the AI
  // functions' ai_quota_consume.
  const quota = await fetch(`${Deno.env.get("SUPABASE_URL")}/rest/v1/rpc/preview_quota_consume`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      Authorization: req.headers.get("Authorization") ?? "",
    },
    body: JSON.stringify({ daily_limit: 500 }),
  }).then((r) => r.ok ? r.json() : false).catch(() => false);
  if (quota !== true) return json({ error: "Sign in to fetch link previews." }, 401);

  const empty = { title: null, author: null, image_url: null, duration_seconds: null };

  // oEmbed first for YouTube — documented, reliable, has author.
  if (isYouTube(url)) {
    const endpoint = new URL("https://www.youtube.com/oembed");
    endpoint.searchParams.set("format", "json");
    endpoint.searchParams.set("url", url.href);
    const got = await fetchCapped(endpoint);
    if (got) {
      try {
        const data = JSON.parse(got.html);
        return json({
          title: typeof data.title === "string" ? data.title : null,
          author: typeof data.author_name === "string" ? data.author_name : null,
          image_url: typeof data.thumbnail_url === "string" ? data.thumbnail_url : null,
          duration_seconds: null,
        });
      } catch { /* fall through to OG */ }
    }
  }

  const got = await fetchCapped(url);
  if (!got) return json(empty);
  const html = got.html;

  const image = meta(html, "og:image") ?? meta(html, "twitter:image");
  let imageURL: string | null = null;
  if (image) {
    try {
      imageURL = new URL(image, got.finalURL).href;
    } catch { /* ignore */ }
  }
  const durationRaw = meta(html, "og:video:duration");
  const duration = durationRaw && /^\d+$/.test(durationRaw) ? Number(durationRaw) : null;

  return json({
    title: meta(html, "og:title") ?? meta(html, "twitter:title") ?? titleTag(html),
    author: meta(html, "author") ?? meta(html, "og:site_name"),
    image_url: imageURL,
    duration_seconds: duration,
  });
});
