// What each device has used this month, and what all devices have used today. Plain data and functions, so the
// Durable Objects that hold them stay thin and the rules are testable.
import type { AttestedKey } from "./attest";
import type { Feature } from "./validate";

export type Allowance = Record<Feature, number>;

export interface DeviceRecord {
  key?: AttestedKey;
  /** The counter of the last accepted assertion. */
  counter: number;
  /** "2026-11": uses reset when the month changes (UTC). */
  month: string;
  used: Partial<Record<Feature, number>>;
}

export function newDevice(now: Date): DeviceRecord {
  return { counter: 0, month: monthOf(now), used: {} };
}

export function monthOf(date: Date): string {
  return date.toISOString().slice(0, 7);
}

export function dayOf(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** Takes one use of `feature` if the allowance has room, and says how many are left. */
export function takeUse(
  record: DeviceRecord,
  feature: Feature,
  allowance: Allowance,
  now: Date,
): { record: DeviceRecord; remaining: number } | null {
  const current = record.month === monthOf(now) ? record : { ...record, month: monthOf(now), used: {} };
  const used = current.used[feature] ?? 0;
  if (used >= allowance[feature]) return null;
  return {
    record: { ...current, used: { ...current.used, [feature]: used + 1 } },
    remaining: allowance[feature] - used - 1,
  };
}

/** Gives a use back when Claude failed, so a server error doesn't cost the user. */
export function returnUse(record: DeviceRecord, feature: Feature): DeviceRecord {
  const used = record.used[feature] ?? 0;
  return used > 0 ? { ...record, used: { ...record.used, [feature]: used - 1 } } : record;
}

export interface DailyRecord {
  day: string;
  tokens: number;
}

/** Whether today's spend across every device is still under the cap. */
export function underDailyCap(record: DailyRecord | undefined, cap: number, now: Date): boolean {
  return !record || record.day !== dayOf(now) || record.tokens < cap;
}

export function addTokens(record: DailyRecord | undefined, tokens: number, now: Date): DailyRecord {
  const today = dayOf(now);
  return { day: today, tokens: (record?.day === today ? record.tokens : 0) + tokens };
}
