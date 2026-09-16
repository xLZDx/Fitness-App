#!/usr/bin/env node
// P2-ACCESS-1 (Firestore Access-Control Drift Guard).
//
// firestore.rules' generic `match /users/{uid}/{coll}/{document=**}` block
// grants the owner read/write over ANY subcollection under their own
// `users/{uid}` except an explicit denylist -- several real subcollections
// (generated_exercises, equipment_setup_notes, programmes, machine_cards,
// recognised_equipment, scheduled_sessions, workout_logs, stats,
// workout_sessions, ...) ride this wildcard today with no dedicated rules
// block, and nothing failed CI when a NEW sensitive collection joined that
// list by omission -- the wildcard silently grants owner access to whatever
// a future subcollection turns out to be, with nobody having made that
// access decision on purpose.
//
// This is check_data_lifecycle_coverage.js's own proven "discover every
// collection, require an explicit classification, fail CI on a gap"
// mechanism, applied to a second, independent axis: ACCESS CONTROL rather
// than data RETENTION. Both axes share scripts/ci/data_lifecycle_policy.json
// (RETENTION's `classification`/`reason`, ACCESS's `clientAccess`) -- see
// that file's own `_comment` and scripts/ci/DATA_ACCESS_POLICY_DESIGN.md for
// the full design this implements.
//
// FOUR discovery sources, unioned, PLUS one fail-closed scanner:
//   A. firestore.rules -- every DEDICATED match block's FULL path (not just
//      the leaf name check_data_lifecycle_coverage.js's own discovery
//      needs) is a canonical declaration target on its own.
//   B. Literal `.collection('name')` calls in production source, across
//      PRODUCTION_SOURCE_ROOTS (functions/src, functions-equipment-
//      identity/src, mobile/lib) -- catches a wildcard-riding subcollection
//      with no dedicated rules block at all (e.g. `workout_logs`, written by
//      the mobile app as a literal `.collection('workout_logs')` call).
//   C. A registered path-registry list: `{file, exportName}` pairs naming an
//      `export const XPaths = { key: "literal", ... } as const` object.
//      Property-access reads like `P2CollectionPaths.textKeys` are invisible
//      to a literal-string scan -- Source C unions the object's own string
//      VALUES as discovered names, exactly like a literal call would be.
//      Resolution additionally requires the calling file to actually IMPORT
//      the identifier from the registered file (or BE the registered file)
//      -- see `registryBindingHolds()` (2026-09-16 remediation, item 4).
//   D. Direct `.doc(<path>)` / `.doc\`<path>\`` calls (member call off `db`/
//      `db()`, NOT chained directly off a `.collection(...)` call -- that
//      shape is a relative document-id argument within an ALREADY-
//      discovered collection, not a second declaration target). The
//      argument is parsed the same way a `doc(db, path)` call in a test
//      body already is (`docCallPathArgs`/`testDocPathCollectionSegments`):
//      a literal string or a template literal with `${...}` interpolations
//      wildcarded. A `.doc()` call whose collection segment itself cannot be
//      statically resolved (a bare variable, a function call, an
//      interpolation landing ON the collection-name segment) falls under
//      the SAME fail-closed treatment as an unresolved `.collection()` call
//      below -- there is one standard, not a looser one for `.doc()`
//      (2026-09-16 remediation, item 1 -- was the BLOCKER: `functions/src/
//      index.ts` alone has 15+ real `db.doc(\`...\`)` call sites invisible
//      to the old `.collection()`-only discovery).
//   FAIL-CLOSED SCANNER -- every `.collection(<arg>)` AND `.doc(<arg>)` call
//   across the same PRODUCTION_SOURCE_ROOTS whose argument cannot be
//   statically resolved to a literal collection name / Firestore path fails
//   CI outright, naming the file:line, the call kind, and the unresolved
//   expression -- UNLESS that exact `{file, line, arg}` triple is a
//   documented, audited entry in KNOWN_AUDITED_DYNAMIC_CALL_SITES below
//   (2026-09-16 remediation, item 2 -- was the BLOCKER: a whole EXPRESSION
//   CLASS, not just specific audited call sites, used to be exempted as
//   non-blocking "residue" -- see that array's own doc comment and
//   DATA_ACCESS_POLICY_DESIGN.md §9 for why each entry is legitimate).
'use strict';

const fs = require('fs');
const path = require('path');
const {
  parseFirestoreRulesFile,
  collectionAccess,
  ALL_VERBS,
  GENERIC_WILDCARD_PATH,
} = require('./lib/rules_parser.js');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const RULES_PATH = path.join(REPO_ROOT, 'firestore.rules');
const POLICY_PATH = path.join(REPO_ROOT, 'scripts/ci/data_lifecycle_policy.json');

const VALID_ACCESS_VALUES = new Set(['NONE', 'OWNER', 'AUTHENTICATED', 'PUBLIC', 'CONDITIONAL']);

/** Every codebase that writes to Firestore in production. Adding a new
 * Firestore-writing codebase to this repo means adding its source root
 * here -- this list is exactly what closed GPT-PM's round-2 finding (the
 * P2 identity codebase was previously unscanned, which is how
 * `P2CollectionPaths.textKeys` went unseen by the OLD lifecycle checker's
 * literal-only scan until this gate). */
const PRODUCTION_SOURCE_ROOTS = [
  { root: path.join(REPO_ROOT, 'functions/src'), exclude: ['__tests__', '__e2e__', '__rules__'], ext: '.ts' },
  { root: path.join(REPO_ROOT, 'functions-equipment-identity/src'), exclude: ['__tests__', '__e2e__'], ext: '.ts' },
  { root: path.join(REPO_ROOT, 'mobile/lib'), exclude: ['test'], ext: '.dart' },
];

/** Registered `{file, exportName}` path-registries -- Source C. Adding a
 * new `as const` collection-path registry means registering it here; an
 * unregistered property-access `.collection()` call is the exact gap the
 * fail-closed scanner below exists to catch. */
const PATH_REGISTRIES = [
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/firestore_paths.ts'),
    exportName: 'P2CollectionPaths',
  },
];

/**
 * `.collection(<arg>)` / `.doc(<arg>)` call sites carved out as explicit,
 * AUDITED exceptions to the fail-closed non-literal-call scanner -- see
 * DATA_ACCESS_POLICY_DESIGN.md's "Known, documented scope limits" section.
 * Each entry pins an EXACT {file, line, arg} triple, not a loose name-only
 * match, so a NEW non-literal call elsewhere (the actual gap this check
 * exists to catch) is never silently covered by an entry meant for a
 * different call site.
 *
 * 2026-09-16 remediation, item 2 (was BLOCKER): this array replaces the
 * narrower `KNOWN_SAFE_BARE_IDENTIFIER_CALLS` -- it used to be the only
 * escape hatch for a BARE IDENTIFIER call; every other non-literal shape
 * (an interpolated template, a function-call argument, string
 * concatenation) was silently exempted as a whole EXPRESSION CLASS
 * ("dynamic-path residue"), never audited call-site by call-site. That
 * generalization was the actual gap: a genuinely new helper with no
 * separately-discoverable literal call site slipped through entirely,
 * silent, exit 0. Every entry below is now individually verified (not
 * carried forward on faith) against the real repository as of 2026-09-16 --
 * each reason states exactly where the real collection name is otherwise
 * discoverable/declared.
 */
