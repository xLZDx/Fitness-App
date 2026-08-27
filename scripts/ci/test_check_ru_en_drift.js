#!/usr/bin/env node
// MVP1.G3 OBS-1 item 7 [CI] -- self-test for check_ru_en_drift.js's heuristics,
// per the gate's own Definition of Done: a semantically acceptable fixture
// must pass, and an intentionally meaning-corrupted translation that PRESERVES
// Cyrillic script and ICU structure must fail. This is the proof that the
// checker catches meaning drift specifically, not merely "looks different" --
// a naive structural check (key parity, placeholder parity, Cyrillic-presence
// alone) would pass every fixture below, corrupted or not.

const assert = require('assert');
const { evaluatePair } = require('./check_ru_en_drift.js');

function run(name, fn) {
  try {
    fn();
    console.log(`ok - ${name}`);
  } catch (err) {
    console.error(`FAIL - ${name}`);
    console.error(err);
    process.exitCode = 1;
  }
}

// 1. Semantically acceptable: a real-shaped sentence, faithfully translated.
run('acceptable translation produces no flags', () => {
  const en = 'You can cancel your subscription at any time from Settings.';
  const ru = 'Вы можете отменить подписку в любое время в настройках.';
  const flags = evaluatePair(en, ru);
  assert.deepStrictEqual(flags, [], `expected no flags, got: ${flags.join(', ')}`);
});

// 2. Meaning-corrupted via negation inversion, Cyrillic and sentence
// structure both PRESERVED -- exactly the case structural checks (key
// parity, placeholder parity, "is it Cyrillic") cannot see, since none of
// those properties changed. Only a meaning-aware check catches this.
run('negation-inverted translation (same structure, same Cyrillic) fails', () => {
  const en = 'You can cancel your subscription at any time from Settings.';
  const ruCorrupted = 'Вы не можете отменить подписку в любое время в настройках.';
  const flags = evaluatePair(en, ruCorrupted);
  assert.ok(
    flags.includes('negation_polarity_mismatch'),
    `expected negation_polarity_mismatch, got: ${flags.join(', ') || '(none)'}`
  );
});

// 3. Sanity: the two fixtures above differ ONLY by one inserted "не" -- same
// length band, same script, same placeholder set (none). If a future edit to
// the heuristics silently made this pair indistinguishable from case 1, that
// would be exactly the regression this test exists to catch.
run('the corrupted fixture is not caught by accident (isolates the real signal)', () => {
  const en = 'You can cancel your subscription at any time from Settings.';
  const ruClean = 'Вы можете отменить подписку в любое время в настройках.';
  const ruCorrupted = 'Вы не можете отменить подписку в любое время в настройках.';
  assert.deepStrictEqual(evaluatePair(en, ruClean), []);
  assert.ok(evaluatePair(en, ruCorrupted).includes('negation_polarity_mismatch'));
});

// 4. A placeholder dropped in translation -- different failure class
// (placeholder_mismatch), still meaning-changing (the RU string can no
// longer show the value the EN string shows).
run('a dropped ICU placeholder is caught as placeholder_mismatch', () => {
  const en = 'You have {count} workouts left this week.';
  const ru = 'На этой неделе осталось несколько тренировок.'; // "{count}" silently dropped
  const flags = evaluatePair(en, ru);
  assert.ok(
    flags.includes('placeholder_mismatch'),
    `expected placeholder_mismatch, got: ${flags.join(', ') || '(none)'}`
  );
});

if (process.exitCode) {
  console.error('\nSelf-test FAILED.');
  process.exit(1);
} else {
  console.log('\nAll self-tests passed.');
}
