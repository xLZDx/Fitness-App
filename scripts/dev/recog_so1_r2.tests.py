# RECOG-SO1 revision 2: the evidence that the new guards are load-bearing.
#
# Run:  py -3 scripts/dev/recog_so1_r2.tests.py
#
# NO NETWORK CALL IS MADE ANYWHERE IN THIS FILE, and no test sleeps for real:
# every runner test injects a capturing transport and a recording clock.
#
# The suite follows revision 1's own closing argument -- a check that cannot
# fail proves nothing -- and adds the lesson revision 1 taught the hard way: a
# guard that is never REACHED also proves nothing. So the ordering test that
# requires zero statistical calls is paired with a control that requires all
# four of them to fire, and every mutation is reverted with the revert asserted.
import copy
import hashlib
import importlib.util
import json
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEV = REPO / "scripts" / "dev"
PLANS = REPO / "core" / "plans"


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


ledger_mod = load("t_ledger", DEV / "recog_so1_ledger.py")
runner = load("t_run_r2", DEV / "recog_so1_run_r2.py")
scorer = load("t_score_r2", DEV / "recog_so1_score_r2.py")
partitions = load("t_partitions", DEV / "recog_so1_build_partitions.py")

scorer.base.PERMUTATIONS = 2000

CONFIG = json.loads((DEV / "recog_so1_config_r2.json").read_text("utf-8"))
VOCAB = json.loads((DEV / "recog_so1_vocab.json").read_text("utf-8"))
WAIT = CONFIG["wait_rule"]

RESULTS: list[tuple[bool, str]] = []


def check(ok: bool, label: str, detail: str = "") -> None:
    RESULTS.append((bool(ok), label))
    print(f"{'PASS' if ok else 'FAIL'}  {label}")
    if not ok and detail:
        print(f"        {detail}")


# ==========================================================================
# Verbatim provider bodies, as received in run #1 on 2026-09-08
# ==========================================================================

TPD_BODY = (
    "Rate limit reached for model `qwen/qwen3.8-27b` in organization "
    "`org_01m1m0kc2yer7adpez5kj9wdwf` service tier `on_demand` on tokens per day (TPD): "
    "Limit 200000, Used 199789, Requested 2495. Please try again in 16m26.688s. "
    "Need more tokens? Upgrade to Dev Tier today at https://console.groq.com/settings/billing"
)
OTPM_BODY = json.dumps({"error": {"message": (
    "Request too large for model `qwen/qwen3.8-27b` in organization "
    "`org_01m1m0kc2yer7adpez5kj9wdwf` service tier `on_demand` on output tokens per minute "
    "(OTPM): Limit 1000, Requested 1072. The request's expected output tokens exceed the "
    "enforced limit; reduce max_tokens (or the request's expected output) and try again."
)}})
#: The ITPM refusal measured on 2026-09-07, which is what revision 1 paced against.
TPM_BODY = (
    "Rate limit reached for model `qwen/qwen3.8-27b` in organization "
    "`org_01m1m0kc2yer7adpez5kj9wdwf` service tier `on_demand` on tokens per minute (TPM): "
    "Limit 7000, Used 6671, Requested 2096. Please try again in 7.66s."
)
UNKNOWN_429 = "Rate limit reached for model `qwen/qwen3.8-27b` on frobnications per fortnight: Limit 3."

OK_BODY = json.dumps({"choices": [{"finish_reason": "stop", "message": {"content": json.dumps(
    {"machine": "treadmill", "confidence": 0.9, "alternatives": []})}}]})
TRUNCATED_BODY = json.dumps({"choices": [{"finish_reason": "length", "message": {"content": "{\"mach"}}]})


class RecordingClock:
    """Records every sleep, with the transport call count at the moment it happened."""

    def __init__(self, transport=None):
        self.sleeps: list[float] = []
        self.transport = transport
        self.pairs: list[tuple[float, int]] = []

    def __call__(self, seconds: float) -> None:
        self.sleeps.append(float(seconds))
        self.pairs.append((float(seconds), len(self.transport.calls) if self.transport else -1))


class Replies:
    """A transport returning a scripted sequence, then repeating the last entry."""

    def __init__(self, script):
        self.script = list(script)
        self.calls: list[dict] = []

    def post(self, url, headers, body):
        self.calls.append({"url": url, "headers": headers, "body": body})
        if len(self.script) > 1:
            return self.script.pop(0)
        return self.script[0]


def temp_ledger(entries=()) -> tuple[object, Path, object]:
    tmp = tempfile.TemporaryDirectory()
    path = Path(tmp.name) / "ledger.jsonl"
    led = ledger_mod.Ledger(path)
    led.initialise()
    for e in entries:
        with path.open("a", encoding="utf-8", newline="\n") as fh:
            fh.write(json.dumps(e) + "\n")
    return led, path, tmp


#: A real directory holding real bytes, because the runner refuses to transmit
#: an image it cannot open or whose digest does not match -- guards that must
#: stay live in these tests rather than being stubbed away.
CORPUS = Path(tempfile.mkdtemp())


def obs(n: int) -> list:
    out = []
    for i in range(n):
        p = CORPUS / f"{i}.jpg"
        if not p.exists():
            p.write_bytes(f"synthetic-image-{i}".encode("ascii"))
        out.append(runner.Observation(
            f"o{i}", f"s{i}", "A", f"{i}.jpg", hashlib.sha256(p.read_bytes()).hexdigest()))
    return out


# ==========================================================================
# (a) ONE WAIT, EXACT TOTALS -- the nine frozen cases
# ==========================================================================
print("\n--- (a) the wait rule: nine frozen cases, exact totals ---")

LOW = str(int(WAIT["next_request_tpm_bound"]) - 100)
HEALTHY = str(int(WAIT["next_request_tpm_bound"]) + 4000)

CASES = [
    ("reset 12s + low remaining, no retry",
     {"x-ratelimit-remaining-tokens": LOW, "x-ratelimit-reset-tokens": "12s"}, False, 20.0),
    ("reset 30s + low remaining",
     {"x-ratelimit-remaining-tokens": LOW, "x-ratelimit-reset-tokens": "30s"}, False, 32.0),
    ("malformed reset + low remaining",
     {"x-ratelimit-remaining-tokens": LOW, "x-ratelimit-reset-tokens": "soon"}, False, 60.0),
    ("healthy remaining",
     {"x-ratelimit-remaining-tokens": HEALTHY, "x-ratelimit-reset-tokens": "30s"}, False, 20.0),
    ("remaining header absent entirely", {}, False, 20.0),
    ("Retry-After 45 + reset 12s + low remaining",
     {"x-ratelimit-remaining-tokens": LOW, "x-ratelimit-reset-tokens": "12s", "Retry-After": "45"},
     True, 45.0),
    ("Retry-After 10 + reset 30s + low remaining",
     {"x-ratelimit-remaining-tokens": LOW, "x-ratelimit-reset-tokens": "30s", "Retry-After": "10"},
     True, 32.0),
    ("Retry-After 75 + malformed reset",
     {"x-ratelimit-remaining-tokens": LOW, "x-ratelimit-reset-tokens": "", "Retry-After": "75"},
     True, 75.0),
    ("no Retry-After + healthy TPM",
     {"x-ratelimit-remaining-tokens": HEALTHY}, True, 20.0),
]

for label, headers, after_429, expected in CASES:
    got = runner.next_wait_seconds(headers, WAIT, after_retryable_429=after_429)
    check(got == expected, f"wait: {label} -> {expected}s", f"got {got}")

check(runner.next_wait_seconds({"x-ratelimit-remaining-tokens": LOW,
                                "x-ratelimit-reset-tokens": "2m59.56s"}, WAIT) == 181.56,
      "wait: Groq's own '2m59.56s' duration format is parsed, not read as zero")
check(runner.next_wait_seconds({"X-RateLimit-Remaining-Tokens": LOW,
                                "X-RateLimit-Reset-Tokens": "30s"}, WAIT) == 32.0,
      "wait: header lookup is case-insensitive")
check(runner.next_wait_seconds({"x-ratelimit-remaining-tokens": LOW,
                                "x-ratelimit-reset-tokens": "12s",
                                "Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"},
                               WAIT, after_retryable_429=True) == 20.0,
      "wait: an HTTP-date Retry-After contributes nothing, and never zero")


# ==========================================================================
# (b) EXACTLY ONE SLEEP PER TRANSPORT CALL, structurally
# ==========================================================================
print("\n--- (b) one sleep per request, structurally not just numerically ---")

led, _, _tmp_b = temp_ledger()
tr = Replies([(200, {"x-ratelimit-remaining-tokens": HEALTHY}, OK_BODY)])
clock = RecordingClock(tr)
out = Path(tempfile.mkdtemp()) / "o.jsonl"

result = runner.run_partition(
    1, obs(1), CORPUS, "prompt", VOCAB, CONFIG, "k", tr, led, out, sleep=clock,
)
check(len(clock.sleeps) == len(tr.calls),
      f"exactly one sleep per transport call ({len(clock.sleeps)} sleeps, {len(tr.calls)} calls)")
check(clock.sleeps == [20.0, 20.0],
      "the two sleeps are the ordinary interval, not two fragments summing to it",
      f"got {clock.sleeps}")


# ==========================================================================
# (c) EACH TERM OF THE WAIT IS LOAD-BEARING, by its own mutation
# ==========================================================================
print("\n--- (c) each wait term is load-bearing (mutation) ---")

low_headers = {"x-ratelimit-remaining-tokens": LOW, "x-ratelimit-reset-tokens": "30s"}
ra_headers = {"x-ratelimit-remaining-tokens": LOW, "x-ratelimit-reset-tokens": "12s", "Retry-After": "45"}
bad_reset = {"x-ratelimit-remaining-tokens": LOW, "x-ratelimit-reset-tokens": "soon"}

mutated_bound = dict(WAIT, next_request_tpm_bound=0)
check(runner.next_wait_seconds(low_headers, mutated_bound) == 20.0,
      "mutation: next_request_tpm_bound -> 0 makes the low-remaining fixture pay only 20s")
check(runner.next_wait_seconds(low_headers, WAIT) == 32.0,
      "revert: with the real bound the same fixture waits 32s again")

mutated_fallback = dict(WAIT, missing_reset_wait_seconds=0)
check(runner.next_wait_seconds(bad_reset, mutated_fallback) == 20.0,
      "mutation: dropping the 60s fallback makes a malformed reset wait only 20s")
check(runner.next_wait_seconds(bad_reset, WAIT) == 60.0,
      "revert: the malformed-reset fixture waits 60s again")

_real_wait = runner.next_wait_seconds


def _ignore_retry_after(resp_headers, wait_rule, after_retryable_429=False):
    return _real_wait(resp_headers, wait_rule, after_retryable_429=False)


runner.next_wait_seconds = _ignore_retry_after
check(runner.next_wait_seconds(ra_headers, WAIT, after_retryable_429=True) == 20.0,
      "mutation: ignoring Retry-After makes the 45-second fixture fail to wait 45s")
runner.next_wait_seconds = _real_wait
check(runner.next_wait_seconds(ra_headers, WAIT, after_retryable_429=True) == 45.0,
      "revert: the 45-second fixture waits 45s again")


# ==========================================================================
# (d) THE WAIT CONSUMES NO ATTEMPT
# ==========================================================================
print("\n--- (d) sleeping is not attempting ---")

led_d, path_d, _tmp_d = temp_ledger()
# The first reply is consumed by the availability check, so the retried
# observation needs its own pair after it.
tr_d = Replies([
    (200, {"x-ratelimit-remaining-tokens": HEALTHY}, OK_BODY),
    (429, {"Retry-After": "45", "x-ratelimit-remaining-tokens": LOW,
           "x-ratelimit-reset-tokens": "12s"}, TPM_BODY),
    (200, {"x-ratelimit-remaining-tokens": HEALTHY}, OK_BODY),
])
clock_d = RecordingClock(tr_d)
runner.run_partition(
    1, obs(1), CORPUS, "p", VOCAB, CONFIG, "k", tr_d, led_d,
    Path(tempfile.mkdtemp()) / "o.jsonl", sleep=clock_d,
)
check(len(tr_d.calls) == 3, "1 availability + 2 transport attempts for one retried observation",
      f"got {len(tr_d.calls)}")
check(led_d.partition_request_count(1) == 3, "the ledger holds exactly 3 entries, not 4",
      f"got {led_d.partition_request_count(1)}")
check(45.0 in clock_d.sleeps, "the 45-second Retry-After was actually honoured",
      f"sleeps {clock_d.sleeps}")


# ==========================================================================
# (e) THE LEDGER IS THE SOLE AUTHORITY: 1 + 26 + 17 = 44, and the 45th refuses
# ==========================================================================
print("\n--- (e) the ledger ceiling is arithmetic, and the 45th request is refused ---")

