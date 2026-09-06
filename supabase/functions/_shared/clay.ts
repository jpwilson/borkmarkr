// Shared clay-scene image caller. The key lives in the function environment —
// never in the iOS binary, same contract as `openrouter.ts`.
//
// This goes through OpenRouter, on the same `OPENROUTER_API_KEY` as
// categorise and name-quest, so there is exactly one AI credential to deploy.
// It is a separate file from `openrouter.ts` because it speaks a different
// endpoint — the dedicated Image API at `/api/v1/images` rather than
// `/chat/completions` — not because it speaks to a different vendor.
//
// The model is unchanged: OpenRouter routes `openai/gpt-image-1` to OpenAI's
// own images endpoint, and `input_references` is that endpoint's edit path.
// Same model, same master, same prompt — so scenes drawn after this switch
// still match the ones drawn before it, which is the whole point of the
// locked style in Branding/ILLUSTRATION_STYLE.md.

export const IMAGE_MODEL = "openai/gpt-image-1";

const IMAGE_ENDPOINT = "https://openrouter.ai/api/v1/images";

/** The house style, verbatim from Branding/ILLUSTRATION_STYLE.md.
 *
 *  Kept as one constant so there is exactly one copy of the locked prompt in
 *  the codebase. If the style ever moves, it moves here and in that file
 *  together — the guide is the source of truth, this is the machine copy. */
const STYLE = [
  "Soft clay-3D editorial illustration for the iOS app bookmarker.",
  "Isolated subject, centered, generous cream paper background exactly #F6F3EE.",
  "Rounded friendly forms like a collectible toy or premium sticker.",
  "Gentle studio lighting, a small contact shadow under the object only.",
  "Palette: muted coral, sage, warm brown, terracotta, cream.",
  "No text, no letters, no numbers, no watermark, no frame, no logo,",
  "no drop shadow behind the whole canvas. One clear subject, generous margin.",
  // The all-ages rule. Every bundled scene is wholesome — a candle, a stack
  // of stones, two clay figures holding hands — and a topic someone types
  // can be anything. The subject is chosen by the judge below, but the
  // drawing model gets the rule too, so a slip upstream still draws kindly.
  "Wholesome, friendly and suitable for all ages: no violence, weapons, gore,",
  "drugs, alcohol, nudity, politics, religion or anything unkind or scary.",
  "If the topic is edgy, draw its gentlest everyday object.",
].join(" ");

/** The scene every new one is edited from. The guide is explicit that an
 *  independent `image_gen` drifts, so we start from a locked master and
 *  replace only the subject. Served by the marketing site, which is the same
 *  bitmap as `Branding/illustrations/questRabbit.jpg`. */
const REFERENCE_URL = "https://bookmarker.lol/img/quests/rabbit.jpg";

const REQUEST_TIMEOUT_MS = 60_000;   // image models are slow; this is not a page fetch
const REFERENCE_TIMEOUT_MS = 8_000;
const MAX_IMAGE_BYTES = 1_500_000;   // the bucket enforces 2MB as a backstop

/** A topic name is user input on its way into a model prompt, so it is
 *  fenced rather than interpolated raw: one line, no markup, length-capped,
 *  and quoted in the prompt so "ignore the above" reads as a subject, not an
 *  instruction. The model can still be silly about it; it cannot restyle. */
