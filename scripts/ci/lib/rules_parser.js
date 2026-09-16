// P2-ACCESS-1 (Firestore Access-Control Drift Guard) -- shared rules-body
// parser used by scripts/ci/check_data_access_policy.js.
//
// Extracts every `match` block in firestore.rules (full path, not just the
// leaf segment -- unlike check_data_lifecycle_coverage.js's own
// collectionsFromRules(), which only needs the leaf name for its retention
// axis) and classifies each block's `allow` condition PER VERB as one of:
//
//   PLAIN_OWNER   -- bare `request.auth != null && request.auth.uid == X`,
//                    nothing else (X is whatever path variable that match's
//                    OWN path binds -- `uid`, `canaryUid`, ...).
//   ALWAYS_FALSE  -- `if false`, verbatim.
//   NON_TRIVIAL   -- any other condition: extra clauses, field checks, role
//                    checks, `if true` (open/PUBLIC), `request.auth != null`
//                    alone with no uid comparison (AUTHENTICATED), etc.
//   IMPLICIT_DENY -- no `allow` clause covers this verb at all in this block
//                    (Firestore's own default-deny). Only meaningful for the
//                    generic wildcard's per-collection resolution below --
//                    a *dedicated* block in this file always states every
//                    verb it grants explicitly via `allow read, write: ...`
//                    or a full `allow read, create, update, delete: ...`,
//                    so IMPLICIT_DENY never applies inside collectionAccess()
//                    for a dedicated block, only when a collection rides
//                    (or is excluded from) the generic wildcard with nothing
//                    else picking up the slack -- see `subscription`, whose
//                    write is excluded from the wildcard and granted by no
//                    other block in this file.
//
// `NON_TRIVIAL` is intentionally not itself split into "role check" /
// "field check" / "public" / "authenticated-only" sub-kinds here -- the
// caller (check_data_access_policy.js) additionally derives AUTHENTICATED
// and PUBLIC as their own access values from the SAME condition text
// (bare `request.auth != null` / `if true`) precisely because those two are
// legitimate final `clientAccess` declarations in their own right, not
// something that must be downgraded to CONDITIONAL. Everything that is
// neither bare-owner, always-false, bare-authenticated nor bare-public is
// where CONDITIONAL is mandatory.
//
// Deliberately NOT a general CEL parser (the plan's own guidance: "regex or
// lightweight text parsing is fine -- no full TypeScript type-checker
// needed"). What IS done properly rather than by naive line regex: match
// BLOCK BODIES are extracted by brace-depth counting, not by a non-greedy
// regex up to the next `}` -- this file's match bodies happen to contain no
// nested `{}` today (CEL array literals use `[...]`, and the two helper
// functions `healthIsStripped`/`flagsAreStripped` are declared as SIBLINGS
// of the match blocks, not nested inside one), but a checker that assumes
// that structurally rather than verifying it is a claim, not a result --
// see the "no material issue found" framing this repo's other checkers use
// for exactly this kind of shortcut.
'use strict';

const fs = require('fs');

/** Every collection-name EXCLUSION clause in the generic wildcard's own
 * condition (`coll != 'x'`) is structural ELIGIBILITY, not an access
 * decision about the collections that are NOT excluded -- it says "this
 * block does not govern this name at all", which is a routing fact the
 * caller already has (a dedicated block exists for that name), not part of
 * the OWNER-ness of the grant for the collections that remain. Likewise
 * `!isCanaryToken()` is uniform structural boilerplate applied identically
 * regardless of which collection is being reached, exactly like
 * `request.auth != null` already is for the PLAIN_OWNER pattern itself.
 * Both are stripped before judging whether what's left is bare uid-equality.
 * This stripping is applied ONLY to the block whose own path is the literal
 * generic-wildcard shape (`/users/{uid}/{coll}/{document=**}`) -- never to
 * any other block, where a matching clause would be a REAL, non-structural
 * condition.
 */
const GENERIC_WILDCARD_PATH = '/users/{uid}/{coll}/{document=**}';

const VERB_GROUPS = {
  read: ['read', 'get', 'list'],
  create: ['write', 'create'],
  update: ['write', 'update'],
  delete: ['write', 'delete'],
};
const ALL_VERBS = ['read', 'create', 'update', 'delete'];

