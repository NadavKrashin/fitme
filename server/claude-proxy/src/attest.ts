// App Attest, following Apple's "Validating apps that connect to your server": an attestation registers a device's
// key once; after that every request carries an assertion, a signature over the request body made with that key.
// @peculiar/x509 needs the Reflect metadata polyfill loaded before it.
import "reflect-metadata";
import * as x509 from "@peculiar/x509";
import { decode } from "cborg";

x509.cryptoProvider.set(crypto);

/** Apple's App Attest certificate extension holding the nonce. */
const nonceExtensionOID = "1.2.840.113635.100.8.2";

/** `aaguid` in the authenticator data: which App Attest environment issued the key. */
export type AttestEnvironment = "production" | "development";
const aaguids: Record<AttestEnvironment, string> = {
  production: "appattest\0\0\0\0\0\0\0",
  development: "appattestdevelop",
};

export class AttestError extends Error {}

export interface AttestedKey {
  /** The key as an uncompressed P-256 point, base64. */
  publicKey: string;
  /** Apple's receipt, kept in case fraud checks are added later. */
  receipt: string;
}

export interface AttestationInput {
  keyId: string;
  attestation: Uint8Array;
  challenge: Uint8Array;
  appId: string;
  environments: AttestEnvironment[];
  rootPem: string;
  now?: Date;
}

/** Checks a one-time attestation and returns the key to store. Throws `AttestError` on any mismatch. */
export async function verifyAttestation(input: AttestationInput): Promise<AttestedKey> {
  const object = decode(input.attestation) as {
    fmt?: string;
    attStmt?: { x5c?: Uint8Array[]; receipt?: Uint8Array };
    authData?: Uint8Array;
  };
  const x5c = object.attStmt?.x5c;
  const authData = object.authData;
  if (object.fmt !== "apple-appattest" || !x5c || x5c.length < 2 || !authData) {
    throw new AttestError("not an App Attest attestation");
  }

  // 1. The certificates chain to Apple's App Attestation root.
  const [leaf, intermediate] = x5c.map((der) => new x509.X509Certificate(der));
  const root = new x509.X509Certificate(input.rootPem);
  const date = input.now ?? new Date();
  const chained =
    (await leaf.verify({ publicKey: intermediate.publicKey, date })) &&
    (await intermediate.verify({ publicKey: root.publicKey, date }));
  if (!chained) throw new AttestError("certificate chain doesn't lead to Apple");

  // 2–4. The certificate's nonce is SHA-256(authData ‖ SHA-256(challenge)).
  const nonce = await sha256(concat(authData, await sha256(input.challenge)));
  const extension = leaf.getExtension(nonceExtensionOID);
  if (!extension || !equal(nonceFromExtension(new Uint8Array(extension.value)), nonce)) {
    throw new AttestError("nonce mismatch");
  }

  // 5. The key ID is the SHA-256 of the certificate's public key.
  const publicKey = await rawPublicKey(leaf);
  const keyId = base64ToBytes(input.keyId);
  if (!equal(await sha256(publicKey), keyId)) throw new AttestError("key ID doesn't match the certificate");

  // 6–9. The authenticator data names this app, starts at zero, comes from an accepted environment, and is for
  // this key.
  const data = parseAuthData(authData, true);
  if (!equal(data.rpIdHash, await sha256(new TextEncoder().encode(input.appId)))) {
    throw new AttestError("attestation is for another app");
  }
  if (data.counter !== 0) throw new AttestError("counter must start at zero");
  const environment = input.environments.find((name) => equal(data.aaguid ?? new Uint8Array(), ascii(aaguids[name])));
  if (!environment) throw new AttestError("App Attest environment not accepted");
  if (!data.credentialId || !equal(data.credentialId, keyId)) throw new AttestError("credential isn't this key");

  return {
    publicKey: bytesToBase64(publicKey),
    receipt: bytesToBase64(object.attStmt?.receipt ?? new Uint8Array()),
  };
}

export interface AssertionInput {
  assertion: Uint8Array;
  /** Exactly the bytes the app signed: the request body. */
  clientData: Uint8Array;
  publicKey: string;
  appId: string;
  /** The counter from the last accepted assertion (0 after attestation). */
  lastCounter: number;
}

