// A stand-in for Apple's App Attest: a test root and intermediate CA, and devices whose attestations and assertions
// are built exactly as Apple documents them. Only the root differs from production.
import "reflect-metadata";
import * as x509 from "@peculiar/x509";
import { encode } from "cborg";
import { bytesToBase64, concat, sha256 } from "../src/attest";

x509.cryptoProvider.set(crypto);

const notBefore = new Date("2025-01-01T00:00:00Z");
const notAfter = new Date("2035-01-01T00:00:00Z");
const ecdsa384 = { name: "ECDSA", namedCurve: "P-384" } as const;
const ecdsa256 = { name: "ECDSA", namedCurve: "P-256" } as const;

export interface FakeApple {
  rootPem: string;
  intermediate: x509.X509Certificate;
  intermediateKey: CryptoKey;
}

export async function fakeApple(): Promise<FakeApple> {
  const rootKeys = (await crypto.subtle.generateKey(ecdsa384, true, ["sign", "verify"])) as CryptoKeyPair;
  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01",
    name: "CN=Test App Attestation Root CA",
    notBefore,
    notAfter,
    keys: rootKeys,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-384" },
    extensions: [new x509.BasicConstraintsExtension(true, undefined, true)],
  });
  const intermediateKeys = (await crypto.subtle.generateKey(ecdsa384, true, ["sign", "verify"])) as CryptoKeyPair;
  const intermediate = await x509.X509CertificateGenerator.create({
    serialNumber: "02",
    subject: "CN=Test App Attestation CA 1",
    issuer: root.subject,
    notBefore,
    notAfter,
    signingKey: rootKeys.privateKey,
    publicKey: intermediateKeys.publicKey,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-384" },
    extensions: [new x509.BasicConstraintsExtension(true, 0, true)],
  });
  return { rootPem: root.toString("pem"), intermediate, intermediateKey: intermediateKeys.privateKey };
}

export interface FakeDevice {
  keyId: string;
  keys: CryptoKeyPair;
  attestation: Uint8Array;
}

export async function fakeDevice(
  apple: FakeApple,
  options: { appId: string; challenge: Uint8Array; environment?: "production" | "development"; nonce?: Uint8Array },
): Promise<FakeDevice> {
  const keys = (await crypto.subtle.generateKey(ecdsa256, true, ["sign", "verify"])) as CryptoKeyPair;
  const publicKey = new Uint8Array((await crypto.subtle.exportKey("raw", keys.publicKey)) as ArrayBuffer);
  const keyId = await sha256(publicKey);
  const aaguid = options.environment === "development" ? "appattestdevelop" : "appattest\0\0\0\0\0\0\0";
  const authData = concat(
    await sha256(utf8(options.appId)),
    Uint8Array.of(0x41),
    u32(0),
    utf8(aaguid),
    Uint8Array.of(0, keyId.length),
    keyId,
    Uint8Array.of(0xa5, 0x01, 0x02), // a COSE key starts here; the server doesn't read it
  );
  const nonce = options.nonce ?? (await sha256(concat(authData, await sha256(options.challenge))));
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03",
    subject: "CN=device",
    issuer: apple.intermediate.subject,
    notBefore,
    notAfter,
    signingKey: apple.intermediateKey,
    publicKey: keys.publicKey,
    signingAlgorithm: { name: "ECDSA", hash: "SHA-256" },
    extensions: [new x509.Extension("1.2.840.113635.100.8.2", false, concat(Uint8Array.of(0x30, 0x24, 0xa1, 0x22, 0x04, 0x20), nonce))],
  });
  const attestation = encode({
    fmt: "apple-appattest",
    attStmt: { x5c: [new Uint8Array(leaf.rawData), new Uint8Array(apple.intermediate.rawData)], receipt: Uint8Array.of(1, 2, 3) },
    authData,
  });
  return { keyId: bytesToBase64(keyId), keys, attestation };
}

/** An assertion over `clientData`, as the app makes one per request. */
export async function assertion(device: FakeDevice, appId: string, counter: number, clientData: Uint8Array): Promise<string> {
  const authenticatorData = concat(await sha256(utf8(appId)), Uint8Array.of(0x01), u32(counter));
  const nonce = await sha256(concat(authenticatorData, await sha256(clientData)));
  const raw = new Uint8Array(
    (await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, device.keys.privateKey, nonce)) as ArrayBuffer,
  );
  return bytesToBase64(encode({ signature: rawToDer(raw), authenticatorData }));
}

/** r ‖ s to DER, as Apple's devices produce it. */
export function rawToDer(raw: Uint8Array): Uint8Array {
  const integer = (bytes: Uint8Array) => {
    let start = 0;
    while (start < bytes.length - 1 && bytes[start] === 0) start += 1;
    const trimmed = bytes.slice(start);
    const padded = trimmed[0] & 0x80 ? concat(Uint8Array.of(0), trimmed) : trimmed;
    return concat(Uint8Array.of(0x02, padded.length), padded);
  };
  const body = concat(integer(raw.slice(0, 32)), integer(raw.slice(32)));
  return concat(Uint8Array.of(0x30, body.length), body);
}

export function utf8(text: string): Uint8Array {
  return new TextEncoder().encode(text);
}

function u32(value: number): Uint8Array {
  const bytes = new Uint8Array(4);
  new DataView(bytes.buffer).setUint32(0, value);
  return bytes;
}
