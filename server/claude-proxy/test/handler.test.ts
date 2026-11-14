import { beforeAll, describe, expect, it, vi } from "vitest";
import { verifyAttestation, type AttestedKey } from "../src/attest";
import { makeChallenge } from "../src/challenge";
import { DeviceRules } from "../src/device";
import { handle, type Config, type Dependencies } from "../src/handler";
import type { DeviceRecord } from "../src/ledger";
import { assertion, fakeApple, fakeDevice, type FakeApple } from "./fakeAppAttest";

const appId = "4ARX779852.io.github.nadavkrashin.fitme";
const installId = "6F9619FF-8B86-D011-B42D-00CF4FC964FF";

function config(overrides: Partial<Config> = {}): Config {
  return {
    appIds: [appId],
    attestEnvironments: ["production"],
    allowedModels: ["claude-opus-5-5"],
    allowance: { tag: 2, stylist: 2, bag: 2 },
    unattestedAllowance: null,
    dailyTokenCap: 1_000_000,
    paused: false,
    challengeSecret: "test secret",
    maxBodyBytes: 4_500_000,
    ...overrides,
  };
}

let apple: FakeApple;
beforeAll(async () => {
  apple = await fakeApple();
});

/** The real rules over in-memory storage, with Claude faked. */
function server(settings: Config, claude: Dependencies["callClaude"] = async () => ({ status: 200, body: { content: [] }, tokens: 100 })) {
  const records = new Map<string, DeviceRecord>();
  let tokensToday = 0;
  const deps: Dependencies = {
    config: settings,
    device: (name) =>
      new DeviceRules(
        { get: async () => records.get(name), put: async (record) => void records.set(name, record) },
        settings.allowance,
        settings.unattestedAllowance,
      ),
    underDailyCap: async () => tokensToday < settings.dailyTokenCap,
    addTokens: async (tokens) => void (tokensToday += tokens),
    verifyAttestation: (keyId, attestation, challenge): Promise<AttestedKey> =>
      verifyAttestation({ keyId, attestation, challenge, appId, environments: ["production"], rootPem: apple.rootPem }),
    callClaude: vi.fn(claude),
  };
  return { deps, records, tokens: () => tokensToday, fetch: (request: Request) => handle(request, deps) };
}

const body = JSON.stringify({
  model: "claude-opus-5-5",
  max_tokens: 1000,
  system: "You are a menswear stylist.",
  messages: [{ role: "user", content: [{ type: "text", text: "Candidates: A, B" }] }],
  output_config: { effort: "medium", format: { type: "json_schema", schema: { type: "object" } } },
  fallbacks: "default",
});

function messages(headers: Record<string, string>, payload = body): Request {
  return new Request("https://proxy.test/v1/messages", {
    method: "POST",
    headers: { "content-type": "application/json", "x-fitme-feature": "stylist", ...headers },
    body: payload,
  });
}

async function attestedDevice(fetch: (request: Request) => Promise<Response>) {
  const challengeResponse = await fetch(new Request("https://proxy.test/v1/attest/challenge"));
  const { challenge } = (await challengeResponse.json()) as { challenge: string };
  const challengeBytes = Uint8Array.from(atob(challenge), (c) => c.charCodeAt(0));
  const device = await fakeDevice(apple, { appId, challenge: challengeBytes });
  const response = await fetch(
    new Request("https://proxy.test/v1/attest", {
      method: "POST",
      body: JSON.stringify({ keyId: device.keyId, attestation: btoa(String.fromCharCode(...device.attestation)), challenge }),
    }),
  );
  expect(response.status).toBe(204);
  return device;
}

