#!/usr/bin/env node
// MVP1.G3 OBS-1 item 7 [CI]: RU/EN semantic-drift detection.
//
// Key parity between app_en.arb and app_ru.arb is already structurally
// enforced (l10n.yaml's `nullable-getter: false` makes Flutter's own codegen
// fail on a missing key) -- that catches a MISSING translation, not a WRONG
// one. This check is the thing structural parity cannot see: a translation
// that exists, keeps the same ICU placeholders, stays in Cyrillic, and is
// roughly the right length, but says something different from the English --
// a dropped or inverted negation, a swapped number, a truncated sentence.
//
// None of the heuristics below require a translation-quality model or an API
// budget (that class of check belongs to the [RUNTIME] track, which needs an
// owner/budget decision first) -- they are cheap, deterministic, and tuned
// against this project's real corpus rather than invented in the abstract.
//
// Baseline / grandfather mechanism: the check was introduced against ~1200
// pre-existing key pairs that were never reviewed against it. Flagging all of
// them on day one would either block every unrelated PR or force a fake
// mass-review -- so RU_EN_DRIFT_BASELINE.json records today's real flags,
// each with a reason, and an EXPIRY date. Before expiry, only a NEW flag (a
// key not in the baseline, or a baseline key whose flag set grew) fails CI.
// After expiry, the whole baseline fails CI too -- so grandfathering something
// once is not the same as grandfathering it forever, and this can never
// become a permanent "known-red" suppression list.

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const EN_ARB = path.join(REPO_ROOT, 'mobile/lib/l10n/app_en.arb');
const RU_ARB = path.join(REPO_ROOT, 'mobile/lib/l10n/app_ru.arb');
const BASELINE_PATH = path.join(REPO_ROOT, 'scripts/ci/ru_en_drift_baseline.json');

