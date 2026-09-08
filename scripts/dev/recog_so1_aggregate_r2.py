"""RECOG-SO1 revision 2 aggregator: the fail-closed boundary the scorer stands behind.

The runner produces one JSONL file per partition. The scorer needs exactly one
evidence bundle. Between those two shapes sits every failure mode a manual
concatenation would let through silently: a missing partition, a duplicate
observation, a partial file from an INVALID_INSTRUMENT stop treated as if it
were complete, a ledger that does not actually back the attempts a file
claims, a hand-edited file with a correct-looking header pasted onto raw lines
nobody produced together. This module is the mechanical check for all of it.

TWO ENTRY POINTS, ONE DIRECTION OF TRUST.

  aggregate()          reads the runner's raw per-partition output files plus
                        the live ledger, and -- only if every structural and
                        ledger-reconciliation check holds -- writes ONE evidence
                        bundle: a provenance record, then every raw record
                        verbatim (availability, observation, invalid_instrument
                        markers), and nothing else.

  validate_bundle()    is the boundary `recog_so1_score_r2.py` actually stands
                        behind. It does not trust that a bundle came from
                        aggregate() -- a bundle's own bytes are all it is given
                        -- so it re-derives everything aggregate() claimed:
                        recomputes each partition segment's sha256 from the
                        bundle's OWN raw bytes, re-verifies the whole seal,
                        re-checks the current pre-registration and manifest
                        digests, and RE-RUNS the same ledger reconciliation
                        aggregate() ran, selecting ledger rows by
                        `entry.partition == N` over the WHOLE current ledger --
                        never by any timestamp window the bundle itself
                        declares. A bundle's own claimed window is verified
                        against that independently-derived one, never trusted
                        as a selector.

TWO CLOSED SHAPES, NOT ONE "fewer than four files is an error."

  COMPLETE           partitions 1-4 all present. Each file opens with exactly
                     one availability record (status "ok", first in the
                     file), its observation-record IDs are exactly that
                     partition's manifest set, and no invalid_instrument
                     marker appears anywhere in the file.

  TERMINAL_INVALID   partitions 1..k-1 (if any) are COMPLETE per above;
                     partition k is either availability-invalid (exactly one
                     record, carrying invalid_instrument, zero observations)
                     or corpus-invalid (one ok availability record, then a
                     manifest-order-consistent prefix of that partition's own
                     observations, where the LAST record and only the last
                     carries invalid_instrument); partitions k+1..4 are
                     absent -- they were never run, so nothing is expected of
                     them. Any other partial shape refuses as unrecognised.

LEDGER RECONCILIATION IS PER CLASS, NOT ONE POOLED TOTAL. The availability
probe and every corpus observation share the same retry engine
(`send_with_retries` in recog_so1_run_r2.py), so a rolling-window 429 can
legitimately leave `attempts` above 1, and a pre-transport budget refusal can
legitimately leave it at 0. Zero is accepted in exactly two situations: the
observation never entered the retry engine at all (image_missing,
image_digest_mismatch -- no ledger entry was ever written for it), or the
first call hit the ledger-budget guard before any transport call
(`invalid_instrument: "ledger_budget_exceeded"`, on the availability probe or
a corpus observation). Any other zero, or any negative value, refuses. This
establishes ledger/output COUNT-AND-TIMING CONSISTENCY, not cryptographic
proof of authorship -- the ledger schema carries no run or observation
identifier, and extending it is out of scope for this gate.

WHAT THIS MODULE DOES NOT TOUCH. `recog_so1_run_r2.py`, `recog_so1_ledger.py`,
and revision 1's `recog_so1_run.py` / `recog_so1_score.py` are all imported
unedited. The real `<!-- SEAL -->` block in the pre-registration stays empty
until the operator's own sealing sequence fills it; until then this module
refuses to build or validate a bundle at all, on exactly the same empty-seal
condition the runner already refuses on.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parents[2]
PLANS = REPO / "core" / "plans"
DEV = REPO / "scripts" / "dev"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


#: The revision 2 runner. Imported, never edited. `runner.base` is the sealed
#: revision 1 runner this module reaches `load_manifest`, `load_seal`,
#: `verify_seal` and `sha256_file` through -- the same instances the runner
#: itself uses, so a test rebinding `runner.base.REPO` redirects this module's
#: own seal verification exactly as it redirects the runner's.
runner = _load_module("so1_aggregate_run_r2", DEV / "recog_so1_run_r2.py")
ledger_mod = _load_module("so1_aggregate_ledger", DEV / "recog_so1_ledger.py")

Ledger = ledger_mod.Ledger
LedgerUnusable = ledger_mod.LedgerUnusable

PARTITIONS: tuple[int, ...] = (1, 2, 3, 4)

#: Production defaults. `aggregate()` and `validate_bundle()` accept every one
#: of these as a parameter for the test harness; `score_r2.main()` calls
#: `validate_bundle()` with none of them, so production always resolves the
#: real files with no branch, flag or special case.
PREREGISTRATION_R2 = runner.PREREGISTRATION_R2
LEDGER = runner.LEDGER
PARTITION_MANIFEST_PATHS: dict[int, Path] = {p: runner.partition_manifest(p) for p in PARTITIONS}

#: The path key this module's own digest must appear under in the seal, once
#: sealed. Relative to REPO, matching every other entry in the seal block.
AGGREGATOR_SELF_REL = "scripts/dev/recog_so1_aggregate_r2.py"

PROVENANCE_RECORD_TYPE = "provenance"

#: The only observation failures that legitimately never reach the retry
#: engine at all -- both are local, pre-transport checks in `run_partition()`.
KNOWN_PRETRANSPORT_FAILURES = frozenset({"image_missing", "image_digest_mismatch"})

ISOLATION_HOURS = 24


# --------------------------------------------------------------------------
# Small, independently-testable predicates (Contract 5: predicate/integration
# split). Each one is shown capable of failing on its own terms, not only as
# part of a larger fixture.
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class PartitionFile:
    partition: int
    raw_lines: list[str]
    records: list[dict]


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _parse_jsonl_text(label: str, text: str) -> tuple[list[str], list[dict]]:
    """Every non-blank line, parsed. Raises ValueError with a labelled message."""
    raw_lines = [ln for ln in text.splitlines() if ln.strip()]
    records = []
    for i, ln in enumerate(raw_lines, start=1):
        try:
            d = json.loads(ln)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{label} line {i} is not JSON: {exc}") from exc
        if not isinstance(d, dict):
            raise ValueError(f"{label} line {i} is not an object")
        records.append(d)
    return raw_lines, records


def _classify_partition_file(pf: PartitionFile, manifest_order: list[str]) -> tuple[str | None, list[str]]:
    """Is this one file COMPLETE-shaped ("present") or TERMINAL_INVALID-shaped
    ("terminal")? Returns (None, reasons) for any other shape.

    Structural only: this never touches the ledger. Ledger reconciliation is a
    separate predicate (`reconcile_partition_ledger`) so a fixture can defeat
    one without the other.
    """
    p = pf.partition
    manifest_set = set(manifest_order)
    if not pf.records:
        return None, [f"partition {p}: the file is empty"]

    first = pf.records[0]
    if first.get("record_type") != "availability":
        return None, [f"partition {p}: the first record is not an availability record"]
    rest = pf.records[1:]

    if first.get("invalid_instrument"):
        if rest:
            return None, [
                f"partition {p}: the availability record carries invalid_instrument but the file "
                f"holds {len(rest)} additional record(s); an availability-invalid file must be "
                f"exactly one record"
            ]
        return "terminal", []

    if first.get("status") != "ok":
        return None, [
            f"partition {p}: the availability record is neither status 'ok' nor "
            f"invalid_instrument -- an unrecognised shape"
        ]

    for i, r in enumerate(rest, start=1):
        if r.get("record_type") != "observation":
            return None, [f"partition {p}: record {i} after the availability record is not an "
                          f"observation record"]

    ids_in_order = [r.get("observation_id") for r in rest]
    if len(set(ids_in_order)) != len(ids_in_order):
        return None, [f"partition {p}: a duplicate observation_id appears within this file"]

    invalid_positions = [i for i, r in enumerate(rest) if r.get("invalid_instrument")]

    if not invalid_positions:
        if set(ids_in_order) != manifest_set:
            missing = sorted(manifest_set - set(ids_in_order))
            extra = sorted(set(ids_in_order) - manifest_set)
            return None, [
                f"partition {p}: observation IDs do not equal the partition's manifest set "
                f"(missing {missing}, unexpected {extra})"
            ]
        return "present", []

    if len(invalid_positions) > 1:
        return None, [
            f"partition {p}: invalid_instrument appears on {len(invalid_positions)} records; "
            f"at most one, on the final record, is a recognised shape"
        ]
    if invalid_positions[0] != len(rest) - 1:
        return None, [f"partition {p}: invalid_instrument is not on the file's final record"]
    if ids_in_order != manifest_order[: len(ids_in_order)]:
        return None, [
            f"partition {p}: the observation IDs are not a manifest-order-consistent prefix "
            f"ending at the invalid_instrument record"
        ]
    return "terminal", []


def _attempts_of(record: dict) -> tuple[int, str | None]:
    """(attempts, problem). problem is None exactly when the value is legitimate.

    A missing `attempts` field contributes 0 and is legitimate ONLY for a known
    pre-transport observation failure. An explicit 0 is legitimate ONLY when
    the record's own invalid_instrument is "ledger_budget_exceeded" -- the one
    outcome `budget_room()` can produce before any transport call is made.
    """
    if "attempts" not in record:
        if record.get("record_type") == "observation" and record.get("failure") in KNOWN_PRETRANSPORT_FAILURES:
            return 0, None
        return 0, "the record carries no attempts field and is not a known pre-transport failure"
    a = record["attempts"]
    if not isinstance(a, int) or isinstance(a, bool):
        return 0, f"attempts is not an integer: {a!r}"
    if a < 0:
        return 0, f"attempts is negative: {a}"
    if a == 0:
        if record.get("invalid_instrument") == "ledger_budget_exceeded":
            return 0, None
        return 0, "attempts is 0 but invalid_instrument is not ledger_budget_exceeded"
    return a, None


def reconcile_partition_ledger(
    partition: int,
    availability_record: dict | None,
    observation_records: list[dict],
    ledger_entries: list,
) -> list[str]:
    """Per-class reconciliation. `ledger_entries` is always the WHOLE ledger --
    this function selects its own partition's rows by `entry.partition ==
    partition`, never from a pre-filtered or bundle-declared subset, so the
    selection can never be made circular by whatever calls it.
    """
    reasons: list[str] = []
    mine = [e for e in ledger_entries if e.partition == partition]
    avail_ledger_n = sum(1 for e in mine if e.request_class == "availability")
    corpus_ledger_n = sum(1 for e in mine if e.request_class == "corpus")

    if availability_record is not None:
        a, problem = _attempts_of(availability_record)
        if problem:
            reasons.append(f"partition {partition} availability record: {problem}")
        elif a != avail_ledger_n:
            reasons.append(
                f"partition {partition}: the availability record claims {a} attempt(s) but the "
                f"ledger holds {avail_ledger_n} availability-class entries for this partition"
            )

    corpus_claimed = 0
    for r in observation_records:
        a, problem = _attempts_of(r)
        if problem:
            reasons.append(
                f"partition {partition} observation {r.get('observation_id')!r}: {problem}"
            )
            continue
        corpus_claimed += a
    if corpus_claimed != corpus_ledger_n:
        reasons.append(
            f"partition {partition}: observation records claim {corpus_claimed} total corpus "
            f"attempt(s) but the ledger holds {corpus_ledger_n} corpus-class entries"
        )
    return reasons


def partition_ledger_window(partition: int, ledger_entries: list) -> tuple[datetime, datetime] | None:
    """(min at, max at) over this partition's own ledger rows, or None if none exist."""
    at = [e.at for e in ledger_entries if e.partition == partition]
    if not at:
        return None
    return min(at), max(at)


def verify_isolation_gaps(present_partitions: list[int], ledger_entries: list, hours: int = ISOLATION_HOURS) -> list[str]:
    """Two independent gap requirements, both drawn verbatim from the frozen
    protocol (RECOG_SO1_PREREGISTRATION_R2_2026-09-08.md, section 7):

    1. For EVERY partition's start, the gap since the last ledger entry of ANY
       class -- any partition, stress probes (`partition: None`) included --
       must be >= `hours`. This mirrors `Ledger.isolation_ok()`'s own contract
       exactly ("of any class deliberately"): an interposed stress probe or any
       other request genuinely resets the isolation clock the runner itself
       reads, no matter which partition (if any) it is filed under.
    2. For every LATER partition specifically, the gap since the PREVIOUS
       partition's (by number) own last ledger entry must ALSO independently
       be >= `hours` -- "Each later partition may not start until 24 hours
       after the previous partition's last ledger entry." Requirement 1 alone
       does not enforce that partitions ran in ascending numeric/chronological
       order: a partition run out of number order can still pass requirement 1
       against whatever the closest preceding entry of any kind happens to be,
       while silently violating this pairwise rule the protocol separately
       states. Dropping this when requirement 1 was added was a real
       regression, caught by GPT-PM's round-2 review of that very fix.
    """
    reasons: list[str] = []
    windows: dict[int, tuple[datetime, datetime]] = {}
    for p in present_partitions:
        w = partition_ledger_window(p, ledger_entries)
        if w is None:
            reasons.append(f"partition {p}: no ledger entries at all; isolation cannot be verified")
            continue
        windows[p] = w
    if reasons:
        return reasons

    required = timedelta(hours=hours)
    ordered = sorted(present_partitions)

    for p in ordered:
        start_p, _ = windows[p]
        earlier = [e.at for e in ledger_entries if e.at < start_p]
        if not earlier:
            continue
        gap = start_p - max(earlier)
        if gap < required:
            reasons.append(
                f"partition {p}: only {gap.total_seconds() / 3600:.1f}h since the last ledger "
                f"entry of any class before it (< {hours}h)"
            )

    for prev, cur in zip(ordered, ordered[1:]):
        _, end_prev = windows[prev]
        start_cur, _ = windows[cur]
        gap = start_cur - end_prev
        if gap < required:
            reasons.append(
                f"partition {cur}: only {gap.total_seconds() / 3600:.1f}h since partition {prev}'s "
                f"last ledger entry (< {hours}h)"
            )
    return reasons


def verify_absent_partitions_are_truly_unrun(states: dict[int, str], ledger_entries: list) -> list[str]:
    """A partition tagged `absent_after_terminal` is a claim that it was NEVER
    RUN. Prove it against the WHOLE ledger rather than merely omitting it from
    reconciliation -- otherwise a bundle correctly shaped for partitions 1..k
    validates regardless of what the ledger actually holds for k+1..4, and the
    closed TERMINAL_INVALID shape (`recog_so1_aggregate_r2.py`'s own module
    docstring: "they were never run, so nothing is expected of them") is
    unenforced exactly where it matters.
    """
    reasons: list[str] = []
    for p in PARTITIONS:
        if states.get(p) != "absent_after_terminal":
            continue
        if partition_ledger_window(p, ledger_entries) is not None:
            reasons.append(
                f"partition {p} is declared absent_after_terminal -- never run -- but the ledger "
                f"holds request(s) recorded for it; that contradicts the closed TERMINAL_INVALID "
                f"shape this bundle claims"
            )
    return reasons


def _seal_ok(preregistration_path: Path, load_seal, verify_seal) -> tuple[dict | None, list[str]]:
    seal = load_seal(preregistration_path)
    if not seal:
        return None, [
            "the pre-registration seal is EMPTY. The aggregator refuses to run exactly as the "
            "runner refuses on an empty seal -- this protocol is drafted, not sealed."
        ]
    reasons = []
    if AGGREGATOR_SELF_REL not in seal:
        reasons.append(
            f"the seal does not cover {AGGREGATOR_SELF_REL}; the aggregator's own script must be "
            f"sealed before it may build or validate an evidence bundle"
        )
    problems = verify_seal(seal)
    if problems:
        reasons.append("the frozen artefacts do not match the seal:")
        reasons.extend("  " + p for p in problems)
    if reasons:
        return None, reasons
    return seal, []


# --------------------------------------------------------------------------
# Cross-file assembly (Contract 2 + 4)
# --------------------------------------------------------------------------

def _assemble(
    partition_files: dict[int, PartitionFile],
    manifest_orders: dict[int, list[str]],
) -> tuple[str | None, dict[int, str], list[str]]:
    present = sorted(partition_files)
    if present != list(range(1, len(present) + 1)):
        return None, {}, [
            f"partition files present are {present}; they must be a contiguous prefix starting "
            f"at 1 with no gaps"
        ]

    states: dict[int, str] = {}
    terminal_at: int | None = None
    for p in present:
        state, why = _classify_partition_file(partition_files[p], manifest_orders[p])
        if state is None:
            return None, {}, why
        states[p] = state
        if state == "terminal":
            if p != present[-1]:
                return None, {}, [f"partition {p} is TERMINAL_INVALID but partitions after it "
                                  f"are also present"]
            terminal_at = p

    all_ids: list[str] = []
    for p in present:
        for r in partition_files[p].records:
            if r.get("record_type") == "observation":
                all_ids.append(r.get("observation_id"))
    if len(set(all_ids)) != len(all_ids):
        return None, {}, ["an observation_id appears in more than one partition file"]

    if terminal_at is not None:
        for p in PARTITIONS:
            if p not in states:
                states[p] = "absent_after_terminal"
        return "TERMINAL_INVALID", states, []

    if present != list(PARTITIONS):
        return None, {}, [
            f"only partitions {present} are present and none is TERMINAL_INVALID; COMPLETE "
            f"requires all four, and a partial run must end in a file that actually carries "
            f"invalid_instrument"
        ]
    return "COMPLETE", states, []


# --------------------------------------------------------------------------
# aggregate(): build the one evidence bundle
# --------------------------------------------------------------------------

def aggregate(
    partition_paths: dict[int, Path],
    *,
    ledger_path: Path | None = None,
    manifest_paths: dict[int, Path] | None = None,
    preregistration_path: Path | None = None,
    load_seal: Callable[[Path], dict] = runner.base.load_seal,
    verify_seal: Callable[[dict], list[str]] = runner.base.verify_seal,
    now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
) -> tuple[bytes | None, list[str]]:
    """(bundle_bytes, reasons). bundle_bytes is None on any refusal.

    `ledger_path`, `manifest_paths` and `preregistration_path` default to
    `None` and are resolved against the CURRENT module constants inside the
    function body, not bound as literal defaults at definition time -- a
    plain `= PREREGISTRATION_R2` default parameter freezes at import, so a
    test rebinding the module constant afterward would silently have no
    effect on a call using the default. This is exactly the sentinel pattern
    `manifest_paths` already used; `ledger_path` and `preregistration_path`
    are brought in line with it here.
    """
    manifest_paths = manifest_paths if manifest_paths is not None else PARTITION_MANIFEST_PATHS
    ledger_path = ledger_path if ledger_path is not None else LEDGER
    preregistration_path = preregistration_path if preregistration_path is not None else PREREGISTRATION_R2

    seal, reasons = _seal_ok(preregistration_path, load_seal, verify_seal)
    if seal is None:
        return None, reasons

    ledger = Ledger(ledger_path)
    try:
        ledger_entries = ledger.entries()
    except LedgerUnusable as exc:
        return None, [f"ledger unusable: {exc}"]

    for p in partition_paths:
        if p not in PARTITIONS:
            return None, [f"partition {p} is not one of {list(PARTITIONS)}"]
    if not partition_paths:
        return None, ["no partition output files were given"]

    partition_files: dict[int, PartitionFile] = {}
    for p, path in sorted(partition_paths.items()):
        if not path.is_file():
            return None, [f"partition {p} output file {path} does not exist"]
        try:
            raw_lines, records = _parse_jsonl_text(f"partition {p}", path.read_text("utf-8"))
        except ValueError as exc:
            return None, [str(exc)]
        partition_files[p] = PartitionFile(p, raw_lines, records)

    manifest_orders: dict[int, list[str]] = {}
    manifest_digests: dict[int, str] = {}
    for p in PARTITIONS:
        mp = manifest_paths[p]
        if not mp.is_file():
            return None, [f"partition {p} manifest {mp} is missing"]
        manifest_orders[p] = [o.observation_id for o in runner.base.load_manifest(mp)]
        manifest_digests[p] = runner.base.sha256_file(mp)

    kind, states, why = _assemble(partition_files, manifest_orders)
    if kind is None:
        return None, why

    present = sorted(partition_files)

    for p in present:
        recs = partition_files[p].records
        availability_record = recs[0] if recs and recs[0].get("record_type") == "availability" else None
        observation_records = [r for r in recs if r.get("record_type") == "observation"]
        reasons.extend(reconcile_partition_ledger(p, availability_record, observation_records, ledger_entries))
    if reasons:
        return None, reasons

    reasons.extend(verify_isolation_gaps(present, ledger_entries))
    if reasons:
        return None, reasons

    reasons.extend(verify_absent_partitions_are_truly_unrun(states, ledger_entries))
    if reasons:
        return None, reasons

    segment_digests: dict[int, str] = {}
    segment_line_counts: dict[int, int] = {}
    segment_windows: dict[int, tuple[datetime, datetime] | None] = {}
    for p in present:
        raw_lines = partition_files[p].raw_lines
        segment_text = "\n".join(raw_lines) + "\n"
        segment_digests[p] = hashlib.sha256(segment_text.encode("utf-8")).hexdigest()
        segment_line_counts[p] = len(raw_lines)
        segment_windows[p] = partition_ledger_window(p, ledger_entries)

    preregistration_digest = runner.base.sha256_file(preregistration_path)
    partitions_table: dict[str, dict] = {}
    for p in PARTITIONS:
        state = states[p]
        if state == "absent_after_terminal":
            partitions_table[str(p)] = {"state": state}
            continue
        entry = {
            "state": state,
            "sha256": segment_digests[p],
            "raw_line_count": segment_line_counts[p],
        }
        w = segment_windows[p]
        if w is not None:
            entry["ledger_start"] = _iso(w[0])
            entry["ledger_end"] = _iso(w[1])
        partitions_table[str(p)] = entry

    provenance = {
        "record_type": PROVENANCE_RECORD_TYPE,
        "aggregation_kind": kind,
        "recorded_at": _iso(now()),
        "preregistration_sha256": preregistration_digest,
        "partition_manifest_sha256": {str(p): manifest_digests[p] for p in PARTITIONS},
        "partitions": partitions_table,
    }

    out_lines = [json.dumps(provenance, ensure_ascii=False, sort_keys=True)]
    for p in present:
        out_lines.extend(partition_files[p].raw_lines)
    bundle_text = "\n".join(out_lines) + "\n"
    return bundle_text.encode("utf-8"), []


# --------------------------------------------------------------------------
# validate_bundle(): the boundary the scorer stands behind
# --------------------------------------------------------------------------

class _ImmutableText:
    """A read-only stand-in for a Path, holding one fixed string in memory.

    `recog_so1_score.py`'s `load_rows()` performs exactly one operation on its
    `so1_jsonl` argument: `.read_text(encoding)`. Nothing checks `isinstance`,
    calls `open()`, or resolves a filename. Python's duck typing means this
    class satisfies that boundary completely, so the rows R1 parses are the
    exact same in-memory string a `ValidatedBundle` already holds -- there is
    no file on disk for anything to race against between validation and read.
    """

    def __init__(self, text: str) -> None:
        self._text = text

    def read_text(self, encoding: str = "utf-8") -> str:
        return self._text


@dataclass(frozen=True)
class ValidatedBundle:
    raw_bytes: bytes
    provenance: dict
    raw_records: list[dict]
    observation_text: str


def validate_bundle(
    bundle_path: Path,
    *,
    preregistration_path: Path | None = None,
    manifest_paths: dict[int, Path] | None = None,
    ledger_path: Path | None = None,
    load_seal: Callable[[Path], dict] = runner.base.load_seal,
    verify_seal: Callable[[dict], list[str]] = runner.base.verify_seal,
) -> tuple[ValidatedBundle | None, list[str]]:
    """Read the bundle path ONCE, into bytes, and validate everything against
    that one snapshot. Nothing downstream of a successful return ever reopens
    `bundle_path`.

    `preregistration_path`, `manifest_paths` and `ledger_path` default to
    `None` and resolve against the CURRENT module constants at call time --
    see `aggregate()`'s docstring for why a literal `= PREREGISTRATION_R2`
    default would not do that. This is the property `score_r2.main()` relies
    on: calling `validate_bundle(bundle_path)` with no further arguments
    always resolves whatever these constants currently are.
    """
    manifest_paths = manifest_paths if manifest_paths is not None else PARTITION_MANIFEST_PATHS
    ledger_path = ledger_path if ledger_path is not None else LEDGER
    preregistration_path = preregistration_path if preregistration_path is not None else PREREGISTRATION_R2
    bundle_path = Path(bundle_path)

    if not bundle_path.is_file():
        return None, [f"no evidence bundle at {bundle_path}"]
    raw_bytes = bundle_path.read_bytes()
    try:
        text = raw_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        return None, [f"the evidence bundle is not valid utf-8: {exc}"]

    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return None, ["the evidence bundle is empty"]
    try:
        provenance = json.loads(lines[0])
    except json.JSONDecodeError as exc:
        return None, [f"the evidence bundle's first line does not parse: {exc}"]
    if not isinstance(provenance, dict) or provenance.get("record_type") != PROVENANCE_RECORD_TYPE:
        return None, ["the evidence bundle's first line is not a provenance record"]

    reasons: list[str] = []

    current_prereg_digest = runner.base.sha256_file(preregistration_path)
    if provenance.get("preregistration_sha256") != current_prereg_digest:
        reasons.append(
            "the bundle's provenance binds a preregistration_sha256 that does not match the "
            "CURRENT pre-registration document on disk"
        )

    bound_manifests = provenance.get("partition_manifest_sha256")
    if not isinstance(bound_manifests, dict):
        reasons.append("the bundle's provenance carries no partition_manifest_sha256 table")
    else:
        for p in PARTITIONS:
            mp = manifest_paths[p]
            if not mp.is_file():
                reasons.append(f"partition {p} manifest {mp} is missing")
                continue
            if bound_manifests.get(str(p)) != runner.base.sha256_file(mp):
                reasons.append(
                    f"partition {p}'s manifest digest in the bundle does not match the CURRENT "
                    f"manifest on disk"
                )
    if reasons:
        return None, reasons

    seal, seal_reasons = _seal_ok(preregistration_path, load_seal, verify_seal)
    if seal is None:
        return None, seal_reasons

    kind = provenance.get("aggregation_kind")
    if kind not in ("COMPLETE", "TERMINAL_INVALID"):
        return None, [f"the bundle declares an unrecognised aggregation_kind {kind!r}"]

    partitions_table = provenance.get("partitions")
    if not isinstance(partitions_table, dict):
        return None, ["the bundle's provenance carries no per-partition table"]

    states: dict[int, str] = {}
    for p in PARTITIONS:
        entry = partitions_table.get(str(p))
        if not isinstance(entry, dict) or "state" not in entry:
            return None, [f"partition {p} has no provenance entry"]
        states[p] = entry["state"]

    if kind == "COMPLETE":
        if any(states[p] != "present" for p in PARTITIONS):
            return None, ["aggregation_kind is COMPLETE but not every partition is tagged 'present'"]
    else:
        terminals = [p for p in PARTITIONS if states[p] == "terminal"]
        if len(terminals) != 1:
            return None, [
                f"aggregation_kind is TERMINAL_INVALID but {len(terminals)} partition(s) are "
                f"tagged 'terminal' (exactly one required)"
            ]
        t = terminals[0]
        for p in PARTITIONS:
            if p < t and states[p] != "present":
                return None, [f"partition {p} precedes the terminal partition {t} but is not "
                              f"tagged 'present'"]
            if p > t and states[p] != "absent_after_terminal":
                return None, [f"partition {p} follows the terminal partition {t} but is not "
                              f"tagged 'absent_after_terminal'"]

    present_like = [p for p in PARTITIONS if states[p] in ("present", "terminal")]

    body_lines = lines[1:]
    cursor = 0
    segments: dict[int, list[str]] = {}
    for p in present_like:
        entry = partitions_table[str(p)]
        n = entry.get("raw_line_count")
        if not isinstance(n, int) or n < 1:
            return None, [f"partition {p}'s provenance entry carries no usable raw_line_count"]
        segment = body_lines[cursor: cursor + n]
        if len(segment) != n:
            return None, [f"the bundle does not contain {n} raw line(s) for partition {p}"]
        cursor += n
        segment_text = "\n".join(segment) + "\n"
        got = hashlib.sha256(segment_text.encode("utf-8")).hexdigest()
        if got != entry.get("sha256"):
            return None, [
                f"partition {p}'s segment digest does not match the bundle's own bytes "
                f"(recomputed sha256 mismatch)"
            ]
        segments[p] = segment
    if cursor != len(body_lines):
        return None, [
            f"the bundle carries {len(body_lines) - cursor} raw line(s) not claimed by any "
            f"partition segment"
        ]

    ledger = Ledger(ledger_path)
    try:
        ledger_entries = ledger.entries()
    except LedgerUnusable as exc:
        return None, [f"ledger unusable: {exc}"]

    all_raw_records: list[dict] = []
    observation_lines: list[str] = []
    for p in present_like:
        try:
            seg_raw_lines, seg_records = _parse_jsonl_text(f"partition {p} segment", "\n".join(segments[p]))
        except ValueError as exc:
            return None, [str(exc)]
        pf = PartitionFile(p, seg_raw_lines, seg_records)
        manifest_order = [o.observation_id for o in runner.base.load_manifest(manifest_paths[p])]
        state, why = _classify_partition_file(pf, manifest_order)
        if state is None or state != states[p]:
            reasons.extend(why or [
                f"partition {p}'s reconstructed shape does not match its declared state "
                f"{states[p]!r}"
            ])
            continue

        availability_record = seg_records[0] if seg_records and seg_records[0].get("record_type") == "availability" else None
        observation_records = [r for r in seg_records if r.get("record_type") == "observation"]
        reasons.extend(reconcile_partition_ledger(p, availability_record, observation_records, ledger_entries))

        w = partition_ledger_window(p, ledger_entries)
        if w is None:
            reasons.append(f"partition {p}: no ledger entries at all for this partition; cannot "
                           f"independently verify its declared timestamp window")
        else:
            declared_start = partitions_table[str(p)].get("ledger_start")
            declared_end = partitions_table[str(p)].get("ledger_end")
            if declared_start is not None and declared_start != _iso(w[0]):
                reasons.append(f"partition {p}: declared ledger_start does not equal the "
                               f"independently-derived value from the current ledger")
            if declared_end is not None and declared_end != _iso(w[1]):
                reasons.append(f"partition {p}: declared ledger_end does not equal the "
                               f"independently-derived value from the current ledger")

        all_raw_records.extend(seg_records)
        for ln, rec in zip(seg_raw_lines, seg_records):
            if rec.get("record_type") == "observation":
                observation_lines.append(ln)

    reasons.extend(verify_isolation_gaps(present_like, ledger_entries))
    if reasons:
        return None, reasons

    reasons.extend(verify_absent_partitions_are_truly_unrun(states, ledger_entries))
    if reasons:
        return None, reasons

    observation_text = ("\n".join(observation_lines) + "\n") if observation_lines else ""
    return ValidatedBundle(
        raw_bytes=raw_bytes,
        provenance=provenance,
        raw_records=all_raw_records,
        observation_text=observation_text,
    ), []


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--p1")
    ap.add_argument("--p2")
    ap.add_argument("--p3")
    ap.add_argument("--p4")
    ap.add_argument("--out", required=True, help="where to write the evidence bundle")
    args = ap.parse_args(argv)

    partition_paths: dict[int, Path] = {}
    for i, raw in enumerate((args.p1, args.p2, args.p3, args.p4), start=1):
        if raw:
            partition_paths[i] = Path(raw)

    bundle, reasons = aggregate(partition_paths)
    if bundle is None:
        print("REFUSED: no evidence bundle was written.")
        for r in reasons:
            print("  " + r)
        return 1

    Path(args.out).write_bytes(bundle)
    print(f"evidence bundle written to {args.out} ({len(bundle)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
