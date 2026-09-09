# -*- coding: utf-8 -*-
"""P0.G6 tests for scripts/equipment_identity/verify_deployment_isolation.py.

    python -m pytest scripts/equipment_identity/test_deployment_isolation.py -q

These are real build/subprocess tests (npm/tsc), not mocks -- they are
slower than the rest of this project's Python suite by design, because
P0.G6's whole acceptance criterion is that isolation is proven by an actual
compile, not by inspecting config.
"""
from __future__ import annotations

import json
import os
import subprocess
import time
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
        "3a. no cross-import from functions/src: OK",
        "3b. default TypeScript program resolves 0 files under the identity package: OK",
        "3c. no project reference reaches the identity package: OK",
        "3d. no tsconfig inheritance reaches the identity package: OK",
        "4. default build:",
        "5. identity build (normal state):",
        "6. broken-identity isolation probe:",
        "7. firebase CLI version:",
        "8. default test suite:",
        "production deploy performed: False",
    ):
        assert marker in result.stdout, f"missing step marker {marker!r} in main() output"


# ---------------------------------------------------------------------------
# The isolation checks, proven to BITE.
#
# Every fixture below is built in pytest's tmp_path, outside the repository:
# writing a probe .ts into the real `functions/src` would be picked up by
# `release_guard.ts`'s own provenance check, so the test would dirty the very
# thing it exists to protect.
#
# Each fixture is also proven NON-SUBSUMED: it is rejected for its own
# reason, and the same fixture with only that trigger removed passes. A rule
# no fixture can distinguish from its own absence is a claim, not depth --
# the G3 rights gate measured exactly that over 11,110 strings and deleted
# the guard rather than keeping it.
# ---------------------------------------------------------------------------

IDENTITY_NAME = vdi.IDENTITY_PACKAGE_DIR_NAME


def _scratch_functions(tmp_path: Path, sources: dict, manifest: dict | None = None) -> Path:
    root = tmp_path / "functions"
    (root / "src").mkdir(parents=True, exist_ok=True)
    for rel, content in sources.items():
        target = root / "src" / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")
    (root / "package.json").write_text(
        json.dumps(manifest if manifest is not None else {"name": "scratch"}),
        encoding="utf-8",
    )
    return root


def _relative_identity_import(from_dir: Path, suffix: str = "/src/index") -> str:
    rel = os.path.relpath(vdi.IDENTITY_DIR, from_dir).replace("\\", "/")
    return rel + suffix


# --- step 3a: the three source-level channels ------------------------------

def test_3a_rejects_a_module_specifier_naming_the_identity_package(tmp_path):
    src_dir = tmp_path / "functions" / "src"
    spec = _relative_identity_import(src_dir)
    root = _scratch_functions(tmp_path, {"index.ts": f'import {{ x }} from "{spec}";\n'})
    with pytest.raises(vdi.IsolationVerificationError, match="must not resolve a module"):
        vdi.verify_no_cross_import(root)


def test_3a_rejects_a_relative_traversal_into_the_identity_package(tmp_path):
    # The runtime filesystem coupling the compiler never resolves, so step 3b
    # cannot see it. This is the fixture that keeps rule (b) non-subsumed.
    #
    # The read goes through a binding actually imported from `fs`. An earlier
    # version of this fixture called a bare `readFileSync(...)` with nothing
    # bound, and it stopped being detected the moment the rule became
    # semantic at the sink -- correctly: an unbound identifier is not node's
    # filesystem module, and treating it as one is how `foo.join(...)` came
    # to be reported as a dependency.
    root = _scratch_functions(
        tmp_path,
        {
            "index.ts": (
                'import * as fs from "fs";\n'
                f'const terms = fs.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
            )
        },
    )
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


def test_3a_rejects_a_package_json_dependency_on_the_identity_package(tmp_path):
    # Neither the compiler graph nor the source scan reports this: a declared
    # dependency nothing imports yet is still a dependency `npm ci` installs.
    root = _scratch_functions(
        tmp_path,
        {"index.ts": "export const ok = 1;\n"},
        manifest={"name": "scratch", "dependencies": {"identity": f"file:../{IDENTITY_NAME}"}},
    )
    with pytest.raises(vdi.IsolationVerificationError, match="declares a dependency"):
        vdi.verify_no_cross_import(root)


def test_3a_accepts_the_data_shapes_that_used_to_be_banned_outright(tmp_path):
    # The regression for the failure this gate was opened on. All three of
    # these name the package and none of them depends on it: a doc comment,
    # a `git status` scope entry, and a git-status output fixture in a test.
    # The previous check banned the literal anywhere under functions/src and
    # so reported a deliberate provenance decision as an isolation breach.
    root = _scratch_functions(
        tmp_path,
        {
            "release_guard.ts": (
                "/**\n"
                f" * - `{IDENTITY_NAME}` -- firebase.json's SECOND codebase.\n"
                " */\n"
                "const PROVENANCE_RELEVANT_PATHS = [\n"
                '  "functions",\n'
                f'  "{IDENTITY_NAME}",\n'
                "] as const;\n"
                "export default PROVENANCE_RELEVANT_PATHS;\n"
            ),
            "__tests__/release_guard.test.ts": (
                f'test("provenance FAILS on a dirty {IDENTITY_NAME}/", () => {{\n'
                f'  const stdout = " M {IDENTITY_NAME}/src/index.ts\\n";\n'
                "  expect(stdout).toBeTruthy();\n"
                "});\n"
            ),
        },
    )
    assert vdi.verify_no_cross_import(root) == 2


def test_3a_is_not_subsumed_by_3b_because_tsconfig_excludes_test_files(tmp_path):
    # The reason rule (a) is kept alongside the compiler-graph proof rather
    # than deleted as redundant: `functions/tsconfig.json` excludes
    # `src/**/__tests__`, so an import there is INVISIBLE to step 3b -- yet
    # firebase.json's default predeploy runs `npm test`, so it really would
    # couple this codebase's deploy to identity source.
    root = tmp_path / "functions"
    (root / "src" / "__tests__").mkdir(parents=True)
    (root / "package.json").write_text(json.dumps({"name": "scratch"}), encoding="utf-8")
    (root / "src" / "index.ts").write_text("export const ok = 1;\n", encoding="utf-8")
    spec = _relative_identity_import(root / "src" / "__tests__")
    (root / "src" / "__tests__" / "x.test.ts").write_text(
        f'import {{ x }} from "{spec}";\nexport const y = x;\n', encoding="utf-8"
    )
    (root / "tsconfig.json").write_text(
        json.dumps({
            "compilerOptions": {
                "target": "es2020", "module": "commonjs", "noEmit": True,
                "esModuleInterop": True, "skipLibCheck": True, "resolveJsonModule": True,
            },
            "include": ["src"],
            "exclude": ["src/**/__tests__", "src/**/*.test.ts"],
        }),
        encoding="utf-8",
    )

    # 3b cannot see it...
    assert vdi.verify_default_program_excludes_identity(root / "tsconfig.json") > 0
    # ...and 3a can. That difference is the whole justification for rule (a).
    with pytest.raises(vdi.IsolationVerificationError, match="must not resolve a module"):
        vdi.verify_no_cross_import(root)


# --- step 3b: the compiler-resolved program --------------------------------

