"""RECOG-SO1 revision 2: the single ledger of every request ever made to Qwen.

Revision 1 failed as an instrument because the run had THREE different stories
about how much budget it had spent -- the retry loop's own attempt counter, the
pacing arithmetic in the config, and the provider's headers -- and none of them
was authoritative. 260 requests were made for 104 observations and nothing in
the program knew that.

This module is the one place that knows. Every request to the model, of every
class, is written here BEFORE it is transmitted:

  * a stress probe run while the protocol is still being sealed,
  * the availability check at the head of a partition,
  * a corpus observation,
  * and EVERY retry attempt, which is its own entry because it is its own
    transmission and spends its own tokens.

Two questions are answered from this file and from nothing else:

  1.  how many requests has this partition already made, which is what the
      daily-budget guard divides into its ceiling;
  2.  when was the last request of ANY class made, which is what the 24-hour
      isolation rule compares against.

FAILING CLOSED IS THE POINT. A ledger that is missing, unreadable, or carries a
line that will not parse means the program does not know what it has spent, and
a program that does not know what it has spent must not spend more. Every one
of those states raises `LedgerUnusable` and the runner refuses to transmit. In
particular a MISSING file is refused rather than treated as "no requests yet":
an absent ledger is indistinguishable from a deleted one, and the deleted one
is the case that matters. Creating the file is a separate, explicit act
(`Ledger.initialise`), so beginning a fresh count is always deliberate.
"""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable

#: The classes of request that may be recorded. An unrecognised class is
#: refused rather than stored: the isolation rule and the budget guard both
#: read this field, and a class neither of them knows how to weigh is a hole.
REQUEST_CLASSES = frozenset({"stress_probe", "availability", "corpus"})

ISOLATION_HOURS = 24


class LedgerUnusable(Exception):
    """The ledger cannot be trusted, so nothing may be transmitted."""


@dataclass(frozen=True)
class LedgerEntry:
    model: str
    at: datetime
    request_class: str
    partition: int | None

    def to_json(self) -> str:
        return json.dumps(
            {
                "model": self.model,
                "at": self.at.astimezone(timezone.utc).isoformat().replace("+00:00", "Z"),
                "request_class": self.request_class,
                "partition": self.partition,
            },
            ensure_ascii=False,
        )


def _parse_entry(line: str, lineno: int) -> LedgerEntry:
    try:
        d = json.loads(line)
    except json.JSONDecodeError as exc:
        raise LedgerUnusable(f"ledger line {lineno} is not JSON: {exc}") from exc
    if not isinstance(d, dict):
        raise LedgerUnusable(f"ledger line {lineno} is not an object")
    missing = sorted({"model", "at", "request_class", "partition"} - set(d))
    if missing:
        raise LedgerUnusable(f"ledger line {lineno} is missing {missing}")
    request_class = d["request_class"]
    if request_class not in REQUEST_CLASSES:
        raise LedgerUnusable(
            f"ledger line {lineno} records unknown request class {request_class!r}; "
            f"expected one of {sorted(REQUEST_CLASSES)}"
        )
    raw_at = d["at"]
    if not isinstance(raw_at, str):
        raise LedgerUnusable(f"ledger line {lineno} has a non-string timestamp")
    try:
        at = datetime.fromisoformat(raw_at.replace("Z", "+00:00"))
    except ValueError as exc:
        raise LedgerUnusable(f"ledger line {lineno} has an unparseable timestamp {raw_at!r}: {exc}") from exc
    if at.tzinfo is None:
        raise LedgerUnusable(f"ledger line {lineno} timestamp {raw_at!r} carries no timezone")
    partition = d["partition"]
    if partition is not None and not isinstance(partition, int):
        raise LedgerUnusable(f"ledger line {lineno} has a non-integer partition {partition!r}")
    model = d["model"]
    if not isinstance(model, str) or not model.strip():
        raise LedgerUnusable(f"ledger line {lineno} names no model")
    return LedgerEntry(model=model, at=at, request_class=request_class, partition=partition)


