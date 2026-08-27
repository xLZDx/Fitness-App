#!/usr/bin/env node
// MVP1.G3-CI-8 (Data Lifecycle Coverage Drift Guard).
//
// `deleteAccount` can return 200/OK for years while silently forgetting a
// new Firestore collection -- nothing enforces that deletion (or export)
// coverage stays complete as the schema grows. This check makes that
// mechanical: it discovers every Firestore collection actually in use (two
// independent sources, unioned -- see below) and requires each one to carry
// an explicit lifecycle policy classification. A collection with no policy
// entry fails CI; there is no default.
//
// Two discovery sources, unioned by leaf collection name:
//   1. `firestore.rules` -- every `match /path/{var}` block names a
//      collection; the generic per-user wildcard
//      (`/users/{uid}/{coll}/{document=**}`) is recognised and skipped,
//      since it does not name a specific collection.
//   2. Literal `.collection('name')` / `.collection("name")` calls in
//      PRODUCTION source (`functions/src/**/*.ts` and `mobile/lib/**/*.dart`,
//      excluding test directories) -- this is what catches a collection used
//      in code but never given its own rules block (found live while
//      building this checker: `coach_listings` had exactly this gap).
//
// Neither source alone is sufficient: rules do not enumerate the "ordinary"
// per-user subcollections that fall through the generic wildcard
// (workout_logs, programmes, ...), and code alone would miss a
// rules-reserved-but-not-yet-wired namespace (recognised_models and its
// siblings, reserved ahead of a runtime that writes them). The union is
// deliberately not "smart" about the difference -- both are simply merged.

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const RULES_PATH = path.join(REPO_ROOT, 'firestore.rules');
const POLICY_PATH = path.join(REPO_ROOT, 'scripts/ci/data_lifecycle_policy.json');
const FUNCTIONS_SRC = path.join(REPO_ROOT, 'functions/src');
const MOBILE_LIB = path.join(REPO_ROOT, 'mobile/lib');

const VALID_CLASSIFICATIONS = new Set(['DELETE', 'EXPORT', 'BOTH', 'EXEMPT']);

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

// Source 1: firestore.rules `match /path/{var}` blocks.
function collectionsFromRules() {
  const text = fs.readFileSync(RULES_PATH, 'utf8');
  const names = new Set();
  // Non-greedy up to a `{` that is the LAST non-whitespace character on the
  // line (anchored by `$` in multiline mode) -- a path segment's own `{var}`
  // is always followed by more path content on the same line, so this
  // cannot stop early at one of those, only at the rule-body-opening brace.
  const re = /^\s*match\s+(\/.+?)\s*\{\s*$/gm;
  let m;
  while ((m = re.exec(text)) !== null) {
    const segs = m[1].split('/').filter(Boolean);
    if (segs.length < 2) continue; // need at least collection/{doc}
    const collSeg = segs[segs.length - 2];
    if (collSeg.startsWith('{')) continue; // generic wildcard, no literal name
    names.add(collSeg);
  }
  return names;
}

// Source 2: literal `.collection('name')` calls in production source.
function collectionsFromCode() {
  const names = new Set();
  const re = /\.collection\((['"])([a-zA-Z_][a-zA-Z0-9_]*)\1\)/g;
  const files = [
    ...walk(FUNCTIONS_SRC, ['__tests__', '__e2e__', '__rules__']).filter((f) => f.endsWith('.ts')),
    ...walk(MOBILE_LIB, ['test']).filter((f) => f.endsWith('.dart')),
  ];
  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    let m;
    re.lastIndex = 0;
    while ((m = re.exec(text)) !== null) names.add(m[2]);
  }
  return names;
}

function loadPolicy() {
  return JSON.parse(fs.readFileSync(POLICY_PATH, 'utf8'));
}

function main() {
  const fromRules = collectionsFromRules();
  const fromCode = collectionsFromCode();
  const inUse = new Set([...fromRules, ...fromCode]);
  // `users` is the root container, not a distinct data class -- every
  // subcollection under it is separately discovered and classified; the
  // container itself is EXEMPT by construction, not a policy gap.
  inUse.delete('users');

  const policy = loadPolicy();
  const policyNames = new Set(Object.keys(policy.collections));

  const missing = [...inUse].filter((n) => !policyNames.has(n)).sort();
  const malformed = [];
  for (const [name, entry] of Object.entries(policy.collections)) {
    if (!VALID_CLASSIFICATIONS.has(entry.classification)) {
      malformed.push(`${name}: invalid classification "${entry.classification}"`);
    }
    if (!entry.reason || !entry.reason.trim()) {
      malformed.push(`${name}: missing a non-empty reason`);
    }
  }
  const stale = [...policyNames].filter((n) => !inUse.has(n)).sort();

  console.log(
    `Data lifecycle coverage: ${inUse.size} collection(s) in use ` +
    `(${fromRules.size} from firestore.rules, ${fromCode.size} from source), ` +
    `${policyNames.size} classified in policy.`,
  );

  let failed = false;

  if (missing.length > 0) {
    failed = true;
    console.error('\nCollection(s) in use with NO lifecycle policy entry -- classify each as ' +
      'DELETE / EXPORT / BOTH / EXEMPT with a reason in ' +
      'scripts/ci/data_lifecycle_policy.json:');
    for (const name of missing) console.error(`  ${name}`);
  }

  if (malformed.length > 0) {
    failed = true;
    console.error('\nMalformed policy entries:');
    for (const line of malformed) console.error(`  ${line}`);
  }

  if (stale.length > 0) {
    // Not a failure: a policy entry with no current source reference is a
    // hygiene signal (the collection may have been removed from the app),
    // not itself a coverage gap. Printed so it does not go unnoticed.
    console.log('\nPolicy entries with no current code/rules reference (review, not blocking):');
    for (const name of stale) console.log(`  ${name}`);
  }

  if (failed) process.exit(1);
  console.log('OK -- every in-use collection has a lifecycle policy entry.');
}

module.exports = { collectionsFromRules, collectionsFromCode };

if (require.main === module) {
  main();
}