def _scratch_tsconfig(tmp_path: Path, includes: list, name: str = "tsconfig.json") -> Path:
    cfg = tmp_path / name
    cfg.write_text(
        json.dumps({
            "compilerOptions": {
                "target": "es2020", "module": "commonjs", "noEmit": True,
                "esModuleInterop": True, "skipLibCheck": True, "resolveJsonModule": True,
            },
            "include": includes,
            "exclude": ["**/__tests__", "**/*.test.ts"],
        }),
        encoding="utf-8",
    )
    return cfg


def test_3b_accepts_the_real_default_program(tmp_path):
    # The control. Without it every rejection below would also be satisfied
    # by a check that simply always raised.
    assert vdi.verify_default_program_excludes_identity() > 100


def test_3b_rejects_a_tsconfig_that_includes_identity_source(tmp_path):
    # No import string exists anywhere in this fixture -- the coupling is
    # made entirely by configuration, which is why a source scan cannot be
    # the isolation proof.
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "index.ts").write_text("export const ok = 1;\n", encoding="utf-8")
    cfg = _scratch_tsconfig(
        tmp_path,
        [str(tmp_path / "src").replace("\\", "/"),
         str(vdi.IDENTITY_DIR / "src").replace("\\", "/")],
    )
    with pytest.raises(vdi.IsolationVerificationError, match="physically inside"):
        vdi.verify_default_program_excludes_identity(cfg)


def _link_directory(link: Path, target: Path) -> None:
    """A junction on Windows, a symlink elsewhere.

    `mklink /J` needs no elevation, which is why this test can actually run
    rather than being skipped -- and a skipped isolation test is not
    evidence of isolation.
    """
    if sys.platform == "win32":
        done = subprocess.run(
            ["cmd", "/c", "mklink", "/J", str(link), str(target)],
            capture_output=True, text=True,
        )
        assert done.returncode == 0, f"mklink /J failed: {done.stdout}{done.stderr}"
    else:
        os.symlink(target, link, target_is_directory=True)


def test_3b_rejects_an_alias_link_into_identity_that_a_substring_test_would_miss(tmp_path):
    # The bypass that makes `realpath` non-negotiable rather than tidy:
    # the compiler reports every one of these files under the ALIAS path, so
    # a lexical test for the package's directory name matches none of them
    # while the compiler is reading identity source the whole time.
    (tmp_path / "src").mkdir()
    _link_directory(tmp_path / "src" / "vendor_identity", vdi.IDENTITY_DIR / "src")
    (tmp_path / "src" / "index.ts").write_text(
        'import * as feas from "./vendor_identity/p0/cloud_feasibility";\n'
        "export const x = feas;\n",
        encoding="utf-8",
    )
    cfg = _scratch_tsconfig(tmp_path, [str(tmp_path / "src").replace("\\", "/")])

    # First: prove the substring test really is blind here, so the assertion
    # below is measuring something rather than restating the obvious.
    listed = vdi._tsc(["-p", str(cfg), "--listFilesOnly", "--noEmit"], str(cfg))
    program_files = [line.strip() for line in listed.splitlines() if line.strip()]
    assert any("vendor_identity" in p for p in program_files), "the alias was not compiled at all"
    assert not any(IDENTITY_NAME in p for p in program_files), (
        "the compiler reported the physical path, so this fixture no longer "
        "demonstrates the alias bypass it exists for"
    )

    with pytest.raises(vdi.IsolationVerificationError, match="physically inside"):
        vdi.verify_default_program_excludes_identity(cfg)


# --- step 3c: project references, which 3b provably cannot see -------------

def test_3c_rejects_a_project_reference_to_identity(tmp_path):
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "index.ts").write_text("export const ok = 1;\n", encoding="utf-8")
    cfg = tmp_path / "tsconfig.json"
    cfg.write_text(
        json.dumps({
            "compilerOptions": {
                "target": "es2020", "module": "commonjs", "noEmit": True,
                "esModuleInterop": True, "skipLibCheck": True,
            },
            "include": [str(tmp_path / "src").replace("\\", "/")],
            "references": [{"path": str(vdi.IDENTITY_DIR).replace("\\", "/")}],
        }),
        encoding="utf-8",
    )
    with pytest.raises(vdi.IsolationVerificationError, match="references project"):
        vdi.verify_no_project_reference_to_identity(cfg)


def test_3b_does_not_enumerate_a_referenced_projects_files(tmp_path):
    """The measured fact that makes step 3c necessary rather than decorative.

    An earlier version of this proved it by pointing a reference at the real
    identity package and asserting step 3b returned a count. It never
    returned one: tsc exits 1 with TS6306 because that project is not
    `composite: true`, so the reference cannot build at all. Concluding "3b
    cannot see it" from THAT failure would have been a conclusion drawn from
    the wrong error -- the same defect as a mutant counted killed because an
    unrelated exception turned the suite red. So the general property is
    measured on a reference that can actually be built.
    """
    dep = tmp_path / "dep"
    (dep / "src").mkdir(parents=True)
    (dep / "src" / "index.ts").write_text("export const depValue = 41;\n", encoding="utf-8")
    (dep / "tsconfig.json").write_text(
        json.dumps({
            "compilerOptions": {
                "composite": True, "declaration": True, "outDir": "lib",
                "target": "es2020", "module": "commonjs",
            },
            "include": ["src"],
        }),
        encoding="utf-8",
    )

    main = tmp_path / "main"
    (main / "src").mkdir(parents=True)
    (main / "src" / "index.ts").write_text("export const mainValue = 1;\n", encoding="utf-8")
    cfg = main / "tsconfig.json"
    cfg.write_text(
        json.dumps({
            "compilerOptions": {"target": "es2020", "module": "commonjs", "noEmit": True},
            "include": ["src"],
            "references": [{"path": "../dep"}],
        }),
        encoding="utf-8",
    )

    listed = vdi._tsc(["-p", str(cfg), "--listFilesOnly", "--noEmit"], str(cfg))
    program_files = [line.strip() for line in listed.splitlines() if line.strip()]
    assert any(str(main / "src" / "index.ts").replace("\\", "/") in p for p in program_files)
    assert not any("dep" + "/src/index.ts" in p.replace("\\", "/") for p in program_files), (
        "tsc --listFilesOnly now enumerates referenced projects; step 3c's "
        "justification has changed and must be re-derived, not assumed"
    )


def test_3c_accepts_the_real_default_project(tmp_path):
    assert vdi.verify_no_project_reference_to_identity() == 1


# --- the instruments themselves --------------------------------------------

def test_tsc_wrapper_refuses_to_read_silence_as_isolation(tmp_path):
    # Fail closed. A compiler that cannot run must not be reported as a
    # compiler that found nothing -- that is a broken instrument imitating
    # the result it was asked for.
    empty = _scratch_tsconfig(tmp_path, [str(tmp_path / "nothing-here").replace("\\", "/")])
    with pytest.raises(vdi.IsolationVerificationError):
        vdi.verify_default_program_excludes_identity(empty)


def test_path_containment_is_not_a_string_prefix():
    # `functions-equipment-identity-old` starts with the identity root's name
    # and is a different directory. `commonpath` compares components; a
    # `startswith` test would call this contained.
    root = vdi._canonical(vdi.IDENTITY_DIR)
    sibling = os.path.normcase(str(vdi.IDENTITY_DIR) + "-old" + os.sep + "src" + os.sep + "x.ts")
    assert not vdi._is_within(root, sibling)
    inside = vdi._canonical(vdi.IDENTITY_DIR / "src" / "index.ts")
    assert vdi._is_within(root, inside)


