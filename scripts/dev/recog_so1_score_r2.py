"""RECOG-SO1 revision 2 scorer: decide whether there is anything to score AT ALL, first.

Revision 1's scorer had the right thresholds in the wrong order. `verdict()`
computed the disagreement rates, the delta, the clustered permutation p and the
competence figures, and only THEN reached the power floor that was supposed to
stop an underpowered dataset from producing a verdict. And the floor it reached
counted manifest ROWS: it reported 26 unique sources per arm and kind for a run
in which 58 of 104 observations carried no reply at all. The safeguard against
exactly the situation that occurred could not fire, and the statistics it was
meant to guard had already been computed before it was consulted.

Two structural changes, and nothing else:

  1.  `run_validity()` runs FIRST, in both `verdict()` and `report()`, and both
      return from inside it. Not "the statistics are computed but not printed" --
      proving no statistics by reading rendered text proves only that nothing
      was printed. The suite replaces `rate`, `delta_pp`, `permutation_p` and
      `competence` with spies that RAISE, on the module where they actually
      execute, and requires an invalid fixture to complete with zero calls to
      all four -- and a valid fixture to reach all four, so the assertion is
      known to be able to fail.

  2.  The floor counts ANSWERS, in BOTH arms, per source photograph. A 429, a
      timeout, a 5xx or a reply that will not parse does not become coverage
      merely because a manifest row exists for it.

TWO OUTCOMES THAT ARE NOT VERDICTS.

  INVALID_INSTRUMENT   a provider, configuration or quota failure makes the
                       measurement structurally invalid. NO hypothesis statistic
                       is produced -- not computed-and-withheld, not
                       reported-with-caveats. There is nothing to caveat.

  INCONCLUSIVE         execution was valid; there were simply too few valid
                       answers, or the numbers met neither the PASS bar nor any
                       FAIL condition.

THE ARITHMETIC ITSELF IS UNCHANGED, AND IS THE SAME CODE. `rate`, `delta_pp`,
`permutation_p`, `competence` and the PASS/FAIL thresholds are imported from the
revision 1 scorer, which is sealed and unedited. Re-implementing them here would
have made "the hypothesis did not move" a claim; importing them makes it a
property. Revision 1's own file is never modified, so its seal still verifies
and run #1 remains judgeable by the protocol it actually ran under.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEV = REPO / "scripts" / "dev"
PLANS = REPO / "core" / "plans"

CONFIG_R2 = DEV / "recog_so1_config_r2.json"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


#: The sealed revision 1 scorer. Imported, never edited.
base = _load_module("so1_score_base", DEV / "recog_so1_score.py")

# Re-exported for callers' convenience. The ordering test does NOT patch these
# copies: the arithmetic actually executes inside `base`, so the spies are
# installed on `base.rate`, `base.delta_pp`, `base.permutation_p` and
# `base.competence` -- the names that are really reached. Patching the copies
# here would have produced a test that passes because nothing ever calls them,
# which is a vacuous control rather than evidence. The same suite therefore also
# runs a VALID fixture through the spies and requires all four to FIRE, so the
# zero-call assertion is known to be capable of failing.
Row = base.Row
resolve = base.resolve
load_rows = base.load_rows
rate = base.rate
delta_pp = base.delta_pp
permutation_p = base.permutation_p
competence = base.competence
unique_sources = base.unique_sources

VALID = "VALID"
INVALID_INSTRUMENT = "INVALID_INSTRUMENT"
INCONCLUSIVE = "INCONCLUSIVE"

#: Both arms of a source photograph. A "complete answered pair" needs both.
ARMS = ("A", "B")


def _config() -> dict:
    return json.loads(CONFIG_R2.read_text("utf-8"))


def min_answered_sources() -> int:
    return int(_config()["coverage_floor"]["min_unique_sources_with_answers_in_both_arms"])


# --------------------------------------------------------------------------
# Coverage that counts answers, not rows
# --------------------------------------------------------------------------

def answered_sources(rows: list[Row], kind: str) -> int:
    """Source photographs with a valid parsed answer in BOTH arms.

    Deliberately beside `unique_sources`, which counts rows, so a report can
    print the two side by side and the difference between them is visible
    rather than inferred. In run #1 that difference was 26 against 6.
    """
    by_source: dict[str, dict[str, bool]] = defaultdict(dict)
    for r in rows:
        if r.kind != kind:
            continue
        by_source[r.source_photo_id][r.arm] = not r.unresolved
    return sum(
        1
        for arms in by_source.values()
        if all(arms.get(arm, False) for arm in ARMS)
    )


# --------------------------------------------------------------------------
# Validity, which precedes every statistic
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class Validity:
    outcome: str
    reasons: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return self.outcome == VALID


def invalid_markers(raw_records: list[dict]) -> list[str]:
    """Every INVALID_INSTRUMENT class the runner recorded, in order of appearance."""
    seen: list[str] = []
    for d in raw_records:
        marker = d.get("invalid_instrument")
        if marker and marker not in seen:
            seen.append(marker)
    return seen


def run_validity(rows: list[Row], raw_records: list[dict]) -> Validity:
    """Is this run scoreable at all? Computed WITHOUT touching any statistic.

    Every input to this function is a count or a recorded failure class. It
    reads no disagreement rate, no delta, no p-value and no competence figure,
    which is what lets it run before all four of them.
    """
    markers = invalid_markers(raw_records)
    if markers:
        return Validity(
            INVALID_INSTRUMENT,
            [
                "the run recorded a structurally invalidating failure, so no hypothesis "
                "statistic may be computed from it:",
                *(f"  {m}" for m in markers),
                "INVALID_INSTRUMENT is not PASS, not FAIL and not INCONCLUSIVE. It says the "
                "instrument failed, not that the hypothesis was tested and came out ambiguous.",
            ],
        )

    if not rows:
        return Validity(INVALID_INSTRUMENT, ["the run produced no observations at all"])

    floor = min_answered_sources()
    thin: list[str] = []
    for kind in ("canonical_single", "multiple"):
        n = answered_sources(rows, kind)
        if n < floor:
            thin.append(
                f"  {kind}: {n} source photographs answered in BOTH arms "
                f"(< {floor}); {unique_sources(rows, kind)} rows exist for it"
            )
    if thin:
        return Validity(
            INCONCLUSIVE,
            [
                "too few source photographs carry a valid answer in both arms, so no PASS or "
                "FAIL may be claimed:",
                *thin,
                "A manifest row is not an answer. This floor counts replies.",
            ],
        )

    return Validity(VALID, [f"{len(rows)} observations, coverage floor {floor} met in both kinds"])


# --------------------------------------------------------------------------
# The verdict -- reached only through validity
# --------------------------------------------------------------------------

def verdict(
    rows: list[Row],
    raw_records: list[dict],
    enforce_power_floor: bool = True,
    cluster_by_observation: bool = False,
) -> tuple[str, list[str]]:
    """PASS / FAIL / INCONCLUSIVE / INVALID_INSTRUMENT.

    The validity gate is the FIRST statement and returns from inside itself. No
    statistic exists above this line for a caller to accidentally read.
    """
    if enforce_power_floor:
        validity = run_validity(rows, raw_records)
        if not validity.ok:
            return validity.outcome, list(validity.reasons)

    # Below this line the run is known to be scoreable. Revision 1's own
    # thresholds and arithmetic decide it, unchanged and unre-implemented.
    return base.verdict(rows, enforce_power_floor=False, cluster_by_observation=cluster_by_observation)


def report(
    rows: list[Row],
    raw_records: list[dict],
    enforce_power_floor: bool = True,
    cluster_by_observation: bool = False,
) -> str:
    """The same gate, in the same position, for the rendered report.

    Revision 1 repeated the statistics here independently of `verdict()`, so
    fixing only the verdict would have left the report computing them anyway.
    """
    if enforce_power_floor:
        validity = run_validity(rows, raw_records)
        if not validity.ok:
            out = [
                f"observations                {len(rows)}",
                f"  answered in both arms     canonical_single "
                f"{answered_sources(rows, 'canonical_single')}   "
                f"multiple {answered_sources(rows, 'multiple')}",
                "",
            ]
            unresolved = [r for r in rows if r.unresolved]
            if unresolved:
                out.append(f"  unresolved                {len(unresolved)}")
                for failure, n in Counter(r.qwen_failure or "unknown" for r in unresolved).most_common():
                    out.append(f"    {failure}: {n}")
                out.append("")
            out.append(f"VERDICT: {validity.outcome}")
            out.extend(validity.reasons)
            out.append("")
            out.append(
                "No disagreement rate, delta, permutation p or competence figure appears above, "
                "and none was computed: this report returned before reaching them."
            )
            return "\n".join(out)

    body = base.report(rows, enforce_power_floor=False, cluster_by_observation=cluster_by_observation)
    extra = (
        f"  answered in both arms     canonical_single {answered_sources(rows, 'canonical_single')}   "
        f"multiple {answered_sources(rows, 'multiple')}"
    )
    lines = body.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("  D_canonical"):
            lines.insert(i + 1, extra)
            break
    else:
        lines.insert(1, extra)
    return "\n".join(lines)


# --------------------------------------------------------------------------
# Loading
# --------------------------------------------------------------------------

def load_raw(so1_jsonl: Path) -> list[dict]:
    out: list[dict] = []
    for line in so1_jsonl.read_text("utf-8").splitlines():
        if line.strip():
            out.append(json.loads(line))
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--so1", required=True, help="the runner's JSONL output")
    args = ap.parse_args(argv)

    path = Path(args.so1)
    raw = load_raw(path)
    rows = load_rows(path)
    print(report(rows, raw))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
