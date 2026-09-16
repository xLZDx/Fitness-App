#!/usr/bin/env node
// P2-ACCESS-1 -- mutation-proof self-test for check_data_access_policy.js.
//
// Mirrors verify_deployment_isolation.py's run_broken_identity_probe()
// pattern (scripts/equipment_identity/verify_deployment_isolation.py):
// an __dirname-relative TEMP COPY of the real, tracked files (never the
// tracked source itself), a real deterministic mutation, a real subprocess
// invocation of the real checker, and cleanup in `finally` even on
// failure. Five independent failure classes, each proven RED (mutation
// injected) then GREEN (the corresponding correct declaration/registration
// added) -- a check that only proves red is half the proof, same
// discipline that module's own header states.
//
// Run: node scripts/ci/test_check_data_access_policy.js
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const assert = require('assert');
const { spawnSync } = require('child_process');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const REAL_CHECKER = path.join(REPO_ROOT, 'scripts/ci/check_data_access_policy.js');
const REAL_PARSER = path.join(REPO_ROOT, 'scripts/ci/lib/rules_parser.js');
const REAL_POLICY = path.join(REPO_ROOT, 'scripts/ci/data_lifecycle_policy.json');
const REAL_RULES = path.join(REPO_ROOT, 'firestore.rules');
const REAL_TEST_FILE = path.join(REPO_ROOT, 'functions/src/__rules__/data_access_policy.test.ts');
const REAL_REGISTRY = path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/firestore_paths.ts');
const REAL_ACCOUNT_EXPORT = path.join(REPO_ROOT, 'functions/src/account_export.ts');
const REAL_TEXT_KEY_INDEX = path.join(REPO_ROOT, 'functions-equipment-identity/src/p2/text_key_index.ts');

let failures = 0;

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    failures++;
    console.error(`FAIL - ${name}`);
    console.error(err && err.stack ? err.stack : err);
  }
}

/** Builds a fresh __dirname-relative temp copy of the minimal real subset
 * this checker needs: the checker itself, its parser lib, the (real,
 * already-valid) policy JSON, the real firestore.rules, the real emulator
 * test file (for conditionalRefs existence/SDK-call checks), and the real
 * P2 path registry. Empty production-source directories otherwise -- the
 * checker's own discovery is self-sufficient from dedicated rules blocks
 * alone (28 of 37 declared paths need no code evidence at all), so a
 * baseline with zero extra source files is a genuine, real, green run of
 * the actual instrument, not a synthetic stand-in.
 */
function buildTempCopy() {
  const tmpRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'p2access_mutation_'));
  fs.mkdirSync(path.join(tmpRoot, 'scripts/ci/lib'), { recursive: true });
  fs.copyFileSync(REAL_CHECKER, path.join(tmpRoot, 'scripts/ci/check_data_access_policy.js'));
  fs.copyFileSync(REAL_PARSER, path.join(tmpRoot, 'scripts/ci/lib/rules_parser.js'));
  fs.copyFileSync(REAL_POLICY, path.join(tmpRoot, 'scripts/ci/data_lifecycle_policy.json'));
  fs.copyFileSync(REAL_RULES, path.join(tmpRoot, 'firestore.rules'));
  fs.mkdirSync(path.join(tmpRoot, 'functions/src/__rules__'), { recursive: true });
  fs.copyFileSync(REAL_TEST_FILE, path.join(tmpRoot, 'functions/src/__rules__/data_access_policy.test.ts'));
  fs.mkdirSync(path.join(tmpRoot, 'functions-equipment-identity/src/p2'), { recursive: true });
  fs.copyFileSync(REAL_REGISTRY, path.join(tmpRoot, 'functions-equipment-identity/src/p2/firestore_paths.ts'));
  fs.mkdirSync(path.join(tmpRoot, 'mobile/lib'), { recursive: true });
  return tmpRoot;
}

function runChecker(tmpRoot) {
  return spawnSync(process.execPath, [path.join(tmpRoot, 'scripts/ci/check_data_access_policy.js')], {
    encoding: 'utf8',
  });
}

function readPolicy(tmpRoot) {
  return JSON.parse(fs.readFileSync(path.join(tmpRoot, 'scripts/ci/data_lifecycle_policy.json'), 'utf8'));
}
function writePolicy(tmpRoot, policy) {
  fs.writeFileSync(path.join(tmpRoot, 'scripts/ci/data_lifecycle_policy.json'), JSON.stringify(policy, null, 2), 'utf8');
}

function assertGreen(result, context) {
  if (result.status !== 0) {
    throw new Error(`${context}: expected GREEN (exit 0), got exit ${result.status}\n--- stdout ---\n${result.stdout}\n--- stderr ---\n${result.stderr}`);
  }
}
function assertRed(result, context, expectedSubstring) {
  if (result.status === 0) {
    throw new Error(`${context}: expected RED (nonzero exit), got exit 0\n--- stdout ---\n${result.stdout}`);
  }
  const combined = result.stdout + result.stderr;
  if (!combined.includes(expectedSubstring)) {
    throw new Error(`${context}: RED as expected, but stdout/stderr did not contain ${JSON.stringify(expectedSubstring)}\n--- stdout ---\n${result.stdout}`);
  }
}

// Baseline sanity, run first: the unmutated temp copy must itself be
// GREEN, or every "RED after mutation" result below is meaningless (an
// already-broken instrument produces failures for the wrong reason -- the
// same baseline discipline verify_deployment_isolation.py's own
// run_broken_identity_probe() applies before injecting anything).
let baselineTmp;
run('baseline: unmutated temp copy is GREEN', () => {
  baselineTmp = buildTempCopy();
  const result = runChecker(baselineTmp);
  assertGreen(result, 'baseline');
});