# ---------------------------------------------------------------------------
# Round-1 implementation review: the parser replaces the pattern, and `extends`
# becomes a fourth channel. Both were measured before being accepted, and both
# were real -- in the first case a defect I had introduced myself while fixing
# the same defect one layer up.
# ---------------------------------------------------------------------------

def test_3a_does_not_read_import_shaped_prose_as_an_import(tmp_path):
    # The regression that matters most here: the pattern-based version
    # REJECTED this file. Import-shaped words inside an ordinary string are
    # still just words, and reading them as a dependency is the same defect
    # that produced this gate's twelve red tests.
    root = _scratch_functions(
        tmp_path,
        {
            "note.ts": (
                f"const note = 'do not import \"../{IDENTITY_NAME}/src/x\"';\n"
                "export default note;\n"
            ),
            "__tests__/titles.test.ts": (
                f'test("provenance FAILS on a dirty {IDENTITY_NAME}/", () => {{\n'
                f'  expect(" M {IDENTITY_NAME}/src/index.ts").toBeTruthy();\n'
                "});\n"
            ),
        },
    )
    assert vdi.verify_no_cross_import(root) == 2


_FS_PATH_IMPORTS_ESM = 'import * as fs from "fs";\nimport * as p from "path";\n'
_FS_PATH_IMPORTS_CJS = 'const fs = require("fs");\nconst p = require("path");\n'
_FS_NAMED_IMPORTS = 'import * as fs from "fs";\nimport { join } from "path";\n'


@pytest.mark.parametrize(
    "source, shape",
    [
        (f'const mod = require("../" + "{IDENTITY_NAME}/src/x");', "concatenated specifier"),
        (f'const mod = require(`../{IDENTITY_NAME}/src/x`);', "template-literal specifier"),
        (
            _FS_PATH_IMPORTS_ESM
            + f'const t = fs.readFileSync(p.join("..", "{IDENTITY_NAME}", "terms.json"));',
            "fs sink over path.join",
        ),
        (
            _FS_PATH_IMPORTS_CJS
            + f'const t = fs.readFileSync(p.resolve("..", "{IDENTITY_NAME}", "terms.json"));',
            "fs sink over path.resolve, required",
        ),
        (
            _FS_NAMED_IMPORTS
            + f'const t = fs.readFileSync(join("..", "{IDENTITY_NAME}", "terms.json"));',
            "fs sink over a destructured join",
        ),
        (
            'import * as fs from "fs";\n'
            + f'const t = fs.promises.readFile("../{IDENTITY_NAME}/terms.json");',
            "nested fs sink",
        ),
    ],
    ids=["concat", "template", "join", "resolve-cjs", "named-join", "fs-promises"],
)
def test_3a_rejects_a_computed_identity_path_in_an_excluded_test(tmp_path, source, shape):
    # Two things at once, deliberately. The path is COMPUTED, so no single
    # literal spells it -- the pattern-based version passed every one of
    # these. And it lives in `__tests__`, which `functions/tsconfig.json`
    # excludes, so step 3b cannot rescue the miss; `npm test` in predeploy
    # runs it all the same.
    #
    # Each case goes through a REAL sink rather than a bare `path.join(...)`
    # assigned to a variable: a call is only a filesystem dependency when
    # something actually consumes the path, and demanding that is what stops
    # the check treating any object with a `.join()` method as node's `path`.
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source + "\n"})
    # Pinned to the declared reason. Without `match=` this passed on any
    # IsolationVerificationError at all -- a missing manifest, an unparseable
    # file -- which is the "killed by the wrong exception" result this gate
    # already recorded once.
    with pytest.raises(vdi.IsolationVerificationError, match="must not resolve a module|relative path"):
        vdi.verify_no_cross_import(root)


@pytest.mark.parametrize(
    "source, shape",
    [
        (f'console.log("../{IDENTITY_NAME}/src/x");', "a path string merely logged"),
        (f'const p = foo.join("..", "{IDENTITY_NAME}", "terms.json");', "some other object's join"),
        (f'const p = foo.resolve("..", "{IDENTITY_NAME}", "x");', "some other object's resolve"),
        (f'const m = obj.require("../{IDENTITY_NAME}/src/x");', "some other object's require"),
        (
            'import * as p from "path";\n'
            + f'const shown = p.join("..", "{IDENTITY_NAME}", "x");\nconsole.log(shown);',
            "a real path.join whose value is only displayed",
        ),
    ],
    ids=["console", "foo-join", "foo-resolve", "obj-require", "join-only-displayed"],
)
def test_3a_does_not_read_data_or_a_foreign_method_as_a_dependency(tmp_path, source, shape):
    # The controls that keep the rule honest in the other direction. An
    # earlier AST version was semantic at the syntax node but not at the
    # SINK: it accepted any property named `.join`/`.resolve`/`.require` and
    # treated every call's constant arguments as filesystem paths, so all
    # five of these were reported as identity dependencies. Data read as
    # behaviour -- this gate's own defect, one layer further down.
    root = _scratch_functions(tmp_path, {"probe.ts": source + "\n"})
    assert vdi.verify_no_cross_import(root) == 1


def test_3a_fails_closed_when_the_parser_cannot_run(tmp_path, monkeypatch):
    # A probe that cannot run must not be reported as a probe that found
    # nothing. This project has already written down what a broken instrument
    # imitating the wanted result costs.
    root = _scratch_functions(tmp_path, {"index.ts": "export const ok = 1;\n"})
    monkeypatch.setattr(vdi, "TS_MODULE", tmp_path / "no-typescript-here")
    with pytest.raises(vdi.IsolationVerificationError, match="cannot parse"):
        vdi.verify_no_cross_import(root)


# --- step 3d: configuration inheritance ------------------------------------

def _config(directory: Path, payload: dict, name: str = "tsconfig.json") -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / name
    target.write_text(json.dumps(payload), encoding="utf-8")
    return target


def test_3d_accepts_the_real_default_project():
    # Control. The real config inherits nothing.
    assert vdi.verify_no_config_inheritance_from_identity() == 0


def test_3d_rejects_a_direct_extends_into_identity(tmp_path):
    # Measured before this check existed: this exact fixture passed 3a, 3b
    # AND 3c -- 52 program files, none inside the identity package, no
    # project reference, no import -- while the default build could not run
    # without a file in the identity tree.
    cfg = _config(tmp_path / "proj", {
        "extends": str(vdi.IDENTITY_DIR / "tsconfig.json").replace("\\", "/"),
        "compilerOptions": {"noEmit": True},
        "include": ["src"],
    })
    with pytest.raises(vdi.IsolationVerificationError, match="inherits configuration"):
        vdi.verify_no_config_inheritance_from_identity(cfg)


def test_3d_rejects_an_alias_link_to_an_identity_config(tmp_path):
    # Same alias bypass as step 3b's, applied to the inheritance channel: the
    # config path names no identity directory anywhere in its spelling.
    link = tmp_path / "vendor_cfg"
    _link_directory(link, vdi.IDENTITY_DIR)
    cfg = _config(tmp_path / "proj", {
        "extends": str(link / "tsconfig.json").replace("\\", "/"),
        "compilerOptions": {"noEmit": True},
    })
    assert IDENTITY_NAME not in cfg.read_text(encoding="utf-8"), (
        "the fixture must not name the package, or it would not test the alias at all"
    )
    with pytest.raises(vdi.IsolationVerificationError, match="inherits configuration"):
        vdi.verify_no_config_inheritance_from_identity(cfg)