const KNOWN_AUDITED_DYNAMIC_CALL_SITES = [
  {
    file: path.join(REPO_ROOT, 'functions/src/account_export.ts'),
    line: 64,
    arg: '`users/${uid}/${name}`',
    reason: "sub()'s own collection-name PARAMETER (a template literal interpolating a generic helper " +
      'parameter, not a fixed collection name at this call site). Every real call site ' +
      '(sub(uid, "workout_logs", truncated), "workout_sessions", "scheduled_sessions", "programmes", ' +
      '"machine_cards", "recognised_equipment", "generated_exercises", "equipment_setup_notes", ' +
      '"receipts") passes a literal string; every one of those names is independently discovered by ' +
      "Source B via mobile/lib's own literal `.collection('<name>')` calls (or, for \"receipts\", " +
      'Source A -- firestore.rules:109) -- verified 2026-09-16, not carried forward on faith. See ' +
      'DATA_ACCESS_POLICY_DESIGN.md §9.',
  },
  {
    file: path.join(REPO_ROOT, 'functions/src/account_export.ts'),
    line: 100,
    arg: 'collection',
    reason: "owned()'s own collection-name PARAMETER -- every real call site passing it a literal " +
      '(coach_bookings, equipment_reports, debug_sessions, ...) is itself discovered by Source B ' +
      "independently, at that different call site, in this same file. See DATA_ACCESS_POLICY_DESIGN.md §9.",
  },
  {
    file: path.join(REPO_ROOT, 'functions/src/account_export.ts'),
    line: 88,
    arg: 'path',
    reason: "one()'s own Firestore-path PARAMETER -- every real call site passes a literal template " +
      '(`users/${uid}/profile/main`, `users/${uid}/subscription/main`, `users/${uid}/stats/workouts`, ' +
      '`donor_wall/${uid}`, `coach_listings/${uid}`). Each target collection is independently ' +
      'discoverable/declared elsewhere: profile -- dedicated rules block (firestore.rules:181); ' +
      "subscription -- Source D at this file's own other .doc() call sites (functions/src/index.ts); " +
      "stats -- Source B (mobile/lib's own literal .collection('stats') calls); donor_wall, " +
      'coach_listings -- dedicated rules blocks (firestore.rules:236,324). Verified 2026-09-16.',
  },
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/catalog_reader.ts'),
    line: 35,
    arg: 'CATALOG_ACTIVE_POINTER_DOC_PATH',
    reason: 'a fixed module-level constant (`${CollectionPaths.catalogActive}/current`, ' +
      'functions-equipment-identity/src/p1/firestore_paths.ts:131) -- always resolves to the single ' +
      'collection "equipment_catalog_active", which is a dedicated, already-declared rules block ' +
      '(firestore.rules:405). Never a dynamically-chosen path. Verified 2026-09-16.',
  },
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/catalog_reader.ts'),
    line: 53,
    arg: 'path',
    reason: "fetchEquipmentModel()'s own local variable, assigned one line above from " +
      'modelDocPath(catalogVersion, modelId) = `${CollectionPaths.models}/...` -- always resolves to ' +
      '"equipment_models", a dedicated, already-declared rules block (firestore.rules -- see ' +
      '`match /equipment_models/{docId}`). Never a dynamically-chosen collection. Verified 2026-09-16.',
  },
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/session_repository.ts'),
    line: 209,
    arg: 'userEquipmentIdentitySessionDocPath(uid, sessionId)',
    reason: 'always resolves to "equipment_identity_sessions" (functions-equipment-identity/src/p1/' +
      'firestore_paths.ts:139-144, `users/${uid}/equipment_identity_sessions/${sessionId}`), a ' +
      'dedicated, already-declared rules block (firestore.rules -- see `match /users/{uid}/' +
      'equipment_identity_sessions/{sessionId}`). Never a dynamically-chosen collection. Verified ' +
      '2026-09-16.',
  },
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/session_repository.ts'),
    line: 210,
    arg: 'userEquipmentIdentityLatestSessionDocPath(uid)',
    reason: 'always resolves to "equipment_identity_latest_session" (functions-equipment-identity/src/' +
      'p2/firestore_paths.ts:63-66, `users/${uid}/equipment_identity_latest_session/current`), a ' +
      'dedicated, already-declared rules block. Never a dynamically-chosen collection. Verified ' +
      '2026-09-16.',
  },
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/session_repository.ts'),
    line: 315,
    arg: 'userEquipmentIdentitySessionDocPath(uid, sessionId)',
    reason: 'same target/justification as line 209 above. Verified 2026-09-16.',
  },
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/session_repository.ts'),
    line: 316,
    arg: 'userEquipmentIdentityLatestSessionDocPath(uid)',
    reason: 'same target/justification as line 210 above. Verified 2026-09-16.',
  },
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/session_repository.ts'),
    line: 364,
    arg: 'userEquipmentIdentitySessionDocPath(uid, sessionId)',
    reason: 'same target/justification as line 209 above. Verified 2026-09-16.',
  },
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/session_repository.ts'),
    line: 380,
    arg: 'userEquipmentIdentityLatestSessionDocPath(uid)',
    reason: 'same target/justification as line 210 above. Verified 2026-09-16.',
  },
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/telemetry_repository.ts'),
    line: 133,
    arg: 'userEquipmentIdentityTelemetryDocPath(uid, scanId)',
    reason: 'always resolves to "equipment_identity_telemetry" (functions-equipment-identity/src/p1/' +
      'firestore_paths.ts:147-..., `users/${uid}/equipment_identity_telemetry/${docId}`), a dedicated, ' +
      'already-declared rules block. Never a dynamically-chosen collection. Verified 2026-09-16.',
  },
  {
    file: path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/telemetry_repository.ts'),
    line: 323,
    arg: 'userEquipmentIdentityTelemetryDocPath(uid, scanId)',
    reason: 'same target/justification as line 133 above. Verified 2026-09-16.',
  },
];

// ---------------------------------------------------------------------------
// File discovery (mirrors check_data_lifecycle_coverage.js's own walk() --
// same directory-exclusion semantics: match any PATH SEGMENT, not just a
// top-level directory, so a nested `p2/__tests__` is excluded exactly like
// a top-level one).
// ---------------------------------------------------------------------------
function walk(dir, exclude, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (exclude.some((seg) => full.split(path.sep).includes(seg))) continue;
    if (entry.isDirectory()) {
      walk(full, exclude, out);
    } else {
      out.push(full);
    }
  }
  return out;
}

function productionFiles() {
  const files = [];
  for (const { root, exclude, ext } of PRODUCTION_SOURCE_ROOTS) {
    for (const f of walk(root, exclude)) if (f.endsWith(ext)) files.push(f);
  }
  return files;
}

// ---------------------------------------------------------------------------
// Source C: path-registry parsing.
// ---------------------------------------------------------------------------
function parseRegistry(registryPath, exportName) {
  if (!fs.existsSync(registryPath)) {
    throw new Error(`registered path-registry file does not exist: ${registryPath}`);
  }
  const text = fs.readFileSync(registryPath, 'utf8');
  const headerRe = new RegExp(`export\\s+const\\s+${exportName}\\s*=\\s*\\{`);
  const m = headerRe.exec(text);
  if (!m) {
    throw new Error(`registered export ${exportName} not found in ${registryPath} (expected 'export const ${exportName} = { ... }')`);
  }
  let depth = 1;
  let i = m.index + m[0].length;
  for (; i < text.length && depth > 0; i++) {
    if (text[i] === '{') depth++;
    else if (text[i] === '}') depth--;
  }
  const body = text.slice(m.index + m[0].length, i - 1);
  const values = new Map(); // key -> string value
  const kvRe = /(\w+)\s*:\s*["']([^"']+)["']/g;
  let kv;
  while ((kv = kvRe.exec(body)) !== null) values.set(kv[1], kv[2]);
  return { file: registryPath, exportName, values };
}

function loadRegistries() {
  return PATH_REGISTRIES.map(({ file, exportName }) => parseRegistry(file, exportName));
}

/**
 * (2026-09-16 remediation round 3+4, MAJOR) Whether `identName` is declared
 * ANYWHERE in `text` other than an import statement -- as a function/arrow
 * PARAMETER, a `const`/`let`/`var` (re-)declaration, or (round 4) an
 * object/array DESTRUCTURING binding naming the identifier -- which would
 * shadow a genuine file-level import at whatever call site sits inside that
 * scope. Deliberately conservative and file-WIDE rather than a real scope
 * resolver (no AST, no actual lexical-scope tracking, matching this
 * checker's own "regex/lightweight text parsing is fine" scope, per GPT-PM's
 * own stated acceptable options -- pick the simpler, safe one): ANY other
 * declaration of the exact identifier name anywhere in the file is treated
 * as a POTENTIAL shadow, even where a real parser would prove it is not
 * actually in scope at the specific `.collection(Ident.member)` call site.
 * This can over-flag a file that happens to reuse the name in a totally
 * unrelated, non-shadowing way -- an acceptable, safe direction for a CI
 * gate: a false failure costs a rename, a false pass is the actual security
 * gap this whole checker exists to catch.
 *
 * Round 4's own gap (GPT-PM's ruling on the round-3 MAJOR, round 4's own
 * remediation): `const { P2CollectionPaths } = runtimePaths;` (object
 * destructuring) doesn't match the plain `const|let|var IDENT` declaration
 * regex, AND the actual `.collection(P2CollectionPaths.textKeys)` use site
 * is deliberately excluded from the bare-identifier parameter detector
 * (since it's followed by `.`, correctly treated elsewhere as legitimate
 * member-access, never a redeclaration) -- so a destructured local shadow
 * was invisible to both halves of the detector simultaneously. GPT-PM's own
 * specified fix, explicitly NOT a full lexical scope-resolution engine,
 * staying consistent with the existing fail-closed philosophy: extend the
 * declaration-matching regexes to also recognize object destructuring
 * (`const|let|var\s*\{[^}]*\bIDENT\b[^}]*\}\s*=`, matching the identifier
 * anywhere among the destructured names) and array destructuring
 * (`const|let|var\s*\[[^\]]*\bIDENT\b[^\]]*\]\s*=`) as additional
 * shadow-declaration shapes, alongside the existing plain-declaration and
 * function/arrow-parameter checks below.
 *
 * `const/let/var IDENT` is a plain whole-file regex; the two destructuring
 * regexes are the same idea applied to `{...}`/`[...]` binding patterns.
 * The parameter check balanced-paren-scans every `(...)` span in the file
 * and tests whether IDENT appears inside it as a BARE token -- not
 * immediately preceded or followed by `.` (which would make it a
 * property-access base/member, e.g. `Foo.IDENT` or `IDENT.member`, never a
 * parameter) -- so a genuine `Ident.member` call argument like
 * `P2CollectionPaths.textKeys` is never mistaken for a parameter
 * declaration of that same name, while `function handler(P2CollectionPaths)
 * {...}` (and, for the same reason, an ordinary call passing the bare
 * identifier as an argument) is flagged.
 */
