# -*- coding: utf-8 -*-
"""One canonical JSON serialisation for the whole equipment_identity P0 namespace.

Every generator under `scripts/equipment_identity/` writes its committed
artefact through `dump_pretty` and hashes payloads through `payload_sha256` —
never a bespoke `json.dumps` call and never `hashlib.sha256` applied directly
to the pretty-printed file bytes. Two reasons this is one shared module
instead of a convention repeated in six generators:

1. **Determinism.** `sort_keys=True` on the pretty form and `separators=(",",
   ":")` on the compact form are cheap to get right once and easy to get
   subtly wrong six times (a forgotten `sort_keys`, a platform-dependent
   `\\r\\n`, a float that reprints differently across Python builds).
2. **Hash stability across formatting.** Pretty-printing (2-space indent) is
   for the file a human reads in a diff; hashing must not depend on how many
   spaces separate a key from its value, or on the OS's line-ending
   convention. `payload_sha256` always hashes the COMPACT form of the same
   dict `dump_pretty` would have pretty-printed, so re-indenting a generator's
   output can never silently change a recorded hash.

Matches `scripts/ml/dataset_registry.py`'s own `_dump` convention
(`json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\\n"`)
so a reader who already knows that file recognises this one.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


def dump_pretty(payload: dict[str, Any]) -> str:
    """The form committed to the repo: 2-space indent, sorted keys, one
    trailing newline, UTF-8 text (no `\\uXXXX` escaping of non-ASCII)."""
    return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def dump_compact(payload: dict[str, Any]) -> str:
    """The form that gets hashed: no insignificant whitespace, sorted keys.

    Two payloads that would pretty-print identically always compact-dump
    identically too, so this is never a second source of drift from
    `dump_pretty` — it is the same dict, same key order, just without the
    formatting a hash must not be sensitive to.
    """
    return json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    )


def payload_sha256(payload: dict[str, Any]) -> str:
    """SHA256 over the compact canonical form. This is the ONLY sanctioned way
    to hash a generated payload in this namespace — never hash the
    pretty-printed file bytes, which vary with indentation and line endings
    across platforms without the underlying data having changed at all."""
    return hashlib.sha256(dump_compact(payload).encode("utf-8")).hexdigest()


def file_sha256(path: Path) -> str:
    """SHA256 of a real file on disk (a source artefact this namespace reads
    and records the hash of — a `.dart` file, a `.tflite` model, a `.json`
    catalogue this namespace does not itself generate). Distinct from
    `payload_sha256`: this hashes bytes that already exist and are not ours
    to reformat; `payload_sha256` hashes a dict this namespace is about to
    write out."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_pretty(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dump_pretty(payload), encoding="utf-8")


def sort_by_key(items: list[dict[str, Any]], key: str) -> list[dict[str, Any]]:
    """Sort a list of dict records by one of their own fields.

    For any generated array whose order is not itself semantic (a set of
    source records, a set of scanner-contract entries), sorting by a stable
    key before serialising means two runs over the same real input always
    produce byte-identical output — re-running the generator is never itself
    a reason for `payload_sha256` to change.
    """
    return sorted(items, key=lambda item: item[key])