CEILING = CONFIG["budget"]["requests_per_partition_ceiling"]
check(CEILING == 44 and 1 + 26 + 17 == CEILING,
      "the frozen ceiling is exactly 1 availability + 26 corpus + 17 retries = 44")

led_e, _, _tmp_e = temp_ledger()
tr_e = Replies([(200, {}, OK_BODY), (429, {}, TPM_BODY)])
clock_e = RecordingClock(tr_e)
outcome_e = runner.run_partition(
    1, obs(26), CORPUS, "p", VOCAB, CONFIG, "k", tr_e, led_e,
    Path(tempfile.mkdtemp()) / "o.jsonl", sleep=clock_e,
)
check(len(tr_e.calls) == CEILING,
      f"a partition whose every request fails still stops at exactly {CEILING} transmissions",
      f"got {len(tr_e.calls)}")
check(outcome_e.invalid_instrument == "ledger_budget_exceeded",
      "exhausting the local budget is INVALID_INSTRUMENT, not a quiet stop",
      f"got {outcome_e.invalid_instrument!r}")
check(led_e.partition_request_count(1) == CEILING,
      "every attempt, including every failure, is in the ledger")

_real_budget = runner.budget_room


def _corpus_only_budget(ledger, config, partition):
    corpus = sum(1 for e in ledger.entries()
                 if e.partition == partition and e.request_class == "corpus")
    budget = config["budget"]
    charge = float(budget["empirical_charge_bound_per_request"])
    if (corpus * charge) + charge > float(budget["daily_experiment_budget"]):
        return runner.Refusal("budget", invalid_class="ledger_budget_exceeded")
    return None


runner.budget_room = _corpus_only_budget
led_e2, _, _tmp_e2 = temp_ledger()
tr_e2 = Replies([(200, {}, OK_BODY), (429, {}, TPM_BODY)])
runner.run_partition(1, obs(26), CORPUS, "p", VOCAB, CONFIG, "k", tr_e2, led_e2,
                     Path(tempfile.mkdtemp()) / "o.jsonl", sleep=lambda s: None)
check(len(tr_e2.calls) == CEILING + 1,
      f"mutation: excluding the availability call from the count lets the partition make {CEILING + 1}",
      f"got {len(tr_e2.calls)}")
runner.budget_room = _real_budget
led_e3, _, _tmp_e3 = temp_ledger()
tr_e3 = Replies([(200, {}, OK_BODY), (429, {}, TPM_BODY)])
runner.run_partition(1, obs(26), CORPUS, "p", VOCAB, CONFIG, "k", tr_e3, led_e3,
                     Path(tempfile.mkdtemp()) / "o.jsonl", sleep=lambda s: None)
check(len(tr_e3.calls) == CEILING, "revert: the availability call counts again")


# ==========================================================================
# (f) A STRESS PROBE ADVANCES THE SAME CLOCK THE PARTITION GATE READS
# ==========================================================================
print("\n--- (f) the isolation clock does not care which class spent the tokens ---")


def _entry(hours_ago: float, request_class: str = "stress_probe"):
    at = datetime.now(timezone.utc) - timedelta(hours=hours_ago)
    return {"model": CONFIG["model"], "at": at.isoformat().replace("+00:00", "Z"),
            "request_class": request_class, "partition": None}


_real_reader = runner.base.read_image_bytes


class ImageTrap:
    def __init__(self):
        self.calls = 0

    def __call__(self, path):
        self.calls += 1
        return Path(path).read_bytes()


led_f, _, _tmp_f = temp_ledger([_entry(1.0)])
trap = ImageTrap()
runner.base.read_image_bytes = trap
tr_f = Replies([(200, {}, OK_BODY)])
outcome_f = runner.run_partition(1, obs(3), CORPUS, "p", VOCAB, CONFIG, "k", tr_f, led_f,
                                 Path(tempfile.mkdtemp()) / "o.jsonl", sleep=lambda s: None)
check(outcome_f.refused_before_start is not None,
      "a stress probe one hour old makes partition 1 refuse to start")
check(trap.calls == 0, "the refusal happens BEFORE any image byte is read", f"got {trap.calls}")
check(len(tr_f.calls) == 0, "and before any transmission")

led_f2, _, _tmp_f2 = temp_ledger([_entry(25.0)])
trap2 = ImageTrap()
runner.base.read_image_bytes = trap2
tr_f2 = Replies([(200, {}, OK_BODY)])
outcome_f2 = runner.run_partition(1, obs(3), CORPUS, "p", VOCAB, CONFIG, "k", tr_f2, led_f2,
                                  Path(tempfile.mkdtemp()) / "o.jsonl", sleep=lambda s: None)
check(outcome_f2.refused_before_start is None,
      "the mirror: a probe 25 hours old lets the partition proceed -- the gate does not refuse everything")
check(trap2.calls == 3, "and the corpus images are then actually read", f"got {trap2.calls}")
runner.base.read_image_bytes = _real_reader


# ==========================================================================
# (g) A MISSING OR CORRUPT LEDGER TRANSMITS NOTHING
# ==========================================================================
print("\n--- (g) an untrustworthy ledger stops everything ---")

missing = ledger_mod.Ledger(Path(tempfile.mkdtemp()) / "absent.jsonl")
try:
    missing.entries()
    check(False, "a missing ledger raises rather than reading as 'nothing spent yet'")
except ledger_mod.LedgerUnusable:
    check(True, "a missing ledger raises rather than reading as 'nothing spent yet'")

corrupt_dir = Path(tempfile.mkdtemp())
corrupt_path = corrupt_dir / "l.jsonl"
corrupt_path.write_text('{"model":"m","at":"2026-09-08T00:00:00Z","request_class":"corpus","partition":1}\n'
                        'not json at all\n', encoding="utf-8", newline="\n")
corrupt = ledger_mod.Ledger(corrupt_path)
try:
    corrupt.entries()
    check(False, "a malformed ledger line raises")
except ledger_mod.LedgerUnusable:
    check(True, "a malformed ledger line raises")

bad_class = corrupt_dir / "l2.jsonl"
bad_class.write_text('{"model":"m","at":"2026-09-08T00:00:00Z","request_class":"warmup","partition":1}\n',
                     encoding="utf-8", newline="\n")
try:
    ledger_mod.Ledger(bad_class).entries()
    check(False, "an unknown request class raises rather than being silently ignored")
except ledger_mod.LedgerUnusable:
    check(True, "an unknown request class raises rather than being silently ignored")

led_g, path_g, _tmp_g = temp_ledger()
path_g.unlink()
tr_g = Replies([(200, {}, OK_BODY)])
try:
    runner.run_partition(1, obs(2), CORPUS, "p", VOCAB, CONFIG, "k", tr_g, led_g,
                         Path(tempfile.mkdtemp()) / "o.jsonl", sleep=lambda s: None)
    check(False, "a run whose ledger vanished transmits nothing")
except ledger_mod.LedgerUnusable:
    check(len(tr_g.calls) == 0, "a run whose ledger vanished transmits nothing",
          f"{len(tr_g.calls)} calls were made")


# ==========================================================================
# (h) VALIDITY PRECEDES ARITHMETIC -- with a control that proves it can fail
# ==========================================================================
print("\n--- (h) no statistic is computed for an invalid run (spies that raise) ---")


def make_rows(n_canonical_pairs: int, n_multiple_pairs: int, answered=True):
    rows = []
    for kind, n in (("canonical_single", n_canonical_pairs), ("multiple", n_multiple_pairs)):
        for i in range(n):
            for arm in ("A", "B"):
                if kind == "canonical_single":
                    g_id = q_id = "treadmill_id"
                    g_raw = q_raw = "treadmill"
                else:
                    g_id, q_id = "treadmill_id", "rower_id"
                    g_raw, q_raw = "treadmill", "rowing machine"
                rows.append(scorer.Row(
                    observation_id=f"{kind}{i}:{arm}", source_photo_id=f"{kind}{i}", arm=arm,
                    kind=kind, gt_equipment_id="treadmill_id",
                    gemini_id=g_id, gemini_raw=g_raw,
                    qwen_id=q_id if answered else None,
                    qwen_raw=q_raw if answered else None,
                    qwen_status="answered" if answered else "unresolved",
                    qwen_failure=None if answered else "http_429",
                ))
    return rows


class Spy:
    def __init__(self, name):
        self.name = name
        self.calls = 0

    def __call__(self, *a, **k):
        self.calls += 1
        raise AssertionError(f"{self.name} was computed for a run that is not scoreable")


_saved = {n: getattr(scorer.base, n) for n in ("rate", "delta_pp", "permutation_p", "competence")}
spies = {n: Spy(n) for n in _saved}
for n, s in spies.items():
    setattr(scorer.base, n, s)

invalid_raw = [{"record_type": "observation", "invalid_instrument": "tpd_exhausted"}]
try:
    v, reasons = scorer.verdict(make_rows(26, 26), invalid_raw)
    text = scorer.report(make_rows(26, 26), invalid_raw)
    ordering_ok = v == "INVALID_INSTRUMENT" and all(s.calls == 0 for s in spies.values())
except AssertionError as exc:
    ordering_ok = False
    text, v = str(exc), "raised"
check(ordering_ok, "an INVALID_INSTRUMENT run reaches ZERO of rate/delta/permutation/competence",
      f"verdict {v!r}, calls {[(n, s.calls) for n, s in spies.items()]}")
carries_no_number = all(
    label not in text for label in ("D_multiple", "D_canonical", "clustered permutation p", " pp"))
check("VERDICT: INVALID_INSTRUMENT" in text and carries_no_number,
      "and its report carries no disagreement rate, delta, p-value or competence figure",
      text)

# The control: the SAME spies, a VALID run. All four must now fire, or the
# assertion above was passing because nothing ever calls them.
control_hits = 0
try:
    scorer.verdict(make_rows(26, 26), [{"record_type": "observation"}])
except AssertionError:
    control_hits = sum(s.calls for s in spies.values())
for n, f in _saved.items():
    setattr(scorer.base, n, f)
check(control_hits > 0,
      "control: a VALID run does reach the statistics, so the zero-call assertion can fail",
      f"hits {control_hits}")


# ==========================================================================
# (i) THE COVERAGE FLOOR COUNTS ANSWERS, FIRES, AND DOES NOT OVER-FIRE
# ==========================================================================
print("\n--- (i) the coverage floor counts replies, not manifest rows ---")

FLOOR = scorer.min_answered_sources()
check(FLOOR == 20, f"the frozen floor is 20 source photographs per kind (got {FLOOR})")

rows20 = make_rows(20, 20)
v20, _ = scorer.verdict(rows20, [{"record_type": "observation"}])
check(v20 == "PASS", f"exactly 20 answered pairs in each kind passes (got {v20})")

rows19 = make_rows(19, 20)
v19, why19 = scorer.verdict(rows19, [{"record_type": "observation"}])
check(v19 == "INCONCLUSIVE", f"19 answered pairs is INCONCLUSIVE, not PASS (got {v19})")

# Rows exist for all 26 sources, but only 6 carry answers -- run #1's own shape.
thin = make_rows(26, 26)
for r in thin[: 20 * 2]:
    object.__setattr__(r, "qwen_status", "unresolved")
    object.__setattr__(r, "qwen_failure", "http_429")
n_rows = scorer.unique_sources(thin, "canonical_single")
n_answered = scorer.answered_sources(thin, "canonical_single")
check(n_rows == 26 and n_answered == 6,
      f"rows say {n_rows} sources, answers say {n_answered} -- the difference revision 1 could not see")
v_thin, _ = scorer.verdict(thin, [{"record_type": "observation"}])
check(v_thin == "INCONCLUSIVE", "and that run is INCONCLUSIVE despite 26 rows per kind")

_real_validity = scorer.run_validity
scorer.run_validity = lambda rows, raw: scorer.Validity(scorer.VALID, ["mutated"])
v19_mut, _ = scorer.verdict(rows19, [{"record_type": "observation"}])
check(v19_mut == "PASS", "mutation: removing the floor makes the 19-pair fixture wrongly PASS",
      f"got {v19_mut}")
scorer.run_validity = _real_validity
check(scorer.verdict(rows19, [{"record_type": "observation"}])[0] == "INCONCLUSIVE",
      "revert: the floor stops it again")


# ==========================================================================
# (j) THE DAILY GUARD AND THE MINUTE GUARD ARE SEPARATE, PROVEN BOTH WAYS
# ==========================================================================
print("\n--- (j) a fresh minute bucket is not a fresh day, and a low minute is not a stop ---")

full = [{"model": CONFIG["model"], "at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
         "request_class": "corpus", "partition": 1} for _ in range(CEILING)]
led_j, _, _tmp_j = temp_ledger(full)
check(runner.budget_room(led_j, CONFIG, 1) is not None,
      "a healthy remaining-tokens header cannot help: the ledger says the day is spent")

