# 2026-10-16 S00 deploy guard: git-ignored deployable files

## What changed

- `functions/src/release_guard.ts`:
  - `checkSourceProvenance` now runs `git status --porcelain --ignored=matching -- <paths>`. Lines not starting
    with `!!` are uncommitted changes (FAILED as before). Lines starting with `!!` are git-ignored entries and are
    classified; any entry that is not allowed makes the check FAILED with a detail that leads with
    `ignored-deployable-files:` and lists up to 20 offending paths. A failing `git status` stays UNAVAILABLE (blocks).
  - `provenancePaths` became `provenanceScope`: the same path list (fixed list plus `firebase.json`-derived paths,
    unsafe paths still rejected) plus each uploaded directory (hosting `public`, functions `source`) with its own
    `ignore` list. With an unreadable `firebase.json` the fixed directories are used with empty ignore lists.
  - New internal helpers: `globToRegExp`, `excludedByTargetIgnore`, `isAllowedIgnoredEntry`; no new dependency.
- `docs/phase2/split/BACKEND_SEPARATION.md`: provenance scope paragraph.

## Why

GPT-PM round 2, MAJOR-02A: `git status --porcelain` does not report ignored files, but `firebase deploy` uploads
the hosting public dir and the functions source minus only the target's own `ignore` list, so an ignored
`public/app.js` would reach production although it is not in the verified commit.

## Classification rules (ignored entry, repo-relative, trailing `/` stripped)

ALLOW when any of:
1. any path segment is `node_modules`;
2. the path is `functions/lib` or `functions-equipment-identity/lib`, or inside them;
3. the path is inside a hosting public dir or functions source and, relative to that dir, it or any ancestor
   directory matches the target's own `ignore` list from `firebase.json`. Matcher: exact names, `*` (no `/`, does
   not match a leading dot at a segment start), `?`, `**/` prefix, `/**` suffix, `**`; patterns with `[]{}()!+@|\`
   never match;
4. a functions source dir contains it directly as `.env` or `.env.*`.

Everything else, including quoted paths, blocks.

## Known false-positive risks on a developer machine

Ignored files that Firebase would really upload and that therefore block by design: `functions/.runtimeconfig.json`,
`functions/jest_result.json`, `functions/coverage/`, other `*.log` files not covered by the functions ignore list,
`Thumbs.db` or other non-dot files in `public/`. Remove them before deploying. Dot files in `public/` are allowed by
`**/.*`. On the current checkout the only ignored entry in scope is `functions/node_modules/` (allowed).

## Verification state

NOT YET RUN: no test, build, tsc or lint. The test agent follows and must cover: ignored `public/app.js` blocks;
ignored `public/.hidden` allowed by `**/.*`; ignored `node_modules` allowed; ignored `functions/lib` allowed; ignored
`functions/.env.fitness-app-phase2-korostelev` allowed; ignored `functions/src/evil.ts` blocks; ignored
`functions/foo.local` allowed by `*.local`; ignored `firestore.rules` blocks; quoted path blocks; unreadable
`firebase.json` strictness; `git status` failure blocks; a mixed output with a modified file and an ignored file
reports the uncommitted change; the existing provenance tests whose fake stdout is empty or `??` lines; the
existing test that asserts the exact `git status` arguments now sees `--ignored=matching`.