function hasLocalShadowDeclaration(text, identName) {
  const esc = identName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  if (new RegExp(`\\b(?:const|let|var)\\s+${esc}\\b`).test(text)) return true;
  if (new RegExp(`\\b(?:const|let|var)\\s*\\{[^}]*\\b${esc}\\b[^}]*\\}\\s*=`).test(text)) return true;
  if (new RegExp(`\\b(?:const|let|var)\\s*\\[[^\\]]*\\b${esc}\\b[^\\]]*\\]\\s*=`).test(text)) return true;
  const bareRe = new RegExp(`(^|[^.\\w$])${esc}(?![.\\w$])`);
  let i = 0;
  while (i < text.length) {
    const open = text.indexOf('(', i);
    if (open === -1) break;
    let depth = 1;
    let j = open + 1;
    for (; j < text.length && depth > 0; j++) {
      if (text[j] === '(') depth++;
      else if (text[j] === ')') depth--;
    }
    const inner = text.slice(open + 1, j - 1);
    if (bareRe.test(inner)) return true;
    i = open + 1;
  }
  return false;
}

/**
 * (2026-09-16 remediation, item 4 -- was MAJOR; narrowed further round 3 --
 * was MAJOR again) Whether `file` (whose full text is `text`) is actually
 * BOUND to `registry.exportName` -- either the file IS the registry's own
 * declaration file, or it imports that exact name from a RELATIVE path that
 * resolves to the registry file, AND (round 3) that import is not itself
 * shadowed anywhere else in the file. Matching by identifier SPELLING alone
 * (the item-4 pre-remediation behavior) would resolve a locally-shadowed
 * `const P2CollectionPaths = {...}` with different values in an unrelated
 * file to the registered (wrong) value.
 *
 * Round 3's own gap: item 4's fix checked only whether the WHOLE FILE
 * contains a matching import -- it had no idea whether a CLOSER local
 * declaration (a function parameter, an inner-scope `const`/`let`
 * re-declaration of the same identifier name) shadows that import at the
 * actual `.collection(Ident.member)` call site. A file that legitimately
 * imports `P2CollectionPaths` at the top AND ALSO has, say,
 * `function handler(P2CollectionPaths) { ... .collection(P2CollectionPaths
 * .textKeys) ... }` would still silently resolve via the file-level import,
 * even though the real value in scope at that call site is whatever the
 * caller passed as the parameter, not the registered one.
 *
 * Deliberately lightweight (no module resolver, no tsconfig paths/aliases):
 * only a plain relative `import { Name } from './relative/path'` (or
 * `'../relative/path'`) is recognized, matching this gate's own "regex or
 * lightweight text parsing is fine" scope. A non-relative import (a path
 * alias, a package import) cannot be resolved this way and does not bind --
 * fails closed, same philosophy as every other unresolved shape here.
 */
function registryBindingHolds(file, text, registry) {
  if (file === registry.file) return true; // same-file definition
  const importRe = /import\s+(?:type\s+)?\{([^}]*)\}\s*from\s*["']([^"']+)["']/g;
  let m;
  while ((m = importRe.exec(text)) !== null) {
    const names = m[1]
      .split(',')
      .map((s) => s.trim().split(/\s+as\s+/)[0].trim())
      .filter(Boolean);
    if (!names.includes(registry.exportName)) continue;
    const importSpec = m[2];
    if (!importSpec.startsWith('.')) continue; // not a relative import -- cannot resolve to a local file
    const resolved = path.resolve(path.dirname(file), importSpec).replace(/\\/g, '/').replace(/\.ts$/, '');
    const registryNoExt = registry.file.replace(/\\/g, '/').replace(/\.ts$/, '');
    if (resolved === registryNoExt) {
      // Bound via a genuine relative import -- but conservatively refuse to
      // trust it if the same identifier name is ALSO declared anywhere else
      // in this file (function parameter, const/let/var), since a closer
      // declaration could shadow the import at the real call site and this
      // lightweight checker has no way to resolve actual lexical scope.
      if (hasLocalShadowDeclaration(text, registry.exportName)) return false;
      return true;
    }
  }
  return false;
}

// ---------------------------------------------------------------------------
// Sources B + D + the fail-closed scanner, together: one pass over every
// `.collection(<arg>)` and `.doc(<arg>)` call site in a file.
// ---------------------------------------------------------------------------
const STRING_LITERAL_RE = /^(['"])([a-zA-Z_][a-zA-Z0-9_]*)\1$/;
const TEMPLATE_NO_INTERP_RE = /^`([^`$]*)`$/;
// A property-access expression on a plain identifier -- `Ident.member`,
// nothing else on either side (no computed access, no call, no chain).
const MEMBER_EXPR_RE = /^([A-Za-z_$][\w$]*)\.([A-Za-z_$][\w$]*)$/;
// A single bare identifier -- a local variable or function parameter,
// nothing else (no dot, no call, no computed access, no concatenation).
const BARE_IDENTIFIER_RE = /^[A-Za-z_$][\w$]*$/;

/** Every `.{methodName}(...)` member-call site in `text` -- balanced-paren
 * argument extraction, 1-based line numbers, plus `prefixStart` (the index
 * of the `.` immediately before `methodName`, used to test whether one call
 * is chained directly off another) and `callEnd` (the index just past the
 * call's closing paren). Used for both `.collection(` and `.doc(`. */
function memberCallSites(text, methodName) {
  const sites = [];
  const re = new RegExp(`\\.${methodName}\\(`, 'g');
  let m;
  while ((m = re.exec(text)) !== null) {
    const prefixStart = m.index;
    const argStart = m.index + m[0].length;
    let depth = 1;
    let i = argStart;
    for (; i < text.length && depth > 0; i++) {
      if (text[i] === '(') depth++;
      else if (text[i] === ')') depth--;
    }
    const arg = text.slice(argStart, i - 1).trim();
    const line = text.slice(0, m.index).split('\n').length;
    sites.push({ arg, line, prefixStart, callEnd: i });
  }
  return sites;
}

/** Whether `text[fromEnd..toPrefixStart)` is empty or whitespace-only --
 * i.e. whether a call ending at `fromEnd` is chained DIRECTLY into another
 * call starting at `toPrefixStart`, with nothing but whitespace/newlines
 * between (2026-09-16 remediation, item 5 -- was MAJOR: replaces a
 * `/\.doc\([^()]*\)\s*$/`-shaped regex that could not match past a NESTED
 * paren in the `.doc()` argument, e.g. `doc(getUid())` -- this balanced-
 * paren-position check has no such blind spot, since `memberCallSites()`
 * already resolved each call's true start/end via depth counting). */
function isAdjacentCall(text, fromEnd, toPrefixStart) {
  // `toPrefixStart` must come AT OR AFTER `fromEnd` -- `String.prototype
  // .slice(start, end)` silently returns '' when `start > end` (rather than
  // reversing or throwing), which would otherwise make this function
  // falsely report "adjacent" for a call whose end lands AFTER the target
  // call's start (i.e. two calls in the wrong order, or an unrelated later
  // call anywhere else in the file) -- found live while sanity-checking
  // this against the real repo: it spuriously marked
  // `db().collection(P2CollectionPaths.textKeys)` as chained off a
  // `.doc(id)` call that actually comes AFTER it on the same line.
  if (toPrefixStart < fromEnd) return false;
  return /^\s*$/.test(text.slice(fromEnd, toPrefixStart));
}

/** Parse a `.doc()`/`doc()` raw path-argument text (still quoted) into its
 * collection-only segment array (the trailing document-id segment
 * dropped), or `null` if the argument is not a statically-interpretable
 * string/template literal (e.g. a bare variable or a function call --
 * genuinely dynamic path arguments are outside what this lightweight
 * text-parsing gate can verify). A template literal's `${...}`
 * interpolations are wildcarded to `*`, not evaluated -- exactly like a
 * path variable (`{uid}`) is on the declared-policy side. Shared, byte-for-
 * byte, between the CONDITIONAL-ref test-body path verifier below and
 * Source D's production-code `.doc()` discovery (2026-09-16 remediation,
 * item 1's own instruction: derive the path "the same way
 * docCallPathArgs/testDocPathCollectionSegments already do for test
 * bodies" -- one implementation, not two). */
function testDocPathCollectionSegments(rawArgText) {
  const trimmed = rawArgText.trim();
  let raw;
  if (/^`[\s\S]*`$/.test(trimmed)) {
    raw = trimmed.slice(1, -1).replace(/\$\{[^}]*\}/g, '*');
  } else if (/^"[^"]*"$/.test(trimmed) || /^'[^']*'$/.test(trimmed)) {
    raw = trimmed.slice(1, -1);
  } else {
    return null;
  }
  const segs = raw.split('/').filter(Boolean);
  segs.pop(); // trailing document-id segment
  return segs.length > 0 ? segs : null;
}

