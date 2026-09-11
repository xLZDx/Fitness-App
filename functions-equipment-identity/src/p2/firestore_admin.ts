/**
 * P2.G3 -- lazy per-call Firestore accessor, same reasoning as
 * abuse_guard.ts's own `db()` in the default codebase: a module-scope
 * `admin.firestore()` would make merely IMPORTING a p2 module reach for a
 * live Admin app, so a unit test that only exercises the pure parts (the
 * normalizer, the materializer) would be forced to initialize Firebase
 * Admin for no reason. Resolved per call instead, so `admin.initializeApp()`
 * only has to have happened by the time a caller actually does Firestore
 * I/O (index.ts at real deploy time, jest.e2e.setup.js in the e2e suite).
 */
import * as admin from "firebase-admin";

export const db = (): admin.firestore.Firestore => admin.firestore();
