import { describe, expect, it } from "vitest";
import { checkChallenge, makeChallenge } from "../src/challenge";
import { addTokens, newDevice, returnUse, takeUse, underDailyCap } from "../src/ledger";
import { validateRequest } from "../src/validate";

const models = ["claude-opus-5-5"];

/** A request shaped like the app's ClaudeClient sends. */
function request(content: unknown[], extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    model: "claude-opus-5-5",
    max_tokens: 16000,
    system: "You catalog clothing.",
    messages: [{ role: "user", content }],
    output_config: { effort: "low", format: { type: "json_schema", schema: { type: "object" } } },
    fallbacks: "default",
    ...extra,
  };
}
const photo = { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "/9j/4AAQ" } };
const text = { type: "text", text: "Tag this." };

describe("request validation", () => {
  it("accepts what the app sends", () => {
    expect(validateRequest(request([photo, text]), "tag", models).ok).toBe(true);
    expect(validateRequest(request([text]), "stylist", models).ok).toBe(true);
  });

  it.each([
    ["another model", request([text], { model: "claude-sonnet-5-5" }), "stylist"],
    ["tools", request([text], { tools: [] }), "stylist"],
    ["streaming", request([text], { stream: true }), "stylist"],
    ["too many tokens", request([text], { max_tokens: 64000 }), "stylist"],
    ["no schema", request([text], { output_config: { effort: "low" } }), "stylist"],
    ["a photo for the stylist", request([photo, text]), "stylist"],
    ["two photos to tag", request([photo, photo, text]), "tag"],
    ["a PNG", request([{ ...photo, source: { ...photo.source, media_type: "image/png" } }]), "tag"],
    ["two turns", { ...request([text]), messages: [{ role: "user", content: [text] }, { role: "assistant", content: [text] }] }, "stylist"],
  ] as const)("rejects %s", (_, body, feature) => {
    expect(validateRequest(body, feature, models).ok).toBe(false);
  });
});

describe("challenges", () => {
  it("are good for five minutes, and only ours", async () => {
    const now = Date.UTC(2026, 10, 14, 12);
    const challenge = await makeChallenge("secret", now);
    expect(await checkChallenge("secret", challenge, now + 60_000)).not.toBeNull();
    expect(await checkChallenge("secret", challenge, now + 6 * 60_000)).toBeNull();
    expect(await checkChallenge("another secret", challenge, now)).toBeNull();
    expect(await checkChallenge("secret", "not base64!", now)).toBeNull();
  });
});

describe("allowance", () => {
  const allowance = { tag: 2, stylist: 1, bag: 1 };
  const november = new Date("2026-11-14T10:00:00Z");

  it("counts uses per feature up to the allowance", () => {
    let record = newDevice(november);
    const first = takeUse(record, "tag", allowance, november);
    expect(first?.remaining).toBe(1);
    record = first!.record;
    record = takeUse(record, "tag", allowance, november)!.record;
    expect(takeUse(record, "tag", allowance, november)).toBeNull();
    expect(takeUse(record, "stylist", allowance, november)?.remaining).toBe(0);
  });

  it("starts over each month", () => {
    const record = takeUse(takeUse(newDevice(november), "tag", allowance, november)!.record, "tag", allowance, november)!.record;
    expect(takeUse(record, "tag", allowance, new Date("2026-12-01T00:00:00Z"))?.remaining).toBe(1);
  });

  it("gives a use back when Claude failed", () => {
    const record = takeUse(newDevice(november), "tag", allowance, november)!.record;
    expect(returnUse(record, "tag").used.tag).toBe(0);
  });

  it("caps tokens across everyone per day", () => {
    const today = addTokens(undefined, 900, november);
    expect(underDailyCap(today, 1000, november)).toBe(true);
    expect(underDailyCap(addTokens(today, 200, november), 1000, november)).toBe(false);
    expect(underDailyCap(addTokens(today, 200, november), 1000, new Date("2026-11-15T00:00:01Z"))).toBe(true);
  });
});