/** Derive `{leaf, isUserSubcollection}` from a `.doc()` call's own
 * collection-only segments (as returned by `testDocPathCollectionSegments`,
 * interpolations already wildcarded to `*`) -- `null` if the LEAF segment
 * itself is dynamic (`*`), which is exactly as unresolvable as a dynamic
 * `.collection()` argument and must fail closed the same way, not be
 * guessed at. Mirrors `leafFromPath()`'s own users/{uid}/... vs top-level
 * shape logic, applied to a code-derived segment array instead of a
 * declared policy path string.
 *
 * 2026-09-16 remediation, round 3, BLOCKER 1: the per-user-subcollection
 * branch below used to additionally require `segs[1] === '*'` -- i.e. it
 * only recognized the shape when the uid segment came from a template
 * interpolation (`${uid}` -> wildcarded to `*`). A STATICALLY LITERAL path
 * like `db().doc("users/alice/sensitive_new/current")` has `segs[1] ===
 * 'alice'` (a real uid value, not a wildcard) and fell through to the
 * generic branch, which returned `{leaf: 'users', isUserSubcollection:
 * false}` -- silently discarded by `addCandidate()`'s own `leaf === 'users'`
 * guard below, with neither a candidate nor a violation ever produced.
 * Whether a path is a per-user subcollection is a STRUCTURAL fact (segment
 * count and `segs[0] === 'users'`), never a function of whether the uid
 * VALUE happens to be a literal or a wildcarded interpolation -- a genuine
 * literal uid ("alice") and `${uid}` are equally "some user's id" for
 * classification purposes. The `segs[1] === '*'` gate is removed; ANY path
 * with `segs.length >= 3 && segs[0] === 'users'` is now treated as a
 * per-user subcollection regardless of what `segs[1]` actually is. */
function collectionShapeFromDocSegments(segs) {
  if (segs.length >= 3 && segs[0] === 'users') {
    if (segs[2] === '*') return null;
    return { leaf: segs[2], isUserSubcollection: true };
  }
  if (segs.length >= 1) {
    if (segs[0] === '*') return null;
    return { leaf: segs[0], isUserSubcollection: false };
  }
  return null;
}

function classifyViolationKind(arg) {
  if (BARE_IDENTIFIER_RE.test(arg)) return 'bare';
  if (MEMBER_EXPR_RE.test(arg)) return 'member';
  return 'dynamic';
}

/** Whether text immediately before a `.doc(` call (i.e. `text.slice(0,
 * prefixStart)`) ends in the Firestore-ROOT expression `db` / `db()` /
 * `_db` (every real spelling this repo's own production code uses for a
 * Firestore instance -- verified 2026-09-16, not assumed) with nothing but
 * optional whitespace after it.
 *
 * This is Source D's actual scope boundary, and it is a POSITIVE
 * allowlist rather than a negative "not chained off .collection()" check
 * (an earlier draft of this function): a `.doc(<arg>)` call chained off
 * ANY OTHER expression -- a `.collection(...)` call, a stored
 * `CollectionReference` variable, or (this codebase's own dominant
 * mobile/lib idiom) a private helper method returning one, e.g.
 * `_col(uid).doc(entryId)` where `_col(uid) => _db.collection('users')
 * .doc(uid).collection('workout_logs')` -- is a RELATIVE document-id
 * argument within an ALREADY-discovered collection (the `.collection()`
 * call inside the helper), not a second declaration target. A same-
 * statement textual-adjacency check (an earlier draft) only recognizes the
 * FIRST of those shapes; the helper-method shape is this repo's own most
 * common one (every mobile/lib repository class), and treating it as a new
 * path would have flooded CI with false failures for ordinary relative
 * `.doc(<localId>)` calls -- confirmed live against the real repo (16 false
 * violations across 8 mobile/lib files before this fix). Restricting to a
 * literal Firestore-root prefix instead sidesteps the whole "what is this
 * chained off" question: every real full-PATH `.doc()` call site in this
 * codebase (functions/src, functions-equipment-identity/src) is called
 * directly on the root, and no relative doc-id call anywhere is (verified
 * by grep: zero `_db.doc(`/`_db().doc(` root-level call in mobile/lib). */
const DB_ROOT_DOC_CALL_RE = /(?:^|[^\w$])_?db(\(\))?\s*$/;
function isDbRootDocCall(text, prefixStart) {
  return DB_ROOT_DOC_CALL_RE.test(text.slice(0, prefixStart));
}

/**
 * Runs Sources B + D (literal names / paths) and the fail-closed scanner
 * over every `.collection(<arg>)` and `.doc(<arg>)` call site across
 * `files`. Returns:
 *   literalNames: Set<string>                -- Source B's own discovery
 *   literalHits:  [{name,file,line,chainedOffDoc}] -- one per literal
 *                 `.collection()` call site, kept (not just unioned into
 *                 literalNames) so discoverCandidates() can read the
 *                 per-site chain shape.
 *   registryHits: [{ident,member,value,file,line,chainedOffDoc}] --
 *                 resolved via a registered, import-bound registry.
 *   docHits:      [{leaf,isUserSubcollection,file,line}] -- Source D: one
 *                 per resolvable root-level `.doc(<literal-or-template>)`
 *                 call site (never chained directly off `.collection()`,
 *                 which is a relative document-id argument, not a new
 *                 declaration target). Already carries its own resolved
 *                 shape -- no chain-shape ambiguity is possible for a
 *                 `.doc()` call the way it is for a bare `.collection()`
 *                 name, since the full path is right there in the literal.
 *   violations:   [{file,line,expr,kind,callKind}] -- unresolved
 *                 `.collection()`/`.doc()` calls (`kind`: 'bare' | 'member'
 *                 | 'dynamic', `callKind`: 'collection' | 'doc').
 *   residue:      [{file,line,expr,callKind}] -- every non-literal call
 *                 site that IS covered by an exact, audited
 *                 KNOWN_AUDITED_DYNAMIC_CALL_SITES entry.
 */
function scanProductionCalls(files, registries, knownAudited = KNOWN_AUDITED_DYNAMIC_CALL_SITES) {
  const registryByIdent = new Map(registries.map((r) => [r.exportName, r]));
  const literalNames = new Set();
  const literalHits = [];
  const registryHits = [];
  const docHits = [];
  const violations = [];
  const residue = [];

  const isAllowed = (file, line, arg) =>
    knownAudited.some((k) => k.file === file && k.line === line && k.arg === arg);

  function pushUnresolved(callKind, arg, file, line) {
    if (isAllowed(file, line, arg)) {
      residue.push({ file, line, expr: arg, callKind });
      return;
    }
    violations.push({ file, line, expr: arg, kind: classifyViolationKind(arg), callKind });
  }

  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    const collectionSites = memberCallSites(text, 'collection');
    const docSites = memberCallSites(text, 'doc');

    for (const site of collectionSites) {
      const { arg, line, prefixStart } = site;
      const chainedOffDoc = docSites.some((d) => isAdjacentCall(text, d.callEnd, prefixStart));

      const lit = STRING_LITERAL_RE.exec(arg) || TEMPLATE_NO_INTERP_RE.exec(arg);
      if (lit) {
        const name = lit[2] !== undefined ? lit[2] : lit[1];
        literalNames.add(name);
        literalHits.push({ name, file, line, chainedOffDoc });
        continue;
      }
      const mem = MEMBER_EXPR_RE.exec(arg);
      if (mem) {
        const [, ident, member] = mem;
        const registry = registryByIdent.get(ident);
        const bound = !!registry && registryBindingHolds(file, text, registry);
        if (registry && bound && registry.values.has(member)) {
          registryHits.push({ ident, member, value: registry.values.get(member), file, line, chainedOffDoc });
          continue;
        }
        pushUnresolved('collection', arg, file, line);
        continue;
      }
      pushUnresolved('collection', arg, file, line);
    }

    // Source D: root-level `.doc(<path>)` calls only -- see
    // isDbRootDocCall()'s own doc comment for why this is a positive
    // "called directly on db/_db" check rather than a negative "not
    // chained off .collection()" one.
    for (const site of docSites) {
      const { arg, line, prefixStart } = site;
      if (!isDbRootDocCall(text, prefixStart)) continue;

      const segs = testDocPathCollectionSegments(arg);
      const shape = segs ? collectionShapeFromDocSegments(segs) : null;
      if (shape) {
        docHits.push({ leaf: shape.leaf, isUserSubcollection: shape.isUserSubcollection, file, line });
        continue;
      }
      pushUnresolved('doc', arg, file, line);
    }
  }
  return { literalNames, literalHits, registryHits, docHits, violations, residue };
}

