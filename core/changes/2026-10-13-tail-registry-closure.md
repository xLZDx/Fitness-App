# Change record: tail closure registry update (2026-10-13)

**Change.** `core/state/TAIL_CLOSURE_REGISTRY.json`: the eight NEW-* engineering tails move to CLOSED_VERIFIED (NEW-WEAR to FIXED_UNVERIFIED because the Kotlin change cannot be compiled here); VER-01/04/05/07 are closed by development rule 8 (documentation/CI-only) as OUT_OF_SCOPE_APPROVED and marked not verified; NEW-STRIPE-CUSTOMER is retained by operator decision (tax retention), no code change. Backlog minors that were deliberately not fixed are listed in the registry outcome.

**Operator-only items still open.** EXT-01..06, CR-06, VER-02, FC-T1-T2; CR-04 (paid tier is client-gated) is carried as a release note.

**Verification state.** The registry parses as JSON; statuses rest on the focused tests and reviews recorded in the other 2026-10-13 change records. Nothing pushed.