// -----------------------------------------------------------------------
// (a) fake literal under functions/src, no declaration -> RED, then fixed.
// -----------------------------------------------------------------------
run('(a) undeclared literal .collection() under functions/src -> RED, then GREEN once declared', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_a.ts');
    // Chained off `.doc('someUid')` -- this codebase's own real call shape
    // for every per-user subcollection reached only via code (see e.g.
    // mobile/lib's repository classes: `.collection('users').doc(uid)
    // .collection('workout_logs')`), so item 5's shape-based
    // subcollection-vs-top-level disambiguation reads this the same way a
    // genuine new per-user-subcollection call site would.
    fs.writeFileSync(mutFile, `export function touch(db: any) {\n  return db.collection('users').doc('someUid').collection('sensitive_new');\n}\n`);

    const red = runChecker(tmp);
    assertRed(red, '(a) red', 'sensitive_new');
    assertRed(red, '(a) red names the gap', 'NO clientAccess DECLARATION');

    const policy = readPolicy(tmp);
    policy.collections.sensitive_new = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture',
      clientAccess: [{ path: '/users/{uid}/sensitive_new/{docId}', access: { read: 'OWNER', create: 'OWNER', update: 'OWNER', delete: 'OWNER' } }],
    };
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(a) green after declaring');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (b) same shape, but under functions-equipment-identity/src specifically
// -- proves the NEW source root is actually wired into discovery, not
// just documented in a comment.
// -----------------------------------------------------------------------
run('(b) undeclared literal .collection() under functions-equipment-identity/src -> RED, then GREEN once declared', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions-equipment-identity/src/__mutation_b.ts');
    // Chained off `.doc('someUid')` -- see (a)'s own comment on why this
    // matters post-item-5.
    fs.writeFileSync(mutFile, `export function touch(db: any) {\n  return db.collection('users').doc('someUid').collection('sensitive_identity_new');\n}\n`);

    const red = runChecker(tmp);
    assertRed(red, '(b) red', 'sensitive_identity_new');

    const policy = readPolicy(tmp);
    policy.collections.sensitive_identity_new = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture',
      clientAccess: [{ path: '/users/{uid}/sensitive_identity_new/{docId}', access: { read: 'OWNER', create: 'OWNER', update: 'OWNER', delete: 'OWNER' } }],
    };
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(b) green after declaring');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (c) an already-classified leaf name ("profile") under a STRUCTURALLY
// DIFFERENT injected parent path -> must be treated as a NEW, undeclared
// path, not silently covered by the existing users/{uid}/profile entry
// (proves path-awareness rather than leaf-collapse).
// -----------------------------------------------------------------------
run('(c) same leaf name, different parent path -> RED (not leaf-collapsed), then GREEN once declared', () => {
  const tmp = buildTempCopy();
  try {
    const rulesPath = path.join(tmp, 'firestore.rules');
    const rules = fs.readFileSync(rulesPath, 'utf8');
    const injected = rules.replace(
      '    // Equipment + exercise catalogs are read-only for clients.',
      `    match /admin/{adminId}/profile/{docId} {\n` +
      `      allow read, write: if request.auth != null && request.auth.uid == adminId;\n` +
      `    }\n\n` +
      `    // Equipment + exercise catalogs are read-only for clients.`,
    );
    assert.notStrictEqual(injected, rules, 'injection anchor not found in copied firestore.rules');
    fs.writeFileSync(rulesPath, injected);

    const red = runChecker(tmp);
    assertRed(red, '(c) red', '/admin/{adminId}/profile/{docId}');

    const policy = readPolicy(tmp);
    policy.collections.profile.clientAccess.push({
      path: '/admin/{adminId}/profile/{docId}',
      access: { read: 'OWNER', create: 'OWNER', update: 'OWNER', delete: 'OWNER' },
    });
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(c) green after declaring the new path');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (d) a CONDITIONAL cell's conditionalRef pointed at a test that exercises
// a DIFFERENT operation (an existing, real, read-only test cited for an
// `update` declaration) -> RED, then GREEN once corrected.
// -----------------------------------------------------------------------
run('(d) conditionalRef naming a wrong-operation test -> RED, then GREEN once corrected', () => {
  const tmp = buildTempCopy();
  try {
    const policy = readPolicy(tmp);
    const original = JSON.parse(JSON.stringify(policy.collections.profile.clientAccess[0].conditionalRefs.update));
    policy.collections.profile.clientAccess[0].conditionalRefs.update.testName =
      'CONDITIONAL cell _canary/read: the canary identity can read its own document';
    writePolicy(tmp, policy);

    const red = runChecker(tmp);
    assertRed(red, '(d) red', 'no update-shaped Firestore SDK call');

    policy.collections.profile.clientAccess[0].conditionalRefs.update = original;
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(d) green after correcting the ref');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (e) a non-literal, UNREGISTERED property-access .collection() call ->
// RED naming the call site, then GREEN once genuinely REGISTERED (not
// merely deleted) -- plus the companion POSITIVE proof that the REAL
// P2CollectionPaths.textKeys registration needs no hand-mapping at all.
// -----------------------------------------------------------------------
run('(e) unregistered property-access .collection() call -> RED naming the site, then GREEN once registered', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_e.ts');
    // Chained off `.doc('someUid')` -- see (a)'s own comment on why this
    // matters post-item-5.
    fs.writeFileSync(
      mutFile,
      `export const SomeUnregisteredConst = { value: "sneaky_collection" } as const;\n` +
      `export function touch(db: any) {\n  return db.collection('users').doc('someUid').collection(SomeUnregisteredConst.value);\n}\n`,
    );

    const red = runChecker(tmp);
    assertRed(red, '(e) red', 'UNRESOLVED .collection() CALL');
    assertRed(red, '(e) red names the expression', 'SomeUnregisteredConst.value');

    // Fix by REGISTERING, not by deleting the call site: mutate the
    // temp-copied checker's own PATH_REGISTRIES to include the new export,
    // and declare the collection it resolves to -- same two-step shape a
    // real developer follows for a genuine new registry (register, then
    // declare the discovered path). The fixture file defines
    // SomeUnregisteredConst AND does the `.collection()` call in the same
    // file, so it is trivially "same-file" import-bound (item 4's
    // registryBindingHolds() treats same-file definition as bound with no
    // import needed) -- (q) below covers the cross-file, genuinely-
    // unbound-shadow case item 4 was actually about.
    const checkerPath = path.join(tmp, 'scripts/ci/check_data_access_policy.js');
    const checkerText = fs.readFileSync(checkerPath, 'utf8');
    const patched = checkerText.replace(
      'const PATH_REGISTRIES = [',
      "const PATH_REGISTRIES = [\n  { file: path.join(REPO_ROOT, 'functions/src/__mutation_e.ts'), exportName: 'SomeUnregisteredConst' },",
    );
    assert.notStrictEqual(patched, checkerText, 'PATH_REGISTRIES anchor not found in copied checker');
    fs.writeFileSync(checkerPath, patched);

    const policy = readPolicy(tmp);
    policy.collections.sneaky_collection = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture',
      clientAccess: [{ path: '/users/{uid}/sneaky_collection/{docId}', access: { read: 'OWNER', create: 'OWNER', update: 'OWNER', delete: 'OWNER' } }],
    };
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(e) green after registering + declaring');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

run('(e-positive) the REAL P2CollectionPaths.textKeys registration needs no hand-mapping', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions-equipment-identity/src/__mutation_e_positive.ts');
    fs.writeFileSync(
      mutFile,
      `import { P2CollectionPaths } from "./p2/firestore_paths";\n` +
      `export function touch(db: any) {\n  return db.collection(P2CollectionPaths.textKeys);\n}\n`,
    );

    const result = runChecker(tmp);
    assertGreen(result, '(e-positive) real registry resolves with no hand-mapping');
    // Belt-and-suspenders: use the checker's own exported internals
    // in-process to confirm the call site was actually RESOLVED via the
    // registry (registryHits), not merely absent from violations because
    // it was never scanned at all.
    delete require.cache[require.resolve(path.join(tmp, 'scripts/ci/check_data_access_policy.js'))];
    const checkerModule = require(path.join(tmp, 'scripts/ci/check_data_access_policy.js'));
    const files = checkerModule.productionFiles();
    assert.ok(files.some((f) => f.includes('__mutation_e_positive.ts')), 'fixture file was not scanned as production source');
    const registries = checkerModule.loadRegistries();
    const { registryHits, violations } = checkerModule.scanProductionCalls(files, registries);
    assert.ok(
      registryHits.some((h) => h.value === 'equipment_model_text_keys'),
      `expected a registryHits entry resolving to equipment_model_text_keys, got: ${JSON.stringify(registryHits)}`,
    );
    assert.strictEqual(violations.length, 0, `expected zero violations, got: ${JSON.stringify(violations)}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// =========================================================================
// Remediation round (2026-09-16): cold second-round internal review
// (database-reviewer + security-reviewer) found 1 BLOCKER + 4 distinct
// MAJOR in the five classes above's own blind spots. Each gets its own
// mutation-proof class here, same RED-then-GREEN discipline, named by the
// item number from core/DECISION_LOG.md's "Row 24 gate" remediation entry.
// =========================================================================

// -----------------------------------------------------------------------
// (f) [item 1, was BLOCKER] a CONDITIONAL cell's conditionalRef pointed at
// a real, CORRECTLY-SHAPED test (right SDK call, has both asserts) for a
// DIFFERENT collection entirely -> RED naming the path mismatch (not the
// SDK-shape mismatch (d) already covers), then GREEN once pointed back at
// a real profile-path test.
// -----------------------------------------------------------------------
run('(f) conditionalRef pointing at a real, correctly-shaped test for a DIFFERENT collection -> RED naming the path mismatch, then GREEN once pointed at a real profile-path test', () => {
  const tmp = buildTempCopy();
  try {
    const policy = readPolicy(tmp);
    const original = JSON.parse(JSON.stringify(policy.collections.profile.clientAccess[0].conditionalRefs.update));
    // _canary/update: right op (updateDoc), has both assertSucceeds and
    // assertFails -- passes every check (d)'s SDK-shape/both-asserts logic
    // covers. Isolates the NEW path-derivation check this item adds: none
    // of its doc() calls construct a /users/{uid}/profile/... path.
    policy.collections.profile.clientAccess[0].conditionalRefs.update.testName =
      'CONDITIONAL cell _canary/update: the canary identity can update its own document';
    writePolicy(tmp, policy);

    const red = runChecker(tmp);
    assertRed(red, '(f) red', 'does not actually exercise the declared path');
    assertRed(red, '(f) red names the declared collection', 'users/*/profile');

    policy.collections.profile.clientAccess[0].conditionalRefs.update = original;
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(f) green after pointing back at a real profile-path test');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (g) [item 2, was MAJOR x2, independently found] a dedicated block
// restricting a verb the generic wildcard would otherwise still grant
// (unexcluded) -> RED naming the missing exclusion (Firestore ORs matching
// rules, so the wildcard's grant is still live), then GREEN once the
// exclusion is added.
// -----------------------------------------------------------------------
run('(g) dedicated restrictive block NOT excluded from the wildcard -> RED naming the missing exclusion, then GREEN once excluded', () => {
  const tmp = buildTempCopy();
  try {
    const rulesPath = path.join(tmp, 'firestore.rules');
    const rules = fs.readFileSync(rulesPath, 'utf8');
    const withDedicated = rules.replace(
      '    // Equipment + exercise catalogs are read-only for clients.',
      `    match /users/{uid}/newLeaf/{docId} {\n` +
      `      allow write: if false;\n` +
      `    }\n\n` +
      `    // Equipment + exercise catalogs are read-only for clients.`,
    );
    assert.notStrictEqual(withDedicated, rules, '(g) dedicated-block injection anchor not found');
    fs.writeFileSync(rulesPath, withDedicated);

    const policy = readPolicy(tmp);
    policy.collections.newLeaf = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture (item 2)',
      clientAccess: [{
        path: '/users/{uid}/newLeaf/{docId}',
        access: { read: 'OWNER', create: 'NONE', update: 'NONE', delete: 'NONE' },
      }],
    };
    writePolicy(tmp, policy);

    const red = runChecker(tmp);
    assertRed(red, '(g) red', "coll != 'newLeaf'");
    assertRed(red, '(g) red names the leaf', 'newLeaf');

    const excluded = withDedicated.replace(
      "coll != 'profile'",
      "coll != 'profile'\n                   && coll != 'newLeaf'",
    );
    assert.notStrictEqual(excluded, withDedicated, '(g) exclusion-injection anchor not found');
    fs.writeFileSync(rulesPath, excluded);

    const green = runChecker(tmp);
    assertGreen(green, '(g) green after adding the exclusion');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (h) [item 3, was MAJOR] a second `allow write` statement for an
// already-populated verb within one block -> RED (fail closed, not
// silently keep the last one), then GREEN on the real, unmodified
// firestore.rules (which has no such duplicate today).
// -----------------------------------------------------------------------
run('(h) duplicate allow-statement for the same verb within one block -> RED, then GREEN on the real unmodified rules', () => {
  const tmp = buildTempCopy();
  try {
    const rulesPath = path.join(tmp, 'firestore.rules');
    const rules = fs.readFileSync(rulesPath, 'utf8');
    const duplicated = rules.replace(
      '                           || request.resource.data.lifestyle.alcohol == null));\n    }',
      '                           || request.resource.data.lifestyle.alcohol == null));\n' +
      '      allow write: if request.auth != null && request.auth.uid == uid;\n    }',
    );
    assert.notStrictEqual(duplicated, rules, '(h) duplicate-statement injection anchor not found');
    fs.writeFileSync(rulesPath, duplicated);

    const red = runChecker(tmp);
    assertRed(red, '(h) red', 'more than one "allow" statement covering');
    assertRed(red, '(h) red names the block', '/users/{uid}/profile/{docId}');

    // GREEN: the real, unmodified rules file has no such duplicate.
    fs.writeFileSync(rulesPath, rules);
    const green = runChecker(tmp);
    assertGreen(green, '(h) green on the real unmodified firestore.rules');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (i) [item 4, was MAJOR] a one-line helper function wrapping
// `.collection(<param>)` (bare-identifier indirection, not
// Identifier.member) -> RED naming the call site, then GREEN once the
// exact call site is added to KNOWN_AUDITED_DYNAMIC_CALL_SITES with a
// documented justification (the only legitimate fix path for a call this
// scanner genuinely cannot resolve to a name -- see item 5's own note that
// the collection name itself, "brand_new_leaf", never appears as a literal
// anywhere the scanner looks, which is exactly why the bare-identifier
// shape itself has to be the hard-fail signal).
// -----------------------------------------------------------------------
run('(i) bare-identifier helper-function indirection wrapping .collection() -> RED naming the call site, then GREEN once explicitly allow-listed', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_i.ts');
    fs.writeFileSync(
      mutFile,
      'export function coll(db: any, n: string) {\n' + // line 1
      '  return db.collection(n);\n' + // line 2 -- the call site under test
      '}\n' + // line 3
      'export function touch(db: any) {\n' + // line 4
      "  return coll(db, 'brand_new_leaf');\n" + // line 5
      '}\n', // line 6
    );

    const red = runChecker(tmp);
    assertRed(red, '(i) red', 'UNRESOLVED .collection() CALL');
    assertRed(red, '(i) red names the shape', 'bare identifier');
    assertRed(red, '(i) red names the call site', '__mutation_i.ts:2');

    const checkerPath = path.join(tmp, 'scripts/ci/check_data_access_policy.js');
    const checkerText = fs.readFileSync(checkerPath, 'utf8');
    const patched = checkerText.replace(
      'const KNOWN_AUDITED_DYNAMIC_CALL_SITES = [',
      "const KNOWN_AUDITED_DYNAMIC_CALL_SITES = [\n  { file: path.join(REPO_ROOT, 'functions/src/__mutation_i.ts'), line: 2, arg: 'n', reason: 'mutation-proof fixture' },",
    );
    assert.notStrictEqual(patched, checkerText, '(i) KNOWN_AUDITED_DYNAMIC_CALL_SITES anchor not found');
    fs.writeFileSync(checkerPath, patched);

    const green = runChecker(tmp);
    assertGreen(green, '(i) green after allow-listing the exact call site');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (j) [item 5, was MAJOR] a code-discovered .collection() call NOT chained
// off a .doc(...) reference (this codebase's own real top-level shape) is
// no longer mis-derived as a per-user subcollection -> RED naming the
// CORRECT top-level canonical path; still RED if wrongly declared at the
// old, buggy subcollection-shaped path (proves the fix actually changed
// the derived path, not merely relocated the same bug); GREEN once
// declared at the real top-level path (implicit default-deny, since no
// dedicated rules block exists for it).
// -----------------------------------------------------------------------
run('(j) code-discovered top-level (non-doc-chained) .collection() call is not mis-derived as a user subcollection', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_j.ts');
    fs.writeFileSync(mutFile, `export function touch(db: any) {\n  return db.collection('new_top_level_leaf').doc('x');\n}\n`);

    const red = runChecker(tmp);
    assertRed(red, '(j) red', 'NO clientAccess DECLARATION for discovered path /new_top_level_leaf/{docId}');

    // Wrong fix: declare it at the OLD, pre-fix (buggy) subcollection-shaped
    // path -- must still be RED, proving the fix changed the derived
    // canonical path rather than merely relocating the same bug.
    const wrongPolicy = readPolicy(tmp);
    wrongPolicy.collections.new_top_level_leaf = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture (item 5) -- WRONG path, must still fail',
      clientAccess: [{
        path: '/users/{uid}/new_top_level_leaf/{docId}',
        access: { read: 'OWNER', create: 'OWNER', update: 'OWNER', delete: 'OWNER' },
      }],
    };
    writePolicy(tmp, wrongPolicy);
    const stillRed = runChecker(tmp);
    assertRed(stillRed, '(j) still red on the wrong (subcollection) declaration', 'NO clientAccess DECLARATION for discovered path /new_top_level_leaf/{docId}');

    // Correct fix: declare at the REAL top-level path Firestore actually
    // resolves -- no dedicated rules block, so every verb is an implicit
    // default-deny.
    const policy = readPolicy(tmp);
    policy.collections.new_top_level_leaf = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture (item 5)',
      clientAccess: [{
        path: '/new_top_level_leaf/{docId}',
        access: { read: 'NONE', create: 'NONE', update: 'NONE', delete: 'NONE' },
      }],
    };
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(j) green after declaring the correct top-level path');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (k) [item 5, companion] the SAME code-discovered name reached through
// BOTH shapes (chained off .doc(...) at one call site, not at another) is
// genuinely ambiguous -- the checker fails closed naming both call sites
// rather than guessing either way.
// -----------------------------------------------------------------------
run('(k) code-discovered name with CONFLICTING call-site shapes -> RED naming the ambiguity', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_k.ts');
    fs.writeFileSync(
      mutFile,
      "export function subShape(db: any) {\n  return db.collection('users').doc('someUid').collection('weird_leaf');\n}\n" +
      "export function topShape(db: any) {\n  return db.collection('weird_leaf');\n}\n",
    );

    const red = runChecker(tmp);
    assertRed(red, '(k) red', 'AMBIGUOUS collection name "weird_leaf"');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// =========================================================================
// Remediation round 2 (2026-09-16): GPT-PM implementation review round 1
// (core/DECISION_LOG.md's "Row 24 gate" entry) found 3 BLOCKER + 4 MAJOR
// against the round-1 remediation above. Each gets its own mutation-proof
// class here, same RED-then-GREEN discipline, named by the finding number
// from that entry.
// =========================================================================

// -----------------------------------------------------------------------
// (l) [finding 1, BLOCKER] Source D -- a direct db().doc(<full path>) call
// with no matching declaration is now discovered (previously invisible to
// every discovery source: only .collection() shapes were scanned).
// -----------------------------------------------------------------------
run('(l) [finding 1] undeclared db().doc(`full/path`) call under functions/src -> RED, then GREEN once declared', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_l.ts');
    fs.writeFileSync(
      mutFile,
      'export function touch() {\n  return db().doc(`users/${uid}/sensitive_new/current`);\n}\n',
    );

    const red = runChecker(tmp);
    assertRed(red, '(l) red', 'NO clientAccess DECLARATION for discovered path /users/{uid}/sensitive_new/{docId}');

    const policy = readPolicy(tmp);
    policy.collections.sensitive_new = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture (finding 1)',
      clientAccess: [{ path: '/users/{uid}/sensitive_new/{docId}', access: { read: 'OWNER', create: 'OWNER', update: 'OWNER', delete: 'OWNER' } }],
    };
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(l) green after declaring');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (m) [finding 2a, BLOCKER] a function-call argument to .collection() with
// no separately-discoverable literal -- previously silently exempted as
// "dynamic-path residue" for the WHOLE expression class; now hard-fails by
// default like every other unresolved shape.
// -----------------------------------------------------------------------
run('(m) [finding 2a] function-call argument to .collection() -> RED naming the call site (no allowlist entry exists for it)', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_m.ts');
    fs.writeFileSync(
      mutFile,
      'export function touch(db: any) {\n  return db.collection(getSensitiveCollectionName());\n}\n',
    );

    const red = runChecker(tmp);
    assertRed(red, '(m) red', 'UNRESOLVED .collection() CALL');
    assertRed(red, '(m) red names the expression', 'getSensitiveCollectionName()');
    assertRed(red, '(m) red classifies it as non-literal, not silently residue', 'non-literal expression');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (n) [finding 2b, BLOCKER] string concatenation passed to .collection() --
// same class, same hard-fail-by-default requirement.
// -----------------------------------------------------------------------
run('(n) [finding 2b] string concatenation argument to .collection() -> RED naming the call site', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_n.ts');
    fs.writeFileSync(
      mutFile,
      "export function touch(db: any, prefix: string) {\n  return db.collection(prefix + 'sensitive');\n}\n",
    );

    const red = runChecker(tmp);
    assertRed(red, '(n) red', 'UNRESOLVED .collection() CALL');
    assertRed(red, '(n) red names the expression', "prefix + 'sensitive'");
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (o) [finding 2, positive counterpart] the REAL account_export.ts dynamic
// call sites (sub()'s interpolated template at :64, owned()'s bare
// `collection` param at :100, one()'s bare `path` param at :88) resolve as
// documented, individually AUDITED residue -- not violations -- once
// properly allow-listed with a verified justification. Confirms the
// narrowed (per-site, not per-expression-class) residue policy still lets
// legitimate, already-covered production code through.
// -----------------------------------------------------------------------
run('(o) [finding 2, positive] the REAL account_export.ts dynamic call sites are audited residue, not violations', () => {
  const tmp = buildTempCopy();
  try {
    fs.copyFileSync(REAL_ACCOUNT_EXPORT, path.join(tmp, 'functions/src/account_export.ts'));

    const result = runChecker(tmp);
    assertGreen(result, '(o) real account_export.ts still green once allow-listed');

    delete require.cache[require.resolve(path.join(tmp, 'scripts/ci/check_data_access_policy.js'))];
    const checkerModule = require(path.join(tmp, 'scripts/ci/check_data_access_policy.js'));
    const files = checkerModule.productionFiles();
    assert.ok(files.some((f) => f.includes('account_export.ts')), 'account_export.ts was not scanned as production source');
    const registries = checkerModule.loadRegistries();
    const { residue, violations } = checkerModule.scanProductionCalls(files, registries);
    const accountExportViolations = violations.filter((v) => v.file.includes('account_export.ts'));
    assert.strictEqual(accountExportViolations.length, 0, `expected zero account_export.ts violations, got: ${JSON.stringify(accountExportViolations)}`);
    const residueLines = residue.filter((r) => r.file.includes('account_export.ts')).map((r) => r.line).sort((a, b) => a - b);
    assert.deepStrictEqual(residueLines, [64, 88, 100], `expected account_export.ts residue at lines 64, 88, 100, got: ${JSON.stringify(residueLines)}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (p) [finding 3, BLOCKER] a CONDITIONAL cell's conditionalRef test whose
// REAL assertSucceeds/assertFails calls target a DIFFERENT collection,
// with an unrelated, UNUSED doc() reference to the declared path sitting
// elsewhere in the same test body (not inside either assert call) -- the
// prior remediation's own fix (mutation class (f)) bound the SDK-shape and
// presence checks correctly but never confirmed the PATH match was about
// the SAME assertion; an unrelated doc() reference anywhere in the body
// used to be enough "evidence" for the whole cell.
// -----------------------------------------------------------------------
run('(p) [finding 3] conditionalRef test targets a DIFFERENT collection with an unrelated unused doc() reference elsewhere in the body -> RED', () => {
  const tmp = buildTempCopy();
  try {
    const testFilePath = path.join(tmp, 'functions/src/__rules__/data_access_policy.test.ts');
    const testFileText = fs.readFileSync(testFilePath, 'utf8');
    const fixtureTestName = 'CONDITIONAL cell fixture (finding 3): canary update, unrelated unused profile doc reference';
    const injected = testFileText + '\n\n' +
      `test("${fixtureTestName}", async () => {\n` +
      '  // Unused, unrelated -- sits OUTSIDE both assert calls below. Must\n' +
      '  // NOT count as path evidence for either of them.\n' +
      '  const unusedRef = doc(asAlice(), `users/${ALICE}/profile/main`);\n' +
      '  await seedAsAdmin(`_canary/${CANARY_UID}`, { probe: true });\n' +
      '  await assertSucceeds(updateDoc(doc(asCanary(), `_canary/${CANARY_UID}`), { probe: false }));\n' +
      '  await seedAsAdmin(`_canary/other-canary`, { probe: true });\n' +
      '  await assertFails(updateDoc(doc(asCanary(), `_canary/other-canary`), { probe: false }));\n' +
      '});\n';
    fs.writeFileSync(testFilePath, injected);

    const policy = readPolicy(tmp);
    const original = JSON.parse(JSON.stringify(policy.collections.profile.clientAccess[0].conditionalRefs.update));
    policy.collections.profile.clientAccess[0].conditionalRefs.update.testName = fixtureTestName;
    writePolicy(tmp, policy);

    const red = runChecker(tmp);
    assertRed(red, '(p) red', 'does not actually exercise the declared path');
    assertRed(red, '(p) red names the declared collection', 'users/*/profile');

    policy.collections.profile.clientAccess[0].conditionalRefs.update = original;
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(p) green after pointing back at a real profile-path test');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (q) [finding 4, MAJOR] a locally-shadowed, UNIMPORTED `P2CollectionPaths`
// constant in a file that never imports the real registry does not
// silently resolve via the real registry's own values -- registry
// resolution now requires the base identifier to be genuinely BOUND (same-
// file definition, or a real relative import) to the registered export,
// not merely spelled the same. The positive counterpart (the REAL,
// legitimately-imported P2CollectionPaths.textKeys usage) is already
// covered by (e-positive) above.
// -----------------------------------------------------------------------
run('(q) [finding 4] locally-shadowed, unimported P2CollectionPaths does not silently resolve via the real registry -> RED', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_q.ts');
    fs.writeFileSync(
      mutFile,
      'const P2CollectionPaths = { textKeys: "sensitive_shadow" };\n' +
      "export function touch(db: any) {\n  return db.collection('users').doc('someUid').collection(P2CollectionPaths.textKeys);\n}\n",
    );

    const red = runChecker(tmp);
    assertRed(red, '(q) red', 'UNRESOLVED .collection() CALL');
    assertRed(red, '(q) red names the expression', 'P2CollectionPaths.textKeys');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (r) [finding 5, MAJOR] `.doc(getUid())` -- a NESTED paren inside the
// .doc() argument -- no longer defeats chainedOffDoc detection: a genuine
// per-user subcollection reached this way is correctly recognized as one
// (not misclassified as top-level, which would validate it against the
// wrong -- default-deny -- expected access).
// -----------------------------------------------------------------------
run('(r) [finding 5] .collection().doc(getUid()).collection() with a NESTED-paren doc() argument is still correctly recognized as a per-user subcollection', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_r.ts');
    fs.writeFileSync(
      mutFile,
      "export function touch(db: any) {\n  return db.collection('users').doc(getUid()).collection('sensitive_new_nested');\n}\n",
    );

    const red = runChecker(tmp);
    assertRed(red, '(r) red', 'NO clientAccess DECLARATION for discovered path /users/{uid}/sensitive_new_nested/{docId}');

    // Wrong fix: declaring it at the top-level (mis-derived) path must
    // still fail -- proves the nested-paren argument did not defeat the
    // per-user-subcollection recognition.
    const wrongPolicy = readPolicy(tmp);
    wrongPolicy.collections.sensitive_new_nested = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture (finding 5) -- WRONG (top-level) path, must still fail',
      clientAccess: [{ path: '/sensitive_new_nested/{docId}', access: { read: 'NONE', create: 'NONE', update: 'NONE', delete: 'NONE' } }],
    };
    writePolicy(tmp, wrongPolicy);
    const stillRed = runChecker(tmp);
    assertRed(stillRed, '(r) still red on the wrong (top-level) declaration', 'NO clientAccess DECLARATION for discovered path /users/{uid}/sensitive_new_nested/{docId}');

    const policy = readPolicy(tmp);
    policy.collections.sensitive_new_nested = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture (finding 5)',
      clientAccess: [{ path: '/users/{uid}/sensitive_new_nested/{docId}', access: { read: 'OWNER', create: 'OWNER', update: 'OWNER', delete: 'OWNER' } }],
    };
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(r) green after declaring the correct per-user-subcollection path');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (s) [finding 6, MAJOR, dormant] two distinct top-level match blocks
// sharing a root/leaf segment (`/admin/{adminId}/profile/{docId}` and
// `/admin/{adminId}/audit/{docId}`, both rooted at "admin") are BOTH
// independently discovered (neither silently drops out of the candidate
// set via a leaf-keyed Map collision) AND each declared clientAccess entry
// is validated against its OWN block's rules, not whichever same-leaf
// block a coarse lookup happens to find first.
// -----------------------------------------------------------------------
run('(s) [finding 6] two distinct top-level blocks sharing a leaf/root segment are both independently discovered and validated against their OWN block', () => {
  const tmp = buildTempCopy();
  try {
    const rulesPath = path.join(tmp, 'firestore.rules');
    const rules = fs.readFileSync(rulesPath, 'utf8');
    const injected = rules.replace(
      '    // Equipment + exercise catalogs are read-only for clients.',
      `    match /admin/{adminId}/profile/{docId} {\n` +
      `      allow read, write: if request.auth != null && request.auth.uid == adminId;\n` +
      `    }\n\n` +
      `    match /admin/{adminId}/audit/{docId} {\n` +
      `      allow read: if request.auth != null && request.auth.uid == adminId;\n` +
      `      allow write: if false;\n` +
      `    }\n\n` +
      `    // Equipment + exercise catalogs are read-only for clients.`,
    );
    assert.notStrictEqual(injected, rules, '(s) injection anchor not found');
    fs.writeFileSync(rulesPath, injected);

    // Nothing declared yet -- BOTH must be independently required.
    const red1 = runChecker(tmp);
    assertRed(red1, '(s) red, profile missing', '/admin/{adminId}/profile/{docId}');
    assertRed(red1, '(s) red, audit missing too (not leaf-collapsed away)', '/admin/{adminId}/audit/{docId}');

    // Declare ONLY profile -- audit must STILL be independently required.
    const policyOnlyProfile = readPolicy(tmp);
    policyOnlyProfile.collections.admin_profile_fixture = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture (finding 6)',
      clientAccess: [{
        path: '/admin/{adminId}/profile/{docId}',
        access: { read: 'OWNER', create: 'OWNER', update: 'OWNER', delete: 'OWNER' },
      }],
    };
    writePolicy(tmp, policyOnlyProfile);
    const red2 = runChecker(tmp);
    assertRed(red2, '(s) red, audit still missing after declaring only profile', '/admin/{adminId}/audit/{docId}');

    // Declare audit too, but with profile's OWN access cross-assigned to
    // it (OWNER for write) -- audit's real write is `if false`, so this
    // must fail if (and only if) collectionAccess() resolves audit against
    // its OWN block rather than whichever same-leaf block comes first.
    const policyWrong = readPolicy(tmp);
    policyWrong.collections.admin_audit_fixture = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture (finding 6) -- WRONG (cross-assigned) access, must still fail',
      clientAccess: [{
        path: '/admin/{adminId}/audit/{docId}',
        access: { read: 'OWNER', create: 'OWNER', update: 'OWNER', delete: 'OWNER' },
      }],
    };
    writePolicy(tmp, policyWrong);
    const red3 = runChecker(tmp);
    assertRed(red3, '(s) red, audit declared with WRONG (cross-assigned) access', 'admin_audit_fixture');

    // Correct: audit's real write is an unconditional deny.
    const policyCorrect = readPolicy(tmp);
    policyCorrect.collections.admin_audit_fixture.clientAccess[0].access = {
      read: 'OWNER', create: 'NONE', update: 'NONE', delete: 'NONE',
    };
    writePolicy(tmp, policyCorrect);
    const green = runChecker(tmp);
    assertGreen(green, '(s) green once both blocks are independently, correctly declared');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// =========================================================================
// Remediation round 3 (2026-09-16): GPT-PM implementation review round 2
// (core/DECISION_LOG.md's "Row 24 gate: GPT-PM implementation review round
// 2" entry) found the round-1 fixes for findings 1, 3 and 4 above were only
// PARTIALLY complete -- narrower/deeper versions of the same bugs. Each new
// class below reproduces GPT-PM's OWN adversarial scenario verbatim (not an
// easier nearby case), same RED-then-GREEN discipline, named "BLOCKER 1"/
// "BLOCKER 2"/"MAJOR" to match that decision-log entry's own labels.
// =========================================================================

// -----------------------------------------------------------------------
// (t) [BLOCKER 1, round 3] a FULLY LITERAL db().doc("users/<uid>/<coll>/
// <doc>") path -- no template interpolation anywhere -- is no longer
// silently dropped. Distinct from (l) above, which only ever tested the
// templated `${uid}` case (which already wildcarded to `*` and happened to
// satisfy the OLD, buggy `segs[1] === '*'` gate); a real, literal uid value
// like "alice" is exactly what that old gate rejected. Pre-flight-verified
// against the REAL unfixed round-2 checker (2026-09-16): this exact
// fixture produced a clean exit 0 with zero discovered paths for it -- a
// completely silent miss, not merely a wrong classification.
// -----------------------------------------------------------------------
run('(t) [BLOCKER 1] fully literal db().doc("users/<uid>/<collection>/<doc>") -- no interpolation at all -- is no longer silently dropped', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions/src/__mutation_t.ts');
    fs.writeFileSync(
      mutFile,
      'export function touch() {\n  return db().doc("users/alice/sensitive_new/current");\n}\n',
    );

    const red = runChecker(tmp);
    assertRed(red, '(t) red', 'NO clientAccess DECLARATION for discovered path /users/{uid}/sensitive_new/{docId}');

    const policy = readPolicy(tmp);
    policy.collections.sensitive_new = {
      classification: 'EXEMPT',
      reason: 'mutation-proof fixture (BLOCKER 1, round 3)',
      clientAccess: [{ path: '/users/{uid}/sensitive_new/{docId}', access: { read: 'OWNER', create: 'OWNER', update: 'OWNER', delete: 'OWNER' } }],
    };
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(t) green after declaring');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (u) [BLOCKER 2, round 3] a CONDITIONAL test's assertSucceeds contains a
// real updateDoc() call targeting `_canary`, PLUS a decoy doc() reference
// to the declared collection ("profile") sitting INSIDE THE SAME
// assertSucceeds argument -- but in updateDoc's own PAYLOAD object (its
// SECOND argument), never as the document being updated (updateDoc's FIRST
// argument). Round 2's own fix (mutation class (p) above) only closed the
// "decoy sits OUTSIDE every assert call entirely" gap; it never bound the
// path check to the matched SDK call's OWN document-reference argument, so
// a decoy INSIDE that same SDK call (just not as its own ref argument)
// still passed round 2's checks. GPT-PM's own exact scenario:
// `assertSucceeds(updateDoc(doc(db,'_canary/x'), {ref: doc(db,'users/
// alice/profile/main')}))`.
// -----------------------------------------------------------------------
run("(u) [BLOCKER 2] CONDITIONAL test's real SDK call targets a DIFFERENT collection, with a decoy doc() reference INSIDE the SAME assertSucceeds call's payload argument -> RED", () => {
  const tmp = buildTempCopy();
  try {
    const testFilePath = path.join(tmp, 'functions/src/__rules__/data_access_policy.test.ts');
    const testFileText = fs.readFileSync(testFilePath, 'utf8');
    const fixtureTestName = 'CONDITIONAL cell fixture (BLOCKER 2, round 3): canary update, decoy profile doc() inside the same assertSucceeds payload';
    const injected = testFileText + '\n\n' +
      `test("${fixtureTestName}", async () => {\n` +
      '  await seedAsAdmin(`_canary/${CANARY_UID}`, { probe: true });\n' +
      "  // updateDoc's OWN first (document-reference) argument targets\n" +
      '  // _canary. The decoy doc() call below sits inside the SAME\n' +
      "  // assertSucceeds argument, but as part of updateDoc's SECOND\n" +
      '  // argument (the payload object) -- never as the document being\n' +
      '  // updated. Must still be treated as NOT exercising "profile".\n' +
      '  await assertSucceeds(\n' +
      '    updateDoc(doc(asCanary(), `_canary/${CANARY_UID}`), {\n' +
      '      probe: false,\n' +
      '      decoyRef: doc(asAlice(), `users/${ALICE}/profile/main`),\n' +
      '    }),\n' +
      '  );\n' +
      '  await seedAsAdmin(`_canary/other-canary`, { probe: true });\n' +
      '  await assertFails(updateDoc(doc(asCanary(), `_canary/other-canary`), { probe: false }));\n' +
      '});\n';
    fs.writeFileSync(testFilePath, injected);

    const policy = readPolicy(tmp);
    const original = JSON.parse(JSON.stringify(policy.collections.profile.clientAccess[0].conditionalRefs.update));
    policy.collections.profile.clientAccess[0].conditionalRefs.update.testName = fixtureTestName;
    writePolicy(tmp, policy);

    const red = runChecker(tmp);
    assertRed(red, '(u) red', 'does not actually exercise the declared path');
    assertRed(red, '(u) red names the declared collection', 'users/*/profile');

    policy.collections.profile.clientAccess[0].conditionalRefs.update = original;
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(u) green after pointing back at a real profile-path test');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (v) [MAJOR, round 3] a file that legitimately imports `P2CollectionPaths`
// at the top AND has a FUNCTION-PARAMETER shadow of the same name at the
// actual `.collection(...)` call site -- the genuine, legitimately-bound
// file-level import must no longer be trusted once a closer declaration of
// the identical name exists anywhere in the file.
// -----------------------------------------------------------------------
run('(v) [MAJOR] file-level P2CollectionPaths import shadowed by a function-PARAMETER of the same name at the actual call site -> RED', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions-equipment-identity/src/__mutation_v.ts');
    fs.writeFileSync(
      mutFile,
      'import { P2CollectionPaths } from "./p2/firestore_paths";\n' +
      '\n' +
      '// P2CollectionPaths here is the FUNCTION PARAMETER, not the import --\n' +
      '// a real caller could pass anything for it. The file-level import must\n' +
      '// no longer be trusted for the .collection() call inside this scope.\n' +
      'function handler(db: any, P2CollectionPaths: any) {\n' +
      '  return db.collection("users").doc("someUid").collection(P2CollectionPaths.textKeys);\n' +
      '}\n' +
      'export { handler };\n',
    );

    const red = runChecker(tmp);
    assertRed(red, '(v) red', 'UNRESOLVED .collection() CALL');
    assertRed(red, '(v) red names the expression', 'P2CollectionPaths.textKeys');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (w) [MAJOR, round 3 companion] the same shadow gap, via an INNER-SCOPE
// const re-declaration inside a function body instead of a parameter --
// GPT-PM's own second stated example shape.
// -----------------------------------------------------------------------
run('(w) [MAJOR, companion] file-level P2CollectionPaths import shadowed by an inner-scope CONST re-declaration inside a function body -> RED', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions-equipment-identity/src/__mutation_w.ts');
    fs.writeFileSync(
      mutFile,
      'import { P2CollectionPaths } from "./p2/firestore_paths";\n' +
      '\n' +
      'export function touch(db: any) {\n' +
      '  // Inner-scope shadow -- a totally different object, same name.\n' +
      '  const P2CollectionPaths = { textKeys: "sensitive_shadow_w" };\n' +
      '  return db.collection("users").doc("someUid").collection(P2CollectionPaths.textKeys);\n' +
      '}\n',
    );

    const red = runChecker(tmp);
    assertRed(red, '(w) red', 'UNRESOLVED .collection() CALL');
    assertRed(red, '(w) red names the expression', 'P2CollectionPaths.textKeys');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (v-positive) the REAL, unmodified, legitimately-imported (non-shadowed)
// functions-equipment-identity/src/p2/text_key_index.ts usage of
// `P2CollectionPaths.textKeys` still resolves correctly (stays GREEN) --
// confirms the shadow-detection fix above is not so broad it breaks the
// one genuine production call site it must keep trusting.
// -----------------------------------------------------------------------
run('(v-positive) the REAL text_key_index.ts P2CollectionPaths.textKeys usage still resolves after the shadow-detection fix', () => {
  const tmp = buildTempCopy();
  try {
    fs.copyFileSync(REAL_TEXT_KEY_INDEX, path.join(tmp, 'functions-equipment-identity/src/p2/text_key_index.ts'));

    const result = runChecker(tmp);
    assertGreen(result, '(v-positive) real text_key_index.ts still green');

    delete require.cache[require.resolve(path.join(tmp, 'scripts/ci/check_data_access_policy.js'))];
    const checkerModule = require(path.join(tmp, 'scripts/ci/check_data_access_policy.js'));
    const files = checkerModule.productionFiles();
    assert.ok(files.some((f) => f.includes('text_key_index.ts')), 'text_key_index.ts was not scanned as production source');
    const registries = checkerModule.loadRegistries();
    const { registryHits, violations } = checkerModule.scanProductionCalls(files, registries);
    const textKeyIndexViolations = violations.filter((v) => v.file.includes('text_key_index.ts'));
    assert.strictEqual(textKeyIndexViolations.length, 0, `expected zero text_key_index.ts violations, got: ${JSON.stringify(textKeyIndexViolations)}`);
    assert.ok(
      registryHits.some((h) => h.value === 'equipment_model_text_keys' && h.file.includes('text_key_index.ts')),
      `expected a registryHits entry from text_key_index.ts resolving to equipment_model_text_keys, got: ${JSON.stringify(registryHits)}`,
    );
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// =========================================================================
// Remediation round 4 (2026-09-16): GPT-PM's own terminal ruling on the
// round-cap process question (core/DECISION_LOG.md's "Row 24 gate: GPT-PM
// ruled on the round-cap process question" entry) authorized one final
// round against exactly 2 named findings from round 3's own review -- the
// BLOCKER (analyzeAssertCalls' first-match-anywhere-in-the-argument
// binding) and the MAJOR (destructuring invisible to the shadow detector).
// Four new classes below, same RED-then-GREEN discipline.
// =========================================================================

// -----------------------------------------------------------------------
// (x) [BLOCKER, round 4] a Promise.all([...])-wrapped assertFails,
// containing a real profile-path updateDoc call ALONGSIDE an unrelated
// canary updateDoc call -- the OLD code (searching anywhere within the
// assertion's argument text for a matching call) would have wrongly
// certified this cell via the profile call buried inside the Promise.all,
// even though the actual rejection reason is unknowable from this test
// alone (either call, or both, could be the one that actually rejects).
// The new structural check requires the assertFails argument to ITSELF be
// one supported SDK call, not a Promise.all wrapper -- correctly rejected
// as 'shape', not silently certified.
// -----------------------------------------------------------------------
run('(x) [BLOCKER, round 4] Promise.all([...])-wrapped assertFails for profile/update -> RED (not a direct SDK-call-shaped argument), not wrongly certified via the profile call inside it', () => {
  const tmp = buildTempCopy();
  try {
    const testFilePath = path.join(tmp, 'functions/src/__rules__/data_access_policy.test.ts');
    const testFileText = fs.readFileSync(testFilePath, 'utf8');
    const fixtureTestName = 'CONDITIONAL cell fixture (x, round 4): Promise.all-wrapped assertFails -- old code would wrongly certify via the profile call inside it';
    const injected = testFileText + '\n\n' +
      `test("${fixtureTestName}", async () => {\n` +
      '  await assertSucceeds(updateDoc(doc(asAlice(), `users/${ALICE}/profile/main`), { health: {} }));\n' +
      '  // The real rejection reason is unknowable from this Promise.all alone --\n' +
      '  // either call could be the one that actually rejects. The assertion\n' +
      '  // argument itself is a Promise.all wrapper, not a direct SDK call, so it\n' +
      '  // must never count as evidence for either declared collection.\n' +
      '  await assertFails(\n' +
      '    Promise.all([\n' +
      '      updateDoc(doc(asAlice(), `users/${ALICE}/profile/main`), { health: {} }),\n' +
      '      updateDoc(doc(asCanary(), `_canary/${CANARY_UID}`), { probe: false }),\n' +
      '    ]),\n' +
      '  );\n' +
      '});\n';
    fs.writeFileSync(testFilePath, injected);

    const policy = readPolicy(tmp);
    const original = JSON.parse(JSON.stringify(policy.collections.profile.clientAccess[0].conditionalRefs.update));
    policy.collections.profile.clientAccess[0].conditionalRefs.update.testName = fixtureTestName;
    writePolicy(tmp, policy);

    const red = runChecker(tmp);
    assertRed(red, '(x) red', 'no update-shaped Firestore SDK call');
    assertRed(red, '(x) red names it as a different-operation shape, not silently certified', 'DIFFERENT operation');

    policy.collections.profile.clientAccess[0].conditionalRefs.update = original;
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(x) green after pointing back at a real profile-path test');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (y) [BLOCKER, round 4 companion] an assertFails argument that is a bare
// STRING LITERAL whose text happens to look like a real updateDoc/doc()
// call targeting the declared profile path -- pure regex/text scanning
// (the OLD sdkCallSiteArgTexts-based search, which does not distinguish
// real code from string contents) would match the SDK call name and doc()
// path INSIDE the string text and wrongly certify the cell. The new
// structural check requires the trimmed argument to itself START with the
// SDK call name followed directly by `(` -- a string literal starts with a
// quote character, so it can never match, no separate string-literal
// awareness needed. A decoy also sits in a console.log(...) call entirely
// OUTSIDE both assert calls, to confirm that shape is irrelevant too (never
// scanned at all, since analyzeAssertCalls only looks inside
// assertSucceeds/assertFails argument text in the first place).
// -----------------------------------------------------------------------
run("(y) [BLOCKER, round 4 companion] SDK-call-shaped decoy substring inside a string literal (as the assertFails argument itself, and separately inside an unrelated console.log) -> RED, never mistaken for real evidence", () => {
  const tmp = buildTempCopy();
  try {
    const testFilePath = path.join(tmp, 'functions/src/__rules__/data_access_policy.test.ts');
    const testFileText = fs.readFileSync(testFilePath, 'utf8');
    const fixtureTestName = 'CONDITIONAL cell fixture (y, round 4): SDK-call-shaped decoy substring inside a string literal must not be mistaken for evidence';
    const injected = testFileText + '\n\n' +
      `test("${fixtureTestName}", async () => {\n` +
      '  // Decoy entirely OUTSIDE both assert calls -- never scanned at all.\n' +
      '  console.log("looks like code but is not: updateDoc(doc(db, \'users/x/profile/y\'))");\n' +
      '  await assertSucceeds(updateDoc(doc(asAlice(), `users/${ALICE}/profile/main`), { health: {} }));\n' +
      '  // The assertFails argument ITSELF is a bare string literal whose text\n' +
      '  // is SDK-call-shaped and resolves to the declared path if pure text\n' +
      '  // scanning is applied to it -- but it is not real code.\n' +
      '  await assertFails("updateDoc(doc(db, \'users/alice/profile/main\'))");\n' +
      '});\n';
    fs.writeFileSync(testFilePath, injected);

    const policy = readPolicy(tmp);
    const original = JSON.parse(JSON.stringify(policy.collections.profile.clientAccess[0].conditionalRefs.update));
    policy.collections.profile.clientAccess[0].conditionalRefs.update.testName = fixtureTestName;
    writePolicy(tmp, policy);

    const red = runChecker(tmp);
    assertRed(red, '(y) red', 'no update-shaped Firestore SDK call');

    policy.collections.profile.clientAccess[0].conditionalRefs.update = original;
    writePolicy(tmp, policy);

    const green = runChecker(tmp);
    assertGreen(green, '(y) green after pointing back at a real profile-path test');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (z) [MAJOR, round 4] a file that legitimately imports `P2CollectionPaths`
// at the top AND has an OBJECT-DESTRUCTURING local shadow of the same name
// inside a function body (`const { P2CollectionPaths } = runtimePaths;`) --
// invisible to BOTH the pre-fix plain-declaration regex (destructuring
// isn't `const IDENT`) AND the bare-identifier parameter detector (the real
// use site is `P2CollectionPaths.textKeys`, excluded because it's followed
// by `.`). The pre-fix code would have wrongly trusted the file-level
// import for the call site inside this shadowed scope.
// -----------------------------------------------------------------------
run('(z) [MAJOR, round 4] file-level P2CollectionPaths import shadowed by an object-DESTRUCTURING local binding of the same name -> RED', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions-equipment-identity/src/__mutation_z.ts');
    fs.writeFileSync(
      mutFile,
      'import { P2CollectionPaths } from "./p2/firestore_paths";\n' +
      '\n' +
      'export function touch(db: any, runtimePaths: any) {\n' +
      '  // Destructured local shadow -- a totally different object, same name.\n' +
      '  const { P2CollectionPaths } = runtimePaths;\n' +
      '  return db.collection("users").doc("someUid").collection(P2CollectionPaths.textKeys);\n' +
      '}\n',
    );

    const red = runChecker(tmp);
    assertRed(red, '(z) red', 'UNRESOLVED .collection() CALL');
    assertRed(red, '(z) red names the expression', 'P2CollectionPaths.textKeys');
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

// -----------------------------------------------------------------------
// (z-positive) [round 4 companion] a legitimate file-level P2CollectionPaths
// import, in a file that ALSO destructures a totally DIFFERENT identifier
// name nearby, is not falsely flagged as shadowed -- confirms the new
// destructuring-shape regexes are anchored to the exact registered
// identifier name, not any destructuring pattern anywhere in the file. The
// REAL, unmodified, non-shadowed text_key_index.ts usage is independently
// re-confirmed GREEN by (v-positive) above, which this round 4 run also
// re-executes against the destructuring-extended shadow detector.
// -----------------------------------------------------------------------
run('(z-positive) [round 4 companion] destructuring an UNRELATED identifier near a legitimate P2CollectionPaths import does not falsely flag a shadow', () => {
  const tmp = buildTempCopy();
  try {
    const mutFile = path.join(tmp, 'functions-equipment-identity/src/__mutation_z_positive.ts');
    fs.writeFileSync(
      mutFile,
      'import { P2CollectionPaths } from "./p2/firestore_paths";\n' +
      '\n' +
      'export function touch(db: any, runtimePaths: any) {\n' +
      '  // Destructures a DIFFERENT identifier -- must not be mistaken for a\n' +
      '  // shadow of P2CollectionPaths.\n' +
      '  const { SomeOtherPaths } = runtimePaths;\n' +
      '  return db.collection(P2CollectionPaths.textKeys);\n' +
      '}\n',
    );

    const result = runChecker(tmp);
    assertGreen(result, '(z-positive) unrelated destructuring does not falsely flag the real import as shadowed');

    delete require.cache[require.resolve(path.join(tmp, 'scripts/ci/check_data_access_policy.js'))];
    const checkerModule = require(path.join(tmp, 'scripts/ci/check_data_access_policy.js'));
    const files = checkerModule.productionFiles();
    const registries = checkerModule.loadRegistries();
    const { registryHits, violations } = checkerModule.scanProductionCalls(files, registries);
    const fixtureViolations = violations.filter((v) => v.file.includes('__mutation_z_positive.ts'));
    assert.strictEqual(fixtureViolations.length, 0, `expected zero violations for the unrelated-destructuring fixture, got: ${JSON.stringify(fixtureViolations)}`);
    assert.ok(
      registryHits.some((h) => h.value === 'equipment_model_text_keys' && h.file.includes('__mutation_z_positive.ts')),
      `expected a registryHits entry from the fixture resolving to equipment_model_text_keys, got: ${JSON.stringify(registryHits)}`,
    );
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

if (baselineTmp) fs.rmSync(baselineTmp, { recursive: true, force: true });

if (failures > 0) {
  console.error(`\n${failures} mutation-proof case(s) FAILED.`);
  process.exit(1);
}
console.log('\nAll mutation-proof cases passed (RED on injection, GREEN on the real fix).');
