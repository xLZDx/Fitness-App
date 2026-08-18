# SPTR Marketing Site — Claim Register

**Date:** 2026-08-19 · **Build:** internal R&D prototype · **Verified against:** `78b24dc`
**Classes:** per Decision Pack v1.0 §02 — `exists` / `committed` / `hypothesis` / `never`

Every classified sentence on the page appears here with the evidence that supports it. Each entry
is anchored by its `data-i18n` key, which is also the `data-claim-class` carrier in the markup, so
this table can be regenerated from source rather than maintained by hand.

---

## EXISTS — true of the shipped build, sayable publicly today

| Key | Claim | Evidence |
|---|---|---|
| `subA` | Point your phone at it. SPTR helps identify the equipment and shows the exercises and instructions available for it. | Three recognition paths ship; catalogue of 69 equipment types; 1,887 exercises |
| `subB` | When SPTR uses words printed on a machine to make a match, it shows you the words it read, right next to the result. | `scannerReadOnMachine` = "Read on the machine: {arg0}", both locales; `machine_text_anchor.dart` |
| `s2aBody` | Aim at the machine you mean. SPTR reads the words printed on it, and looks at the machine itself. | Text anchor + cloud vision + on-device fallback; prompt instructs the model to use the machine nearest frame centre |
| `s2bBody` | It answers from a catalogue of 69 equipment types — in English and Russian, with the aliases people actually use. | `equipment.json` = 69 records; `equipment_aliases.json` carries EN **and** RU aliases for 69/69 ids |
| `s2cBody` | 1,887 exercises with steps and demonstration video, filtered against the injuries you tell it about. | 1,887 records; all 1,887 have ≥1 instruction step and a non-empty clip path; 1,527 carry contraindications used by `exercise_filter.dart` |
| `s3c` | A suggested next weight, derived from how the last sessions went. | `suggestNextWeight()` in `progression.dart`, wired into `workout_player_page.dart:1258` and tappable to copy |
| `s4Restraint` | When it is not sure, it says "Not sure — closest matches" and offers them. | `scannerNotSureClosest`, both locales |
| `s5aBody` | The machine gets a card of its own, marked "Not in the catalog yet", with your photo of it. | `machineCardNotInCatalogYet`; `machine_card.dart` stores the photo and a `MachineCardStatus` |
| `s5bBody` | Sightings of the same machine merge — "scanned 3 times". | `machineCardSeenTimes` plural form; sightings merge across gyms in `machine_card.dart` |
| `s6aBody` | Progress photos are encrypted on the device with a key in the hardware keystore, and excluded from device backups. | AES-256-GCM on-device encryption; hardware keystore; Android backup exclusion rules |
| `s6bBody` | A machine photo goes to Google's Gemini through Firebase to be identified. That is not on-device, and the app says so too. | `gemini_equipment_service.dart`; disclosed in `legalPrivacyBody` |
| `s6cBody` | No analytics, no third-party scripts, no cookies. | Verified by test: zero external requests across all cells and viewports |

### Nuances recorded against `exists` claims

- **`s2cBody` — video is streamed, not bundled.** `assets/exercises/` was removed from `pubspec.yaml`
  on 2026-08-04. Clips play through `VideoPlayerController.networkUrl` on a signed URL; a bundled
  poster (2,979 stills) paints instantly and remains if signing fails. The claim is true and
  network-dependent. **Never phrase it as "works offline".**
- **`s2bBody` — the catalogue is the ceiling, in every path.** The cloud prompt is pinned to ~75
  canonical names or `unknown`, and unresolvable answers are dropped rather than guessed. The site
  must never imply open-ended recognition; §5 of the page exists precisely to state the boundary.
- **`s6aBody` vs `s6bBody` must stay adjacent.** Progress photos are on-device; recognition photos
  are not. Separating them would let a reader generalise the first onto the second, which is the
  single most likely privacy over-read on this page.

---

## COMMITTED — not built; internal prototype only