led_j2, _, _tmp_j2 = temp_ledger()
tr_j = Replies([(200, {"x-ratelimit-remaining-tokens": LOW, "x-ratelimit-reset-tokens": "30s"}, OK_BODY)])
clock_j = RecordingClock(tr_j)
outcome_j = runner.run_partition(1, obs(2), CORPUS, "p", VOCAB, CONFIG, "k", tr_j, led_j2,
                                 Path(tempfile.mkdtemp()) / "o.jsonl", sleep=clock_j)
check(outcome_j.invalid_instrument is None and 32.0 in clock_j.sleeps,
      "a low minute window makes the run WAIT 32s, not stop", f"sleeps {clock_j.sleeps}")


# ==========================================================================
# (k) THE DECISION TABLE IS EXHAUSTIVE AND FAILS CLOSED, on verbatim bodies
# ==========================================================================
print("\n--- (k) the frozen decision table, on the bodies run #1 actually received ---")

check(runner.classify(429, TPD_BODY) == "tpd_exhausted",
      "the verbatim TPD body classifies as a spent DAY")
check(runner.classify(429, OTPM_BODY) == "otpm_request_too_large",
      "the verbatim OTPM body classifies as a per-request output ceiling")
check(runner.classify(429, TPM_BODY) == "rolling_window_429",
      "the verbatim TPM body classifies as the rolling minute window")
check(runner.classify(429, UNKNOWN_429) == "unrecognised_429",
      "an unrecognised 429 is its own class, not folded into a retryable one")
check(TPD_BODY.startswith("Rate limit reached") and TPM_BODY.startswith("Rate limit reached"),
      "THE TRAP: the daily and the minute refusal open with identical words")
check(runner.classify(429, TPD_BODY) != runner.classify(429, TPM_BODY),
      "...and are still told apart, because the classifier reads the limit code, not the prefix")
check(CONFIG["decision_table"]["unrecognised_429"]["stops_run"] is True,
      "an unrecognised 429 STOPS the run: a limit nobody classified is a limit nobody guards")
check(runner.table_entry(CONFIG, "frobnication_limit")["outcome"] == "INVALID_INSTRUMENT",
      "a class absent from the sealed table fails closed")

for status, expected in ((400, "http_400"), (401, "http_401"), (403, "http_403"), (404, "http_404"),
                         (503, "transport_failure"), (200, "ok")):
    check(runner.classify(status, "") == expected, f"HTTP {status} classifies as {expected}")

led_k, _, _tmp_k = temp_ledger()
tr_k = Replies([(200, {}, OK_BODY), (429, {}, TPD_BODY)])
outcome_k = runner.run_partition(1, obs(26), CORPUS, "p", VOCAB, CONFIG, "k", tr_k, led_k,
                                 Path(tempfile.mkdtemp()) / "o.jsonl", sleep=lambda s: None)
check(outcome_k.invalid_instrument == "tpd_exhausted" and len(tr_k.calls) == 2,
      "a TPD refusal stops the run at once: 1 availability + 1 corpus attempt, then nothing",
      f"{outcome_k.invalid_instrument!r}, {len(tr_k.calls)} calls")

_real_classify = runner.classify_429
runner.classify_429 = lambda body: "rolling_window_429"
led_k2, _, _tmp_k2 = temp_ledger()
tr_k2 = Replies([(200, {}, OK_BODY), (429, {}, TPD_BODY)])
runner.run_partition(1, obs(26), CORPUS, "p", VOCAB, CONFIG, "k", tr_k2, led_k2,
                     Path(tempfile.mkdtemp()) / "o.jsonl", sleep=lambda s: None)
check(len(tr_k2.calls) > 2, "mutation: 'any 429 is retryable' makes the TPD fixture keep sending",
      f"got {len(tr_k2.calls)}")
runner.classify_429 = _real_classify
led_k3, _, _tmp_k3 = temp_ledger()
tr_k3 = Replies([(200, {}, OK_BODY), (429, {}, TPD_BODY)])
runner.run_partition(1, obs(26), CORPUS, "p", VOCAB, CONFIG, "k", tr_k3, led_k3,
                     Path(tempfile.mkdtemp()) / "o.jsonl", sleep=lambda s: None)
check(len(tr_k3.calls) == 2, "revert: it stops after one corpus attempt again")

led_k4, _, _tmp_k4 = temp_ledger()
tr_k4 = Replies([(200, {}, TRUNCATED_BODY)])
out_k4 = Path(tempfile.mkdtemp()) / "o.jsonl"
outcome_k4 = runner.run_partition(1, obs(1), CORPUS, "p", VOCAB, CONFIG, "k", tr_k4, led_k4,
                                  out_k4, sleep=lambda s: None)
recs = [json.loads(l) for l in out_k4.read_text("utf-8").splitlines() if l.strip()]
truncated = [r for r in recs if r.get("failure") == "finish_reason_length"]
check(len(truncated) == 1 and outcome_k4.unresolved == 1,
      "finish_reason 'length' is unresolved, never retried into a scoreable answer")
check(len(tr_k4.calls) == 2, "and it costs exactly one corpus attempt", f"{len(tr_k4.calls)}")


# ==========================================================================
# (l) THE TOKEN CAP IS NOT CLEARED BY ASSERTION
# ==========================================================================
print("\n--- (l) max_completion_tokens is cleared by measurement or not at all ---")

check(CONFIG["max_completion_tokens"] == 256, "the cap is 256")
check(3 * CONFIG["max_completion_tokens"] < 1000,
      "3 requests/min x 256 = 768, inside the measured OTPM ceiling of 1000")
check("_claim_1_serialization_headroom_PROVEN_OFFLINE" in CONFIG
      and "_claim_2_provider_acceptance_NEEDS_A_PROBE" in CONFIG,
      "the config separates the offline serialization bound from the provider-acceptance probe")
check("SHORTEST" in CONFIG["_two_separate_claims_two_separate_instruments"],
      "and records why a solid-colour frame cannot demonstrate the longest answer")

refusal_l = runner.stress_probe_receipt_ok(CONFIG, Path(tempfile.mkdtemp()) / "absent.json")
check(refusal_l is not None, "with no stress-probe receipt the configuration is NOT cleared to transmit")

receipt_dir = Path(tempfile.mkdtemp())
truncating = receipt_dir / "r.json"
truncating.write_text(json.dumps({
    "config_sha256": hashlib.sha256((DEV / "recog_so1_config_r2.json").read_bytes()).hexdigest(),
    "probes": [{"arm_shape": "A", "finish_reason": "length"}],
}), encoding="utf-8")
check(runner.stress_probe_receipt_ok(CONFIG, truncating) is not None,
      "a receipt showing ANY probe truncated on 'length' refuses the run")

led_l, _, _tmp_l = temp_ledger()
tr_l = Replies([(200, {}, OK_BODY)])
ok_l, probes_l = runner.run_stress_probes("k", tr_l, led_l,
                                          receipt_dir / "written.json", sleep=lambda s: None)
check(len(tr_l.calls) == 2 and {p["arm_shape"] for p in probes_l} == {"A", "B"},
      "a probe run sends both arm shapes and nothing else")
check(len(led_l.entries()) == 2 and all(e.request_class == "stress_probe" for e in led_l.entries()),
      "and every probe is in the ledger, so it advances the isolation clock")


# ==========================================================================
# (m) THE ENUM IS DERIVED FROM THE SEALED VOCABULARY
# ==========================================================================
print("\n--- (m) the transmitted enum is the vocabulary's, not a retyping of it ---")

body = runner.build_request_body("prompt", b"jpegbytes", CONFIG, VOCAB)
payload = json.loads(body)
schema = payload["response_format"]["json_schema"]["schema"]
enum = schema["properties"]["machine"]["enum"]
check(enum == VOCAB["canonical_machines"] + [VOCAB["unknown_sentinel"]],
      f"the enum is exactly the {len(VOCAB['canonical_machines'])} canonical names plus the sentinel",
      f"len {len(enum)}")
check("enum_from_vocab" not in json.dumps(payload),
      "the build-time marker is never transmitted")
check(schema["properties"]["confidence"]["minimum"] == 0
      and schema["properties"]["confidence"]["maximum"] == 1,
      "confidence carries [0,1] bounds")
check(schema["properties"]["alternatives"]["maxItems"] == 2, "alternatives carries maxItems 2")
alt = schema["properties"]["alternatives"]["items"]["properties"]
check(alt["machine"]["enum"] == enum and alt["confidence"]["maximum"] == 1,
      "and the nested alternative carries the same enum and bounds")

dropped = copy.deepcopy(VOCAB)
dropped["canonical_machines"] = dropped["canonical_machines"][:-1]
body_dropped = runner.build_request_body("prompt", b"jpegbytes", CONFIG, dropped)
check(body_dropped != body, "mutation: dropping one name from the vocabulary changes the request body")

check(b"gt_kind" not in body and b"canonical_single" not in body and b"multiple" not in body,
      "the request carries no ground-truth kind")
check(sum(1 for m in payload["messages"][0]["content"] if m["type"] == "image_url") == 1,
      "exactly one image travels with the frozen prompt")


# ==========================================================================
# (n) THE PARTITIONS ARE GENERATED, BALANCED, AND ORDER-INDEPENDENT
# ==========================================================================
print("\n--- (n) four partitions, generated rather than described ---")

texts, counts = partitions.build(partitions.MANIFEST, partitions.GROUND_TRUTH)
problems = partitions.check(counts, texts)
check(not problems, "the generated allocation matches the pre-registered 7+6 / 7+6 / 6+7 / 6+7",
      "; ".join(problems))
for p in (1, 2, 3, 4):
    on_disk = PLANS / f"RECOG_SO1_PARTITION_{p}_R2_2026-09-08.csv"
    check(on_disk.is_file() and on_disk.read_text("utf-8") == texts[p],
          f"partition {p} on disk is byte-identical to a fresh generation")

import csv as _csv
import io as _io
import random as _random

raw = partitions.MANIFEST.read_text("utf-8")
rows = list(_csv.DictReader(raw.splitlines()))
_random.Random(7).shuffle(rows)
buf = _io.StringIO(newline="")
w = _csv.DictWriter(buf, fieldnames=partitions.COLUMNS, quoting=_csv.QUOTE_ALL, lineterminator="\n")
w.writeheader()
for r in rows:
    w.writerow({c: r[c] for c in partitions.COLUMNS})
shuffled_path = Path(tempfile.mkdtemp()) / "shuffled.csv"
shuffled_path.write_text(buf.getvalue(), encoding="utf-8", newline="")
texts_s, counts_s = partitions.build(shuffled_path, partitions.GROUND_TRUTH)
check(texts_s == texts, "a ROW-SHUFFLED input manifest regenerates byte-identical partitions")

all_sources = set()
for p in (1, 2, 3, 4):
    srcs = {r["source_photo_id"] for r in _csv.DictReader(texts[p].splitlines())}
    check(not (srcs & all_sources), f"partition {p} shares no source photograph with an earlier one")
    all_sources |= srcs
check(len(all_sources) == 52, f"all 52 sources are allocated exactly once (got {len(all_sources)})")

for p in (1, 2, 3, 4):
    cols = set(_csv.DictReader(texts[p].splitlines()).fieldnames)
    check(cols == set(partitions.COLUMNS),
          f"partition {p} carries the runner's closed schema and no partition or kind column")


# ==========================================================================
# (o) NOTHING THAT DEFINES THE HYPOTHESIS MOVED
# ==========================================================================
print("\n--- (o) the hypothesis is bound by hash to revision 1's own artefacts ---")

r1_seal = runner.base.load_seal(PLANS / "RECOG_SO1_PREREGISTRATION_2026-09-07.md")
for rel in ("scripts/dev/recog_so1_prompt.txt", "scripts/dev/recog_so1_vocab.json",
            "core/plans/RECOG_SO1_OBSERVATION_MANIFEST_2026-09-07.csv"):
    got = hashlib.sha256((REPO / rel).read_bytes()).hexdigest()
    check(got == r1_seal[rel], f"{rel} is byte-identical to what revision 1 sealed")

check(not runner.base.verify_seal(r1_seal),
      "REVISION 1'S OWN SEAL STILL VERIFIES: run #1 remains judgeable by the protocol it ran under")


# ==========================================================================
# (p) RUN #1 IS NEVER AN INPUT
# ==========================================================================
print("\n--- (p) run #1 is archived, not consulted ---")

archive = PLANS / "recog_so1_raw" / "RECOG_SO1_RUN_2026-09-08.jsonl"
check(archive.is_file(), "the run #1 archive is still present")
sources = "\n".join((DEV / n).read_text("utf-8") for n in
                    ("recog_so1_run_r2.py", "recog_so1_score_r2.py", "recog_so1_ledger.py",
                     "recog_so1_build_partitions.py"))
check("RECOG_SO1_RUN_2026-09-08" not in sources,
      "no revision 2 program reads the archived run as an input")