/** Checks a request's assertion and returns its counter, which the caller must store. */
export async function verifyAssertion(input: AssertionInput): Promise<number> {
  const object = decode(input.assertion) as { signature?: Uint8Array; authenticatorData?: Uint8Array };
  if (!object.signature || !object.authenticatorData) throw new AttestError("not an App Attest assertion");

  const nonce = await sha256(concat(object.authenticatorData, await sha256(input.clientData)));
  const key = await crypto.subtle.importKey(
    "raw",
    base64ToBytes(input.publicKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const signed = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    derSignatureToRaw(object.signature),
    nonce,
  );
  if (!signed) throw new AttestError("signature doesn't match");

  const data = parseAuthData(object.authenticatorData, false);
  if (!equal(data.rpIdHash, await sha256(new TextEncoder().encode(input.appId)))) {
    throw new AttestError("assertion is for another app");
  }
  if (data.counter <= input.lastCounter) throw new AttestError("assertion replayed");
  return data.counter;
}

// MARK: Parsing

interface AuthData {
  rpIdHash: Uint8Array;
  counter: number;
  aaguid?: Uint8Array;
  credentialId?: Uint8Array;
}

/** rpIdHash (32) ‖ flags (1) ‖ counter (4) ‖ [aaguid (16) ‖ credential ID length (2) ‖ credential ID ‖ COSE key]. */
function parseAuthData(data: Uint8Array, attested: boolean): AuthData {
  if (data.length < 37) throw new AttestError("authenticator data too short");
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const result: AuthData = { rpIdHash: data.slice(0, 32), counter: view.getUint32(33) };
  if (attested) {
    if (data.length < 55) throw new AttestError("attested credential data missing");
    const length = view.getUint16(53);
    if (data.length < 55 + length) throw new AttestError("credential ID truncated");
    result.aaguid = data.slice(37, 53);
    result.credentialId = data.slice(55, 55 + length);
  }
  return result;
}

/** The extension is DER: SEQUENCE { [1] EXPLICIT OCTET STRING nonce }. */
function nonceFromExtension(value: Uint8Array): Uint8Array {
  const sequence = readTLV(value, 0);
  if (sequence.tag !== 0x30) throw new AttestError("malformed nonce extension");
  const tagged = readTLV(value, sequence.start);
  if (tagged.tag !== 0xa1) throw new AttestError("malformed nonce extension");
  const octets = readTLV(value, tagged.start);
  if (octets.tag !== 0x04) throw new AttestError("malformed nonce extension");
  return value.slice(octets.start, octets.end);
}

/** Apple signs with ECDSA in DER (SEQUENCE { INTEGER r, INTEGER s }); WebCrypto wants r ‖ s, 32 bytes each. */
export function derSignatureToRaw(der: Uint8Array): Uint8Array {
  const sequence = readTLV(der, 0);
  const r = readTLV(der, sequence.start);
  const s = readTLV(der, r.end);
  if (sequence.tag !== 0x30 || r.tag !== 0x02 || s.tag !== 0x02) throw new AttestError("malformed signature");
  const raw = new Uint8Array(64);
  raw.set(fixed32(der.slice(r.start, r.end)), 0);
  raw.set(fixed32(der.slice(s.start, s.end)), 32);
  return raw;
}

function fixed32(integer: Uint8Array): Uint8Array {
  let start = 0;
  while (start < integer.length - 1 && integer[start] === 0) start += 1;
  const trimmed = integer.slice(start);
  if (trimmed.length > 32) throw new AttestError("malformed signature");
  const out = new Uint8Array(32);
  out.set(trimmed, 32 - trimmed.length);
  return out;
}

/** One DER tag-length-value at `offset`: where its contents start and end. */
function readTLV(bytes: Uint8Array, offset: number): { tag: number; start: number; end: number } {
  if (offset + 2 > bytes.length) throw new AttestError("malformed DER");
  const tag = bytes[offset];
  let length = bytes[offset + 1];
  let start = offset + 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 3 || start + count > bytes.length) throw new AttestError("malformed DER");
    length = 0;
    for (let i = 0; i < count; i += 1) length = (length << 8) | bytes[start + i];
    start += count;
  }
  if (start + length > bytes.length) throw new AttestError("malformed DER");
  return { tag, start, end: start + length };
}

async function rawPublicKey(certificate: x509.X509Certificate): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "spki",
    certificate.publicKey.rawData,
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["verify"],
  );
  return new Uint8Array((await crypto.subtle.exportKey("raw", key)) as ArrayBuffer);
}

// MARK: Bytes

export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

export function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

export function equal(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i += 1) difference |= a[i] ^ b[i];
  return difference === 0;
}

function ascii(text: string): Uint8Array {
  return Uint8Array.from(text, (character) => character.charCodeAt(0));
}

export function base64ToBytes(text: string): Uint8Array {
  const binary = atob(text);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
