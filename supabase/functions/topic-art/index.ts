// bookmarker — draw a clay scene for a topic somebody made up.
//
// The 50 built-in topics ship bundled art. A topic you add yourself cannot:
// nobody can bundle a picture for "Looksmaxxing" before anyone types it. So
// Browse shows those tiles blank, and this is what fills them — one image,
// generated once, in the locked house style (Branding/ILLUSTRATION_STYLE.md),
// stored in the public `topic-art` bucket.
//
// Two rules shape everything here:
//
//   1. **An image costs money.** `topic_art_begin` in 0010 is a claim, not a
//      cache lookup — it is taken before the model is called and released on
//      every failure path, so two devices, a retry loop and a double tap all
//      collapse onto one generation. The daily AI quota is consumed on top,
//      the same as categorise and name-quest.
//   2. **Art can never block a topic.** The phone has already inserted its
//      CustomTopic locally before it calls us; it is asking for a decoration.
//      Every failure returns 200 with `{ url: null }` and a reason, because a
//      topic with no art is exactly what the app looks like today.
//
// The gateway checks the JWT (no config.toml entry, so verify_jwt stays on)
// and we resolve the caller from that same token — you can only ever draw
// into your own library.

import { consumeQuota, json } from "../_shared/openrouter.ts";
import { clayImage } from "../_shared/openai.ts";

const DAILY_LIMIT = 200;   // shared with categorise/name-quest, per user per UTC day
const BUCKET = "topic-art";
const MAX_NAME = 80;

/** Mirrors CustomTopic.makeID in Core/CustomSubtopic.swift. Only ids of that
 *  shape are drawable: a built-in topic already has bundled art, and anything
 *  else is a client sending us something we did not design for. */
const TOPIC_ID = /^custom\.[a-z0-9]+(-[a-z0-9]+)*$/;

/** One object per topic, always at the same name, so a regenerate overwrites
 *  rather than accumulates. Same shape as thumb's objectPath. */
async function objectPath(owner: string, topicID: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(topicID));
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

type Claim = { outcome: "done" | "claimed" | "busy" | "failed"; public_url: string | null };

addEventListener("unhandledrejection", (e) => { console.error("unhandled", e.reason); e.preventDefault(); });

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return json({}, 200);
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const base = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !anonKey || !serviceKey) {
    console.error("missing SUPABASE_* environment");
    return json({ error: "Server misconfigured" }, 500);
  }

  const authorization = req.headers.get("Authorization") ?? "";
  if (!/^Bearer\s+\S+/i.test(authorization)) return json({ error: "Sign in first" }, 401);

  let payload: { id?: unknown; name?: unknown };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }

  const topicID = typeof payload.id === "string" ? payload.id.trim() : "";
  const name = typeof payload.name === "string" ? payload.name.trim().slice(0, MAX_NAME) : "";
  if (!TOPIC_ID.test(topicID)) return json({ error: "id must be a custom topic id" }, 400);
  if (name.length < 2) return json({ error: "name is required" }, 400);

  // Who is asking? The token says — nothing else is consulted.
  const who = await fetch(`${base}/auth/v1/user`, {
    headers: { apikey: anonKey, Authorization: authorization },
  });
  if (!who.ok) return json({ error: "Sign in first" }, 401);
  const user = await who.json() as { id?: string };
  if (typeof user.id !== "string" || user.id.length === 0) {
    return json({ error: "Sign in first" }, 401);
  }

  const be = new Backend(base, serviceKey);

  // Claim before spending. `done` short-circuits without touching the model,
  // which is also what makes this safe to call on every Browse appearance.
  let claim: Claim;
  try {
    const rows = await be.rpc<Claim[]>("topic_art_begin", {
      p_owner: user.id, p_topic_id: topicID, p_name: name,
    });
    claim = rows?.[0] ?? { outcome: "busy", public_url: null };
  } catch (e) {
    console.error("topic_art_begin", e);
    return json({ url: null, reason: "ledger-unavailable" });
  }

  if (claim.outcome === "done") return json({ url: claim.public_url, reason: "cached" });
  if (claim.outcome === "busy") return json({ url: null, reason: "busy" });
  if (claim.outcome === "failed") return json({ url: null, reason: "given-up" });

  // From here the claim is ours, so every exit must release it.
  const release = async (reason: string) => {
    await be.rpc("topic_art_fail", { p_owner: user.id, p_topic_id: topicID, p_error: reason })
      .catch((e) => console.error("topic_art_fail", e));
    return json({ url: null, reason });
  };

  if (!await consumeQuota(authorization, DAILY_LIMIT)) return release("quota");

  const drawn = await clayImage(name);
  if ("error" in drawn) {
    // `not-configured` means OPENAI_API_KEY was never set. Say so plainly in
    // the log — this is the one failure a deploy fixes rather than a retry.
    if (drawn.error === "not-configured") console.error("topic-art: OPENAI_API_KEY missing");
    return release(drawn.error);
  }

  const path = await objectPath(user.id, topicID);
  const uploadError = await be.upload(path, drawn.bytes, drawn.contentType);
  if (uploadError) {
    console.error("topic-art upload", uploadError);
    return release("upload-failed");
  }

  const url = be.publicURL(path);
  try {
    await be.rpc("topic_art_apply", {
      p_owner: user.id, p_topic_id: topicID, p_public_url: url, p_path: path,
      p_bytes: drawn.bytes.length, p_content_type: drawn.contentType,
    });
  } catch (e) {
    // The bytes are in the bucket and the URL is good; only the ledger is
    // behind. Hand the URL over — the next call re-claims and overwrites the
    // same object, which is wasteful but never wrong.
    console.error("topic_art_apply", e);
    return json({ url, reason: "applied-without-ledger" });
  }

  console.log(JSON.stringify({ topic: topicID, bytes: drawn.bytes.length, type: drawn.contentType }));
  return json({ url, reason: "generated" });
});
