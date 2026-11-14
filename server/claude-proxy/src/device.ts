// A device ledger's rules over a storage interface: the Durable Object wraps this with real storage, the tests with a
// map. Every method runs as one step for its device (the Durable Object serializes them).
import { AttestError, verifyAssertion, type AttestedKey } from "./attest";
import type { DeviceLedger, DeviceVerdict } from "./handler";
import { newDevice, returnUse, takeUse, type Allowance, type DeviceRecord } from "./ledger";
import type { Feature } from "./validate";

export interface RecordStore {
  get(): Promise<DeviceRecord | undefined>;
  put(record: DeviceRecord): Promise<void>;
}

export class DeviceRules implements DeviceLedger {
  constructor(
    private readonly store: RecordStore,
    private readonly allowance: Allowance,
    private readonly unattestedAllowance: Allowance | null,
    private readonly now: () => Date = () => new Date(),
  ) {}

  async register(key: AttestedKey): Promise<boolean> {
    const record = await this.store.get();
    if (record?.key) return false;
    await this.store.put({ ...(record ?? newDevice(this.now())), key, counter: 0 });
    return true;
  }

  async authorize(assertion: string, clientData: Uint8Array, feature: Feature, appIds: string[]): Promise<DeviceVerdict> {
    const record = await this.store.get();
    if (!record?.key) return denied(401, "attestation_failed", "This key isn't registered. Attest again.");
    let counter: number | null = null;
    for (const appId of appIds) {
      try {
        counter = await verifyAssertion({
          assertion: Uint8Array.from(atob(assertion), (character) => character.charCodeAt(0)),
          clientData,
          publicKey: record.key.publicKey,
          appId,
          lastCounter: record.counter,
        });
        break;
      } catch (cause) {
        if (!(cause instanceof AttestError) && !(cause instanceof DOMException)) throw cause;
      }
    }
    if (counter === null) return denied(401, "attestation_failed", "The request's signature didn't check out.");
    return this.take({ ...record, counter }, feature, this.allowance);
  }

  async authorizeUnattested(feature: Feature): Promise<DeviceVerdict> {
    if (!this.unattestedAllowance) return denied(401, "attestation_required", "This app install isn't verified.");
    return this.take((await this.store.get()) ?? newDevice(this.now()), feature, this.unattestedAllowance);
  }

  async returnUse(feature: Feature): Promise<void> {
    const record = await this.store.get();
    if (record) await this.store.put(returnUse(record, feature));
  }

  private async take(record: DeviceRecord, feature: Feature, allowance: Allowance): Promise<DeviceVerdict> {
    const taken = takeUse(record, feature, allowance, this.now());
    if (!taken) {
      await this.store.put(record);
      return denied(429, "allowance_exceeded", "This month's AI allowance is used up. It resets on the 1st.");
    }
    await this.store.put(taken.record);
    return { ok: true, remaining: taken.remaining };
  }
}

function denied(status: number, type: string, message: string): DeviceVerdict {
  return { ok: false, status, type, message };
}
