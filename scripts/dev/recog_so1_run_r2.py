"""RECOG-SO1 revision 2 runner: guard the limits that actually exist, one partition at a time.

Revision 1 paced against ITPM, 7,000 input tokens per minute, which it had
measured from a real 429. That measurement was correct and it was not the
binding constraint. What stopped the run was TPD -- 200,000 tokens per DAY,
enforced per ORGANISATION -- and OTPM, a 1,000-output-token PER-REQUEST ceiling
that no amount of pacing can reach. 260 requests produced 104 observations, 58
of them refusals, and nothing in the program knew how much had been spent.

FOUR THINGS ARE DIFFERENT HERE.

1.  A LEDGER, and it is the only authority. Every transmission of every class --
    stress probe, availability check, corpus observation, and every retry
    attempt separately -- is written before it is sent. The partition's request
    count and the isolation clock are both read from it and from nothing else.
    A ledger that is missing, unreadable or malformed stops the run.

2.  ONE WAIT AUTHORITY. Revision 1 had two: the ordinary pacing sleep and
    `pace_after_failure()`, which took max(pacing, Retry-After) on the failure
    path only. Adding a TPM guard beside them would have left three signals with
    no defined composition. Instead `next_wait_seconds()` folds all three into
    one maximum, taken once, before every transport call. `pace_after_failure`
    does not exist in this revision.

3.  A FROZEN DECISION TABLE, read from the sealed config as data, that FAILS
    CLOSED. Note the trap it is built around: the TPD refusal and the ordinary
    rolling-window refusal BOTH begin "Rate limit reached for model ...". A
    classifier keyed on that prefix would read a spent DAY as a spent minute and
    retry into it. So classification reads the parenthesised limit code -- (TPD),
    (RPD), (OTPM), (TPM), (RPM) -- AND, for (OTPM), the failure form as well,
    because that one code covers both a permanent per-request ceiling and an
    ordinary rolling window. Anything else stops the run.

4.  FOUR PARTITIONS, at least 24 hours apart. The experiment does not fit in one
    day on this tier: 2,153 mean prompt tokens x 104 observations is 223,962
    against a 200,000 daily ceiling.

WHAT IS UNCHANGED, and is unchanged by IMPORTING revision 1 rather than
restating it: the seal check, the consent state machine, the closed manifest
schema, the single image-reading function, the transports and the reply parser.
Revision 1's file is never edited, so its seal still verifies and run #1 remains
judgeable by the protocol it actually ran under.

BLINDNESS IS UNCHANGED. The request carries the frozen prompt, the frozen
machine list and one image. The partition a photograph belongs to is derived
from the ground truth, so it is never a column in the runner's input -- the four
partitions are four separate files carrying revision 1's closed schema exactly,
and the partition is named by which file the runner is pointed at.
"""

from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import importlib.util
import io
import json
import re
import sys
import time
import urllib.error
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable, Mapping

REPO = Path(__file__).resolve().parents[2]
PLANS = REPO / "core" / "plans"
DEV = REPO / "scripts" / "dev"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


#: The sealed revision 1 runner. Imported, never edited.
base = _load_module("so1_run_base", DEV / "recog_so1_run.py")
ledger_mod = _load_module("so1_ledger", DEV / "recog_so1_ledger.py")

Ledger = ledger_mod.Ledger
LedgerUnusable = ledger_mod.LedgerUnusable
Observation = base.Observation
CapturingTransport = base.CapturingTransport
HttpTransport = base.HttpTransport

PREREGISTRATION_R2 = PLANS / "RECOG_SO1_PREREGISTRATION_R2_2026-09-08.md"
CONSENT_R2 = PLANS / "RECOG_SO1_CONSENT_R2.json"
CONFIG_R2 = DEV / "recog_so1_config_r2.json"
PROMPT = DEV / "recog_so1_prompt.txt"
VOCAB = DEV / "recog_so1_vocab.json"
LEDGER = PLANS / "recog_so1_raw" / "RECOG_SO1_QWEN_REQUEST_LEDGER.jsonl"


def partition_manifest(partition: int) -> Path:
    return PLANS / f"RECOG_SO1_PARTITION_{partition}_R2_2026-09-08.csv"


# --------------------------------------------------------------------------
# The request: the enum is DERIVED from the sealed vocabulary
# --------------------------------------------------------------------------

def machine_enum(vocab: dict) -> list[str]:
    """The 71 canonical names in the sealed vocabulary, plus the sentinel.

    Derived rather than copied into the config, because a hand-typed list there
    could drift from the vocabulary the prompt is built from and nothing would
    notice. In the vocabulary's own order, so the transmitted body is stable.
    """
    names = list(vocab["canonical_machines"])
    sentinel = vocab["unknown_sentinel"]
    if sentinel in names:
        return names
    return names + [sentinel]


def resolve_schema(schema: dict, enum: list[str]) -> dict:
    """Replace every {'enum_from_vocab': true} marker with the real enum.

    The marker is a build-time instruction and is never transmitted: this
    function removes it and puts an explicit `enum` in its place.
    """
    out = copy.deepcopy(schema)

    def walk(node):
        if isinstance(node, dict):
            if node.pop("enum_from_vocab", None) is True:
                node["enum"] = list(enum)
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(out)
    return out


def build_request_body(prompt: str, image_bytes: bytes, config: dict, vocab: dict) -> bytes:
    """The whole semantic payload: the frozen prompt, and one image. Nothing else."""
    data_url = "data:image/jpeg;base64," + base64.b64encode(image_bytes).decode("ascii")
    payload = {
        "model": config["model"],
        "temperature": config["temperature"],
        "top_p": config["top_p"],
        "seed": config["seed"],
        "max_completion_tokens": config["max_completion_tokens"],
        "response_format": resolve_schema(config["response_format"], machine_enum(vocab)),
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": prompt},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            }
        ],
    }
    payload.update(config.get("extra_body") or {})
    return json.dumps(payload).encode("utf-8")


