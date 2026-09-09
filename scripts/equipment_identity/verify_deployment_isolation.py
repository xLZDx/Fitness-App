# -*- coding: utf-8 -*-
"""P0.G6 -- deployment isolation verification (strategy A: separate Firebase
codebase).

    python scripts/equipment_identity/verify_deployment_isolation.py
    python -m pytest scripts/equipment_identity/test_deployment_isolation.py -q

This module is the REAL build/compile proof behind P0.G6's one acceptance
test: a deliberately-broken `functions-equipment-identity` module must fail
to compile while the default (`functions/`, Stripe-carrying) codebase still
builds clean. Every step here runs a real `npm`/`tsc` subprocess against
real files -- nothing here is a string assertion standing in for an actual
build.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
FIREBASE_JSON = REPO / "firebase.json"
FUNCTIONS_DIR = REPO / "functions"
IDENTITY_DIR = REPO / "functions-equipment-identity"
P0_DIR = REPO / "core" / "equipment_identity" / "p0"

NPM = shutil.which("npm") or "npm"
FIREBASE = shutil.which("firebase") or "firebase"

TARGETED_DEPLOY_COMMANDS = (
    "firebase deploy --only functions:default",
    "firebase deploy --only functions:equipment-identity",
)

_SUBPROCESS_TIMEOUT_S = 300


class IsolationVerificationError(RuntimeError):
    """The isolation strategy is not actually holding -- a config claim or
    a build result contradicts what P0.G6 requires."""


def _run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess:
    # Runtime enforcement, not a style convention: every subprocess call in
    # this module goes through this one function, so refusing "deploy" here
    # makes "this module never performs a real deploy" true regardless of
    # how any call site is later reshaped (a variable, a helper, different
    # quoting) -- a source-text grep for one literal spelling would not
    # survive that kind of refactor; this does.
    if any("deploy" in str(arg) for arg in cmd):
        raise IsolationVerificationError(
            f"refusing to run {cmd!r} -- this module must never perform a real deploy"
        )
    return subprocess.run(
        cmd, cwd=str(cwd), capture_output=True, text=True, shell=False, timeout=_SUBPROCESS_TIMEOUT_S
    )


def verify_firebase_json_codebases() -> dict[str, Any]:
    """Step 1: firebase.json declares exactly the two expected codebases,
    each mapped to the expected source directory."""
    data = json.loads(FIREBASE_JSON.read_text(encoding="utf-8"))
    entries = {e["codebase"]: e for e in data.get("functions", [])}
    if "default" not in entries or entries["default"]["source"] != "functions":
        raise IsolationVerificationError(
            "firebase.json: codebase 'default' must map to source 'functions'"
        )
    if (
        "equipment-identity" not in entries
        or entries["equipment-identity"]["source"] != "functions-equipment-identity"
    ):
        raise IsolationVerificationError(
            "firebase.json: codebase 'equipment-identity' must map to source 'functions-equipment-identity'"
        )
    return {"default": entries["default"], "equipment-identity": entries["equipment-identity"]}


def verify_independent_package_locks() -> None:
    """Step 2: each codebase resolves its own dependency tree -- not a
    shared or duplicated lockfile."""
    default_lock = FUNCTIONS_DIR / "package-lock.json"
    identity_lock = IDENTITY_DIR / "package-lock.json"
    if not default_lock.is_file():
        raise IsolationVerificationError(f"{default_lock} missing")
    if not identity_lock.is_file():
        raise IsolationVerificationError(f"{identity_lock} missing")
    if default_lock.read_bytes() == identity_lock.read_bytes():
        raise IsolationVerificationError(
            "default and identity package-lock.json are byte-identical -- dependency resolution is not independent"
        )


TSC_JS = FUNCTIONS_DIR / "node_modules" / "typescript" / "lib" / "tsc.js"
NODE = shutil.which("node") or "node"

#: The literal that used to be banned outright anywhere under `functions/src`.
IDENTITY_PACKAGE_DIR_NAME = "functions-equipment-identity"


def _canonical(path: Path | str) -> str:
    """The physical, case-normalised path.

    `realpath` matters here and is not defensive tidying: on this Windows
    checkout a junction is a real bypass. Measured while designing this
    module -- a project whose `src/vendor_identity` was an NTFS junction to
    the real identity source compiled 30 identity files, and every one of
    them was REPORTED BY THE COMPILER under the alias path, so a lexical
    test for the package's directory name matched none of them while the
    compiler was reading identity source the whole time.
    """
    return os.path.normcase(os.path.realpath(str(path)))


def _is_within(root: str, candidate: str) -> bool:
    """True containment, not a string prefix.

    `commonpath` compares path COMPONENTS, so a sibling directory whose name
    merely starts with the root's name (`functions-equipment-identity-old`)
    is correctly outside, which `str.startswith` would get wrong.
    """
    if candidate == root:
        return True
    try:
        return os.path.commonpath([root, candidate]) == root
    except ValueError:
        # Different drives (or a mix of absolute and relative): not contained.
        return False


TS_PROBE = Path(__file__).resolve().parent / "ts_dependency_probe.cjs"
TS_MODULE = FUNCTIONS_DIR / "node_modules" / "typescript"


def _ts_probe(mode: str, args: list[str]) -> dict[str, Any]:
    """Ask TypeScript's own parser, via `ts_dependency_probe.cjs`.

    This replaced a hand-written comment stripper plus two regular
    expressions, which GPT-PM's round-1 implementation review showed were
    wrong in BOTH directions -- measured, not argued:

    * `const note = 'do not import "../functions-equipment-identity/src/x"';`
      was REJECTED. Import-shaped words inside an ordinary string matched:
      the same "prose read as code" defect that produced this gate's twelve
      red tests, reintroduced one layer down by the fix for it.
    * `require("../" + "functions-equipment-identity/src/x")` and
      `path.join("..", "functions-equipment-identity", "terms.json")` both
      PASSED. Real couplings, invisible to a pattern looking for one
      contiguous spelling.

    The scanner is gone rather than kept alongside: nothing distinguished it
    from its own absence once the parser answered the same questions, and a
    check no fixture can tell apart from not existing is a claim, not depth.

    Fails closed on a missing probe, a missing compiler, a non-zero exit or
    an `ok:false` payload -- an unread file must never be reported as a clean
    one.
    """
    if not TS_PROBE.is_file():
        raise IsolationVerificationError(f"{TS_PROBE} is missing -- cannot read dependencies")
    if not TS_MODULE.is_dir():
        raise IsolationVerificationError(
            f"{TS_MODULE} is missing -- cannot parse with the compiler this codebase builds with"
        )
    result = _run([NODE, str(TS_PROBE), str(TS_MODULE), mode, *args], FUNCTIONS_DIR)
    if result.returncode != 0:
        raise IsolationVerificationError(
            f"ts_dependency_probe {mode} failed (returncode={result.returncode}): "
            f"{result.stdout[-600:]}{result.stderr[-600:]}"
        )
    try:
        data = json.loads(result.stdout or "{}")
    except json.JSONDecodeError as exc:
        raise IsolationVerificationError(
            f"ts_dependency_probe {mode} produced unparseable output: {exc}"
        ) from exc
    if not data.get("ok"):
        raise IsolationVerificationError(
            f"ts_dependency_probe {mode} reported: {data.get('error')}"
        )
    return data


def _components(value: str) -> list[str]:
    return [part for part in re.split(r"[\\/]+", value)]


def _specifier_names_identity(specifier: str) -> bool:
    """A module specifier that resolves into the identity package.

    Compared by path COMPONENT, so a sibling package whose name merely starts
    with this one's (`functions-equipment-identity-old`) is not a match.
    """
    return IDENTITY_PACKAGE_DIR_NAME in _components(specifier)


def _is_relative_path_into_identity(value: str) -> bool:
    """A constant-folded pathname argument that reaches into the identity
    package -- not a sentence that happens to quote one.

    The probe normalises the value with node's own `path.join`/`path.resolve`
    semantics before it gets here, so `join("scratch", "..", "..", NAME, ...)`
    arrives as `../NAME/...` rather than as its unnormalised spelling. That
    normalisation is not cosmetic: without it a fully constant, correctly
    bound filesystem dependency read as clean, because its first component
    was `scratch`.

    Relative values are judged by COMPONENT -- the first must be `.` or `..`,
    which is what separates a real path from prose quoting one. An absolute
    value is judged by physical containment, the same realpath discipline
    step 3b uses, so an absolute read into the package is caught too.

    A Windows DRIVE-RELATIVE value (`D:..\\x`) is a third shape, and it was
    missed until round 4: `path.win32.join("D:..", NAME, "package.json")` is
    what node really returns for those arguments -- measured, and
    `path.win32.isAbsolute` agrees it is not absolute. It reached neither
    branch above and read as clean. It means "relative to whatever the
    current directory on that drive is", which is not knowable here, so the
    drive prefix is dropped and the remainder judged as the relative path it
    is. `D:<NAME>/x` -- no leading `..` -- stays clean for the same reason a
    bare `<NAME>/x` does: nothing marks it as a path rather than a name.
    """
    normalized = value.replace("\\", "/")
    drive_relative = re.match(r"^[A-Za-z]:(?![\\/])", normalized)
    if drive_relative:
        normalized = normalized[drive_relative.end():]
    parts = _components(normalized)
    if parts and parts[0] in {".", ".."}:
        return IDENTITY_PACKAGE_DIR_NAME in parts[1:]
    if not drive_relative and os.path.isabs(normalized):
        return _is_within(_canonical(IDENTITY_DIR), _canonical(normalized))
    return False


def _spec_components(spec: str) -> list[str]:
    """The path/package components of a `package.json` dependency spec.

    `file:../<NAME>` names the package; `npm:<NAME>-old@1.0.0` names a
    different one. Matching the raw string by substring could not tell them
    apart, and rejected the second -- the same "sibling whose name starts
    with this one's" case `_specifier_names_identity` was already written to
    survive, in the one channel that had not been given the same discipline.
    """
    body = re.sub(r"^[A-Za-z][A-Za-z0-9+.-]*:", "", spec.strip()).replace("\\", "/")
    components: list[str] = []
    for part in body.split("/"):
        if not part:
            continue
        components.append(part)
        #: `<name>@<version>` and a git `#<ref>` are decorations on a
        #: component, not components of their own.
        if not part.startswith("@"):
            components.append(part.split("@", 1)[0])
        components.append(part.split("#", 1)[0])
    return components


def verify_no_cross_import(functions_dir: Path | None = None) -> int:
    """Step 3a: no file under `functions/src` DEPENDS on the identity package.

    Three channels, and this check is explicitly NOT the isolation proof --
    step 3b is. Kept alongside it for one reason that makes it genuinely
    non-redundant: `functions/tsconfig.json` excludes `src/**/__tests__` and
    `src/**/*.test.ts`, so those files are invisible to step 3b's compiler
    graph -- yet `firebase.json`'s default `predeploy` runs `npm test`, so a
    test importing the identity package really would couple this codebase's
    deploy to identity source. That is the fixture that proves this check is
    not subsumed by step 3b.

    What it does NOT do, stated rather than implied: it does not ban the
    package's DIRECTORY NAME. `release_guard.ts` names it in
    `PROVENANCE_RELEVANT_PATHS`, a `git status --porcelain -- <paths>` scope
    list added deliberately (791d221, on a GPT-PM round-5 MAJOR) because
    `firebase deploy --only functions` deploys BOTH codebases, so a dirty
    identity tree must block the release. That string is data: the default
    codebase compiles and runs identically whether or not the directory
    exists. The previous version of this check banned the literal outright
    and so reported a deliberate provenance decision as an isolation
    breach -- a claim far wider than the invariant it was named for.

    Detection is bounded, semantic at the SINK, and the bound is stated
    rather than implied. Module specifiers come from the AST nodes that ARE
    specifiers, and `require` means the bare identifier, never `obj.require`.
    A filesystem path is read only from a real sink: a method on a binding
    this file imported from `fs`, whose constant arguments are folded --
    string literals, substitution-free template literals, `+` concatenation,
    and `path.join`/`path.resolve` ON A BINDING IMPORTED FROM `path`.

    That last qualification is not pedantry. An earlier version accepted any
    property named `.join`/`.resolve`/`.require` and treated every call's
    constant arguments as paths; measured, it rejected
    `console.log("../functions-equipment-identity/...")`,
    `foo.join(...)`, `foo.resolve(...)` and `obj.require(...)` -- data read as
    behaviour, which is this gate's own defect one layer down.

    Two further corrections, each from a measured counterexample rather than
    from review of the code:

    * `fs` bindings are tracked by NAME and ALIAS as well as by namespace.
      `import { readFileSync } from "fs"` was a real dependency this check
      reported clean, because only namespace bindings were collected.
    * Only the argument POSITIONS that are pathnames are read as paths
      (`FS_PATH_ARGUMENTS`). `fs.writeFileSync("out.txt", "<identity path>")`
      was rejected although the second argument is file content. An `fs`
      method not in that table is read conservatively at position 0, node's
      near-universal convention.

    NOT detectable here, named rather than implied: a path assembled at
    runtime from a variable; a filesystem call through an alias this file
    does not bind from `fs`; `require("path").join(...)` inline; and a
    `path.resolve` whose arguments are all relative, whose true target
    depends on the working directory and is emitted as the normalised
    relative form instead. For a file excluded from `functions/tsconfig.json`
    step 3b cannot rescue those misses either, so they are a real residue
    rather than a covered case.

    `functions_dir` exists so the regressions can point this at a scratch
    tree. Writing a fixture .ts into the real `functions/src` would be
    picked up by `release_guard.ts`'s own provenance check -- the check
    would be testing itself by dirtying the thing it protects. Returns the
    number of files scanned, so an empty scan is visibly empty rather than
    silently passing.
    """
    root = functions_dir or FUNCTIONS_DIR
    sources = sorted((root / "src").rglob("*.ts"))
    if sources:
        probed = _ts_probe("specifiers", [str(p) for p in sources])
        for entry in probed["files"]:
            try:
                origin = str(Path(entry["file"]).relative_to(REPO)).replace("\\", "/")
            except ValueError:
                origin = entry["file"]

            for hit in entry["specifiers"]:
                if _specifier_names_identity(hit["value"]):
                    raise IsolationVerificationError(
                        f"{origin}:{hit['line']} imports {hit['value']!r} -- the default "
                        "codebase must not resolve a module from the identity package"
                    )
            for hit in entry["pathLikes"]:
                if _is_relative_path_into_identity(hit["value"]):
                    raise IsolationVerificationError(
                        f"{origin}:{hit['line']} reaches into the identity package by "
                        f"relative path ({hit['value']!r}) -- a runtime filesystem "
                        "dependency the compiler never resolves and step 3b cannot see"
                    )
    scanned = len(sources)
    if scanned == 0:
        # A zero here means nothing was READ, and printing "OK (0 .ts files)"
        # for it is the broken-instrument result this project keeps
        # recording. The docstring already promised an empty scan would be
        # "visibly empty rather than silently passing" -- visible was not the
        # same as refused, which is this gate's own defect in its own text.
        raise IsolationVerificationError(
            f"{root / 'src'} holds no .ts files -- step 3a scanned nothing, and reporting "
            "isolation over a tree nothing read would be a claim, not a result"
        )

    manifest_path = root / "package.json"
    if not manifest_path.is_file():
        raise IsolationVerificationError(
            f"{manifest_path} is missing -- the dependency-declaration channel cannot be "
            "checked, and reporting isolation without it would be a claim, not a result"
        )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for field in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
        for name, spec in (manifest.get(field) or {}).items():
            declares = IDENTITY_PACKAGE_DIR_NAME in _components(name) or (
                IDENTITY_PACKAGE_DIR_NAME in _spec_components(str(spec))
            )
            if declares:
                raise IsolationVerificationError(
                    f"{manifest_path} {field}.{name} = {spec!r} declares a dependency on "
                    "the identity package -- a channel neither the compiler graph nor the "
                    "source scan above would report"
                )
    return scanned


def _tsc(args: list[str], origin: str) -> str:
    """Run the default codebase's OWN TypeScript compiler and return stdout.

    Fails closed: a non-zero exit or empty output raises rather than being
    read as "nothing found", which would turn a broken instrument into a
    clean bill of health.
    """
    if not TSC_JS.is_file():
        raise IsolationVerificationError(
            f"{TSC_JS} is missing -- cannot prove compile isolation without the compiler "
            "the default codebase actually builds with"
        )
    result = _run([NODE, str(TSC_JS), *args], FUNCTIONS_DIR)
    if result.returncode != 0:
        raise IsolationVerificationError(
            f"tsc {' '.join(args)} failed for {origin} (returncode={result.returncode}): "
            f"{result.stdout[-800:]}{result.stderr[-800:]}"
        )
    if not result.stdout.strip():
        raise IsolationVerificationError(
            f"tsc {' '.join(args)} produced no output for {origin} -- refusing to read "
            "silence as isolation"
        )
    return result.stdout


def verify_default_program_excludes_identity(tsconfig: Path | None = None) -> int:
    """Step 3b: the default TypeScript PROGRAM resolves zero identity files.

    This is the compile-isolation proof, and it is a compiler-resolved graph
    assertion rather than a hand-enumerated textual proxy: `--listFilesOnly`
    reports every file the program actually contains, so `include`, path
    aliases and real resolved imports are all covered by one measurement
    instead of by a list of shapes someone thought of.

    Every reported path is canonicalised with `realpath` before the
    containment test -- see `_canonical` for the measured junction bypass
    that makes this non-negotiable.

    What it does NOT cover, so the next check exists: project references.
    `tsc -p <cfg> --listFilesOnly` does not enumerate a referenced project's
    files at all -- measured, not assumed: a project referencing another
    listed only its own sources, zero from the reference.

    Returns the number of program files, so a caller can see the measurement
    was real rather than trusting that it ran.
    """
    cfg = tsconfig or (FUNCTIONS_DIR / "tsconfig.json")
    origin = str(cfg)
    stdout = _tsc(["-p", str(cfg), "--listFilesOnly", "--noEmit"], origin)

    identity_root = _canonical(IDENTITY_DIR)
    listed = [line.strip() for line in stdout.splitlines() if line.strip()]
    offenders = sorted({p for p in listed if _is_within(identity_root, _canonical(p))})
    if offenders:
        raise IsolationVerificationError(
            f"the default TypeScript program built from {origin} resolves "
            f"{len(offenders)} file(s) physically inside {IDENTITY_DIR}, e.g. "
            f"{offenders[0]} -> {os.path.realpath(offenders[0])} -- the default codebase's "
            "compilation depends on identity source"
        )
    return len(listed)


def verify_no_config_inheritance_from_identity(tsconfig: Path | None = None) -> int:
    """Step 3d: no tsconfig this build reads, at any depth, lives in the
    identity package.

    A fourth dependency channel, found by GPT-PM's round-1 implementation
    review and confirmed by measurement here: a config can `extends` a file
    inside the identity package, contributing compiler options but no source
    files. Measured -- a project extending
    `functions-equipment-identity/tsconfig.json` compiled 52 files with ZERO
    inside the identity package, so step 3b passed; it declares no project
    reference, so step 3c passed; and it imports nothing, so step 3a passed.
    The default build nonetheless could not run if that file were deleted.

    `--showConfig` cannot answer this and is deliberately not used for it:
    its output is the RESOLVED options, and the same measurement showed the
    word `extends` absent from that output entirely.

    The chain is not resolved by hand either. A first attempt walked
    `extends` with node's `require.resolve`, and TypeScript disagreed with it
    on a real, valid chain: a config package declaring
    `{"main": "index.js", "tsconfig": "base.json"}` is accepted by tsc, which
    inherits `base.json`, while `require.resolve` follows `main` and lands on
    JavaScript. Measured -- tsc exited 0 and inherited the option while this
    check reported the chain unreadable. An instrument that fails a valid
    build is the same defect class as one that passes an invalid one. So
    TypeScript's own config resolver runs with `readFile` instrumented, and
    the files it consumes ARE the chain; they are then canonicalised with the
    same realpath/containment discipline as step 3b, so an alias cannot hide
    an inherited config either.

    Fails closed on an `extends` target that cannot be resolved: an
    unreadable link in the chain is not proof there is nothing at the end
    of it.
    """
    cfg = tsconfig or (FUNCTIONS_DIR / "tsconfig.json")
    data = _ts_probe("extends", [str(cfg)])

    unresolved = data.get("unresolved") or []
    if unresolved:
        first = unresolved[0]
        raise IsolationVerificationError(
            f"{first['from']} could not resolve its configuration chain: {first['reason']} "
            "-- refusing to report isolation over a config chain this check could not read "
            "to the end"
        )

    identity_root = _canonical(IDENTITY_DIR)
    for inherited in data.get("chain") or []:
        if _is_within(identity_root, _canonical(inherited)):
            raise IsolationVerificationError(
                f"{cfg} inherits configuration from {inherited}, physically inside "
                f"{IDENTITY_DIR} -- the default build reads a file it must not depend on, "
                "and neither the program file list nor the reference walk reports it"
            )
    return len(data.get("chain") or [])


def verify_no_project_reference_to_identity(tsconfig: Path | None = None) -> int:
    """Step 3c: no project reference, at any depth, reaches the identity package.

    Separate from step 3b because `--listFilesOnly` provably does not see
    this channel. The reference graph is read from `tsc --showConfig`, which
    emits the RESOLVED configuration as JSON -- so a tsconfig carrying
    comments or trailing commas is parsed by TypeScript itself rather than by
    a hand-written JSONC reader here.

    Returns the number of projects visited, so an empty graph is visibly an
    empty graph rather than an unrun check.
    """
    start = (tsconfig or (FUNCTIONS_DIR / "tsconfig.json")).resolve()
    identity_root = _canonical(IDENTITY_DIR)

    visited: set[str] = set()
    queue: list[Path] = [start]
    while queue:
        cfg = queue.pop()
        key = _canonical(cfg)
        if key in visited:
            continue
        visited.add(key)

        data = json.loads(_tsc(["-p", str(cfg), "--showConfig"], str(cfg)))
        for reference in data.get("references") or []:
            target = (cfg.parent / str(reference.get("path", ""))).resolve()
            if _is_within(identity_root, _canonical(target)):
                raise IsolationVerificationError(
                    f"{cfg} references project {reference.get('path')!r}, which resolves to "
                    f"{target} inside {IDENTITY_DIR} -- the default codebase's build depends "
                    "on the identity project through a reference the file list never reports"
                )
            nested = target / "tsconfig.json" if target.is_dir() else target
            if nested.is_file():
                queue.append(nested)
    return len(visited)


def build_default(cwd: Path = FUNCTIONS_DIR) -> subprocess.CompletedProcess:
    """Steps 4 and 6b: `npm run build` for the default (Stripe) codebase."""
    return _run([NPM, "run", "build"], cwd)


def build_identity(cwd: Path = IDENTITY_DIR) -> subprocess.CompletedProcess:
    """Step 5 (and, on a temp copy, step 6a): `npm run build` for the
    identity codebase."""
    return _run([NPM, "run", "build"], cwd)


def run_broken_identity_probe() -> dict[str, Any]:
    """Step 6: the core P0.G6 invariant.

    Copies functions-equipment-identity to a disposable temp directory
    (never the tracked source), injects a deterministic TypeScript compile
    error into ONLY that copy, proves the copy fails to build, then --
    while that broken copy still exists on disk -- proves the REAL default
    codebase still builds clean. The tracked working tree is never
    modified; cleanup runs in `finally` even on failure.

    SCOPE, corrected: this proves the scenario it actually executes -- a
    broken identity COPY does not stop the default codebase building. It
    does NOT prove that the real default compiler graph cannot reach the
    real identity tree, because the default build here never touches the
    temp copy: an accidental coupling to the REAL identity source would
    leave this probe entirely green. That property is
    `verify_default_program_excludes_identity` and
    `verify_no_project_reference_to_identity`, steps 3b and 3c. Keeping
    the wider reading of this probe was the same defect as the check it
    sits beside: a claim broader than the thing measured.
    """
    tmp_root = Path(tempfile.mkdtemp(prefix="p0g6_broken_identity_"))
    try:
        temp_identity = tmp_root / "functions-equipment-identity"
        # node_modules is deliberately excluded from the copy, not just
        # skipped-if-present: shutil.copytree does not reliably reproduce
        # npm's own node_modules layout on Windows (nested packages can be
        # linked via NTFS junctions, which copytree does not special-case),
        # which produced a corrupted `typescript` install (tsc.js missing)
        # under the temp copy on a real run -- a false "broken" result for
        # the wrong reason. Always `npm ci` fresh in the temp copy instead.
        shutil.copytree(
            IDENTITY_DIR, temp_identity, ignore=shutil.ignore_patterns(".git", "lib", "node_modules")
        )
        # P1.G1 (§5.14): `npm run build` now runs `check:p0-snapshot` first,
        # which reads core/equipment_identity/p0/functional_type_snapshot_
        # v1.json via a path relative to functions-equipment-identity's own
        # location (REPO_ROOT = two levels up from scripts/). That file is a
        # real, intentional build-time dependency in every actual checkout
        # (functions-equipment-identity never deploys without the rest of
        # the repo present alongside it) -- this probe's temp copy must
        # mirror that same relative layout, or `check:p0-snapshot` fails on
        # a missing file that has nothing to do with the isolation property
        # being tested here. Read-only P0 source, not the tracked file
        # itself -- never modified.
        temp_p0_dir = tmp_root / "core" / "equipment_identity" / "p0"
        temp_p0_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(
            P0_DIR / "functional_type_snapshot_v1.json",
            temp_p0_dir / "functional_type_snapshot_v1.json",
        )
        # P1.G2: `npm run build` also now runs `check:p1-generated`, which
        # reads core/equipment_identity/p0/source_registry.json and every
        # core/equipment_identity/p1/source_captures/*.json fixture, by the
        # exact same relative-path convention as the P1.G1 snapshot check
        # above -- same self-caught-bug class, same fix. Read-only sources,
        # never modified.
        shutil.copy2(
            P0_DIR / "source_registry.json",
            temp_p0_dir / "source_registry.json",
        )
        temp_p1_captures_dir = tmp_root / "core" / "equipment_identity" / "p1" / "source_captures"
        temp_p1_captures_dir.mkdir(parents=True, exist_ok=True)
        p1_captures_dir = REPO / "core" / "equipment_identity" / "p1" / "source_captures"
        for fixture_path in sorted(p1_captures_dir.glob("*.json")):
            shutil.copy2(fixture_path, temp_p1_captures_dir / fixture_path.name)

        install = _run([NPM, "ci"], temp_identity)
        if install.returncode != 0:
            raise IsolationVerificationError(
                f"could not install dependencies into the temp identity copy: {install.stderr}"
            )

        # Differential proof, not a single build: confirm the fresh, unmodified
        # temp copy builds clean BEFORE injecting anything. Found by
        # silent-failure-hunter in the P0.G6 review round -- without this
        # baseline, a build that failed for an unrelated reason (a stale
        # `node_modules` copy, a disk/permissions quirk from `copytree`, a
        # flaky toolchain) would be indistinguishable from the injected error
        # actually working, and the gate would still report PASS.
        baseline_build = build_identity(temp_identity)
        if baseline_build.returncode != 0:
            raise IsolationVerificationError(
                "the temp identity copy failed to build BEFORE any error was injected -- the probe's "
                f"own baseline is broken, not proof of anything: stderr={baseline_build.stderr}"
            )

        broken_file = temp_identity / "src" / "p0" / "cloud_feasibility.ts"
        if not broken_file.is_file():
            raise IsolationVerificationError(f"expected {broken_file} to exist in the temp copy")
        original = broken_file.read_text(encoding="utf-8")
        # A deterministic, unambiguous TS compile error -- an identifier
        # type that doesn't exist, not a syntax typo a formatter could
        # silently "fix" or a linter could tolerate.
        injected_marker = "ThisTypeDoesNotExistAnywhere"
        broken_file.write_text(
            original + f"\nconst __p0g6_deliberately_broken: {injected_marker} = 1;\n",
            encoding="utf-8",
        )

        broken_build = build_identity(temp_identity)
        if broken_build.returncode == 0:
            raise IsolationVerificationError(
                "the deliberately-broken identity copy built successfully -- the injected TS error did not fail the build"
            )
        # The build must have failed for the SPECIFIC reason this probe
        # injected, not for some other, unrelated toolchain failure -- tsc
        # names the offending identifier in its own error output.
        combined_output = broken_build.stdout + broken_build.stderr
        if injected_marker not in combined_output:
            raise IsolationVerificationError(
                "the temp identity copy failed to build, but not for the injected reason -- "
                f"{injected_marker!r} does not appear in its build output: {combined_output!r}"
            )

        # While the broken copy exists on disk (proving the failure above
        # is real, not already cleaned up), the REAL default codebase must
        # still build -- this is the actual isolation proof.
        default_while_broken = build_default()
        if default_while_broken.returncode != 0:
            raise IsolationVerificationError(
                "default codebase build FAILED while a broken identity copy existed -- isolation is violated. "
                f"stderr={default_while_broken.stderr}"
            )

        return {
            "brokenIdentityBuildExpectedFailure": True,
            "brokenIdentityBuildReturnCode": broken_build.returncode,
            "defaultBuildWhileIdentityBroken": True,
            "defaultBuildWhileIdentityBrokenReturnCode": default_while_broken.returncode,
        }
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)
        # Belt-and-suspenders: the broken file only ever existed in
        # tmp_root, never in the tracked IDENTITY_DIR, but assert that
        # explicitly rather than merely relying on never having touched it.
        tracked_file = IDENTITY_DIR / "src" / "p0" / "cloud_feasibility.ts"
        if tracked_file.is_file() and "__p0g6_deliberately_broken" in tracked_file.read_text(encoding="utf-8"):
            raise IsolationVerificationError(
                "the tracked identity source was modified by this probe -- this must never happen"
            )


def firebase_cli_version() -> str:
    """Step 7: record the installed Firebase CLI version as evidence that
    the codebase/targeted-deploy syntax used above is actually supported.
    Never deploys anything."""
    result = _run([FIREBASE, "--version"], REPO)
    if result.returncode != 0:
        raise IsolationVerificationError(f"firebase --version failed: {result.stderr}")
    return result.stdout.strip()


def run_default_tests(cwd: Path = FUNCTIONS_DIR) -> subprocess.CompletedProcess:
    """Step 8: the existing default-codebase (Stripe/account) test suite
    still passes, unmodified by this gate."""
    return _run([NPM, "test"], cwd)


def main() -> int:
    print("1. firebase.json codebases:", verify_firebase_json_codebases())
    verify_independent_package_locks()
    print("2. package-locks independent: OK")
    scanned = verify_no_cross_import()
    print(f"3a. no cross-import from functions/src: OK ({scanned} .ts files)")
    program_files = verify_default_program_excludes_identity()
    print(
        f"3b. default TypeScript program resolves 0 files under the identity package: OK "
        f"({program_files} files in the program)"
    )
    projects = verify_no_project_reference_to_identity()
    print(f"3c. no project reference reaches the identity package: OK ({projects} project(s))")
    inherited = verify_no_config_inheritance_from_identity()
    print(
        f"3d. no tsconfig inheritance reaches the identity package: OK "
        f"({inherited} inherited config(s))"
    )

    default_build = build_default()
    print(f"4. default build: returncode={default_build.returncode}")
    if default_build.returncode != 0:
        raise IsolationVerificationError(f"default build failed: {default_build.stderr}")

    identity_build = build_identity()
    print(f"5. identity build (normal state): returncode={identity_build.returncode}")
    if identity_build.returncode != 0:
        raise IsolationVerificationError(f"identity build failed: {identity_build.stderr}")

    probe = run_broken_identity_probe()
    print("6. broken-identity isolation probe:", probe)

    version = firebase_cli_version()
    print("7. firebase CLI version:", version)
    print("   targeted deploy commands:", TARGETED_DEPLOY_COMMANDS)

    default_tests = run_default_tests()
    print(f"8. default test suite: returncode={default_tests.returncode}")
    if default_tests.returncode != 0:
        raise IsolationVerificationError(f"default test suite failed: {default_tests.stderr}")

    print("production deploy performed: False (never attempted)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