// EN negation markers: word-boundary matched, standard English negation
// vocabulary plus the common contracted forms. `fail(ed/ure)` is included
// deliberately, NOT as a general synonym for negation, but because this
// project's own error-copy idiom translates "X failed" / "Could not X" pairs
// with "Не удалось X" on the RU side every time (confirmed against the real
// corpus below) -- without it, that one recurring idiom alone produced most
// of this heuristic's false positives.
const EN_NEGATION = /\b(not|never|none|nobody|nothing|nowhere|no|cannot|can't|won't|don't|doesn't|didn't|couldn't|shouldn't|wouldn't|hasn't|haven't|hadn't|isn't|aren't|wasn't|weren't|without|neither|nor|fail(?:s|ed|ure)?|unavailable)\b/i;

// RU negation markers, two classes:
// (a) a STANDALONE particle (word boundaries on both sides, using a
//     Cyrillic-aware boundary rather than \b, which does not understand
//     Cyrillic letters) -- "не" as a bound prefix inside an unrelated word
//     (e.g. "неделя", "неон") is not negation and must not match; "не" as its
//     own word before a verb/adjective (e.g. "не работает") is the real,
//     common negation-drop bug this exists to catch.
// (b) a small, explicit list of common LEXICALIZED "не-" adjectives/adverbs
//     that carry genuine negation as a single word with no standalone
//     particle (недоступно = "not available", невозможно = "impossible",
//     недостаточно = "not enough", необратимо = "irreversible") -- found by
//     auditing this project's real corpus, not a general "не-" prefix rule
//     (which would also match unrelated words like "неделя", "необходимо").
const RU_NEGATION_PARTICLE = /(^|[^а-яёА-ЯЁ])(не|нет|нельзя|никогда|ничего|никто|нигде|ни|без)($|[^а-яёА-ЯЁ])/iu;
const RU_NEGATION_LEXICAL = /(недоступ|невозможн|необратим|недостаточн|неверн|неправильн|непонятн|неважн)/iu;
function ruHasNegation(text) {
  return RU_NEGATION_PARTICLE.test(text) || RU_NEGATION_LEXICAL.test(text);
}

// ICU control-structure messages (plural/select) legitimately restructure
// prose per plural category -- RU has four (one/few/many/other) where EN has
// two (one/other), so length, Cyrillic-density and literal-digit comparisons
// across the whole message are comparing different shapes by design, not
// drift. Recognised by the literal ICU syntax this project's .arb files use.
function hasIcuControlStructure(text) {
  return /,\s*(plural|select)\s*,/.test(text);
}

// ICU placeholder identifiers: the leading identifier of every `{ident` token,
// which is well-defined even inside nested plural/select syntax (each nested
// clause still opens with `{identifier,` or a literal `{identifier}`).
const ICU_IDENT = /\{([a-zA-Z][a-zA-Z0-9_]*)[,}]/g;

function icuPlaceholders(text) {
  const out = new Set();
  let m;
  ICU_IDENT.lastIndex = 0;
  while ((m = ICU_IDENT.exec(text)) !== null) out.add(m[1]);
  return out;
}

function setsEqual(a, b) {
  if (a.size !== b.size) return false;
  for (const v of a) if (!b.has(v)) return false;
  return true;
}

// Strips ICU placeholder braces/identifiers so length/Cyrillic/digit checks
// look at the actual prose, not at variable names that happen to be Latin
// letters or digits (e.g. `{count}`, `=1{...}`).
function stripIcu(text) {
  return text.replace(/\{[^{}]*\}/g, ' ').replace(/\{[^{}]*\}/g, ' ');
}

function digitTokens(text) {
  const stripped = stripIcu(text);
  const out = new Set();
  const re = /\d+/g;
  let m;
  while ((m = re.exec(stripped)) !== null) out.add(m[0]);
  return out;
}

function hasCyrillic(text) {
  return /[а-яёА-ЯЁ]/u.test(text);
}

// Returns the list of flags (empty = clean) for one EN/RU string pair.
function evaluatePair(en, ru) {
  const flags = [];

  const enPh = icuPlaceholders(en);
  const ruPh = icuPlaceholders(ru);
  if (!setsEqual(enPh, ruPh)) flags.push('placeholder_mismatch');

  const enNeg = EN_NEGATION.test(en);
  const ruNeg = ruHasNegation(ru);
  if (enNeg !== ruNeg) flags.push('negation_polarity_mismatch');

  // Plural/select messages restructure prose per grammatical category by
  // design (RU has more categories than EN) -- length, Cyrillic-density and
  // literal-digit comparisons across the whole message would be comparing
  // different shapes, not drift, so those three checks are skipped for them.
  if (!hasIcuControlStructure(en) && !hasIcuControlStructure(ru)) {
    const enStripped = stripIcu(en).trim();
    const ruStripped = stripIcu(ru).trim();
    if (enStripped.length >= 12) {
      const ratio = ruStripped.length / Math.max(1, enStripped.length);
      if (ratio < 0.4 || ratio > 2.8) flags.push('length_ratio_outlier');
    }

    if (ruStripped.replace(/[^\p{L}]/gu, '').length > 0 && !hasCyrillic(ruStripped)) {
      flags.push('missing_cyrillic');
    }

    const enDigits = digitTokens(en);
    const ruDigits = digitTokens(ru);
    if (!setsEqual(enDigits, ruDigits)) flags.push('numeric_token_mismatch');
  }

  return flags;
}

function loadArb(file) {
  const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
  const out = {};
  const meta = {};
  for (const [k, v] of Object.entries(raw)) {
    if (k.startsWith('@')) {
      meta[k.slice(1)] = v;
    } else if (typeof v === 'string') {
      out[k] = v;
    }
  }
  return { strings: out, meta };
}

function isExempt(meta) {
  const desc = meta && meta.description;
  return typeof desc === 'string' && /not translated/i.test(desc);
}

function evaluateAll() {
  const en = loadArb(EN_ARB);
  const ru = loadArb(RU_ARB);
  const findings = {};
  for (const key of Object.keys(en.strings)) {
    if (!(key in ru.strings)) continue; // key parity is a separate, already-enforced concern
    if (isExempt(en.meta[key])) continue;
    const flags = evaluatePair(en.strings[key], ru.strings[key]);
    if (flags.length > 0) findings[key] = flags.sort();
  }
  return findings;
}

function loadBaseline() {
  if (!fs.existsSync(BASELINE_PATH)) {
    return { expiry: null, entries: {} };
  }
  return JSON.parse(fs.readFileSync(BASELINE_PATH, 'utf8'));
}

function main() {
  const findings = evaluateAll();
  const baseline = loadBaseline();
  const baselineEntries = baseline.entries || {};

  const newFindings = {};
  for (const [key, flags] of Object.entries(findings)) {
    const grandfathered = baselineEntries[key];
    if (!grandfathered) {
      newFindings[key] = flags;
      continue;
    }
    const grandfatheredFlags = new Set(grandfathered.flags || []);
    const grew = flags.some((f) => !grandfatheredFlags.has(f));
    if (grew) newFindings[key] = flags;
  }

  const today = new Date().toISOString().slice(0, 10);
  const expired = baseline.expiry && today > baseline.expiry;

  const newCount = Object.keys(newFindings).length;
  const totalCount = Object.keys(findings).length;
  const baselineCount = Object.keys(baselineEntries).length;

  console.log(`RU/EN drift check: ${totalCount} key(s) currently flagged, ` +
    `${baselineCount} grandfathered in baseline (expiry ${baseline.expiry || 'none'}), ` +
    `${newCount} NEW/worsened finding(s).`);

  let failed = false;

  if (newCount > 0) {
    failed = true;
    console.error('\nNEW findings not covered by the baseline -- review the translation:');
    for (const [key, flags] of Object.entries(newFindings)) {
      console.error(`  ${key}: ${flags.join(', ')}`);
    }
  }

  if (expired) {
    failed = true;
    console.error(
      `\nBaseline expired on ${baseline.expiry} (today: ${today}). ` +
      'The grandfathered findings below must be reviewed and either fixed ' +
      'or re-baselined with a new expiry -- this check does not carry a ' +
      'permanent "known-red" suppression list:'
    );
    for (const [key, entry] of Object.entries(baselineEntries)) {
      console.error(`  ${key}: ${(entry.flags || []).join(', ')} -- ${entry.reason || '(no reason recorded)'}`);
    }
  }

  if (failed) process.exit(1);
  console.log('OK (no new drift; baseline not expired).');
}

module.exports = { evaluatePair, icuPlaceholders, evaluateAll };

if (require.main === module) {
  main();
}