# --------------------------------------------------------------------------
# The ONE wait authority
# --------------------------------------------------------------------------

_DURATION = re.compile(
    r"^\s*(?:(?P<h>\d+(?:\.\d+)?)h)?(?:(?P<m>\d+(?:\.\d+)?)m)?(?:(?P<s>\d+(?:\.\d+)?)s?)?\s*$"
)


def parse_duration_seconds(raw: str | None) -> float | None:
    """Groq writes durations as '7.66s', '2m59.56s', '16m26.688s' -- not bare seconds.

    A plain number is accepted too. Anything else returns None, which the wait
    rule treats as a malformed reset: the conservative 60-second branch, never
    zero.
    """
    if raw is None:
        return None
    text = str(raw).strip()
    if not text:
        return None
    m = _DURATION.match(text)
    if not m or not any(m.group(g) for g in ("h", "m", "s")):
        return None
    total = 0.0
    for group, factor in (("h", 3600.0), ("m", 60.0), ("s", 1.0)):
        value = m.group(group)
        if value is not None:
            total += float(value) * factor
    return total


def parse_number(raw: str | None) -> float | None:
    """A bare number, or None. Used for remaining-tokens and Retry-After.

    Retry-After may legally be an HTTP-date; that returns None and therefore
    contributes NOTHING, exactly as the frozen rule says.
    """
    if raw is None:
        return None
    try:
        return float(str(raw).strip())
    except (TypeError, ValueError):
        return None


def header(headers: Mapping[str, str] | None, name: str) -> str | None:
    """Case-insensitive lookup. HTTP header case is not guaranteed by anyone."""
    if not headers:
        return None
    lowered = name.lower()
    for key, value in headers.items():
        if str(key).lower() == lowered:
            return value
    return None


def next_wait_seconds(
    resp_headers: Mapping[str, str] | None,
    wait_rule: Mapping[str, float],
    after_retryable_429: bool = False,
) -> float:
    """The interval before the NEXT transport call. The only function that decides one.

        wait = ordinary_pacing_seconds
        if the latest VALID remaining-tokens header < next_request_tpm_bound:
            wait = max(wait, reset + tpm_reset_margin_seconds)
            or max(wait, missing_reset_wait_seconds) if that reset is unusable
        if this attempt follows a retryable 429 with a VALID Retry-After:
            wait = max(wait, Retry-After)
        sleep ONCE for wait

    MAXIMUM, NEVER ADDITION. Each term states the earliest moment the next
    request may go out, so the binding one is the latest of them; adding them
    would honour none of the three and would stretch a 44-request partition past
    every wall-clock estimate in the pre-registration.

    Not knowing is never a reason to go faster: an absent or unparseable
    remaining-tokens header leaves the ordinary interval, and an unusable reset
    on a LOW window takes the conservative fallback rather than zero.

    The remaining-tokens and reset-tokens headers describe Groq's TOKENS-PER-
    MINUTE window. They are not an ITPM or OTPM remaining budget, and they say
    nothing whatever about the day -- the daily ceiling is accounted locally
    from the ledger.
    """
    ordinary = float(wait_rule["ordinary_pacing_seconds"])
    bound = float(wait_rule["next_request_tpm_bound"])
    margin = float(wait_rule["tpm_reset_margin_seconds"])
    fallback = float(wait_rule["missing_reset_wait_seconds"])

    wait = ordinary

    remaining = parse_number(header(resp_headers, "x-ratelimit-remaining-tokens"))
    if remaining is not None and remaining < bound:
        reset = parse_duration_seconds(header(resp_headers, "x-ratelimit-reset-tokens"))
        wait = max(wait, fallback) if reset is None else max(wait, reset + margin)

    if after_retryable_429:
        asked = parse_number(header(resp_headers, "Retry-After"))
        if asked is not None:
            wait = max(wait, asked)

    return wait


# --------------------------------------------------------------------------
# The frozen decision table
# --------------------------------------------------------------------------

#: Groq names the limit it enforced in parentheses. Both the daily refusal and
#: the ordinary rolling-window refusal open with "Rate limit reached for model",
#: so the OPENING WORDS ARE NOT A CLASSIFIER -- only the code is.
LIMIT_CODES = {
    "TPD": "tpd_exhausted",
    "RPD": "tpd_exhausted",
    "TPM": "rolling_window_429",
    "RPM": "rolling_window_429",
}
_CODE = re.compile(r"\((TPD|RPD|OTPM|TPM|RPM)\)")

#: `(OTPM)` alone does not say which failure it is, so the FORM decides.
_OTPM_PERMANENT = re.compile(r"request too large|expected output tokens exceed", re.I)
_OTPM_ROLLING = re.compile(r"rate limit reached", re.I)

TRANSPORT_FAILURE_STATUSES = frozenset({500, 502, 503, 504})

#: HTTP 200 never happened: the request did not complete at all.
TRANSPORT_EXCEPTION_STATUS = 0


def classify_429(body: str) -> str:
    """Which limit refused this request, and in which form? Unknown means STOP.

    Two different classifications hide behind one code. `(OTPM)` is the
    per-request output ceiling when the body says the request is too large, and
    an ordinary rolling window when the body says a rate limit was reached --
    the first is structural and stops the run, the second is retried twice.
    Reading only the code would turn a transient minute-window refusal into a
    whole invalidated partition; that was GPT-PM's MAJOR against the first
    implementation, and the sealed config had said the right thing all along
    while the code did something else.
    """
    text = body or ""
    m = _CODE.search(text)
    if not m:
        return "unrecognised_429"
    code = m.group(1)
    if code != "OTPM":
        return LIMIT_CODES[code]
    if _OTPM_PERMANENT.search(text):
        return "otpm_request_too_large"
    if _OTPM_ROLLING.search(text):
        return "rolling_window_429"
    # An (OTPM) body in wording nobody has seen. Fail closed.
    return "unrecognised_429"


