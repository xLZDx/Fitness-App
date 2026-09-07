"""RECOG-SO1 scorer: apply the pre-registered bars, and nothing else.

This program decides PASS / FAIL / INCONCLUSIVE by criteria that were fixed
before any Qwen output existed. It has no thresholds of its own to offer and no
discretion to exercise: every number it compares against comes from
`RECOG_SO1_PREREGISTRATION_2026-09-07.md`, which GPT-PM wrote and approved.

THE HYPOTHESIS. RECOG-C1 established that the recogniser's own self-report
carries no abstention signal: across 104 observations it never answered
`unknown`, and neither confidence, nor the lead over the second candidate, nor
the number of alternatives separated the frames that HAVE a single right answer
from the frames that do not. SO1 asks whether a SECOND, INDEPENDENT model
supplies from outside what the first model cannot supply about itself: do the
two models disagree more often on frames where no single machine is the subject
than on frames where one is?

  D                 the two models do not name the same equipment
  D_multiple        D over frames whose frozen ground truth is `multiple`
  D_canonical       D over frames whose frozen ground truth is `canonical_single`
  delta             D_multiple - D_canonical, in percentage points

THREE RULES THAT DECIDE MORE THAN THE THRESHOLDS DO.

1. Comparison is on RESOLVED equipment identity, never raw strings. The frozen
   vocabulary maps "plyo box" and "aerobic step" to the same `plyo_box`, and
   "parallettes" and "push-up blocks" to the same `parallettes`. Scoring the
   strings would manufacture two disagreement classes that are agreements. Raw
   strings are still reported, for audit.

2. An unresolved observation counts AGAINST the signal. In the `multiple`
   stratum it is scored as agreement (lowering D_multiple); in the
   `canonical_single` stratum as disagreement (raising D_canonical). Both push
   delta down. A run that fails to get answers must not be rewarded with a
   result. An invalid reply is never read as an abstention -- `unknown` is an
   abstention and is scored as such; a reply that would not parse is a failure.

3. Inference clusters by SOURCE PHOTOGRAPH. 104 observations are 52 scenes seen
   twice, not 104 independent samples, and the frozen ground truth confirms the
   kind is a property of the photograph: all 52 sources carry the same kind in
   both arms. The permutation test therefore permutes source-level labels,
   carrying both arms of a source together.
"""

from __future__ import annotations

import argparse
import csv
import json
import random
import re
import statistics
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PLANS = REPO / "core" / "plans"
DEV = REPO / "scripts" / "dev"

GROUND_TRUTH = PLANS / "RECOG_C1_GROUND_TRUTH_2026-09-05.csv"
GEMINI_RAW = [PLANS / "recog_c1_raw" / f"recog_c1_raw_{w}.jsonl" for w in ("w1", "w2")]
VOCAB = DEV / "recog_so1_vocab.json"

# ---- the pre-registered bars. Changing a number here without changing the
# ---- pre-registration document is a protocol violation, not a tuning choice.
PASS_D_MULTIPLE_MIN = 0.60
PASS_D_CANONICAL_MAX = 0.20
PASS_DELTA_MIN_PP = 40.0
PASS_P_MAX = 0.05

FAIL_D_MULTIPLE_BELOW = 0.50
FAIL_D_CANONICAL_ABOVE = 0.25
FAIL_DELTA_BELOW_PP = 25.0
FAIL_QWEN_ACCURACY_BELOW = 0.80
FAIL_QWEN_WORSE_THAN_GEMINI_PP = 10.0

MIN_UNIQUE_SOURCES_PER_KIND = 20

PERMUTATIONS = 20000
PERMUTATION_SEED = 20260907

UNKNOWN = "unknown"


# --------------------------------------------------------------------------
# Vocabulary resolution -- the same port production uses
# --------------------------------------------------------------------------

_NON_TOKEN = re.compile(r"[^a-zа-я0-9]+")


def normalise(s: str) -> str:
    return _NON_TOKEN.sub(" ", s.lower().replace("ё", "е")).strip()


def resolve(free_text: str, index: dict[str, str]) -> str | None:
    text = normalise(free_text)
    if not text:
        return None
    direct = index.get(text)
    if direct is not None:
        return direct
    best_id, best_len = None, 0
    padded = f" {text} "
    for alias, equipment_id in index.items():
        if len(alias) <= best_len:
            continue
        if f" {alias} " in padded:
            best_id, best_len = equipment_id, len(alias)
    return best_id


# --------------------------------------------------------------------------
# Observations
# --------------------------------------------------------------------------