def test_3d_rejects_a_transitive_extends_through_a_neutral_config(tmp_path):
    middle = _config(tmp_path / "middle", {
        "extends": str(vdi.IDENTITY_DIR / "tsconfig.json").replace("\\", "/"),
        "compilerOptions": {"strict": True},
    }, name="base.json")
    cfg = _config(tmp_path / "proj", {
        "extends": str(middle).replace("\\", "/"),
        "compilerOptions": {"noEmit": True},
    })
    with pytest.raises(vdi.IsolationVerificationError, match="inherits configuration"):
        vdi.verify_no_config_inheritance_from_identity(cfg)


def test_3d_accepts_an_ordinary_non_identity_base_config(tmp_path):
    # The control that stops every rejection above from also being satisfied
    # by a check that simply always raised.
    base = _config(tmp_path / "shared", {"compilerOptions": {"strict": True}}, name="base.json")
    cfg = _config(tmp_path / "proj", {
        "extends": str(base).replace("\\", "/"),
        "compilerOptions": {"noEmit": True},
    })
    assert vdi.verify_no_config_inheritance_from_identity(cfg) == 1


def test_3d_agrees_with_tsc_on_a_config_package_that_declares_a_tsconfig_field(tmp_path):
    """A valid chain must not be reported as a broken one.

    Measured against a hand-rolled `require.resolve` walk: a package
    declaring `{"main": "index.js", "tsconfig": "base.json"}` is accepted by
    tsc, which inherits `base.json` -- while node resolution follows `main`
    and lands on JavaScript, and the check then called the chain unreadable.
    An instrument that fails a valid build is the same defect class as one
    that passes an invalid build, so TypeScript's own resolver decides.
    """
    package = tmp_path / "node_modules" / "myconfig"
    package.mkdir(parents=True)
    (package / "package.json").write_text(
        json.dumps({"name": "myconfig", "main": "index.js", "tsconfig": "base.json"}),
        encoding="utf-8",
    )
    (package / "index.js").write_text("module.exports = {};\n", encoding="utf-8")
    (package / "base.json").write_text(
        json.dumps({"compilerOptions": {"strict": True}}), encoding="utf-8"
    )

    project = tmp_path / "proj"
    (project / "src").mkdir(parents=True)
    (project / "src" / "index.ts").write_text("export const ok = 1;\n", encoding="utf-8")
    cfg = _config(project, {
        "extends": "myconfig",
        "compilerOptions": {"noEmit": True},
        "include": ["src"],
    })

    # First prove tsc really does accept it, so this test measures a
    # disagreement rather than asserting one.
    shown = subprocess.run(
        [vdi.NODE, str(vdi.TSC_JS), "-p", str(cfg), "--showConfig"],
        capture_output=True, text=True, cwd=str(vdi.FUNCTIONS_DIR),
    )
    assert shown.returncode == 0, shown.stdout + shown.stderr
    assert '"strict": true' in shown.stdout, "the fixture does not actually inherit anything"

    # ...and that step 3d follows the same chain instead of failing closed.
    assert vdi.verify_no_config_inheritance_from_identity(cfg) >= 1


def test_3d_fails_closed_on_an_unresolvable_extends(tmp_path):
    cfg = _config(tmp_path / "proj", {"extends": "./nowhere.json"})
    with pytest.raises(vdi.IsolationVerificationError, match="could not resolve its config"):
        vdi.verify_no_config_inheritance_from_identity(cfg)


def test_3d_survives_a_cycle_rather_than_hanging(tmp_path):
    """A cycle must TERMINATE and then REFUSE -- not terminate and pass.

    This test asserted `>= 1` until round 4: it proved the check does not
    hang, and then accepted a RESULT over a chain TypeScript had explicitly
    refused to resolve. Measured, on the version it was written against: the
    probe returned `ok:true, unresolved:[]` for this fixture and step 3d
    printed OK, because only diagnostics 5083/6053 counted as unresolved and
    circularity is 18000. The assertion was green for the wrong reason -- it
    encoded the very "unread link read as no link" the surrounding code
    exists to prevent.
    """
    a = tmp_path / "a"
    b = tmp_path / "b"
    a.mkdir(); b.mkdir()
    _config(a, {"extends": str(b / "tsconfig.json").replace("\\", "/")})
    _config(b, {"extends": str(a / "tsconfig.json").replace("\\", "/")})
    started = time.monotonic()
    with pytest.raises(vdi.IsolationVerificationError, match="could not resolve its configuration chain"):
        vdi.verify_no_config_inheritance_from_identity(a / "tsconfig.json")
    # The original point of the test, kept: it refuses promptly rather than
    # walking the cycle forever.
    assert time.monotonic() - started < 60


def test_3d_refuses_a_config_whose_extends_is_not_a_path(tmp_path):
    # The second measured case behind the same fix. `"extends": 42` is a
    # config TypeScript cannot follow (diagnostic 5024); reporting "0
    # inherited configs: OK" for it says the chain was read and found empty.
    cfg = _config(tmp_path / "bad", {"extends": 42})
    with pytest.raises(vdi.IsolationVerificationError, match="could not resolve its configuration chain"):
        vdi.verify_no_config_inheritance_from_identity(cfg)


def test_3a_refuses_a_tree_with_nothing_to_scan(tmp_path):
    # A zero that means "nothing was read" printed as "OK (0 .ts files)" is
    # the broken-instrument result, not a clean one. Both shapes: an empty
    # src/, and no src/ at all.
    empty = tmp_path / "empty" / "functions"
    (empty / "src").mkdir(parents=True)
    (empty / "package.json").write_text(json.dumps({"name": "scratch"}), encoding="utf-8")
    with pytest.raises(vdi.IsolationVerificationError, match="scanned nothing"):
        vdi.verify_no_cross_import(empty)

    missing = tmp_path / "missing" / "functions"
    missing.mkdir(parents=True)
    (missing / "package.json").write_text(json.dumps({"name": "scratch"}), encoding="utf-8")
    with pytest.raises(vdi.IsolationVerificationError, match="scanned nothing"):
        vdi.verify_no_cross_import(missing)


# ---------------------------------------------------------------------------
# Round-3 implementation review. The sink model was semantic about WHICH
# object, but not yet about which BINDING or which ARGUMENT -- and it folded
# `path.join` as string concatenation rather than as a path. Each case below
# is one of GPT-PM's counterexamples, measured against the submitted code
# before the fix: three real dependencies reported clean, one piece of data
# reported as a dependency.
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "source, shape",
    [
        (
            'import { readFileSync } from "fs";\n'
            f'const t = readFileSync("../{IDENTITY_NAME}/terms.json");',
            "named ESM import",
        ),
        (
            'const { readFileSync } = require("fs");\n'
            f'const t = readFileSync("../{IDENTITY_NAME}/terms.json");',
            "destructured CJS require",
        ),
        (
            'import { readFileSync as read } from "fs";\n'
            f'const t = read("../{IDENTITY_NAME}/terms.json");',
            "aliased named import",
        ),
        (
            'const { readFileSync: read } = require("fs");\n'
            f'const t = read("../{IDENTITY_NAME}/terms.json");',
            "renamed CJS destructuring",
        ),
    ],
    ids=["named-esm", "destructured-cjs", "aliased-esm", "renamed-cjs"],
)
def test_3a_rejects_an_fs_sink_reached_through_a_named_or_aliased_binding(tmp_path, source, shape):
    # Only NAMESPACE bindings were collected, so every one of these read as
    # clean while being a real filesystem dependency -- and in an excluded
    # test file, step 3b cannot rescue that.
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source + "\n"})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


