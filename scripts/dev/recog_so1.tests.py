# RECOG-SO1: the evidence that the guards are load-bearing, not decorative.
#
# Run:  py -3 scripts/dev/recog_so1.tests.py
#
# NO NETWORK CALL IS MADE ANYWHERE IN THIS FILE. Every runner test injects a
# capturing transport; the one test that proves a denial never builds a client
# injects a factory that records its own construction, so "no request was sent"
# is shown rather than assumed.
#
# The suite follows the convention set by recog_c1_build_correlation.tests.py in
# this directory, including its closing argument: a check that cannot fail
# proves nothing. So each guard is shown REFUSING on a mutation, and the three
# statistical guards are additionally shown to let the bad fixture through once
# the guard itself is removed -- if disabling a rule changes no verdict, the rule
# was never deciding anything.
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEV = REPO / "scripts" / "dev"


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


run_mod = load("so1_run", DEV / "recog_so1_run.py")
score = load("so1_score", DEV / "recog_so1_score.py")

# 2000 keeps the suite quick. It only coarsens the p-value's resolution; every
# fixture below is planted far from the 0.05 boundary, so no verdict here turns
# on the difference between 2000 and the 20000 a real run uses.
score.PERMUTATIONS = 2000

RESULTS: list[tuple[bool, str]] = []


def check(ok: bool, label: str, detail: str = "") -> None:
    RESULTS.append((ok, label))
    print(f"{'PASS' if ok else 'FAIL'}  {label}")
    if not ok and detail:
        print(f"        {detail}")


# ==========================================================================
# 1. The vocabulary is production's, not a retyping of it
# ==========================================================================
print("\n--- 1. vocabulary derivation (GPT-PM MAJOR 3) ---")

vocab = json.loads((DEV / "recog_so1_vocab.json").read_text("utf-8"))
alias_index: dict[str, str] = vocab["alias_to_equipment_id"]
machines: list[str] = vocab["canonical_machines"]

unresolved = [m for m in machines if score.resolve(m, alias_index) is None]
check(not unresolved, "every canonical prompt name resolves to an equipment id", f"unresolved: {unresolved}")

resolved_once = all(isinstance(score.resolve(m, alias_index), str) for m in machines)
check(resolved_once, "resolution returns exactly one id per canonical name, never a set")

check(score.resolve("unknown", alias_index) is None,
      "the sentinel 'unknown' resolves to nothing, so an abstention cannot become a named answer")

# The case GPT-PM's own G1 round-1 review used to disprove "pass 1 is enough".
check(score.resolve("hip abductor machine", alias_index) is not None
      and "hip abductor machine" not in alias_index,
      "'hip abductor machine' is not itself an alias and resolves only through pass 2")

# The punctuation-folding case that a bare toLowerCase().trim() would break.
check(score.normalise("hip abductor / adductor machine") == "hip abductor adductor machine",
      "punctuation folds to single spaces, as EquipmentAliasIndex.normalise does")
check(score.normalise("Гакк-Машина!") == "гакк машина" and score.normalise("ёлка") == "елка",
      "cyrillic lowercasing and the ё->е fold match production")

rc = subprocess.run([sys.executable, str(DEV / "recog_so1_build_vocab.py"), "--check"],
                    capture_output=True, text=True, cwd=REPO)
check(rc.returncode == 0, "the vocabulary regenerates byte-identically from production",
      rc.stdout + rc.stderr)

rc = subprocess.run([sys.executable, str(DEV / "recog_so1_build_prompt.py"), "--check"],
                    capture_output=True, text=True, cwd=REPO)
check(rc.returncode == 0, "the frozen prompt still matches production's buildPrompt() exactly",
      rc.stdout + rc.stderr)

# ---- cross-language: the Python port vs the TypeScript port ---------------
# Both are ports of the same Dart original. Neither is retyped here: the JS
# below is EXTRACTED from the shipped test file, so if that port is edited this
# check follows it rather than drifting from it.
TS_TEST = REPO / "functions" / "src" / "__tests__" / "ai_equipment_recognition.test.ts"
ts_src = TS_TEST.read_text("utf-8")
m_norm = re.search(r"const normalise = \(s: string\) =>(.*?);\n", ts_src, re.S)
m_res = re.search(r"function resolve\(freeText: string\): string \| undefined \{(.*?)\n  \}\n", ts_src, re.S)
if not (m_norm and m_res):
    check(False, "the TypeScript port could be located for cross-checking",
          "anchors not found in ai_equipment_recognition.test.ts")
