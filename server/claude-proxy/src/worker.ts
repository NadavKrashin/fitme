// The Cloudflare Worker: real storage (Durable Objects), real App Attest checks and the real Anthropic API, wired
// into `handle`. Settings come from wrangler.toml [vars]; the API key and challenge secret are Worker secrets.
import Anthropic from "@anthropic-ai/sdk";
import { DurableObject } from "cloudflare:workers";
import rootPem from "./apple-app-attestation-root-ca.pem";
import { verifyAttestation, type AttestEnvironment, type AttestedKey } from "./attest";
import { DeviceRules } from "./device";
import { handle, type Config, type Dependencies, type DeviceVerdict } from "./handler";
import { addTokens, underDailyCap, type Allowance, type DailyRecord, type DeviceRecord } from "./ledger";
import type { Feature } from "./validate";

export interface Env {
  ANTHROPIC_API_KEY: string;
  CHALLENGE_SECRET: string;
  /** Team ID and bundle ID, comma-separated when one Worker serves several builds. */
  APP_IDS: string;
  ATTEST_ENVIRONMENTS: string;
  ALLOWED_MODELS: string;
  /** JSON: uses per device per month, e.g. {"tag":200,"stylist":60,"bag":20}. */
  ALLOWANCE: string;
  /** JSON allowance for devices without App Attest, or "" to require it (production). */
  UNATTESTED_ALLOWANCE: string;
  DAILY_TOKEN_CAP: string;
  /** "true" pauses every Claude call: the kill switch. */
  AI_PAUSED: string;
  DEVICES: DurableObjectNamespace<DeviceLedgerObject>;
  DAILY: DurableObjectNamespace<DailyLedgerObject>;
}

/** The server-side fallback beta the app opts into (see the app's ClaudeClient). */
const betas = ["server-side-fallback-2026-07-01"];

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handle(request, dependencies(env));
  },
} satisfies ExportedHandler<Env>;

function config(env: Env): Config {
  return {
    appIds: list(env.APP_IDS),
    attestEnvironments: list(env.ATTEST_ENVIRONMENTS) as AttestEnvironment[],
    allowedModels: list(env.ALLOWED_MODELS),
    allowance: JSON.parse(env.ALLOWANCE) as Allowance,
    unattestedAllowance: env.UNATTESTED_ALLOWANCE ? (JSON.parse(env.UNATTESTED_ALLOWANCE) as Allowance) : null,
    dailyTokenCap: Number(env.DAILY_TOKEN_CAP),
    paused: env.AI_PAUSED === "true",
    challengeSecret: env.CHALLENGE_SECRET,
    maxBodyBytes: 4_500_000,
  };
}

function dependencies(env: Env): Dependencies {
  const settings = config(env);
  const daily = () => env.DAILY.get(env.DAILY.idFromName("all-devices"));
  return {
    config: settings,
    device: (name) => env.DEVICES.get(env.DEVICES.idFromName(name)),
    underDailyCap: () => daily().underCap(settings.dailyTokenCap),
    addTokens: (tokens) => daily().add(tokens),
    async verifyAttestation(keyId, attestation, challenge) {
      let lastError: unknown;
      for (const appId of settings.appIds) {
        try {
          return await verifyAttestation({
            keyId,
            attestation,
            challenge,
            appId,
            environments: settings.attestEnvironments,
            rootPem,
          });
        } catch (cause) {
          lastError = cause;
        }
      }
      throw lastError;
    },
    async callClaude(body) {
      const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 1 });
      try {
        const params = { ...body, betas } as unknown as Anthropic.Beta.Messages.MessageCreateParamsNonStreaming;
        const message = await client.beta.messages.create(params);
        return { status: 200, body: message, tokens: message.usage.input_tokens + message.usage.output_tokens };
      } catch (cause) {
        if (cause instanceof Anthropic.APIError && typeof cause.status === "number") {
          return { status: cause.status, body: cause.error ?? { type: "error", error: { type: "api_error" } }, tokens: 0 };
        }
        throw cause;
      }
    },
  };
}

function list(value: string): string[] {
  return value
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

/** One per device, named by its App Attest key ID (or install ID on Staging). */
export class DeviceLedgerObject extends DurableObject<Env> {
  private rules(): DeviceRules {
    const settings = config(this.env);
    const storage = this.ctx.storage;
    return new DeviceRules(
      { get: () => storage.get<DeviceRecord>("record"), put: (record) => storage.put("record", record) },
      settings.allowance,
      settings.unattestedAllowance,
    );
  }

  register(key: AttestedKey): Promise<boolean> {
    return this.ctx.blockConcurrencyWhile(() => this.rules().register(key));
  }

  authorize(assertion: string, clientData: Uint8Array, feature: Feature, appIds: string[]): Promise<DeviceVerdict> {
    // Serialized, so two requests can't both pass with the same counter.
    return this.ctx.blockConcurrencyWhile(() => this.rules().authorize(assertion, clientData, feature, appIds));
  }

  authorizeUnattested(feature: Feature): Promise<DeviceVerdict> {
    return this.ctx.blockConcurrencyWhile(() => this.rules().authorizeUnattested(feature));
  }

  returnUse(feature: Feature): Promise<void> {
    return this.ctx.blockConcurrencyWhile(() => this.rules().returnUse(feature));
  }
}

/** One for everyone: tokens spent today, against the daily cap. */
export class DailyLedgerObject extends DurableObject<Env> {
  async underCap(cap: number): Promise<boolean> {
    return underDailyCap(await this.ctx.storage.get<DailyRecord>("today"), cap, new Date());
  }

  async add(tokens: number): Promise<void> {
    const storage = this.ctx.storage;
    await storage.put("today", addTokens(await storage.get<DailyRecord>("today"), tokens, new Date()));
  }
}