@pytest.mark.parametrize(
    "source, shape",
    [
        (
            'import * as fs from "fs";\n'
            f'fs.writeFileSync("output.txt", "../{IDENTITY_NAME}/src/x");',
            "identity-shaped string as file CONTENT",
        ),
        (
            'import { writeFileSync } from "fs";\n'
            f'writeFileSync("output.txt", "../{IDENTITY_NAME}/src/x");',
            "same, through a named binding",
        ),
    ],
    ids=["namespace-content", "named-content"],
)
def test_3a_does_not_read_file_content_as_a_pathname(tmp_path, source, shape):
    # `writeFileSync(path, content)` has one of each. Treating every constant
    # argument of every `fs` method as a path made an identity-shaped string
    # a dependency -- data read as behaviour, the defect this whole gate is
    # about, and the reason the check now knows which POSITIONS are paths.
    root = _scratch_functions(tmp_path, {"probe.ts": source + "\n"})
    assert vdi.verify_no_cross_import(root) == 1


def test_3a_folds_path_join_with_node_semantics_not_concatenation(tmp_path):
    """Cancelling components must resolve the way node resolves them.

    `path.join("scratch", "..", "..", NAME, "terms.json")` is
    `../<NAME>/terms.json` -- node's own answer, verified in this test rather
    than assumed. Concatenating the parts with "/" leaves `scratch/../../…`,
    whose first component is `scratch`, so the containment predicate returned
    False and a fully constant, correctly bound filesystem dependency read as
    clean. This is not one of the declared residues: constant
    `path.join`/`path.resolve` is claimed as covered, so it has to be.
    """
    joined = subprocess.run(
        [
            vdi.NODE,
            "-e",
            "const p=require('path');"
            f"process.stdout.write(p.join('scratch','..','..','{IDENTITY_NAME}','terms.json'))",
        ],
        capture_output=True, text=True,
    )
    assert joined.returncode == 0, joined.stderr
    # Measure node's answer instead of asserting a spelling of it.
    resolved = joined.stdout.replace("\\", "/")
    assert resolved.startswith("../"), resolved
    assert IDENTITY_NAME in resolved.split("/"), resolved

    source = (
        'import * as fs from "fs";\n'
        'import * as p from "path";\n'
        f'const t = fs.readFileSync(p.join("scratch", "..", "..", "{IDENTITY_NAME}", "terms.json"));\n'
    )
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


def test_3a_does_not_reject_a_join_that_cancels_back_out_of_identity(tmp_path):
    # The control in the other direction: normalisation must be real, not a
    # rule that treats any mention of the name as a hit. This path walks into
    # a sibling and back out, and never reaches the package.
    source = (
        'import * as fs from "fs";\n'
        'import * as p from "path";\n'
        f'const t = fs.readFileSync(p.join("..", "{IDENTITY_NAME}", "..", "elsewhere", "t.json"));\n'
    )
    root = _scratch_functions(tmp_path, {"probe.ts": source})
    assert vdi.verify_no_cross_import(root) == 1


def test_3a_rejects_an_absolute_read_into_the_identity_package(tmp_path):
    # A constant absolute pathname is judged by physical containment, the
    # same realpath discipline step 3b uses -- a relative-only rule would
    # have missed it entirely.
    target = str(vdi.IDENTITY_DIR / "package.json").replace("\\", "/")
    source = 'import * as fs from "fs";\n' + f'const t = fs.readFileSync("{target}");\n'
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


# ---------------------------------------------------------------------------
# Round-4 implementation review. The sink model knew which OBJECT and which
# ARGUMENT, but resolved a name against a file-global set rather than against
# the declaration in scope -- so a parameter called `fs` was node's `fs`, and
# a name genuinely bound from `fs` was not. And it folded `path.join` with a
# hand-written algebra that disagreed with node on Windows drive-relative
# paths, in a direction that changed the target rather than the spelling.
#
# The fixes are both deletions: TypeScript's checker answers "what is this
# name bound to here", and node's own `path` module answers "what does this
# join mean". Each test below is one of the measured counterexamples.
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "source, shape",
    [
        (
            'import * as fs from "fs";\n'
            "interface FakeFs { readFileSync(p: string): string }\n"
            "export function inspect(fs: FakeFs) {\n"
            f'  return fs.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
            "}\n"
            "export const keep = fs;\n",
            "parameter shadows the namespace import",
        ),
        (
            'import * as fs from "fs";\n'
            "export function probe() {\n"
            "  const fs = { readFileSync: (p: string) => p };\n"
            f'  return fs.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
            "}\n"
            "export const keep = fs;\n",
            "block-local const shadows it",
        ),
        (
            'import { readFileSync } from "fs";\n'
            "export function probe(readFileSync: (p: string) => string) {\n"
            f'  return readFileSync("../{IDENTITY_NAME}/terms.json");\n'
            "}\n"
            "export const keep = readFileSync;\n",
            "parameter shadows a named import",
        ),
        (
            "export function probe(require: (p: string) => unknown) {\n"
            f'  return require("../{IDENTITY_NAME}/src/index");\n'
            "}\n",
            "a local `require` is not node's",
        ),
    ],
    ids=["param-shadows-namespace", "block-shadows-namespace", "param-shadows-named", "local-require"],
)
def test_3a_does_not_read_a_shadowed_local_named_fs_as_the_module(tmp_path, source, shape):
    # The false-positive direction of the same defect. A file-global set of
    # NAMES cannot express scope, so an unrelated object's method call was
    # read as node's filesystem API -- an arbitrary object's method treated
    # as the real thing, which is the exact defect the previous round fixed
    # one layer up. Each fixture keeps the real import alive (`export const
    # keep`) so the case is genuinely about shadowing and not about the
    # import having been removed.
    root = _scratch_functions(tmp_path, {"probe.ts": source})
    assert vdi.verify_no_cross_import(root) == 1


@pytest.mark.parametrize(
    "source, shape",
    [
        (
            'import { promises as fsp } from "fs";\n'
            f'export const t = fsp.readFile("../{IDENTITY_NAME}/terms.json");\n',
            "named object export, aliased",
        ),
        (
            'import * as fs from "fs";\n'
            f'export const t = fs.promises.readFile("../{IDENTITY_NAME}/terms.json");\n',
            "object export off a namespace",
        ),
        (
            'const { promises } = require("fs");\n'
            f'export const t = promises.readFile("../{IDENTITY_NAME}/terms.json");\n',
            "CJS destructuring of the object export",
        ),
        (
            'const { promises: { readFile } } = require("fs");\n'
            f'export const t = readFile("../{IDENTITY_NAME}/terms.json");\n',
            "nested CJS binding pattern",
        ),
        (
            'import fsp from "fs/promises";\n'
            f'export const t = fsp.readFile("../{IDENTITY_NAME}/terms.json");\n',
            "the promises module itself",
        ),
    ],
    ids=["aliased-promises", "namespace-promises", "cjs-promises", "nested-binding", "fs-promises-module"],
)
def test_3a_rejects_a_sink_reached_through_an_fs_object_export(tmp_path, source, shape):
    # The miss direction. `promises` is an OBJECT export carrying the same
    # path-taking API, so `fsp.readFile(...)` is a real filesystem sink --
    # and every one of these names IS bound from `fs`, so none of them falls
    # under the declared residue "an alias this file does not bind from fs".
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