else:
    # Strip the type annotations only. `.replace(": string", "")` is not enough:
    # the body declares `let bestId: string | undefined;`, which that leaves as
    # `let bestId: | undefined;` -- a syntax error, and one that would have made
    # this whole cross-check silently unavailable rather than loudly wrong.
    body = re.sub(r":\s*string(\s*\|\s*undefined)?", "", m_res.group(1))
    js = (
        "const normalise = (s) =>" + m_norm.group(1) + ";\n"
        "const aliasToId = new Map(Object.entries(JSON.parse(process.argv[2])));\n"
        "function resolve(freeText) {" + body + "\n}\n"
        "const names = JSON.parse(process.argv[3]);\n"
        "console.log(JSON.stringify(names.map((n) => resolve(n) ?? null)));\n"
    )
    with tempfile.TemporaryDirectory() as td:
        jsf = Path(td) / "port.mjs"
        jsf.write_text(js, encoding="utf-8")
        probes = machines + ["unknown", "hip abductor / adductor machine", "Гакк-Машина!",
                            "looks like a smith machine to me", "", "   ", "seated leg curl"]
        proc = subprocess.run(
            ["node", str(jsf), json.dumps(alias_index, ensure_ascii=False), json.dumps(probes, ensure_ascii=False)],
            capture_output=True, text=True, encoding="utf-8",
        )
        if proc.returncode != 0:
            check(False, "the TypeScript port runs", proc.stderr[:400])
        else:
            ts_out = json.loads(proc.stdout)
            py_out = [score.resolve(p, alias_index) for p in probes]
            mismatch = [(p, t, y) for p, t, y in zip(probes, ts_out, py_out) if t != y]
            check(not mismatch,
                  f"the Python port agrees with the shipped TypeScript port on all {len(probes)} probes",
                  f"mismatches: {mismatch[:5]}")


# ==========================================================================
# 2. Consent is affirmative authorisation, not a well-formed answer
# ==========================================================================
print("\n--- 2. the consent state machine (GPT-PM BLOCKER 1) ---")

MANIFEST_DIGEST = "a" * 64
PREREG_DIGEST = "b" * 64

GOOD = {
    "decision": "whole_corpus",
    "recorded_at": "2026-09-07",
    "operator_statement": "весь корпус (52 фото, максимальная статистическая сила)",
    "manifest_sha256": MANIFEST_DIGEST,
    "preregistration_sha256": PREREG_DIGEST,
    "groq_data_controls": {"global_zdr": "enabled", "recorded_from": "console screenshot",
                           "recorded_at": "2026-09-07"},
}


def consent_verdict(record, *, write=True, raw=None):
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / "RECOG_SO1_CONSENT.json"
        if raw is not None:
            p.write_text(raw, encoding="utf-8")
        elif write:
            p.write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
        return run_mod.evaluate_consent(p, MANIFEST_DIGEST, PREREG_DIGEST)


check(consent_verdict(GOOD).authorised, "a fully-bound affirmative record AUTHORISES")

REFUSAL_CASES = [
    ("absent file", dict(write=False, record=None)),
    ("unparseable file", dict(raw="{not json", record=None)),
    ("decision 'deny'", dict(record={**GOOD, "decision": "deny"})),
    ("an unrecognised decision value", dict(record={**GOOD, "decision": "sure_go_ahead"})),
    ("no decision at all", dict(record={k: v for k, v in GOOD.items() if k != "decision"})),
    ("affirmative with no manifest binding",
     dict(record={k: v for k, v in GOOD.items() if k != "manifest_sha256"})),
    ("affirmative with no pre-registration binding",
     dict(record={k: v for k, v in GOOD.items() if k != "preregistration_sha256"})),
    ("affirmative with no recorded retention state",
     dict(record={k: v for k, v in GOOD.items() if k != "groq_data_controls"})),
    ("affirmative binding the WRONG manifest", dict(record={**GOOD, "manifest_sha256": "c" * 64})),
    ("affirmative binding the WRONG pre-registration", dict(record={**GOOD, "preregistration_sha256": "d" * 64})),
    ("affirmative with no verbatim operator statement", dict(record={**GOOD, "operator_statement": ""})),
    ("a property the schema does not define", dict(record={**GOOD, "override_gate": True})),
]
for label, kwargs in REFUSAL_CASES:
    rec = kwargs.pop("record")
    v = consent_verdict(rec, **kwargs)
    check(not v.authorised, f"REFUSES: {label}", f"got {v}")


