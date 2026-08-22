# -*- coding: utf-8 -*-
"""P0.G6 tests for scripts/equipment_identity/verify_deployment_isolation.py.

    python -m pytest scripts/equipment_identity/test_deployment_isolation.py -q

These are real build/subprocess tests (npm/tsc), not mocks -- they are
slower than the rest of this project's Python suite by design, because
P0.G6's whole acceptance criterion is that isolation is proven by an actual
compile, not by inspecting config.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_deployment_isolation as vdi  # noqa: E402


def test_firebase_json_declares_both_codebases():
    codebases = vdi.verify_firebase_json_codebases()
    assert codebases["default"]["source"] == "functions"
    assert codebases["equipment-identity"]["source"] == "functions-equipment-identity"


def test_package_locks_are_independent():
    vdi.verify_independent_package_locks()  # must not raise


def test_no_cross_import_from_default_to_identity():
    vdi.verify_no_cross_import()  # must not raise


def test_default_codebase_builds():
    result = vdi.build_default()
    assert result.returncode == 0, result.stderr


def test_identity_codebase_builds_in_normal_state():
    result = vdi.build_identity()
    assert result.returncode == 0, result.stderr


def test_broken_identity_copy_fails_while_default_codebase_still_builds():
    # The core P0.G6 invariant, per the gate contract's own Story AC: "a
    # deliberately-broken identity-module TypeScript error does NOT block a
    # stripeWebhook hotfix deploy."
    tracked_file = vdi.IDENTITY_DIR / "src" / "p0" / "cloud_feasibility.ts"
    before = tracked_file.read_bytes()

    probe = vdi.run_broken_identity_probe()

    assert probe["brokenIdentityBuildExpectedFailure"] is True
    assert probe["brokenIdentityBuildReturnCode"] != 0
    assert probe["defaultBuildWhileIdentityBroken"] is True
    assert probe["defaultBuildWhileIdentityBrokenReturnCode"] == 0

    # No test may leave a broken source file in the working tree -- prove
    # the tracked identity source is byte-identical to what it was before.
    after = tracked_file.read_bytes()
    assert before == after


def test_firebase_cli_supports_codebase_syntax():
    version = vdi.firebase_cli_version()
    assert version
    assert len(vdi.TARGETED_DEPLOY_COMMANDS) == 2
    assert "functions:default" in vdi.TARGETED_DEPLOY_COMMANDS[0]
    assert "functions:equipment-identity" in vdi.TARGETED_DEPLOY_COMMANDS[1]


def test_default_stripe_test_suite_passes():
    result = vdi.run_default_tests()
    assert result.returncode == 0, result.stderr


def test_run_refuses_any_command_containing_deploy():
    # Runtime enforcement, not a source-text grep (found insufficient by
    # silent-failure-hunter in the P0.G6 review round -- a grep for one
    # literal spelling survives any reshaping of the call site). Every
    # subprocess call in this module funnels through _run(), so asserting
    # the refusal lives there proves the property regardless of how a call
    # site is later written.
    with pytest.raises(vdi.IsolationVerificationError, match="deploy"):
        vdi._run(["firebase", "deploy", "--only", "functions:default"], vdi.REPO)
    with pytest.raises(vdi.IsolationVerificationError, match="deploy"):
        vdi._run([vdi.FIREBASE, "deploy"], vdi.REPO)


def test_main_runs_end_to_end_and_exits_zero():
    # silent-failure-hunter's Q3 MAJOR: every individual step function was
    # tested in isolation, but main()'s own sequencing, exit code, and
    # print output were never exercised by any test -- a regression only in
    # main() (wrong step order, a step silently skipped, an exception
    # swallowed instead of propagated) would not have been caught above.
    # Run the script exactly as documented/as CI invokes it, as a real
    # subprocess, so `if __name__ == "__main__"` wiring is covered too.
    result = subprocess.run(
        [sys.executable, str(vdi.__file__)],
        cwd=str(vdi.REPO),
        capture_output=True,
        text=True,
        timeout=600,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    for marker in (
        "1. firebase.json codebases",
        "2. package-locks independent: OK",
        "3. no cross-import from functions/src: OK",
        "4. default build:",
        "5. identity build (normal state):",
        "6. broken-identity isolation probe:",
        "7. firebase CLI version:",
        "8. default test suite:",
        "production deploy performed: False",
    ):
        assert marker in result.stdout, f"missing step marker {marker!r} in main() output"