@dataclass
class Row:
    observation_id: str
    source_photo_id: str
    arm: str
    kind: str
    gt_equipment_id: str
    gemini_id: str | None
    gemini_raw: str | None
    qwen_id: str | None
    qwen_raw: str | None
    qwen_status: str          # answered | unresolved
    qwen_failure: str | None

    @property
    def unresolved(self) -> bool:
        return self.qwen_status != "answered"

    def disagrees(self) -> bool:
        """Do the two models fail to name the same equipment?

        The conservative rule lives here, in one place, so that removing it is a
        one-line mutation the test suite can perform and observe.
        """
        if self.unresolved:
            # Counts against the signal in whichever direction hurts delta.
            return self.kind == "canonical_single"
        if self.qwen_raw and self.qwen_raw.strip().lower() == UNKNOWN:
            # An explicit abstention by the second model IS a disagreement with
            # a first model that named something -- unless both abstained.
            return not (self.gemini_raw and self.gemini_raw.strip().lower() == UNKNOWN)
        if self.gemini_id is None or self.qwen_id is None:
            return True
        return self.gemini_id != self.qwen_id


def load_rows(so1_jsonl: Path, cluster_by_observation: bool = False) -> list[Row]:
    vocab = json.loads(VOCAB.read_text("utf-8"))
    index: dict[str, str] = vocab["alias_to_equipment_id"]

    gt: dict[tuple[str, str], dict] = {}
    for r in csv.DictReader(GROUND_TRUTH.read_text("utf-8").splitlines()):
        gt[(r["image_id"], r["arm"])] = r

    gemini: dict[tuple[str, str], dict] = {}
    for path in GEMINI_RAW:
        for line in path.read_text("utf-8").splitlines():
            d = json.loads(line)
            if d.get("record_type") != "observation":
                continue
            gemini[(d["image_id"], d["arm"])] = d

    rows: list[Row] = []
    for line in so1_jsonl.read_text("utf-8").splitlines():
        if not line.strip():
            continue
        d = json.loads(line)
        source, arm = d["source_photo_id"], d["arm"]
        g = gt.get((source, arm))
        if g is None:
            raise SystemExit(f"{d['observation_id']}: no frozen ground truth for this observation")
        gm = gemini.get((source, arm)) or {}
        cands = gm.get("candidates") or []
        gemini_id = cands[0]["equipment_id"] if cands else None
        gemini_raw = cands[0].get("raw_name") if cands else None

        qwen_raw = d.get("machine_raw")
        qwen_id = resolve(qwen_raw, index) if qwen_raw and qwen_raw.strip().lower() != UNKNOWN else None
        rows.append(
            Row(
                observation_id=d["observation_id"],
                source_photo_id=source,
                arm=arm,
                kind=g["gt_kind"],
                gt_equipment_id=g.get("canonical_equipment_id") or "",
                gemini_id=gemini_id,
                gemini_raw=gemini_raw,
                qwen_id=qwen_id,
                qwen_raw=qwen_raw,
                qwen_status=d.get("status", "unresolved"),
                qwen_failure=d.get("failure"),
            )
        )
    return rows


# --------------------------------------------------------------------------
# Statistics
# --------------------------------------------------------------------------

def rate(rows: list[Row], kind: str) -> tuple[float, int]:
    subset = [r for r in rows if r.kind == kind]
    if not subset:
        return float("nan"), 0
    return sum(1 for r in subset if r.disagrees()) / len(subset), len(subset)


def delta_pp(rows: list[Row]) -> float:
    d_multi, _ = rate(rows, "multiple")
    d_canon, _ = rate(rows, "canonical_single")
    return (d_multi - d_canon) * 100.0


def unique_sources(rows: list[Row], kind: str, arm: str | None = None) -> int:
    return len({r.source_photo_id for r in rows if r.kind == kind and (arm is None or r.arm == arm)})


def _bits_under_each_label(row: Row) -> tuple[bool, bool]:
    """(disagrees if labelled canonical_single, disagrees if labelled multiple).

    `Row.disagrees()` reads `kind` only through the conservative unresolved
    rule, so a row's outcome under a hypothetical label is fully determined by
    these two booleans. Precomputing them turns the permutation loop from two
    million object constructions into arithmetic, and -- more importantly --
    keeps the conservative rule in ONE place: this helper asks `disagrees()`
    rather than restating it, so the mutation that removes the rule still
    reaches the permutation test.
    """
    def as_kind(kind: str) -> bool:
        clone = Row(row.observation_id, row.source_photo_id, row.arm, kind, row.gt_equipment_id,
                    row.gemini_id, row.gemini_raw, row.qwen_id, row.qwen_raw,
                    row.qwen_status, row.qwen_failure)
        return clone.disagrees()

    return as_kind("canonical_single"), as_kind("multiple")


