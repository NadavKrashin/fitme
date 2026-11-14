// Checks a Messages API request from the app before it's forwarded with FitMe's key. The app builds the prompts; the
// proxy only lets through the shapes the app actually sends, so a genuine install can't use the key as a general
// Claude endpoint beyond its allowance.

export const features = ["tag", "stylist", "bag"] as const;
export type Feature = (typeof features)[number];

export function isFeature(value: string | null): value is Feature {
  return features.includes(value as Feature);
}

/** The most a request may ask for. */
export const limits = {
  maxTokens: 16_000,
  systemChars: 12_000,
  textChars: 30_000,
  /** Base64 characters of one JPEG: about 3 MB of image. */
  imageChars: 4_000_000,
};

/** Images each feature may send: a photo to tag (and nothing else needs one). */
const imagesAllowed: Record<Feature, number> = { tag: 1, stylist: 0, bag: 0 };

const allowedKeys = new Set(["model", "max_tokens", "system", "messages", "output_config", "fallbacks"]);
const efforts = new Set(["low", "medium", "high"]);

export type ValidationResult = { ok: true; body: Record<string, unknown> } | { ok: false; reason: string };

export function validateRequest(body: unknown, feature: Feature, allowedModels: string[]): ValidationResult {
  if (!isObject(body)) return fail("body must be a JSON object");
  const extra = Object.keys(body).filter((key) => !allowedKeys.has(key));
  if (extra.length > 0) return fail(`unsupported fields: ${extra.sort().join(", ")}`);

  if (typeof body.model !== "string" || !allowedModels.includes(body.model)) return fail("model not allowed");
  const maxTokens = body.max_tokens;
  if (!Number.isInteger(maxTokens) || (maxTokens as number) < 1 || (maxTokens as number) > limits.maxTokens) {
    return fail("max_tokens out of range");
  }
  if (typeof body.system !== "string" || body.system.length > limits.systemChars) return fail("system too long");
  if (body.fallbacks !== undefined && body.fallbacks !== "default") return fail("fallbacks must be \"default\"");

  const output = body.output_config;
  if (!isObject(output) || !efforts.has(output.effort as string)) return fail("output_config.effort required");
  const format = output.format;
  if (!isObject(format) || format.type !== "json_schema" || !isObject(format.schema)) {
    return fail("output_config.format must be a JSON schema");
  }

  const messages = body.messages;
  if (!Array.isArray(messages) || messages.length !== 1) return fail("exactly one message");
  const message = messages[0];
  if (!isObject(message) || message.role !== "user" || !Array.isArray(message.content)) {
    return fail("the message must be the user's");
  }

  let images = 0;
  let textChars = 0;
  for (const block of message.content) {
    if (!isObject(block)) return fail("content blocks must be objects");
    if (block.type === "text" && typeof block.text === "string") {
      textChars += block.text.length;
    } else if (block.type === "image" && isJPEG(block.source)) {
      images += 1;
    } else {
      return fail("content must be text or a base64 JPEG");
    }
  }
  if (images > imagesAllowed[feature]) return fail(`too many images for ${feature}`);
  if (textChars > limits.textChars) return fail("text too long");

  return { ok: true, body };
}

function isJPEG(source: unknown): boolean {
  return (
    isObject(source) &&
    source.type === "base64" &&
    source.media_type === "image/jpeg" &&
    typeof source.data === "string" &&
    source.data.length <= limits.imageChars
  );
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function fail(reason: string): ValidationResult {
  return { ok: false, reason };
}
