# Decision: `roboflow-key-reissue`

**Decision: ACCEPT THE RISK. Do not reissue.**

The Roboflow API key was pasted into a conversation on 2026-08-07
(`core/plans/B5_DATA_SOURCES_2026-08-07.md`) and no key literal has ever been committed to this
repository, at HEAD or anywhere in history (`scripts/review/state_ledger.py`'s
`roboflow_key_not_committed` re-verifies this on every run — the repository can prove the key is
not IN the tree, it cannot prove whether it was rotated in the Roboflow console).

## Who decided, and how

Recorded from a live, in-session exchange with the operator (the product's sole owner —
`korostelevivan@gmail.com`), 2026-09-17, in response to a direct question laying out the exposure:
the key sat in a chat transcript with no confirmed reissue since 2026-08-07. The operator's own
words: *"Риск незначителен, не буду перевыпускать"* ("the risk is insignificant, I will not
reissue").

## What this closes and what it does not

This closes the `roboflow-key-reissue` row in `core/CURRENT_STATE.md` as an operator decision, not
as a remediation — the key itself is unchanged, and if it was ever exposed to a third party via the
original conversation, that exposure is unaffected by this decision. Reopening this row later
(reissuing after all) needs a fresh operator action in the Roboflow console; nothing in this
repository can perform or observe that action either way.