def permutation_p(rows: list[Row], cluster_by_observation: bool = False) -> tuple[float, float]:
    """One-sided p for delta > 0, permuting labels at the SOURCE level.

    `cluster_by_observation` exists so the test suite can weaken the clustering
    on purpose and watch the p-value collapse. It is never used in a real run --
    treating 104 observations as 104 independent samples doubles the apparent
    sample size for free, which is precisely the error this design avoids.
    """
    observed = delta_pp(rows)
    rng = random.Random(PERMUTATION_SEED)

    if cluster_by_observation:
        units: list[list[Row]] = [[r] for r in rows]
    else:
        by_source: dict[str, list[Row]] = defaultdict(list)
        for r in rows:
            by_source[r.source_photo_id].append(r)
        units = list(by_source.values())
    # One label per unit. At source level the frozen ground truth licenses this:
    # all 52 sources carry the same kind in both arms.
    labels = [group[0].kind for group in units]
    bits = [[_bits_under_each_label(r) for r in group] for group in units]

    ge = 0
    for _ in range(PERMUTATIONS):
        shuffled = labels[:]
        rng.shuffle(shuffled)
        c_dis = c_n = m_dis = m_n = 0
        for group_bits, label in zip(bits, shuffled):
            if label == "multiple":
                for _c, m in group_bits:
                    m_n += 1
                    m_dis += m
            else:
                for c, _m in group_bits:
                    c_n += 1
                    c_dis += c
        if not c_n or not m_n:
            continue
        if (m_dis / m_n - c_dis / c_n) * 100.0 >= observed:
            ge += 1
    return (ge + 1) / (PERMUTATIONS + 1), observed


def competence(rows: list[Row]) -> tuple[float, float, int]:
    """Top-1 accuracy against frozen ground truth on `canonical_single` only.

    A second opinion from a model that cannot recognise equipment is noise, not
    evidence -- which is why GPT-PM made this a FAIL condition rather than a
    footnote.
    """
    subset = [r for r in rows if r.kind == "canonical_single" and r.gt_equipment_id]
    if not subset:
        return float("nan"), float("nan"), 0
    qwen = sum(1 for r in subset if r.qwen_id == r.gt_equipment_id) / len(subset)
    gem = sum(1 for r in subset if r.gemini_id == r.gt_equipment_id) / len(subset)
    return qwen, gem, len(subset)


# --------------------------------------------------------------------------
# The verdict
# --------------------------------------------------------------------------

def verdict(
    rows: list[Row],
    enforce_power_floor: bool = True,
    cluster_by_observation: bool = False,
) -> tuple[str, list[str]]:
    reasons: list[str] = []
    d_multi, n_multi = rate(rows, "multiple")
    d_canon, n_canon = rate(rows, "canonical_single")
    p, delta = permutation_p(rows, cluster_by_observation)
    q_acc, g_acc, n_comp = competence(rows)

    arms = sorted({r.arm for r in rows})
    per_arm = {a: delta_pp([r for r in rows if r.arm == a]) for a in arms}

    # --- the power floor, which can override a numerically passing result ---
    if enforce_power_floor:
        underpowered = []
        for arm in arms:
            for kind in ("canonical_single", "multiple"):
                n = unique_sources(rows, kind, arm)
                if n < MIN_UNIQUE_SOURCES_PER_KIND:
                    underpowered.append(f"arm {arm} {kind}: {n} unique source photographs "
                                        f"(< {MIN_UNIQUE_SOURCES_PER_KIND})")
        if underpowered:
            reasons.append("the dataset is underpowered, so no PASS or FAIL may be claimed from it:")
            reasons.extend("  " + u for u in underpowered)
            return "INCONCLUSIVE", reasons

    # --- FAIL conditions, checked first: any one of them decides -----------
    fails: list[str] = []
    if d_multi < FAIL_D_MULTIPLE_BELOW:
        fails.append(f"D_multiple {d_multi:.1%} < {FAIL_D_MULTIPLE_BELOW:.0%}")
    if d_canon > FAIL_D_CANONICAL_ABOVE:
        fails.append(f"D_canonical {d_canon:.1%} > {FAIL_D_CANONICAL_ABOVE:.0%}")
    if delta < FAIL_DELTA_BELOW_PP:
        fails.append(f"delta {delta:.1f} pp < {FAIL_DELTA_BELOW_PP:.0f} pp")
    if q_acc == q_acc and q_acc < FAIL_QWEN_ACCURACY_BELOW:
        fails.append(f"Qwen canonical top-1 {q_acc:.1%} < {FAIL_QWEN_ACCURACY_BELOW:.0%}")
    if q_acc == q_acc and g_acc == g_acc and (g_acc - q_acc) * 100 > FAIL_QWEN_WORSE_THAN_GEMINI_PP:
        fails.append(f"Qwen is {(g_acc - q_acc) * 100:.1f} pp worse than Gemini "
                     f"(> {FAIL_QWEN_WORSE_THAN_GEMINI_PP:.0f} pp)")
    reversed_arms = [a for a, d in per_arm.items() if d < 0]
    if reversed_arms:
        fails.append(f"the direction reverses in arm(s) {reversed_arms}: "
                     + ", ".join(f"{a} delta {per_arm[a]:.1f} pp" for a in reversed_arms))
    if fails:
        reasons.append("FAIL conditions met:")
        reasons.extend("  " + f for f in fails)
        return "FAIL", reasons

    # --- PASS requires all five ------------------------------------------
    passes = {
        f"D_multiple {d_multi:.1%} >= {PASS_D_MULTIPLE_MIN:.0%}": d_multi >= PASS_D_MULTIPLE_MIN,
        f"D_canonical {d_canon:.1%} <= {PASS_D_CANONICAL_MAX:.0%}": d_canon <= PASS_D_CANONICAL_MAX,
        f"delta {delta:.1f} pp >= {PASS_DELTA_MIN_PP:.0f} pp": delta >= PASS_DELTA_MIN_PP,
        "direction holds in both arms": all(d > 0 for d in per_arm.values()),
        f"clustered permutation p {p:.4f} < {PASS_P_MAX}": p < PASS_P_MAX,
    }
    for label, ok in passes.items():
        reasons.append(f"  {'yes' if ok else 'NO '}  {label}")
    if all(passes.values()):
        return "PASS", reasons
    reasons.insert(0, "neither the PASS bar nor any FAIL condition is met:")
    reasons.append("INCONCLUSIVE is a real outcome. It is NOT permission to tune on these same "
                   "52 photographs -- a threshold chosen after seeing them is not a threshold.")
    return "INCONCLUSIVE", reasons


