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


def verify_no_cross_import() -> None:
    """Step 3: no file under functions/src references the identity
    package -- the default codebase cannot import what it must not depend
    on."""
    forbidden = "functions-equipment-identity"
    for path in (FUNCTIONS_DIR / "src").rglob("*.ts"):
        text = path.read_text(encoding="utf-8", errors="ignore")
        if forbidden in text:
            raise IsolationVerificationError(
                f"{path} references {forbidden!r} -- the default codebase must not import the identity package"
            )


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
    verify_no_cross_import()
    print("3. no cross-import from functions/src: OK")

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
