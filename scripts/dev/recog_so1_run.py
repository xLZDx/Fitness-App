"""RECOG-SO1 runner: ask a second model the same question, blind, or refuse to ask at all.

This program transmits the operator's own photographs of their gym -- containing
identifiable people, two of them children whose faces are legible -- to a
third-party inference provider. Everything below is arranged so that it CANNOT
do that by accident. In order:

  1.  the seal is loaded and every frozen artefact is re-hashed against it;
  2.  the consent record is evaluated to AUTHORISED or REFUSED;
  3.  ONLY on AUTHORISED is a transport constructed;
  4.  ONLY then is any image byte read, and each is re-hashed against the
      manifest immediately before its own request.

Steps 1 and 2 happen before step 3 deliberately, and the test suite asserts a
`deny` record yields zero transport calls AND zero image reads -- not merely a
non-zero exit code (GPT-PM, BLOCKER on plan revision 1).

BLINDNESS. The request carries the frozen prompt, the frozen machine list and
one image. It carries no Gemini answer, no confidence, no ground-truth kind, no
arm identity and no scorer-derived field. This is not asserted by the absence of
those files from this source -- that would only prove those particular files
were not opened. The input schema is CLOSED, so a hint cannot arrive inside the
observation list either, and `test_recog_so1.py` inspects the SERIALIZED request
body with a capturing transport (GPT-PM, MAJOR 4).

WHAT THIS PROGRAM DOES NOT DO. It does not read the ground truth. It does not
read Gemini's replies. It does not score anything -- `recog_so1_score.py` does
that, from this program's output, afterwards. Keeping them apart is what stops
a runner from being tuned until the numbers improve.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Protocol

REPO = Path(__file__).resolve().parents[2]
PLANS = REPO / "core" / "plans"
DEV = REPO / "scripts" / "dev"

PREREGISTRATION = PLANS / "RECOG_SO1_PREREGISTRATION_2026-09-07.md"
CONSENT = PLANS / "RECOG_SO1_CONSENT.json"
MANIFEST = PLANS / "RECOG_SO1_OBSERVATION_MANIFEST_2026-09-07.csv"
PROMPT = DEV / "recog_so1_prompt.txt"
VOCAB = DEV / "recog_so1_vocab.json"
CONFIG = DEV / "recog_so1_config.json"

#: The observation list may contain these fields and nothing else. A closed
#: schema is the point: an open one would let a ground-truth kind, a Gemini
#: candidate or an arm-derived hint ride into the runner inside its own input.
MANIFEST_FIELDS = frozenset({"observation_id", "source_photo_id", "arm", "image_path", "expected_sha256"})

AFFIRMATIVE = frozenset({"whole_corpus", "people_free_only"})


# --------------------------------------------------------------------------
# Seal
# --------------------------------------------------------------------------

def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_seal(preregistration: Path) -> dict[str, str]:
    """Parse the sealed-artefact digests out of the pre-registration document.

    They live in the document rather than in a sidecar file so that the
    protocol and the digests of what it governs cannot drift apart: changing
    one changes the other's container.
    """
    text = preregistration.read_text("utf-8")
    m = re.search(r"<!-- SEAL -->\s*```json\s*(\{.*?\})\s*```", text, re.S)
    if not m:
        raise SystemExit(f"{preregistration.name}: no <!-- SEAL --> json block found")
    return json.loads(m.group(1))


def verify_seal(seal: dict[str, str]) -> list[str]:
    """Re-hash every sealed artefact. Returns a list of human-readable failures."""
    problems: list[str] = []
    for rel, expected in seal.items():
        path = REPO / rel
        if not path.is_file():
            problems.append(f"sealed artefact missing: {rel}")
            continue
        got = sha256_file(path)
        if got != expected:
            problems.append(f"sealed artefact changed: {rel}\n    sealed {expected}\n    found  {got}")
    return problems


# --------------------------------------------------------------------------
# Consent -- the state machine GPT-PM's BLOCKER required
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class ConsentVerdict:
    authorised: bool
    decision: str | None
    reason: str

    def __str__(self) -> str:
        return f"{'AUTHORISED' if self.authorised else 'REFUSED'} ({self.reason})"


def evaluate_consent(
    consent_path: Path,
    manifest_digest: str,
    preregistration_digest: str,
) -> ConsentVerdict:
    """Return AUTHORISED only for affirmative, fully-bound consent.

    Every other outcome -- absent, unparseable, denied, unknown value, missing
    binding, wrong binding, unexpected property -- is REFUSED. `deny` is not an
    error condition; it is a valid answer that this function reports as a
    refusal, which is exactly the distinction the previous design lacked.
    """
    if not consent_path.is_file():
        return ConsentVerdict(False, None, f"no consent record at {consent_path.name}")
    try:
        record = json.loads(consent_path.read_text("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        return ConsentVerdict(False, None, f"consent record does not parse: {exc}")
    if not isinstance(record, dict):
        return ConsentVerdict(False, None, "consent record is not a JSON object")

    allowed = {
        "decision", "recorded_at", "operator_statement", "manifest_sha256",
        "preregistration_sha256", "groq_data_controls", "notes",
    }
    unexpected = sorted(set(record) - allowed)
    if unexpected:
        return ConsentVerdict(False, None, f"consent record carries undefined properties: {unexpected}")

    decision = record.get("decision")
    if decision is None:
        return ConsentVerdict(False, None, "consent record names no decision")
    if decision == "deny":
        return ConsentVerdict(False, "deny", "the operator declined transmission")
    if decision not in AFFIRMATIVE:
        return ConsentVerdict(False, None, f"decision {decision!r} is not a recognised value")

    if not record.get("operator_statement"):
        return ConsentVerdict(False, decision, "affirmative consent carries no verbatim operator statement")
    for field_name, actual in (
        ("manifest_sha256", manifest_digest),
        ("preregistration_sha256", preregistration_digest),
    ):
        bound = record.get(field_name)
        if not bound:
            return ConsentVerdict(False, decision, f"affirmative consent does not bind {field_name}")
        if bound != actual:
            return ConsentVerdict(
                False, decision,
                f"{field_name} binds {bound[:16]}... but the file on disk hashes to {actual[:16]}...",
            )
    controls = record.get("groq_data_controls")
    if not isinstance(controls, dict) or "global_zdr" not in controls:
        return ConsentVerdict(False, decision, "affirmative consent records no provider retention state")

    return ConsentVerdict(True, decision, f"{decision}, retention state global_zdr={controls['global_zdr']!r}")


# --------------------------------------------------------------------------
# Manifest -- closed schema
# --------------------------------------------------------------------------

@dataclass(frozen=True)
class Observation:
    observation_id: str
    source_photo_id: str
    arm: str
    image_path: str
    expected_sha256: str


def load_manifest(path: Path) -> list[Observation]:
    import csv

    rows = list(csv.DictReader(path.read_text("utf-8").splitlines()))
    if not rows:
        raise SystemExit(f"{path.name}: empty")
    present = set(rows[0])
    if present != MANIFEST_FIELDS:
        extra = sorted(present - MANIFEST_FIELDS)
        missing = sorted(MANIFEST_FIELDS - present)
        raise SystemExit(
            f"{path.name}: the observation list must carry exactly {sorted(MANIFEST_FIELDS)}.\n"
            f"  unexpected: {extra}\n  missing: {missing}\n"
            "An unexpected column is refused rather than ignored: that is how a ground-truth kind "
            "or another model's answer would reach a request that is supposed to be blind."
        )
    return [Observation(**{k: r[k] for k in MANIFEST_FIELDS}) for r in rows]


# --------------------------------------------------------------------------
# Transport -- injectable, so blindness can be inspected without a network
# --------------------------------------------------------------------------

def read_image_bytes(path: Path) -> bytes:
    """The ONLY place this program reads an image.

    Funnelled through a single named function so that "no image byte is read
    before consent is evaluated" is a testable claim rather than a description
    of the source. GPT-PM's closure review made exactly this point: proving that
    no transport was constructed and no output file was written does NOT prove
    an image was never opened -- a runner could read the file, then refuse, and
    satisfy both of those assertions. `recog_so1.tests.py` replaces this
    function with one that counts its calls and raises, and requires a `deny`,
    absent or malformed consent record to finish with a call count of ZERO.
    """
    return path.read_bytes()


class Transport(Protocol):
    def post(self, url: str, headers: dict[str, str], body: bytes) -> tuple[int, dict[str, str], str]: ...


@dataclass
class CapturingTransport:
    """Records requests and returns canned replies. Never touches the network."""

    replies: list[tuple[int, dict[str, str], str]] = field(default_factory=list)
    calls: list[dict] = field(default_factory=list)

    def post(self, url: str, headers: dict[str, str], body: bytes) -> tuple[int, dict[str, str], str]:
        self.calls.append({"url": url, "headers": dict(headers), "body": body})
        if not self.replies:
            return 200, {}, json.dumps(
                {"choices": [{"message": {"content": json.dumps({"machine": "unknown", "confidence": 0.0})}}]}
            )
        return self.replies.pop(0)


class HttpTransport:
    def post(self, url: str, headers: dict[str, str], body: bytes) -> tuple[int, dict[str, str], str]:
        req = urllib.request.Request(url, data=body, headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                return resp.status, dict(resp.headers), resp.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            return exc.code, dict(exc.headers or {}), exc.read().decode("utf-8", "replace")


# --------------------------------------------------------------------------
# Request construction and parsing
# --------------------------------------------------------------------------

def build_request_body(prompt: str, image_bytes: bytes, config: dict) -> bytes:
    """The whole semantic payload: the frozen prompt, and one image. Nothing else."""
    data_url = "data:image/jpeg;base64," + base64.b64encode(image_bytes).decode("ascii")
    payload = {
        "model": config["model"],
        "temperature": config["temperature"],
        "top_p": config["top_p"],
        "seed": config["seed"],
        "max_completion_tokens": config["max_completion_tokens"],
        "response_format": config["response_format"],
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


def parse_reply(text: str, vocab: dict) -> tuple[str | None, dict]:
    """Return (raw machine name or None, diagnostics).

    None means unresolved. An unresolved observation is NEVER an abstention:
    `unknown` is an abstention, a reply that will not parse is a failure, and
    the scorer counts the two differently and in opposite directions.
    """
    diag: dict = {}
    try:
        envelope = json.loads(text)
        content = envelope["choices"][0]["message"]["content"]
    except (json.JSONDecodeError, KeyError, IndexError, TypeError) as exc:
        diag["failure"] = f"envelope: {type(exc).__name__}: {exc}"
        return None, diag
    if not content or not content.strip():
        diag["failure"] = "empty_completion"
        return None, diag
    try:
        answer = json.loads(content)
    except json.JSONDecodeError as exc:
        diag["failure"] = f"content is not JSON: {exc}"
        diag["content"] = content[:400]
        return None, diag
    if not isinstance(answer, dict) or "machine" not in answer:
        diag["failure"] = "content carries no 'machine' field"
        diag["content"] = content[:400]
        return None, diag
    machine = answer["machine"]
    if not isinstance(machine, str) or not machine.strip():
        diag["failure"] = "'machine' is not a non-empty string"
        return None, diag
    diag["confidence"] = answer.get("confidence")
    diag["alternatives"] = answer.get("alternatives")
    return machine, diag


# --------------------------------------------------------------------------
# The run
# --------------------------------------------------------------------------

def pace_after_failure(resp_headers: dict[str, str], pacing_seconds: float) -> float:
    """How long to wait before the NEXT observation, after a request that failed.

    A request that came back 429 still SPENT its input tokens: the token bucket
    does not care that the reply was a refusal. Skipping the pacing interval
    here is how one 429 cascades into a run of them -- the bounded retry backoff
    alone (5s then 10s, and the final attempt's Retry-After is by definition
    never honoured because there is no further attempt) totals 15s, under the
    frozen 20s interval, so observation N+1 would fire EARLY at exactly the
    moment the provider has just said the bucket is empty. Found by GPT-PM as a
    MAJOR against the first revision of this change, which paced only the
    successful path.

    The provider's own Retry-After wins when it asks for longer than the frozen
    interval; a malformed or HTTP-date value falls back to the frozen interval
    rather than to zero.
    """
    raw = resp_headers.get("Retry-After")
    try:
        asked = float(raw) if raw else 0.0
    except (TypeError, ValueError):
        asked = 0.0
    return max(pacing_seconds, asked)


@dataclass(frozen=True)
class RunOutcome:
    """A completed run and a stopped run are different results, not one integer.

    The previous version returned only the unresolved count, so a run that
    aborted on its first observation and a run that finished with one bad
    observation were indistinguishable to the caller.
    """

    observations_total: int
    observations_processed: int
    unresolved: int
    aborted_on: str | None = None

    @property
    def aborted(self) -> bool:
        return self.aborted_on is not None


def run(
    observations: Iterable[Observation],
    corpus_root: Path,
    prompt: str,
    vocab: dict,
    config: dict,
    api_key: str,
    transport: Transport,
    out: Path,
    sleep: Callable[[float], None] | None = None,
) -> RunOutcome:
    # Resolved here rather than as a default argument value, so that `time` is
    # looked up at call time. The suite substitutes a recording stand-in and
    # asserts on the actual backoff and pacing intervals; a default bound at
    # definition time would have made a 503 retry sleep for five real seconds
    # inside a test whose whole point is that it makes no network call.
    nap = sleep if sleep is not None else time.sleep
    url = config["endpoint"]
    headers_base = {
        "Content-Type": "application/json",
        "User-Agent": config["user_agent"],
        "Authorization": f"Bearer {api_key}",
    }
    policy = config["retry_policy"]
    retry_on = set(policy["retry_on"])
    #: Configuration-class statuses stop the WHOLE run. The request shape is
    #: frozen and identical for every observation, so a 400/401/403/404 is a
    #: property of the request, never of the photograph in front of it:
    #: continuing would burn all 104 photographs against a broken request and
    #: produce 104 unresolved observations that look like data. Read from the
    #: sealed config rather than hard-coded, so the rule is part of what the
    #: pre-registration froze.
    abort_on = set(policy.get("abort_run_on", ()))
    max_attempts = int(policy["max_attempts"])
    pacing_seconds = float(config["rate_limits_measured"]["seconds_between_requests"])

    observations = list(observations)
    unresolved = 0
    processed = 0
    aborted_on: str | None = None
    with out.open("w", encoding="utf-8", newline="\n") as fh:
        for obs in observations:
            processed += 1
            path = corpus_root / obs.image_path
            record: dict = {
                "observation_id": obs.observation_id,
                "source_photo_id": obs.source_photo_id,
                "arm": obs.arm,
            }
            if not path.is_file():
                record.update(status="unresolved", failure="image_missing", detail=str(path))
                fh.write(json.dumps(record, ensure_ascii=False) + "\n")
                unresolved += 1
                continue

            image_bytes = read_image_bytes(path)
            got = hashlib.sha256(image_bytes).hexdigest()
            if got != obs.expected_sha256:
                # Refuse rather than measure. A corpus that no longer hashes to
                # the frozen values is not the corpus the experiment was
                # pre-registered against, and sending it would be the exact
                # "record the hash of what was sent afterwards" failure the
                # frozen-dataset rule exists to prevent.
                record.update(status="unresolved", failure="image_digest_mismatch",
                              expected=obs.expected_sha256, found=got)
                fh.write(json.dumps(record, ensure_ascii=False) + "\n")
                unresolved += 1
                continue
            record["image_sha256"] = got

            body = build_request_body(prompt, image_bytes, config)
            attempt = 0
            while True:
                attempt += 1
                status, resp_headers, text = transport.post(url, dict(headers_base), body)
                cls = f"http_{status}" if status != 200 else "ok"
                if status == 200:
                    break
                if cls in retry_on and attempt < max_attempts:
                    wait = float(resp_headers.get("Retry-After") or (5 * attempt))
                    nap(wait)
                    continue
                break

            record["attempts"] = attempt
            record["http_status"] = status
            if status != 200:
                cls = f"http_{status}"
                record.update(status="unresolved", failure=cls, detail=text[:400])
                if cls in abort_on:
                    # Record this observation with its failure class, then STOP.
                    # No further request is made and no pacing sleep happens.
                    record["run_aborted"] = cls
                    fh.write(json.dumps(record, ensure_ascii=False) + "\n")
                    unresolved += 1
                    aborted_on = cls
                    break
                fh.write(json.dumps(record, ensure_ascii=False) + "\n")
                unresolved += 1
                # A request WAS sent and its input tokens WERE spent, so this
                # observation is paced exactly like a successful one. Only the
                # abort path above skips the wait, because the run ends there.
                nap(pace_after_failure(resp_headers, pacing_seconds))
                continue

            machine, diag = parse_reply(text, vocab)
            record["raw_reply"] = text[:4000]
            record.update(diag)
            if machine is None:
                record["status"] = "unresolved"
                unresolved += 1
            else:
                record["status"] = "answered"
                record["machine_raw"] = machine
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")

            # Pace against the measured token ceiling rather than waiting to be
            # told off by a 429.
            nap(pacing_seconds)

    return RunOutcome(
        observations_total=len(observations),
        observations_processed=processed,
        unresolved=unresolved,
        aborted_on=aborted_on,
    )


def main(argv: list[str], transport_factory: Callable[[], Transport] = HttpTransport) -> int:
    """`transport_factory` is injectable for one reason only, and it is the reason
    GPT-PM's BLOCKER exists: the test suite has to be able to prove that a `deny`
    record means the factory is NEVER CALLED -- that no client was constructed,
    not merely that none was used. A boolean return code cannot show that."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--corpus-root", required=True, help="directory holding arm_a/ and arm_b/")
    ap.add_argument("--out", required=True, help="JSONL output path")
    ap.add_argument("--api-key-file", help="file holding the Groq API key; never a command-line argument")
    ap.add_argument("--dry-run", action="store_true",
                    help="verify the seal and the consent state machine, then stop before any transport exists")
    args = ap.parse_args(argv)

    # ---- 1. seal ---------------------------------------------------------
    seal = load_seal(PREREGISTRATION)
    problems = verify_seal(seal)
    if problems:
        print("REFUSED: the frozen artefacts do not match the seal.")
        for p in problems:
            print("  " + p)
        return 2
    print(f"seal verified: {len(seal)} artefacts unchanged")

    # ---- 2. consent, before any image byte and before any transport ------
    verdict = evaluate_consent(CONSENT, sha256_file(MANIFEST), sha256_file(PREREGISTRATION))
    print(f"consent: {verdict}")
    if not verdict.authorised:
        print("REFUSED: no affirmative, fully-bound consent to transmit these photographs.")
        return 3

    observations = load_manifest(MANIFEST)
    print(f"{len(observations)} observations authorised under decision {verdict.decision!r}")
    if args.dry_run:
        print("--dry-run: stopping before constructing a transport. Nothing was sent.")
        return 0

    if not args.api_key_file:
        print("REFUSED: --api-key-file is required for a real run.")
        return 4
    api_key = Path(args.api_key_file).read_text("utf-8").strip()

    # ---- 3. only now does a transport exist ------------------------------
    transport = transport_factory()
    outcome = run(
        observations,
        Path(args.corpus_root),
        PROMPT.read_text("utf-8"),
        json.loads(VOCAB.read_text("utf-8")),
        json.loads(CONFIG.read_text("utf-8")),
        api_key,
        transport,
        Path(args.out),
    )
    if outcome.aborted:
        print(
            f"ABORTED on {outcome.aborted_on} after {outcome.observations_processed} of "
            f"{outcome.observations_total} observations. No further request was made."
        )
        print(
            "A configuration-class status is a property of the frozen request shape, not of the "
            "photograph. SO1 stops here; the remaining observations were NOT transmitted. Editing "
            "the sealed configuration to make the request acceptable and continuing is exactly the "
            "freedom the pre-registration exists to remove -- it requires a new pre-registration "
            "revision, reviewed before any further transmission."
        )
        return 5
    print(f"done; {outcome.unresolved} unresolved of {outcome.observations_total}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
