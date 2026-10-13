# Change record: stale auth snapshot in the interrupted-wipe sweep (GPT-PM round 2, R2-01)

**Finding (MAJOR, verified).** The sweep captured the signed-in uid when an auth event queued it. A run delayed behind an earlier one could therefore act on a stale value: pending {B}, auth null (sweep queued), auth B, the first run still holds "signed out" and wipes B, who is now signed in.

**Change.**
- `local_data_wipe.dart`: `finishInterruptedWipe` takes an optional `currentUid` callback, asked immediately before each wipe and winning over `signedInUid`.
- `account_deletion_providers.dart`: queued runs no longer capture the uid. Each run reads the live auth state when it executes, skips itself when auth has no value yet (a later emission re-runs the sweep), and passes `currentUid` reading the live value.

**Tests (test agent).** account_deletion directory: 67 passed. New: provider-level pending {X, B} with the wipe gated on X, auth null then B, B never wiped and stays pending; `currentUid` beats a stale `signedInUid` in both directions; `currentUid` consulted before every wipe. The guard was not mutated to prove the tests fail without it (policy: no mutation runs).

**Verification state.** Focused tests only. Nothing pushed.
