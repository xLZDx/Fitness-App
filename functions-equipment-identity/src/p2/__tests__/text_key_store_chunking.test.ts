/**
 * FirestoreTextKeyStore.writeMany must never put more than the batch ceiling
 * into one Firestore batch (hard limit 500), and must still write every record.
 */
const batches: Array<{ sets: number; commit: jest.Mock }> = [];

jest.mock("../firestore_admin", () => ({
  db: () => ({
    collection: () => ({ doc: (id: string) => ({ id }) }),
    batch: () => {
      const b = { sets: 0, commit: jest.fn(async () => undefined) };
      batches.push(b);
      return {
        set: () => {
          b.sets += 1;
        },
        commit: b.commit,
      };
    },
  }),
}));

import {
  FirestoreTextKeyStore,
  TEXT_KEY_BATCH_SIZE,
  type DerivedTextKeyRecord,
} from "../text_key_index";

const records = (n: number): DerivedTextKeyRecord[] =>
  Array.from({ length: n }, (_, i) => ({
    catalogVersion: "v1",
    lookupKey: `key${i}`,
    modelId: "m1",
    keyKinds: ["ALIAS"],
  }));

beforeEach(() => {
  batches.length = 0;
});

describe("FirestoreTextKeyStore.writeMany chunking", () => {
  test("an empty list opens no batch", async () => {
    await new FirestoreTextKeyStore().writeMany([]);
    expect(batches).toHaveLength(0);
  });

  test("a list within the ceiling is one committed batch", async () => {
    await new FirestoreTextKeyStore().writeMany(records(TEXT_KEY_BATCH_SIZE));
    expect(batches.map((b) => b.sets)).toEqual([TEXT_KEY_BATCH_SIZE]);
    expect(batches[0].commit).toHaveBeenCalledTimes(1);
  });

  test("an oversized list is split, every batch is at most 450, and all records are written", async () => {
    await new FirestoreTextKeyStore().writeMany(records(1000));
    expect(TEXT_KEY_BATCH_SIZE).toBe(450);
    expect(batches.map((b) => b.sets)).toEqual([450, 450, 100]);
    for (const b of batches) expect(b.commit).toHaveBeenCalledTimes(1);
  });
});
