import { beforeAll, describe, expect, it } from "vitest";
import { AttestError, derSignatureToRaw, verifyAssertion, verifyAttestation } from "../src/attest";
import appleRoot from "../src/apple-app-attestation-root-ca.pem?raw";
import { assertion, fakeApple, fakeDevice, rawToDer, utf8, type FakeApple } from "./fakeAppAttest";

const appId = "4ARX779852.io.github.nadavkrashin.fitme";
const challenge = utf8("a challenge from the server");

let apple: FakeApple;
beforeAll(async () => {
  apple = await fakeApple();
});

const check = (device: { keyId: string; attestation: Uint8Array }, overrides: Partial<Parameters<typeof verifyAttestation>[0]> = {}) =>
  verifyAttestation({
    keyId: device.keyId,
    attestation: device.attestation,
    challenge,
    appId,
    environments: ["production"],
    rootPem: apple.rootPem,
    ...overrides,
  });

describe("attestation", () => {
  it("accepts a genuine device and returns its key", async () => {
    const device = await fakeDevice(apple, { appId, challenge });
    const key = await check(device);
    expect(key.publicKey.length).toBeGreaterThan(80);
  });

  it("rejects a chain that doesn't lead to Apple's real root", async () => {
    const device = await fakeDevice(apple, { appId, challenge });
    await expect(check(device, { rootPem: appleRoot })).rejects.toThrow(AttestError);
  });

  it("rejects another challenge", async () => {
    const device = await fakeDevice(apple, { appId, challenge });
    await expect(check(device, { challenge: utf8("an old challenge") })).rejects.toThrow("nonce mismatch");
  });

  it("rejects another app", async () => {
    const device = await fakeDevice(apple, { appId: "SOMEONEELSE.com.example.app", challenge });
    await expect(check(device)).rejects.toThrow("another app");
  });

  it("rejects the development environment unless accepted", async () => {
    const device = await fakeDevice(apple, { appId, challenge, environment: "development" });
    await expect(check(device)).rejects.toThrow("environment");
    await expect(check(device, { environments: ["production", "development"] })).resolves.toBeDefined();
  });

  it("rejects a key ID that isn't the certificate's key", async () => {
    const device = await fakeDevice(apple, { appId, challenge });
    const other = await fakeDevice(apple, { appId, challenge });
    await expect(check({ ...device, keyId: other.keyId })).rejects.toThrow("key ID");
  });
});

describe("assertion", () => {
  it("accepts a signed request and returns its counter; rejects replays, edits and other apps", async () => {
    const device = await fakeDevice(apple, { appId, challenge });
    const { publicKey } = await check(device);
    const body = utf8('{"model":"claude-opus-5-5"}');
    const signed = Uint8Array.from(atob(await assertion(device, appId, 1, body)), (c) => c.charCodeAt(0));

    await expect(verifyAssertion({ assertion: signed, clientData: body, publicKey, appId, lastCounter: 0 })).resolves.toBe(1);
    await expect(verifyAssertion({ assertion: signed, clientData: body, publicKey, appId, lastCounter: 1 })).rejects.toThrow("replayed");
    await expect(
      verifyAssertion({ assertion: signed, clientData: utf8('{"model":"other"}'), publicKey, appId, lastCounter: 0 }),
    ).rejects.toThrow("signature");
    await expect(
      verifyAssertion({ assertion: signed, clientData: body, publicKey, appId: "X.other.app", lastCounter: 0 }),
    ).rejects.toThrow("another app");
  });

  it("reads DER signatures with and without padding bytes", () => {
    const raw = new Uint8Array(64);
    raw[0] = 0x80; // high bit set: DER pads r with a zero byte
    raw[32] = 0x01;
    raw[63] = 0x02;
    expect(derSignatureToRaw(rawToDer(raw))).toEqual(raw);
  });
});
