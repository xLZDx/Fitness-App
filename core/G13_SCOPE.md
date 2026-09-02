# Gate G13 — review scope

**In scope: one defect, and one flake found while verifying it.**

1. **`RepCounter` had no ceiling on a repetition's duration.** Measured on an
   S23 on 2026-09-02: the thirteenth "repetition" of a real set ran to 980
   observed frames (~33s) against a set whose tempo readout averaged 1.9s. It
   completed, was scored against a target it had never been near (peak match
   0.072), and told the lifter they had missed the shape of a movement they had
   stopped performing half a minute earlier. `maxRepDurationMs` (20s, a stated
   PRODUCT_HEURISTIC) discards such a lap as `RepRejectReason.abandoned` and
   disarms the counter so it does not immediately reopen one.

2. **The three coach goldens were failing at random**, found while verifying (1)
   — 54% then 94% on the same unchanged test in consecutive runs. The backdrop
   photograph is chosen randomly and was never pinned; the goldens passed only
   while `Image.asset` was not resolving in widget tests. Seeded now.

**Not in scope, deliberately:**
- The alignment work of G12, already approved and pushed as `ce4231e`.
- The authored `squat.bottom` geometry. I checked it against the operator's own
  recorded rep before proposing a gate for it and withdrew: thigh/torso 0.817
  vs 0.839 measured, shin/torso 0.820 vs 0.808. Re-authoring would move it away
  from the measured body.
- Device confirmation of G12's alignment against a real body, which needs the
  operator present at a phone.

**Authorisation, stated plainly.** (1) was not in the operator's five-point
redesign spec. I put it to you as a roadmap question and the send failed —
`CHATGPT_SEND_UNCONFIRMED`, no user turn — and I did not resend. It proceeds on
the operator's standing autonomous mandate and comes to you here instead.

Acceptance: a stalled lap is discarded and does not count; a genuinely slow
repetition (a 5-3-5-3 tempo protocol, ~16s) still counts; the counter recovers
only after the lifter stands up; the goldens pass repeatedly rather than once.
Full suite green.