# ==========================================================================
# 3. The runner: a denial builds no client; the request is blind
# ==========================================================================
print("\n--- 3. the runner (GPT-PM BLOCKER 1 + MAJOR 1 + MAJOR 4) ---")

JPEG = bytes.fromhex("ffd8ffe000104a46494600010100000100010000ffdb004300"
                     + "01" * 64 + "ffd9")


class FactorySpy:
    def __init__(self):
        self.constructed = 0
        self.transport = run_mod.CapturingTransport()

    def __call__(self):
        self.constructed += 1
        return self.transport


def make_env(td: Path, consent_record, images=True, manifest_extra_col=False, corrupt_image=False):
    """A complete, self-contained runner environment with two observations."""
    import hashlib

    (td / "arm_a").mkdir(parents=True, exist_ok=True)
    (td / "arm_b").mkdir(parents=True, exist_ok=True)
    rows = []
    for i, arm in enumerate(("A", "B")):
        payload = JPEG + bytes([i])
        rel = f"arm_{arm.lower()}/p{i}.jpg"
        if images:
            (td / rel).write_bytes(payload)
        digest = hashlib.sha256(payload).hexdigest()
        if corrupt_image and arm == "B":
            (td / rel).write_bytes(payload + b"x")   # one byte more than was sealed
        rows.append({"observation_id": f"src{i}:{arm}", "source_photo_id": f"src{i}",
                     "arm": arm, "image_path": rel, "expected_sha256": digest})

    cols = ["observation_id", "source_photo_id", "arm", "image_path", "expected_sha256"]
    if manifest_extra_col:
        cols.append("gt_kind")
        for r in rows:
            r["gt_kind"] = "multiple"
    manifest = td / "manifest.csv"
    with manifest.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write(",".join(f'"{c}"' for c in cols) + "\n")
        for r in rows:
            fh.write(",".join(f'"{r[c]}"' for c in cols) + "\n")

    prompt = td / "prompt.txt"
    prompt.write_text((DEV / "recog_so1_prompt.txt").read_text("utf-8"), encoding="utf-8", newline="")
    vocab_f = td / "vocab.json"
    vocab_f.write_text((DEV / "recog_so1_vocab.json").read_text("utf-8"), encoding="utf-8", newline="")
    config_f = td / "config.json"
    cfg = json.loads((DEV / "recog_so1_config.json").read_text("utf-8"))
    cfg["rate_limits_measured"]["seconds_between_requests"] = 0
    config_f.write_text(json.dumps(cfg), encoding="utf-8", newline="")

    def d(p: Path) -> str:
        return hashlib.sha256(p.read_bytes()).hexdigest()

    prereg = td / "prereg.md"
    # The seal is written LAST and covers everything except itself.
    seal = {
        str(manifest.relative_to(td)).replace("\\", "/"): d(manifest),
        str(prompt.relative_to(td)).replace("\\", "/"): d(prompt),
        str(vocab_f.relative_to(td)).replace("\\", "/"): d(vocab_f),
        str(config_f.relative_to(td)).replace("\\", "/"): d(config_f),
    }
    prereg.write_text("<!-- SEAL -->\n```json\n" + json.dumps(seal, indent=2) + "\n```\n",
                      encoding="utf-8", newline="")

    consent = td / "consent.json"
    if consent_record is not None:
        rec = dict(consent_record)
        if rec.get("decision") in ("whole_corpus", "people_free_only"):
            rec["manifest_sha256"] = d(manifest)
            rec["preregistration_sha256"] = d(prereg)
        consent.write_text(json.dumps(rec, ensure_ascii=False), encoding="utf-8")

    key = td / "key.txt"
    key.write_text("not-a-real-key", encoding="utf-8")

    run_mod.REPO = td
    run_mod.PREREGISTRATION = prereg
    run_mod.CONSENT = consent
    run_mod.MANIFEST = manifest
    run_mod.PROMPT = prompt
    run_mod.VOCAB = vocab_f
    run_mod.CONFIG = config_f
    return key