export function subjectFrom(name: string): string {
  return name
    .replace(/[\x00-\x1f\x7f]/g, " ")
    .replace(/["`\\]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 48);
}

/** What the drawing model is told to draw. `subject` is the judge's answer
 *  (one concrete object, already wholesome); `name` is the topic it stands
 *  for, kept in the prompt so the model knows what the object means. */
export function clayPrompt(name: string, subject: string): string {
  const topic = subjectFrom(name);
  const object = subjectFrom(subject) || topic;
  return [
    `Replace the subject of this illustration with: ${object} — a single object that represents the topic “${topic}”.`,
    "Keep the existing art style, background, lighting and palette exactly as they are.",
    "Draw only the new subject — do not keep the bird, the burrow or the charts.",
    STYLE,
  ].join(" ");
}

export type ImageResult = { bytes: Uint8Array; contentType: string } | { error: string };

function decodeBase64(b64: string): Uint8Array {
  const binary = atob(b64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

/** Chunked because `btoa(String.fromCharCode(...bytes))` spreads a megabyte
 *  of arguments onto the stack and throws. 0x8000 is the usual safe stride. */
function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

/** JPEG, PNG or WebP by magic bytes — headers lie and an error page is HTML.
 *  Mirrors `sniff()` in functions/thumb/index.ts, minus GIF, which the
 *  topic-art bucket does not accept. */
function sniff(b: Uint8Array): string | null {
  if (b.length < 12) return null;
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return "image/png";
  if (b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 &&
      b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50) return "image/webp";
  return null;
}

/** The master, as a data URL ready to hand to `input_references`.
 *
 *  We fetch it ourselves rather than passing `REFERENCE_URL` straight through
 *  so that an unreachable master degrades to a plain generation, the way the
 *  style guide allows, instead of failing the whole request. It also keeps
 *  the size cap ours. */
async function reference(): Promise<string | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REFERENCE_TIMEOUT_MS);
  try {
    const res = await fetch(REFERENCE_URL, { signal: controller.signal });
    if (!res.ok) return null;
    const bytes = new Uint8Array(await res.arrayBuffer());
    if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES) return null;
    const type = sniff(bytes);
    if (!type) return null;
    return `data:${type};base64,${encodeBase64(bytes)}`;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function readImage(payload: unknown): ImageResult {
  const b64 = (payload as { data?: { b64_json?: string }[] })?.data?.[0]?.b64_json;
  if (typeof b64 !== "string" || b64.length === 0) return { error: "no-image-in-reply" };
  let bytes: Uint8Array;
  try {
    bytes = decodeBase64(b64);
  } catch {
    return { error: "bad-base64" };
  }
  if (bytes.length > MAX_IMAGE_BYTES) return { error: "too-large" };
  // `media_type` comes back alongside the bytes, but the bucket only accepts
  // three types and a wrong Content-Type is a broken tile, so the bytes get
  // the last word here exactly as they did before.
  const contentType = sniff(bytes);
  if (!contentType) return { error: "not-image" };
  return { bytes, contentType };
}

/** Draw one topic scene.
 *
 *  Edit-from-master first, per the style guide. If the master can't be
 *  fetched we still draw — a scene generated from the style prompt alone is
 *  worth more than a blank tile, and it is the only case where drift is
 *  possible. Returns `{ error }` rather than throwing: every caller here
 *  degrades to no art, never to a failed topic. */
/** The judge. A topic is a word somebody typed — "Juice", "Retention",
 *  "Looksmaxxing" — and the drawing model is bad at deciding what a word
 *  *means* and worse at deciding what is kind to draw for it. So a language
 *  model decides first, from the name and a handful of the titles filed
 *  under it, and answers with one concrete everyday object. The rule in
 *  `STYLE` is repeated here because this is where the real choice is made.
 *  Returns null when the model can't answer; the caller falls back to the
 *  bare name, which is what happened before the judge existed. */
export async function judgeSubject(name: string, titles: string[]): Promise<string | null> {
  const { completeJSON } = await import("./openrouter.ts");
  const system = [
    "You choose what to draw for a topic in a bookmarking app.",
    "The illustration style is a soft clay-3D toy: one isolated everyday object on cream paper.",
    "You are given the topic's name and, when there are any, titles of links a person saved under it.",
    "Work out what the person means by the topic, then answer with ONE concrete, physical object",
    "(or a small pair of objects) that a stranger would recognise as that topic at a glance.",
    "Rules: wholesome, friendly, suitable for all ages — never weapons, violence, gore, drugs,",
    "alcohol, nudity, politics, religion, hate, or anything unkind, scary or mocking.",
    "If the topic is edgy or adult, choose its gentlest everyday object (a magnifying glass for",
    "conspiracies, a comb and hand mirror for looksmaxxing, a glass of orange juice for juice).",
    "No text on the object. No people's faces. No logos or brands.",
    "Answer as JSON: {\"subject\": \"<object, 3 to 12 words, e.g. a tall glass of orange juice with a paper straw>\"}.",
  ].join(" ");
  const user = [
    `Topic name: "${subjectFrom(name)}"`,
    titles.length ? "Some links saved under it:\n" + titles.slice(0, 12).map((t) => `- ${subjectFrom(t)}`).join("\n")
                  : "No links saved under it yet — go by the name.",
  ].join("\n");
  const answer = await completeJSON(system, user, 120) as { subject?: unknown } | null;
  const subject = typeof answer?.subject === "string" ? subjectFrom(answer.subject) : "";
  return subject.length >= 3 ? subject : null;
}

export async function clayImage(name: string, subject: string): Promise<ImageResult> {
  const key = Deno.env.get("OPENROUTER_API_KEY");
  if (!key) {
    console.error("OPENROUTER_API_KEY is not set");
    return { error: "not-configured" };
  }

  const master = await reference();
  const body: Record<string, unknown> = {
    model: IMAGE_MODEL,
    prompt: clayPrompt(name, subject),
    // gpt-image-1's 1:1 is the 1024x1024 the tiles were always drawn at.
    aspect_ratio: "1:1",
    n: 1,
  };
  if (master) {
    body.input_references = [{ type: "image_url", image_url: { url: master } }];
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(IMAGE_ENDPOINT, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://bookmarker.lol/",
        "X-Title": "bookmarker",
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });

    if (!response.ok) {
      const detail = (await response.text()).slice(0, 200);
      console.error("openrouter images", response.status, detail);
      // 401/403 is a key problem and retrying spends nothing but time.
      return { error: response.status === 401 || response.status === 403
        ? "not-authorised"
        : `http-${response.status}` };
    }

    return readImage(await response.json());
  } catch (e) {
    return { error: e instanceof Error && e.name === "AbortError" ? "timeout" : "fetch-failed" };
  } finally {
    clearTimeout(timer);
  }
}
