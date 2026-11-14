// Routes and rules, with storage and Anthropic injected (see worker.ts for the real ones, the tests for fakes).
//
//   GET  /v1/attest/challenge  -> { challenge }               a fresh, signed challenge
//   POST /v1/attest            { keyId, attestation, challenge } -> 204   registers a device's key
//   POST /v1/messages          Messages API body; headers name the feature and prove the device -> Claude's reply
//
// Errors use the Messages API's error shape, { type: "error", error: { type, message } }, so the app decodes them
// the same way as Anthropic's.
import type { AttestEnvironment, AttestedKey } from "./attest";
import { base64ToBytes } from "./attest";
import { checkChallenge, makeChallenge } from "./challenge";
import type { Allowance } from "./ledger";
import { isFeature, validateRequest, type Feature } from "./validate";

export interface Config {
  appIds: string[];
  attestEnvironments: AttestEnvironment[];
  allowedModels: string[];
  allowance: Allowance;
  /** Staging only: devices without App Attest (the Simulator) may call with an install ID, at this allowance. */
  unattestedAllowance: Allowance | null;
  dailyTokenCap: number;
  paused: boolean;
  challengeSecret: string;
  /** Largest request body accepted, in bytes. */
  maxBodyBytes: number;
}

export type DeviceVerdict =
  | { ok: true; remaining: number }
  | { ok: false; status: number; type: string; message: string };

/** One device's ledger. Each call is atomic for that device. */
export interface DeviceLedger {
  register(key: AttestedKey): Promise<boolean>;
  authorize(assertion: string, clientData: Uint8Array, feature: Feature, appIds: string[]): Promise<DeviceVerdict>;
  authorizeUnattested(feature: Feature): Promise<DeviceVerdict>;
  returnUse(feature: Feature): Promise<void>;
}

export interface Dependencies {
  config: Config;
  device(name: string): DeviceLedger;
  underDailyCap(): Promise<boolean>;
  addTokens(tokens: number): Promise<void>;
  verifyAttestation(keyId: string, attestation: Uint8Array, challenge: Uint8Array): Promise<AttestedKey>;
  /** Calls the Messages API; resolves to the status and JSON body to pass back. */
  callClaude(body: Record<string, unknown>): Promise<{ status: number; body: unknown; tokens: number }>;
}

export async function handle(request: Request, deps: Dependencies): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET" && url.pathname === "/v1/attest/challenge") {
    return Response.json({ challenge: await makeChallenge(deps.config.challengeSecret) });
  }
  if (request.method === "POST" && url.pathname === "/v1/attest") return attest(request, deps);
  if (request.method === "POST" && url.pathname === "/v1/messages") return messages(request, deps);
  return error(404, "not_found_error", "No such endpoint.");
}

async function attest(request: Request, deps: Dependencies): Promise<Response> {
  const body = (await request.json().catch(() => null)) as Record<string, unknown> | null;
  const { keyId, attestation, challenge } = body ?? {};
  if (typeof keyId !== "string" || typeof attestation !== "string" || typeof challenge !== "string") {
    return error(400, "invalid_request_error", "keyId, attestation and challenge are required.");
  }
  const fresh = await checkChallenge(deps.config.challengeSecret, challenge);
  if (!fresh) return error(401, "attestation_failed", "The challenge expired. Ask for a new one.");
  let key: AttestedKey;
  try {
    key = await deps.verifyAttestation(keyId, base64ToBytes(attestation), fresh);
  } catch (cause) {
    return error(401, "attestation_failed", `Attestation rejected: ${(cause as Error).message}.`);
  }
  if (!(await deps.device(`key:${keyId}`).register(key))) {
    return error(409, "attestation_failed", "This key is already registered.");
  }
  return new Response(null, { status: 204 });
}

async function messages(request: Request, deps: Dependencies): Promise<Response> {
  const { config } = deps;
  if (config.paused) return error(503, "ai_paused", "FitMe's AI features are paused for now.");

  const feature = request.headers.get("x-fitme-feature");
  if (!isFeature(feature)) return error(400, "invalid_request_error", "Unknown feature.");
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length > config.maxBodyBytes) return error(413, "request_too_large", "The request is too large.");
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return error(400, "invalid_request_error", "The body isn't JSON.");
  }
  const checked = validateRequest(parsed, feature, config.allowedModels);
  if (!checked.ok) return error(400, "invalid_request_error", `Not allowed: ${checked.reason}.`);

  const verdict = await authorize(request, bytes, feature, deps);
  if (!verdict.ledger) return verdict.response;
  if (!(await deps.underDailyCap())) {
    await verdict.ledger.returnUse(feature);
    return error(503, "daily_cap", "FitMe's AI is at capacity for today. Try again tomorrow.");
  }

  const reply = await deps.callClaude(checked.body).catch(() => null);
  if (!reply) {
    await verdict.ledger.returnUse(feature);
    return error(502, "api_error", "Couldn't reach Claude.");
  }
  if (reply.status >= 500 || reply.status === 429) await verdict.ledger.returnUse(feature);
  if (reply.tokens > 0) await deps.addTokens(reply.tokens);
  return Response.json(reply.body, {
    status: reply.status,
    headers: { "x-fitme-remaining": String(verdict.remaining) },
  });
}

type Authorization =
  | { ledger: DeviceLedger; remaining: number; response?: never }
  | { ledger?: never; remaining?: never; response: Response };

/** Attested devices sign the body; on Staging, a device without App Attest may use an install ID instead. */
async function authorize(
  request: Request,
  body: Uint8Array,
  feature: Feature,
  deps: Dependencies,
): Promise<Authorization> {
  const keyId = request.headers.get("x-fitme-key-id");
  const assertion = request.headers.get("x-fitme-assertion");
  const installId = request.headers.get("x-fitme-install-id");
  let ledger: DeviceLedger;
  let verdict: DeviceVerdict;
  if (keyId && assertion) {
    ledger = deps.device(`key:${keyId}`);
    verdict = await ledger.authorize(assertion, body, feature, deps.config.appIds);
  } else if (installId && deps.config.unattestedAllowance && /^[0-9A-Fa-f-]{36}$/.test(installId)) {
    ledger = deps.device(`install:${installId}`);
    verdict = await ledger.authorizeUnattested(feature);
  } else {
    return { response: error(401, "attestation_required", "This app install isn't verified.") };
  }
  if (!verdict.ok) return { response: error(verdict.status, verdict.type, verdict.message) };
  return { ledger, remaining: verdict.remaining };
}

export function error(status: number, type: string, message: string): Response {
  return Response.json({ type: "error", error: { type, message } }, { status });
}