def invoke(td: Path, consent_record, **env):
    key = make_env(td, consent_record, **env)
    out = td / "out.jsonl"
    spy = FactorySpy()
    code = run_mod.main(
        ["--corpus-root", str(td), "--out", str(out), "--api-key-file", str(key)],
        transport_factory=spy,
    )
    return code, spy, out


with tempfile.TemporaryDirectory() as _td:
    td = Path(_td)
    code, spy, out = invoke(td, {**GOOD, "decision": "deny"})
    check(code == 3 and spy.constructed == 0 and not out.exists(),
          "a 'deny' record: NO transport is constructed, NO output is written",
          f"exit {code}, transports constructed {spy.constructed}, output exists {out.exists()}")

with tempfile.TemporaryDirectory() as _td:
    td = Path(_td)
    code, spy, out = invoke(td, None)
    check(code == 3 and spy.constructed == 0, "an absent consent record: no transport is constructed",
          f"exit {code}, constructed {spy.constructed}")

with tempfile.TemporaryDirectory() as _td:
    td = Path(_td)
    code, spy, out = invoke(td, GOOD)
    check(code == 0 and spy.constructed == 1 and len(spy.transport.calls) == 2,
          "affirmative consent: exactly one transport, one request per observation",
          f"exit {code}, constructed {spy.constructed}, calls {len(spy.transport.calls)}")

    # ---- blindness, inspected on the SERIALIZED body -----------------------
    body = spy.transport.calls[0]["body"].decode("utf-8")
    payload = json.loads(body)
    parts = payload["messages"][0]["content"]
    text_parts = [p for p in parts if p["type"] == "text"]
    image_parts = [p for p in parts if p["type"] == "image_url"]
    frozen_prompt = (DEV / "recog_so1_prompt.txt").read_text("utf-8")
    check(len(text_parts) == 1 and text_parts[0]["text"] == frozen_prompt,
          "the request carries the frozen prompt, verbatim and alone")
    check(len(image_parts) == 1, "the request carries exactly one image", f"{len(image_parts)} image parts")
    check(all(m in text_parts[0]["text"] for m in machines[:5]) and machines[-1] in text_parts[0]["text"],
          "the request carries the frozen canonical machine list")

    FORBIDDEN = ["gemini", "gt_kind", "canonical_single", "ground_truth", "ground truth",
                 "source_photo_id", "observation_id", "expected_sha256", "disagree",
                 "d_multiple", "arm_a", "arm_b", "\"arm\""]
    lowered = body.lower()
    leaked = [t for t in FORBIDDEN if t in lowered]
    check(not leaked, "no ground truth, first-model answer, arm identity or scorer field is in the request",
          f"leaked: {leaked}")

with tempfile.TemporaryDirectory() as _td:
    td = Path(_td)
    key = make_env(td, GOOD, manifest_extra_col=True)
    try:
        run_mod.load_manifest(run_mod.MANIFEST)
        ok = False
    except SystemExit:
        ok = True
    check(ok, "an unexpected column in the observation list REFUSES rather than being ignored")

with tempfile.TemporaryDirectory() as _td:
    td = Path(_td)
    code, spy, out = invoke(td, GOOD, corrupt_image=True)
    records = [json.loads(l) for l in out.read_text("utf-8").splitlines()]
    mismatched = [r for r in records if r.get("failure") == "image_digest_mismatch"]
    check(len(mismatched) == 1 and len(spy.transport.calls) == 1,
          "a ONE-BYTE change to an image refuses that observation and never sends it",
          f"mismatched {len(mismatched)}, requests sent {len(spy.transport.calls)}")

for artefact, label in (("prompt.txt", "prompt"), ("vocab.json", "vocabulary"), ("config.json", "configuration")):
    with tempfile.TemporaryDirectory() as _td:
        td = Path(_td)
        key = make_env(td, GOOD)
        target = td / artefact
        target.write_text(target.read_text("utf-8") + "\n", encoding="utf-8", newline="")
        spy = FactorySpy()
        code = run_mod.main(["--corpus-root", str(td), "--out", str(td / "o.jsonl"),
                             "--api-key-file", str(key)], transport_factory=spy)
        check(code == 2 and spy.constructed == 0,
              f"a mutated {label} fails the seal and no transport is constructed",
              f"exit {code}, constructed {spy.constructed}")


