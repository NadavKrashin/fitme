// One-time challenges for attestation, without storage: a timestamp and random bytes, signed with a server secret.
// A challenge is good for five minutes.
import { base64ToBytes, bytesToBase64, concat, equal } from "./attest";

const lifetimeMs = 5 * 60 * 1000;

export async function makeChallenge(secret: string, now = Date.now()): Promise<string> {
  const body = concat(timestampBytes(now), crypto.getRandomValues(new Uint8Array(16)));
  return bytesToBase64(concat(body, await sign(secret, body)));
}

/** The challenge's bytes if it's ours and fresh; otherwise nil. */
export async function checkChallenge(secret: string, challenge: string, now = Date.now()): Promise<Uint8Array | null> {
  let bytes: Uint8Array;
  try {
    bytes = base64ToBytes(challenge);
  } catch {
    return null;
  }
  if (bytes.length !== 8 + 16 + 32) return null;
  const body = bytes.slice(0, 24);
  if (!equal(bytes.slice(24), await sign(secret, body))) return null;
  const issued = Number(new DataView(body.buffer).getBigUint64(0));
  return now - issued >= 0 && now - issued <= lifetimeMs ? bytes : null;
}

function timestampBytes(ms: number): Uint8Array {
  const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setBigUint64(0, BigInt(ms));
  return bytes;
}

async function sign(secret: string, data: Uint8Array): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, data));
}
