// bookmarker — keep a bookmark's cover alive.
//
// Instagram, Facebook and TikTok sign their CDN image URLs and let them die
// in about five days. 0008_thumbs.sql queues a job whenever a bookmark
// arrives with one of those and pokes this function; pg_cron pokes it again
// every minute while anything is due. We copy the bytes into the public
// `thumbs` bucket and point image_url at the copy. If the CDN URL is already
// dead we re-read the page's og:image first.
//
// Postgres is the caller, so this is authenticated by a shared token
// (THUMB_TOKEN, matched against the Vault secret the trigger reads) and
// deployed with verify_jwt = false. The service role is used only from here,
// to upload objects and call the thumb_* RPCs; it never reaches a client.
//
// Nothing in here can affect a save: by the time we run, the client already
// has its 2xx from PostgREST. Every failure path releases the job with a
// reason and a backoff, and the next drain tries again.

import { checkURL, pageImage, readBytes, USER_AGENT } from "../_shared/fetchguard.ts";

const MAX_IMAGE_BYTES = 1_500_000;   // the bucket enforces 2MB as a backstop
const IMAGE_TIMEOUT_MS = 10_000;
const DRAIN_MAX = 8;                 // × ~30s worst case ÷ pool of 3 stays under the wall clock
const POOL = 3;
const SETTLE_MS = 8_000;             // see apply(): let the client stamp its sync cursor first
const BUCKET = "thumbs";

// Mirrors public.thumb_is_expiring() in 0008_thumbs.sql — widen both together.
function urlExpires(u: string | null | undefined, base: string): boolean {
  if (!u || u.startsWith(`${base}/`)) return false;
  let host = "";
  try { host = new URL(u).hostname.toLowerCase(); } catch { return false; }
  if (/(^|\.)(cdninstagram\.com|fbcdn\.net|tiktokcdn(-[a-z0-9]+)?\.com)$/.test(host)) return true;
  if (/^https:\/\/pbs\.twimg\.com\/card_img\//.test(u)) return true;
  return /[?&](oe|oh|x-expires|x-amz-expires)=/i.test(u);
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/* JPEG, PNG, WebP or GIF by magic bytes. Headers lie, error pages are HTML,
   and an SVG served from our origin would be script — so only these four. */
function sniff(b: Uint8Array): string | null {
  if (b.length < 12) return null;
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) return "image/webp";
  if (b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x38) return "image/gif";
  return null;
}

type Download = { bytes: Uint8Array; type: string } | { error: string };

async function download(raw: string): Promise<Download> {
  const url = checkURL(raw);
  if (!url) return { error: "bad-url" };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), IMAGE_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      redirect: "follow",
      signal: controller.signal,
      headers: { "User-Agent": USER_AGENT, Accept: "image/*" },
    });
    if (!checkURL(res.url || url.href)) return { error: "redirect-refused" };
    if (!res.ok) return { error: `http-${res.status}` };     // an expired signature is a 403 here
    if (Number(res.headers.get("content-length") || 0) > MAX_IMAGE_BYTES) return { error: "too-large" };
    const bytes = await readBytes(res, MAX_IMAGE_BYTES + 1);
    if (bytes.length > MAX_IMAGE_BYTES) return { error: "too-large" };
    const type = sniff(bytes);
    if (!type) return { error: "not-image" };
    return { bytes, type };
  } catch (e) {
    return { error: e instanceof Error && e.name === "AbortError" ? "timeout" : "fetch-failed" };
  } finally {
    clearTimeout(timer);
  }
}

/* One object per bookmark, always at the same name, so re-runs overwrite
   rather than accumulate. */
async function objectPath(owner: string, id: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(id));
  const hex = [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return `${owner}/${hex}`;
}

class Backend {
  constructor(readonly base: string, readonly key: string) {}

  private headers(extra: Record<string, string> = {}) {
    return { apikey: this.key, Authorization: `Bearer ${this.key}`, ...extra };
  }