# ==========================================================================
# 4. The scorer reaches all three outcomes on data with known answers
# ==========================================================================
print("\n--- 4. the scorer's outcomes (GPT-PM: PASS / FAIL / INCONCLUSIVE) ---")


def make_rows(n_per_kind=26, d_multi=0.85, d_canon=0.10, d_multi_b=None, d_canon_b=None,
              qwen_wrong=0, unresolved_multi=0, unresolved_canon=0):
    """Plant exact disagreement counts. Deterministic -- no sampling, no flake.

    ON `canonical_single`, DISAGREEMENTS ALTERNATE WHICH MODEL IS WRONG. The
    first version of this factory made Gemini right every time, so every
    canonical disagreement was Qwen erring -- which made the fixture trip the
    Qwen-competence FAIL condition and reported a broken scorer when the scorer
    was correct. The competence bar is about the second model being usable at
    all; a fixture that silently blames one model for every disagreement is
    testing an artefact of its own construction.
    """
    rows: list[score.Row] = []
    plans = [("multiple", d_multi, d_multi_b, unresolved_multi),
             ("canonical_single", d_canon, d_canon_b, unresolved_canon)]
    for kind, da, db, n_unres in plans:
        db = da if db is None else db
        for arm, d in (("A", da), ("B", db)):
            n_dis = round(d * n_per_kind)
            for i in range(n_per_kind):
                gt_id = f"eq_{kind}_{i}"
                unres = (arm == "A" and i < n_unres)
                disagree = i < n_dis
                gem = qwen = gt_id
                if kind == "canonical_single" and i < qwen_wrong:
                    qwen = "eq_wrong"
                elif disagree and kind == "canonical_single":
                    if i % 2 == 0:
                        gem = f"eq_other_{i}"      # Gemini is the one in error
                    else:
                        qwen = f"eq_other_{i}"     # Qwen is the one in error
                elif disagree:
                    qwen = f"eq_other_{i}"
                rows.append(score.Row(
                    observation_id=f"{kind}{i}:{arm}", source_photo_id=f"{kind}{i}", arm=arm,
                    kind=kind, gt_equipment_id=gt_id if kind == "canonical_single" else "",
                    gemini_id=gem, gemini_raw=gem,
                    qwen_id=None if unres else qwen, qwen_raw=None if unres else qwen,
                    qwen_status="unresolved" if unres else "answered",
                    qwen_failure="parse_failure" if unres else None,
                ))
    return rows


strong = make_rows(d_multi=0.85, d_canon=0.10)
v, why = score.verdict(strong)
check(v == "PASS", "a planted strong signal PASSES", f"got {v}: {why}")

noise = make_rows(d_multi=0.50, d_canon=0.50)
v, why = score.verdict(noise)
check(v == "FAIL", "pure noise FAILS", f"got {v}: {why}")

between = make_rows(d_multi=0.55, d_canon=0.22)
v, why = score.verdict(between)
check(v == "INCONCLUSIVE", "a signal between the bars is INCONCLUSIVE", f"got {v}: {why}")

reversal = make_rows(d_multi=0.95, d_canon=0.10, d_multi_b=0.05, d_canon_b=0.30)
v, why = score.verdict(reversal)
check(v == "FAIL", "a direction reversal in one arm FAILS even with a strong overall delta",
      f"got {v}: {why}")

incompetent = make_rows(d_multi=0.85, d_canon=0.10, qwen_wrong=13)
v, why = score.verdict(incompetent)
check(v == "FAIL", "a Qwen that cannot recognise equipment FAILS regardless of the delta",
      f"got {v}: {why}")

underpowered = make_rows(n_per_kind=19, d_multi=0.85, d_canon=0.10)
v, why = score.verdict(underpowered)
check(v == "INCONCLUSIVE", "19 unique sources per kind is INCONCLUSIVE however good the numbers look",
      f"got {v}: {why}")

# The conservative rule must move a result TOWARD failure, never away from it.
base_delta = score.delta_pp(make_rows(d_multi=0.85, d_canon=0.10))
with_unres = score.delta_pp(make_rows(d_multi=0.85, d_canon=0.10, unresolved_multi=13, unresolved_canon=13))
check(with_unres < base_delta,
      "unresolved observations lower the delta rather than raising it",
      f"delta {base_delta:.1f} pp -> {with_unres:.1f} pp")


