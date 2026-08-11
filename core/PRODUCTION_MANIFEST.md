# Production manifest

**Generated 2026-08-12 02:50 local (E. Europe Daylight Time) / 2026-08-11 23:50 UTC** by `scripts/dev/production_manifest.py`.

Do not hand-edit: re-run the script. Every value below was read from a live API at that moment, or says `unavailable:` with the reason it could not be.

## Source tree this manifest was generated from

| Field | Value |
|---|---|
| Commit | `52818051212bf1506f7af70e1fe0a940dcfbde21` (`5281805`) |
| Branch | `master` |
| Working tree | DIRTY -- 3 uncommitted path(s) |

This is the LOCAL tree, not proof of what was deployed. Compare it against the function source generations below, which change on every deploy.

## Cloud Functions

14 deployed.

| Function | Platform | Region | Runtime | Source generation |
|---|---|---|---|---|
| `bookCoachSession` | gcfv2 | europe-west1 | nodejs20 | `1786459750064372` |
| `clipUrl` | gcfv2 | europe-west1 | nodejs20 | `1786459749764135` |
| `clipUrls` | gcfv2 | europe-west1 | nodejs20 | `1786459750001136` |
| `createCheckoutSession` | gcfv2 | europe-west1 | nodejs20 | `1786459749905895` |
| `createPortalSession` | gcfv2 | europe-west1 | nodejs20 | `1786459749721848` |
| `deleteAccount` | gcfv2 | europe-west1 | nodejs20 | `1786459749862047` |
| `exportAccountData` | gcfv2 | europe-west1 | nodejs20 | `1786459690851312` |
| `generateAnnualReceipt` | gcfv2 | europe-west1 | nodejs20 | `1786459749968379` |
| `optInDonorWall` | gcfv2 | europe-west1 | nodejs20 | `1786459749727417` |
| `optOutDonorWall` | gcfv2 | europe-west1 | nodejs20 | `1786459749751560` |
| `reportEquipment` | gcfv2 | europe-west1 | nodejs20 | `1786459749872875` |
| `startCoachOnboarding` | gcfv2 | europe-west1 | nodejs20 | `1786459749874653` |
| `startFreeTrial` | gcfv2 | europe-west1 | nodejs20 | `1786459749684022` |
| `stripeWebhook` | gcfv2 | europe-west1 | nodejs20 | `1786459749875272` |

## Firestore ruleset


| Release | Ruleset | Updated |
|---|---|---|
| `cloud.firestore` | `298949ea-bc19-4f70-a72c-c7a343510ebf` | 2026-08-05T12:32:14.064940Z |

## App Check enforcement


| Service | Enforcement | Updated |
|---|---|---|
| `firebaseml.googleapis.com` | **UNENFORCED** | 2026-08-07T22:18:33.818415Z |
| `firestore.googleapis.com` | **UNENFORCED** | 2026-08-05T14:26:48.336431Z |
| `identitytoolkit.googleapis.com` | **UNENFORCED** | 2026-08-05T14:26:47.403167Z |

## Hosting

| Field | Value |
|---|---|
| Release | `1786459779252000` |
| Version | `3ab6ffd44614d492` |
| Status | FINALIZED |
| Created | 2026-08-11T14:48:05.317400Z |