  async rpc<T>(name: string, args: Record<string, unknown>): Promise<T> {
    const r = await fetch(`${this.base}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: this.headers({ "Content-Type": "application/json" }),
      body: JSON.stringify(args),
    });
    const text = await r.text();
    if (!r.ok) throw new Error(`${name} ${r.status} ${text.slice(0, 200)}`);
    return (text ? JSON.parse(text) : null) as T;
  }

  async upload(path: string, bytes: Uint8Array, type: string): Promise<string | null> {
    const r = await fetch(`${this.base}/storage/v1/object/${BUCKET}/${path}`, {
      method: "POST",
      headers: this.headers({
        "Content-Type": type,
        "Cache-Control": "max-age=31536000, immutable",
        "x-upsert": "true",
      }),
      body: bytes,
    });
    if (r.ok) return null;
    return `upload-${r.status} ${(await r.text()).slice(0, 120)}`;
  }

  publicURL(path: string) {
    return `${this.base}/storage/v1/object/public/${BUCKET}/${path}`;
  }
}

type Job = {
  owner_id: string; bookmark_id: string; source_url: string; page_url: string;
  image_url: string | null; deleted: boolean; attempts: number; enqueued_at: string;
};

type Outcome = {
  id: string; status: "done" | "skipped" | "failed";
  via?: "direct" | "refetch" | "refetch-permanent"; bytes?: number; applied?: number; error?: string; ms: number;
};

async function processJob(be: Backend, job: Job): Promise<Outcome> {
  const started = Date.now();
  const { owner_id: owner, bookmark_id: id } = job;
  const out = (o: Omit<Outcome, "id" | "ms">): Outcome => ({ id, ...o, ms: Date.now() - started });
  const fail = async (error: string, status: string | null = null) => {
    await be.rpc("thumb_fail", { p_owner: owner, p_id: id, p_error: error, p_status: status }).catch(() => {});
    return out({ status: status === "skipped" ? "skipped" : "failed", error });
  };

  if (job.deleted) return fail("tombstoned", "skipped");
  // The trigger payload is a hint; the row is the truth and may have moved on.
  if (!urlExpires(job.image_url, be.base)) return fail("already-permanent", "skipped");

  let src = job.image_url as string;
  let via: Outcome["via"] = "direct";
  let got = await download(src);

  if ("error" in got) {
    // The CDN copy is gone; the page usually still advertises a fresh one.
    const page = checkURL(job.page_url);
    const fresh = page ? await pageImage(page) : null;
    if (!fresh) return fail(`direct:${got.error}; refetch:no-image`);
    src = fresh;
    if (!urlExpires(fresh, be.base)) {
      // Moved to a stable host — store the URL itself, nothing to copy.
      const applied = await be.rpc<number>("thumb_apply", {
        p_owner: owner, p_id: id, p_public_url: src, p_path: null, p_bytes: null, p_content_type: null,
      });
      return out({ status: "done", via: "refetch-permanent", applied });
    }
    via = "refetch";
    got = await download(src);
    if ("error" in got) return fail(`direct:dead; refetch:${got.error}`);
  }

  const path = await objectPath(owner, id);
  const uploadError = await be.upload(path, got.bytes, got.type);
  if (uploadError) return fail(uploadError);

  // The phone syncs push → pull → lastSynced = now. Our rewrite must land
  // after that stamp or the phone never pulls it, so give the client's write
  // a few seconds to finish its sync before bumping updated_at.
  const settle = SETTLE_MS - (Date.now() - Date.parse(job.enqueued_at));
  if (settle > 0) await sleep(settle);

  let applied = 0;
  try {
    applied = await be.rpc<number>("thumb_apply", {
      p_owner: owner, p_id: id, p_public_url: be.publicURL(path), p_path: path,
      p_bytes: got.bytes.length, p_content_type: got.type,
    });
  } catch (e) {
    return fail(`apply:${String(e).slice(0, 120)}`);
  }
  return out({ status: "done", via, bytes: got.bytes.length, applied });
}

/* Run jobs a few at a time; one failure never aborts the batch. */
async function drain(be: Backend, jobs: Job[]): Promise<Outcome[]> {
  const results: Outcome[] = [];
  let next = 0;
  const worker = async () => {
    while (next < jobs.length) {
      const job = jobs[next++];
      const r = await processJob(be, job).catch((e) =>
        ({ id: job.bookmark_id, status: "failed", error: String(e).slice(0, 120), ms: 0 } as Outcome));
      console.log(JSON.stringify(r));
      results.push(r);
    }
  };
  await Promise.all(Array.from({ length: Math.min(POOL, jobs.length) }, worker));
  return results;
}

addEventListener("unhandledrejection", (e) => { console.error("unhandled", e.reason); e.preventDefault(); });

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const token = Deno.env.get("THUMB_TOKEN");
  const base = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!token || !base || !serviceKey) {
    console.error("missing THUMB_TOKEN / SUPABASE_* environment");
    return json({ error: "Server misconfigured" }, 500);
  }
  if (req.headers.get("x-thumb-token") !== token) return json({ error: "no" }, 401);

  let body: { mode?: string; limit?: number; owner_id?: string; id?: string; wait?: boolean; reason?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }
  const be = new Backend(base, serviceKey);

  // One named job, synchronously — for tests and repairs.
  if (body.mode === "one") {
    if (typeof body.owner_id !== "string" || typeof body.id !== "string") {
      return json({ error: "owner_id and id required" }, 400);
    }
    const jobs = await be.rpc<Job[]>("thumb_claim", { p_limit: 1, p_owner: body.owner_id, p_id: body.id });
    if (!jobs.length) return json({ error: "no such job" }, 404);
    return json((await drain(be, jobs))[0]);
  }

  if (body.mode !== "drain") return json({ error: "mode must be drain or one" }, 400);

  const limit = Math.max(1, Math.min(DRAIN_MAX, Number(body.limit) || DRAIN_MAX));
  const jobs = await be.rpc<Job[]>("thumb_claim", { p_limit: limit, p_owner: null, p_id: null });
  if (body.wait) return json({ claimed: jobs.length, results: await drain(be, jobs) });

  // Answer pg_net now (its timeout is 8s); finish in the background.
  // deno-lint-ignore no-explicit-any
  (globalThis as any).EdgeRuntime?.waitUntil?.(drain(be, jobs));
  return json({ ok: true, claimed: jobs.length, reason: body.reason ?? null }, 202);
});