/** Normalize whitespace/newlines inside a condition so regex matching does
 * not have to account for line wraps. */
function normalizeCondition(text) {
  return text.replace(/\s+/g, ' ').trim();
}

/** Split `allow a, b, c: if <cond>;` (or `allow a, b: if <cond>` without a
 * trailing `;` right before `}`) into `{verbs: ['a','b','c'], cond}`. */
function parseAllowStatements(body) {
  const out = [];
  const re = /allow\s+([a-zA-Z,\s]+?)\s*:\s*if\s+([\s\S]*?);/g;
  let m;
  while ((m = re.exec(body)) !== null) {
    const verbs = m[1].split(',').map((v) => v.trim()).filter(Boolean);
    out.push({ verbs, cond: normalizeCondition(m[2]) });
  }
  return out;
}

/** Expand a raw rules verb (`read`/`write`/`get`/`list`/`create`/`update`/
 * `delete`) into the subset of the four operations this parser tracks. */
function expandVerb(rawVerb) {
  switch (rawVerb) {
    case 'read':
    case 'get':
    case 'list':
      return ['read'];
    case 'write':
      return ['create', 'update', 'delete'];
    case 'create':
      return ['create'];
    case 'update':
      return ['update'];
    case 'delete':
      return ['delete'];
    default:
      return [];
  }
}

/**
 * `request.resource` does not exist on a `delete` request (there is no new
 * document to describe) -- confirmed empirically against the real emulator
 * while building this gate: `profile`'s write condition, which is one
 * `allow write` statement covering create/update/delete identically and
 * reads `request.resource.data.health`, errors on EVERY delete attempt
 * ("Null value error ... for 'delete'"), and a rule that errors denies.
 * That is not a real two-outcome condition for delete -- it is
 * unconditional denial, textually disguised as the same NON_TRIVIAL
 * condition that genuinely gates create/update. Generalized here (any
 * `delete`-verb condition that mentions `request.resource` is
 * ALWAYS_FALSE) rather than special-cased to `profile` by name, since the
 * same shape would silently misclassify any future collection whose
 * write rule is field-conditioned the same way.
 */
function deleteReferencesResource(cond) {
  return /request\.resource/.test(cond);
}

/** Classify ONE already-normalized condition string for a NON-wildcard
 * block. `pathVar` is the path variable this match's own path binds that a
 * bare-owner check would compare against (e.g. `uid` for
 * `/users/{uid}/profile/{docId}`, `canaryUid` for `/_canary/{canaryUid}`).
 * `verb` is one of the four tracked operations -- see
 * `deleteReferencesResource` for the one case classification depends on it. */
function classifyCondition(cond, pathVar, verb) {
  if (cond === 'false') return 'ALWAYS_FALSE';
  if (verb === 'delete' && deleteReferencesResource(cond)) return 'ALWAYS_FALSE';
  if (cond === 'true') return 'PUBLIC';
  const ownerRe = new RegExp(
    `^request\\.auth\\s*!=\\s*null\\s*&&\\s*request\\.auth\\.uid\\s*==\\s*${pathVar}$`,
  );
  if (ownerRe.test(cond)) return 'PLAIN_OWNER';
  if (/^request\.auth\s*!=\s*null$/.test(cond)) return 'AUTHENTICATED';
  return 'NON_TRIVIAL';
}

/** Classify ONE already-normalized condition string for the GENERIC
 * WILDCARD block specifically -- see the module doc comment for why this is
 * a distinct code path rather than a case inside classifyCondition(). */
function classifyWildcardCondition(cond) {
  if (cond === 'false') return 'ALWAYS_FALSE';
  if (cond === 'true') return 'PUBLIC';
  let stripped = cond
    .replace(/request\.auth\s*!=\s*null/g, '')
    .replace(/!\s*isCanaryToken\(\)/g, '')
    .replace(/coll\s*!=\s*'[^']*'/g, '')
    .replace(/&&/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (stripped === 'request.auth.uid == uid') return 'PLAIN_OWNER';
  if (stripped === '') return 'AUTHENTICATED';
  return 'NON_TRIVIAL';
}

/** Every `coll != 'x'` name excluded from the wildcard's condition for ONE
 * verb group (read or write, as written in the rules -- the source file
 * only ever excludes at that granularity today). */
function wildcardExclusions(cond) {
  const names = new Set();
  const re = /coll\s*!=\s*'([^']*)'/g;
  let m;
  while ((m = re.exec(cond)) !== null) names.add(m[1]);
  return names;
}

