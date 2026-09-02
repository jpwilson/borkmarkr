// Fetching user-supplied URLs from our egress, safely. Shared by `preview`
// (page metadata) and `thumb` (image bytes) so there is exactly one copy of
// the SSRF rules: only http(s), only default ports, never a private or
// link-local host — checked on the input AND on the redirect destination.
// We never pretend to be a browser.

export const USER_AGENT = "bookmarker/0.1 (+https://bookmarker.lol)";
export const PAGE_MAX_BYTES = 64 * 1024;
export const PAGE_TIMEOUT_MS = 8_000;

export function hostIsPrivate(hostname: string): boolean {
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

export function checkURL(raw: string): URL | null {
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

/* Read at most `max` bytes of a body, then hang up. */
export async function readBytes(res: Response, max: number): Promise<Uint8Array> {
  const reader = res.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (total < max) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    total += value.length;
  }
  reader.cancel().catch(() => {});
  const merged = new Uint8Array(Math.min(total, max));
  let offset = 0;
  for (const chunk of chunks) {
    const slice = chunk.slice(0, max - offset);
    merged.set(slice, offset);
    offset += slice.length;
    if (offset >= max) break;
  }
  return merged;
}

export async function readCapped(res: Response): Promise<string> {
  return new TextDecoder("utf-8", { fatal: false }).decode(await readBytes(res, PAGE_MAX_BYTES));
}

/* First 64KB of an HTML page, or null if the site (or its redirect) is off limits. */
export async function fetchCapped(url: URL): Promise<{ html: string; finalURL: URL } | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PAGE_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      redirect: "follow",
      signal: controller.signal,
      headers: { "User-Agent": USER_AGENT, Accept: "text/html,application/json" },
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

export const decodeEntities = (s: string) =>
  s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&apos;/g, "'")
    .replace(/&#x27;/gi, "'").replace(/&nbsp;/g, " ").trim();

export function meta(html: string, property: string): string | null {
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

export function titleTag(html: string): string | null {
  const m = html.match(/<title[^>]*>([^<]+)<\/title>/i);
  return m ? decodeEntities(m[1]) : null;
}

/* The page's preferred preview image, absolute, or null. */
export async function pageImage(page: URL): Promise<string | null> {
  const got = await fetchCapped(page);
  if (!got) return null;
  const image = meta(got.html, "og:image") ?? meta(got.html, "twitter:image");
  if (!image) return null;
  try {
    return new URL(image, got.finalURL).href;
  } catch {
    return null;
  }
}
