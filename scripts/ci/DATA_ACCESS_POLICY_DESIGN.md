# P2-ACCESS-1 — Firestore Access-Control Drift Guard: design

GPT-PM APPROVE, round 3, `reviewRequestId c885cbd8-651e-4c56-8b51-65f90552419d`,
`replyId d841a663-8714-47fc-8bd3-a49bd64a674c`. Two REVISE rounds found real
gaps (round-1 MAJOR-3: operation-specific proof required, not path-only;
round-2: a property-access constant is invisible to a literal-string scan)
before this design closed. This document is the durable reference both a
cold internal review and GPT-PM's own implementation review check the code
against — see "Deviations from the approved design" at the end for every
point this implementation had to make a judgment call on.

**2026-09-16 remediation, round 1**: a cold second-round internal review
(database-reviewer + security-reviewer, run independently, neither primed
with the other's findings) found 1 BLOCKER + 4 distinct MAJOR + 1 MINOR
against the implementation this document originally described — see
`core/DECISION_LOG.md`'s "Row 24 gate" entry for the full findings text.
This document was updated in place to describe the mechanism AFTER that
remediation — the relevant subsections under §3–§9 each carry their own
"2026-09-16 remediation" marker naming which review item they close.

**2026-09-16 remediation, round 2**: GPT-PM's own implementation review of
round 1's diff (`core/DECISION_LOG.md`'s "Row 24 gate: GPT-PM implementation
review round 1" entry) returned `VERDICT: REVISE`, 3 BLOCKER + 4 MAJOR, all
independently re-verified against the real source before remediating. This
document is updated in place a second time; subsections carrying this
round's fixes are marked "2026-09-16 remediation, round 2" to distinguish
them from round 1's own markers above. Summary of what changed:
- **Discovery gained a FOURTH source** (direct `.doc(<path>)` calls, not
  just `.collection()`) — round 1's own fail-closed scanner never looked at
  `.doc()` at all, so every collection reached only that way (real,
  pre-existing: `subscription`, plus 15+ call sites in `functions/src/
  index.ts` alone) was invisible to every discovery source simultaneously.
- **The fail-closed scanner's exemption narrowed from a whole EXPRESSION
  CLASS to individually audited call sites** — an interpolated template, a
  function call, or string concatenation used to be exempted wholesale as
  non-blocking "residue"; now every one of those shapes hard-fails by
  default, exactly like a bare identifier or an unregistered property
  access already did, and only an exact, individually verified {file, line,
  arg} entry in `KNOWN_AUDITED_DYNAMIC_CALL_SITES` exempts a specific site.
- **CONDITIONAL-ref provenance is now bound to a SINGLE assertion**, not
  independently true facts about a whole test body — the SDK-call shape and
  the path match must both hold of the SAME `assertSucceeds`/`assertFails`
  call, with comments stripped first.
- **Registry resolution now requires a verified import binding**, not just
  identifier-name spelling — a locally-shadowed, unimported same-named
  constant no longer silently resolves to the registered export's value.
- **`chainedOffDoc`/Source D's own chain detection use balanced-paren
  POSITION matching**, not a regex that could not see past a nested paren.
- **Discovery is keyed by the full canonical path everywhere**, including
  inside `rules_parser.js`'s `collectionAccess()` — two dedicated blocks
  sharing a leaf/root segment can no longer collide or be validated against
  the wrong block.
- **The emulator suite's generic sweep** no longer reuses the same fixture
  document across a positive-then-negative CREATE pair for OWNER/
  AUTHENTICATED cells, which could silently test Firestore's UPDATE
  semantics instead.

**2026-09-16 remediation, round 3 (this project's standing 3-round GPT-PM
review cap — last round available)**: GPT-PM's own implementation review of
round 2's diff (`core/DECISION_LOG.md`'s "Row 24 gate: GPT-PM implementation
review round 2" entry) returned `VERDICT: REVISE`, 2 BLOCKER + 1 MAJOR — all
three narrower/deeper versions of round-1's own fixes that were only
partially complete, all independently re-verified against the real source
(and empirically reproduced against the pre-fix code) before remediating.
Summary of what changed:
- **Source D's per-user-subcollection recognition is now a purely
  STRUCTURAL test** (segment count and `segs[0] === 'users'`), never
  conditioned on whether the uid segment happens to be a literal string or a
  wildcarded template interpolation — a fully literal
  `db().doc("users/alice/sensitive_new/current")` used to be silently
  dropped (neither a candidate nor a violation) because the old check
  additionally required `segs[1] === '*'`, which only a `${uid}`-shaped
  interpolation ever produced.
- **CONDITIONAL-ref path verification is now bound to the matched SDK
  call's OWN document-reference argument**, not "a `doc()` call anywhere in
  the same assertSucceeds/assertFails argument text." Round 2's own fix
  bound "which assertion" but not "which argument of the SDK call inside
  that assertion" — a decoy `doc()` reference sitting in the SDK call's
  PAYLOAD argument (e.g. `updateDoc(doc(db,'_canary/x'), {ref:
  doc(db,'users/alice/profile/main')})`) still counted as path evidence.
- **Registry import-binding now fails closed on ANY local shadow of the
  registered identifier name** (a function parameter, or an inner-scope
  `const`/`let`/`var` re-declaration) anywhere else in the file — a
  legitimate file-level import no longer silently wins over a closer
  declaration the checker cannot actually prove is out of scope.

**2026-09-16 remediation, round 4 (this project's standing 3-round GPT-PM
review cap had already been reached; GPT-PM's own ruling on the round-cap
process question — `core/DECISION_LOG.md`'s "Row 24 gate: GPT-PM ruled on
the round-cap process question" entry, `VERDICT: APPROVE` — explicitly
authorized exactly one further, terminal round against exactly the 2
findings named below, no fresh whole-mechanism sweep).** GPT-PM's own
implementation review of round 3's diff (`core/DECISION_LOG.md`'s "Row 24
gate: GPT-PM implementation review round 3" entry) returned `VERDICT:
REVISE`, 1 BLOCKER + 1 MAJOR, both re-verified against the real source
before remediating. Summary of what changed:
- **`analyzeAssertCalls()` now requires the `assertSucceeds`/`assertFails`
  argument itself to be, STRUCTURALLY, one supported Firestore SDK
  operation expression** — not "some matching call found anywhere within
  the argument text via recursive search." Round 3's own fix bound "which
  SDK call inside the assertion" but still searched for that call ANYWHERE
  inside the assertion's argument text (`sdkCallSiteArgTexts()`), rather
  than requiring the argument to itself BE the call. A
  `Promise.all([updateDoc(profileRef, validPatch),
  updateDoc(invalidCanaryRef, ...)])`-wrapped assertion could certify via
  whichever wrapped call happened to match, even though the actual
  rejection/success reason is not attributable to any one call inside a
  `Promise.all`; the same recursive-search property meant an SDK-call-
  shaped substring sitting inside a plain string literal (not real code)
  could, in principle, also be matched by pure text scanning. Requiring the
  trimmed argument text to start at position 0 with `<sdkName>(` and
  account for the call's own balanced closing paren (modulo one optional
  JS-permitted trailing comma) closes all three named sub-cases at once, in
  one mechanism — see §5's own updated subsection and §7's `(x)`/`(y)`
  mutation classes.
- **`hasLocalShadowDeclaration()` now also recognizes object- and array-
  destructuring bindings** (`const { P2CollectionPaths } = runtimePaths;`,
  `const [P2CollectionPaths] = arr;`) as shadow-declaration shapes, alongside
  the existing plain `const|let|var IDENT` declaration and function/arrow-
  parameter checks. A destructured local shadow was previously invisible to
  BOTH halves of the detector: the plain-declaration regex doesn't match a
  destructuring pattern, and the real `.collection(Ident.member)` use site
  is deliberately excluded from the bare-identifier parameter detector
  (since it is followed by `.`, correctly treated elsewhere as legitimate
  member-access). See §4's own updated subsection and §7's `(z)`/
  `(z-positive)` mutation classes.

## 1. The problem

`firestore.rules`' generic wildcard —

```
match /users/{uid}/{coll}/{document=**} {
  allow read: if ... && coll != 'usage' && coll != 'receipts' && ...;
  allow write: if ... && coll != 'subscription' && coll != 'usage' && ...;
}
```

— grants the owner read/write over **any** subcollection under their own
`users/{uid}` except an explicit denylist. Several real subcollections
(`generated_exercises`, `equipment_setup_notes`, `programmes`,
`machine_cards`, `recognised_equipment`, `scheduled_sessions`,
`workout_logs`, `stats`, `workout_sessions`, …) ride this wildcard today
with **no dedicated rules block**. Nothing fails CI when a new sensitive
collection is added by omission — the wildcard silently grants owner access
to whatever a future subcollection turns out to be, with nobody having made
that access decision on purpose.

`scripts/ci/check_data_lifecycle_coverage.js` (MVP1.G3-CI-8) already solves
this exact shape of problem for a different axis — data **retention**
(DELETE/EXPORT/BOTH/EXEMPT): discover every collection, require an explicit
classification, fail CI on a gap. This gate applies the same proven
mechanism to the **access-control** axis.

## 2. Data model

`scripts/ci/data_lifecycle_policy.json` gains a new field per collection,
`clientAccess`, an **array** of entries (always an array, even for the
single-path common case — one shape to maintain):

```json
"clientAccess": [
  {
    "path": "/users/{uid}/profile/{docId}",
    "access": { "read": "OWNER", "create": "CONDITIONAL", "update": "CONDITIONAL", "delete": "NONE" },
    "conditionalRefs": {
      "create": { "testFile": "functions/src/__rules__/data_access_policy.test.ts", "testName": "...", "operation": "create" },
      "update": { "testFile": "functions/src/__rules__/data_access_policy.test.ts", "testName": "...", "operation": "update" }
    }
  }
]
```

Each of `read`/`create`/`update`/`delete` is exactly one of `NONE` /
`OWNER` / `AUTHENTICATED` / `PUBLIC` / `CONDITIONAL`. `conditionalRefs` is
required, and only valid, for an operation declared `CONDITIONAL`.

`path` is the collection's full path exactly as `firestore.rules` states
it (own variable names preserved — `{docId}`, `{canaryUid}`, `{day}`, …),
which keeps every declaration traceable 1:1 back to the rules file it
describes.

## 3. Rule-body parser (`scripts/ci/lib/rules_parser.js`)

Not a general CEL parser (per this gate's own approved scope: "regex or
lightweight text parsing is fine — no full TypeScript type-checker
needed"). What **is** done properly rather than by naive line-regex: match
block bodies are extracted by **brace-depth counting**, not a non-greedy
regex up to the next `}` — this file's blocks happen to contain no nested
`{}` today, but a checker that assumed that structurally rather than
verified it would be a claim, not a result.

Per verb, per block, the condition is classified:

- **PLAIN_OWNER** — bare `request.auth != null && request.auth.uid == X`
  (X is whatever path variable that match's own path binds), nothing else.
- **ALWAYS_FALSE** — `if false`, verbatim.
- **AUTHENTICATED** — bare `request.auth != null`, no uid comparison.
- **PUBLIC** — `if true`.
- **NON_TRIVIAL** — anything else: field conditions, role checks, extra
  clauses.
- **IMPLICIT_DENY** — (resolution-time only, not a raw classification) no
  `allow` clause covers this verb at all for this collection — Firestore's
  own default-deny. Only arises when a collection is excluded from the
  wildcard for a verb and no dedicated block picks it up either (real
  example: `subscription`'s write).

The static checker (§5) **refuses** an `access` value of `OWNER` for any
operation the parser classifies `NON_TRIVIAL` — `CONDITIONAL` is the only
legal declaration there. `profile`'s write path is the concrete case this
rule exists for: owner-scoped **and** field-conditioned via a health-strip
function — confirmed to fire for real against the emulator (not just a
synthetic example), see §7.

### Dedicated-block-vs-wildcard OR semantics (2026-09-16 remediation)

Firestore **ORs every matching rule together** — a dedicated match block
does not override or narrow the generic wildcard's own separate grant for
the same collection; both are evaluated, and either one succeeding grants
the request (`firestore.rules:20-23`'s own comment documents this exact
hazard). `collectionAccess()` originally trusted a dedicated block's
classification unconditionally once found, without checking whether the
wildcard's own per-verb exclusion list (`wildcardExclusions[op]`) actually
excludes that leaf too — a dedicated `allow write: if false;` block for a
leaf the wildcard's write condition never excludes would be *certified*
`NONE`/`CONDITIONAL`-safe by the classifier while Firestore itself still
grants the wildcard's owner-write for real, because the wildcard's separate
rule is still live regardless of what the dedicated block says.

`collectionAccess()` now checks this explicitly: whenever a dedicated
block's classification for a verb is `ALWAYS_FALSE` or `NON_TRIVIAL` (i.e.
plausibly MORE restrictive than what the wildcard would otherwise grant)
**and** the wildcard would actually grant something for that verb (its own
classification is not itself `ALWAYS_FALSE`) **and** the leaf is not
present in `wildcard.wildcardExclusions[op]`, the checker throws, naming
the exact leaf, verb and the missing `coll != '<leaf>'` clause that would
close the gap. Every real dedicated restrictive block in `firestore.rules`
today is already correctly excluded (verified: the checker runs clean
against the real, unmodified rules file), so this is a structural
safety net for a future regression, not a fix to a live hole.

### The generic wildcard is a special case, by design

The wildcard's own condition has extra `!isCanaryToken()` and `coll !=
'x'` clauses. These are **structural eligibility** ("does this block even
govern this collection at all"), not per-collection access logic — exactly
like `request.auth != null` is already boilerplate inside the
PLAIN_OWNER pattern itself. For a collection that actually reaches the
wildcard (not excluded), the parser strips these structural clauses before
judging bare-owner-ness. This is a deliberate, documented reading of the
approved design's own example ("confirm it rides the generic wildcard, i.e.
PLAIN_OWNER per the wildcard's own bare uid-equality condition") — treating
the routing exclusions as part of the OWNER-ness judgment, rather than as
extra conditions that would force every wildcard-riding collection to
CONDITIONAL, is what makes that example's own phrasing coherent.

### `delete` and `request.resource` — an empirically-forced refinement

**Measured against the real Firestore emulator while building this gate**
(not assumed): `request.resource` does not exist on a `delete` request.
`profile`'s write condition — one `allow write` statement textually
covering create/update/delete identically — reads
`request.resource.data.health`, and a live probe against the emulator
showed every delete attempt fails with `Null value error ... for
'delete'`. A rule that errors denies. This is not a genuine two-outcome
condition for `delete` — it is unconditional denial, textually disguised
as the same NON_TRIVIAL condition that genuinely gates create/update.

The parser generalizes this rather than special-casing `profile` by name:
**any `delete`-verb condition that references `request.resource` is
classified `ALWAYS_FALSE`**, not `NON_TRIVIAL`. `profile.delete` is
declared `NONE` accordingly (see §8's own note on this). A future
collection whose write rule is field-conditioned the same way would be
misclassified as a genuine CONDITIONAL-with-two-outcomes without this
generalization.

### Exact-canonical-path matching in `collectionAccess()` (2026-09-16 remediation, round 2, finding 6)

`collectionAccess(blocks, canonicalPath, leafName, isUserSubcollection)` now
finds the dedicated block for a declared `clientAccess[].path` by comparing
`canonicalPath` against each block's own `matchPath` with EXACT STRING
EQUALITY. It used to match by `leafName`/`segments[0]` alone — a coarse
"root" key — so two distinct dedicated blocks that happen to share a leaf or
root segment (e.g. `/admin/{adminId}/profile/{docId}` and `/admin/
{adminId}/audit/{docId}`, both rooted at `admin`) would resolve to
WHICHEVER block `.find()` landed on first, silently validating one declared
`clientAccess` entry against a DIFFERENT block's access rules. `leafName` is
still passed and used separately, only for the generic wildcard's own
per-verb exclusion-set lookup (`coll != '<leaf>'` is keyed by the bare
subcollection name, not the full path).

This is not a new constraint on the data: every `canonicalPath` this checker
ever calls with is already required, by `discoverCandidates()`'s own Source
A seeding and by the coverage check in `main()`, to equal a real block's
`matchPath` verbatim (for a rules-derived collection) or a
`derivePathVars()`-constructed string (for a code-only one) — exact string
comparison only corrects HOW this function looks a block up, not what data
it is allowed to accept. Confirmed dormant against the real repo today (no
two top-level blocks in `firestore.rules` share a root segment), fixed
properly rather than left latent — the same root-cause pattern
(coarse-key collapse) recurs across this gate's own history, see
`discoverCandidates()`'s own matching fix in §4 below.

### Duplicate allow-statements per verb (2026-09-16 remediation)

Firestore ORs multiple `allow <verb>` statements covering the same
operation WITHIN one match block, exactly like it ORs across blocks (the
hazard above) — a second statement never narrows or overrides the first.
The parser originally built `verbs[op]` by straightforward last-write-wins
assignment, silently discarding an earlier statement for the same op if a
second one appeared. `parseFirestoreRules` now fails closed instead: if
`verbs[op]` is already populated when a second statement for that op is
encountered, it throws, naming the match block and both conditions,
because deciding how to union two arbitrary CEL conditions correctly is
out of scope for this lightweight text parser (per its own stated
non-goal — no general CEL evaluator) and silently keeping only one is a
misrepresentation, not a simplification. No live block in `firestore.rules`
has this shape today (verified: the checker runs clean against the real,
unmodified rules file).

One structural consequence of this fix: the outermost
`match /databases/{database}/documents { ... }` wrapper block's own body
textually contains every nested block's `allow` statements (this parser's
match-body extraction is brace-depth-scoped per `match`, but
`parseAllowStatements`'s own regex is not match-boundary-aware within a
body), so a naive read of the wrapper's body would see the SAME verb
declared by many different nested blocks and misfire the duplicate check
on blocks that are not actually duplicates of each other. The parser skips
allow-statement extraction entirely for any block whose own body contains
a further nested `match` statement (in this file, only that one wrapper) —
its `verbs` map is always empty, which is harmless because
`discoverCandidates()` already filtered this exact matchPath out of
`dedicated` before this fix existed.

## 4. Discovery — four sources, unioned, plus one fail-closed scanner

- **Source A (rules, full path)** — every DEDICATED `match` block's full
  path is its own canonical declaration target (unlike the lifecycle
  checker's own leaf-name-only discovery, which is sufficient for its axis
  but not for path-aware access declarations). Seeded into the candidate
  map keyed by the block's own full `matchPath` text — never a coarse
  leaf/root key (2026-09-16 remediation, round 2, finding 6: the original
  `dedicatedByLeaf` Map silently OVERWROTE one of two dedicated blocks
  sharing a leaf/root segment, dropping it from the candidate set entirely
  — a real coverage hole, not merely a display collapse. `hasDedicatedBlock()`
  now does a plain `.some()` existence check over the block list for the
  separate "does a CODE-discovered name already have its own dedicated
  block" question, never a lossy keyed Map).
- **Source B (code, literal `.collection()`)** — the same literal
  `.collection('name')` / `.collection("name")` scan the lifecycle checker
  already runs, across an explicit, named `PRODUCTION_SOURCE_ROOTS` list:
  `functions/src`, `functions-equipment-identity/src`, `mobile/lib`. Adding
  a new Firestore-writing codebase to this repo means adding its root to
  this list — documented in the checker's own code comment, not only here.
- **Source C (declared path-registry)** — an explicit `PATH_REGISTRIES`
  list of `{file, exportName}` pairs, each naming an `export const XPaths =
  { key: "literal", ... } as const` object. The object literal is parsed
  (brace-matched, then `key: "value"` pairs regex-extracted — lightweight
  text parsing, no type-checker) and its string VALUES are unioned into
  discovery exactly like a literal call would be. `P2CollectionPaths`
  (`functions-equipment-identity/src/p2/firestore_paths.ts`) is the first
  real registration. **Resolution now also requires a verified import
  binding** (2026-09-16 remediation, round 2, finding 4 — was MAJOR):
  matching `Identifier.member` against a registry by IDENTIFIER SPELLING
  alone would resolve a locally-shadowed `const P2CollectionPaths = {...}`
  with different values in an unrelated file to the registered (wrong)
  value. `registryBindingHolds()` additionally requires the calling file to
  either BE the registry's own declaration file, or contain a real relative
  `import { P2CollectionPaths } from '<path resolving to the registry
  file>'` — a non-relative import (a path alias, a package import) cannot
  be resolved this lightweight way and does not bind, failing closed like
  every other unresolved shape here. **Round 3 (MAJOR): resolution
  additionally fails closed if the registered identifier name is ALSO
  declared anywhere else in the file** — a function parameter, or an
  inner-scope `const`/`let`/`var` re-declaration — besides the import
  itself; see the dedicated subsection at the end of this section.
- **Source D (code, literal `.doc(<full path>)`) — new, 2026-09-16
  remediation, round 2, finding 1 (was the BLOCKER)**. `functions/src/
  index.ts` alone has 15+ real `db.doc(\`users/${uid}/subscription/main\`)`-
  shaped call sites, plus `functions-equipment-identity/src/p2/quota.ts` and
  `functions/src/abuse_guard.ts` — all invisible to Source B, which only
  ever scanned `.collection()`. `subscription` in particular had NO
  discovery source requiring it at all before this fix (declared in the
  policy, but nothing forced it) — exactly the omission class this whole
  gate exists to catch. Every `.doc(<arg>)` call site directly on the
  Firestore root (`db`, `db()`, or `_db` — see `isDbRootDocCall()`'s own
  scope-boundary doc comment below) is parsed the same way a `doc(db,
  path)` two-arg call in a test body already is (`testDocPathCollection
  Segments()`, shared code, not duplicated): a literal string or template
  literal with `${...}` interpolations wildcarded, the trailing document-id
  segment dropped, and the remaining segments read as `/users/{uid}/<leaf>`
  or `/<leaf>` depending on shape. A `.doc()` call whose resulting LEAF
  segment is itself dynamic (an interpolation landed on the collection-name
  position, not just the doc-id) is treated exactly like an unresolved
  `.collection()` argument — see the fail-closed scanner below, one
  standard for both call kinds, not a looser one for `.doc()`.

  **Per-user-subcollection shape is STRUCTURAL, not a function of whether
  the uid is literal or interpolated (2026-09-16 remediation, round 3,
  BLOCKER 1).** `collectionShapeFromDocSegments()` used to additionally
  require `segs[1] === '*'` to recognize the `/users/{uid}/<leaf>/...`
  shape — which only a template interpolation (`${uid}` wildcarded to `*`)
  ever produces. A STATICALLY LITERAL path like
  `db().doc("users/alice/sensitive_new/current")` has `segs[1] === 'alice'`
  (a real uid VALUE, not a wildcard), fell through to the generic
  top-level branch, and returned `{leaf: 'users', isUserSubcollection:
  false}` — silently discarded entirely by `addCandidate()`'s own
  `leaf === 'users'` guard, with neither a candidate nor a violation ever
  produced. Empirically confirmed against the pre-fix checker (2026-09-16):
  this exact fixture returned a clean exit 0. Whether a path is a per-user
  subcollection is a STRUCTURAL fact — `segs.length >= 3 && segs[0] ===
  'users'` — never a function of whether the uid segment happens to be a
  literal string or a wildcarded interpolation; both are equally "some
  user's id" for classification purposes. The `segs[1] === '*'` gate is
  removed; the narrower `addCandidate()` `leaf === 'users'` guard is KEPT,
  now serving only the genuinely narrower case of a bare 2-segment
  `.doc('users/<id>')` call (no third segment at all — a reference to the
  `users` root container itself, never a real collection).

  **Scope boundary — root-`.doc()` calls only, not "not chained off
  `.collection()`"**: an earlier draft of Source D tried to recognize a
  relative document-id call (`.collection('users').doc(uid)` — `uid` is a
  doc id inside an ALREADY-discovered collection, not a new path) by
  checking textual, same-statement adjacency to a preceding `.collection(`
  call. That under-covers this codebase's own DOMINANT idiom: every
  `mobile/lib` repository class defines a private helper
  (`_col(uid) => _db.collection('users').doc(uid).collection('workout_logs')`)
  and calls `.doc(entryId)` on ITS result, not on a literal `.collection()`
  call in the same statement — an adjacency check flagged 16 real,
  legitimate relative `.doc(<localId>)` calls across 8 mobile/lib files as
  fake new top-level paths. Fixed by flipping to a POSITIVE allowlist
  instead: only a `.doc(<arg>)` call whose immediately preceding token is
  the literal Firestore-root expression `db` / `db()` / `_db` is a Source D
  candidate at all (verified against the real repo: zero root-level
  `_db.doc(`/`_db().doc(` call exists in `mobile/lib` — every real
  full-PATH `.doc()` call site lives in `functions/src`/`functions-
  equipment-identity/src`). This sidesteps the "what is this chained off"
  question entirely rather than trying to enumerate every possible
  indirection shape.
- **Fail-closed non-literal-call scanner** — every `.collection(<arg>)`
  AND `.doc(<arg>)` call site across the same `PRODUCTION_SOURCE_ROOTS` is
  inspected, one shared classification for both call kinds. `<arg>` is
  classified:
  - a quoted string literal, or a template literal that resolves to a
    literal collection name / path — already covered by Source B/D, no
    action;
  - a **property-access expression** on a plain identifier
    (`Identifier.member`, single dot, nothing else) — resolved against
    `PATH_REGISTRIES` by identifier name AND a verified import binding (see
    Source C above); if unresolved, **CI fails outright**, naming the
    file:line and the expression text.
  - a **bare identifier** (`Identifier` alone — a local variable or
    function parameter, no dot, no call) — **CI fails outright**, naming
    the file:line and the expression, UNLESS that EXACT `{file, line, arg}`
    triple is explicitly registered in `KNOWN_AUDITED_DYNAMIC_CALL_SITES`
    with a documented, individually verified justification (see §9). This
    closes the security-reviewer's MAJOR finding that an ordinary one-line
    helper — `function coll(db,n){return db.collection(n);}` — reached a
    genuinely new, undeclared collection with zero CI signal.
  - **anything else — a template literal WITH interpolation landing on the
    collection-name/leaf position, a function call, or string
    concatenation — ALSO fails outright by default** (2026-09-16
    remediation, round 2, finding 2 — was the BLOCKER; narrower than round
    1's own version of this rule, which exempted this whole EXPRESSION
    CLASS as non-blocking "residue" no matter the call site). The
    round-1 justification (a generic helper's real collection names are
    separately discoverable as literals at their OWN call sites) was
    legitimate for the SPECIFIC audited instances that motivated it, but
    was wrongly generalized to exempt the entire shape everywhere — a
    genuinely new helper with no separately-discoverable literal call site
    would have slipped through entirely, silent, exit 0. Only an exact,
    individually verified `{file, line, arg}` entry in
    `KNOWN_AUDITED_DYNAMIC_CALL_SITES` (same shape as the bare-identifier
    exception, now used for every non-literal shape uniformly) exempts a
    specific call site — never the whole expression class. See §9 for the
    real, named, currently-audited entries.

### Per-user-subcollection vs. top-level disambiguation (2026-09-16 remediation, item 5)

Every code-discovered name (Source B literal, or Source C registry) used to
be assumed a per-user subcollection unconditionally
(`derivePathVars(name, true)`, hardcoded). A genuinely new TOP-LEVEL
collection reached only via code (no dedicated rules block yet) would get
its canonical path mis-derived as `/users/{uid}/<name>/{docId}` — and, the
actually dangerous part, validated against the WRONG expected
classification (the wildcard's owner-style grant) instead of Firestore's
real default-deny for an unmatched top-level path, silently certifying a
declaration the real rules do not back up (database-reviewer's MAJOR
finding).

Fixed **mechanically**, not documented as a limit: every real
`.collection(<literal-or-registry-name>)` call site in this codebase that
reaches a per-user subcollection is chained directly off a `.doc(...)`
reference — `_db.collection('users').doc(uid).collection('workout_logs')`
(mobile/lib's repository classes, verified by reading every current
call site) — while every real top-level call site is not
(`_db.collection('debug_sessions')`, `db.collection('coach_bookings')`).
`scanProductionCalls()` now records, per `.collection(<arg>)` call site,
whether it is chained directly off a `.doc(...)` call — `chainedOffDoc`.
`discoverCandidates()` aggregates this evidence per discovered name across
ALL its call sites:

**Balanced-paren POSITION matching, not a regex (2026-09-16 remediation,
round 2, finding 5 — was MAJOR).** The original `chainedOffDoc` detector was
a `/\.doc\([^()]*\)\s*$/`-shaped regex, which cannot match past a NESTED
paren inside the `.doc()` argument — `db.collection('users')
.doc(getUid()).collection('sensitive_new')` would be misclassified as
top-level (the regex's `[^()]*` stops at `getUid(`'s own opening paren),
silently validating a genuine per-user subcollection against Firestore's
top-level default-deny instead of the wildcard's real owner-style grant.
Fixed by `memberCallSites()` (used for both `.collection(` and `.doc(`
scanning) recording each call's own resolved start/end POSITIONS via the
same balanced-paren depth-counting already used everywhere else in this
module, and `isAdjacentCall()` checking whether one call's end position is
followed only by whitespace before another call's start — a pure text-
position comparison with no blind spot for what is inside either call's own
argument list, however deeply nested.

- every call site agrees it's chained off `.doc(...)` → per-user
  subcollection, `/users/{uid}/<name>/{docId}` (the original, now
  evidence-backed rather than assumed, behavior);
- every call site agrees it's NOT chained → top-level,
  `/<name>/{docId}` (previously `derivePathVars(leaf, false)` returned
  `null`, dead code since the caller always passed `true` — now returns
  the real top-level path shape);
- call sites for the SAME name DISAGREE (some chained, some not) → cannot
  be mechanically resolved. Reported as a distinct `AMBIGUOUS collection
  name "..."` hard failure, naming every conflicting call site, rather than
  guessing either way.

Verified against the real repo: every currently code-only-discovered name
(the nine subcollections riding the wildcard — `workout_logs`,
`workout_sessions`, `scheduled_sessions`, `programmes`, `machine_cards`,
`recognised_equipment`, `generated_exercises`, `equipment_setup_notes`,
`stats`) is unanimously `chainedOffDoc: true` at every real call site, so
this fix changes zero real classifications — it only changes what happens
for a name that does NOT yet have this evidence, which previously silently
defaulted to the (sometimes wrong) subcollection assumption.

This is a full mechanical fix for this codebase's own actual calling
conventions, not the documented-scope-limit fallback the original
plan allowed for if a mechanical fix proved impractical — it remains a
heuristic (a codebase that reached a top-level collection via
`.doc(someUnrelatedId).collection(name)` for a non-per-user reason would
be misread), not a real AST/type-checker, consistent with this gate's
overall lightweight-parsing philosophy; see §9.

### Registry import-binding is call-SITE-scope-aware, not just file-level (2026-09-16 remediation, round 3, MAJOR)

Round 2's own fix (`registryBindingHolds()`, see Source C above) closed the
identifier-SPELLING gap but only ever checked whether the WHOLE FILE
contains a matching import statement — it had no idea whether a CLOSER
local declaration (a function parameter, an inner-scope `const`/`let`
re-declaration of the same identifier name) shadows that import at the
actual `.collection(Ident.member)` call site. A file that legitimately
imports `P2CollectionPaths` at the top AND ALSO has, say,
`function handler(P2CollectionPaths) { ... .collection(P2CollectionPaths
.textKeys) ... }` still silently resolved via the file-level import, even
though the real value in scope at that call site is whatever the caller
passed as the parameter, not the registered one. Empirically confirmed
against the pre-fix `registryBindingHolds()` (2026-09-16): this exact
scenario returned `true` (bound).

Fix, per GPT-PM's own stated acceptable options (the simpler, safe one):
`registryBindingHolds()` now additionally calls `hasLocalShadowDeclaration()`
before trusting a genuine import match, and refuses to trust it (falls
through to fail-closed, same as an unresolved import) whenever the
registered identifier name is ALSO declared anywhere else in the file as a
function/arrow-function PARAMETER, a `const`/`let`/`var`
(re-)declaration, or (2026-09-16 remediation, round 4 — GPT-PM's own
terminal-round MAJOR) an object- or array-DESTRUCTURING binding naming the
identifier (`const { P2CollectionPaths } = runtimePaths;` /
`const [P2CollectionPaths] = arr;`) — besides the import itself. Round 3's
own fix covered only a PLAIN `const|let|var IDENT` (re-)declaration; a
destructuring pattern doesn't match that regex at all, and the real
`.collection(Ident.member)` use site is separately, deliberately excluded
from the bare-identifier parameter detector (it is followed by `.`), so a
destructured local shadow was invisible to both halves of the detector at
once — empirically confirmed against the pre-round-4 `registryBindingHolds()`
(2026-09-16): a file legitimately importing `P2CollectionPaths` at the top,
with `const { P2CollectionPaths } = runtimePaths;` destructured inside a
function body, resolved `bound: true` via the file-level import even though
the real value in scope at the call site is whatever `runtimePaths`
actually contained. This is deliberately NOT a real scope resolver (no AST,
no actual lexical-scope tracking, matching this checker's own "regex/
lightweight text parsing is fine" scope): ANY other declaration of the
exact identifier name anywhere in the file counts as a potential shadow,
even in a case a real parser would prove is not actually in scope at the
specific call site. This can over-flag a file that happens to reuse the
name in a totally unrelated, non-shadowing way — an acceptable, safe
direction for a CI gate: a false failure costs a rename, a false pass is
the actual security gap this whole checker exists to catch.

`hasLocalShadowDeclaration()`'s parameter check balanced-paren-scans every
`(...)` span in the file and tests whether the identifier appears inside it
as a BARE token — not immediately preceded or followed by `.` (which would
make it a property-access base/member, e.g. `Foo.IDENT` or `IDENT.member`,
never a parameter). This means a genuine `Ident.member` call argument like
`P2CollectionPaths.textKeys` is never mistaken for a parameter declaration
of that same name (the real, legitimately-imported usage in
`functions-equipment-identity/src/p2/text_key_index.ts` stays green after
this fix — verified both by the full checker run and by a dedicated
mutation-proof positive case, §7's `(v-positive)`), while
`function handler(P2CollectionPaths) {...}` (and, for the same
over-flag-is-acceptable reason, an ordinary call passing the bare
identifier as an argument elsewhere) is correctly flagged.

Note this shadow check is skipped for the same-file-as-registry case
(`file === registry.file` returns `true` immediately, unchanged from round
2) — the registry's own tiny declaration file has no redeclaration risk in
practice today, and adding scope-awareness to a file that IS its own
canonical declaration is out of scope for the gap GPT-PM actually found
(an IMPORTING file's own local shadow).

## 5. Static schema checker (`scripts/ci/check_data_access_policy.js`)

Wired into the same job shape as `check_data_lifecycle_coverage.js` in
`.github/workflows/functions.yml` (repo-root working directory, no `npm
install` needed — only Node's built-in `fs`/`path`). Validates:

- required keys present, `access` values are one of the five valid enums;
- every discovered path (all four sources, plus the fail-closed scanner's
  own violations) has a `clientAccess` declaration;
- for every declared cell, the parser's own classification (re-derived
  from `firestore.rules` **from the declared `path` itself**, never
  trusted from the JSON blindly) is consistent with the declared `access`
  value — `NON_TRIVIAL` ⇒ must be `CONDITIONAL`; `ALWAYS_FALSE`/
  `IMPLICIT_DENY` ⇒ must be `NONE`; `PLAIN_OWNER` ⇒ must be `OWNER`;
  `AUTHENTICATED`/`PUBLIC` ⇒ must match exactly;
- every `CONDITIONAL` operation's `conditionalRefs` entry names a real
  test file and a real, findable `test("...")` block whose body contains
  **both** an `assertSucceeds` and an `assertFails` case, **and** a
  Firestore SDK call matching the declared operation
  (`getDoc`/`getDocs` for read, `setDoc`/`addDoc` for create, `updateDoc`
  for update, `deleteDoc` for delete) — closing GPT-PM's round-1 MAJOR-3
  finding mechanically, not just by convention;
- **(2026-09-16 remediation, item 1 — was the cold-review BLOCKER)** that
  same named test's body actually TARGETS the declared collection, not
  just the right operation shape. The checks above alone would accept a
  CONDITIONAL declaration for a brand-new sensitive collection pointed at
  an unrelated, pre-existing, correctly-shaped test (e.g. `_canary/update`)
  — no backstop caught this anywhere else, since the emulator suite's own
  Part 2 generic sweep explicitly skips every CONDITIONAL cell (§6). The
  checker now derives the actual Firestore path(s) the named test
  constructs — every `doc(<dbExpr>, <pathArg>)` call site in the test
  body, balanced-paren-extracted, with a template literal's `${...}`
  interpolations wildcarded the same way a declared path's `{var}`
  segments are — and requires at least one to resolve to the same
  collection segments as the cell's own declared `path`. A test whose
  `doc()` calls all resolve to a DIFFERENT collection fails, naming the
  mismatch and every path it did find. Deliberately still lightweight
  text parsing (no expression evaluator): a `doc()` call built from
  anything other than a string or template literal (a bare variable, a
  function call) is not statically resolvable and is excluded from the
  match set rather than guessed at — if NO call site is resolvable at all,
  the cell fails closed rather than passing on the assumption that an
  unparseable path is a correct one.
- **(2026-09-16 remediation, round 2, finding 3 — was the BLOCKER)** the
  SDK-call-shape check, the assertSucceeds/assertFails-presence check, and
  the path-match check above are now bound to the SAME assertion, not three
  independent facts about the whole test body. Round 1's own fix (the item
  above) added path verification but checked it against `doc()` calls
  ANYWHERE in the test body — a test whose REAL `assertSucceeds(...)`/
  `assertFails(...)` calls target a totally different collection, with an
  unrelated `doc()` reference to the declared path sitting elsewhere in the
  body (setup code, an unused variable, even inside a comment), passed
  every check. `analyzeAssertCalls()` now extracts each `assertSucceeds(...)`
  / `assertFails(...)` call's own balanced-paren argument text as its own
  self-contained unit (not a substring search over the whole body) and
  requires AT LEAST ONE call of each kind, independently, to (a) contain the
  op-shaped SDK call AND (b) have that SAME call's own `doc(...)` path
  argument(s) resolve to the declared collection. Comments (`//` and
  `/* */`) are stripped from the test body BEFORE any of this analysis
  (`stripComments()`, string/template-literal-aware so it never eats a
  comment-looking token inside a real string) — a comment containing
  matching tokens must never count as evidence.
- **(2026-09-16 remediation, round 3, BLOCKER 2)** the path check is now
  bound to the matched SDK call's OWN document-reference argument, not "a
  `doc()` call anywhere in that same assertSucceeds/assertFails argument
  text." Round 2's own fix (the item above) bound WHICH ASSERTION but not
  WHICH ARGUMENT of the SDK call inside it — it filtered the assertion's
  whole argument text by (a) "the SDK token matches somewhere in this
  text" then separately by (b) "some `doc()` call anywhere in this SAME
  text matches the declared path", two independent facts, neither
  confirming the matching `doc()` call is actually the operand of the
  matched SDK call. GPT-PM's own exact adversarial scenario:
  `assertSucceeds(updateDoc(doc(db,'_canary/x'), {ref:
  doc(db,'users/alice/profile/main')}))` — a real update targeting
  `_canary`, with an unrelated `profile`-path `doc()` reference buried in
  the update's own PAYLOAD object (`updateDoc`'s SECOND argument) — passed
  both round-2 checks even though the actual update target was `_canary`,
  not `profile`. Empirically confirmed against the pre-fix
  `analyzeAssertCalls()` (2026-09-16): this exact scenario returned
  `{ok: true}`.

  `analyzeAssertCalls()` (round 3) found each SDK-named call
  (`updateDoc`/`setDoc`/`addDoc`/`deleteDoc`/`getDoc`/`getDocs` — plain
  names now, `OP_SDK_CALL_NAMES`, not a single alternation regex) as its
  OWN balanced-paren unit ANYWHERE inside the matched assertSucceeds/
  assertFails argument text (`sdkCallSiteArgTexts()`, reusing the already-
  proven `extractCallArgTexts()` one name at a time), split THAT call's own
  argument list into its top-level arguments
  (`splitTopLevelArgs()`, already used elsewhere in this module), and took
  ONLY the FIRST one — the SDK call's own document-reference argument; the
  path was derived from a `doc(...)` call found within THAT first argument
  alone (still `docCallPathArgs()` + `testDocPathCollectionSegments()`) — a
  `doc()` reference anywhere else in the SDK call (a later argument, a
  payload object field) was never consulted.

- **(2026-09-16 remediation, round 4, BLOCKER — GPT-PM's own terminal
  ruling)** round 3's own fix above still searched for a matching SDK call
  ANYWHERE within the assertion's argument text, rather than requiring the
  assertion argument to itself BE that call. GPT-PM's own round-4 guidance
  (`core/DECISION_LOG.md`'s "GPT-PM ruled on the round-cap process question"
  entry): acceptance should be stronger than merely "count calls" — each
  referenced `assertSucceeds(...)`/`assertFails(...)` must have ONE
  mechanically attributable operation whose outcome IS the assertion's
  outcome, concretely by requiring the assertion argument itself to be
  (structurally) ONE supported Firestore SDK operation expression, rather
  than recursively searching for a matching call inside arbitrary wrappers.

  `analyzeAssertCalls()` now calls a new `wholeSdkCallExpression()`: it
  trims the assertion's own argument text and requires it to start, at
  index 0, with `<sdkName>(`, with everything from there to that call's own
  balanced matching close-paren accounting for the ENTIRE trimmed text
  (modulo one optional JS/TS-permitted trailing comma after a lone single
  argument — the real multi-line shape several of the 7 hand-written
  `conditionalRefs` tests use, e.g. `assertSucceeds(\n  setDoc(...),\n)`;
  verified against all 7 before writing this fix — every one already has
  this exact direct shape, so no real test's shape needed adjusting). This
  single structural change closes three sub-cases GPT-PM named, together,
  in one mechanism rather than three separate patches:
  - a `Promise.all([updateDoc(profileRef, validPatch),
    updateDoc(invalidCanaryRef, ...)])`-wrapped assertion: the trimmed
    argument text starts with `Promise.all(`, not any SDK name, so the
    whole assertion is now correctly treated as NOT valid evidence,
    regardless of which individual wrapped call happens to target the
    declared path — the real rejection/success reason is not mechanically
    attributable to any one call inside a `Promise.all` (§7's `(x)`);
  - any other wrapper (`await someHelper(...)`, a bare variable holding a
    pre-built promise, etc.) around a real SDK call: same reasoning, the
    trimmed text does not start with the SDK call name;
  - an SDK-call-shaped decoy substring sitting inside an actual STRING
    LITERAL (e.g. `assertFails("updateDoc(doc(db,'users/x/profile/y'))")`,
    a raw code string rather than real code): the trimmed text starts with
    a quote character, never with the bare SDK name followed directly by
    `(`, so it can never match — closed structurally, with no separate
    string-literal-awareness pass needed (§7's `(y)`).

  **Residual, explicitly not closed**: if a real test ever passed a
  VARIABLE holding a pre-built document reference
  (`const ref = doc(...); updateDoc(ref, data)`) instead of an inline
  `doc(...)` call, this cannot trace the variable's value back to a path —
  the site is simply skipped (neither shape nor path evidence for that
  particular call). Checked against the real test suite: none of the 7
  hand-written `conditionalRefs` tests in `data_access_policy.test.ts` use
  this pattern, so the gap does not currently affect any real declared
  cell. The failure mode if it ever did is safe (fail closed — `reason:
  'shape'` or `'path'`, never a silent pass), not silently accepting.

## 6. Emulator-driven semantic verification (`functions/src/__rules__/data_access_policy.test.ts`)

Two parts:

1. **Seven hand-written, single-operation tests** — one per `CONDITIONAL`
   cell (`_canary`'s four verbs, `debug_sessions`' create, `profile`'s
   create/update). The existing 1016-line suite was searched first, per
   this gate's own fallback rule ("only write a new emulator test if no
   existing one already proves the specific operation"); none of its
   existing tests isolate a single operation with both a clean
   `assertSucceeds` and an adversarial `assertFails` in one block (the
   canary test bundles read+create+delete together; the profile re-attack
   tests are `assertFails`-only). Fresh, single-operation pairs keep the
   operation-specific proof mechanically checkable by
   `check_data_access_policy.js`'s own SDK-call-regex matcher (and, since
   2026-09-16, its `doc()`-call PATH matcher — see §5's item-1 subsection)
   rather than relying on fragile archaeology against tests written for a
   different, narrative purpose.

   **`profile`'s create/update tests also cover the lifestyle-bypass
   clauses (2026-09-16 remediation, item 6 — was MINOR):**
   `firestore.rules`'s real `profile` write condition
   (`firestore.rules:188-197`) is a THREE-way conjunction — health-strip
   AND `lifestyle.smoking` null AND `lifestyle.alcohol` null — but the
   original two fixtures only ever varied `health`, so a regression in
   either lifestyle-null clause specifically (with the health-strip left
   intact) would have passed this cell's proof by coincidence, not because
   it was actually exercised. Each of `profile/create` and `profile/update`
   now carries two additional `assertFails` cases: health correctly
   stripped, but `lifestyle.smoking`/`lifestyle.alcohol` present and
   non-null. These are additional assertions inside the SAME two `test()`
   blocks, not new test cases — the emulator suite's total count is
   unchanged (269), and `check_data_access_policy.js`'s conditionalRef
   validation (both the SDK-shape and the path check) is unaffected, since
   it only requires the body to CONTAIN both an `assertSucceeds` and an
   `assertFails`, not that there be exactly one of each.
2. **A generic, data-driven sweep**, generated directly from the policy
   JSON at test-collection time, covering every `NONE`/`OWNER`/
   `AUTHENTICATED`/`PUBLIC` cell (148 − 7 = 141 generated cases across the
   real policy). `CONDITIONAL` cells are excluded — a generic fixture
   payload cannot meaningfully exercise a field-conditioned rule.

**Binding, non-optimizable**: this suite re-verifies **every** declared
path+operation cell on **every** CI run. There is no incremental/changed-
only mode, and adding one later is a regression against this gate's own
Definition of Done (GPT-PM round-1 MAJOR-3 / round-3 DoD item).

**Fresh-fixture CREATE-negative assertions (2026-09-16 remediation, round 2,
finding 7 — was MAJOR, confirmed real by direct investigation).** The
generic sweep's `OWNER`/`AUTHENTICATED` branches used to run the positive
assertion (`assertSucceeds(call(asAlice()))`) and, for `create` specifically,
immediately follow it with the negative principal's assertion on the SAME
document path — with an explicit comment noting the fixture was
deliberately NOT re-seeded because "create just made it exist". That is the
bug: Firestore's rules engine decides `create` vs. `update` by whether the
document ALREADY EXISTS (`resource == null`), never by which client SDK
method was called — so the negative principal's `setDoc` against a document
Alice's own positive call just created is evaluated as an `update`, not a
`create`. For any collection where create/update access genuinely diverge,
this negative case would silently stop proving anything about `create`
while still reporting green. Fixed with a distinct, never-seeded
`negPath` (`ownerPath` with its trailing `fixtureDoc` id swapped for
`fixtureDocNeg`) for the create-negative call in both the `OWNER` and
`AUTHENTICATED` branches (the only two with a positive-then-negative
sequence on the same collection for `create` — `PUBLIC` has no negative
case, `NONE` never has a preceding positive on the same document), plus a
self-verifying `assertNegPathIsFreshForCreate()` guard that reads `negPath`
with security rules disabled immediately before the negative call and
throws loudly if it already exists — a backstop against a future
regression silently reintroducing the reused-fixture bug (e.g. someone
"simplifying" `negPath` back to `ownerPath`) without a visible test
failure to show for it.

## 7. Mutation-proof test (`scripts/ci/test_check_data_access_policy.js`)

Mirrors `verify_deployment_isolation.py`'s `run_broken_identity_probe()`
pattern: an `__dirname`-relative temp copy of the minimal real subset (the
checker + its parser lib, the real `firestore.rules`, the real, already-
valid `data_lifecycle_policy.json`, the real emulator test file, the real
`P2CollectionPaths` registry file) — never the tracked source itself — a
real deterministic mutation, a real subprocess invocation of the real
checker, cleanup in `finally`. A baseline sanity check (unmutated temp
copy must itself be GREEN) runs first, for the same reason
`run_broken_identity_probe()`'s own baseline build does: an already-broken
instrument produces failures for the wrong reason.

Five independent failure classes, each proven **RED** (mutation injected)
then **GREEN** (the corresponding correct declaration/registration added —
never merely undone):

- **(a)** an undeclared literal `.collection('sensitive_new')` under
  `functions/src` → fails, names the gap; fixed by declaring it.
- **(b)** the same shape under `functions-equipment-identity/src`
  specifically → fails; proves the new source root is actually wired into
  discovery, not just documented.
- **(c)** the leaf name `profile`, reused under a structurally different
  injected parent path (`/admin/{adminId}/profile/{docId}`) → fails to
  find a declaration for the NEW path rather than silently treating it as
  covered by the existing `users/{uid}/profile` entry — proves
  path-awareness, not leaf-collapse.
- **(d)** a `CONDITIONAL` cell's `conditionalRefs` pointed at a real,
  existing test that exercises a DIFFERENT operation (a read-only test
  cited for an `update` declaration) → rejected on the SDK-call mismatch.
- **(e)** a non-literal `.collection(SomeUnregisteredConst.value)` call
  (unregistered base identifier) under a production root → fails, naming
  the call site; fixed by genuinely **registering** the constant (not
  deleting the call site) plus declaring the collection it resolves to.
  A companion **positive** case confirms the real
  `P2CollectionPaths.textKeys` registration resolves
  `equipment_model_text_keys` with zero hand-mapping, proving the actual
  gap that motivated this whole plan revision is genuinely closed.

**2026-09-16 remediation — six more classes**, one per item in the cold
second-round internal review (`core/DECISION_LOG.md`'s "Row 24 gate"
entry has the full findings text):

- **(f)** [item 1, was the BLOCKER] a CONDITIONAL cell's `conditionalRef`
  pointed at a real, correctly-SHAPED test (right SDK call, both asserts)
  for a DIFFERENT collection entirely → fails naming the path mismatch;
  fixed by pointing it back at a real same-collection test.
- **(g)** [item 2, was MAJOR ×2, independently found by both reviewers] a
  dedicated restrictive block NOT excluded from the generic wildcard's own
  per-verb exclusion list → fails naming the specific missing
  `coll != '<leaf>'` clause; fixed by adding it.
- **(h)** [item 3, was MAJOR] a second `allow write` statement for an
  already-populated verb within one block → fails rather than silently
  keeping only the last one; the real, unmodified rules file has no such
  duplicate.
- **(i)** [item 4, was MAJOR] a one-line helper function wrapping
  `.collection(<bare param>)` → fails naming the exact call site; fixed
  by explicitly registering that exact file:line:arg in
  `KNOWN_AUDITED_DYNAMIC_CALL_SITES` (renamed from
  `KNOWN_SAFE_BARE_IDENTIFIER_CALLS` in round 2, see below) with a
  documented justification (the only fix path available — the collection
  name itself never appears as a literal anywhere the scanner looks).
- **(j)** [item 5, was MAJOR] a code-discovered `.collection()` call NOT
  chained off `.doc(...)` (this codebase's own real top-level shape) is no
  longer mis-derived as a per-user subcollection → fails naming the
  CORRECT top-level canonical path; still fails if wrongly declared at the
  old, pre-fix subcollection-shaped path (proves the fix changed the
  derived path, not merely relocated the bug); passes once declared at the
  real top-level path.
- **(k)** [item 5, companion] the same code-discovered name reached
  through BOTH call-site shapes (conflicting evidence) → fails naming the
  ambiguity and every conflicting call site, rather than guessing either
  way.

Item 6 (was MINOR — the `profile` CONDITIONAL fixtures not exercising the
`lifestyle.smoking`/`lifestyle.alcohol` bypass clauses) has no
`check_data_access_policy.js` mutation class of its own — it is a gap in
the EMULATOR test fixtures (§6), not in this static checker, closed there
directly rather than through this file's mutation harness.

**2026-09-16 remediation, round 2 — nine more classes**, one per finding in
GPT-PM's own implementation review of round 1 (`core/DECISION_LOG.md`'s
"Row 24 gate: GPT-PM implementation review round 1" entry has the full
findings text), all independently re-verified against the real source
before remediating:

- **(l)** [finding 1, was the BLOCKER] an undeclared `db().doc(\`full/
  path\`)` call under `functions/src` → fails naming the missing
  declaration; fixed by declaring it. Proves Source D is real, not just
  documented.
- **(m)** [finding 2a, was the BLOCKER] a function-call argument to
  `.collection()` (`db.collection(getSensitiveCollectionName())`) with no
  separately-discoverable literal, and no allowlist entry → fails, naming
  the call site and classifying it as a non-literal expression rather than
  silently treating it as residue.
- **(n)** [finding 2b, companion] string concatenation
  (`db.collection(prefix + 'sensitive')`) → same treatment, fails naming
  the call site.
- **(o)** [finding 2, positive counterpart] the REAL `account_export.ts`
  dynamic call sites (`sub()`'s interpolated template at :64, `owned()`'s
  bare `collection` param at :100, `one()`'s bare `path` param at :88) all
  resolve as documented, individually AUDITED residue — not violations —
  confirming the narrowed (per-site, not per-expression-class) exemption
  policy still lets legitimate, already-covered production code through.
- **(p)** [finding 3, was the BLOCKER] a CONDITIONAL cell's
  `conditionalRef` test whose REAL `assertSucceeds`/`assertFails` calls
  target a DIFFERENT collection (`_canary`), with an unrelated, UNUSED
  `doc()` reference to the declared `profile` path sitting elsewhere in the
  same test body (outside either assert call) → fails naming the path
  mismatch — proving the fix actually binds the SDK-shape and path checks
  to the SAME assertion, not independent facts about the whole body (the
  gap `(f)`'s own remediation left one level deeper).
- **(q)** [finding 4, was MAJOR] a locally-shadowed, UNIMPORTED
  `P2CollectionPaths` constant with different values, in a file that never
  imports the real registry → fails, naming the call site — no longer
  silently resolves to the registered export's real value by identifier
  spelling alone. The positive counterpart (the real, legitimately-imported
  `P2CollectionPaths.textKeys` usage) is `(e-positive)` above.
- **(r)** [finding 5, was MAJOR] a `.doc(getUid())` call — a NESTED paren
  inside the argument — chained into a further `.collection(...)` is still
  correctly recognized as a per-user subcollection, not misclassified as
  top-level the way the old regex-based detector would have.
- **(s)** [finding 6, was MAJOR, dormant] two distinct top-level match
  blocks sharing a leaf/root segment (`/admin/{adminId}/profile/{docId}`
  and `/admin/{adminId}/audit/{docId}`, both rooted at `admin`) are BOTH
  independently discovered (neither silently drops out of the candidate set
  the way the old leaf-keyed Map would have) AND each declared
  `clientAccess` entry is validated against its OWN block's rules — a
  wrong access value cross-assigned from the OTHER same-leaf block's rules
  still fails.

Finding 7 (was MAJOR — the generic sweep's create-negative fixture reuse,
confirmed real by direct investigation) has no `check_data_access_policy.js`
mutation class of its own, per the remediation instructions: it is a defect
in the EMULATOR test's own fixture-seeding (§6), not in this static
checker, and the harness here tests the STATIC checker, not the emulator
test's internal correctness. Closed directly in §6 instead, with a
self-verifying in-test guard rather than a mutation-proof class.

**2026-09-16 remediation, round 3 — five more classes (this project's
standing 3-round GPT-PM review cap; last round available)**, one per finding
in GPT-PM's own implementation review of round 2 (`core/DECISION_LOG.md`'s
"Row 24 gate: GPT-PM implementation review round 2" entry has the full
findings text), each reproducing GPT-PM's OWN adversarial scenario verbatim
(not an easier nearby case) and each independently, empirically confirmed
against the PRE-FIX code before remediating (not merely reasoned about):

- **(t)** [BLOCKER 1] a FULLY LITERAL `db().doc("users/alice/sensitive_new/
  current")` — no template interpolation anywhere — fails, naming the
  missing declaration for `/users/{uid}/sensitive_new/{docId}`; fixed by
  declaring it. Distinct from `(l)` above, which only ever tested the
  templated `${uid}` case (already wildcarded to `*`, which happened to
  satisfy the OLD buggy `segs[1] === '*'` gate) — `(t)`'s literal uid value
  ("alice") is exactly what that old gate rejected. Pre-flight-verified
  against the real pre-fix checker: this exact fixture produced a clean
  exit 0 with zero discovered paths.
- **(u)** [BLOCKER 2] a CONDITIONAL test's `assertSucceeds` contains a real
  `updateDoc(doc(asCanary(), \`_canary/${CANARY_UID}\`), {...})` call
  (targeting `_canary`) PLUS a decoy `doc(asAlice(), \`users/${ALICE}/
  profile/main\`)` reference INSIDE THE SAME `assertSucceeds` argument, but
  in `updateDoc`'s own PAYLOAD object (its SECOND argument) — never as the
  document being updated (`updateDoc`'s FIRST argument) — fails, naming the
  path mismatch against `users/*/profile`; fixed by pointing the
  `conditionalRef` back at a real profile-path test. Reproduces GPT-PM's
  own exact scenario (`assertSucceeds(updateDoc(doc(db,'_canary/x'),
  {ref: doc(db,'users/alice/profile/main')}))`) verbatim, adapted to this
  test file's own helper names. Pre-flight-verified: the pre-fix
  `analyzeAssertCalls()` returned `{ok: true}` for this exact scenario.
- **(v)** [MAJOR] a file that legitimately imports `P2CollectionPaths` at
  the top AND has a FUNCTION-PARAMETER shadow of the same name
  (`function handler(db, P2CollectionPaths) {...}`) at the actual
  `.collection(...)` call site — fails, naming the now-untrusted
  `P2CollectionPaths.textKeys` expression. Pre-flight-verified: the pre-fix
  `registryBindingHolds()` returned `true` (bound) for this exact scenario.
- **(w)** [MAJOR, companion] the same shadow gap via an INNER-SCOPE `const`
  re-declaration inside a function body instead of a parameter — GPT-PM's
  own second stated example shape — fails the same way.
- **(v-positive)** the REAL, unmodified, legitimately-imported (non-
  shadowed) `functions-equipment-identity/src/p2/text_key_index.ts` usage
  of `P2CollectionPaths.textKeys` (both call sites) still resolves via the
  registry with zero violations — confirms the shadow-detection fix is not
  so broad it breaks the one genuine production call site it must keep
  trusting.

**2026-09-16 remediation, round 4 — four more classes (this gate's own
terminal round; GPT-PM's `VERDICT: APPROVE` on the round-cap process
question authorized exactly one further round against exactly the 2 named
findings below, no fresh whole-mechanism sweep)**, per finding in GPT-PM's
own implementation review of round 3 (`core/DECISION_LOG.md`'s "Row 24
gate: GPT-PM implementation review round 3" entry has the full findings
text):

- **(x)** [BLOCKER] a `Promise.all([updateDoc(profileRef, validPatch),
  updateDoc(invalidCanaryRef, ...)])`-wrapped `assertFails` for a
  `profile`/`update` `conditionalRef` → fails as `'shape'` (not a direct
  SDK-call-shaped argument), naming "no update-shaped Firestore SDK call" —
  proves the OLD (round-3) code's own would-be wrong certification path
  (matching the profile `updateDoc` call buried inside the `Promise.all`)
  is now closed.
- **(y)** [BLOCKER, companion] an `assertFails` argument that is a bare
  STRING LITERAL whose text happens to look like a real `updateDoc`/`doc()`
  call targeting the declared `profile` path (plus a second decoy sitting
  in an unrelated `console.log(...)` call entirely outside both assertions)
  → fails the same way, naming "no update-shaped Firestore SDK call" —
  proves a decoy substring can never be mistaken for real evidence, whether
  it sits inside a wrapper's own text or entirely outside both assert
  calls.
- **(z)** [MAJOR] a file that legitimately imports `P2CollectionPaths` at
  the top AND has an OBJECT-DESTRUCTURING local shadow of the same name
  inside a function body (`const { P2CollectionPaths } = runtimePaths;`) at
  the actual `.collection(...)` call site → fails, naming the now-untrusted
  `P2CollectionPaths.textKeys` expression — invisible to BOTH halves of the
  pre-round-4 detector simultaneously (see §4's own updated subsection).
- **(z-positive)** a legitimate file-level `P2CollectionPaths` import, in a
  file that ALSO destructures a totally DIFFERENT identifier name nearby
  (`const { SomeOtherPaths } = runtimePaths;`), is NOT falsely flagged as
  shadowed — confirms the new destructuring-shape regexes are anchored to
  the exact registered identifier name, not triggered by any destructuring
  pattern anywhere in the file. The REAL, unmodified, non-shadowed
  `text_key_index.ts` usage is independently re-confirmed GREEN by
  `(v-positive)` above, re-run against the destructuring-extended shadow
  detector as part of this same round-4 test run.

## 8. Backfill

All 37 collections `check_data_lifecycle_coverage.js` itself now discovers
carry a `clientAccess` declaration. Two collections
(`equipment_model_text_keys`, `equipment_identity_latest_session`) had **no
lifecycle policy entry at all** before this gate — a pre-existing gap on
the retention axis, confirmed live (`check_data_lifecycle_coverage.js`
reported both "in use with NO lifecycle policy entry" before this
backfill) — fixed as a byproduct rather than left half-declared; see
"Deviations" below.

Notable non-obvious declarations, each traced to its actual rules block
rather than assumed:

- `subscription.{create,update,delete}` = `NONE` — excluded from the
  wildcard's write grant (`coll != 'subscription'`) and picked up by no
  dedicated block; Firestore's own implicit default-deny, not an explicit
  `if false`. **Before Source D existed, `subscription` had NO discovery
  source requiring it at all** — reached only via `db.doc(\`users/${uid}/
  subscription/main\`)` calls in `functions/src/index.ts`, invisible to
  Source B's `.collection()`-only scan. The 37/37-clean result was real but
  accidental: nothing would have failed CI if this entry had quietly drifted
  wrong. Now genuinely required and validated via Source D.
- `profile.delete` = `NONE` — see §3's `request.resource`-on-delete
  refinement; empirically confirmed, not inferred.
- `debug_sessions.create` = `CONDITIONAL` (field-stamped uid + shape/size
  validation); its `read`/`update`/`delete` are `NONE` (`if false` /
  no verb granted).
- `_canary.{read,create,update,delete}` = `CONDITIONAL` — the canary
  custom-claim check is never bare uid-equality.
- Nine subcollections ride the wildcard with no dedicated block at all
  (`workout_logs`, `workout_sessions`, `scheduled_sessions`, `programmes`,
  `machine_cards`, `recognised_equipment`, `generated_exercises`,
  `equipment_setup_notes`, `stats`) — all `OWNER` for all four operations,
  discovered via Source B (the mobile app's own literal
  `.collection('workout_logs')`-shaped calls), never via Source A.

## 9. Known, documented scope limits

**Every non-literal `.collection()`/`.doc()` shape now hard-fails by
default (2026-09-16 remediation, round 2, finding 2 — see §4).** Round 1
exempted a whole EXPRESSION CLASS (any template interpolation, function
call, or string concatenation) as non-blocking "residue"; round 2 narrowed
that to individually audited call sites only, in
`KNOWN_AUDITED_DYNAMIC_CALL_SITES` (renamed from the narrower, bare-
identifier-only `KNOWN_SAFE_BARE_IDENTIFIER_CALLS`), pinned by exact
`{file, line, arg}`, never by expression shape or name alone. Every current
entry, individually verified against the real repository as of 2026-09-16
(not carried forward on faith):

| File:line | Argument | Verified target | Why it's already covered elsewhere |
| --- | --- | --- | --- |
| `account_export.ts:64` | `` `users/${uid}/${name}` `` | varies per call site | `sub()`'s real call sites (`sub(uid, "workout_logs", truncated)`, …) pass literals Source B discovers independently in `mobile/lib` (or Source A for `receipts`) |
| `account_export.ts:100` | `collection` | varies per call site | `owned()`'s real call sites (`owned("coach_bookings", ...)`, …) pass literals Source B discovers independently in this same file |
| `account_export.ts:88` | `path` | varies per call site | `one()`'s real call sites pass literal templates; each target (`profile`, `subscription`, `stats`, `donor_wall`, `coach_listings`) is independently discoverable/declared elsewhere (dedicated rules block, Source D at other call sites, or Source B in `mobile/lib`) |
| `catalog_reader.ts:35` | `CATALOG_ACTIVE_POINTER_DOC_PATH` | `equipment_catalog_active` | fixed module-level constant, dedicated rules block |
| `catalog_reader.ts:53` | `path` | `equipment_models` | assigned one line above from `modelDocPath(...)`, dedicated rules block |
| `session_repository.ts:209,315,364` | `userEquipmentIdentitySessionDocPath(uid, sessionId)` | `equipment_identity_sessions` | fixed literal template inside the function, dedicated rules block |
| `session_repository.ts:210,316,380` | `userEquipmentIdentityLatestSessionDocPath(uid)` | `equipment_identity_latest_session` | fixed literal template inside the function, dedicated rules block |
| `telemetry_repository.ts:133,323` | `userEquipmentIdentityTelemetryDocPath(uid, scanId)` | `equipment_identity_telemetry` | fixed literal template inside the function, dedicated rules block |

Printed on every run as documented, individually audited residue, never
hidden — the check for each entry is "does the reasoning still hold", not
"does the shape still match", since a new call site with the exact same
SHAPE (a new function-call argument, say) is NOT covered by any of these
entries (the match is file+line+arg, never shape or name alone) and hard-
fails until it is either fixed to pass a literal, or audited and added as
its own new entry.

- The scanner's property-access detection is `Identifier.member` only —
  one dot, two plain identifiers. A chained or computed access
  (`Foo.Bar.baz`, `Foo['bar']`) is classified `'dynamic'` (2026-09-16
  remediation, round 2) and hard-fails like any other unresolved shape,
  UNLESS individually audited into `KNOWN_AUDITED_DYNAMIC_CALL_SITES`. No
  such shape exists in this repo today.
- **Registry import-binding is lightweight, not a real module resolver**
  (2026-09-16 remediation, round 2, finding 4 — see §4/§3).
  `registryBindingHolds()` recognizes only a plain relative
  `import { Name } from './relative/path'` (or same-file definition) — a
  path alias, a package-style import, a re-export, or an
  `import { P2CollectionPaths as X }` rename is not resolved this way and
  does not bind, failing closed exactly like every other unresolved shape.
  No such import style is used for `P2CollectionPaths` in this repo today.
- **Source D's own scope boundary is a POSITIVE `db`/`db()`/`_db`-root
  check, not a general "is this call chained off a known collection"
  resolver** (2026-09-16 remediation, round 2, finding 1 — see §4's own
  "Scope boundary" subsection). A `.doc(<arg>)` call chained off anything
  other than the literal Firestore root — a stored variable, a getter, a
  helper method's return value — is invisible to Source D entirely (never
  scanned as a candidate, never flagged as a violation either). This is
  deliberate: every real relative document-id call in this codebase is
  exactly that shape, and treating it as a full-path candidate would flood
  CI with false failures (confirmed live: 16 of them, across 8 `mobile/lib`
  files, before this fix landed). The residual risk is the inverse of
  round 1's own `chainedOffDoc` risk below — a genuinely NEW full-path
  `.doc()` call written through an indirection (e.g. a helper function
  wrapping `db.doc(...)` and returning the ref) would be invisible to
  Source D and to the fail-closed scanner alike. No such indirection exists
  in this repo today (verified by reading every `.doc()` call site).
- **`chainedOffDoc`/Source D's own chain detection is balanced-paren
  POSITION matching (2026-09-16 remediation, round 2, finding 5), not a
  verified reference chain.** It is still a text-adjacency check, now
  correct regardless of what is nested inside either call's own argument
  list (see §4's own subsection), but it remains a heuristic: a
  `.collection()` call chained off an unrelated `.doc(someOtherId)` for a
  non-per-user reason would be misread as a per-user subcollection. No such
  shape exists in this repo today (verified by reading every real call
  site); a genuinely conflicting one is caught as `AMBIGUOUS`, not silently
  misclassified, only when the SAME collection name is reached through both
  shapes.
- **No full TypeScript type-checker or AST parser anywhere in this gate —
  every TypeScript-reading part of it (discovery, the CONDITIONAL-ref
  verifier, the shadow detector) is regex/lightweight-text-based LEXICAL
  SCANNING, by design, per the approved plan's own scope.** Stated
  explicitly and honestly here, at the end of four remediation rounds, so
  it reads as the deliberate architectural choice it is rather than an
  implied gap discovered by accident: this checker never builds a real
  syntax tree, never resolves identifiers through actual lexical scoping,
  and never type-checks an expression. It recognizes a fixed set of textual
  SHAPES (a balanced-paren call, a quoted string/template literal, a
  `const`/`let`/`var`/destructuring declaration, an import statement) and
  reasons about them positionally. Every remediation round in this
  document's history — four rounds, roughly a dozen named findings — has
  been a new adversarial shape the lexical scanner did not yet recognize,
  closed by teaching it one more shape, never by giving it real parsing.
  This is a genuine, accepted trade-off for THIS gate's scope (a CI text
  check with no build step, no `npm install`, no TypeScript compiler
  dependency, matching `check_data_lifecycle_coverage.js`'s own already-
  established lightweight-parsing precedent) — not a defect to silently
  work around with one more regex indefinitely. A real AST-based rewrite
  (parsing with the TypeScript compiler API or a similar real parser,
  closing this whole CLASS of "a new adversarial shape the lexical scanner
  doesn't recognize" finding at the root, rather than one shape at a time)
  is real, useful future work — GPT-PM's own round-3 Option C, explicitly
  deferred to a separate, future, larger gate rather than attempted
  piecemeal inside this one's own remediation rounds. Tracked as backlog,
  not attempted here.
- **CONDITIONAL-ref path verification cannot trace a document reference
  held in a variable** (2026-09-16 remediation, round 3, BLOCKER 2's own
  residual — see §5; STILL OPEN after round 4, not touched by it). Round
  4's `wholeSdkCallExpression()` requires the assertion argument to itself
  be a whole SDK call, but the SDK call's own document-reference argument
  is still resolved only when it is an INLINE `doc(...)` call; `const ref =
  doc(...); updateDoc(ref, data)` is invisible to it (the site is skipped,
  contributing neither shape nor path evidence). Checked against the real
  test suite: none of the 7 hand-written `conditionalRefs` tests in
  `data_access_policy.test.ts` use this pattern today. The failure mode is
  safe if this pattern is ever introduced (fails closed — `reason: 'shape'`
  or `'path'`), never a silent false pass.
- **The assertion-argument structural check (round 4) is itself a lexical
  shape test, not a real expression evaluator** — see the new,
  general "No full TypeScript type-checker or AST parser" bullet above.
  `wholeSdkCallExpression()` accepts an SDK call plus one optional trailing
  comma as the ENTIRE trimmed argument; any other wrapper (`Promise.all`,
  `await`, a helper function, a string literal) is rejected, per design —
  but a genuinely new, currently-unwritten JS/TS syntax for "one call,
  nothing else" that this text-based check does not anticipate (e.g. a
  parenthesized SDK call, `(updateDoc(...))`, with redundant grouping
  parens) would also be rejected, failing closed (`reason: 'shape'`), not
  silently accepted — the safe direction, at the cost of a spurious
  failure a developer would have to reshape the test to avoid. No such
  syntax is used anywhere in the 7 real hand-written `conditionalRefs`
  tests today.
- **Registry shadow-detection is a whole-file, conservative name scan, not
  real lexical-scope resolution** (2026-09-16 remediation, round 3, MAJOR,
  extended round 4 to also recognize destructuring bindings — see the
  "Registry import-binding is call-SITE-scope-aware" subsection in §4).
  `hasLocalShadowDeclaration()` treats ANY other declaration of the
  registered identifier's exact name ANYWHERE in the file — a plain
  declaration, a function/arrow parameter, or (round 4) an object/array
  destructuring binding — as a potential shadow, deliberately without
  verifying the declaration's scope actually reaches the specific
  `.collection(Ident.member)` call site (no AST, no real block-scope
  tracking). Still not exhaustive of every JS/TS binding FORM a real parser
  would recognize (e.g. a nested/renamed destructuring pattern like
  `const { paths: { P2CollectionPaths } } = x;`, or a destructured function
  parameter `function f({ P2CollectionPaths }) {}`) — any such form not
  matched by the three regexes (`const|let|var IDENT`, object destructuring,
  array destructuring) plus the parameter balanced-paren scan is invisible
  to the detector, same residual-gap shape as every other lexical-scanning
  limit in this section. No such form is used for `P2CollectionPaths`
  anywhere in this repo today (verified by reading every real call site).
  This can also over-flag a file that reuses the
  same name in an unrelated, genuinely non-shadowing way (e.g. a totally
  separate function elsewhere in the file that happens to name a local
  variable `P2CollectionPaths` for something unrelated) — accepted as the
  safe direction for a CI gate (a false failure costs a rename; a false
  pass is the security gap this checker exists to catch). No such
  unrelated reuse exists in this repo today (verified: the real
  `text_key_index.ts` usage stays green, §7's `(v-positive)`).

## 10. Deviations from the approved design (flagged for review)

1. **Two missing lifecycle-policy entries backfilled with full new rows**
   (classification + reason + clientAccess), not merely a `clientAccess`
   field added to an existing row — because no existing row existed for
   `equipment_model_text_keys` / `equipment_identity_latest_session`. The
   plan's own wording ("ADD a new field to each entry") assumed every
   discovered collection already had an entry; two did not. Fixed as part
   of this gate's own backfill duty ("every discovered path … needs a
   clientAccess declaration") rather than left half-declared.
2. **`profile.delete` declared `NONE`, not `CONDITIONAL`** — an
   empirically-forced correction (§3/§8), not a simplification: declaring
   it `CONDITIONAL` would have been WRONG (there is no real two-outcome
   condition for a delete request, only unconditional denial via a rule
   evaluation error), and would have made §6's own "both an assertSucceeds
   and an assertFails" requirement unsatisfiable for this cell (there is no
   payload that makes a profile delete succeed).
3. **The static checker's classification-consistency rule is stricter than
   literally specified.** The approved design only mandates refusing
   `OWNER` where the rules are `NON_TRIVIAL`. This implementation also
   refuses a looser-than-actual declaration (`NONE` where the rules
   actually grant something) and a mismatched `AUTHENTICATED`/`PUBLIC`
   declaration — the same principle applied symmetrically, since an
   under-claiming declaration hides a real grant from anyone reading the
   policy instead of the rules file, which is exactly the kind of drift
   this gate exists to prevent.
4. **All seven `CONDITIONAL` cells got freshly-written, dedicated,
   single-operation tests** rather than reusing existing narrative tests
   from the 1016-line suite, even though the plan's own text preferred
   reuse where possible. On inspection, no existing test isolates a single
   operation with both a clean success and a failure case in one block —
   reusing them would have meant brittle text-archaeology against tests
   shaped for a different purpose. This is an application of the plan's
   own fallback clause ("only write a new emulator test if no existing one
   already proves the specific operation"), not a departure from it.