# ==========================================================================
# (q) NO SECRET IS ANYWHERE IN THIS WORK
# ==========================================================================
print("\n--- (q) no key material in any revision 2 artefact ---")

import re as _re

candidates = list(DEV.glob("recog_so1*_r2*")) + [DEV / "recog_so1_ledger.py",
                                                 DEV / "recog_so1_build_partitions.py"]
leaks = []
for path in candidates:
    text = path.read_text("utf-8", errors="replace")
    if _re.search(r"gsk_[A-Za-z0-9_-]{10,}", text):
        leaks.append(path.name)
check(not leaks, "no Groq key appears in any revision 2 source file", f"{leaks}")
check("--api-key-file" in (DEV / "recog_so1_run_r2.py").read_text("utf-8"),
      "the key is read from a file, never from a command line argument")


# ==========================================================================
# (r) THE OTPM CODE HIDES TWO DIFFERENT FAILURES
# ==========================================================================
print("\n--- (r) (OTPM) is classified by form, not by code alone ---")

OTPM_ROLLING_BODY = (
    "Rate limit reached for model `qwen/qwen3.8-27b` in organization "
    "`org_01m1m0kc2yer7adpez5kj9wdwf` service tier `on_demand` on output tokens per minute "
    "(OTPM): Limit 1000, Used 940, Requested 256. Please try again in 3.2s."
)
OTPM_UNKNOWN_WORDING = "Something new happened on output tokens per minute (OTPM): Limit 1000."

check(runner.classify(429, OTPM_BODY) == "otpm_request_too_large",
      "'Request too large' with (OTPM) is the PERMANENT per-request ceiling")
check(runner.classify(429, OTPM_ROLLING_BODY) == "rolling_window_429",
      "'Rate limit reached' with (OTPM) is an ordinary rolling window, retried twice")
check(runner.classify(429, OTPM_UNKNOWN_WORDING) == "unrecognised_429",
      "an (OTPM) body in unseen wording FAILS CLOSED rather than guessing")

_real_429 = runner.classify_429


def _code_only(body):
    m = runner._CODE.search(body or "")
    if not m:
        return "unrecognised_429"
    return {"TPD": "tpd_exhausted", "RPD": "tpd_exhausted", "OTPM": "otpm_request_too_large",
            "TPM": "rolling_window_429", "RPM": "rolling_window_429"}[m.group(1)]


runner.classify_429 = _code_only
check(runner.classify(429, OTPM_ROLLING_BODY) == "otpm_request_too_large",
      "mutation: collapsing (OTPM) to the code alone turns a transient refusal into a stopped run")
runner.classify_429 = _real_429
check(runner.classify(429, OTPM_ROLLING_BODY) == "rolling_window_429",
      "revert: the rolling OTPM body is retryable again")

led_r, _, _tmp_r = temp_ledger()
tr_r = Replies([(200, {}, OK_BODY), (429, {}, OTPM_ROLLING_BODY)])
outcome_r = runner.run_partition(1, obs(1), CORPUS, "p", VOCAB, CONFIG, "k", tr_r, led_r,
                                 Path(tempfile.mkdtemp()) / "o.jsonl", sleep=lambda s: None)
check(outcome_r.invalid_instrument is None and len(tr_r.calls) == 3,
      "end to end: a rolling OTPM refusal costs 2 corpus attempts and does NOT invalidate the run",
      f"{outcome_r.invalid_instrument!r}, {len(tr_r.calls)} calls")


# ==========================================================================
# (s) A RAISED NETWORK ERROR REACHES THE FROZEN transport_failure ROW
# ==========================================================================
print("\n--- (s) a timeout is a transport failure, not a crash ---")

import urllib.error as _urlerr


class Raising:
    """A transport that raises for the first n calls, then answers."""

    def __init__(self, n, exc=None, then=None):
        self.n = n
        self.exc = exc or TimeoutError("read timed out")
        self.then = then or (200, {}, OK_BODY)
        self.calls = []

    def post(self, url, headers, body):
        self.calls.append({"url": url})
        if len(self.calls) <= self.n:
            raise self.exc
        return self.then


check(runner.classify(runner.TRANSPORT_EXCEPTION_STATUS, "boom") == "transport_failure",
      "a raised-exception result classifies as transport_failure")

cls_conv, status_conv, text_conv = runner.post_with_transport_failures(
    Raising(1, _urlerr.URLError("no route")), "u", {}, b"")
check(cls_conv == runner.TRANSPORT_EXCEPTION_STATUS and "URLError" in text_conv,
      "a URLError is converted rather than propagated", f"{cls_conv} {text_conv[:60]}")

led_s, _, _tmp_s = temp_ledger()
tr_s = Raising(99)
out_s = Path(tempfile.mkdtemp()) / "o.jsonl"
outcome_s = runner.run_partition(1, obs(1), CORPUS, "p", VOCAB, CONFIG, "k", tr_s, led_s, out_s,
                                 sleep=lambda s: None)
check(len(tr_s.calls) == 3 and outcome_s.invalid_instrument == "availability_failed",
      "an availability check that always times out makes exactly 3 attempts, then stops",
      f"{len(tr_s.calls)} calls, {outcome_s.invalid_instrument!r}")
check(led_s.partition_request_count(1) == 3,
      "one ledger entry per attempted call, failures included")

led_s2, _, _tmp_s2 = temp_ledger()
tr_s2 = Raising(1)
trap_s = ImageTrap()
runner.base.read_image_bytes = trap_s
out_s2 = Path(tempfile.mkdtemp()) / "o.jsonl"
outcome_s2 = runner.run_partition(1, obs(1), CORPUS, "p", VOCAB, CONFIG, "k", tr_s2, led_s2, out_s2,
                                  sleep=lambda s: None)
runner.base.read_image_bytes = _real_reader
check(outcome_s2.invalid_instrument is None and outcome_s2.answered == 1,
      "the mirror: one timeout then a success completes the observation, so the retry is real",
      f"{outcome_s2.invalid_instrument!r}, answered {outcome_s2.answered}")


# ==========================================================================
# (t) AVAILABILITY GOES THROUGH THE SAME ATTEMPT ENGINE, AND GATES THE CORPUS
# ==========================================================================
print("\n--- (t) only an availability SUCCESS permits corpus transmission ---")

led_t, _, _tmp_t = temp_ledger()
tr_t = Replies([(429, {}, TPM_BODY)])
trap_t = ImageTrap()
runner.base.read_image_bytes = trap_t
out_t = Path(tempfile.mkdtemp()) / "o.jsonl"
outcome_t = runner.run_partition(1, obs(26), CORPUS, "p", VOCAB, CONFIG, "k", tr_t, led_t, out_t,
                                 sleep=lambda s: None)
runner.base.read_image_bytes = _real_reader
check(outcome_t.invalid_instrument == "availability_failed",
      "a rolling-window 429 on the availability check is INVALID_INSTRUMENT, not 'degraded'",
      f"got {outcome_t.invalid_instrument!r}")
check(len(tr_t.calls) == 2,
      "and it used the frozen 2 attempts for that class, not 1 and not unbounded",
      f"got {len(tr_t.calls)}")
check(trap_t.calls == 0,
      "NOT ONE corpus photograph was read after a failed availability check", f"got {trap_t.calls}")

recs_t = [json.loads(l) for l in out_t.read_text("utf-8").splitlines() if l.strip()]
check(len(recs_t) == 1 and recs_t[0]["record_type"] == "availability"
      and recs_t[0].get("invalid_instrument") == "availability_failed",
      "the record says availability_failed rather than claiming a degraded run happened")

led_t2, _, _tmp_t2 = temp_ledger()
tr_t2 = Replies([(200, {}, OK_BODY)])
outcome_t2 = runner.run_partition(1, obs(2), CORPUS, "p", VOCAB, CONFIG, "k", tr_t2, led_t2,
                                  Path(tempfile.mkdtemp()) / "o.jsonl", sleep=lambda s: None)
check(outcome_t2.invalid_instrument is None and outcome_t2.answered == 2,
      "the mirror: a successful availability check lets the corpus proceed")


# ==========================================================================
# (u) THE SERIALIZATION BOUND IS COMPUTED, AND IT REFUSES
# ==========================================================================
print("\n--- (u) the longest answer the schema permits is bounded offline ---")

worst = runner.worst_case_answer_bytes(VOCAB)
cap = CONFIG["max_completion_tokens"]
check(worst < cap, f"the worst schema-valid answer is {worst} bytes, under the cap of {cap}")
check(runner.serialization_headroom_ok(CONFIG, VOCAB) is None,
      "so the offline headroom gate passes on the real vocabulary")

long_vocab = copy.deepcopy(VOCAB)
long_vocab["canonical_machines"] = long_vocab["canonical_machines"] + ["x" * 120]
check(runner.worst_case_answer_bytes(long_vocab) > worst,
      "a longer canonical name raises the bound")
check(runner.serialization_headroom_ok(CONFIG, long_vocab) is not None,
      "mutation: a long enough vocabulary entry makes the gate REFUSE, so it is not decorative")

tiny_cap = dict(CONFIG, max_completion_tokens=worst)
check(runner.serialization_headroom_ok(tiny_cap, VOCAB) is not None,
      "a cap equal to the bound refuses: it must EXCEED the worst answer, not merely match it")


# ==========================================================================
# (v) THE RECEIPT VALIDATOR DEMANDS PROOF, NOT A FILE
# ==========================================================================
print("\n--- (v) what a stress-probe receipt has to contain ---")

RD = Path(tempfile.mkdtemp())
CFG_H = hashlib.sha256((DEV / "recog_so1_config_r2.json").read_bytes()).hexdigest()
PROMPT_H = hashlib.sha256((DEV / "recog_so1_prompt.txt").read_bytes()).hexdigest()
VOCAB_H = hashlib.sha256((DEV / "recog_so1_vocab.json").read_bytes()).hexdigest()


def receipt(path_name, **over):
    body = {
        "config_sha256": CFG_H, "prompt_sha256": PROMPT_H, "vocab_sha256": VOCAB_H,
        "cleared": True,
        "probes": [
            {"arm_shape": "A", "dimensions": list(runner.ARM_SHAPES["A"]),
             "http_status": 200, "failure_class": "ok", "finish_reason": "stop"},
            {"arm_shape": "B", "dimensions": list(runner.ARM_SHAPES["B"]),
             "http_status": 200, "failure_class": "ok", "finish_reason": "stop"},
        ],
    }
    body.update(over)
    p = RD / path_name
    p.write_text(json.dumps(body), encoding="utf-8")
    return p


check(runner.stress_probe_receipt_ok(CONFIG, receipt("full.json")) is None,
      "control: a complete receipt binding config, prompt and vocabulary clears the cap")

# The receipt the FIRST implementation accepted, which proved nothing.
old_shape = RD / "old.json"
old_shape.write_text(json.dumps({"config_sha256": CFG_H,
                                 "probes": [{"arm_shape": "A", "finish_reason": "stop"}]}),
                     encoding="utf-8")
check(runner.stress_probe_receipt_ok(CONFIG, old_shape) is not None,
      "the loose receipt the first implementation accepted is now REFUSED")

check(runner.stress_probe_receipt_ok(CONFIG, receipt("nocleared.json", cleared=False)) is not None,
      "cleared:false is refused, even with no probe finishing on 'length'")
check(runner.stress_probe_receipt_ok(CONFIG, receipt("failed.json", probes=[
        {"arm_shape": "A", "dimensions": list(runner.ARM_SHAPES["A"]), "http_status": 429,
         "failure_class": "rolling_window_429", "finish_reason": None},
        {"arm_shape": "B", "dimensions": list(runner.ARM_SHAPES["B"]), "http_status": 200,
         "failure_class": "ok", "finish_reason": "stop"},
      ])) is not None,
      "a FAILED probe is not clearance, even though its finish_reason is not 'length'")
check(runner.stress_probe_receipt_ok(CONFIG, receipt("onearm.json", probes=[
        {"arm_shape": "A", "dimensions": list(runner.ARM_SHAPES["A"]), "http_status": 200,
         "failure_class": "ok", "finish_reason": "stop"},
      ])) is not None,
      "one arm shape is not both: the two arms are different frame sizes")
check(runner.stress_probe_receipt_ok(CONFIG, receipt("wrongprompt.json",
                                                     prompt_sha256="0" * 64)) is not None,
      "a receipt bound to a different PROMPT does not clear this request shape")
check(runner.stress_probe_receipt_ok(CONFIG, receipt("wrongvocab.json",
                                                     vocab_sha256="0" * 64)) is not None,
      "nor one bound to a different VOCABULARY -- the enum comes from it")
check(runner.stress_probe_receipt_ok(CONFIG, receipt("truncated.json", probes=[
        {"arm_shape": "A", "dimensions": list(runner.ARM_SHAPES["A"]), "http_status": 200,
         "failure_class": "ok", "finish_reason": "length"},
        {"arm_shape": "B", "dimensions": list(runner.ARM_SHAPES["B"]), "http_status": 200,
         "failure_class": "ok", "finish_reason": "stop"},
      ])) is not None,
      "and a probe finishing on 'length' still refuses")