/**
 * Parse firestore.rules text into an array of match-block records:
 *   {
 *     matchPath: '/users/{uid}/profile/{docId}',
 *     segments: ['users','{uid}','profile','{docId}'],
 *     isGenericWildcard: false,
 *     pathVar: 'uid',            // path variable a bare-owner check binds
 *     verbs: {
 *       read:   { classification: 'PLAIN_OWNER', raw: '...' },
 *       create: { classification: 'NON_TRIVIAL', raw: '...' },
 *       update: { classification: 'NON_TRIVIAL', raw: '...' },
 *       delete: { classification: 'NON_TRIVIAL', raw: '...' },
 *     },
 *     wildcardExclusions: { read: Set(...), create: Set(...), ... }, // only
 *       // populated (non-empty) on the generic wildcard block itself
 *   }
 */
function parseFirestoreRules(rulesText) {
  const blocks = [];
  // Anchored the same way check_data_lifecycle_coverage.js's own
  // collectionsFromRules() already is, and for the identical reason: a path
  // segment's own `{var}` is always followed by more path content on the
  // SAME line, so the only `{` that can be the LAST non-whitespace
  // character on a `match ...` line is the real body-opening brace -- a
  // naive "first `{`" scan (this module's own first draft) stops at a
  // path variable's opening brace instead, found live while sanity-checking
  // this parser against the real rules file (every block resolved as if it
  // had zero `allow` statements).
  const matchHeaderRe = /^\s*match\s+(\/.+?)\s*\{\s*$/gm;
  let header;
  while ((header = matchHeaderRe.exec(rulesText)) !== null) {
    const matchPath = header[1].trim();
    const bodyStart = header.index + header[0].length;
    // Brace-depth scan from just after the opening `{` to its match.
    let depth = 1;
    let i = bodyStart;
    for (; i < rulesText.length && depth > 0; i++) {
      if (rulesText[i] === '{') depth++;
      else if (rulesText[i] === '}') depth--;
    }
    if (depth !== 0) {
      throw new Error(`rules_parser: unbalanced braces starting at match ${matchPath}`);
    }
    const bodyEnd = i - 1; // position of the matching closing brace
    const body = rulesText.slice(bodyStart, bodyEnd);

    const segments = matchPath.split('/').filter(Boolean);
    const isGenericWildcard = matchPath === GENERIC_WILDCARD_PATH;

    // The path variable a bare-owner check on THIS match would compare
    // against: the last `{var}` segment that is not `{document=**}` and is
    // not the generic wildcard's own `{coll}` routing variable. For every
    // block in this file that is not the generic wildcard, that is simply
    // the LAST `{var}` segment before the doc-id segment closest to `uid`'s
    // own binding position -- concretely, every dedicated per-user block
    // here is `/users/{uid}/<name>/{docId}` (pathVar = uid) or a top-level
    // `/<name>/{id}` with its own single bound variable used as the owner
    // key (e.g. `/_canary/{canaryUid}`, pathVar = canaryUid). Found by
    // taking the FIRST `{var}` segment in the path (excluding `{document=**}`).
    let pathVar = null;
    for (const seg of segments) {
      if (seg.startsWith('{') && seg.endsWith('}') && seg !== '{document=**}') {
        pathVar = seg.slice(1, -1);
        break;
      }
    }

    // A block whose OWN body contains further nested `match` statements
    // (in this file, only the outermost `/databases/{database}/documents`
    // wrapper) is a structural container, not a leaf access-control block
    // -- a flat, non-nested-aware scan of its body would pick up every
    // `allow` statement belonging to EVERY block nested inside it, not
    // statements that actually belong to this block. That was already
    // silently wrong before the duplicate-statement check just above this
    // was added (the wrapper's `verbs` map got overwritten with whatever
    // nested statement happened to be scanned last, then was filtered out
    // downstream by matchPath -- see discoverCandidates()'s own
    // `!== '/databases/{database}/documents'` exclusion); the duplicate
    // check would otherwise misfire on this block treating two DIFFERENT
    // nested blocks' same-named-verb statements as one block's duplicate.
    // Every real leaf block in this file has no nested match statement
    // (verified structurally, see this module's own header comment).
    const bodyHasNestedMatch = /^\s*match\s+\/.+?\s*\{\s*$/m.test(body);
    const allowStatements = bodyHasNestedMatch ? [] : parseAllowStatements(body);
    const verbs = {};
    const wcExclusions = { read: new Set(), create: new Set(), update: new Set(), delete: new Set() };

    for (const stmt of allowStatements) {
      const opsTouched = new Set();
      for (const rawVerb of stmt.verbs) for (const op of expandVerb(rawVerb)) opsTouched.add(op);
      for (const op of opsTouched) {
        // Firestore ORs every `allow <verb>` statement that covers a given
        // operation WITHIN one match block -- a second statement for an
        // op already populated here does not narrow or override the
        // first, it widens the real grant to whichever of the two
        // conditions is true. Silently keeping only the LAST one (the
        // original behavior here) therefore misrepresents the block's
        // real access whenever this shape occurs -- fail closed instead
        // of guessing at how to union two arbitrary CEL conditions. No
        // live block in firestore.rules has this shape today (verified
        // by inspection); this only fires on a genuine future regression
        // or an injected mutation-proof fixture.
        if (verbs[op]) {
          throw new Error(
            `rules_parser: match ${matchPath} declares more than one "allow" statement covering "${op}" ` +
            `(${JSON.stringify(verbs[op].raw)} and ${JSON.stringify(stmt.cond)}) -- Firestore ORs multiple ` +
            'statements for the same verb within one block, so this parser refuses to silently keep only ' +
            'the last one. Combine them into a single condition (with an explicit `||`) or make the second ' +
            'statement cover a different verb.',
          );
        }
        // Classified PER OP, not once for the whole statement: a single
        // `allow write` textually covers create/update/delete identically,
        // but `delete`'s own evaluation semantics differ (no
        // `request.resource`) -- see classifyCondition's own doc comment.
        const classification = isGenericWildcard
          ? classifyWildcardCondition(stmt.cond)
          : classifyCondition(stmt.cond, pathVar, op);
        verbs[op] = { classification, raw: stmt.cond };
        if (isGenericWildcard) {
          for (const name of wildcardExclusions(stmt.cond)) wcExclusions[op].add(name);
        }
      }
    }

    blocks.push({
      matchPath,
      segments,
      isGenericWildcard,
      pathVar,
      verbs,
      wildcardExclusions: wcExclusions,
    });
  }
  return blocks;
}

/** Load and parse firestore.rules from an absolute path. */
function parseFirestoreRulesFile(rulesPath) {
  return parseFirestoreRules(fs.readFileSync(rulesPath, 'utf8'));
}

/**
 * Resolve the effective per-verb classification for ONE concrete collection
 * reached at a specific depth under `/users/{uid}/...` OR as a top-level
 * collection, given the parsed block list.
 *
 * `canonicalPath` is the EXACT declared path text (e.g.
 * `/users/{uid}/profile/{docId}`, `/admin/{adminId}/profile/{docId}`) --
 * matched against each dedicated block's own `matchPath` by EXACT STRING
 * EQUALITY (2026-09-16 remediation, item 6 -- was MAJOR, database-reviewer,
 * Row 24 gate). The original version of this function matched a dedicated
 * block by `leafName`/`segments[0]` alone (a coarse "root" key) -- two
 * distinct dedicated blocks that happen to share a leaf/root segment (e.g.
 * `/admin/{adminId}/profile/{docId}` and `/admin/{adminId}/audit/{docId}`,
 * both rooted at `admin`) would resolve to whichever block `.find()` landed
 * on first, silently validating one declared `clientAccess` entry against a
 * DIFFERENT block's access rules. Every `canonicalPath` this checker ever
 * calls with is already required (by `discoverCandidates()`'s own Source A
 * seeding, and by the coverage check in `main()`) to equal a real block's
 * `matchPath` verbatim for a rules-derived collection, or a
 * `derivePathVars()`-constructed string for a code-only one -- so exact
 * string comparison is not a NEW constraint on the data, only a correction
 * to how this function looks it up.
 *
 * `leafName` is the collection's own bare name (e.g. `workout_logs`,
 * `profile`) -- still needed separately from `canonicalPath`, purely for
 * the generic wildcard's own per-verb exclusion-set lookup below
 * (`coll != '<leaf>'` is keyed by the bare subcollection name in the rules
 * text, not the full path). `isUserSubcollection` says whether to also
 * consult the generic wildcard as a fallback (and, for the exclusion check,
 * whether the wildcard even applies at all -- it only ever governs
 * `/users/{uid}/...` paths).
 *
 * Returns `{ read, create, update, delete }`, each one of PLAIN_OWNER /
 * ALWAYS_FALSE / NON_TRIVIAL / AUTHENTICATED / PUBLIC / IMPLICIT_DENY, plus
 * `source`: 'dedicated' | 'wildcard' | 'none' per verb, so a caller can
 * explain WHY a value was resolved the way it was.
 */
/** A dedicated block's classification for one verb that a caller could read
 * as MORE RESTRICTIVE than an unconditional grant -- the only shapes where
 * trusting the dedicated block alone, without checking the wildcard is
 * actually excluded, could certify a too-permissive declaration as safe. */
function isRestrictiveClassification(cls) {
  return cls === 'ALWAYS_FALSE' || cls === 'NON_TRIVIAL';
}

/** Whether the generic wildcard's OWN condition for this verb would still
 * grant something (anything short of an outright, unconditional deny) to a
 * leaf that is not excluded from it. */
function wildcardWouldGrant(cls) {
  return !!cls && cls !== 'ALWAYS_FALSE';
}

function collectionAccess(blocks, canonicalPath, leafName, isUserSubcollection) {
  const dedicated = blocks.find((b) => !b.isGenericWildcard && b.matchPath === canonicalPath);

  const wildcard = isUserSubcollection ? blocks.find((b) => b.isGenericWildcard) : null;

  const result = {};
  for (const op of ALL_VERBS) {
    if (dedicated && dedicated.verbs[op]) {
      const dedicatedCls = dedicated.verbs[op].classification;
      // Firestore ORs every matching rule together -- a dedicated block
      // that reads MORE restrictive than the generic wildcard would
      // otherwise grant for this exact leaf/op is only actually enforced
      // if the wildcard's own condition excludes that leaf too. Trusting
      // the dedicated block's classification unconditionally (the
      // original behavior here) can certify a wrong, too-permissive
      // declaration as safe: the wildcard's separate, unexcluded grant is
      // still live regardless of what the dedicated block says.
      if (
        isUserSubcollection
        && wildcard
        && wildcard.verbs[op]
        && isRestrictiveClassification(dedicatedCls)
        && wildcardWouldGrant(wildcard.verbs[op].classification)
        && !wildcard.wildcardExclusions[op].has(leafName)
      ) {
        throw new Error(
          `collectionAccess: dedicated block for "${leafName}" declares "${op}" as ${dedicatedCls} ` +
          `(${JSON.stringify(dedicated.verbs[op].raw)}), but the generic wildcard (${GENERIC_WILDCARD_PATH}) ` +
          `still grants "${op}" (${wildcard.verbs[op].classification}) for "${leafName}" because it is NOT ` +
          `excluded from the wildcard's own "${op}" condition -- Firestore ORs matching rules together, so ` +
          `the wildcard's grant is still live regardless of the dedicated block's own restriction. Add ` +
          `"coll != '${leafName}'" to the wildcard's "${op}" condition, or the dedicated block's restriction ` +
          'is not actually enforced.',
        );
      }
      result[op] = { classification: dedicatedCls, source: 'dedicated', raw: dedicated.verbs[op].raw };
      continue;
    }
    if (wildcard) {
      const excluded = wildcard.wildcardExclusions[op].has(leafName);
      if (!excluded && wildcard.verbs[op]) {
        result[op] = { classification: wildcard.verbs[op].classification, source: 'wildcard', raw: wildcard.verbs[op].raw };
        continue;
      }
    }
    result[op] = { classification: 'IMPLICIT_DENY', source: 'none', raw: null };
  }
  return result;
}

module.exports = {
  GENERIC_WILDCARD_PATH,
  ALL_VERBS,
  parseFirestoreRules,
  parseFirestoreRulesFile,
  collectionAccess,
  // Exported for the mutation-proof test / unit testing of the classifier
  // in isolation.
  classifyCondition,
  classifyWildcardCondition,
};
