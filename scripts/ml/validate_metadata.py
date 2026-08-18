# -*- coding: utf-8 -*-
"""Ask the genuine metadata library what the shipped model actually declares.

    python scripts/ml/validate_metadata.py --model mobile/assets/models/equipment_v1.tflite
    python -m pytest scripts/ml/test_validate_metadata.py -q

## Why this exists

`attach_metadata.py` in the recovered pipeline does not fail for want of a
stub -- it *installs* one. `_install_pywrap_stub` exposes
``GetMinimumMetadataParserVersion`` as a function returning the literal string
``"1.0.0"``, and ``out/metadata.json`` duly records
``min_parser_version: 1.0.0``. So the minimum-parser-version embedded in the
``equipment_v1.tflite`` this app ships was *stamped*, not computed.

For a plain image classifier carrying labels and normalisation that floor is
probably right. **Probably** is the entire problem: nobody computed it, so
nobody knows, and the artefact states it as though somebody had.

The obvious local "fix" -- widen the stub until the current error goes away --
would mean inventing a second metadata parser version and stamping that into a
shipped artefact too. This module exists so the question can be answered by
the real library instead.

## Why it is not run here

``tflite-support`` publishes no Windows wheels. The metadata writers survive
inside ``mediapipe`` but that build ships them without the
``_pywrap_metadata_version`` C extension -- which is what the pipeline's stub
was papering over in the first place. Probed rather than assumed:
``tflite_support`` is absent from ``D:/tools/ml-train-env`` and from the system
interpreter, and the Docker images present locally are bare ``python:*-slim``.

So this is a Linux script. Run it there:

    docker run --rm -v "$PWD":/w -w /w python:3.11-slim bash -c \\
      "pip install --quiet tflite-support==0.4.4 && \\
       python scripts/ml/validate_metadata.py --model mobile/assets/models/equipment_v1.tflite"

## What it will not do

It never writes to the model it is given. Every operation runs on a copy in a
temporary directory, and the champion, the registry and the mobile asset are
untouched by construction rather than by care. It also does not decide
anything: it prints facts and a verdict, and the verdict `VALIDATED_MISMATCH`
is a finding for a person, not a licence for this script to rewrite an
artefact.

**A prepared script is not a validation.** Until this has actually been run on
a machine with the genuine library, the state is ``ENVIRONMENT_NOT_RUN`` and
the provenance question stays open.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

#: What the pipeline's stub stamped. The number this module exists to check.
RECORDED_MIN_PARSER_VERSION = "1.0.0"

#: The four states this subtrack may end in. `ENVIRONMENT_NOT_RUN` is the
#: current one and is listed first so nobody has to hunt for the honest answer.
STATES = (
    "ENVIRONMENT_NOT_RUN",
    "VALIDATED_MATCH",
    "VALIDATED_MISMATCH",
    "PARSE_FAILED",
)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def genuine_library():
    """The real metadata reader, or None with the reason it is unavailable.

    Imported lazily and by name so this module can be read, tested and
    reviewed on a machine that cannot run it -- which is every machine this
    project currently has.
    """
    try:
        from tflite_support import metadata as _metadata  # noqa: F401
        import tflite_support
        return _metadata, getattr(tflite_support, "__version__", "unknown")
    except ImportError as exc:
        return None, f"tflite_support unavailable: {exc}"


def inspect(model: Path, workdir: Path) -> dict:
    """Read a COPY of the model with the genuine library.

    The copy is not a precaution against this function; it is a precaution
    against every future edit of this function. A reader should not have to
    audit the body to know the champion is safe.
    """
    copy = workdir / f"copy-{model.name}"
    shutil.copy2(model, copy)

    report: dict = {
        "input_path": str(model),
        "input_sha256": sha256(model),
        "copy_sha256": sha256(copy),
        "recorded_min_parser_version": RECORDED_MIN_PARSER_VERSION,
    }
    # A copy whose digest differs from its source means the filesystem lied to
    # us, and every number below would be about a different file.
    if report["copy_sha256"] != report["input_sha256"]:
        report["state"] = "PARSE_FAILED"
        report["detail"] = "the working copy does not match its source"
        return report

    lib, version = genuine_library()
    report["genuine_library_version"] = version
    if lib is None:
        report["state"] = "ENVIRONMENT_NOT_RUN"
        report["detail"] = (
            "the genuine library is not installed here, so nothing was "
            "validated. This is a prepared script, not a result."
        )
        return report

    try:
        displayer = lib.MetadataDisplayer.with_model_file(str(copy))
        raw = displayer.get_metadata_json()
        parsed = json.loads(raw)
        report["computed_min_parser_version"] = parsed.get("min_parser_version")
        report["labels"] = sorted(displayer.get_packed_associated_file_list())
        subgraphs = parsed.get("subgraph_metadata") or [{}]
        inputs = subgraphs[0].get("input_tensor_metadata") or [{}]
        report["input_normalization"] = [
            o for o in (inputs[0].get("process_units") or [])
        ]
    except Exception as exc:  # noqa: BLE001 -- any failure is the answer
        report["state"] = "PARSE_FAILED"
        report["detail"] = f"{type(exc).__name__}: {exc}"
        return report

    computed = report.get("computed_min_parser_version")
    report["state"] = (
        "VALIDATED_MATCH" if computed == RECORDED_MIN_PARSER_VERSION
        else "VALIDATED_MISMATCH"
    )
    report["detail"] = (
        f"the genuine library computes {computed!r}; the pipeline's stub "
        f"stamped {RECORDED_MIN_PARSER_VERSION!r}"
    )
    return report


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument(
        "--model",
        default="mobile/assets/models/equipment_v1.tflite",
        help="path, relative to the repository root, of the model to READ",
    )
    args = ap.parse_args(argv)

    model = (REPO / args.model).resolve()
    if not model.exists():
        print(f"no such model: {model}")
        return 2

    with tempfile.TemporaryDirectory(prefix="metadata-validate-") as tmp:
        report = inspect(model, Path(tmp))

    for key in ("input_path", "input_sha256", "genuine_library_version",
                "recorded_min_parser_version", "computed_min_parser_version",
                "labels", "input_normalization", "state", "detail"):
        if key in report:
            print(f"{key.upper():32} {report[key]}")

    # The champion is unchanged by construction; assert it anyway, because an
    # assertion is checkable and a design intention is not.
    assert sha256(model) == report["input_sha256"], "the model was modified"

    if report["state"] == "ENVIRONMENT_NOT_RUN":
        print("\nNOTHING WAS VALIDATED. See this module's docstring for the "
              "container invocation that can.")
        return 3
    return 0 if report["state"] == "VALIDATED_MATCH" else 1


if __name__ == "__main__":
    raise SystemExit(main())
