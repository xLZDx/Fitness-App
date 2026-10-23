# Change record: platform facts for the v1 design (2026-10-23)

Base: master c945e9f8. Adds docs/v1/design/PLATFORM_FACTS_2026-10-23.md, the recorded result and evidence for the platform facts that the v1 design leans on (PRE_IMPLEMENTATION_CONDITIONS section 2 item 4). All commands were read-only; no live system was changed; only secret names are listed.

## Result (15 rows)
9 VERIFIED, 4 NOT VERIFIABLE FROM HERE, 2 CONTRADICTED.
- Contradicted: point-in-time recovery is DISABLED (versionRetentionPeriod 3600s, no backup schedules), so the protocol's 7-day minute-granular fallback and its deploy gate cannot pass yet; Firestore data-write audit logs are not enabled (no auditConfigs, no data-access entries in 30 days), so the authoritative write inventory does not exist yet.
- Verified: trigger SDK exposes before.createTime and before.updateTime (firebase-functions 6.6.0, firebase-admin 13.10.0); 2nd gen retry window 24 hours; TTL active on accountDeletionRetries; log bucket retention 30 days (_Default) and 400 days (_Required); Secret Manager enabled but no seal-key secret exists; waitForPendingWrites exists in cloud_firestore 6.3.0; no minimum-version gate and no device registry exist in the code; deleteAccount can host a begin-deletion step.
- Surprises: functions/src/index.ts:160-175 records an earlier decision against a deleted_accounts tombstone (data minimisation) that protocol 8.7 contradicts; the first step of deleteAccount (line 2573) cancels Stripe subscriptions irreversibly before any fence exists, so a begin step must reorder that.

## Affected contracts and paths
Documentation only. No code, rules or deployment changed. Nothing executed against production.