def test_3a_folds_a_drive_relative_join_the_way_node_does(tmp_path):
    """`D:..` is drive-RELATIVE; rewriting it as `D:\\` is a different place.

    Node's own answer is measured here rather than asserted, exactly as the
    cancelling-components regression does. The hand-written algebra this
    replaced treated any drive prefix as anchoring, dropped the `..`, and
    emitted `D:/<NAME>/package.json` -- an absolute path somewhere else,
    which physical containment then reported as clean. A fully constant,
    correctly bound dependency, under a docstring claiming constant
    `path.join` as covered.
    """
    probe = subprocess.run(
        [
            vdi.NODE,
            "-e",
            "const w=require('path').win32;"
            f"const j=w.join('D:..','{IDENTITY_NAME}','package.json');"
            "process.stdout.write(JSON.stringify({j, abs: w.isAbsolute(j)}))",
        ],
        capture_output=True, text=True,
    )
    assert probe.returncode == 0, probe.stderr
    measured = json.loads(probe.stdout)
    assert measured["abs"] is False, measured
    assert measured["j"].replace("\\", "/").startswith("D:.."), measured

    source = (
        'import * as fs from "fs";\n'
        'import * as p from "path";\n'
        f'export const t = fs.readFileSync(p.join("D:..", "{IDENTITY_NAME}", "package.json"));\n'
    )
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


def test_3a_does_not_reject_a_drive_relative_join_that_stays_outside(tmp_path):
    # The control: the drive-relative reading must be a real path reading,
    # not a rule that fires on any `D:` prefix near the package name.
    source = (
        'import * as fs from "fs";\n'
        'import * as p from "path";\n'
        f'export const t = fs.readFileSync(p.join("D:..", "{IDENTITY_NAME}", "..", "elsewhere", "t.json"));\n'
    )
    root = _scratch_functions(tmp_path, {"probe.ts": source})
    assert vdi.verify_no_cross_import(root) == 1


def test_3a_folds_an_explicitly_posix_binding_under_posix_rules(tmp_path):
    # `path/posix` is one algebra, not both. Measured against node so the
    # test cannot drift from what the module actually does.
    probe = subprocess.run(
        [vdi.NODE, "-e",
         "const p=require('path').posix;"
         f"process.stdout.write(p.join('scratch','..','..','{IDENTITY_NAME}','terms.json'))"],
        capture_output=True, text=True,
    )
    assert probe.returncode == 0, probe.stderr
    assert probe.stdout.startswith("../"), probe.stdout

    source = (
        'import * as fs from "fs";\n'
        'import * as p from "path/posix";\n'
        f'export const t = fs.readFileSync(p.join("scratch", "..", "..", "{IDENTITY_NAME}", "terms.json"));\n'
    )
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


@pytest.mark.parametrize(
    "sources, manifest, shape",
    [
        ({"probe.ts": f'import {{ x }} from "../{IDENTITY_NAME}-old/src";\nexport const y = x;\n'},
         None, "module specifier naming a sibling package"),
        ({"probe.ts": 'import * as fs from "fs";\n'
                      f'export const t = fs.readFileSync("../{IDENTITY_NAME}-old/terms.json");\n'},
         None, "filesystem path into a sibling package"),
        ({"probe.ts": "export const noop = 1;\n"},
         {"name": "scratch", "dependencies": {"other-lib": f"npm:{IDENTITY_NAME}-old@1.0.0"}},
         "dependency spec whose name merely starts with this one's"),
        ({"probe.ts": "export const noop = 1;\n"},
         {"name": "scratch", "dependencies": {"fork": f"github:someorg/{IDENTITY_NAME}-fork"}},
         "git spec naming a fork"),
    ],
    ids=["specifier", "fs-path", "npm-alias-spec", "git-spec"],
)
def test_3a_does_not_read_a_sibling_package_name_as_this_one(tmp_path, sources, manifest, shape):
    # `functions-equipment-identity-old` is a DIFFERENT directory, and the
    # manifest channel was the one place in this file still matching by raw
    # substring while everything around it matched by component. Measured:
    # `npm:<NAME>-old@1.0.0` was rejected as an isolation breach.
    root = _scratch_functions(tmp_path, sources, manifest)
    assert vdi.verify_no_cross_import(root) == 1


@pytest.mark.parametrize(
    "spec",
    [f"file:../{IDENTITY_NAME}", f"link:../{IDENTITY_NAME}", f"npm:{IDENTITY_NAME}@1.0.0"],
    ids=["file", "link", "npm-alias"],
)
def test_3a_still_rejects_a_manifest_spec_that_really_names_the_package(tmp_path, spec):
    # The control in the other direction, so the component rule above cannot
    # be satisfied by a check that stopped looking at manifests at all.
    root = _scratch_functions(
        tmp_path, {"probe.ts": "export const noop = 1;\n"},
        {"name": "scratch", "dependencies": {"identity": spec}},
    )
    with pytest.raises(vdi.IsolationVerificationError, match="declares a dependency"):
        vdi.verify_no_cross_import(root)


@pytest.mark.parametrize(
    "call, shape",
    [
        (f'fs.renameSync("a.json", "../{IDENTITY_NAME}/b.json");', "destination of a two-path call"),
        (f'fs.copyFileSync("a.json", "../{IDENTITY_NAME}/b.json");', "destination of a copy"),
        (f'fs.createReadStream("../{IDENTITY_NAME}/terms.json");', "an fs method the table does not list"),
    ],
    ids=["rename-destination", "copy-destination", "untabulated"],
)
def test_3a_reads_every_declared_path_position_of_an_fs_call(tmp_path, call, shape):
    # `FS_PATH_ARGUMENTS` claims both positions for the two-path APIs and
    # position 0 for anything unlisted. Before this, only single-position
    # `readFileSync` and `writeFileSync` were exercised, so dropping index 1
    # from every dual entry would have failed no test at all.
    source = 'import * as fs from "fs";\n' + call + "\n"
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


def test_3a_does_not_read_the_source_of_a_two_path_call_as_content(tmp_path):
    # The matching control: both positions are paths, so a rename whose
    # SOURCE is outside must still be judged on the source, not waved past.
    source = (
        'import * as fs from "fs";\n'
        f'fs.renameSync("../{IDENTITY_NAME}-old/a.json", "b.json");\n'
    )
    root = _scratch_functions(tmp_path, {"probe.ts": source})
    assert vdi.verify_no_cross_import(root) == 1


def test_tsc_wrapper_refuses_a_silent_success(tmp_path, monkeypatch):
    """Empty stdout on a ZERO exit must raise, isolated from the exit check.

    The existing silence test points `include` at a missing directory, which
    tsc reports as a diagnostic on a NON-zero exit -- so it was killed by the
    returncode branch and could not tell whether the empty-output branch
    existed at all. This one stubs the run so only the second branch can
    fire.
    """
    class _Result:
        returncode = 0
        stdout = ""
        stderr = ""

    monkeypatch.setattr(vdi, "_run", lambda *a, **k: _Result())
    with pytest.raises(vdi.IsolationVerificationError, match="produced no output"):
        vdi._tsc(["--listFilesOnly"], "stubbed")


