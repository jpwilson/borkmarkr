// Langfuse tracing for every model call: what was sent, what came back, how
// long it took, what it cost, and whether it failed — so the AI features,
// filing above all, can be checked and costed.
//
// Configured from the environment only, and both keys or nothing:
//
//   LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY
//   LANGFUSE_BASE_URL     default https://cloud.langfuse.com (LANGFUSE_HOST also works)
//   LANGFUSE_ENVIRONMENT  default "production"
//
// Without both keys this is a no-op and every function behaves exactly as it
// did before tracing existed.
//
// Tracing must never slow or break a request. A call's span is built once the
// model has answered, sent in the background (EdgeRuntime.waitUntil keeps the
// worker alive for it), abandoned after three seconds, and every error on the
// way is caught and logged, never thrown.
//
// No SDK and no dependency: this posts OTLP/HTTP JSON to
// /api/public/otel/v1/traces, which is Langfuse's supported way in. The older
// /api/public/ingestion batch API stops taking traces on Langfuse Cloud on
// 16 November 2026, so it is not used.
//
// What goes in is the request as sent (links, titles, captions) and the answer.
// Who asked never does: no user id, no email, and no IP, because the request
// to Langfuse comes from this server, not from the phone. docs/privacy.html
// says exactly this; widen one and you must widen the other.

const SEND_TIMEOUT_MS = 3_000;

type Attribute = { key: string; value: Record<string, unknown> };
type Settings = { endpoint: string; authorization: string; environment: string };

const text = (key: string, value: string): Attribute => ({ key, value: { stringValue: value } });

/** Langfuse parses a JSON string back into an object and keeps plain text as text. */
const serialise = (value: unknown): string => typeof value === "string" ? value : JSON.stringify(value);

/** OTLP times are nanoseconds as a decimal string; 1.7e18 is past a double's exact range. */
const nanos = (date: Date) => `${date.getTime()}000000`;

const randomHex = (bytes: number) =>
  [...crypto.getRandomValues(new Uint8Array(bytes))].map((b) => b.toString(16).padStart(2, "0")).join("");

function settings(): Settings | null {
  const publicKey = Deno.env.get("LANGFUSE_PUBLIC_KEY")?.trim();
  const secretKey = Deno.env.get("LANGFUSE_SECRET_KEY")?.trim();
  if (!publicKey || !secretKey) return null;
  const base = (Deno.env.get("LANGFUSE_BASE_URL") || Deno.env.get("LANGFUSE_HOST") || "https://cloud.langfuse.com")
    .trim()
    .replace(/\/+$/, "");
  return {
    endpoint: `${base}/api/public/otel/v1/traces`,
    authorization: `Basic ${btoa(`${publicKey}:${secretKey}`)}`,
    environment: Deno.env.get("LANGFUSE_ENVIRONMENT")?.trim() || "production",
  };
}

/** OpenRouter reports tokens the OpenAI way and what it charged as `cost`, in
 *  USD, on chat and image replies alike. Passing the cost through means
 *  Langfuse shows the bill rather than its own estimate from a price list. */
function usageAttributes(usage: unknown): Attribute[] {
  const reported = (usage ?? {}) as Record<string, unknown>;
  const tokens: Record<string, number> = {};
  for (const [from, to] of [["prompt_tokens", "input"], ["completion_tokens", "output"], ["total_tokens", "total"]]) {
    const count = reported[from];
    if (typeof count === "number") tokens[to] = count;
  }
  const attributes: Attribute[] = [];
  if (Object.keys(tokens).length > 0) {
    attributes.push(text("langfuse.observation.usage_details", JSON.stringify(tokens)));
  }
  if (typeof reported.cost === "number") {
    attributes.push(text("langfuse.observation.cost_details", JSON.stringify({ total: reported.cost })));
  }
  return attributes;
}

async function send(config: Settings, span: unknown): Promise<void> {
  try {
    const response = await fetch(config.endpoint, {
      method: "POST",
      headers: {
        Authorization: config.authorization,
        "Content-Type": "application/json",
        // Without it Langfuse may hold OTLP data back for up to ten minutes.
        "x-langfuse-ingestion-version": "4",
      },
      body: JSON.stringify({
        resourceSpans: [{
          resource: { attributes: [text("service.name", "bookmarker")] },
          scopeSpans: [{ scope: { name: "bookmarker" }, spans: [span] }],
        }],
      }),
      signal: AbortSignal.timeout(SEND_TIMEOUT_MS),
    });
    const reply = await response.text();
    if (!response.ok) console.warn("langfuse", response.status, reply.slice(0, 200));
  } catch (error) {
    console.warn("langfuse", error instanceof Error ? error.message : error);
  }
}

/** One model call, and the whole of its trace: the trace is named and tagged
 *  after the feature, and holds this one generation. Fill in what you learn as
 *  the call goes, then `end()` it exactly once; a `finally` is the place. */
export class Generation {
  readonly startedAt = new Date();
  /** The reply as it came back. For an image, a note of what arrived, not the bytes. */
  output?: unknown;
  /** OpenRouter's `usage`, verbatim. */
  usage?: unknown;
  /** Why the call failed, if it did. The span goes in as level ERROR. */
  error?: string;

  constructor(
    /** "categorize", "topic-art"… — the trace's name and its one tag. */
    readonly feature: string,
    readonly model: string,
    /** Exactly what the model was sent. */
    readonly input: unknown,
    readonly parameters: Record<string, unknown> = {},
  ) {}

  /** Sends the span in the background. Never throws, never waits. */
  end(): void {
    try {
      const config = settings();
      if (!config) return;
      const sending = send(config, this.span(new Date(), config.environment));
      (globalThis as any).EdgeRuntime?.waitUntil?.(sending);
    } catch (error) {
      console.warn("langfuse", error instanceof Error ? error.message : error);
    }
  }

  private span(endedAt: Date, environment: string) {
    const attributes: Attribute[] = [
      text("langfuse.trace.name", this.feature),
      { key: "langfuse.trace.tags", value: { arrayValue: { values: [{ stringValue: this.feature }] } } },
      text("langfuse.environment", environment),
      text("langfuse.observation.type", "generation"),
      text("langfuse.observation.model.name", this.model),
      text("langfuse.observation.model.parameters", JSON.stringify(this.parameters)),
      text("langfuse.observation.input", serialise(this.input)),
      ...(this.output === undefined ? [] : [text("langfuse.observation.output", serialise(this.output))]),
      ...usageAttributes(this.usage),
      ...(this.error
        ? [text("langfuse.observation.level", "ERROR"), text("langfuse.observation.status_message", this.error)]
        : []),
    ];
    return {
      traceId: randomHex(16),
      spanId: randomHex(8),
      name: this.feature,
      kind: 3, // CLIENT: a call out to another service
      startTimeUnixNano: nanos(this.startedAt),
      endTimeUnixNano: nanos(endedAt),
      attributes,
      ...(this.error ? { status: { code: 2, message: this.error } } : {}),
    };
  }
}