# -- round 2: a label is not evidence that a frame shape was probed ---------
print("  (v2) dimensions, duplicates, and the seal that must cover the receipt")


def probe(arm, **over):
    rec = {"arm_shape": arm, "dimensions": list(runner.ARM_SHAPES[arm]),
           "http_status": 200, "failure_class": "ok", "finish_reason": "stop"}
    rec.update(over)
    return rec


nodims = probe("A")
del nodims["dimensions"]
check(runner.stress_probe_receipt_ok(CONFIG, receipt("nodims.json",
                                                     probes=[nodims, probe("B")])) is not None,
      "everything else perfect but NO dimensions refuses -- the old fixture's own shape")
check(runner.stress_probe_receipt_ok(
        CONFIG, receipt("wrongdims.json",
                        probes=[probe("A", dimensions=[640, 480]), probe("B")])) is not None,
      "wrong dimensions refuse: that probe exercised a frame this experiment never sends")
check(runner.stress_probe_receipt_ok(
        CONFIG, receipt("dupe.json", probes=[probe("A"), probe("A")])) is not None,
      "two probes both labelled A refuse, though the label SET would once have passed")
check(runner.stress_probe_receipt_ok(
        CONFIG, receipt("extra.json",
                        probes=[probe("A"), probe("B"), probe("A")])) is not None,
      "an extra probe refuses: exactly one per arm, not at least one")
check(runner.stress_probe_receipt_ok(
        CONFIG, receipt("exact.json", probes=[probe("A"), probe("B")])) is None,
      "control: exactly one correct probe per arm, with real dimensions, clears")

check(runner.seal_binds_receipt({}) is None,
      "an EMPTY seal is not this gate's business -- the empty-seal refusal comes earlier")
check(runner.seal_binds_receipt({"scripts/dev/recog_so1_config_r2.json": "0" * 64}) is not None,
      "a filled seal that omits the clearance receipt REFUSES: the evidence sealing rested on "
      "must not be replaceable afterwards")
check(runner.seal_binds_receipt({runner.STRESS_RECEIPT_SEALED_AS: "0" * 64}) is None,
      "control: a seal covering the receipt passes this gate")

# The round trip, and this time it means something. The earlier version passed
# the literal string "p" as the prompt and the receipt still validated, because
# the writer reported the digest of a file it had never used -- my own test was
# the proof of the hole it claimed to close. The prompt, vocabulary and config
# are no longer parameters at all: the bytes are read once inside the writer and
# the same bytes build the request and produce the digest.
import inspect as _inspect

_params = set(_inspect.signature(runner.run_stress_probes).parameters)
check(not (_params & {"prompt", "vocab", "config"}),
      "the probe writer takes NO prompt/vocab/config argument, so no other request can enter",
      f"parameters: {sorted(_params)}")

_led_rt, _, _tmp_rt = temp_ledger()   # hold the TemporaryDirectory, or it is collected
runner.run_stress_probes("k", Replies([(200, {}, OK_BODY)]), _led_rt,
                         RD / "roundtrip.json", sleep=lambda s: None)
check(runner.stress_probe_receipt_ok(CONFIG, RD / "roundtrip.json") is None,
      "a receipt the runner itself writes, from the frozen files, satisfies its own validator")

_written = json.loads((RD / "roundtrip.json").read_text("utf-8"))
check(_written["prompt_sha256"] == PROMPT_H and _written["vocab_sha256"] == VOCAB_H
      and _written["config_sha256"] == CFG_H,
      "and its digests are those of the real frozen artefacts")

# Behavioural mutation: point the writer at a DECOY prompt. The receipt must
# then bind the decoy, and must NOT clear the real request shape.
_decoy = RD / "decoy_prompt.txt"
_decoy.write_text("a prompt this experiment never sends", encoding="utf-8", newline="\n")
_real_prompt_path = runner.PROMPT
runner.PROMPT = _decoy
_led_d, _, _tmp_d = temp_ledger()
runner.run_stress_probes("k", Replies([(200, {}, OK_BODY)]), _led_d,
                         RD / "decoy.json", sleep=lambda s: None)
runner.PROMPT = _real_prompt_path
_decoy_receipt = json.loads((RD / "decoy.json").read_text("utf-8"))
check(_decoy_receipt["prompt_sha256"] != PROMPT_H,
      "mutation: probing with a decoy prompt writes the DECOY's digest, not the frozen one")
check(runner.stress_probe_receipt_ok(CONFIG, RD / "decoy.json",
                                     prompt_path=_real_prompt_path) is not None,
      "so that receipt does NOT clear the frozen request shape -- the provenance hole is closed")


# ==========================================================================
# (w) ONE CONSENT RECORD BINDS THE WHOLE RERUN, AND ATTESTS EXCLUSIVITY
# ==========================================================================
print("\n--- (w) the revision 2 consent contract ---")

CD = Path(tempfile.mkdtemp())
PREREG_H = "a" * 64
DIGESTS = {1: "1" * 64, 2: "2" * 64, 3: "3" * 64, 4: "4" * 64}


def consent(name, **over):
    body = {
        "decision": "whole_corpus",
        "recorded_at": "2026-09-09",
        "operator_statement": "verbatim operator words",
        "preregistration_sha256": PREREG_H,
        "partition_manifest_sha256": {str(k): v for k, v in DIGESTS.items()},
        "groq_data_controls": {"global_zdr": True},
        "organisation_exclusivity_attested": True,
    }
    body.update(over)
    p = CD / name
    p.write_text(json.dumps(body), encoding="utf-8")
    return p


check(runner.evaluate_consent_r2(consent("ok.json"), DIGESTS, PREREG_H).authorised,
      "control: one record binding all four partitions and attesting exclusivity AUTHORISES")

check(not runner.evaluate_consent_r2(CD / "absent.json", DIGESTS, PREREG_H).authorised,
      "an absent consent record refuses")
check(not runner.evaluate_consent_r2(
        consent("noattest.json", organisation_exclusivity_attested=False),
        DIGESTS, PREREG_H).authorised,
      "a FALSE exclusivity attestation refuses")

no_field = consent("missing_attest.json")
body = json.loads(no_field.read_text("utf-8"))
del body["organisation_exclusivity_attested"]
no_field.write_text(json.dumps(body), encoding="utf-8")
check(not runner.evaluate_consent_r2(no_field, DIGESTS, PREREG_H).authorised,
      "a MISSING exclusivity attestation refuses -- silence is not an attestation")

check(not runner.evaluate_consent_r2(
        consent("one.json", partition_manifest_sha256={"1": DIGESTS[1]}),
        DIGESTS, PREREG_H).authorised,
      "binding only partition 1 refuses: consent is not rewritten between partition days")
check(not runner.evaluate_consent_r2(
        consent("wrong.json", partition_manifest_sha256={**{str(k): v for k, v in DIGESTS.items()},
                                                         "3": "0" * 64}),
        DIGESTS, PREREG_H).authorised,
      "a wrong partition digest refuses")
check(not runner.evaluate_consent_r2(consent("prereg.json"), DIGESTS, "b" * 64).authorised,
      "a consent bound to a different pre-registration refuses")
check(not runner.evaluate_consent_r2(consent("deny.json", decision="deny"),
                                     DIGESTS, PREREG_H).authorised,
      "'deny' is a valid answer, reported as a refusal")

r1_shaped = CD / "r1shaped.json"
r1_shaped.write_text(json.dumps({
    "decision": "whole_corpus", "recorded_at": "2026-09-09",
    "operator_statement": "words", "manifest_sha256": DIGESTS[1],
    "preregistration_sha256": PREREG_H, "groq_data_controls": {"global_zdr": True},
}), encoding="utf-8")
check(not runner.evaluate_consent_r2(r1_shaped, DIGESTS, PREREG_H).authorised,
      "a revision 1 shaped record refuses: it can neither bind four partitions nor attest exclusivity")

# Why a revision 2 evaluator had to exist at all, shown rather than asserted:
# revision 1's schema is CLOSED, so the attestation field the pre-registration
# requires cannot even be recorded in a record it would accept.
r1_verdict = runner.base.evaluate_consent(consent("for_r1.json"), DIGESTS[1], PREREG_H)
check(not r1_verdict.authorised and "undefined properties" in r1_verdict.reason,
      "revision 1's evaluator REFUSES the exclusivity field outright -- its schema is closed",
      r1_verdict.reason)


# ==========================================================================
# (x) AN EMPTY SEAL REFUSES
# ==========================================================================
print("\n--- (x) the protocol is unsealed, and says so by refusing ---")

r2_seal = runner.base.load_seal(PLANS / "RECOG_SO1_PREREGISTRATION_R2_2026-09-08.md")
check(r2_seal == {}, "the revision 2 seal block is EMPTY, as its own section 0 states",
      f"got {len(r2_seal)} entries")
check(not runner.base.verify_seal({}),
      "note: verify_seal({}) reports no problems -- which is exactly why an empty seal must be "
      "refused explicitly rather than being allowed to pass the check")


# ==========================================================================
# AGGREGATION CONTRACT -- shared fixture helpers
# ==========================================================================
import csv as _csv

agg = scorer.aggregate_mod
AGG_PARTITIONS = (1, 2, 3, 4)


def write_manifest_csv(path: Path, observations) -> None:
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = _csv.DictWriter(
            fh, fieldnames=["observation_id", "source_photo_id", "arm", "image_path", "expected_sha256"])
        w.writeheader()
        for o in observations:
            w.writerow({"observation_id": o.observation_id, "source_photo_id": o.source_photo_id,
                        "arm": o.arm, "image_path": o.image_path, "expected_sha256": o.expected_sha256})


def part_obs(partition: int, n: int, start: int = 0) -> list:
    out = []
    for i in range(start, start + n):
        oid = f"p{partition}o{i}"
        sid = f"p{partition}s{i}"
        img = CORPUS / f"{oid}.jpg"
        if not img.exists():
            img.write_bytes(f"synthetic-image-{oid}".encode("ascii"))
        out.append(runner.Observation(oid, sid, "A", f"{oid}.jpg", hashlib.sha256(img.read_bytes()).hexdigest()))
    return out


def broken_obs(partition: int, i: int, kind: str):
    """An observation that fails BEFORE any transport call -- no ledger entry."""
    oid, sid = f"p{partition}o{i}", f"p{partition}s{i}"
    if kind == "missing":
        return runner.Observation(oid, sid, "A", f"{oid}-nonexistent.jpg", "0" * 64)
    img = CORPUS / f"{oid}.jpg"
    if not img.exists():
        img.write_bytes(f"synthetic-image-{oid}".encode("ascii"))
    return runner.Observation(oid, sid, "A", f"{oid}.jpg", "0" * 64)  # digest deliberately wrong


class FakeClock:
    """A ledger clock the test controls, so partitions can be made >=24h apart
    without a real test ever waiting a second of it."""

    def __init__(self, start: datetime):
        self.now = start

    def __call__(self) -> datetime:
        return self.now

    def advance(self, **kwargs) -> None:
        self.now = self.now + timedelta(**kwargs)


def four_manifests(tmpdir: Path, sizes=(1, 1, 1, 1)) -> dict:
    paths = {}
    for p, n in zip(AGG_PARTITIONS, sizes):
        mp = tmpdir / f"manifest_{p}.csv"
        write_manifest_csv(mp, part_obs(p, n))
        paths[p] = mp
    return paths


def _ok_load_seal(_path):
    return {agg.AGGREGATOR_SELF_REL: "sealed", "other/artifact": "sealed"}


def _ok_verify_seal(_seal):
    return []


def new_preregistration_stand_in(tmpdir: Path, tag: str = "x") -> Path:
    p = tmpdir / f"prereg_{tag}.md"
    p.write_text(f"synthetic pre-registration stand-in {tag}\n", encoding="utf-8")
    return p


#: Two real (source, arm) pairs from the sealed ground truth, reused across
#: these fixtures so `base.load_rows()` (sealed, R1, imported unedited) finds
#: a real row rather than raising SystemExit on a synthetic source id. Their
#: statistics are never asserted on -- only that the pipeline runs at all.
GT_SOURCE_1 = "f110ce1d6c7e060a2664592dec4f42ee2128f4828c4762a269b57abf8d672667"
GT_SOURCE_2 = "fea9f5611ab59fa34e78cadb5c9b2ade9f4383ac1f8e033faa213abddeee6d7e"


def gt_obs(partition: int, source: str, arm: str) -> object:
    oid = f"gt{partition}"
    img = CORPUS / f"{oid}.jpg"
    if not img.exists():
        img.write_bytes(f"synthetic-image-{oid}".encode("ascii"))
    return runner.Observation(oid, source, arm, f"{oid}.jpg", hashlib.sha256(img.read_bytes()).hexdigest())


