/**
 * F94: the step 0 self-test. Every race test of epic 6a is meaningful only if
 * the fakes can really produce conflicts, retries, generation changes and
 * paused actors. This file proves that, with a control for each case.
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import { FakeBucket, Gate, firestoreInstance, fx, resetAll, store } from "./support/fakes";

const fs: any = firestoreInstance;
beforeEach(() => resetAll());

describe("F94 fake Firestore conflicts", () => {
  test("control: without interference the transaction body runs and commits once", async () => {
    store.set("c/a", { n: 1 });
    let runs = 0;
    await fs.runTransaction(async (tx: any) => {
      runs += 1;
      const s = await tx.get(fs.doc("c/a"));
      tx.set(fs.doc("c/a"), { n: s.data().n + 1 });
    });
    expect(runs).toBe(1);
    expect(fx.txRetries).toBe(0);
    expect(store.get("c/a")).toEqual({ n: 2 });
  });

  test("a write by a second actor between read and commit makes the transaction retry on fresh data", async () => {
    store.set("c/a", { n: 1 });
    let runs = 0;
    fx.afterTxRead = async (_p, attempt) => {
      if (attempt === 1) store.set("c/a", { n: 10 }); // the second actor
    };
    await fs.runTransaction(async (tx: any) => {
      runs += 1;
      const s = await tx.get(fs.doc("c/a"));
      tx.set(fs.doc("c/a"), { n: s.data().n + 1 });
    });
    expect(runs).toBe(2);
    expect(fx.txRetries).toBe(1);
    // The stale value (1 + 1) did not win.
    expect(store.get("c/a")).toEqual({ n: 11 });
  });

  test("two concurrent increments both apply (no lost update)", async () => {
    store.set("c/a", { n: 0 });
    let arrived = 0;
    let open!: () => void;
    const both = new Promise<void>((r) => { open = r; });
    fx.afterTxRead = async (_p, attempt) => {
      if (attempt !== 1) return;
      arrived += 1;
      if (arrived === 2) open();
      await both;
    };
    const inc = () => fs.runTransaction(async (tx: any) => {
      const s = await tx.get(fs.doc("c/a"));
      tx.set(fs.doc("c/a"), { n: s.data().n + 1 });
    });
    await Promise.all([inc(), inc()]);
    expect(store.get("c/a")).toEqual({ n: 2 });
    expect(fx.txRetries).toBeGreaterThanOrEqual(1);
  });

  test("a document deleted between read and commit forces a retry that sees it missing", async () => {
    store.set("c/a", { n: 1 });
    const seen: boolean[] = [];
    fx.afterTxRead = async (_p, attempt) => {
      if (attempt === 1) store.delete("c/a");
    };
    await fs.runTransaction(async (tx: any) => {
      const s = await tx.get(fs.doc("c/a"));
      seen.push(s.exists);
      if (!s.exists) tx.set(fs.doc("c/b"), { recreated: true });
    });
    expect(seen).toEqual([true, false]);
    expect(store.get("c/b")).toEqual({ recreated: true });
  });

  test("a document created between read and commit (read as absent) forces a retry", async () => {
    const seen: boolean[] = [];
    fx.afterTxRead = async (_p, attempt) => {
      if (attempt === 1) store.set("fence/u", { fenceAt: 1 });
    };
    await fs.runTransaction(async (tx: any) => {
      const s = await tx.get(fs.doc("fence/u"));
      seen.push(s.exists);
    });
    expect(seen).toEqual([false, true]);
  });

  test("endless contention ends in an error instead of a stale commit", async () => {
    store.set("c/a", { n: 0 });
    fx.afterTxRead = async () => { store.set("c/a", { n: Math.random() }); };
    await expect(fs.runTransaction(async (tx: any) => { await tx.get(fs.doc("c/a")); tx.set(fs.doc("c/z"), { x: 1 }); }))
      .rejects.toMatchObject({ code: "aborted" });
    expect(store.has("c/z")).toBe(false);
  });
});

describe("F94 gate hooks", () => {
  test("a gate pauses the actor until released", async () => {
    const bucket = new FakeBucket();
    const gate = new Gate("afterPromote");
    bucket.hook = async (phase, op, path) => {
      if (phase === "after" && op === "save" && path.startsWith("streams/")) await gate.hit();
    };
    let finished = false;
    const actor = bucket.file("streams/u/a/up.json.gz").save(Buffer.from("x"), { contentType: "application/gzip" })
      .then(() => { finished = true; });
    await gate.reached;
    await new Promise((r) => setTimeout(r, 20));
    expect(finished).toBe(false); // paused although the object is already promoted
    expect(bucket.keys("streams/")).toHaveLength(1);
    gate.release();
    await actor;
    expect(finished).toBe(true);
  });

  test("deadlock guard: a gate that is never released fails the actor", async () => {
    const gate = new Gate("never", 50);
    await expect(gate.hit()).rejects.toThrow("gate_timeout:never");
  });
});

describe("F94 fake bucket", () => {
  test("generation pinning: a replaced object answers 404 to a pinned read, an unpinned read sees the new bytes", async () => {
    const b = new FakeBucket();
    const g1 = b.put("q/x", Buffer.from("one"));
    const [meta] = await b.file("q/x").getMetadata();
    expect(String(meta.generation)).toBe(String(g1));
    const g2 = b.put("q/x", Buffer.from("two"));
    expect(g2).not.toBe(g1);
    await expect(b.file("q/x", { generation: g1 }).download()).rejects.toMatchObject({ code: 404 });
    const [bytes] = await b.file("q/x", { generation: g2 }).download();
    expect(bytes.toString()).toBe("two");
    expect(b.downloads.map((d) => d.generation)).toEqual([g1, g2]);
  });

  test("404 on missing objects, ignoreNotFound, prefix delete and signed URL record", async () => {
    const b = new FakeBucket();
    await expect(b.file("nope").getMetadata()).rejects.toMatchObject({ code: 404 });
    await expect(b.file("nope").delete()).rejects.toMatchObject({ code: 404 });
    await expect(b.file("nope").delete({ ignoreNotFound: true })).resolves.toBeDefined();
    b.put("p/1", Buffer.from("a"));
    b.put("p/2", Buffer.from("b"));
    b.put("pp/1", Buffer.from("c"));
    await b.deleteFiles({ prefix: "p/" });
    expect(b.keys()).toEqual(["pp/1"]);
    const [url] = await b.file("p/1").getSignedUrl({ version: "v4", action: "write", expires: 1 });
    expect(url).toContain("SIGNED_URL_SENTINEL");
    expect(b.signed[0].config.action).toBe("write");
  });

  test("failure injection and promotion by save", async () => {
    const b = new FakeBucket();
    b.failOn = (op) => (op === "save" ? Object.assign(new Error("boom"), { code: 500 }) : undefined);
    await expect(b.file("s/1").save(Buffer.from("x"), { contentType: "application/gzip" })).rejects.toMatchObject({ code: 500 });
    expect(b.keys()).toEqual([]);
    b.failOn = null;
    await b.file("s/1").save(Buffer.from("x"), { contentType: "application/gzip" });
    expect(b.keys()).toEqual(["s/1"]);
  });
});