// ---------------------------------------------------------------------------
// Discovery union -> canonical path candidates.
// ---------------------------------------------------------------------------
function relPath(p) {
  return path.relative(REPO_ROOT, p).split(path.sep).join('/');
}

function derivePathVars(leaf, isUserSubcollection) {
  return isUserSubcollection ? `/users/{uid}/${leaf}/{docId}` : `/${leaf}/{docId}`;
}

/**
 * Disambiguate whether a code-discovered collection NAME (one with no
 * dedicated rules block -- Source A already resolves those unambiguously)
 * is a per-user subcollection or a top-level collection, from the call-site
 * SHAPE evidence `scanProductionCalls()` recorded per hit: `chainedOffDoc`
 * -- was the `.collection(<name>)` call chained directly off a `.doc(...)`
 * reference (`_db.collection('users').doc(uid).collection('workout_logs')`,
 * this codebase's own real, verified pattern for every current per-user
 * subcollection reached only via code -- see mobile/lib's repository
 * classes) or not (`_db.collection('debug_sessions')`,
 * `db.collection('coach_bookings')`, this codebase's own real pattern for
 * every current top-level collection, verified the same way).
 *
 * A name reached through BOTH shapes across different call sites (real
 * evidence conflicts) cannot be mechanically resolved -- returned as
 * `ambiguous` rather than guessed at either way, fail-closed same as the
 * bare-identifier/property-access violations above. (Source D `.doc()`
 * hits need no equivalent ambiguity handling -- each one already carries
 * its own unambiguous, literally-derived shape.)
 */
function classifyCodeDiscoveredShape(literalHits, registryHits) {
  const evidence = new Map(); // name -> {sawSub, sawTop, examples: [{file,line}]}
  const record = (name, file, line, chainedOffDoc) => {
    if (!evidence.has(name)) evidence.set(name, { sawSub: false, sawTop: false, examples: [] });
    const e = evidence.get(name);
    if (chainedOffDoc) e.sawSub = true; else e.sawTop = true;
    e.examples.push({ file, line, chainedOffDoc });
  };
  for (const h of literalHits) record(h.name, h.file, h.line, h.chainedOffDoc);
  for (const h of registryHits) record(h.value, h.file, h.line, h.chainedOffDoc);
  return evidence;
}

/** Whether ANY dedicated (non-wildcard) block already governs this exact
 * `{leaf, isUserSubcollection}` combination -- a plain existence check over
 * the block list, never a lossy leaf-keyed Map (2026-09-16 remediation,
 * item 6 -- was MAJOR: the original `dedicatedByLeaf` Map silently
 * OVERWROTE one of two dedicated blocks sharing a leaf/root segment,
 * dropping it from the candidate set entirely -- a real coverage hole, not
 * merely a display collapse). Used only to decide whether a CODE-
 * discovered name needs its OWN candidate entry; the candidate set itself
 * is always seeded from every dedicated block's full, unique `matchPath`
 * (see `discoverCandidates()`), so no dedicated block is ever silently
 * dropped regardless of how many share a leaf. */
function hasDedicatedBlock(dedicated, leaf, isUserSubcollection) {
  return dedicated.some((b) => {
    const bIsUserSub = b.segments[0] === 'users';
    const bLeaf = bIsUserSub ? b.segments[2] : b.segments[0];
    return bIsUserSub === isUserSubcollection && bLeaf === leaf;
  });
}

function discoverCandidates(blocks, files, registries) {
  const dedicated = blocks.filter((b) => !b.isGenericWildcard && b.matchPath !== '/databases/{database}/documents');

  // Seed the candidate set directly from EVERY dedicated block's own full,
  // unique matchPath -- see hasDedicatedBlock()'s own doc comment for why
  // this replaces the old leaf-keyed Map.
  const candidates = new Map(); // canonicalPath -> {leaf, isUserSubcollection, sources: Set}
  for (const b of dedicated) {
    const isUserSub = b.segments[0] === 'users';
    const leaf = isUserSub ? b.segments[2] : b.segments[0];
    candidates.set(b.matchPath, { leaf, isUserSubcollection: isUserSub, sources: new Set(['rules']) });
  }

  const { literalNames, literalHits, registryHits, docHits, violations, residue } = scanProductionCalls(files, registries);

  function addCandidate(leaf, isUserSub, sourceTag) {
    // Still needed after the round-3 BLOCKER-1 fix above, for a narrower
    // real case: a bare 2-segment `.doc('users/<id>')` call (no third
    // segment at all) still derives `{leaf: 'users', isUserSubcollection:
    // false}` via collectionShapeFromDocSegments()'s generic branch (its
    // `segs.length >= 3` per-user branch never applies to a 1-segment
    // collection-only array) -- that is a reference to the `users` root
    // container itself, not a real collection, and must still be dropped.
    if (leaf === 'users') return; // the root container, not a collection of its own.
    if (hasDedicatedBlock(dedicated, leaf, isUserSub)) return; // already required via Source A at its own exact path.
    const canonicalPath = derivePathVars(leaf, isUserSub);
    if (!candidates.has(canonicalPath)) {
      candidates.set(canonicalPath, { leaf, isUserSubcollection: isUserSub, sources: new Set([sourceTag]) });
    } else {
      candidates.get(canonicalPath).sources.add(sourceTag);
    }
  }

  // Sources B + C (.collection() literal names/registry values), shape
  // disambiguated per name from call-site evidence.
  const codeNames = new Set([...literalNames]);
  for (const hit of registryHits) codeNames.add(hit.value);

  const shapeEvidence = classifyCodeDiscoveredShape(literalHits, registryHits);
  const ambiguous = [];
  for (const name of codeNames) {
    if (name === 'users') continue;
    const evidence = shapeEvidence.get(name) || { sawSub: false, sawTop: false, examples: [] };
    if (evidence.sawSub && evidence.sawTop) {
      ambiguous.push({ name, examples: evidence.examples });
      continue;
    }
    const isUserSub = evidence.sawTop ? false : true; // default: per-user subcollection (original assumption, now evidence-gated).
    addCandidate(name, isUserSub, 'code');
  }

  // Source D (.doc() literal/template full paths) -- each hit already
  // carries its own unambiguous, literally-derived shape.
  for (const hit of docHits) {
    addCandidate(hit.leaf, hit.isUserSubcollection, 'code');
  }

  return { candidates, violations, residue, ambiguous };
}

// ---------------------------------------------------------------------------
// Policy loading + schema/semantic validation.
// ---------------------------------------------------------------------------
function loadPolicy() {
  return JSON.parse(fs.readFileSync(POLICY_PATH, 'utf8'));
}

/** Derive {leaf, isUserSubcollection} from a declared `clientAccess[].path`
 * string, so validation re-derives the expected rules classification from
 * firestore.rules itself rather than trusting the JSON's own shape. */
function leafFromPath(declaredPath) {
  const segs = declaredPath.split('/').filter(Boolean);
  if (segs[0] === 'users' && segs[1] && segs[1].startsWith('{')) {
    return { leaf: segs[2], isUserSubcollection: true };
  }
  return { leaf: segs[0], isUserSubcollection: false };
}

/** Extract the body text of a named `test("<name>", ...)` /
 * `test('<name>', ...)` block (async or not) via balanced-paren scan --
 * mirrors the same brace/paren-counting discipline used elsewhere in this
 * module rather than a non-greedy regex that could run past a nested call. */
function findTestBody(testFileText, testName) {
  const escaped = testName.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const headerRe = new RegExp(`test\\(\\s*["'\`]${escaped}["'\`]\\s*,`);
  const m = headerRe.exec(testFileText);
  if (!m) return null;
  // Find the opening `(` of the whole `test(...)` call (the one just before
  // the matched header) and balance-scan to ITS matching close.
  const callOpenIdx = testFileText.indexOf('(', m.index);
  let depth = 1;
  let i = callOpenIdx + 1;
  for (; i < testFileText.length && depth > 0; i++) {
    if (testFileText[i] === '(') depth++;
    else if (testFileText[i] === ')') depth--;
  }
  return testFileText.slice(callOpenIdx + 1, i - 1);
}