# ==========================================================================
# 5. Mutation: remove a guard, and the bad fixture gets through
# ==========================================================================
print("\n--- 5. the guards are load-bearing (GPT-PM: shown failing, then passing) ---")

v_floor_on, _ = score.verdict(underpowered, enforce_power_floor=True)
v_floor_off, _ = score.verdict(underpowered, enforce_power_floor=False)
check(v_floor_on == "INCONCLUSIVE" and v_floor_off == "PASS",
      "removing the power floor turns the underpowered fixture into a PASS",
      f"floor on {v_floor_on}, floor off {v_floor_off}")

# Weakening the clustering treats 104 observations as 104 independent samples.
# Built to be indistinguishable from noise at source level: every source is
# internally consistent, so there is no real per-observation information to find.
weak = make_rows(n_per_kind=26, d_multi=0.60, d_canon=0.40)
p_clustered, _ = score.permutation_p(weak, cluster_by_observation=False)
p_unclustered, _ = score.permutation_p(weak, cluster_by_observation=True)
check(p_unclustered < p_clustered,
      "weakening the clustering to per-observation collapses the p-value",
      f"source-level p {p_clustered:.4f}, per-observation p {p_unclustered:.4f}")

# Replace the conservative unresolved rule with the dangerous mistake it exists
# to prevent -- reading a FAILURE TO GET AN ANSWER as evidence of disagreement --
# and a fixture that FAILS on the real rule starts passing.
#
# The fixture is a run that mostly did not work: every `multiple` observation in
# arm A came back unresolved. Conservatively that is agreement, D_multiple
# collapses, and the run FAILS -- correctly, because a run that could not obtain
# answers has not demonstrated anything. Counted as disagreement instead, the
# same broken run reports a large, significant effect in the hypothesised
# direction. That is the whole reason the rule is written down.
failing_with_unresolved = make_rows(d_multi=0.40, d_canon=0.05, unresolved_multi=26)
v_conservative, _ = score.verdict(failing_with_unresolved)

original = score.Row.disagrees


def failure_is_evidence(self):
    if self.unresolved:
        return True
    return original(self)


score.Row.disagrees = failure_is_evidence
v_mutated, _ = score.verdict(failing_with_unresolved)
score.Row.disagrees = original
check(v_conservative == "FAIL" and v_mutated == "PASS",
      "counting an unresolved observation as disagreement turns a failed run into a PASS",
      f"conservative {v_conservative}, mutated {v_mutated}")
check(score.verdict(failing_with_unresolved)[0] == v_conservative,
      "the mutation was reverted cleanly")


# ==========================================================================
# 6. test_the_test -- can these assertions actually fail?
# ==========================================================================
print("\n--- 6. test_the_test ---")

# If `verdict` always returned PASS, the outcome tests would be worthless.
# Substitute exactly that and require the suite's own expectations to break.
real_verdict = score.verdict
score.verdict = lambda rows, **kw: ("PASS", [])
broken = [
    score.verdict(noise)[0] == "FAIL",
    score.verdict(between)[0] == "INCONCLUSIVE",
    score.verdict(underpowered)[0] == "INCONCLUSIVE",
    score.verdict(reversal)[0] == "FAIL",
]
score.verdict = real_verdict
check(not any(broken),
      "a verdict() stubbed to always PASS is rejected by every outcome expectation",
      f"still passed: {broken}")

# If the consent gate always authorised, every refusal case must break.
real_eval = run_mod.evaluate_consent
run_mod.evaluate_consent = lambda *a, **k: run_mod.ConsentVerdict(True, "whole_corpus", "stub")
stub_survivors = [label for label, kwargs in REFUSAL_CASES
                  if consent_verdict(kwargs.get("record"), **{k: v for k, v in kwargs.items() if k != "record"}).authorised is False]
run_mod.evaluate_consent = real_eval
check(not stub_survivors,
      "a consent gate stubbed to always authorise is rejected by every refusal case",
      f"still refused against the stub: {stub_survivors}")


# ==========================================================================
print()
passed = sum(1 for ok, _ in RESULTS if ok)
print(f"{passed}/{len(RESULTS)} checks passed")
for ok, label in RESULTS:
    if not ok:
        print(f"  FAILED: {label}")
raise SystemExit(0 if passed == len(RESULTS) else 1)