def classify(status: int, body: str) -> str:
    """The outcome class for one transport result, from the frozen table."""
    if status == 200:
        return "ok"
    if status == TRANSPORT_EXCEPTION_STATUS:
        return "transport_failure"
    if status == 429:
        return classify_429(body)
    if status in TRANSPORT_FAILURE_STATUSES:
        return "transport_failure"
    if status in (400, 401, 403, 404):
        return f"http_{status}"
    # A status nobody classified is a limit nobody is guarding.
    return "unrecognised_status"


#: Everything a real network can raise instead of returning a status. The
#: imported revision 1 transport converts only HTTPError; a read timeout or a
#: reset connection propagates straight out of it. Without this conversion the
#: frozen "transport_failure -> exactly 3 attempts" row is unreachable with the
#: real transport, and a timeout crashes the process AFTER its ledger entry was
#: written -- spent budget with no matching result record. GPT-PM's MAJOR.
TRANSPORT_EXCEPTIONS: tuple[type[BaseException], ...] = (
    urllib.error.URLError,
    TimeoutError,
    ConnectionError,
    OSError,
)


def post_with_transport_failures(transport, url, headers, body) -> tuple[int, dict, str]:
    """Call the transport, converting a raised network error into the frozen class."""
    try:
        return transport.post(url, headers, body)
    except TRANSPORT_EXCEPTIONS as exc:
        return TRANSPORT_EXCEPTION_STATUS, {}, f"transport exception: {type(exc).__name__}: {exc}"


def table_entry(config: dict, cls: str) -> dict:
    table = config["decision_table"]
    if cls in table:
        return table[cls]
    # Fail closed: anything the sealed table does not name stops the run.
    return {"outcome": "INVALID_INSTRUMENT", "attempts": 1, "stops_run": True}


# --------------------------------------------------------------------------
# Guards read from the ledger
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class Refusal:
    reason: str
    invalid_class: str | None = None


def budget_room(ledger: Ledger, config: dict, partition: int) -> Refusal | None:
    """May ONE more request be made for this partition? Local accounting only.

    The provider exposes no remaining-per-day figure, and the minute-window
    headers say nothing about the day. So the day is counted here, against the
    ledger, at the empirical per-request charge bound.
    """
    budget = config["budget"]
    charge = float(budget["empirical_charge_bound_per_request"])
    daily = float(budget["daily_experiment_budget"])
    already = ledger.partition_request_count(partition)
    if (already * charge) + charge > daily:
        return Refusal(
            f"partition {partition} has already made {already} requests; one more would put "
            f"{(already + 1) * charge:.0f} tokens against the {daily:.0f} daily experiment budget "
            f"(ceiling {budget['requests_per_partition_ceiling']} requests)",
            invalid_class="ledger_budget_exceeded",
        )
    return None


def isolation_ok(ledger: Ledger, config: dict) -> Refusal | None:
    hours = int(config["isolation"]["hours_between_partitions"])
    ok, why = ledger.isolation_ok(hours)
    return None if ok else Refusal(f"isolation: {why}")


# --------------------------------------------------------------------------
# Consent, revision 2: one record binds the WHOLE rerun
# --------------------------------------------------------------------------

#: The closed schema for a revision 2 consent record. Revision 1's evaluator
#: cannot express this one, and that is not a matter of taste: its `allowed` set
#: is closed and REFUSES any unexpected property, so an organisation-exclusivity
#: attestation could not be recorded at all -- while the revision 2
#: pre-registration requires one. It also carries a single `manifest_sha256`,
#: which under four partition files would bind one partition and force the
#: consent record to be rewritten between partition days. GPT-PM's MAJOR, and
#: both halves of it are structural rather than cosmetic.
R2_CONSENT_FIELDS = frozenset({
    "decision", "recorded_at", "operator_statement", "preregistration_sha256",
    "partition_manifest_sha256", "groq_data_controls",
    "organisation_exclusivity_attested", "notes",
})

ConsentVerdict = base.ConsentVerdict
AFFIRMATIVE = base.AFFIRMATIVE