describe("the proxy", () => {
  it("serves an attested device, counts its uses, and refuses replays", async () => {
    const proxy = server(config());
    const device = await attestedDevice(proxy.fetch);
    const signed = await assertion(device, appId, 1, new TextEncoder().encode(body));

    const reply = await proxy.fetch(messages({ "x-fitme-key-id": device.keyId, "x-fitme-assertion": signed }));
    expect(reply.status).toBe(200);
    expect(reply.headers.get("x-fitme-remaining")).toBe("1");
    expect(proxy.tokens()).toBe(100);

    const replay = await proxy.fetch(messages({ "x-fitme-key-id": device.keyId, "x-fitme-assertion": signed }));
    expect(replay.status).toBe(401);
    expect(proxy.deps.callClaude).toHaveBeenCalledTimes(1);
  });

  it("won't register the same key twice", async () => {
    const proxy = server(config());
    const device = await attestedDevice(proxy.fetch);
    const { challenge } = (await (await proxy.fetch(new Request("https://proxy.test/v1/attest/challenge"))).json()) as {
      challenge: string;
    };
    const again = await proxy.fetch(
      new Request("https://proxy.test/v1/attest", {
        method: "POST",
        body: JSON.stringify({ keyId: device.keyId, attestation: btoa(String.fromCharCode(...device.attestation)), challenge }),
      }),
    );
    expect(again.status).toBe(401); // the old attestation's nonce doesn't match a new challenge
  });

  it("refuses requests that aren't attested unless unattested use is allowed", async () => {
    const production = server(config());
    const refused = await production.fetch(messages({ "x-fitme-install-id": installId }));
    expect(refused.status).toBe(401);
    expect(((await refused.json()) as { error: { type: string } }).error.type).toBe("attestation_required");

    const staging = server(config({ unattestedAllowance: { tag: 1, stylist: 1, bag: 1 } }));
    expect((await staging.fetch(messages({ "x-fitme-install-id": installId }))).status).toBe(200);
    const over = await staging.fetch(messages({ "x-fitme-install-id": installId }));
    expect(over.status).toBe(429);
    expect(((await over.json()) as { error: { type: string } }).error.type).toBe("allowance_exceeded");
  });

  it("gives the use back when Claude fails", async () => {
    const staging = server(config({ unattestedAllowance: { tag: 1, stylist: 1, bag: 1 } }), async () => ({
      status: 529,
      body: { type: "error", error: { type: "overloaded_error", message: "Overloaded" } },
      tokens: 0,
    }));
    expect((await staging.fetch(messages({ "x-fitme-install-id": installId }))).status).toBe(529);
    expect(staging.records.get(`install:${installId}`)?.used.stylist).toBe(0);
  });

  it("stops at the daily cap and when paused, without calling Claude", async () => {
    const capped = server(config({ unattestedAllowance: { tag: 9, stylist: 9, bag: 9 }, dailyTokenCap: 0 }));
    const atCap = await capped.fetch(messages({ "x-fitme-install-id": installId }));
    expect(atCap.status).toBe(503);
    expect(capped.records.get(`install:${installId}`)?.used.stylist).toBe(0);

    const paused = server(config({ paused: true }));
    expect((await paused.fetch(messages({ "x-fitme-install-id": installId }))).status).toBe(503);
    expect(capped.deps.callClaude).not.toHaveBeenCalled();
    expect(paused.deps.callClaude).not.toHaveBeenCalled();
  });

  it("rejects requests the app wouldn't send", async () => {
    const staging = server(config({ unattestedAllowance: { tag: 9, stylist: 9, bag: 9 } }));
    const withTools = JSON.stringify({ ...JSON.parse(body), tools: [{ name: "x" }] });
    expect((await staging.fetch(messages({ "x-fitme-install-id": installId }, withTools))).status).toBe(400);
    expect((await staging.fetch(messages({ "x-fitme-install-id": installId, "x-fitme-feature": "chat" }))).status).toBe(400);
  });

  it("issues challenges that it accepts", async () => {
    const challenge = await makeChallenge("test secret");
    expect(challenge.length).toBeGreaterThan(40);
  });
});