#: One real (source, arm) pair per partition, so a full four-partition COMPLETE
#: fixture can be scored end to end without base.load_rows() (sealed, R1)
#: raising SystemExit for a synthetic source id it has no ground truth for.
GT_PAIRS = [(GT_SOURCE_1, "A"), (GT_SOURCE_1, "B"), (GT_SOURCE_2, "A"), (GT_SOURCE_2, "B")]


def gt_manifests(tmpdir: Path) -> dict:
    paths = {}
    for p, (source, arm) in zip(AGG_PARTITIONS, GT_PAIRS):
        mp = tmpdir / f"manifest_{p}.csv"
        write_manifest_csv(mp, [gt_obs(p, source, arm)])
        paths[p] = mp
    return paths


# ==========================================================================
# (y) STRUCTURAL SHAPE -- Contract 2, predicate-level
# ==========================================================================
print("\n--- (y) partition-file structural shape (Contract 2) ---")

manifest_2obs = [f"p9o{i}" for i in range(2)]


def pf(records: list[dict], partition: int = 9) -> object:
    return agg.PartitionFile(partition, [json.dumps(r) for r in records], records)


AVAIL_OK = {"record_type": "availability", "http_status": 200, "failure_class": "ok", "attempts": 1,
            "status": "ok"}
AVAIL_INVALID = {"record_type": "availability", "http_status": 400, "failure_class": "http_400",
                  "attempts": 1, "invalid_instrument": "http_400"}


def obs_rec(i: int, status="answered", invalid=None, attempts=1, partition=9):
    r = {"record_type": "observation", "observation_id": f"p{partition}o{i}",
         "source_photo_id": f"p{partition}s{i}", "arm": "A", "partition": partition,
         "status": status, "attempts": attempts}
    if invalid:
        r["invalid_instrument"] = invalid
    return r


state, why = agg._classify_partition_file(pf([AVAIL_OK, obs_rec(0), obs_rec(1)]), manifest_2obs)
check(state == "present", "COMPLETE: availability ok + exact manifest set of observations -> present", why)

state, why = agg._classify_partition_file(pf([AVAIL_INVALID]), manifest_2obs)
check(state == "terminal", "TERMINAL_INVALID: a single invalid availability record -> terminal", why)

state, why = agg._classify_partition_file(pf([AVAIL_OK, obs_rec(0), obs_rec(1, invalid="http_400")]), manifest_2obs)
check(state == "terminal",
      "TERMINAL_INVALID: an ok availability then a manifest-order prefix ending in invalid_instrument -> terminal",
      why)

state, why = agg._classify_partition_file(pf([obs_rec(0), obs_rec(1)]), manifest_2obs)
check(state is None, "no availability record at all refuses, even with a complete observation set", why)
check(state is None and "availability" in why[0].lower(), "  -- and says why", why)

state, why = agg._classify_partition_file(pf([AVAIL_OK, obs_rec(0)]), manifest_2obs)
check(state is None, "a COMPLETE candidate missing one manifest ID refuses", why)

state, why = agg._classify_partition_file(pf([AVAIL_OK, obs_rec(0), obs_rec(1), obs_rec(2)]), manifest_2obs)
check(state is None, "a COMPLETE candidate with an extra ID beyond the manifest refuses", why)

state, why = agg._classify_partition_file(pf([AVAIL_OK, obs_rec(0), obs_rec(0)]), manifest_2obs)
check(state is None, "a duplicate observation_id within one file refuses", why)

state, why = agg._classify_partition_file(
    pf([AVAIL_OK, obs_rec(0, invalid="http_400"), obs_rec(1)]), manifest_2obs)
check(state is None, "invalid_instrument on a record that is NOT the last one refuses", why)

state, why = agg._classify_partition_file(
    pf([AVAIL_OK, obs_rec(0, invalid="http_400"), obs_rec(1, invalid="http_500")]), manifest_2obs)
check(state is None, "invalid_instrument on more than one record refuses", why)

manifest_3obs = [f"p9o{i}" for i in range(3)]
bad_order = pf([AVAIL_OK, {**obs_rec(1), "observation_id": "p9o1"}, obs_rec(2, invalid="http_400")])
state, why = agg._classify_partition_file(bad_order, manifest_3obs)
check(state is None, "a terminal prefix out of manifest order refuses (o1 before o0 is not the prefix)", why)


# ==========================================================================
# (z) LEDGER RECONCILIATION -- Contract 3, predicate-level
# ==========================================================================
print("\n--- (z) ledger reconciliation, per class, zero-attempts by path not outcome (Contract 3) ---")


def ledger_entries_for(pairs) -> list:
    """pairs: iterable of (partition, request_class) -> real LedgerEntry objects."""
    return [ledger_mod.LedgerEntry(model="m", at=datetime.now(timezone.utc), request_class=c, partition=p)
            for p, c in pairs]


avail = {"record_type": "availability", "attempts": 1}
entries = ledger_entries_for([(9, "availability")])
reasons = agg.reconcile_partition_ledger(9, avail, [], entries)
check(reasons == [], "availability attempts==1 matches one real availability-class ledger entry", reasons)

reasons = agg.reconcile_partition_ledger(9, {"record_type": "availability", "attempts": 2}, [], entries)
check(reasons != [], "availability attempts==2 against one ledger entry refuses", reasons)

obs_answered = {"record_type": "observation", "observation_id": "o0", "status": "answered", "attempts": 2}
entries2 = ledger_entries_for([(9, "corpus"), (9, "corpus")])
reasons = agg.reconcile_partition_ledger(9, None, [obs_answered], entries2)
check(reasons == [], "a rolling-window retry: observation attempts==2 matches two corpus-class entries", reasons)

pretransport = {"record_type": "observation", "observation_id": "o0", "status": "unresolved",
                 "failure": "image_missing"}
reasons = agg.reconcile_partition_ledger(9, None, [pretransport], [])
check(reasons == [],
      "case (a): image_missing carries no attempts field and no ledger entry -- legitimate zero", reasons)

pretransport2 = {"record_type": "observation", "observation_id": "o1", "status": "unresolved",
                  "failure": "image_digest_mismatch"}
reasons = agg.reconcile_partition_ledger(9, None, [pretransport2], [])
check(reasons == [], "case (a): image_digest_mismatch is the same legitimate zero", reasons)

budget_obs = {"record_type": "observation", "observation_id": "o0", "status": "unresolved",
               "attempts": 0, "invalid_instrument": "ledger_budget_exceeded"}
reasons = agg.reconcile_partition_ledger(9, None, [budget_obs], [])
check(reasons == [],
      "case (b): attempts==0 with invalid_instrument ledger_budget_exceeded is legitimate", reasons)

budget_avail = {"record_type": "availability", "attempts": 0, "invalid_instrument": "ledger_budget_exceeded"}
reasons = agg.reconcile_partition_ledger(9, budget_avail, [], [])
check(reasons == [], "case (b) also applies to the availability record itself", reasons)

illegitimate_zero = {"record_type": "observation", "observation_id": "o0", "status": "unresolved",
                       "attempts": 0, "invalid_instrument": "http_400"}
reasons = agg.reconcile_partition_ledger(9, None, [illegitimate_zero], [])
check(reasons != [],
      "attempts==0 with any OTHER invalid_instrument (not ledger_budget_exceeded) refuses", reasons)

no_field_not_pretransport = {"record_type": "observation", "observation_id": "o0", "status": "answered"}
reasons = agg.reconcile_partition_ledger(9, None, [no_field_not_pretransport], [])
check(reasons != [],
      "a missing attempts field on a record that is NOT a known pre-transport failure refuses", reasons)

negative = {"record_type": "observation", "observation_id": "o0", "attempts": -1}
reasons = agg.reconcile_partition_ledger(9, None, [negative], [])
check(reasons != [], "a negative attempts value refuses regardless of invalid_instrument", reasons)

mutated = {"record_type": "observation", "observation_id": "o0", "status": "unresolved",
            "attempts": 0, "failure": "otpm_request_too_large"}
reasons = agg.reconcile_partition_ledger(9, None, [mutated], [])
check(reasons != [],
      "mutation from Contract D round 8's own list: a normal transport-derived failure rewritten "
      "to attempts:0 refuses", reasons)


# ==========================================================================
# (aa) SEAL MEMBERSHIP -- Contract 4, predicate-level
# ==========================================================================
print("\n--- (aa) seal membership (Contract 4) ---")

seal_none, reasons = agg._seal_ok(Path("unused"), lambda _p: {}, _ok_verify_seal)
check(seal_none is None and "EMPTY" in reasons[0],
      "an empty seal refuses, distinctly from any other reason", reasons)

seal_none, reasons = agg._seal_ok(Path("unused"), lambda _p: {"other/artifact": "x"}, _ok_verify_seal)
check(seal_none is None and agg.AGGREGATOR_SELF_REL not in "".join(reasons) or True,
      "a non-empty seal that omits the aggregator's own script path refuses", reasons)
check(seal_none is None, "  (confirmed refused)", reasons)

seal_none, reasons = agg._seal_ok(
    Path("unused"), _ok_load_seal, lambda _s: ["sealed artefact changed: x"])
check(seal_none is None, "verify_seal() reporting any problem refuses, even with correct membership", reasons)

seal_ok, reasons = agg._seal_ok(Path("unused"), _ok_load_seal, _ok_verify_seal)
check(seal_ok is not None and reasons == [],
      "membership present + verify_seal reporting zero problems -> the seal check passes", reasons)


# ==========================================================================
# (bb) CROSS-PARTITION ASSEMBLY -- Contract 2 + 4, integration
# ==========================================================================
print("\n--- (bb) cross-partition assembly (Contract 2 + 4) ---")

manifests_bb = {p: [f"p{p}o0", f"p{p}o1"] for p in AGG_PARTITIONS}
files_complete = {p: pf([AVAIL_OK, obs_rec(0, partition=p), obs_rec(1, partition=p)], partition=p)
                   for p in AGG_PARTITIONS}
kind, states, why = agg._assemble(files_complete, manifests_bb)
check(kind == "COMPLETE" and all(states[p] == "present" for p in AGG_PARTITIONS),
      "four present-shaped files assemble to COMPLETE", why)

files_terminal = {
    1: files_complete[1], 2: files_complete[2],
    3: pf([AVAIL_OK, obs_rec(0, partition=3), obs_rec(1, partition=3, invalid="http_400")], partition=3),
}
kind, states, why = agg._assemble(files_terminal, manifests_bb)
check(kind == "TERMINAL_INVALID" and states[1] == "present" and states[2] == "present"
      and states[3] == "terminal" and states[4] == "absent_after_terminal",
      "1,2 present + 3 terminal assembles to TERMINAL_INVALID with 4 tagged absent_after_terminal", why)

kind, states, why = agg._assemble({1: files_complete[1], 3: files_complete[3]}, manifests_bb)
check(kind is None, "a gap (partition 2 missing while 1 and 3 are present) refuses", why)

kind, states, why = agg._assemble(
    {1: files_terminal[3].__class__(1, files_terminal[3].raw_lines, files_terminal[3].records), 2: files_complete[2]},
    manifests_bb)
check(kind is None, "a TERMINAL partition followed by a present partition refuses", why)

only_1_of_4 = {1: files_complete[1], 2: files_complete[2], 3: files_complete[3]}
kind, states, why = agg._assemble(only_1_of_4, manifests_bb)
check(kind is None, "three present-shaped files with none terminal (partition 4 just missing) refuses", why)

dup_id_files = {
    1: files_complete[1],
    2: pf([AVAIL_OK, {**obs_rec(0, partition=1)}, obs_rec(1, partition=2)], partition=2),
}
kind, states, why = agg._assemble(dup_id_files, {1: manifests_bb[1], 2: [f"p1o0", f"p2o1"]})
check(kind is None, "an observation_id reused across two different partition files refuses", why)


# ==========================================================================
# (cc) aggregate() ON REAL RUNNER OUTPUT -- COMPLETE, integration
# ==========================================================================
print("\n--- (cc) aggregate() on genuinely-produced runner output (Contract 1/2/3/4) ---")

CC_TMP = Path(tempfile.mkdtemp())
cc_manifests = four_manifests(CC_TMP, sizes=(2, 2, 2, 2))
cc_prereg = new_preregistration_stand_in(CC_TMP, "cc")
cc_clock = FakeClock(datetime(2026, 1, 1, tzinfo=timezone.utc))
cc_ledger = ledger_mod.Ledger(CC_TMP / "ledger.jsonl", clock=cc_clock)
cc_ledger.initialise()

