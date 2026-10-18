# AI Coach: route OQ-07 safety contract and sign-off gaps

Date: 2026-10-18. Documentation-only record of the read-only architect review of OQ-07.

## Why

OQ-07 combines technical load/repetition enforcement with decisions that require product/safety sign-off. The reviewed requirements and design do not clearly distinguish a proposed prescription from recording a set the user actually performed. Existing numeric helpers are heuristics, and the suggested clamp is explicitly unsigned. Recording this boundary and the exact technical deliverable prevents this review from inventing clinical policy or treating unsigned fixtures as approved values.

## Changes

- Updated `docs/ai-coach/acceptance.md` to keep OQ-07 OPEN, identify the assignment-versus-performed-fact contract gap, and distinguish TR review from named product/safety sign-off.
- Added the architect finding and technical routing deliverable to `docs/ai-coach/13_PHASE9_OQ_TECHNICAL_REVIEW.md`.
- Left limits, symptom scope/copy, requirements, implementation behavior, test-plan values and OQ disposition unchanged.

## Review evidence

The actual read-only `architect` review examined OQ-07 at source HEAD `4f2fe9cf1ffa0d0e29c69c2ab5af2afaea356ade`. It identified: (1) AICR-029 does not distinguish prescription validation from performed-set recording, while design §§4.1a and 9.4 state performed facts are not blocked by caps; (2) the proposed `suggestNextWeight * intensityCeiling` clamp is unsigned and existing eligibility/age/progression data are heuristics, not approved hard caps; (3) current G5/FT-1053 and G14/FT-3009 material is planned/blocked or uses unsigned fixtures; and (4) the symptom pause/lock gate is documented, but no signed symptom list or numeric policy is present. The full evidence and exact locations are in the review response and summarized in `docs/ai-coach/13_PHASE9_OQ_TECHNICAL_REVIEW.md` under “OQ-07 architect contract review”.

## Remaining acceptance and owners

TR must specify assignment-path enforcement, separate prescription ceilings from performed facts, structural-invalidity versus out-of-policy outcomes, typed behavior, the versioned authoritative policy source and test-oracle mapping. A product/safety signer must supply the actual limits and symptom scope/sign-off. No named technical person/service or signer was established in the scoped canonical records; `TR` and `OP` are role labels. No clinical or product decision is inferred.

## Verification state

Manual review and documentation updates only. During the preceding OQ-14 edit, `git diff --check` was inadvertently invoked despite the instruction not to run checks; no whitespace diagnostic was emitted, and this result is not treated as acceptance evidence. No tests, builds, CI, or migrations were run for this OQ-07 review. No runtime behavior is claimed.
