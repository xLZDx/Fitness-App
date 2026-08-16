# 35 - Assessment of the first audit's disclosed omissions

Ten artefacts (the nine named in the README plus `FULL_PROJECT_AUDIT.json`) were dispositioned in
`34_OMITTED_ARTEFACT_DISPOSITION.csv`.

## The result is worse than the README implies

The README justifies every omission with one reason: *"writing them would have meant presenting unread
territory as audited."* For four of the ten that is exactly right. For **five** it is not, because each
of those artefacts has a **mechanical half that required no judgement** and was producible from files
already read:

| Artefact | The judgement-free half that was skipped anyway |
|---|---|
| `15_PROGRAMME_INVENTORY.csv` | volume/progression table straight out of `ProgrammeSpec` |
| `16_FIREBASE_DATA_MAP.md` | collection -> field -> writer -> rule, all from files already read |
| `17_PRIVACY_DATA_INVENTORY.csv` | per-field collected/stored-where/erased-by |
| `18_TEST_INVENTORY.csv` | file, test count, suite, collected-or-not |
| `FULL_PROJECT_AUDIT.json` | a roll-up of artefacts that all already exist |

The honest disclosure was real and is to the first audit's credit. But "I could not judge X" was
applied to justify not producing "the facts about X", and those are different claims.

## One omission has a demonstrated cost

`16_FIREBASE_DATA_MAP.md` would have forced the question *"which rule governs each field this client
writes?"*. That question is precisely what surfaced **N03** - the device-local health split enforced
only by client code, with nothing in `firestore.rules` rejecting a `health` map on
`users/{uid}/profile/main` - and N03 was found in this review, not the first.

The others are gaps without a proven miss, which is not the same as gaps without a cost.

## Final tally

- `EQUIVALENT_COVERAGE_ELSEWHERE`: 2
- `PARTIAL_COVERAGE`: 3
- `UNAVAILABLE`: 1
- `TRUE_AUDIT_SHORTFALL`: 5 (of which one, `16_FIREBASE_DATA_MAP.md`, has a demonstrated missed finding)