def evaluate_consent_r2(
    consent_path: Path,
    partition_digests: dict[int, str],
    preregistration_digest: str,
) -> ConsentVerdict:
    """AUTHORISED only for affirmative consent bound to the ENTIRE four-partition rerun.

    One immutable record covers all four partitions. Nothing is rewritten
    between partition days: rewriting a consent record to point at the next
    day's manifest would make "the operator consented" a thing this program
    edits on its own behalf.
    """
    if not consent_path.is_file():
        return ConsentVerdict(False, None, f"no consent record at {consent_path.name}")
    try:
        record = json.loads(consent_path.read_text("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return ConsentVerdict(False, None, f"consent record does not parse: {exc}")
    if not isinstance(record, dict):
        return ConsentVerdict(False, None, "consent record is not a JSON object")

    unexpected = sorted(set(record) - R2_CONSENT_FIELDS)
    if unexpected:
        return ConsentVerdict(False, None, f"consent record carries undefined properties: {unexpected}")

    decision = record.get("decision")
    if decision is None:
        return ConsentVerdict(False, None, "consent record names no decision")
    if decision == "deny":
        return ConsentVerdict(False, "deny", "the operator declined a second transmission")
    if decision not in AFFIRMATIVE:
        return ConsentVerdict(False, None, f"decision {decision!r} is not a recognised value")

    if not record.get("operator_statement"):
        return ConsentVerdict(False, decision, "affirmative consent carries no verbatim operator statement")

    bound_prereg = record.get("preregistration_sha256")
    if not bound_prereg:
        return ConsentVerdict(False, decision, "affirmative consent does not bind preregistration_sha256")
    if bound_prereg != preregistration_digest:
        return ConsentVerdict(
            False, decision,
            f"preregistration_sha256 binds {bound_prereg[:16]}... but the document on disk hashes "
            f"to {preregistration_digest[:16]}...",
        )

    bound = record.get("partition_manifest_sha256")
    if not isinstance(bound, dict):
        return ConsentVerdict(False, decision, "affirmative consent binds no partition manifests")
    expected_keys = {str(p) for p in partition_digests}
    if set(bound) != expected_keys:
        return ConsentVerdict(
            False, decision,
            f"consent binds partitions {sorted(bound)}; all of {sorted(expected_keys)} are "
            "required, because one record authorises the whole rerun and none of it is rewritten "
            "between partition days",
        )
    for partition, digest in sorted(partition_digests.items()):
        if bound[str(partition)] != digest:
            return ConsentVerdict(
                False, decision,
                f"partition {partition} binds {str(bound[str(partition)])[:16]}... but its "
                f"manifest hashes to {digest[:16]}...",
            )

    controls = record.get("groq_data_controls")
    if not isinstance(controls, dict) or "global_zdr" not in controls:
        return ConsentVerdict(False, decision, "affirmative consent records no provider retention state")

    if record.get("organisation_exclusivity_attested") is not True:
        return ConsentVerdict(
            False, decision,
            "affirmative consent carries no organisation-exclusivity attestation. The daily limit "
            "is enforced per organisation and the provider exposes nothing that could verify "
            "exclusivity, so the pre-registration requires the operator to attest it explicitly. "
            "Absent or false refuses.",
        )

    return ConsentVerdict(
        True, decision,
        f"{decision}, all {len(partition_digests)} partitions bound, exclusivity attested, "
        f"global_zdr={controls['global_zdr']!r}",
    )


# --------------------------------------------------------------------------
# Synthetic images, for availability and stress probes only
# --------------------------------------------------------------------------

#: The two real frame shapes, measured from the corpus during revision 1.
ARM_SHAPES = {"A": (1640, 1082), "B": (1868, 4000)}


def synthetic_jpeg(shape: tuple[int, int]) -> bytes:
    """A solid-colour frame of a real arm's dimensions. Contains no person.

    Used for the availability check and the stress probes so that neither
    spends a corpus photograph, and so that a probe run before consent exists
    transmits nothing identifiable.
    """
    from PIL import Image

    buf = io.BytesIO()
    Image.new("RGB", shape, (128, 128, 128)).save(buf, format="JPEG", quality=80)
    return buf.getvalue()


# --------------------------------------------------------------------------
# The run
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class RunOutcome:
    partition: int
    observations_total: int
    observations_processed: int
    answered: int
    unresolved: int
    requests_made: int
    invalid_instrument: str | None = None
    refused_before_start: str | None = None

    @property
    def invalid(self) -> bool:
        return self.invalid_instrument is not None


def run_partition(
    partition: int,
    observations: Iterable[Observation],
    corpus_root: Path,
    prompt: str,
    vocab: dict,
    config: dict,
    api_key: str,
    transport,
    ledger: Ledger,
    out: Path,
    sleep: Callable[[float], None] | None = None,
    availability: bool = True,
) -> RunOutcome:
    """One partition, start to finish, under the frozen table.

    `sleep` is resolved at call time rather than bound as a default, so the
    suite can substitute a recording clock and assert on intervals without a
    test ever sleeping for real.
    """
    nap = sleep if sleep is not None else time.sleep
    url = config["endpoint"]
    headers_base = {
        "Content-Type": "application/json",
        "User-Agent": config["user_agent"],
        "Authorization": f"Bearer {api_key}",
    }
    wait_rule = config["wait_rule"]
    model = config["model"]
    observations = list(observations)

    # -- guards, before any image byte is read -----------------------------
    refusal = isolation_ok(ledger, config)
    if refusal is not None:
        return RunOutcome(partition, len(observations), 0, 0, 0, 0,
                          refused_before_start=refusal.reason)

    requests_made = 0
    answered = 0
    unresolved = 0
    processed = 0
    invalid: str | None = None
    last_headers: dict[str, str] = {}

    @dataclass(frozen=True)
    class Attempted:
        cls: str
        status: int
        text: str
        attempts: int
        refusal: Refusal | None = None

    def send_with_retries(request_class: str, body: bytes) -> Attempted:
        """The ONE attempt engine. Budget-check, wait, LEDGER, send -- in that order.

        Every request class goes through here, availability included. The first
        implementation gave availability its own single-shot path, so a
        transient 429 on the very check meant to answer "is the model answering
        at all?" was recorded as "degraded" and the corpus was transmitted
        anyway. GPT-PM's MAJOR: the check's own question went unanswered and the
        photographs were spent regardless.
        """
        nonlocal requests_made, last_headers
        attempt = 0
        after_429 = False
        while True:
            nap(next_wait_seconds(last_headers, wait_rule, after_retryable_429=after_429))
            room = budget_room(ledger, config, partition)
            if room is not None:
                return Attempted("ledger_budget_exceeded", 0, room.reason, attempt, refusal=room)
            ledger.record(model=model, request_class=request_class, partition=partition)
            requests_made += 1
            status, resp_headers, text = post_with_transport_failures(
                transport, url, dict(headers_base), body)
            last_headers = dict(resp_headers or {})
            attempt += 1
            cls = classify(status, text)
            entry = table_entry(config, cls)
            if cls == "ok" or entry.get("stops_run"):
                return Attempted(cls, status, text, attempt)
            if attempt >= int(entry.get("attempts", 1)):
                return Attempted(cls, status, text, attempt)
            after_429 = cls == "rolling_window_429"

    with out.open("w", encoding="utf-8", newline="\n") as fh:
        # -- availability: is the model answering at all, before the corpus --
        if availability:
            probe = send_with_retries(
                "availability",
                build_request_body(prompt, synthetic_jpeg(ARM_SHAPES["A"]), config, vocab),
            )
            record = {
                "record_type": "availability",
                "http_status": probe.status,
                "failure_class": probe.cls,
                "attempts": probe.attempts,
                "_note": "an availability check, not a capability or quality measurement",
            }
            if probe.cls != "ok":
                # ONLY a success permits corpus transmission. An exhausted or
                # refused availability check is INVALID_INSTRUMENT -- never a
                # verdict, and never permission to proceed.
                marker = probe.cls if probe.refusal is not None else "availability_failed"
                record["invalid_instrument"] = marker
                record["detail"] = probe.text[:400]
                fh.write(json.dumps(record, ensure_ascii=False) + "\n")
                return RunOutcome(partition, len(observations), 0, 0, 0, requests_made,
                                  invalid_instrument=marker)
            record["status"] = "ok"
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")

        # -- the corpus ---------------------------------------------------
        for obs in observations:
            processed += 1
            path = corpus_root / obs.image_path
            record: dict = {
                "record_type": "observation",
                "observation_id": obs.observation_id,
                "source_photo_id": obs.source_photo_id,
                "arm": obs.arm,
                "partition": partition,
            }
            if not path.is_file():
                record.update(status="unresolved", failure="image_missing", detail=str(path))
                fh.write(json.dumps(record, ensure_ascii=False) + "\n")
                unresolved += 1
                continue

            image_bytes = base.read_image_bytes(path)
            got = hashlib.sha256(image_bytes).hexdigest()
            if got != obs.expected_sha256:
                record.update(status="unresolved", failure="image_digest_mismatch",
                              expected=obs.expected_sha256, found=got)
                fh.write(json.dumps(record, ensure_ascii=False) + "\n")
                unresolved += 1
                continue
            record["image_sha256"] = got

            body = build_request_body(prompt, image_bytes, config, vocab)
            sent = send_with_retries("corpus", body)
            cls, status, text = sent.cls, sent.status, sent.text
            stop_class: str | None = None
            if sent.refusal is not None:
                stop_class = sent.refusal.invalid_class or "ledger_budget_exceeded"
                record.update(status="unresolved", failure=stop_class, detail=sent.refusal.reason)
            elif table_entry(config, cls).get("stops_run") and cls != "ok":
                stop_class = cls

            record["attempts"] = sent.attempts
            record["http_status"] = status
            if stop_class is not None:
                record["invalid_instrument"] = stop_class
                if "detail" not in record:
                    record.update(status="unresolved", failure=stop_class, detail=text[:400])
                fh.write(json.dumps(record, ensure_ascii=False) + "\n")
                unresolved += 1
                invalid = stop_class
                break
            if cls != "ok":
                record.update(status="unresolved", failure=cls, detail=text[:400])
                fh.write(json.dumps(record, ensure_ascii=False) + "\n")
                unresolved += 1
                continue

            finish = finish_reason(text)
            if finish == "length":
                # Never retried: at temperature 0 with a fixed seed the retry
                # returns the same truncation, and retrying until a reply becomes
                # scoreable is sampling for a usable result.
                record.update(status="unresolved", failure="finish_reason_length", finish_reason=finish)
                fh.write(json.dumps(record, ensure_ascii=False) + "\n")
                unresolved += 1
                continue

            machine, diag = base.parse_reply(text, vocab)
            record["raw_reply"] = text[:4000]
            record.update(diag)
            if machine is None:
                record["status"] = "unresolved"
                unresolved += 1
            else:
                record["status"] = "answered"
                record["machine_raw"] = machine
                answered += 1
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")

    return RunOutcome(
        partition=partition,
        observations_total=len(observations),
        observations_processed=processed,
        answered=answered,
        unresolved=unresolved,
        requests_made=requests_made,
        invalid_instrument=invalid,
    )


def finish_reason(text: str) -> str | None:
    try:
        return json.loads(text)["choices"][0].get("finish_reason")
    except (json.JSONDecodeError, KeyError, IndexError, TypeError):
        return None


# --------------------------------------------------------------------------
# Stress probes: the token cap is CLEARED by measurement, not by a happy path
# --------------------------------------------------------------------------

STRESS_RECEIPT = PLANS / "RECOG_SO1_STRESS_PROBE_RECEIPT_R2.json"


#: A generous allowance for one `confidence` literal. 17 significant digits is
#: what an IEEE double round-trips through JSON; 19 bytes covers that with the
#: leading "0." included.
CONFIDENCE_LITERAL_BYTES = 19


def longest_canonical_names(vocab: dict, n: int = 3) -> list[str]:
    return sorted(vocab["canonical_machines"], key=len, reverse=True)[:n]


def worst_case_answer_bytes(vocab: dict) -> int:
    """The longest answer this schema PERMITS, measured rather than assumed.

    Since `machine` became an enum the names are no longer free text, so the
    longest possible answer is fully determined: the three longest canonical
    names in the sealed vocabulary, `alternatives` at its `maxItems` of 2, and
    three confidence literals. Everything else is fixed keys and punctuation.

    A UTF-8 byte is worth at least one token to any tokeniser, so the byte count
    is an upper bound on the token count. That makes this a real offline bound
    on serialization -- the thing a solid-colour probe can never demonstrate,
    because a gray frame produces the SHORTEST answer, not the longest.
    """
    names = longest_canonical_names(vocab, 3)
    while len(names) < 3:
        names.append(names[-1] if names else "unknown")
    filler = "0." + "1" * (CONFIDENCE_LITERAL_BYTES - 2)
    skeleton = json.dumps({
        "machine": names[0],
        "confidence": "<C>",
        "alternatives": [
            {"machine": names[1], "confidence": "<C>"},
            {"machine": names[2], "confidence": "<C>"},
        ],
    })
    # The placeholder travels as a quoted string; a real number has no quotes.
    return len(skeleton.replace('"<C>"', filler).encode("utf-8"))


def serialization_headroom_ok(config: dict, vocab: dict) -> Refusal | None:
    """Is `max_completion_tokens` above the longest answer the schema permits?

    A hard gate, not a comment: lengthen the vocabulary enough and this refuses.
    """
    worst = worst_case_answer_bytes(vocab)
    cap = int(config["max_completion_tokens"])
    if worst >= cap:
        return Refusal(
            f"the longest answer this schema permits is {worst} bytes, which is not below "
            f"max_completion_tokens {cap}. The cap must exceed the worst schema-valid answer, "
            "or a correct reply can be truncated into an unresolved observation."
        )
    return None


def stress_probe_receipt_ok(
    config: dict,
    receipt_path: Path = STRESS_RECEIPT,
    prompt_path: Path = PROMPT,
    vocab_path: Path = VOCAB,
) -> Refusal | None:
    """Does a receipt exist proving the PROVIDER accepts this exact request shape?

    Separate from `serialization_headroom_ok`, and deliberately: that one bounds
    what the schema permits and can be settled offline; this one asks whether
    Groq accepts the request at this cap, which cannot be, because the output-cost
    estimator behind `Requested 1072` is undocumented.

    GPT-PM's MAJOR against the first implementation: it accepted a receipt on a
    matching config digest, a non-empty probe list and no `finish_reason
    "length"` -- so a receipt recording two FAILED probes, with `cleared: false`
    and `finish_reason: null`, satisfied it. And it bound the config alone, so a
    probe obtained under a different prompt or vocabulary could clear a request
    shape it had never tested. Both holes are closed below.
    """
    if not receipt_path.is_file():
        return Refusal(
            f"no stress-probe receipt at {receipt_path.name}. Whether the provider accepts this "
            f"request shape at max_completion_tokens {config['max_completion_tokens']} has not "
            "been measured. Run --stress-probe first; until then this configuration is drafted, "
            "not cleared for transmission."
        )
    try:
        receipt = json.loads(receipt_path.read_text("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return Refusal(f"stress-probe receipt does not parse: {exc}")

    for field, path in (("config_sha256", CONFIG_R2), ("prompt_sha256", prompt_path),
                        ("vocab_sha256", vocab_path)):
        bound = receipt.get(field)
        actual = base.sha256_file(path)
        if bound != actual:
            return Refusal(
                f"the receipt binds {field} {str(bound)[:16]}... but {path.name} hashes to "
                f"{actual[:16]}...; it cleared a request shape that is not this one"
            )

    if receipt.get("cleared") is not True:
        return Refusal("the stress-probe receipt does not record cleared: true")

    probes = receipt.get("probes")
    if not isinstance(probes, list):
        return Refusal("the stress-probe receipt records no probes")

    # EXACTLY one probe per arm, and each must carry the real frame dimensions.
    # An earlier version compared only the SET of labels, so three records
    # labelled A, A, B satisfied it, and a receipt with no `dimensions` field at
    # all passed -- its own positive fixture was structurally such a receipt.
    # GPT-PM's round-2 MAJOR: labels are not evidence that the declared frame
    # shapes were ever probed.
    if len(probes) != len(ARM_SHAPES):
        return Refusal(
            f"the receipt records {len(probes)} probes; exactly {len(ARM_SHAPES)} are required, "
            f"one per arm shape"
        )
    by_arm: dict[str, dict] = {}
    for p in probes:
        if not isinstance(p, dict):
            return Refusal("a probe record is not an object")
        arm = p.get("arm_shape")
        if arm not in ARM_SHAPES:
            return Refusal(f"probe records unknown arm shape {arm!r}")
        if arm in by_arm:
            return Refusal(f"arm shape {arm!r} is recorded twice; exactly one probe per arm")
        by_arm[arm] = p
    missing = sorted(set(ARM_SHAPES) - set(by_arm))
    if missing:
        return Refusal(
            f"the receipt covers arm shapes {sorted(by_arm)}; {missing} missing. Both are "
            "required, because the two arms are different frame sizes"
        )

    for arm, p in sorted(by_arm.items()):
        expected = list(ARM_SHAPES[arm])
        got = p.get("dimensions")
        if got is None:
            return Refusal(
                f"probe {arm!r} records no dimensions. A label is not evidence that the declared "
                f"{expected[0]}x{expected[1]} frame was actually probed."
            )
        if list(got) != expected:
            return Refusal(
                f"probe {arm!r} records dimensions {list(got)}, not the declared "
                f"{expected}; it probed a frame this experiment does not send"
            )
        if p.get("failure_class") != "ok" or int(p.get("http_status", 0)) != 200:
            return Refusal(
                f"probe {arm!r} recorded http {p.get('http_status')!r} / "
                f"{p.get('failure_class')!r}; a failed probe is not clearance"
            )
        if p.get("finish_reason") == "length":
            return Refusal(
                f"probe {arm!r} finished on 'length'. The cap is not sufficient "
                "and this configuration must NOT be sealed as it stands."
            )
    return None


#: The receipt's own path, as it must appear in the seal.
STRESS_RECEIPT_SEALED_AS = "core/plans/RECOG_SO1_STRESS_PROBE_RECEIPT_R2.json"


def seal_binds_receipt(seal: dict[str, str]) -> Refusal | None:
    """A non-empty seal must cover the clearance evidence itself.

    Otherwise the receipt sits OUTSIDE the seal and can be replaced afterwards
    without `verify_seal()` noticing -- so the corpus path could later be
    cleared by evidence that is not the evidence sealing was performed on.
    GPT-PM's round-2 MAJOR, and it is a structural hole rather than a
    procedural one, so the fix is a check rather than a paragraph.
    """
    if not seal:
        return None  # the empty-seal refusal is a separate, earlier gate
    if STRESS_RECEIPT_SEALED_AS not in seal:
        return Refusal(
            f"the seal does not cover {STRESS_RECEIPT_SEALED_AS}. The stress-probe receipt is the "
            "evidence this configuration was cleared on; leaving it outside the seal would let it "
            "be replaced afterwards without verification failing."
        )
    return None


def run_stress_probes(
    api_key: str,
    transport,
    ledger: Ledger,
    receipt_path: Path = STRESS_RECEIPT,
    sleep: Callable[[float], None] | None = None,
) -> tuple[bool, list[dict]]:
    """Send synthetic probes through the LEDGER, in both arm shapes, and record what came back.

    Through the ledger deliberately: a probe spends the same organisation's
    tokens as a corpus observation and must advance the same isolation clock a
    partition gate reads. A probe that did not count would be a hole exactly the
    size of however many probes someone chose to run.

    THE PROMPT, VOCABULARY AND CONFIGURATION ARE NOT PARAMETERS, and that is the
    fix for GPT-PM's round-3 MAJOR. The earlier version took all three as
    arguments and then wrote the digests of the on-disk frozen files into the
    receipt regardless of what it had actually been handed. A probe run with a
    modified prompt would have produced a receipt claiming the frozen prompt's
    digest -- and that receipt could then be sealed as the eighteenth artefact,
    with both `verify_seal()` and `stress_probe_receipt_ok()` passing, sealing
    evidence that said the frozen request was tested when a different one was.

    My own round-trip test was the proof: it passed the literal string "p" as
    the prompt and the receipt still validated, because the receipt was
    reporting a file it had never used.

    So the bytes are read ONCE, here, and the same bytes both build the request
    and produce the digest. There is no argument left through which a different
    request could enter.
    """
    config_bytes = CONFIG_R2.read_bytes()
    prompt_bytes = PROMPT.read_bytes()
    vocab_bytes = VOCAB.read_bytes()
    config = json.loads(config_bytes)
    prompt = prompt_bytes.decode("utf-8")
    vocab = json.loads(vocab_bytes)
    nap = sleep if sleep is not None else time.sleep
    url = config["endpoint"]
    headers_base = {
        "Content-Type": "application/json",
        "User-Agent": config["user_agent"],
        "Authorization": f"Bearer {api_key}",
    }
    wait_rule = config["wait_rule"]
    probes: list[dict] = []
    last_headers: dict[str, str] = {}
    ok = True

    for shape_name, shape in ARM_SHAPES.items():
        nap(next_wait_seconds(last_headers, wait_rule))
        ledger.record(model=config["model"], request_class="stress_probe", partition=None)
        body = build_request_body(prompt, synthetic_jpeg(shape), config, vocab)
        status, resp_headers, text = post_with_transport_failures(
            transport, url, dict(headers_base), body)
        last_headers = dict(resp_headers or {})
        finish = finish_reason(text)
        cls = classify(status, text)
        probes.append({
            "arm_shape": shape_name,
            "dimensions": list(shape),
            "http_status": status,
            "failure_class": cls,
            "finish_reason": finish,
        })
        if cls != "ok" or finish == "length":
            ok = False

    receipt = {
        "_comment": (
            "Evidence that the PROVIDER accepts this exact request shape at this cap. It is not "
            "evidence about serialization length -- a solid-colour frame produces the shortest "
            "answer, not the longest, so that claim is bounded offline by "
            "worst_case_answer_bytes() instead. Synthetic images only: no corpus photograph is "
            "transmitted by a stress probe. Every probe is in the request ledger and advances "
            "the isolation clock."
        ),
        "recorded_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        # Digests of the EXACT bytes that built the request above, not of paths
        # read a second time. One read, two uses -- so the receipt cannot claim
        # a request shape it did not send.
        "config_sha256": hashlib.sha256(config_bytes).hexdigest(),
        "prompt_sha256": hashlib.sha256(prompt_bytes).hexdigest(),
        "vocab_sha256": hashlib.sha256(vocab_bytes).hexdigest(),
        "max_completion_tokens": config["max_completion_tokens"],
        "worst_case_answer_bytes": worst_case_answer_bytes(vocab),
        "longest_canonical_names": longest_canonical_names(vocab),
        "probes": probes,
        "cleared": ok,
    }
    receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n",
                            encoding="utf-8", newline="\n")
    return ok, probes


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------

def main(argv: list[str], transport_factory: Callable[[], object] = HttpTransport) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--partition", type=int, choices=(1, 2, 3, 4))
    ap.add_argument("--corpus-root")
    ap.add_argument("--out")
    ap.add_argument("--api-key-file")
    ap.add_argument("--ledger", default=str(LEDGER))
    ap.add_argument("--stress-probe", action="store_true",
                    help="send synthetic probes in both arm shapes through the ledger and write "
                         "the receipt that clears max_completion_tokens. No corpus photograph is "
                         "transmitted. Must happen BEFORE the configuration is sealed.")
    ap.add_argument("--dry-run", action="store_true",
                    help="verify the seal, the consent state machine and the ledger, then stop "
                         "before any transport exists")
    args = ap.parse_args(argv)

    config = json.loads(CONFIG_R2.read_text("utf-8"))

    # -- stress probes: before the seal exists, by construction -------------
    if args.stress_probe:
        # The offline bound first: there is no point spending the organisation's
        # tokens probing a cap that is already provably too small for the
        # longest answer the schema permits.
        headroom = serialization_headroom_ok(config, json.loads(VOCAB.read_text("utf-8")))
        if headroom is not None:
            print(f"REFUSED: {headroom.reason}")
            return 8
        ledger = Ledger(Path(args.ledger))
        try:
            ledger.entries()
        except LedgerUnusable as exc:
            print(f"REFUSED: {exc}")
            return 6
        refusal = isolation_ok(ledger, config)
        if refusal is not None:
            print(f"REFUSED: {refusal.reason}")
            print("A stress probe spends the same organisation's tokens as a corpus observation, "
                  "so it waits out the same isolation window.")
            return 7
        if not args.api_key_file:
            print("REFUSED: --api-key-file is required to send a probe.")
            return 4
        ok, probes = run_stress_probes(
            Path(args.api_key_file).read_text("utf-8").strip(),
            transport_factory(),
            ledger,
        )
        for p in probes:
            print(f"  probe {p['arm_shape']} {p['dimensions']}: HTTP {p['http_status']} "
                  f"{p['failure_class']} finish_reason={p['finish_reason']!r}")
        if not ok:
            print("NOT CLEARED: the configuration must not be sealed as it stands.")
            return 8
        print(f"cleared; receipt written to {STRESS_RECEIPT.name}")
        return 0

    if args.partition is None or not args.corpus_root or not args.out:
        print("REFUSED: --partition, --corpus-root and --out are required for a corpus run.")
        return 4

    if not PREREGISTRATION_R2.is_file():
        print(f"REFUSED: no revision 2 pre-registration at {PREREGISTRATION_R2.name}")
        return 2
    seal = base.load_seal(PREREGISTRATION_R2)
    if not seal:
        print("REFUSED: the revision 2 pre-registration carries an EMPTY seal.")
        print(
            "That is its current, deliberate state: the protocol is drafted and not sealed, "
            "because sealing waits on a successful stress-probe receipt that does not exist yet. "
            "An empty seal refuses rather than verifying nothing successfully."
        )
        return 2
    unbound = seal_binds_receipt(seal)
    if unbound is not None:
        print(f"REFUSED: {unbound.reason}")
        return 2
    problems = base.verify_seal(seal)
    if problems:
        print("REFUSED: the frozen artefacts do not match the revision 2 seal.")
        for p in problems:
            print("  " + p)
        return 2
    print(f"seal verified: {len(seal)} artefacts unchanged, clearance receipt included")

    partition_digests = {}
    for p in (1, 2, 3, 4):
        mp = partition_manifest(p)
        if not mp.is_file():
            print(f"REFUSED: partition manifest {mp.name} is missing.")
            return 2
        partition_digests[p] = base.sha256_file(mp)
    manifest = partition_manifest(args.partition)
    verdict = evaluate_consent_r2(
        CONSENT_R2,
        partition_digests,
        base.sha256_file(PREREGISTRATION_R2),
    )
    print(f"consent: {verdict}")
    if not verdict.authorised:
        print("REFUSED: no affirmative, fully-bound consent to transmit these photographs again.")
        print(
            "The consent committed before run #1 authorised that manifest ONCE, and run #1 "
            "consumed it. A second transmission of the same 52 photographs requires a NEW "
            "operator reaffirmation bound to this revision. That is the operator's alone."
        )
        return 3

    ledger = Ledger(Path(args.ledger))
    try:
        entries = ledger.entries()
    except LedgerUnusable as exc:
        print(f"REFUSED: {exc}")
        return 6
    print(f"ledger: {len(entries)} recorded requests, {ledger.partition_request_count(args.partition)} "
          f"for partition {args.partition}")

    vocab = json.loads(VOCAB.read_text("utf-8"))
    for gate in (serialization_headroom_ok(config, vocab), stress_probe_receipt_ok(config)):
        if gate is not None:
            print(f"REFUSED: {gate.reason}")
            return 8

    refusal = isolation_ok(ledger, config)
    if refusal is not None:
        print(f"REFUSED: {refusal.reason}")
        return 7

    observations = base.load_manifest(manifest)
    print(f"{len(observations)} observations in partition {args.partition}")
    if args.dry_run:
        print("--dry-run: stopping before constructing a transport. Nothing was sent.")
        return 0

    if not args.api_key_file:
        print("REFUSED: --api-key-file is required for a real run.")
        return 4
    api_key = Path(args.api_key_file).read_text("utf-8").strip()

    outcome = run_partition(
        args.partition,
        observations,
        Path(args.corpus_root),
        PROMPT.read_text("utf-8"),
        json.loads(VOCAB.read_text("utf-8")),
        config,
        api_key,
        transport_factory(),
        ledger,
        Path(args.out),
    )
    if outcome.refused_before_start:
        print(f"REFUSED: {outcome.refused_before_start}")
        return 7
    if outcome.invalid:
        print(f"INVALID_INSTRUMENT: {outcome.invalid_instrument} after {outcome.requests_made} requests.")
        print("No hypothesis statistic may be computed from this partition.")
        return 5
    print(f"partition {args.partition}: {outcome.answered} answered, {outcome.unresolved} unresolved, "
          f"{outcome.requests_made} requests")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
