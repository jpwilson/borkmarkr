// Fetching user-supplied URLs from our egress, safely. Shared by `preview`
// (page metadata) and `thumb` (image bytes) so there is exactly one copy of
// the SSRF rules: only http(s), only default ports, never a private or
// link-local host — checked on the input AND on every redirect hop, by name
// and by what the name resolves to, before a request is sent there.
// We never pretend to be a browser.

export const USER_AGENT = "bookmarker/0.1 (+https://bookmarker.lol)";
export const PAGE_MAX_BYTES = 64 * 1024;
export const PAGE_TIMEOUT_MS = 8_000;

const MAX_REDIRECTS = 5;

/* A dotted IPv4 address that is not on the public internet. */
function ipv4IsPrivate(ip: string): boolean {
  const m = ip.match(/^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  if (!m) return false;
  const [a, b] = [Number(m[1]), Number(m[2])];
  if (a === 10 || a === 127 || a === 0) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 169 && b === 254) return true;            // link-local, cloud metadata
  if (a === 100 && b >= 64 && b <= 127) return true;  // carrier-grade NAT, some cloud metadata
  if (a === 198 && (b === 18 || b === 19)) return true;
  if (a === 192 && b === 0 && Number(m[3]) === 0) return true;
  if (a >= 224) return true;
  return false;
}

/* A resolved IP address (v4 or v6) that is not on the public internet. */
export function ipIsPrivate(ip: string): boolean {
  const h = ip.toLowerCase().replace(/^\[|\]$/g, "");
  if (!h.includes(":")) return ipv4IsPrivate(h);
  if (h === "::" || h === "::1") return true;
  // IPv4-mapped / -translated forms carry a v4 address in the last 32 bits.
  const mapped = h.match(/^(?:::ffff:|64:ff9b::)(\d+\.\d+\.\d+\.\d+)$/);
  if (mapped) return ipv4IsPrivate(mapped[1]);
  if (/^(?:::ffff:|64:ff9b::)[0-9a-f]{1,4}:[0-9a-f]{1,4}$/.test(h)) return true; // hex-written mapped v4: refuse
  const first = parseInt(h.split(":")[0] || "0", 16);
  if ((first & 0xfe00) === 0xfc00) return true;       // fc00::/7 unique local
  if ((first & 0xffc0) === 0xfe80) return true;       // fe80::/10 link-local
  if ((first & 0xff00) === 0xff00) return true;       // multicast
  return false;
}

export function hostIsPrivate(hostname: string): boolean {
  const h = hostname.toLowerCase().replace(/\.$/, "");
  if (h === "localhost" || h.endsWith(".localhost") || h.endsWith(".local") || h.endsWith(".internal")) return true;
  if (ipv4IsPrivate(h)) return true;
  // IPv6 literals: links to sites never use them, so refuse them all.
  if (h.includes(":")) return true;
  return false;
}

/* Does this name resolve to a private address? A literal check alone lets
   `127.0.0.1.nip.io` or a hostile DNS record walk straight in. When the
   runtime cannot resolve at all, fall back to the literal check (the fetch
   would fail anyway for a name that does not resolve). */
async function resolvesPrivate(hostname: string): Promise<boolean> {
  const h = hostname.replace(/^\[|\]$/g, "");
  if (/^\d+\.\d+\.\d+\.\d+$/.test(h) || h.includes(":")) return false; // literal: hostIsPrivate already ruled
  // deno-lint-ignore no-explicit-any
  const resolve = (globalThis as any).Deno?.resolveDns as
    | ((name: string, type: "A" | "AAAA") => Promise<string[]>)
    | undefined;
  if (typeof resolve !== "function") return false;
  const answers = await Promise.allSettled([resolve(h, "A"), resolve(h, "AAAA")]);
  const addresses = answers.flatMap((a) => (a.status === "fulfilled" ? a.value : []));
  return addresses.some(ipIsPrivate);
}

/* fetch(), following redirects by hand so that EVERY hop — not just the
   last — passes checkURL and the DNS check before any request is sent to it.
   Returns null when a hop is refused or there are too many of them. */
export async function guardedFetch(start: URL, init: RequestInit): Promise<{ res: Response; url: URL } | null> {
  let url: URL | null = start;
  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    if (!url || await resolvesPrivate(url.hostname)) return null;
    const res: Response = await fetch(url, { ...init, redirect: "manual" });
    if (res.status < 300 || res.status > 399 || !res.headers.get("location")) return { res, url };
    const location = res.headers.get("location") as string;
    res.body?.cancel().catch(() => {});
    try {
      url = checkURL(new URL(location, url).href);
    } catch {
      return null;
    }
  }
  return null;
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
    const got = await guardedFetch(url, {
      signal: controller.signal,
      headers: { "User-Agent": USER_AGENT, Accept: "text/html,application/json" },
    });
    if (!got) return null; // redirected somewhere we refuse to read
    const { res, url: finalURL } = got;
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