def test_3d_does_not_read_a_config_that_merely_names_the_package(tmp_path):
    # The step-3d control matching step 3a's own: naming the package in an
    # option value is not inheriting from it.
    base = _config(
        tmp_path / "shared",
        {"compilerOptions": {"paths": {"identity/*": [f"./{IDENTITY_NAME}/*"]}}},
        name="base.json",
    )
    cfg = _config(tmp_path / "proj", {
        "extends": str(base).replace("\\", "/"),
        "compilerOptions": {"noEmit": True},
    })
    assert vdi.verify_no_config_inheritance_from_identity(cfg) == 1


def test_step_1_rejects_a_firebase_json_without_the_identity_codebase(tmp_path, monkeypatch):
    # Step 1's rejections were unreached by any test: deleting its body and
    # returning would have kept the suite green.
    broken = tmp_path / "firebase.json"
    broken.write_text(
        json.dumps({"functions": [{"codebase": "default", "source": "functions"}]}),
        encoding="utf-8",
    )
    monkeypatch.setattr(vdi, "FIREBASE_JSON", broken)
    with pytest.raises(vdi.IsolationVerificationError, match="equipment-identity"):
        vdi.verify_firebase_json_codebases()


def test_step_2_rejects_byte_identical_lockfiles(tmp_path, monkeypatch):
    # Same gap on step 2. The shared-lockfile case is the whole point of the
    # check and nothing exercised it.
    left, right = tmp_path / "a", tmp_path / "b"
    for directory in (left, right):
        directory.mkdir()
        (directory / "package-lock.json").write_text('{"name": "same"}', encoding="utf-8")
    monkeypatch.setattr(vdi, "FUNCTIONS_DIR", left)
    monkeypatch.setattr(vdi, "IDENTITY_DIR", right)
    with pytest.raises(vdi.IsolationVerificationError, match="byte-identical"):
        vdi.verify_independent_package_locks()


@pytest.mark.parametrize(
    "parts, caught_by",
    [
        (["..\\scratch", "..", IDENTITY_NAME, "x"], "win32"),
        (["a\\b", "..", "..", IDENTITY_NAME, "x"], "posix"),
    ],
    ids=["only-win32-sees-it", "only-posix-sees-it"],
)
def test_3a_folds_plain_path_under_both_algebras(tmp_path, parts, caught_by):
    r"""A bare `path` import is folded under win32 AND posix, and both matter.

    This probe runs on Windows; `functions` deploys to nodejs20 on Linux. A
    backslash is a separator to one algebra and an ordinary character to the
    other, so the same constant arguments reach different places -- measured
    here rather than argued:

        join("..\scratch", "..", NAME, "x")
            win32 -> "..\<NAME>\x"          (into the package)
            posix -> "<NAME>/x"               (a plain name, clean)

        join("a\b", "..", "..", NAME, "x")
            win32 -> "<NAME>\x"              (a plain name, clean)
            posix -> "../<NAME>/x"            (into the package)

    Each direction is caught by exactly one algebra, so dropping either one
    is a real miss and neither is decoration. The first fixture is why this
    test exists at all: a mutation that folded plain `path` under posix only
    survived the drive-relative regression, because the Python side rescued
    that particular value -- a guard nothing could tell apart from its own
    absence.
    """
    real = [part.replace("\\\\", "\\") for part in parts]
    probe = subprocess.run(
        [vdi.NODE, "-e",
         "const p=require('path');const a=JSON.parse(process.argv[1]);"
         "process.stdout.write(JSON.stringify({win32:p.win32.join(...a),posix:p.posix.join(...a)}))",
         json.dumps(real)],
        capture_output=True, text=True,
    )
    assert probe.returncode == 0, probe.stderr
    measured = json.loads(probe.stdout)
    other = "posix" if caught_by == "win32" else "win32"
    # Measure the divergence instead of asserting a spelling of it: exactly
    # one algebra must land inside the package for this fixture to prove
    # anything at all.
    assert vdi._is_relative_path_into_identity(measured[caught_by]), measured
    assert not vdi._is_relative_path_into_identity(measured[other]), measured

    arguments = ", ".join('"' + part.replace("\\", "\\\\") + '"' for part in real)
    source = (
        'import * as fs from "fs";\n'
        'import * as p from "path";\n'
        f"export const t = fs.readFileSync(p.join({arguments}));\n"
    )
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


# ---------------------------------------------------------------------------
# Round-5 implementation review. Two of the round-4 fixes were each right in
# one of the two places they had to hold, and the one-program approach that
# made the checker available leaked script globals between files. Every case
# below was measured against the round-4 code before being accepted.
# ---------------------------------------------------------------------------

def test_3a_does_not_read_a_locally_declared_require_as_node(tmp_path):
    """A file that declares its own `require` is not calling node's.

    The direct-call path asked the checker about this in round 4; the CJS
    INITIALIZER path only checked the spelling. Measured on that version, the
    read below was rejected as an identity dependency although `fs` here is a
    plain object literal returned by a local function.
    """
    source = (
        "function require(name: string) {\n"
        "  return { readFileSync: (p: string) => p };\n"
        "}\n"
        'const fs = require("fs");\n'
        f'export const t = fs.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
    )
    root = _scratch_functions(tmp_path, {"probe.ts": source})
    assert vdi.verify_no_cross_import(root) == 1


def test_3a_still_reads_a_genuine_cjs_require_binding(tmp_path):
    # The control, so the rule above cannot be satisfied by a check that gave
    # up on CommonJS entirely.
    source = (
        'const fs = require("fs");\n'
        f'export const t = fs.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
    )
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


def test_3a_does_not_let_a_sibling_file_shadow_node_require(tmp_path):
    """One file's isolation answer must not depend on an unrelated file.

    TypeScript treats a source with no import and no export as a SCRIPT,
    whose top-level declarations share one global scope with every other
    script in the program. Measured on the round-4 code: a sibling containing
    nothing but `function require(...)` made the genuine import below read
    CLEAN, because the checker resolved this file's `require` to the
    sibling's declaration. Node runs each file in its own module wrapper; the
    program did not, until `moduleDetection: Force`.
    """
    root = _scratch_functions(tmp_path, {
        "other.ts": (
            "function require(name: string) {\n"
            "  return { readFileSync: (p: string) => p };\n"
            "}\n"
        ),
        "__tests__/boot.test.ts": f'const mod = require("../{IDENTITY_NAME}/src/index");\n',
    })
    with pytest.raises(vdi.IsolationVerificationError, match="must not resolve a module"):
        vdi.verify_no_cross_import(root)


def test_3a_does_not_let_a_sibling_file_shadow_an_fs_namespace(tmp_path):
    # The same contamination through the other channel: a sibling script
    # declaring `fs` must not change what THIS file's `fs` means.
    root = _scratch_functions(tmp_path, {
        "other.ts": "declare const fs: { readFileSync(p: string): string };\n",
        "__tests__/boot.test.ts": (
            'import * as fs from "fs";\n'
            f'export const t = fs.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
        ),
    })
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