Rendered in this build because it is internal. **None of these may appear publicly until built and
verified at source on the release commit.**

| Key | Claim | Blocking requirement |
|---|---|---|
| `subC` | Recognize the equipment now. When you come back to it, bring back the workout and the setup you saved for that machine. | `MRD-01`, `MRD-03`, `MRD-05` |
| `s3a` | What you lifted on this equipment last time, and when. | `MRD-01`. `grep -c equipmentId workout_log.dart = 0` — no equipment link exists at all |
| `s3b` | The setup you saved for it — seat, pad, pin, or whatever that machine actually has. | `MRD-03` + `MRD-04`. Recognition history is keyed by catalogue type, not physical unit |
| `s3Prov` | SPTR does not decide your settings. It shows you what you saved, and says when it saved it. | Same chain. Kept as a `committed` claim rather than dropped because provenance is the mitigation for the surveillance misread found in testing |

The wording of `s3b` was chosen deliberately: **"or whatever that machine actually has"**. Real
equipment carries numbered detents, lettered positions, unmarked holes, sliders or nothing, so the
copy must not promise "Seat 4 on every machine" and the schema must not assume `seatPosition: int`.

Note that the cheapest rung is closer than the roadmap assumed: equipment-*type* memory needs no
migration, because `WorkoutLogEntry` carries `exerciseId` and 1,384 of 1,887 exercises already carry
`equipmentId`. `s3a` at type level is a join; at machine level it is a new domain model.

---

## HYPOTHESIS — internal language only

| Key | Claim | Status |
|---|---|---|
| `s5cBody` | The equipment people actually stand in front of is what gets covered next. No promise about when. | The mechanism exists — cards, merged sightings, counts. Whether the loop closes depends on user density, which has never been measured. The "no promise about when" clause is load-bearing and must not be edited out |

---

## NEVER — prohibited regardless of build state

None of these appear on the page. Listed so the gate can check for them.

| Prohibited | Why |
|---|---|
| Recognises any machine in any gym | False. Every path terminates in a bounded catalogue |
| Any recognition accuracy percentage | The production cloud path has never been measured. The two circulating figures describe the on-device model and an unshipped 29-class variant |
| Counts your reps *(unqualified)* | True for four movements above the 0.80 holdout bar, false for the rest |
| Safest position · protects your knees · correct for your body | Health claim. Mechanical values describe a machine, not a body |
| It spots you · keeps you safe while lifting · watches your form for danger | The product does not do this. The brand name makes this the most likely misread, so the constraint is absolute |
| Works offline | Recognition needs the network, and so do the clips |

### Brand constraints applied in this build

The name is the highest-risk surface on the page. Applied here:

- the mark teaches quietly — `SPOTTER` collapses to `SPTR` once, with *short for Spotter* set small
  beneath, and the phrase "your digital spotter" appears nowhere;
- no image shows a lone lifter under load, physical rescue, or supervision of a heavy lift. The hero
  photograph is an *empty* machine — deliberately, since the risk lives in showing a body under a bar;
- the word "spot" is never used as a verb anywhere on the page.

---

## Regeneration

```bash
python - <<'PY'
import re, pathlib, html as H
s = pathlib.Path('public/index.html').read_text(encoding='utf-8')
for m in re.finditer(r'<(\w+)([^>]*data-claim-class="(\w+)"[^>]*)>(.*?)</\1>', s, re.S):
    key = re.search(r'data-i18n="([^"]+)"', m.group(2))
    txt = re.sub(r'\s+', ' ', H.unescape(re.sub(r'<[^>]+>', '', m.group(4)))).strip()
    print(f"{m.group(3):11s} | {key.group(1) if key else '-':12s} | {txt}")
PY
```

Current output: **17 classified claims — 12 `exists`, 4 `committed`, 1 `hypothesis`, 0 `never`.**
A claim added to the page without a class will not appear in that output, which is the intended
failure signal for the pre-public gate.
