# SPTR Marketing Site -- Claim Register

**Generated from:** `core/marketing/claim_register.json` -- do not hand-edit this file, edit the JSON and run
`python scripts/marketing/claim_lint.py --write-register`.
**Verified against:** `78b24dc` -- last reviewed 2026-08-19

Two independent axes. `exists` does **not** imply `allowed` -- a true statement can still need
qualification, or simply belong to an internal build. Re-derive both axes for every claim; never
auto-map one from the other.

| Axis | Values |
|---|---|
| `state` (is it true?) | `exists`, `committed`, `hypothesis`, `never` |
| `gate` (may it be said publicly?) | `allowed`, `qualify`, `blocked`, `internal-only` |

## ALLOWED -- publishable today as worded

| Claim ID | State | Gate | Evidence | Qualification | Blocking dependency |
|---|---|---|---|---|---|
| `hero-a-mechanic` | `exists` | `allowed` | Three recognition paths ship (text anchor, cloud, on-device fallback); 69-type catalogue; 1,887 exercises | -- | -- |
| `hero-b-evidence` | `exists` | `allowed` | scannerReadOnMachine = "Read on the machine: {arg0}", both locales; machine_text_anchor.dart | -- | -- |
| `hero-media-provenance` | `exists` | `allowed` | Hero image is a crop of data/gym_photos_2026-07-30/20260730_141731.jpg; no app screenshot used anywhere on the page | -- | -- |
| `mechanic-no-setup` | `exists` | `allowed` | Recognition has no gym-side dependency: no nameplate stickers required, no gym onboarding flow exists in the codebase | -- | -- |
| `mechanic-point` | `exists` | `allowed` | machine_text_anchor.dart (text reading) + gemini_equipment_service.dart (visual recognition) | -- | -- |
| `mechanic-catalogue-size` | `exists` | `allowed` | equipment.json = 69 records; equipment_aliases.json carries EN and RU aliases for 69/69 ids | -- | -- |
| `evidence-restraint` | `exists` | `allowed` | scannerNotSureClosest = "Not sure -- closest matches", both locales | -- | -- |
| `evidence-photo-provenance` | `exists` | `allowed` | data/gym_photos_2026-07-30/20260730_135643.jpg, filename-dated 30 July 2026 | -- | -- |
| `unknown-machine-card` | `exists` | `allowed` | machineCardNotInCatalogYet; machine_card.dart stores the photo and a MachineCardStatus | -- | -- |
| `unknown-sighting-count` | `exists` | `allowed` | machineCardSeenTimes plural form; sightings merge across gyms in machine_card.dart | -- | -- |
| `privacy-recognition-upload` | `exists` | `allowed` | gemini_equipment_service.dart; disclosed in legalPrivacyBody | -- | -- |
| `privacy-no-trackers` | `exists` | `allowed` | Zero external requests confirmed across all cells and viewports in the render QA pass | -- | -- |
| `cta-no-company` | `exists` | `allowed` | legalPrivacyBody: 'There is no company and no nonprofit behind it'; app_en.arb/app_ru.arb both complete (1,101 keys each); PLATFORM_SCOPE.md -- Android supported, iOS not shipped | -- | -- |

## QUALIFY -- publishable only with the named condition attached

| Claim ID | State | Gate | Evidence | Qualification | Blocking dependency |
|---|---|---|---|---|---|
| `mechanic-exercise-library` | `exists` | `qualify` | 1,887 exercises, all with >=1 step and a non-empty video reference; 1,527 of 1,887 carry contraindications used by exercise_filter.dart | Injury filtering covers 1,527 of 1,887 exercises and is self-reported, not a medical screen; wording must say so before public use. Video is streamed from a signed URL, not bundled -- must not be phrased as 'works offline' | -- |
| `memory-last-lift` | `exists` | `qualify` | Gate D, 2026-08-19: summarizeEquipmentTypeHistory() in equipment_type_history.dart, wired into LastSessionCard (equipment/widgets/last_session_card.dart) on the equipment detail page. Matches exerciseId -> equipmentId client-side against workoutSessionHistoryProvider's windowed history; no Firestore schema change. See core/product/GATE_D_EQUIPMENT_TYPE_HISTORY_D0_NOTE_2026-08-19.md | Equipment-TYPE level only -- the same card shows for every gym's leg press, not one physical machine (that needs MRD-03/MRD-04, not built). Matched against the user's most recent logged workouts; a session older than that window is reported as 'not found in your recent workouts', never as 'no history' | -- |
| `memory-suggested-weight` | `exists` | `qualify` | suggestNextWeight() in progression.dart, wired into workout_player_page.dart:1258, tappable to copy the value | Derived from self-logged history, not personalised coaching or a medical recommendation; the app must say the user makes the final call | -- |
| `evidence-nameplate-prevalence` | `exists` | `qualify` | Nameplate mechanic verified to exist (machine_text_anchor.dart); prevalence bounded to ~28 of 69 registry types (selectorised strength machines) -- free weights and bodyweight can never carry one | Nameplate prevalence is bounded to ~28 of 69 registry types (selectorised strength machines); free weights and bodyweight equipment can never carry one. Exact prevalence is an open field study in the evidence backlog, not yet measured | -- |
| `privacy-progress-photo-encryption` | `exists` | `qualify` | AES-256-GCM on-device encryption, hardware keystore, Android backup exclusion rules | Verified against source architecture (hardware-backed secure storage, backup exclusion rules); not an independently audited security claim -- wording must not imply a third-party audit | -- |

## INTERNAL-ONLY -- Marketing R&D language, never public

| Claim ID | State | Gate | Evidence | Qualification | Blocking dependency |
|---|---|---|---|---|---|
| `hero-c-recurring` | `committed` | `internal-only` | grep -c equipmentId workout_log.dart = 0; recognition history keyed by catalogue type, not physical unit | -- | MRD-01, MRD-03, MRD-05 |
| `memory-setup` | `committed` | `internal-only` | Recognition history is keyed by catalogue equipmentId, not physical unit -- no per-machine setup storage exists | -- | MRD-03, MRD-04 |
| `memory-provenance` | `committed` | `internal-only` | Provenance framing for the same unbuilt feature as memory-last-lift / memory-setup | -- | MRD-01, MRD-03, MRD-04 |
| `unknown-coverage-queue` | `hypothesis` | `internal-only` | Mechanism (cards, merged sightings, counts) exists; whether the loop closes depends on user density, which has never been measured -- this is MRD-07 | -- | MRD-07 (measurement layer) |

---

## Enforcement

`scripts/marketing/claim_lint.py` fails closed: any marketing-copy node in `public/index.html` without
either `data-claim-id`/`data-claim-state`/`data-public-gate` or an explicit `data-nonclaim` exemption is a
lint failure, not a silent gap. It also fails on invalid enum values, forbidden state/gate combinations
(a `committed` or `hypothesis` claim marked `allowed`), duplicate claim IDs, drift between the markup and
this register, and a classified claim missing its Russian translation.

```
python scripts/marketing/claim_lint.py              # lint the live site
python scripts/marketing/claim_lint.py --self-test   # prove the lint actually catches mutations
```

## Never claims

None currently render, by rule -- `data-claim-state="never"` is rejected by the lint unconditionally, so
this is enforced structurally rather than by review discipline alone. The six phrases that must never
appear are documented in the implementation report rather than the register, since a `never` claim by
definition has no claim ID to register.