@pytest.mark.parametrize(
    "call, member",
    [
        (f'fs.realpath.native("../{IDENTITY_NAME}/package.json", () => {{}});', "realpath"),
        (f'export const p = fs.realpathSync.native("../{IDENTITY_NAME}/package.json");', "realpathSync"),
    ],
    ids=["realpath-native", "realpathSync-native"],
)
def test_3a_rejects_the_native_variant_of_an_fs_path_function(tmp_path, call, member):
    """`fs.realpath.native` is a real function taking the same pathname.

    Node's own answer is measured here rather than assumed. The round-4 chain
    rule required every intermediate segment to be an fs OBJECT export, and
    `realpath` is a function, so the whole call was discarded as "not a
    sink" -- a false negative the remediation introduced, on an API this
    module's own argument table already lists.
    """
    probe = subprocess.run(
        [vdi.NODE, "-e",
         "const fs=require('fs');"
         f"process.stdout.write(typeof fs.{member}.native)"],
        capture_output=True, text=True,
    )
    assert probe.returncode == 0, probe.stderr
    assert probe.stdout == "function", probe.stdout

    source = 'import * as fs from "fs";\n' + call + "\n"
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


def test_3a_does_not_accept_an_arbitrary_member_chain_on_fs(tmp_path):
    """The control that keeps the `.native` rule from becoming "any member".

    The chain is rooted at a GENUINE `fs` namespace binding on purpose. A
    first attempt rooted it at `const anything = fs as unknown as {...}`, and
    a mutation deleting the intermediate-segment check SURVIVED it -- because
    `anything` is not a module binding at all, so the deleted check was never
    reached. The mutant was inert against that fixture, which is not the same
    as the guard being redundant. Here `fs` really is bound from `fs`,
    `constants` really is an `fs` export, and it still is not an object
    carrying path-taking functions -- so the call must not be a sink.
    """
    source = (
        'import * as fs from "fs";\n'
        f'export const t = fs.constants.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
    )
    root = _scratch_functions(tmp_path, {"probe.ts": source})
    assert vdi.verify_no_cross_import(root) == 1


# ---------------------------------------------------------------------------
# Round-6 implementation review. The round-5 fix defined "not node's require"
# as "the checker returned a declaration" -- but a declaration is not a
# binding. An ambient `declare function require(...)` emits no JavaScript at
# all; what runs is still node's own. Measured on the round-5 code, all three
# shapes below read CLEAN through both channels.
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "declaration, shape",
    [
        ("declare function require(name: string): any;", "ambient function"),
        ("declare const require: (name: string) => any;", "ambient const"),
        ("interface require { readFileSync(p: string): string }", "type-only interface"),
    ],
    ids=["ambient-function", "ambient-const", "type-only-interface"],
)
def test_3a_does_not_read_an_ambient_declaration_as_a_runtime_shadow(tmp_path, declaration, shape):
    # The fs-sink channel. None of these emits a value, so `require("fs")`
    # here is node's and `fs` really is node's filesystem module.
    source = (
        declaration + "\n"
        'const fs = require("fs");\n'
        f'export const t = fs.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
    )
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


def test_3a_does_not_let_an_ambient_require_hide_a_module_specifier(tmp_path):
    # The same defect through the OTHER channel. `isUnbound` feeds both the
    # CJS initializer and the bare-call specifier reader, so a fix in one
    # place that missed the other would be this gate's signature failure.
    source = (
        "declare function require(name: string): any;\n"
        f'export const mod = require("../{IDENTITY_NAME}/src/index");\n'
    )
    root = _scratch_functions(tmp_path, {"__tests__/boot.test.ts": source})
    with pytest.raises(vdi.IsolationVerificationError, match="must not resolve a module"):
        vdi.verify_no_cross_import(root)


def test_3a_still_treats_an_implemented_local_require_as_a_shadow(tmp_path):
    # The control that keeps the ambient rule from becoming "nothing shadows
    # require". A function with a BODY does emit a value.
    source = (
        "function require(name: string) {\n"
        "  return { readFileSync: (p: string) => p };\n"
        "}\n"
        'const fs = require("fs");\n'
        f'export const t = fs.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
    )
    root = _scratch_functions(tmp_path, {"probe.ts": source})
    assert vdi.verify_no_cross_import(root) == 1


# ---------------------------------------------------------------------------
# Round-7 implementation review. `import type` is ERASED from the emitted
# JavaScript, so a type-only alias named `require` shadows nothing at runtime.
# The round-6 predicate read `declaration.isTypeOnly`, which is the
# per-specifier flag; on the whole-clause form the specifier's own flag is
# false and the CLAUSE's is true, and the namespace form has no such flag on
# the declaration at all. TypeScript answers this itself with
# `isTypeOnlyImportOrExportDeclaration`, so the hand-rolled test is gone.
# ---------------------------------------------------------------------------

_TYPES_MODULE = (
    "export interface Foo { readFileSync(p: string): string }\n"
    "export const Foo: any = null;\n"
)


@pytest.mark.parametrize(
    "declaration, shape",
    [
        ('import type { Foo as require } from "./types";', "whole-clause import type"),
        ('import { type Foo as require } from "./types";', "per-specifier type modifier"),
    ],
    ids=["whole-clause", "per-specifier"],
)
def test_3a_does_not_read_a_type_only_import_as_a_runtime_shadow(tmp_path, declaration, shape):
    # Both were already rejected before the round-7 fix, and for a reason
    # this code had not chosen: the checker returns NO declarations for a
    # type-only alias used in a VALUE position, so `isUnbound` was true by
    # default. Pinned here so the behaviour stops depending on that accident.
    source = (
        declaration + "\n"
        "// @ts-ignore -- the import is erased; node's require is what runs\n"
        'const fs = require("fs");\n'
        f'export const t = fs.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
    )
    root = _scratch_functions(
        tmp_path, {"types.ts": _TYPES_MODULE, "__tests__/boot.test.ts": source}
    )
    with pytest.raises(vdi.IsolationVerificationError, match="relative path"):
        vdi.verify_no_cross_import(root)


def test_3a_does_not_read_a_type_only_namespace_import_as_a_shadow(tmp_path):
    """The one shape that was a live miss, and the reason the hand-rolled
    flag test had to go.

    `import type * as require from "./types"` resolves to a `NamespaceImport`
    whose declaration carries no `isTypeOnly` of its own -- the flag lives on
    the enclosing clause. The round-6 predicate therefore called it a runtime
    value, and a genuine `require("../<NAME>/src/index")` in the same file
    read CLEAN, although `import type` emits nothing at all.
    """
    source = (
        'import type * as require from "./types";\n'
        "// @ts-ignore -- the import is erased; node's require is what runs\n"
        f'export const mod = require("../{IDENTITY_NAME}/src/index");\n'
    )
    root = _scratch_functions(
        tmp_path, {"types.ts": _TYPES_MODULE, "__tests__/boot.test.ts": source}
    )
    with pytest.raises(vdi.IsolationVerificationError, match="must not resolve a module"):
        vdi.verify_no_cross_import(root)


@pytest.mark.parametrize(
    "declaration, shape",
    [
        ('import { Foo as require } from "./types";', "value named import"),
        ('import * as require from "./types";', "value namespace import"),
    ],
    ids=["value-named", "value-namespace"],
)
def test_3a_still_treats_a_value_import_named_require_as_a_shadow(tmp_path, declaration, shape):
    # The control in the other direction, without which the rule above would
    # be indistinguishable from "no import ever shadows require". These DO
    # emit a binding, so the call is not node's.
    source = (
        declaration + "\n"
        'const fs = require("fs");\n'
        f'export const t = fs.readFileSync("../{IDENTITY_NAME}/terms.json");\n'
    )
    root = _scratch_functions(tmp_path, {"types.ts": _TYPES_MODULE, "probe.ts": source})
    assert vdi.verify_no_cross_import(root) == 2
