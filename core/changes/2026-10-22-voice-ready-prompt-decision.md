# Change record: voice "ready" prompt decision and editorial fixes (2026-10-22)

## What changed
- New `docs/v1/VOICE_READY_PROMPT_DECISION.md`: a set is started by a free-form affirmative answer to a "tell me when you are ready" prompt, active only in a waiting state; the bare word "go" is no longer the start command. Six proposed acceptance criteria.
- Editorial fixes from the round-2 documentation and code gates: criterion counts in `core/changes/2026-10-21-v1-module-matrix-and-specs.md` (14 and 7), the 30-day value in `docs/v1/LOCAL_QUEUE_DECISION.md` described as an aging-warning threshold, receipt-retention policy to be frozen in the implementation contract, and a corrected base reference in `core/changes/2026-10-21-firestore-negative-rules-tests.md`.

## Why
Operator answer of 2026-10-22 to the open voice-grammar question left by the hardening gate (PR 20): users say "start", "let's go", "okay" in their own style, so a fixed phrase list with "go" is the wrong design.

## Affected contracts and paths
Documentation only. No source, test, build or rules file changes. The parser in `voice_command.dart` is unchanged; the decision lands with the voice runtime.

## Verification state
Documentation; nothing was executed. No speech engine, language list or noise corpus has been measured.

## Gate round 1 remediation (GPT-PM: 0 BLOCKER, 3 MAJOR, 2 MINOR)
- Whole-utterance readiness with negation/deferral precedence and an in-state adversarial set of at least 20 utterances (was missing in-state negative tests).
- Microphone lifecycle: bounded window, visible indicator, context invalidation list, late/duplicate result rejection, no storage or out-of-window transmission.
- StartSet separated from the durable CompleteSet queue; exactly-once consumption of the waiting context.
- The "gap closed" wording changed to "intended to be closed, pending acceptance evidence".
- The decision-log entry for the Firestore rules deferral is now a separate entry with its own source.
