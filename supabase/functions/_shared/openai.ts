// Shared OpenAI image caller. The key lives in the function environment —
// never in the iOS binary, same contract as `openrouter.ts`.
//
// Text generation in this project goes through OpenRouter; images do not,
// because OpenRouter is a chat-completions gateway and we want the image
// endpoint directly. That is the whole reason this file exists next to
// `openrouter.ts` rather than inside it.

export const IMAGE_MODEL = "gpt-image-1";

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

export function clayPrompt(name: string): string {
  const subject = subjectFrom(name);
  return [
    `Replace the subject of this illustration with a single object that represents the topic “${subject}”.`,
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

async function reference(): Promise<Blob | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REFERENCE_TIMEOUT_MS);
  try {
    const res = await fetch(REFERENCE_URL, { signal: controller.signal });
    if (!res.ok) return null;
    const blob = await res.blob();
    return blob.size > 0 && blob.size <= MAX_IMAGE_BYTES ? blob : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function callOpenAI(path: string, body: BodyInit, headers: Record<string, string>, key: string) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
  try {
    return await fetch(`https://api.openai.com/v1/${path}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, ...headers },
      body,
      signal: controller.signal,
    });
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
export async function clayImage(name: string): Promise<ImageResult> {
  const key = Deno.env.get("OPENAI_API_KEY");
  if (!key) {
    console.error("OPENAI_API_KEY is not set");
    return { error: "not-configured" };
  }

  const prompt = clayPrompt(name);
  const master = await reference();

  try {
    let response: Response;
    if (master) {
      const form = new FormData();
      form.append("model", IMAGE_MODEL);
      form.append("prompt", prompt);
      form.append("size", "1024x1024");
      form.append("n", "1");
      form.append("image", master, "reference.jpg");
      response = await callOpenAI("images/edits", form, {}, key);
    } else {
      response = await callOpenAI("images/generations", JSON.stringify({
        model: IMAGE_MODEL,
        prompt,
        size: "1024x1024",
        n: 1,
      }), { "Content-Type": "application/json" }, key);
    }

    if (!response.ok) {
      const detail = (await response.text()).slice(0, 200);
      console.error("openai", response.status, detail);
      // 401/403 is a key problem and retrying spends nothing but time.
      return { error: response.status === 401 || response.status === 403
        ? "not-authorised"
        : `http-${response.status}` };
    }

    return readImage(await response.json());
  } catch (e) {
    return { error: e instanceof Error && e.name === "AbortError" ? "timeout" : "fetch-failed" };
  }
}