/** Strip `//` line comments and `/* *\/` block comments from `text` without
 * touching string/template-literal contents (2026-09-16 remediation, item
 * 3 -- was BLOCKER: an unrelated `doc()` reference sitting inside a COMMENT
 * must never be read as evidence by the CONDITIONAL-ref path verifier
 * below). Comment bodies are replaced with matching-length whitespace/
 * newlines rather than deleted outright, so every surviving character's
 * OFFSET into the string is unchanged -- callers that still need line
 * numbers or original positions keep working against the same indices. */
function stripComments(text) {
  let out = '';
  let inStr = null;
  let i = 0;
  while (i < text.length) {
    const c = text[i];
    if (inStr) {
      out += c;
      if (c === '\\' && i + 1 < text.length) {
        out += text[i + 1];
        i += 2;
        continue;
      }
      if (c === inStr) inStr = null;
      i++;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      inStr = c;
      out += c;
      i++;
      continue;
    }
    if (c === '/' && text[i + 1] === '/') {
      while (i < text.length && text[i] !== '\n') { out += ' '; i++; }
      continue;
    }
    if (c === '/' && text[i + 1] === '*') {
      out += '  ';
      i += 2;
      while (i < text.length && !(text[i] === '*' && text[i + 1] === '/')) {
        out += text[i] === '\n' ? '\n' : ' ';
        i++;
      }
      if (i < text.length) { out += '  '; i += 2; }
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

/** Op -> the Firestore SDK call name(s) that shape genuinely proves that
 * op. Plain names (not regexes) -- round 3's `sdkCallSiteArgTexts()` below
 * needs each individual call NAME so it can find and balanced-paren-extract
 * that SPECIFIC call's own argument list, not just test whether the token
 * appears anywhere in a larger block of text. */
const OP_SDK_CALL_NAMES = {
  read: ['getDoc', 'getDocs'],
  create: ['setDoc', 'addDoc'],
  update: ['updateDoc'],
  delete: ['deleteDoc'],
};

// ---------------------------------------------------------------------------
// CONDITIONAL-ref PATH verification (item 1 remediation, original round).
//
// The checks above only prove the named test has the right SDK-call SHAPE
// (updateDoc/setDoc/etc) and contains both an assertSucceeds and an
// assertFails case -- neither proves the test actually targets the
// DECLARED collection. A CONDITIONAL cell could legally name an unrelated
// existing test (e.g. `_canary/update`) for a brand-new sensitive
// collection and pass every check above. This derives the actual
// Firestore path(s) the named test constructs from its own `doc(db, ...)`
// call sites and confirms at least one resolves to the same collection
// segment as the policy entry's declared `path`.
// ---------------------------------------------------------------------------

/** Split a `doc(...)`/similar call's balanced-paren argument text into its
 * top-level, comma-separated arguments -- respecting nested parens/
 * brackets/braces and string/template-literal quoting, so a comma inside a
 * template interpolation or a nested call does not split an argument in
 * two. */
function splitTopLevelArgs(argsText) {
  const parts = [];
  let depth = 0;
  let inStr = null;
  let current = '';
  for (let i = 0; i < argsText.length; i++) {
    const c = argsText[i];
    if (inStr) {
      current += c;
      if (c === '\\') {
        i++;
        if (i < argsText.length) current += argsText[i];
        continue;
      }
      if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"' || c === "'" || c === '`') {
      inStr = c;
      current += c;
      continue;
    }
    if (c === '(' || c === '[' || c === '{') {
      depth++;
      current += c;
      continue;
    }
    if (c === ')' || c === ']' || c === '}') {
      depth--;
      current += c;
      continue;
    }
    if (c === ',' && depth === 0) {
      parts.push(current);
      current = '';
      continue;
    }
    current += c;
  }
  if (current.trim() !== '') parts.push(current);
  return parts.map((s) => s.trim());
}

/** Every `doc(<dbExpr>, <pathArg>)` call site within `text` -- returns the
 * raw, still-quoted path-argument text (the LAST top-level argument), one
 * entry per call site. A bare-word boundary (`\bdoc\(`) deliberately does
 * not match `getDoc(`/`setDoc(`/etc (different capitalization), only the
 * standalone `doc(...)` document-ref constructor these tests actually use. */
function docCallPathArgs(text) {
  const out = [];
  const re = /\bdoc\(/g;
  let m;
  while ((m = re.exec(text)) !== null) {
    const argStart = m.index + m[0].length;
    let depth = 1;
    let i = argStart;
    for (; i < text.length && depth > 0; i++) {
      if (text[i] === '(') depth++;
      else if (text[i] === ')') depth--;
    }
    const argsText = text.slice(argStart, i - 1);
    const parts = splitTopLevelArgs(argsText);
    if (parts.length >= 2) out.push(parts[parts.length - 1]);
  }
  return out;
}

/** Same normalization applied to a declared `clientAccess[].path` string
 * (e.g. `/users/{uid}/profile/{docId}`) -- `{var}` path segments become the
 * same wildcard token a test's `${...}` interpolation becomes above, so
 * the two sides compare on equal footing. */
function declaredCollectionSegments(declaredPath) {
  const segs = declaredPath
    .split('/')
    .filter(Boolean)
    .map((s) => (s.startsWith('{') && s.endsWith('}') ? '*' : s));
  segs.pop();
  return segs;
}

function collectionSegmentsMatch(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] === '*' || b[i] === '*') continue;
    if (a[i] !== b[i]) return false;
  }
  return true;
}

/** Every top-level `<fnName>(...)` call's own balanced-paren ARGUMENT text
 * within `text` (used for `assertSucceeds`/`assertFails` -- each entry is
 * one call's own argument text, analyzed as its own self-contained unit,
 * not the whole surrounding test body). */
function extractCallArgTexts(text, fnName) {
  const out = [];
  const re = new RegExp(`\\b${fnName}\\(`, 'g');
  let m;
  while ((m = re.exec(text)) !== null) {
    const argStart = m.index + m[0].length;
    let depth = 1;
    let i = argStart;
    for (; i < text.length && depth > 0; i++) {
      if (text[i] === '(') depth++;
      else if (text[i] === ')') depth--;
    }
    out.push(text.slice(argStart, i - 1));
  }
  return out;
}

/** Every occurrence, within `text`, of a call to one of `sdkNames` (e.g.
 * `['updateDoc']` or `['getDoc', 'getDocs']`) -- returns each call's OWN
 * balanced-paren argument-list text (not the surrounding text), one entry
 * per call site, across all names. Reuses `extractCallArgTexts()` per name
 * rather than a single alternation regex, since that helper is already
 * proven correct (nested parens, no false match on a differently-cased
 * sibling like `setDoc` when searching for `doc`). */
function sdkCallSiteArgTexts(text, sdkNames) {
  const out = [];
  for (const name of sdkNames) out.push(...extractCallArgTexts(text, name));
  return out;
}

/**
 * (2026-09-16 remediation round 4, BLOCKER) Whether `trimmedArgText`
 * (already `.trim()`-ed) is, STRUCTURALLY, itself a call to one of
 * `sdkNames` -- i.e. it starts at index 0 with `<sdkName>(`, and everything
 * from there to that call's own balanced matching close-paren accounts for
 * the entire trimmed text, modulo a single optional trailing comma (JS/TS's
 * own permitted trailing comma after a lone single argument -- e.g.
 * `assertSucceeds(\n  setDoc(...),\n)`, the real multi-line shape several of
 * this codebase's own hand-written conditionalRefs tests use -- verified
 * against all 7 before writing this, see the doc comment on
 * `analyzeAssertCalls` below). Returns `{ name, argsText }` (the matched
 * SDK call's own argument-list text) on a match, `null` otherwise.
 *
 * GPT-PM's own round-4 ruling (core/DECISION_LOG.md, "GPT-PM ruled on the
 * round-cap process question"): acceptance must be stronger than "some
 * matching call exists somewhere in the argument" -- the assertSucceeds/
 * assertFails argument itself must BE one supported SDK operation
 * expression, not an arbitrary wrapper searched recursively for a matching
 * call inside it. This single structural change closes three distinct
 * sub-cases GPT-PM named, together, in one mechanism rather than three
 * separate patches:
 *   - a `Promise.all([updateDoc(profileRef, validPatch),
 *     updateDoc(invalidCanaryRef, ...)])`-wrapped assertion: the trimmed
 *     text starts with `Promise.all(`, not any SDK name, so it never
 *     matches -- the whole assertion is correctly treated as NOT valid
 *     evidence, regardless of which individual call inside it happens to
 *     target the declared path (see mutation class (x));
 *   - an `await someHelper(...)` (or any other) wrapper around a real SDK
 *     call: same reasoning, the trimmed text does not start with the SDK
 *     name;
 *   - an SDK-call-shaped decoy substring sitting inside an actual string
 *     literal (`"updateDoc(doc(db,'x'))"` as a log message, say): the
 *     trimmed text starts with a quote character, never with the bare SDK
 *     name followed directly by `(`, so it is never mistaken for a real
 *     call, structurally, with no separate string-literal-awareness pass
 *     needed (see mutation class (y)).
 */
function wholeSdkCallExpression(trimmedArgText, sdkNames) {
  for (const name of sdkNames) {
    const prefix = `${name}(`;
    if (!trimmedArgText.startsWith(prefix)) continue;
    let depth = 1;
    let i = prefix.length;
    for (; i < trimmedArgText.length && depth > 0; i++) {
      if (trimmedArgText[i] === '(') depth++;
      else if (trimmedArgText[i] === ')') depth--;
    }
    if (depth !== 0) continue; // unbalanced -- malformed text, not a real call.
    const trailing = trimmedArgText.slice(i);
    if (!/^,?\s*$/.test(trailing)) continue; // something else follows the call -- the argument is not ITSELF just this call.
    return { name, argsText: trimmedArgText.slice(prefix.length, i - 1) };
  }
  return null;
}

/**
 * (2026-09-16 remediation round 3+4, BLOCKER) Whether AT LEAST ONE call to
 * `fnLabel` (`assertSucceeds` or `assertFails`) in the test body IS,
 * ITSELF, structurally, an op-shaped SDK call (`updateDoc`/`setDoc`/etc --
 * see `wholeSdkCallExpression` above) WHOSE OWN document-reference argument
 * (that SDK call's own first top-level argument -- every real hand-written
 * CONDITIONAL test in this codebase calls `updateDoc(doc(ctx, path), data)`
 * / `setDoc(doc(ctx, path), data)` / `deleteDoc(doc(ctx, path))` /
 * `getDoc(doc(ctx, path))`, i.e. an inline `doc(...)` call as the first
 * argument, directly, with no wrapper -- verified against every one of the
 * 7 hand-written conditionalRefs tests in data_access_policy.test.ts before
 * writing this) resolves to the declared collection.
 *
 * Round-3's own remediation (BLOCKER 2, kept here for the history) bound
 * "which assertSucceeds/assertFails call" and "which specific SDK-call-
 * within-that-assertion's own argument" -- but it found the matching SDK
 * call by searching (`sdkCallSiteArgTexts`) anywhere WITHIN the assertion's
 * argument text, not requiring the assertion argument to itself BE that
 * call. That left three related gaps GPT-PM found in round 4 (see
 * `wholeSdkCallExpression`'s own doc comment: a `Promise.all([...])`-wrapped
 * multi-call assertion could certify on an unrelated call's match; a
 * wrapper could hide an SDK call several levels deep; an SDK-call-shaped
 * decoy substring inside a string literal was, in principle, matchable by
 * pure text scanning). Requiring the argument to itself structurally BE the
 * SDK call closes all three at once, in one mechanism.
 *
 * Residual, explicitly not closed here: if a real test ever passed a
 * VARIABLE holding a pre-built document reference (`const ref = doc(...);
 * updateDoc(ref, data)`) instead of an inline `doc(...)` call, this cannot
 * trace the variable's value back to a path -- `docCallPathArgs()` finds no
 * `doc(...)` call inside a bare `ref` argument and the site is simply
 * skipped (neither counted as shape evidence nor path evidence for that
 * particular call). Checked: none of the 7 real hand-written conditionalRefs
 * tests in data_access_policy.test.ts use this pattern -- every one passes
 * an inline `doc(...)` call directly, so this residual limit does not
 * currently affect any real declared cell. A future CONDITIONAL test that
 * DID use a variable ref would fail closed (reason: 'shape' or 'path',
 * whichever check it never satisfies), not silently pass, so the failure
 * mode is safe even though the coverage gap is real.
 */
function analyzeAssertCalls(text, fnLabel, sdkNames, expectedSegs) {
  const calls = extractCallArgTexts(text, fnLabel);
  if (calls.length === 0) {
    return { ok: false, reason: 'presence' };
  }
  let sawShape = false;
  for (const argText of calls) {
    const call = wholeSdkCallExpression(argText.trim(), sdkNames);
    if (!call) continue; // the assertion's argument is not ITSELF a supported SDK call -- no evidence from this call.
    sawShape = true;
    const topArgs = splitTopLevelArgs(call.argsText);
    if (topArgs.length === 0) continue;
    const refArg = topArgs[0]; // the SDK call's OWN document-reference argument -- never a later one (payload/data).
    const segLists = docCallPathArgs(refArg).map(testDocPathCollectionSegments).filter((s) => s !== null);
    if (segLists.some((segs) => collectionSegmentsMatch(segs, expectedSegs))) {
      return { ok: true };
    }
  }
  if (!sawShape) {
    return { ok: false, reason: 'shape' };
  }
  return { ok: false, reason: 'path' };
}

function validateConditionalRef(op, ref, errors, context, declaredPath) {
  if (!ref || typeof ref !== 'object') {
    errors.push(`${context}: CONDITIONAL op "${op}" has no conditionalRefs entry`);
    return;
  }
  if (ref.operation !== op) {
    errors.push(`${context}: conditionalRefs.${op}.operation is "${ref.operation}", expected "${op}"`);
  }
  const testFilePath = path.join(REPO_ROOT, ref.testFile || '');
  if (!ref.testFile || !fs.existsSync(testFilePath)) {
    errors.push(`${context}: conditionalRefs.${op}.testFile "${ref.testFile}" does not exist`);
    return;
  }
  const text = fs.readFileSync(testFilePath, 'utf8');
  const rawBody = findTestBody(text, ref.testName || '');
  if (rawBody === null) {
    errors.push(`${context}: conditionalRefs.${op} names test "${ref.testName}", not found in ${ref.testFile}`);
    return;
  }
  // Comments stripped BEFORE any of the analysis below -- a `//` or `/* */`
  // comment containing matching tokens (an SDK call name, a doc() path)
  // must never count as real evidence.
  const body = stripComments(rawBody);

  const sdkNames = OP_SDK_CALL_NAMES[op];
  const expectedSegs = declaredCollectionSegments(declaredPath);

  const succeeds = analyzeAssertCalls(body, 'assertSucceeds', sdkNames, expectedSegs);
  const fails = analyzeAssertCalls(body, 'assertFails', sdkNames, expectedSegs);

  const describe = (label, result) => {
    if (result.ok) return;
    if (result.reason === 'presence') {
      errors.push(
        `${context}: conditionalRefs.${op} names test "${ref.testName}", which must contain an ${label} ` +
        'case for operation-specific proof -- none found.',
      );
      return;
    }
    if (result.reason === 'shape') {
      errors.push(
        `${context}: conditionalRefs.${op} names test "${ref.testName}", but its ${label}(...) call(s) ` +
        `contain no ${op}-shaped Firestore SDK call (expected one of: ${sdkNames.join(', ')}) -- it looks like it ` +
        'exercises a DIFFERENT operation than the one this cell declares.',
      );
      return;
    }
    // 'path'
    errors.push(
      `${context}: conditionalRefs.${op} names test "${ref.testName}", but its ${op}-shaped ${label}(...) ` +
      `call's own document-reference argument does not resolve to the declared collection ` +
      `"/${expectedSegs.join('/')}/..." -- this test does not actually exercise the declared path, so it ` +
      "proves nothing about this cell's real access.",
    );
  };
  describe('assertSucceeds', succeeds);
  describe('assertFails', fails);
}

/** Human-readable message for one fail-closed-scanner violation. */
function violationMessage(v) {
  const callText = v.callKind === 'doc' ? '.doc()' : '.collection()';
  const targetNoun = v.callKind === 'doc' ? 'Firestore path' : 'collection name';
  const loc = `${relPath(v.file)}:${v.line}`;
  if (v.kind === 'bare') {
    return `UNRESOLVED ${callText} CALL: ${loc} -- \`${v.expr}\` is a bare identifier (a local variable/` +
      `parameter -- helper-function indirection) whose value cannot be statically resolved to a literal ` +
      `${targetNoun}. Either change the call site to pass a literal directly, or -- only if this exact call ` +
      'site is genuinely safe (see DATA_ACCESS_POLICY_DESIGN.md §9 for audited examples) -- add ' +
      '{file, line, arg} for it to KNOWN_AUDITED_DYNAMIC_CALL_SITES in this script with a documented ' +
      'justification.';
  }
  if (v.kind === 'member') {
    return `UNRESOLVED ${callText} CALL: ${loc} -- \`${v.expr}\` is a property-access expression whose base ` +
      'identifier is not bound, via a local relative import (or same-file definition), to a registered ' +
      'path-registry export (see PATH_REGISTRIES in this script). Either this collection is already declared ' +
      'some other way, a new registry needs registering, or -- only if genuinely audited -- add it to ' +
      'KNOWN_AUDITED_DYNAMIC_CALL_SITES with a documented justification.';
  }
  return `UNRESOLVED ${callText} CALL: ${loc} -- \`${v.expr}\` is a non-literal expression (template ` +
    `interpolation, function call, or string concatenation) whose value cannot be statically resolved to a ` +
    `literal ${targetNoun}. Either change the call site to pass a literal directly, or -- only if this exact ` +
    'call site is genuinely safe and audited (see DATA_ACCESS_POLICY_DESIGN.md §9) -- add {file, line, arg} ' +
    'for it to KNOWN_AUDITED_DYNAMIC_CALL_SITES in this script with a documented justification.';
}

function main() {
  const blocks = parseFirestoreRulesFile(RULES_PATH);
  const files = productionFiles();
  const registries = loadRegistries();
  const { candidates, violations, residue, ambiguous } = discoverCandidates(blocks, files, registries);
  const policy = loadPolicy();

  let failed = false;
  const errors = [];

  // 1. Fail-closed scanner violations -- unconditional hard failure.
  for (const v of violations) {
    failed = true;
    errors.push(violationMessage(v));
  }

  // 1b. Ambiguous code-discovered names -- .collection() call sites for the
  // SAME name disagree on whether it is a per-user subcollection or a
  // top-level collection (some chained off .doc(...), some not). Cannot be
  // mechanically resolved -- fail closed rather than guess either way.
  for (const amb of ambiguous) {
    failed = true;
    errors.push(
      `AMBIGUOUS collection name "${amb.name}": discovered via .collection() calls both chained off a ` +
      `.doc(...) reference (per-user subcollection shape) and NOT chained off one (top-level shape) -- this ` +
      `script cannot mechanically determine its canonical path. Call sites: ` +
      `${amb.examples.map((e) => `${relPath(e.file)}:${e.line}`).join(', ')}. Resolve by adding a dedicated ` +
      `firestore.rules match block for this collection (removing the ambiguity), or by making its ` +
      `.collection() call sites consistent.`,
    );
  }

  // 2. Every declared clientAccess[].path across the WHOLE policy, flattened.
  const declaredPaths = new Map(); // canonicalPath -> {collectionName, entry}
  for (const [collName, entry] of Object.entries(policy.collections)) {
    for (const ca of entry.clientAccess || []) {
      declaredPaths.set(ca.path, { collectionName: collName, ca });
    }
  }

  // 3. Coverage: every discovered candidate must have a declaration.
  const missing = [];
  for (const [canonicalPath, info] of candidates) {
    if (!declaredPaths.has(canonicalPath)) missing.push({ canonicalPath, ...info });
  }
  if (missing.length > 0) {
    failed = true;
    for (const m of missing) {
      errors.push(
        `NO clientAccess DECLARATION for discovered path ${m.canonicalPath} (leaf "${m.leaf}", ` +
        `sources: ${[...m.sources].join(', ')}) -- add a clientAccess entry in ${relPath(POLICY_PATH)}.`,
      );
    }
  }

  // 4. Schema + semantic validation of every declared entry.
  for (const [collName, entry] of Object.entries(policy.collections)) {
    if (!Array.isArray(entry.clientAccess) || entry.clientAccess.length === 0) {
      failed = true;
      errors.push(`${collName}: no clientAccess array (or it is empty) -- every policy collection needs one.`);
      continue;
    }
    for (const ca of entry.clientAccess) {
      const context = `${collName} (${ca.path})`;
      if (!ca.path || typeof ca.path !== 'string') {
        failed = true;
        errors.push(`${context}: missing or non-string "path"`);
        continue;
      }
      if (!ca.access || typeof ca.access !== 'object') {
        failed = true;
        errors.push(`${context}: missing "access" object`);
        continue;
      }
      const { leaf, isUserSubcollection } = leafFromPath(ca.path);
      const expected = collectionAccess(blocks, ca.path, leaf, isUserSubcollection);

      for (const op of ALL_VERBS) {
        const declared = ca.access[op];
        if (!VALID_ACCESS_VALUES.has(declared)) {
          failed = true;
          errors.push(`${context}: access.${op} = ${JSON.stringify(declared)} is not one of ${[...VALID_ACCESS_VALUES].join('/')}`);
          continue;
        }
        const cls = expected[op].classification;
        // The hard, non-negotiable rule (GPT-PM round-1): OWNER is refused
        // outright wherever the rules body is NON_TRIVIAL -- CONDITIONAL is
        // the only legal declaration there. Extended, for the same reason,
        // to ALWAYS_FALSE/IMPLICIT_DENY (must declare NONE, not anything
        // more permissive) and to AUTHENTICATED/PUBLIC (must match the
        // rules' own bare-auth/bare-open shape exactly) -- a looser
        // declaration than what the rules actually grant is a false sense
        // of restriction, and a tighter one hides a real grant from anyone
        // reading the policy instead of the rules file.
        if ((cls === 'NON_TRIVIAL') && declared !== 'CONDITIONAL') {
          failed = true;
          errors.push(
            `${context}: access.${op} = "${declared}" but firestore.rules' own condition for this ` +
            `path/verb is NON_TRIVIAL (${expected[op].raw ? JSON.stringify(expected[op].raw) : '(none)'}) -- ` +
            `only CONDITIONAL may be declared here.`,
          );
        }
        if ((cls === 'ALWAYS_FALSE' || cls === 'IMPLICIT_DENY') && declared !== 'NONE') {
          failed = true;
          errors.push(`${context}: access.${op} = "${declared}" but firestore.rules denies this path/verb ` +
            `unconditionally (${cls}) -- only NONE may be declared here.`);
        }
        if (cls === 'PLAIN_OWNER' && declared !== 'OWNER') {
          failed = true;
          errors.push(`${context}: access.${op} = "${declared}" but firestore.rules grants this path/verb to ` +
            `the bare owner (PLAIN_OWNER) -- declare OWNER.`);
        }
        if (cls === 'AUTHENTICATED' && declared !== 'AUTHENTICATED') {
          failed = true;
          errors.push(`${context}: access.${op} = "${declared}" but firestore.rules grants this path/verb to ` +
            `any authenticated user -- declare AUTHENTICATED.`);
        }
        if (cls === 'PUBLIC' && declared !== 'PUBLIC') {
          failed = true;
          errors.push(`${context}: access.${op} = "${declared}" but firestore.rules grants this path/verb to ` +
            `everyone, signed in or not -- declare PUBLIC.`);
        }

        if (declared === 'CONDITIONAL') {
          const refs = ca.conditionalRefs || {};
          const errCountBefore = errors.length;
          validateConditionalRef(op, refs[op], errors, context, ca.path);
          if (errors.length > errCountBefore) failed = true;
        } else if (ca.conditionalRefs && ca.conditionalRefs[op]) {
          failed = true;
          errors.push(`${context}: access.${op} = "${declared}" but conditionalRefs.${op} is present -- ` +
            `conditionalRefs is only valid for a CONDITIONAL operation.`);
        }
      }
    }
  }
  // Re-scan errors array once more for any CONDITIONAL-ref failure that
  // didn't get `failed = true` set inline above (validateConditionalRef
  // pushes directly into `errors` without returning a boolean).
  if (!failed && errors.length > 0) failed = true;

  console.log(
    `Data access policy: ${candidates.size} discovered path(s), ${declaredPaths.size} declared, ` +
    `${violations.length} unresolved non-literal call(s), ${residue.length} documented dynamic-path residue.`,
  );
  if (residue.length > 0) {
    console.log('\nDynamic-path residue (not mechanically verifiable, individually audited -- see KNOWN_AUDITED_DYNAMIC_CALL_SITES):');
    for (const r of residue) console.log(`  ${relPath(r.file)}:${r.line} -- \`${r.expr}\` (${r.callKind})`);
  }

  if (errors.length > 0) {
    console.error('\nData access policy violations:');
    for (const e of errors) console.error(`  ${e}`);
  }

  if (failed) {
    console.error('\nFAILED.');
    process.exit(1);
  }
  console.log('\nOK -- every discovered path has a declared, rules-consistent clientAccess entry.');
}

module.exports = {
  PRODUCTION_SOURCE_ROOTS,
  PATH_REGISTRIES,
  KNOWN_AUDITED_DYNAMIC_CALL_SITES,
  walk,
  productionFiles,
  parseRegistry,
  loadRegistries,
  registryBindingHolds,
  hasLocalShadowDeclaration,
  memberCallSites,
  isAdjacentCall,
  testDocPathCollectionSegments,
  collectionShapeFromDocSegments,
  scanProductionCalls,
  discoverCandidates,
  leafFromPath,
  findTestBody,
  stripComments,
  analyzeAssertCalls,
  sdkCallSiteArgTexts,
};

if (require.main === module) {
  main();
}