class Ledger:
    """Append-only record of transmissions. The only authority on how many."""

    def __init__(self, path: Path, clock: Callable[[], datetime] | None = None) -> None:
        self.path = path
        self._clock = clock or (lambda: datetime.now(timezone.utc))

    # -- lifecycle ---------------------------------------------------------

    def initialise(self) -> None:
        """Create an empty ledger. Deliberate, and refuses to clobber one."""
        if self.path.exists():
            raise LedgerUnusable(
                f"{self.path} already exists; refusing to reset a ledger that may hold spent budget"
            )
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text("", encoding="utf-8", newline="\n")

    # -- reading -----------------------------------------------------------

    def entries(self) -> list[LedgerEntry]:
        if not self.path.is_file():
            raise LedgerUnusable(
                f"no ledger at {self.path}. An absent ledger is refused rather than read as "
                "'nothing spent yet' -- it is indistinguishable from a deleted one. Create it "
                "explicitly if this really is a fresh count."
            )
        try:
            text = self.path.read_text("utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            raise LedgerUnusable(f"ledger at {self.path} cannot be read: {exc}") from exc
        out: list[LedgerEntry] = []
        for lineno, line in enumerate(text.splitlines(), start=1):
            if not line.strip():
                continue
            out.append(_parse_entry(line, lineno))
        return out

    def partition_request_count(self, partition: int) -> int:
        """Transmissions already made for one partition, retries included."""
        return sum(1 for e in self.entries() if e.partition == partition)

    def last_request_at(self) -> datetime | None:
        """The most recent transmission of ANY class, or None for an empty ledger.

        Of any class deliberately: a stress probe run while sealing the protocol
        spends the same organisation's tokens as a corpus observation does, so
        it must advance the same clock the partition gate reads.
        """
        entries = self.entries()
        if not entries:
            return None
        return max(e.at for e in entries)

    def isolation_ok(self, hours: int = ISOLATION_HOURS) -> tuple[bool, str]:
        """Has enough quiet time passed since the last transmission of any class?"""
        last = self.last_request_at()
        if last is None:
            return True, "ledger is empty; no previous transmission to wait out"
        now = self._clock()
        elapsed = now - last
        required = timedelta(hours=hours)
        if elapsed >= required:
            return True, f"{elapsed.total_seconds() / 3600:.1f}h since the last request (>= {hours}h)"
        return False, (
            f"only {elapsed.total_seconds() / 3600:.1f}h since the last Qwen request "
            f"({last.isoformat()}); the isolation rule requires {hours}h"
        )

    # -- writing -----------------------------------------------------------

    def record(self, model: str, request_class: str, partition: int | None) -> LedgerEntry:
        """Write ONE transmission. Called BEFORE the request is sent.

        Before, not after, and the ordering is the whole design: a request that
        is sent and then fails to be recorded is spent budget the next run
        cannot see. Recording first can over-count if the process dies between
        the write and the send, and over-counting is the safe direction.
        """
        if request_class not in REQUEST_CLASSES:
            raise LedgerUnusable(
                f"refusing to record unknown request class {request_class!r}; "
                f"expected one of {sorted(REQUEST_CLASSES)}"
            )
        if not self.path.is_file():
            raise LedgerUnusable(f"no ledger at {self.path}; refusing to transmit unrecorded")
        entry = LedgerEntry(
            model=model,
            at=self._clock().astimezone(timezone.utc),
            request_class=request_class,
            partition=partition,
        )
        line = entry.to_json() + "\n"
        with self.path.open("a", encoding="utf-8", newline="\n") as fh:
            fh.write(line)
            fh.flush()
            os.fsync(fh.fileno())
        return entry


def atomic_write_text(path: Path, text: str) -> None:
    """Write a whole file or leave the old one intact. Used for generated manifests."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise
