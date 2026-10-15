# 2026-10-16 S00 deploy guard: node_modules is allowed only through the target's own ignore list

## What changed

- `functions/src/release_guard.ts`:
  - `isAllowedIgnoredEntry` no longer allows any path with a `node_modules` segment unconditionally.
  - `provenanceScope` builds the functions ignore list the way firebase-tools does: the configured `ignore`
    array when the key exists (an explicit `[]` stays empty), otherwise `["node_modules", ".git"]`, and always
    `firebase-debug.log` and `firebase-debug.*.log`.
  - `excludedByTargetIgnore` takes a `matchBase` flag: for functions targets a slash-free pattern also matches a
    path segment at any depth (firebase-tools applies `minimatch` with `matchBase: true, dot: true`). Hosting
    keeps whole-path matching.
- `docs/phase2/split/BACKEND_SEPARATION.md`: rule list rewritten.

## Why

GPT-PM round 3, MAJOR-02B: with `hosting.ignore: []` an ignored `public/node_modules/pkg/index.js` was allowed by
the unconditional rule, but Firebase Hosting uploads it.

## Facts from firebase-tools 15.17.0 source

- Functions (`lib/deploy/functions/prepareFunctionsUpload.js`): `ignore = config.ignore || ["node_modules",
  ".git"]`, then `firebase-debug.log`, `firebase-debug.*.log` and the runtime-config file are appended; files are
  listed by `fsAsync.readdirRecursive` with `minimatch(p, glob, { matchBase: true, dot: true })`. Nothing else is
  excluded: `lib/` and `.env*` are packaged. `lib` is the compiled `main` and the `.env*` files are the functions
  environment, so both are accepted by design.
- Hosting (`lib/listFiles.js`): `glob("**/*", { dot: true, ignore: ["**/firebase-debug.log",
  "**/firebase-debug.*.log", ".firebase/*"].concat(hosting.ignore) })`. No implicit `node_modules` exclusion.

## Allow-list after this change

1. `functions/lib` and `functions-equipment-identity/lib` (and below): allowed by design (build output).
2. Excluded by the target's own ignore list (including node_modules, only via the list).
3. `.env` and `.env.*` directly in a functions source dir: allowed by design (env config; content unverified).

Consequence: with an unreadable `firebase.json` (strict mode, empty ignore lists) an ignored `functions/node_modules`
also blocks. A developer machine normally has a readable `firebase.json`; the real one lists `node_modules` for both
functions codebases and `**/node_modules/**` for hosting, so the usual ignored `functions/node_modules/` stays
allowed.

## Verification state

NOT YET RUN: no test, build, tsc or lint. The test agent must cover: `hosting.ignore: []` plus ignored
`public/node_modules/pkg/index.js` blocks; real-style hosting ignore (`**/node_modules/**`) allows it; functions
config without an `ignore` key allows ignored `functions/node_modules` (default) while `ignore: []` blocks it;
nested `functions/src/node_modules` allowed by basename match when `node_modules` is listed; unreadable
`firebase.json` blocks ignored `functions/node_modules`; `functions/lib` and `.env.*` still allowed; the earlier
ignored-file cases remain as before.