def report(rows: list[Row], enforce_power_floor: bool = True, cluster_by_observation: bool = False) -> str:
    out: list[str] = []
    d_multi, n_multi = rate(rows, "multiple")
    d_canon, n_canon = rate(rows, "canonical_single")
    q_acc, g_acc, n_comp = competence(rows)
    p, delta = permutation_p(rows, cluster_by_observation)

    out.append(f"observations                {len(rows)}  across {len({r.source_photo_id for r in rows})} source photographs")
    out.append(f"  D_multiple                {d_multi:.1%}  (n={n_multi}, "
               f"{unique_sources(rows, 'multiple')} unique sources)")
    out.append(f"  D_canonical               {d_canon:.1%}  (n={n_canon}, "
               f"{unique_sources(rows, 'canonical_single')} unique sources)")
    out.append(f"  delta                     {delta:.1f} pp")
    out.append(f"  clustered permutation p   {p:.4f}  ({PERMUTATIONS} permutations, source-level)")
    out.append("")
    for arm in sorted({r.arm for r in rows}):
        sub = [r for r in rows if r.arm == arm]
        dm, _ = rate(sub, "multiple")
        dc, _ = rate(sub, "canonical_single")
        out.append(f"  arm {arm}: D_multiple {dm:.1%}   D_canonical {dc:.1%}   delta {delta_pp(sub):.1f} pp")
    out.append("")
    out.append(f"  Qwen canonical top-1      {q_acc:.1%}   Gemini {g_acc:.1%}   (n={n_comp})")

    unresolved = [r for r in rows if r.unresolved]
    out.append(f"  unresolved                {len(unresolved)}")
    if unresolved:
        for failure, n in Counter(r.qwen_failure or "unknown" for r in unresolved).most_common():
            out.append(f"    {failure}: {n}")
    qwen_unknown = sum(1 for r in rows if r.qwen_raw and r.qwen_raw.strip().lower() == UNKNOWN)
    gem_unknown = sum(1 for r in rows if r.gemini_raw and r.gemini_raw.strip().lower() == UNKNOWN)
    out.append(f"  answered 'unknown'        Qwen {qwen_unknown}   Gemini {gem_unknown}")

    v, reasons = verdict(rows, enforce_power_floor, cluster_by_observation)
    out.append("")
    out.append(f"VERDICT: {v}")
    out.extend(reasons)
    return "\n".join(out)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--so1", required=True, help="the runner's JSONL output")
    ap.add_argument("--disagreement-pairs", action="store_true", help="print every disagreement, raw and resolved")
    args = ap.parse_args(argv)

    rows = load_rows(Path(args.so1))
    print(report(rows))

    if args.disagreement_pairs:
        print("\ndisagreements (raw strings shown for audit; scoring used the resolved ids):")
        for r in rows:
            if r.disagrees() and not r.unresolved:
                print(f"  [{r.kind:16s} {r.arm}] gemini {r.gemini_raw!r} -> {r.gemini_id}"
                      f"   qwen {r.qwen_raw!r} -> {r.qwen_id}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
