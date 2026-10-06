import { Timestamp } from "firebase-admin/firestore";

export function stringValue(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value.trim() : fallback;
}

export function boolValue(value: unknown, fallback = false): boolean {
  if (typeof value === "boolean") return value;
  if (typeof value === "string") return value.trim().toLowerCase() === "true";
  return fallback;
}

export function intValue(value: unknown, fallback: number): number {
  if (typeof value === "number" && Number.isFinite(value)) return Math.trunc(value);
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

export function timestampValue(value: unknown): Timestamp | null {
  if (value instanceof Timestamp) return value;
  if (value instanceof Date) return Timestamp.fromDate(value);
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    if (Number.isFinite(parsed)) return Timestamp.fromMillis(parsed);
  }
  if (typeof value === "number" && Number.isFinite(value)) return Timestamp.fromMillis(value);
  return null;
}

export function normalizedRole(value: unknown): string {
  return stringValue(value).toLowerCase().replace(/[^a-z0-9]/g, "");
}

export function safeData(value: unknown, fallback = ""): string {
  const text = stringValue(value, fallback);
  return text.length <= 4_000 ? text : text.slice(0, 4_000);
}
