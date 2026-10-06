import type { DocumentReference } from "firebase-admin/firestore";
import { adminDb } from "./firebase";
import { stringValue } from "./values";
import { log } from "./log";

export type TokenRecord = { token: string; ref: DocumentReference };

export async function loadFcmTokens(companyId: string, uid: string): Promise<TokenRecord[]> {
  const paths = [
    `users/${uid}/fcmTokens`,
    `companies/${companyId}/members/${uid}/fcmTokens`,
    `companies/${companyId}/users/${uid}/fcmTokens`,
    `companies/${companyId}/users/${uid}/devices`,
  ];
  const byToken = new Map<string, TokenRecord>();

  for (const path of paths) {
    try {
      const snapshot = await adminDb.collection(path).get();
      for (const document of snapshot.docs) {
        const data = document.data();
        if (data.enabled === false) continue;
        const token = stringValue(data.token ?? data.fcmToken ?? document.id);
        if (token.length > 20) byToken.set(token, { token, ref: document.ref });
      }
    } catch (error) {
      log.warn("Unable to read an FCM token collection.", { path, error: String(error) });
    }
  }
  return [...byToken.values()];
}

export async function deleteInvalidTokens(records: TokenRecord[], invalidTokens: Set<string>): Promise<number> {
  if (invalidTokens.size === 0) return 0;
  const batch = adminDb.batch();
  let count = 0;
  for (const record of records) {
    if (!invalidTokens.has(record.token)) continue;
    batch.delete(record.ref);
    count += 1;
  }
  if (count > 0) await batch.commit();
  return count;
}