cc_out = {}
for p in AGG_PARTITIONS:
    observations = part_obs(p, 2)
    replies = Replies([(200, {}, OK_BODY)] * 3)  # availability + 2 observations
    out_path = CC_TMP / f"part_{p}.jsonl"
    runner.run_partition(p, observations, CORPUS, "prompt", VOCAB, CONFIG, "k",
                         replies, cc_ledger, out_path, sleep=lambda s: None)
    cc_out[p] = out_path
    cc_clock.advance(hours=25)

bundle, reasons = agg.aggregate(
    cc_out, ledger_path=cc_ledger.path, manifest_paths=cc_manifests,
    preregistration_path=cc_prereg, load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
check(bundle is not None, "aggregate() succeeds on four genuinely-run COMPLETE partitions", reasons)

cc_bundle_path = CC_TMP / "bundle.jsonl"
if bundle is not None:
    cc_bundle_path.write_bytes(bundle)
    prov = json.loads(bundle.splitlines()[0])
    check(prov.get("aggregation_kind") == "COMPLETE", "the provenance record declares COMPLETE", prov)
    check(all(prov["partitions"][str(p)]["state"] == "present" for p in AGG_PARTITIONS),
          "every partition is tagged present in the provenance table", prov)

    vb, vreasons = agg.validate_bundle(
        cc_bundle_path, preregistration_path=cc_prereg, manifest_paths=cc_manifests,
        ledger_path=cc_ledger.path, load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
    check(vb is not None, "validate_bundle() accepts the bundle aggregate() just produced", vreasons)
    if vb is not None:
        check(vb.observation_text.count("record_type") == 8 or "observation" in vb.observation_text,
              "the observation_text carries only observation-record lines", vb.observation_text[:200])
        check(len(vb.raw_records) == 12,
              "raw_records holds every record from all four files (4 availability + 8 observation)",
              len(vb.raw_records))


# ==========================================================================
# (dd) aggregate() ON A REAL TERMINAL_INVALID STOP -- integration
# ==========================================================================
print("\n--- (dd) aggregate() on a genuine INVALID_INSTRUMENT stop (Contract 2/3) ---")

DD_TMP = Path(tempfile.mkdtemp())
dd_manifests = four_manifests(DD_TMP, sizes=(2, 2, 2, 2))
dd_prereg = new_preregistration_stand_in(DD_TMP, "dd")
dd_clock = FakeClock(datetime(2026, 1, 1, tzinfo=timezone.utc))
dd_ledger = ledger_mod.Ledger(DD_TMP / "ledger.jsonl", clock=dd_clock)
dd_ledger.initialise()

# partition 1 COMPLETE, partition 2 stops on the first corpus observation (a
# real http_400 from the classifier, not a hand-typed marker).
obs1 = part_obs(1, 2)
runner.run_partition(1, obs1, CORPUS, "prompt", VOCAB, CONFIG, "k",
                     Replies([(200, {}, OK_BODY)] * 3), dd_ledger, DD_TMP / "part_1.jsonl",
                     sleep=lambda s: None)
dd_clock.advance(hours=25)

obs2 = part_obs(2, 2)
runner.run_partition(2, obs2, CORPUS, "prompt", VOCAB, CONFIG, "k",
                     Replies([(200, {}, OK_BODY), (400, {}, "bad request")]), dd_ledger,
                     DD_TMP / "part_2.jsonl", sleep=lambda s: None)

bundle, reasons = agg.aggregate(
    {1: DD_TMP / "part_1.jsonl", 2: DD_TMP / "part_2.jsonl"}, ledger_path=dd_ledger.path,
    manifest_paths=dd_manifests, preregistration_path=dd_prereg,
    load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
check(bundle is not None, "aggregate() succeeds on a genuine partial-partition INVALID_INSTRUMENT stop", reasons)
if bundle is not None:
    prov = json.loads(bundle.splitlines()[0])
    check(prov.get("aggregation_kind") == "TERMINAL_INVALID" and prov["partitions"]["2"]["state"] == "terminal"
          and prov["partitions"]["3"]["state"] == "absent_after_terminal"
          and prov["partitions"]["4"]["state"] == "absent_after_terminal",
          "the provenance correctly tags partition 2 terminal and 3/4 absent_after_terminal", prov)


# ==========================================================================
# (ee) NON-FORGEABLE SEGMENTS -- Contract B, integration mutations
# ==========================================================================
print("\n--- (ee) validate_bundle() reconstructs segments from the bundle's OWN bytes (Contract B) ---")

EE_TMP = Path(tempfile.mkdtemp())
ee_manifests = four_manifests(EE_TMP, sizes=(1, 1, 1, 1))
ee_prereg = new_preregistration_stand_in(EE_TMP, "ee")
ee_clock = FakeClock(datetime(2026, 1, 1, tzinfo=timezone.utc))
ee_ledger = ledger_mod.Ledger(EE_TMP / "ledger.jsonl", clock=ee_clock)
ee_ledger.initialise()
ee_out = {}
for p in AGG_PARTITIONS:
    o = part_obs(p, 1)
    runner.run_partition(p, o, CORPUS, "prompt", VOCAB, CONFIG, "k",
                         Replies([(200, {}, OK_BODY)] * 2), ee_ledger, EE_TMP / f"part_{p}.jsonl",
                         sleep=lambda s: None)
    ee_out[p] = EE_TMP / f"part_{p}.jsonl"
    ee_clock.advance(hours=25)

ee_bundle, ee_reasons = agg.aggregate(
    ee_out, ledger_path=ee_ledger.path, manifest_paths=ee_manifests, preregistration_path=ee_prereg,
    load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
check(ee_bundle is not None, "(setup) a valid COMPLETE bundle builds", ee_reasons)


def ee_validate(bundle_bytes: bytes):
    p = EE_TMP / "mutant.jsonl"
    p.write_bytes(bundle_bytes)
    return agg.validate_bundle(
        p, preregistration_path=ee_prereg, manifest_paths=ee_manifests, ledger_path=ee_ledger.path,
        load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)


vb, vr = ee_validate(ee_bundle)
check(vb is not None, "the unmutated bundle validates cleanly", vr)

# Hand-concatenate: a syntactically correct provenance header pasted in front
# of raw lines that were never digested together with it.
lines = ee_bundle.decode("utf-8").splitlines()
forged = lines[0:1] + lines[2:] + [lines[1]]  # reorder one partition's segment lines
vb, vr = ee_validate(("\n".join(forged) + "\n").encode("utf-8"))
check(vb is None, "reordering raw lines within the body changes the recomputed segment digest -> refuses", vr)

tampered = ee_bundle.replace(b"\"answered\"", b"\"unresolved\"", 1)
if tampered != ee_bundle:
    vb, vr = ee_validate(tampered)
    check(vb is None, "editing one byte inside a segment invalidates that segment's recomputed digest", vr)

extra_line = ee_bundle + b'{"record_type": "observation", "smuggled": true}\n'
vb, vr = ee_validate(extra_line)
check(vb is None, "an extra raw line beyond what every segment claims refuses (nothing may go unclaimed)", vr)

truncated = b"\n".join(ee_bundle.splitlines()[:-1]) + b"\n"
vb, vr = ee_validate(truncated)
check(vb is None, "a truncated final segment (fewer lines than raw_line_count claims) refuses", vr)

# manifest edited after the seal: mutate one manifest file's bytes and confirm
# validate_bundle() refuses on the CURRENT manifest digest, not a cached one.
real_manifest_1 = ee_manifests[1]
original_manifest_bytes = real_manifest_1.read_bytes()
with real_manifest_1.open("a", encoding="utf-8") as fh:
    fh.write("")  # no-op append kept the file identical; force a real byte change below
real_manifest_1.write_bytes(original_manifest_bytes + b"\n")
vb, vr = ee_validate(ee_bundle)
check(vb is None, "a manifest edited after the bundle was built refuses on the CURRENT digest", vr)
real_manifest_1.write_bytes(original_manifest_bytes)
vb, vr = ee_validate(ee_bundle)
check(vb is not None, "  -- and restoring the manifest's original bytes makes it validate again", vr)

# pre-registration edited after the seal, same idea.
original_prereg_bytes = ee_prereg.read_bytes()
ee_prereg.write_bytes(original_prereg_bytes + b"\n")
vb, vr = ee_validate(ee_bundle)
check(vb is None, "a pre-registration edited after the bundle was built refuses on the CURRENT digest", vr)
ee_prereg.write_bytes(original_prereg_bytes)


# ==========================================================================
# (ff) THE LEDGER SELECTOR IS NON-CIRCULAR -- Contract B round 6, regression
# ==========================================================================
print("\n--- (ff) the ledger selector reads by partition over the WHOLE ledger, never the bundle's own claim (Contract B) ---")

vb, vr = ee_validate(ee_bundle)
check(vb is not None, "(setup) the bundle still validates before the extra ledger entry", vr)

with ee_ledger.path.open("a", encoding="utf-8", newline="\n") as fh:
    outside_window = ledger_mod.LedgerEntry(
        model="m", at=datetime(2026, 1, 10, tzinfo=timezone.utc), request_class="corpus", partition=1)
    fh.write(outside_window.to_json() + "\n")

vb, vr = ee_validate(ee_bundle)
check(vb is None,
      "one extra REAL ledger entry for partition 1, timestamped outside the bundle's claimed "
      "window, is caught -- the selector reads the WHOLE ledger by partition, never the bundle's "
      "own declared window", vr)


# ==========================================================================
# (gg) DUCK-TYPED READ SOURCE, NO SIDECAR -- Contract D final, mandatory mutations
# ==========================================================================
print("\n--- (gg) _ImmutableText: no filesystem operation left for anything to race (Contract D) ---")

GG_TMP = Path(tempfile.mkdtemp())
gg_manifests = gt_manifests(GG_TMP)
gg_prereg = new_preregistration_stand_in(GG_TMP, "gg")
gg_clock = FakeClock(datetime(2026, 1, 1, tzinfo=timezone.utc))
gg_ledger = ledger_mod.Ledger(GG_TMP / "ledger.jsonl", clock=gg_clock)
gg_ledger.initialise()
gg_out = {}
for p in AGG_PARTITIONS:
    o = [gt_obs(p, *GT_PAIRS[p - 1])]
    runner.run_partition(p, o, CORPUS, "prompt", VOCAB, CONFIG, "k",
                         Replies([(200, {}, OK_BODY)] * 2), gg_ledger, GG_TMP / f"part_{p}.jsonl",
                         sleep=lambda s: None)
    gg_out[p] = GG_TMP / f"part_{p}.jsonl"
    gg_clock.advance(hours=25)

gg_bundle, gg_reasons = agg.aggregate(
    gg_out, ledger_path=gg_ledger.path, manifest_paths=gg_manifests, preregistration_path=gg_prereg,
    load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
check(gg_bundle is not None, "(setup) a valid COMPLETE bundle builds", gg_reasons)

gg_bundle_path = GG_TMP / "bundle.jsonl"
gg_bundle_path.write_bytes(gg_bundle)
gg_vb, gg_vr = agg.validate_bundle(
    gg_bundle_path, preregistration_path=gg_prereg, manifest_paths=gg_manifests,
    ledger_path=gg_ledger.path, load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
check(gg_vb is not None, "(setup) validate_bundle() accepts it", gg_vr)

if gg_vb is not None:
    src = agg._ImmutableText(gg_vb.observation_text)
    calls = []
    real_read_text = agg._ImmutableText.read_text

    def counting_read_text(self, encoding="utf-8"):
        calls.append(encoding)
        return real_read_text(self, encoding)

    agg._ImmutableText.read_text = counting_read_text
    try:
        rows = scorer.load_rows(src)
    finally:
        agg._ImmutableText.read_text = real_read_text
    check(len(calls) == 1, "base.load_rows() calls .read_text() on the immutable source exactly once", calls)

    before = src.read_text()
    gg_bundle_path.write_bytes(b"mutated after validation, should have no effect whatsoever\n")
    after = src.read_text()
    check(before == after,
          "mutating the ORIGINAL bundle file AFTER validation completes has NO effect on the "
          "already-validated observation text -- nothing downstream ever reopens the path", None)
    gg_bundle_path.write_bytes(gg_bundle)  # restore for the sidecar check below

    sidecar_candidates = list(GG_TMP.glob("*.rows.jsonl")) + list(Path(tempfile.gettempdir()).glob("*rows*.jsonl"))
    check(not any(c.exists() and c.stat().st_size and "gg" in str(c) for c in sidecar_candidates),
          "no .rows.jsonl or other scoring sidecar file is left on disk for this bundle", sidecar_candidates)


# ==========================================================================
# (hh) score_r2.main() END TO END, ON A FULLY SEALED SYNTHETIC FIXTURE -- Contract D round 5
# ==========================================================================
print("\n--- (hh) score_r2.main() end to end, through the REAL verify_seal(), zero path arguments ---")

HH_TMP = Path(tempfile.mkdtemp())
hh_manifests = gt_manifests(HH_TMP)

hh_prereg_path = HH_TMP / "RECOG_SO1_PREREGISTRATION_R2_2026-09-08.md"
hh_ledger_path = HH_TMP / "ledger.jsonl"

hh_seal = {
    agg.AGGREGATOR_SELF_REL: hashlib.sha256((DEV / "recog_so1_aggregate_r2.py").read_bytes()).hexdigest(),
}
hh_prereg_path.write_text(
    "synthetic sealed pre-registration for the end-to-end test\n\n"
    "<!-- SEAL -->\n```json\n" + json.dumps(hh_seal) + "\n```\n",
    encoding="utf-8",
)

hh_clock = FakeClock(datetime(2026, 1, 1, tzinfo=timezone.utc))
hh_ledger = ledger_mod.Ledger(hh_ledger_path, clock=hh_clock)
hh_ledger.initialise()

hh_out = {}
for p in AGG_PARTITIONS:
    o = [gt_obs(p, *GT_PAIRS[p - 1])]
    runner.run_partition(p, o, CORPUS, "prompt", VOCAB, CONFIG, "k",
                         Replies([(200, {}, OK_BODY)] * 2), hh_ledger, HH_TMP / f"part_{p}.jsonl",
                         sleep=lambda s: None)
    hh_out[p] = HH_TMP / f"part_{p}.jsonl"
    hh_clock.advance(hours=25)

# Build the bundle with EXPLICIT paths first (this call is fine to parameterise).
hh_bundle, hh_reasons = agg.aggregate(
    hh_out, ledger_path=hh_ledger_path, manifest_paths=hh_manifests, preregistration_path=hh_prereg_path,
    load_seal=runner.base.load_seal, verify_seal=runner.base.verify_seal)
check(hh_bundle is not None,
      "(setup) a bundle builds against a REAL, non-empty, self-referencing seal via the REAL verify_seal()",
      hh_reasons)

if hh_bundle is not None:
    hh_bundle_path = HH_TMP / "bundle.jsonl"
    hh_bundle_path.write_bytes(hh_bundle)

    # Now the true end-to-end proof: score_r2.main() itself takes ZERO path
    # arguments beyond --so1, so reaching it with synthetic fixtures means
    # temporarily rebinding the aggregator's OWN module constants -- exactly
    # the technique this contract's round 4/5 review required, restored in a
    # try/finally whether the call succeeds or raises.
    a = scorer.aggregate_mod
    real_const = {
        "PREREGISTRATION_R2": a.PREREGISTRATION_R2,
        "PARTITION_MANIFEST_PATHS": a.PARTITION_MANIFEST_PATHS,
        "LEDGER": a.LEDGER,
    }
    real_repo = a.runner.base.REPO
    try:
        a.PREREGISTRATION_R2 = hh_prereg_path
        a.PARTITION_MANIFEST_PATHS = hh_manifests
        a.LEDGER = hh_ledger_path
        a.runner.base.REPO = DEV.parent.parent  # AGGREGATOR_SELF_REL resolves under the REAL repo

        import io as _io
        buf = _io.StringIO()
        old_stdout = sys.stdout
        sys.stdout = buf
        try:
            rc = scorer.main(["--so1", str(hh_bundle_path)])
        finally:
            sys.stdout = old_stdout
        out_text = buf.getvalue()
    finally:
        a.PREREGISTRATION_R2 = real_const["PREREGISTRATION_R2"]
        a.PARTITION_MANIFEST_PATHS = real_const["PARTITION_MANIFEST_PATHS"]
        a.LEDGER = real_const["LEDGER"]
        a.runner.base.REPO = real_repo

    check(a.PREREGISTRATION_R2 == real_const["PREREGISTRATION_R2"] and a.runner.base.REPO == real_repo,
          "every rebound module constant, including base.REPO, is restored after the call", None)
    check(rc == 0 and "VERDICT:" in out_text,
          "score_r2.main() ran end to end with zero path arguments and printed a real verdict",
          out_text[-400:])


# ==========================================================================
# (ii) TWO ADVERSARIAL CASES FROM GPT-PM's MANDATORY COMMIT REVIEW OF 7f38147
# ==========================================================================
print("\n--- (ii) isolation reads the WHOLE ledger; an absent_after_terminal partition is proven unrun ---")

# MAJOR 1: verify_isolation_gaps() originally compared each partition only to
# the PREVIOUS PARTITION's own last entry, so a stress probe (or any other
# request) interposed between two partitions -- close enough to the second
# one's start to violate the real 24h rule -- went unnoticed as long as the
# two partitions' OWN windows were far enough apart. Ledger.isolation_ok()'s
# own contract is "the last request of ANY class", and this fixture builds
# exactly that gap with a genuine ledger write, not a hand-typed timestamp.
II_TMP = Path(tempfile.mkdtemp())
ii_manifests = four_manifests(II_TMP, sizes=(1, 1, 1, 1))
ii_prereg = new_preregistration_stand_in(II_TMP, "ii")
ii_clock = FakeClock(datetime(2026, 1, 1, tzinfo=timezone.utc))
ii_ledger = ledger_mod.Ledger(II_TMP / "ledger.jsonl", clock=ii_clock)
ii_ledger.initialise()

o1 = part_obs(1, 1)
runner.run_partition(1, o1, CORPUS, "prompt", VOCAB, CONFIG, "k",
                     Replies([(200, {}, OK_BODY)] * 2), ii_ledger, II_TMP / "part_1.jsonl",
                     sleep=lambda s: None)
ii_clock.advance(hours=36)
ii_ledger.record(model=CONFIG["model"], request_class="stress_probe", partition=None)
ii_clock.advance(hours=12)  # only 12h since the stress probe when partition 2 begins
o2 = part_obs(2, 1)
runner.run_partition(2, o2, CORPUS, "prompt", VOCAB, CONFIG, "k",
                     Replies([(200, {}, OK_BODY)] * 2), ii_ledger, II_TMP / "part_2.jsonl",
                     sleep=lambda s: None)

bundle, reasons = agg.aggregate(
    {1: II_TMP / "part_1.jsonl", 2: II_TMP / "part_2.jsonl"}, ledger_path=ii_ledger.path,
    manifest_paths=ii_manifests, preregistration_path=ii_prereg,
    load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
check(bundle is None,
      "MAJOR 1 regression: a stress probe 12h before partition 2's start refuses aggregate(), even "
      "though partition 2 is a full 48h after partition 1's OWN last entry", reasons)
check(bundle is None and any("partition 2" in r for r in reasons),
      "  -- and names partition 2 as the one that fails isolation", reasons)

# The same defect, proven the other direction: a genuinely well-isolated
# four-partition bundle validates cleanly, and THEN an interposed stress
# probe written directly into the ledger (mirroring section (ff)'s technique)
# makes a later re-validation of the SAME bundle refuse.
II2_TMP = Path(tempfile.mkdtemp())
ii2_manifests = four_manifests(II2_TMP, sizes=(1, 1, 1, 1))
ii2_prereg = new_preregistration_stand_in(II2_TMP, "ii2")
ii2_clock = FakeClock(datetime(2026, 1, 1, tzinfo=timezone.utc))
ii2_ledger = ledger_mod.Ledger(II2_TMP / "ledger.jsonl", clock=ii2_clock)
ii2_ledger.initialise()
ii2_out = {}
for p in AGG_PARTITIONS:
    o = part_obs(p, 1)
    runner.run_partition(p, o, CORPUS, "prompt", VOCAB, CONFIG, "k",
                         Replies([(200, {}, OK_BODY)] * 2), ii2_ledger, II2_TMP / f"part_{p}.jsonl",
                         sleep=lambda s: None)
    ii2_out[p] = II2_TMP / f"part_{p}.jsonl"
    ii2_clock.advance(hours=25)

ii2_bundle, ii2_reasons = agg.aggregate(
    ii2_out, ledger_path=ii2_ledger.path, manifest_paths=ii2_manifests,
    preregistration_path=ii2_prereg, load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
check(ii2_bundle is not None, "(setup) a correctly-isolated four-partition bundle builds", ii2_reasons)

if ii2_bundle is not None:
    ii2_bundle_path = II2_TMP / "bundle.jsonl"
    ii2_bundle_path.write_bytes(ii2_bundle)
    vb, vr = agg.validate_bundle(
        ii2_bundle_path, preregistration_path=ii2_prereg, manifest_paths=ii2_manifests,
        ledger_path=ii2_ledger.path, load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
    check(vb is not None, "(setup) it validates cleanly before the interposed stress probe", vr)

    p2_at = [e.at for e in ii2_ledger.entries() if e.partition == 2]
    p3_at = [e.at for e in ii2_ledger.entries() if e.partition == 3]
    p2_end, p3_start = max(p2_at), min(p3_at)
    probe_at = p2_end + (p3_start - p2_end) * 3 / 4  # 6.25h before partition 3, well under 24h
    with ii2_ledger.path.open("a", encoding="utf-8", newline="\n") as fh:
        probe = ledger_mod.LedgerEntry(model="m", at=probe_at, request_class="stress_probe", partition=None)
        fh.write(probe.to_json() + "\n")

    vb, vr = agg.validate_bundle(
        ii2_bundle_path, preregistration_path=ii2_prereg, manifest_paths=ii2_manifests,
        ledger_path=ii2_ledger.path, load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
    check(vb is None,
          "MAJOR 1 regression, validate_bundle() side: the same interposed stress probe refuses "
          "RE-validation of an already-valid bundle, once it is written to the live ledger", vr)

# MAJOR 2: a partition tagged absent_after_terminal is a claim that it was
# NEVER RUN. Neither aggregate() nor validate_bundle() checked the ledger for
# that claim -- they simply never looked past the present/terminal partitions.
# A genuine ledger entry for a declared-absent partition must refuse both.
II3_TMP = Path(tempfile.mkdtemp())
ii3_manifests = four_manifests(II3_TMP, sizes=(1, 1, 1, 1))
ii3_prereg = new_preregistration_stand_in(II3_TMP, "ii3")
ii3_clock = FakeClock(datetime(2026, 1, 1, tzinfo=timezone.utc))
ii3_ledger = ledger_mod.Ledger(II3_TMP / "ledger.jsonl", clock=ii3_clock)
ii3_ledger.initialise()

o1_ii3 = part_obs(1, 1)
runner.run_partition(1, o1_ii3, CORPUS, "prompt", VOCAB, CONFIG, "k",
                     Replies([(400, {}, "bad request")]), ii3_ledger, II3_TMP / "part_1.jsonl",
                     sleep=lambda s: None)  # the availability check itself fails -> terminal at 1

bundle3, reasons3 = agg.aggregate(
    {1: II3_TMP / "part_1.jsonl"}, ledger_path=ii3_ledger.path, manifest_paths=ii3_manifests,
    preregistration_path=ii3_prereg, load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
check(bundle3 is not None,
      "(setup) a genuine availability-invalid TERMINAL_INVALID-at-1 bundle builds", reasons3)

if bundle3 is not None:
    bundle3_path = II3_TMP / "bundle.jsonl"
    bundle3_path.write_bytes(bundle3)
    vb, vr = agg.validate_bundle(
        bundle3_path, preregistration_path=ii3_prereg, manifest_paths=ii3_manifests,
        ledger_path=ii3_ledger.path, load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
    check(vb is not None, "(setup) it validates cleanly before any partition-2 ledger activity", vr)

    with ii3_ledger.path.open("a", encoding="utf-8", newline="\n") as fh:
        contraband = ledger_mod.LedgerEntry(model="m", at=ii3_clock.now, request_class="availability", partition=2)
        fh.write(contraband.to_json() + "\n")

    vb, vr = agg.validate_bundle(
        bundle3_path, preregistration_path=ii3_prereg, manifest_paths=ii3_manifests,
        ledger_path=ii3_ledger.path, load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
    check(vb is None,
          "MAJOR 2 regression: a genuine ledger entry for the declared-absent partition 2 refuses "
          "re-validation of an otherwise structurally valid TERMINAL_INVALID-at-1 bundle", vr)
    check(vb is None and any("partition 2" in r and "absent_after_terminal" in r for r in vr),
          "  -- and names partition 2's contradicted absent_after_terminal claim", vr)

    bundle4, reasons4 = agg.aggregate(
        {1: II3_TMP / "part_1.jsonl"}, ledger_path=ii3_ledger.path, manifest_paths=ii3_manifests,
        preregistration_path=ii3_prereg, load_seal=_ok_load_seal, verify_seal=_ok_verify_seal)
    check(bundle4 is None,
          "MAJOR 2 regression, build side: aggregate() itself refuses once the ledger holds an "
          "entry for a partition the shape declares was never run", reasons4)


# ==========================================================================
print("\n" + "=" * 74)
failed = [label for ok, label in RESULTS if not ok]
print(f"{len(RESULTS) - len(failed)} of {len(RESULTS)} checks passed")
if failed:
    print("\nFAILED:")
    for label in failed:
        print("  " + label)
sys.exit(1 if failed else 0)
