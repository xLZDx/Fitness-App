#!/usr/bin/env node
// S02 remediation A6 -- every Firestore TTL policy this repository relies on must be declared
// as a `fieldOverrides` entry with `ttl: true` in firestore.indexes.json, so it is created when
// the indexes are deployed and is never an undocumented console step.
//
// Usage: node scripts/ci/check_ttl_overrides.js [path/to/firestore.indexes.json]
// Exit code 0 when every required TTL override is present, 1 otherwise (each miss is named).
'use strict';

const fs = require('fs');
const path = require('path');

const DEFAULT_FILE = path.resolve(__dirname, '..', '..', 'firestore.indexes.json');

// collectionGroup + field of every TTL policy that code or the lifecycle policy depends on.
const REQUIRED_TTL_OVERRIDES = [
  { collectionGroup: 'activity_tombstones', fieldPath: 'expireAt' },
  { collectionGroup: 'accountDeletionRetries', fieldPath: 'expireAt' },
  { collectionGroup: 'nutrition_cache', fieldPath: 'expireAt' },
];

function findMissing(indexes, required = REQUIRED_TTL_OVERRIDES) {
  const overrides = Array.isArray(indexes && indexes.fieldOverrides) ? indexes.fieldOverrides : [];
  return required.filter(
    (r) => !overrides.some(
      (o) => o && o.collectionGroup === r.collectionGroup && o.fieldPath === r.fieldPath && o.ttl === true,
    ),
  );
}

function main() {
  const file = process.argv[2] ? path.resolve(process.argv[2]) : DEFAULT_FILE;
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (err) {
    console.error(`FAIL: cannot read ${file}: ${err.message}`);
    process.exit(1);
  }
  const missing = findMissing(parsed);
  if (missing.length === 0) {
    console.log('OK -- every required TTL policy is declared as a fieldOverride with ttl: true.');
    return;
  }
  for (const m of missing) {
    console.error(`MISSING TTL override: collectionGroup ${m.collectionGroup}, field ${m.fieldPath} (ttl: true) in ${file}`);
  }
  process.exit(1);
}

if (require.main === module) main();

module.exports = { REQUIRED_TTL_OVERRIDES, findMissing };
