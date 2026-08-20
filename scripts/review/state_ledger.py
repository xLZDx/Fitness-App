# -*- coding: utf-8 -*-
"""The current-state ledger, and the check that stops it drifting from source.

    python scripts/review/state_ledger.py --check
    python scripts/review/state_ledger.py --report
    python -m pytest scripts/review/test_state_ledger.py -q

## The failure this exists to prevent

On 2026-08-18 a reconciliation sweep found `core/review/N05_DISPOSITION.md`
carrying F-prefetch as **OPEN, recorded**: "`resolveAll` still swallows a quota
refusal". `resolveAll` had not existed under `mobile/lib/` for some time. It had
become `resolveBatch` returning `ClipBatch`, converted by the prefetch layer
into `PrefetchOutcome`, whose `PrefetchState.partialQuota` is precisely the
"38 of 84, limit reached" the row asked for.

Nothing was broken. The source was right, the append-only decision log was
right, the whole suite was green. The single wrong artefact was the table a
reader opens to ask *what is still open*, and it was wrong in the expensive
direction: it claimed work remained that had already been done. A report
assembled from that table would have sent a future author to redo finished
work, and not one test in the repository would have objected -- because no test
reads a status table.

So this module makes status a computed thing where it can be computed, and
makes the human-readable table a GENERATED artefact rather than a maintained
one. `core/CURRENT_STATE.md` is regenerated and byte-compared by the test
suite. It cannot drift, because drifting is a test failure.

## Why the recorded state is not trusted

For a row whose authority is `SOURCE`, `state` is not an input. The invariant
recomputes the state from the tree and the check compares. That single rule
catches both directions of the failure at once:

* a **stale OPEN** -- the row says OPEN, the predicate computes CLOSED;
* a **false CLOSED** -- the row says CLOSED, the predicate computes OPEN.

Neither needs its own mechanism, and neither can be argued with, because the
recorded word is never consulted to decide the answer.

## Why source may not close an external or operator row

The opposite error is just as available: declaring a clinical review complete
because a worklist exists, or N-05 closed because App Check code was written.
No local predicate has that authority, and a check that let one grow into it
would be worse than no check at all -- it would launder an engineering artefact
into a clinical or product claim.

So a row whose authority is not `SOURCE` may only carry a terminal state if its
`closure` callable reports that the owning authority has actually produced
something. `D1` closes when a clinical submission carries a named reviewer's
credentials and authority, and not before. `N-05` closes when an operator
decision record exists, and not before. There is deliberately no flag, no
override and no environment variable that skips this.

That is not the same as ignoring source on those rows. An external or operator
row still carries an `invariant`: a condition that must remain true while it
sits in its current state. `N-05` rests on a conflict with the published
deletion promise; if that promise were rewritten, the row's premise changed and
the check says so rather than letting a settled decision quietly rest on a
document that no longer says what it said. Source cannot CLOSE such a row, but
it can and must be able to REOPEN the question.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parents[2]

#: The four authorities. A row names the one that owns its state, and nothing
#: else may set it.
#:
#: A `TEST` authority was declared here at first, on the reasoning that "the
#: tree contains this code" and "a test proves this behaviour" fail
#: differently. A reviewer showed it was unimplementable rather than reserved:
#: the only mechanism that could express it is a predicate, and `check()`
#: forbids a predicate to any non-`SOURCE` row. Whoever first reached for it
#: would have hit the contradiction and relabelled their row `SOURCE`, erasing
#: the distinction the constant existed to make. A constant whose documented
#: meaning the checker rejects is a trap, so it is gone until a row needs it.
SOURCE = "SOURCE"
EXTERNAL = "EXTERNAL"
OPERATOR = "OPERATOR"
ENVIRONMENT = "ENVIRONMENT"

AUTHORITIES = (SOURCE, EXTERNAL, OPERATOR, ENVIRONMENT)

#: Nothing remains. Requires closure authority on any non-source row.
TERMINAL_STATES = ("CLOSED", "NOT_A_DEFECT")

#: An authority ACTED and chose to leave things as they are. Semantically just
#: as closed, so it needs the same permission.
#:
#: This category exists because a reviewer found the escape: `check()` decided
#: terminality by membership of a two-element tuple, so ANY other word was
#: non-terminal by default and walked straight past the closure gate. A row
#: reading `RESOLVED`, `SETTLED` or `DONE` would have passed every check while
#: reading to a human as finished. `DORMANT_BY_PRODUCT_DECISION` on N-07 was a
#: live instance: it asserted a product decision had been taken, carried a
#: closure callable, and that callable was never once invoked.
SETTLED_STATES = ("SETTLED_BY_DECISION",)

#: Work genuinely remains, and saying so needs nobody's permission.
OPEN_STATES = (
    "OPEN", "DORMANT", "HOLD", "DISABLED", "ENVIRONMENT_BLOCKED",
    "OPERATOR_DECISION_REQUIRED", "EXTERNAL_AUTHORITY_REQUIRED",
    "EXECUTABLE_ENGINEERING_WORK", "ENABLED",
)

#: The whole vocabulary. `row.state` was an unvalidated free string; a word
#: outside this tuple is now a finding rather than a silent bypass.
STATES = TERMINAL_STATES + SETTLED_STATES + OPEN_STATES


def needs_closure(state: str) -> bool:
    return state in TERMINAL_STATES or state in SETTLED_STATES

CURRENT_STATE_DOC = REPO / "core" / "CURRENT_STATE.md"

#: The residual marker. Prose that records executable work still to be done
#: must write `RESIDUAL[<item>]`, naming a row in this ledger.
#:
#: Twice in one session a real defect sat unfixed in document PROSE while every
#: status table said the work was done -- "the flow still does not handle it",
#: and two operator items recorded only in decision-log narrative. The tempting
#: response is to scan prose for words like *unfixed*, *still* or *open*. That
#: was rejected: those words appear constantly in correct historical narration
#: ("this used to be broken, and still reads oddly"), so the guard would be
#: mostly false positives, and a guard people learn to ignore protects nothing.
#:
#: This is an AUTHORING rule with a narrow check instead. It cannot find an
#: unmarked residual -- nothing can, short of understanding English -- but it
#: makes the marked ones impossible to lose, and gives a writer one obvious
#: thing to type. The convention is cheap precisely because it does not try to
#: be clever.
RESIDUAL_MARKER = re.compile(r"RESIDUAL\[([A-Za-z0-9._-]+)\]")

#: Documents that may carry residual markers.
RESIDUAL_DOCS = (
    "core/DECISION_LOG.md",
    "core/review/N05_DISPOSITION.md",
    # The document that owns D1 and H3. Omitting it meant a marker written in
    # the one place an EXTERNAL-authority residual would naturally be recorded
    # was not read at all.
    "core/review/CLINICAL_VALIDATION_HANDOFF.md",
    "core/review/N04_EQUIPMENT_REPORT_AUTHORITY.md",
    "core/review/N07_TEAM_ACTIVATION_GATE.md",
    "core/ml/SCANNER_PROVENANCE.md",
    "core/ml/METRIC_PROVENANCE.md",
)


def residual_markers(docs=None, repo=None) -> dict[str, list[str]]:
    """Every `RESIDUAL[id]` in the governed documents, id -> where it appears."""
    root = repo or REPO
    found: dict[str, list[str]] = {}
    for rel in (docs or RESIDUAL_DOCS):
        path = root / rel
        if not path.exists():
            continue
        body = path.read_text(encoding="utf-8", errors="replace")
        for m in RESIDUAL_MARKER.finditer(body):
            found.setdefault(m.group(1), []).append(rel)
    return found


def untracked_residuals(docs=None, repo=None) -> dict[str, list[str]]:
    """Markers naming something the ledger does not track.

    An empty result is the correct state when nothing is outstanding, and that
    is deliberately not treated as suspicious -- unlike a subject-set that went
    empty by accident, an empty residual set is a claim the ledger itself
    independently checks row by row.
    """
    tracked = {r.item for r in LEDGER}
    return {
        item: where for item, where in residual_markers(docs, repo).items()
        if item not in tracked
    }


# --------------------------------------------------------------- file helpers

def _read(rel: str) -> str:
    return (REPO / rel).read_text(encoding="utf-8", errors="replace")


def _dart_sources() -> dict[str, str]:
    """Every Dart file under `mobile/lib`, keyed by repo-relative path.

    Generated output and build artefacts are excluded: `mobile/build` holds
    copies of assets and would make an absence check answer about a stale
    build directory rather than about the source tree.
    """
    out = {}
    for p in (REPO / "mobile" / "lib").rglob("*.dart"):
        out[p.relative_to(REPO).as_posix()] = p.read_text(
            encoding="utf-8", errors="replace"
        )
    return out


def _symbol_absent(symbol: str) -> tuple[bool, str]:
    """True when `symbol` appears in no Dart source under `mobile/lib`.

    Word-bounded, so `resolveAll` is not reported present because
    `resolveAllTheThings` exists somewhere.
    """
    pattern = re.compile(r"\b" + re.escape(symbol) + r"\b")
    hits = [path for path, body in _dart_sources().items() if pattern.search(body)]
    if hits:
        return False, f"`{symbol}` still present in {len(hits)} file(s): {hits[:3]}"
    return True, f"`{symbol}` absent from mobile/lib"


def _member_body(body: str, signature: str) -> str:
    """The body of one Dart method, sliced by brace depth from its signature.

    Whole-file checks answer the wrong question. `throw StripeCheckoutException`
    is correct and present six times in the Stripe service -- for a missing
    URL, for a signed-out caller -- and the defect was only ever the ONE inside
    `startFreeTrial`. A file-wide ban reports the correct code as broken, which
    is how a guard teaches people to ignore it.
    """
    i = body.find(signature)
    if i < 0:
        return ""
    j = body.find("{", i)
    if j < 0:
        return ""
    depth, k = 1, j + 1
    while k < len(body) and depth:
        depth += {"{": 1, "}": -1}.get(body[k], 0)
        k += 1
    return body[j:k]


def _exported_member(body: str, signature: str) -> str:
    """One top-level `export const NAME = ...` declaration, up to the next one.

    `_member_body` cannot do this job for a Cloud Function. `onCall(` takes an
    options object first, so slicing from the first brace returns
    `{...INTERACTIVE, secrets: [...]}` -- 317 characters of configuration, and
    none of the handler. The nearest correct boundary is the next top-level
    export, which in this file is unambiguous because every handler is declared
    at column zero.

    This function exists because `f5` was measured returning CLOSED on a tree
    with F5's defect fully restored: both of its substrings also occur inside
    `startFreeTrial`, which is the handler F5 compares *against*, so deleting
    the real-money guard changed nothing the predicate could see. That is the
    same whole-file mistake `_member_body`'s docstring describes, made in the
    other direction -- a false CLOSED instead of a false OPEN, and the more
    expensive of the two.
    """
    i = body.find(signature)
    if i < 0:
        return ""
    j = body.find("\nexport ", i + len(signature))
    return body[i:] if j < 0 else body[i:j]


def _tracked_text_files() -> tuple[str, ...]:
    """Every tracked file git considers text, repo-relative.

    Asked of git rather than globbed, so the guard's subject set is exactly
    what a commit could carry. `-I` on the grep side is not available here, so
    binary files are filtered by extension after the fact.
    """
    import subprocess
    try:
        out = subprocess.run(
            ["git", "-C", str(REPO), "ls-files"],
            capture_output=True, text=True, check=True,
        ).stdout.split("\n")
    except Exception:
        return ()
    skip = {".png", ".jpg", ".jpeg", ".webp", ".tflite", ".ttf", ".otf",
            ".ico", ".zip", ".jar", ".keystore", ".pdf", ".mp4"}
    return tuple(
        rel for rel in out
        if rel and not any(rel.lower().endswith(e) for e in skip)
    )


def _without_comments(body: str) -> str:
    """Line comments removed.

    Necessary because several of these guards watch for a construct that the
    surrounding comment legitimately quotes while explaining why it was
    removed. A guard that reads prose finds the explanation and calls it the
    defect.
    """
    out, in_block = [], False
    for ln in body.splitlines():
        s = ln.lstrip()
        if in_block:
            # `*` continuation lines and the closing `*/`. Missing these let a
            # doc comment keep `gym_webhook_still_undisclosed` alive after the
            # dispatch it describes had been deleted -- the premise satisfied
            # by prose about itself.
            if "*/" in ln:
                in_block = False
            continue
        if s.startswith("/*"):
            in_block = "*/" not in ln
            continue
        if s.startswith("//") or s.startswith("*"):
            continue
        out.append(ln)
    return "\n".join(out)


def _block_at(body: str, needle: str, opener: str = "{") -> str:
    """The brace-delimited block that `needle` opens.

    `_member_body` slices from a signature; this slices from anything -- an
    `if`, a getter, a branch. It exists because the round of fixes before this
    one proved only that a guard was in the right FILE and the right HANDLER,
    never that the guard did anything. Demoting `throw new HttpsError(` to
    `logger.info(` inside the anonymous-caller branch left `f5` reading CLOSED
    while anonymous callers bought lifetime subscriptions again.
    """
    closer = {"{": "}", "[": "]", "(": ")"}[opener]
    i = body.find(needle)
    if i < 0:
        return ""
    j = body.find(opener, i)
    if j < 0:
        return ""
    depth, k = 1, j + 1
    while k < len(body) and depth:
        depth += {opener: 1, closer: -1}.get(body[k], 0)
        k += 1
    return body[j:k]


def _enum_has(body: str, enum_name: str, member: str) -> bool:
    """Whether a Dart enum declares a member, without depending on line numbers.

    Matches the declaration and scans to its closing brace rather than
    searching the whole file, so a same-named member on a different enum does
    not answer for this one.
    """
    m = re.search(r"\benum\s+" + re.escape(enum_name) + r"\b[^{]*\{", body)
    if not m:
        return False
    depth, i = 1, m.end()
    while i < len(body) and depth:
        depth += {"{": 1, "}": -1}.get(body[i], 0)
        i += 1
    return re.search(r"\b" + re.escape(member) + r"\b", body[m.end():i]) is not None


# ------------------------------------------------------------------ predicates
#
# Each source invariant returns (state, detail). The state it returns is THE
# state; whatever the row records is compared against it, never consulted to
# produce it.

def f_prefetch() -> tuple[str, str]:
    absent, detail = _symbol_absent("resolveAll")
    resolver = _read("mobile/lib/features/equipment/data/clip_url_resolver.dart")
    outcome = _read("mobile/lib/features/workouts/data/prefetch_outcome.dart")
    # The two files above declare the TYPES. Neither carries the refusal. The
    # wire is one line in the provider that builds the outcome from the batch,
    # and a file the predicate never opened cannot be a file it can vouch for:
    # cut that line and every quota refusal renders as `partialFailed`, a
    # self-resolving refusal shown to the user as a fault -- F-prefetch's
    # literal defect, restored, with this row still reading CLOSED. Measured.
    provider = _without_comments(
        _read("mobile/lib/features/workouts/state/offline_video_providers.dart")
    )
    page = _without_comments(
        _read("mobile/lib/features/workouts/workouts_page.dart")
    )
    carried = "quotaExhausted: batch.quotaExhausted" in provider
    # The getter is the one line between the flag and the state, and nothing
    # watched it. Collapsing `quotaExhausted ? partialQuota : partialFailed`
    # to a bare `partialFailed` left this row CLOSED with every quota refusal
    # rendering as a fault.
    mapped = "? PrefetchState.partialQuota" in _without_comments(
        _block_at(outcome, "PrefetchState get state")
    ).replace("\n", " ").replace("  ", " ")
    # And the two states must reach a person as different sentences. Pointing
    # the partialQuota arm at the failure string is the F2 defect wearing
    # F-prefetch's clothes, so it gets F2's treatment: resolve both arms
    # through the ARB and compare what is actually read.
    arb_page = json.loads(_read("mobile/lib/l10n/app_en.arb"))
    arms = {
        state: re.search(
            r"PrefetchState\." + state + r"\s*=>\s*l10n\.(\w+)", page
        )
        for state in ("partialQuota", "partialFailed")
    }
    texts = [
        arb_page.get(m.group(1)) if m else None for m in arms.values()
    ]
    rendered = all(texts) and texts[0] != texts[1]

    has_batch = re.search(r"\bclass\s+ClipBatch\b", resolver) is not None
    has_flag = re.search(r"\bfinal\s+bool\s+quotaExhausted\b", resolver) is not None
    has_partial = _enum_has(outcome, "PrefetchState", "partialQuota")

    parts = [
        detail,
        f"class ClipBatch: {has_batch}",
        f"ClipBatch.quotaExhausted: {has_flag}",
        f"PrefetchState.partialQuota: {has_partial}",
        f"refusal carried into the outcome: {carried}",
        f"the getter maps the flag to the state: {mapped}",
        f"rendered as its own sentence: {rendered}",
    ]
    ok = (absent and has_batch and has_flag and has_partial
          and carried and mapped and rendered)
    return ("CLOSED" if ok else "OPEN"), "; ".join(parts)


def f2() -> tuple[str, str]:
    failure = _read("mobile/lib/features/equipment/data/video_failure.dart")
    card = _read("mobile/lib/features/equipment/widgets/exercise_reference.dart")

    named = _enum_has(failure, "VideoFailureReason", "quotaExhausted")
    mapped = re.search(
        r"VideoFailureReason\.quotaExhausted\s*=>\s*l10n\.(\w+)", card
    )
    fault = re.search(
        r"VideoFailureReason\.linkUnavailable\s*=>\s*l10n\.(\w+)", card
    )
    # The key name proves nothing. A reviewer put it exactly: rename the key to
    # `clipQuotaReached` while its VALUE stays "The clip link is unavailable"
    # and an identifier check computes CLOSED for a screen still showing the
    # defect F2 names. So resolve both keys in the ARB and compare the strings
    # a person would actually read.
    arb = json.loads(_read("mobile/lib/l10n/app_en.arb"))
    quota_text = arb.get(mapped.group(1)) if mapped else None
    fault_text = arb.get(fault.group(1)) if fault else None
    distinct = bool(quota_text) and bool(fault_text) and quota_text != fault_text
    # And something has to PRODUCE the reason. The three checks above prove the
    # enum member exists, that the card maps it, and that the two strings a
    # person reads differ -- none of them proves any code path ever returns it.
    # Delete the one line that classifies the error and `ClipQuotaExhausted`
    # falls through to the generic branch: the user reads "The clip link is
    # unavailable" for a quota refusal, which IS F2, while this row reports
    # CLOSED and prints the correct refusal string as its evidence. Measured.
    classified = (
        "if (error is ClipQuotaExhausted) return VideoFailureReason"
        ".quotaExhausted" in _without_comments(failure).replace("\n", "")
    )
    # ...and the card has to CALL it with the error it was given. Rewrapping
    # the argument -- `classifyVideoFailure(Exception(error.toString()))` --
    # makes `error is ClipQuotaExhausted` false, drops the user to "The clip
    # link is unavailable" for a quota refusal, and left this row printing the
    # CORRECT refusal string as its own evidence.
    called = "classifyVideoFailure(error)" in _without_comments(card)
    ok = named and distinct and classified and called
    return ("CLOSED" if ok else "OPEN"), (
        f"VideoFailureReason.quotaExhausted: {named}; classified from "
        f"ClipQuotaExhausted: {classified}; classifier called with the raw "
        f"error: {called}; refusal reads {quota_text!r}; "
        f"fault reads {fault_text!r}"
    )


def f5() -> tuple[str, str]:
    """F5 is about `createCheckoutSession`, and only about it.

    `startFreeTrial` has rejected anonymous callers all along -- N-05 §6 states
    F5 as the *contrast* between the two handlers. So the guard has to be found
    inside the paid path specifically; found anywhere in the file, it is as
    likely to be the code F5 was complaining about as the code that fixes it.
    """
    handler = _without_comments(_exported_member(
        _read("functions/src/index.ts"),
        "export const createCheckoutSession = onCall(",
    ))
    guarded = 'sign_in_provider === "anonymous"' in handler
    # And it has to REFUSE. Scoping the search to the paid handler fixed WHERE
    # this looked and left it proving only that an `if` existed: replacing
    # `throw new HttpsError(` with `logger.info(` inside that branch -- valid
    # TypeScript, the firebase logger is variadic -- kept both substrings and
    # the row read CLOSED, while anonymous callers bought the uncancellable,
    # unrestorable subscription the comment above the guard describes.
    branch = _block_at(handler, 'sign_in_provider === "anonymous"')
    refuses = "throw new HttpsError(" in branch
    named = "reason: CHECKOUT_REFUSAL.ANONYMOUS_ACCOUNT" in branch
    ok = guarded and refuses and named
    return ("CLOSED" if ok else "OPEN"), (
        f"in createCheckoutSession -- anonymous guard present: {guarded}; "
        f"the branch throws: {refuses}; refusal names itself: {named}"
    )


def checkout_copy() -> tuple[str, str]:
    page = _read("mobile/lib/features/subscription/subscription_page.dart")
    classified = "checkoutLine(AppLocalizations.of(context), error)" in page
    # `error.toString()` is allowed, but only where the classifier has already
    # admitted it has no name for the failure. Anywhere else it is the defect.
    #
    # Presence of the branch is not the property. It used to be checked as a
    # substring, so appending `+ ' (' + error.toString() + ')'` to the
    # classified line -- a raw Firebase exception in front of a paying user,
    # which is exactly what this row forbids -- changed nothing. Count instead:
    # every raw render in the file must fall inside the unclassified branch.
    stripped = _without_comments(page)
    # A Dart collection-if: `if (...) ...[ ... ]`. Brackets, not braces.
    branch = _block_at(
        stripped, "CheckoutFailure.of(error).isUnclassified", opener="["
    )
    # And only RENDERS count. `_composePayload` writes the raw error into the
    # string the Copy button puts on the clipboard for a bug report -- correct,
    # and never on screen. Requiring every mention to sit inside the branch
    # reported the shipped tree as broken, which is how a guard gets muted.
    def _renders(text: str) -> int:
        return sum(
            1 for m in re.finditer(r"error\.toString\(\)|'\$error'", text)
            if "Text(" in text[max(0, m.start() - 140):m.start()]
        )
    guarded = bool(branch) and _renders(stripped) == _renders(branch)
    service = _read(
        "mobile/lib/features/subscription/data/cloud_functions_stripe_service.dart"
    )
    trial = _without_comments(
        _member_body(service, "Future<void> startFreeTrial(")
    )
    found = bool(trial)
    unwrapped = found and "throw StripeCheckoutException" not in trial
    ok = classified and guarded and unwrapped
    return ("CLOSED" if ok else "OPEN"), (
        f"card renders checkoutLine: {classified}; raw text behind "
        f"isUnclassified: {guarded}; startFreeTrial located: {found}; "
        f"trial not re-wrapped: {unwrapped}"
    )


def guest_upgrade_outcome() -> tuple[str, str]:
    """A sign-in that cost the person their guest history has to say so.

    Three conjuncts, because the defect can return by dropping any one of
    them: the outcome type must exist, the SHIPPING repository must decide it
    on whether a guest session was actually in play, and the screen must
    render the losing case. A type nobody reads is the original bug with more
    ceremony.
    """
    outcome = _read("mobile/lib/features/auth/data/sign_in_outcome.dart")
    repo = _without_comments(
        _read("mobile/lib/features/auth/data/firebase_auth_repository.dart")
    )
    page = _without_comments(_read("mobile/lib/features/auth/login_page.dart"))

    typed = _enum_has(outcome, "GuestUpgrade", "orphaned")
    decided = (
        "wasGuest ? GuestUpgrade.orphaned : GuestUpgrade.notAGuest" in repo
    )
    # A CONSTRUCTION inside the losing branch. `"_GuestHistoryNotice" in page`
    # was satisfied by the widget's own `class _GuestHistoryNotice` declaration
    # further down the same file, so the call site could be deleted outright
    # while this reported "the screen renders it: True" -- and the person who
    # had just lost their guest history was told nothing. Which is the original
    # bug, with more ceremony, exactly as this docstring warns.
    branch = _block_at(
        page, "action.value == GuestUpgrade.orphaned", opener="["
    )
    shown = "GuestUpgrade.orphaned" in page and "_GuestHistoryNotice(" in branch
    ok = typed and decided and shown
    return ("CLOSED" if ok else "OPEN"), (
        f"GuestUpgrade.orphaned declared: {typed}; the shipping repository "
        f"decides on wasGuest: {decided}; the screen renders it: {shown}"
    )


def scanner_dependency_pin() -> tuple[str, str]:
    """The recovered v1 environment, still recorded outside the environment.

    A pin whose only copy lives in the venv it describes is not a pin. This
    checks the file exists and still carries the versions the provenance
    document names -- so deleting it, or quietly editing a version in one place
    and not the other, is a finding rather than a discovery made years later.
    """
    path = REPO / "core" / "ml" / "pins" / "ml_train_env_recovered_2026-08-18.txt"
    if not path.exists():
        return "OPEN", "the recovered pin file is gone"
    body = path.read_text(encoding="utf-8", errors="replace")
    doc = _read("core/ml/SCANNER_PROVENANCE.md")
    required = ("tensorflow-cpu==2.15.1", "keras==2.15.0",
                "numpy==1.26.4", "mediapipe==1.0.0")
    # Whole lines, comments stripped. As a substring test,
    # `tensorflow-cpu==2.16.0  # was tensorflow-cpu==2.15.1` satisfied the
    # check while the file pinned a different TensorFlow than the provenance
    # document names -- the recovered environment silently ceasing to be
    # reproducible, reported as agreement.
    pinned = {
        ln.split("#")[0].strip()
        for ln in body.splitlines() if ln.split("#")[0].strip()
    }
    missing = [v for v in required if v not in pinned]
    # The versions must agree with the prose that cites them, in both
    # directions -- the document names these four explicitly.
    undocumented = [
        v for v in required
        if v.split("==")[1] not in doc
    ]
    ok = not missing and not undocumented
    return ("CLOSED" if ok else "OPEN"), (
        f"pin holds {len(required) - len(missing)}/{len(required)} named "
        f"versions; missing from pin: {missing or 'none'}; absent from the "
        f"provenance document: {undocumented or 'none'}"
    )


def metric_provenance_six() -> tuple[str, str]:
    """Recomputed from the locator, not read from the document.

    The six claims are DORMANT because no locator can honestly find them, not
    because a document says six. Flipping one to MATCHES without source
    equivalence changes this count, and the row fails.
    """
    sys.path.insert(0, str(REPO / "scripts" / "ml"))
    from evaluation_report import audit  # noqa: E402

    result = audit()
    counts = result["counts"]
    # The denominator. Emptying `models` in MODEL_REGISTRY.json took the audit
    # to zero claims, and zero NOT_LOCATABLE read as progress: a registry that
    # had lost the evaluation blocks this audit exists to police was
    # indistinguishable from one that had been fixed. `human_labels_are_zero`
    # already refuses a zero that came from an empty scan; this did not.
    claims = result.get("claims", 0)
    n = counts.get("NOT_LOCATABLE", 0)
    drifted = counts.get("DRIFTED", 0)
    missing = counts.get("SOURCE_MISSING", 0)
    # DRIFTED is a different animal and is NOT dormant: it means a source was
    # located and disagrees. One appearing here is a defect, not a status.
    # `n == 6` was wrong, and wrong in a way worth naming: it made the
    # residual a permanent expectation, so honestly closing one of the six
    # would have read as drift and blocked --report. Six is a CEILING. Fewer
    # is progress; more is a regression; DRIFTED and SOURCE_MISSING are
    # different animals entirely and must stay at zero, because they mean a
    # source WAS located and disagrees, or is missing outright.
    ok = claims >= 20 and n <= 6 and drifted == 0 and missing == 0
    return ("DORMANT" if ok else "EXECUTABLE_ENGINEERING_WORK"), (
        f"NOT_LOCATABLE={n} (ceiling 6), DRIFTED={drifted} (expected 0), "
        f"SOURCE_MISSING={missing} (expected 0), total claims={result['claims']}"
    )


# ---------------------------------------------------- non-source invariants
#
# These return (ok, detail). They cannot set a state; they can only report that
# the premise a state rests on still holds.

def n07_still_dormant() -> tuple[bool, str]:
    router = _read("mobile/lib/core/router/app_router.dart")
    declared = "'/team/:teamId'" in router
    # Dormancy is the absence of a caller, so it is an absence check. A literal
    # navigation to the route is what would end it.
    #
    # Comments are stripped first, and that is not a detail: a mutation that
    # inserted `// context.go('/team/1')` as a COMMENT was caught by the first
    # version of this predicate, which would have reported a documented example
    # as a wired route. Same defect as the image predicate that read the word
    # `training` in prose. A guard that cannot tell code from commentary
    # eventually gets switched off by whoever it cries wolf at.
    nav = re.compile(r"""(?:go|push|pushNamed|goNamed)\(\s*['"]/team/""")
    callers = [
        p for p, b in _dart_sources().items()
        if nav.search(_without_comments(b))
    ]
    ok = declared and not callers
    return ok, (
        f"route declared: {declared}; navigations from lib/: "
        f"{callers if callers else 'none'}"
    )


#: Where a gym-membership model could appear. Client code alone is not enough:
#: `reportEquipment` writes through the Admin SDK, which bypasses
#: `firestore.rules` entirely, so a membership that actually BOUND anything
#: would have to be checked server-side. A Dart-only scan therefore watches the
#: one place the model is least likely to live.
MEMBERSHIP_SURFACES = ("functions/src/index.ts", "firestore.rules")

#: Named flows, plus the collection path in any quoting style. `db.doc(
#: `memberships/${uid}`)` is how the server would write it and matches no
#: `collection("memberships")` spelling, which the first version of this
#: pattern was the only thing looking for.
_MEMBERSHIP_MODEL = re.compile(
    r"\b(?:GymMembership|MembershipRepository|joinGym|checkInToGym)\b"
    r"|memberships/"
    r"|collection\(\s*['\"]memberships['\"]"
)


def no_gym_membership_model() -> tuple[bool, str]:
    """N-04's premise: the equipment report has no gym to associate with.

    The review that produced this established that a gym-membership model does
    not exist here in any form -- no membership collection, no join or
    check-in flow, no writer for `gyms/`, no scanner resolving a gym id. The
    report sheet defaults `gymId` to `unknown` because there is nothing to
    default it to. If one ever appears, the question the operator was asked
    has changed and the row must be re-put rather than left standing.

    The first version scanned `mobile/lib` and nothing else. Measured: adding a
    `joinGym` callable and a `memberships/` collection to
    `functions/src/index.ts` -- a complete membership model, in the only layer
    that could enforce one -- left this returning True. An operator would have
    gone on being asked a question whose premise had died, which is the exact
    failure the ledger exists to prevent, one level up: not a stale STATE, a
    stale QUESTION.
    """
    hits = [p for p, b in _dart_sources().items()
            if _MEMBERSHIP_MODEL.search(_without_comments(b))]
    hits += [rel for rel in MEMBERSHIP_SURFACES
             if _MEMBERSHIP_MODEL.search(_without_comments(_read(rel)))]
    return not hits, (
        "no gym-membership model exists in mobile/lib, "
        f"{' or '.join(MEMBERSHIP_SURFACES)}, so an equipment report still "
        "has nothing to associate with"
        if not hits else f"a membership model now exists in {hits}"
    )


def f025_tripwire_intact() -> tuple[bool, str]:
    """F025 was left dormant and given a tripwire rather than a repair.

    The precedent this repository set: repairing an artefact nothing reaches
    spends effort on code with no user, while deleting it removes intended
    work mid-audit. The tripwire is the whole of the mitigation, so its
    disappearance is the event worth catching -- a dormant item whose guard
    was quietly dropped is indistinguishable from a live one.
    """
    trap = REPO / "mobile" / "test" / "adversarial" / "dormant_traps_test.dart"
    if not trap.exists():
        return False, "the dormant-code tripwire suite is gone"
    body = _without_comments(trap.read_text(encoding="utf-8", errors="replace"))
    # Not the NAME. The whole check used to be `"F025" in body` over the raw
    # file, comments included -- so a suite reduced to `// F025: tripwire
    # deleted.` plus an empty `main()` passed, and `flutter test` passes on an
    # empty main too. That is the guard-cannot-tell-code-from-commentary
    # failure this module fixed for `n07_still_dormant` and then repeated here.
    #
    # So assert what the tripwire ASSERTS. F025's mitigation is this suite and
    # nothing else; a suite that no longer makes these two claims is not a
    # weaker tripwire, it is an absent one.
    required = ("dailyWorkouts", "expect(readers, isEmpty",
                "expect(seed, contains(",
                # The subject set itself. Narrowing `dartSources('lib')` to
                # `dartSources('lib/l10n')` leaves all three assertions above
                # intact and makes the suite assert emptiness over an empty
                # set -- so a real reader ships, the tripwire passes, and this
                # invariant agreed. Same empty-denominator failure
                # `human_labels_are_zero` already refuses.
                "dartSources('lib')")
    missing = [needle for needle in required if needle not in body]
    return not missing, (
        "the tripwire still asserts that nothing reads dailyWorkouts and that "
        "the nine ids are still dangling"
        if not missing else
        f"the tripwire no longer makes these assertions: {missing}"
    )


def n05_premise_holds() -> tuple[bool, str]:
    """N-05 rests on a conflict with the published deletion promise.

    If the policy were rewritten, the decision's premise changed and the
    operator should be asked again rather than left resting on a document that
    no longer says what it said.
    """
    policy = _read("public/privacy.html")
    promise = "It is irreversible: afterwards there is nothing left to restore"
    holds = promise in policy
    return holds, (
        "published deletion promise intact, so a device control surviving "
        "deletion still conflicts with it"
        if holds else
        "the deletion promise in public/privacy.html has changed -- N-05's "
        "premise must be re-examined before the row is trusted"
    )


#: Where a human QA label would actually land. `core/ml/review/` holds the
#: batches SENT OUT; `core/ml/datasets/` is where `human_eval.py --out`
#: defaults (`scripts/ct1/human_eval.py`) and therefore where the labels
#: `review_import.py` builds are persisted. The first version of this guard
#: watched only the outbound directory -- a guard pointed at the wrong surface,
#: which is worse than an untested one because it reports zero forever.
HUMAN_LABEL_ROOTS = ("core/ml/review", "core/ml/datasets")


def human_labels_are_zero() -> tuple[bool, str]:
    """`HUMAN_REVIEW_LABELS = 0`, counted, with the denominator reported.

    Returning "0" from a scan that visited no files is the empty-set pass this
    repository keeps finding in its own guards. The denominator is part of the
    answer, and it is asserted non-zero by the caller.
    """
    hits, scanned = [], 0
    for root in HUMAN_LABEL_ROOTS:
        base = REPO / root
        if not base.exists():
            continue
        for p in base.rglob("*.json"):
            scanned += 1
            if "HUMAN_REVIEWED_QA_LABEL" in p.read_text(
                encoding="utf-8", errors="replace"
            ):
                hits.append(p.relative_to(REPO).as_posix())
    ok = not hits and scanned > 0
    return ok, (
        f"HUMAN_REVIEW_LABELS = {len(hits)} of {scanned} files scanned"
        + (f" in {hits[:3]}" if hits else "")
        + ("" if scanned else " -- SCANNED NOTHING, so the zero means nothing")
    )


def production_image_collection_disabled() -> tuple[str, str]:
    """`PRODUCTION_IMAGE_COLLECTION = DISABLED`, proven by absent machinery.

    The first version of this predicate searched for the words `training`,
    `dataset` and `corpus` near an upload verb, and immediately reported
    `programme_specs.dart` -- a comment reading "would put an unreviewed
    training design into the split". In a fitness application `training` is the
    domain noun; a vocabulary check cannot mean anything here.

    So it checks for the MACHINERY instead, which is unambiguous and, at the
    time of writing, entirely absent: `mobile/lib` contains no `FirebaseStorage`
    handle, no `putData`/`putFile`, no `UploadTask`, and `functions/` has no
    storage-object trigger. Progress photos are not in Storage at all -- they
    are encrypted with a key that never leaves the device. Collection is not
    disabled by a flag someone could flip; there is nothing built to collect
    with, and that is a far stronger statement.
    """
    # Storage was never the only route. A file that base64-encodes a progress
    # photo and `http.post`s it to an intake endpoint carried images off the
    # device with none of the machinery below present, and this row -- which
    # is a PRIVACY claim -- went on asserting DISABLED. Storage handles, and
    # any outbound call in a file that also encodes bytes.
    client = re.compile(
        r"\b(?:FirebaseStorage|UploadTask)\b|\.put(?:Data|File|String|Blob)\s*\("
    )
    outbound = re.compile(r"\b(?:http|dio|Dio)\s*\.\s*post\b|\bhttp\.MultipartRequest\b")
    encodes = re.compile(r"\bbase64Encode\b|\breadAsBytes\b|\bXFile\b")
    server = re.compile(r"\bonObjectFinalized\b|\bonObjectArchived\b")
    hits = []
    for p, raw in _dart_sources().items():
        b = _without_comments(raw)
        if client.search(b) or (outbound.search(b) and encodes.search(b)):
            hits.append(p)
    for p in (REPO / "functions" / "src").rglob("*.ts"):
        if server.search(p.read_text(encoding="utf-8", errors="replace")):
            hits.append(p.relative_to(REPO).as_posix())
    return ("DISABLED" if not hits else "ENABLED"), (
        "no client upload machinery and no storage-object trigger exist"
        if not hits else f"image-collection machinery present in {hits}"
    )


def scanner_metadata_validated() -> tuple[str, str]:
    """The genuine library's answer, tied to the artefact it answered about.

    This row read `ENVIRONMENT_BLOCKED` for several passes on the strength of a
    `pip install` that failed INSIDE a container -- the interception CA is in
    the Windows trust store and absent from `python:3-slim`'s bundle, so a
    property of the container was generalised into a property of the host. The
    host reaches PyPI perfectly well. Downloading the manylinux wheels there
    and installing them offline in the container needs no TLS bypass at all,
    and the genuine `_pywrap_metadata_version` then computes `1.0.0` -- the
    same value the pipeline's stub stamped.

    So the state is now source-provable, and the conjunct that matters is the
    DIGEST: the recorded answer is about one artefact, and swapping the model
    must reopen the question rather than inherit a verdict earned by a
    different file. That is the whole reason this is a predicate and not a
    sentence in a document.
    """
    try:
        record = json.loads(_read("core/ml/METADATA_VALIDATION.json"))
    except Exception as exc:  # noqa: BLE001 -- absent or unparseable is the answer
        return "OPEN", f"no usable validation record: {type(exc).__name__}"
    # `null`, a list, a string -- all parse cleanly and are not a record. Found
    # by a mutation that deleted the record's contents and crashed this
    # function instead of opening the row. `check()` would have caught the
    # raise as PREDICATE_ERROR, so nothing was ever silently green; but a guard
    # that answers "OPEN, and here is why" is more use than a traceback.
    if not isinstance(record, dict):
        return "OPEN", f"the validation record is a {type(record).__name__}"

    model = REPO / record.get("input_path", "")
    if not model.exists():
        return "OPEN", f"the validated artefact is gone: {record.get('input_path')}"
    digest = hashlib.sha256(model.read_bytes()).hexdigest()
    if digest != record.get("input_sha256"):
        return "OPEN", (
            "the shipped model is not the one that was validated "
            f"({digest[:12]} on disk, {str(record.get('input_sha256'))[:12]} "
            "recorded) -- revalidate rather than inherit the old answer"
        )
    if record.get("state") != "VALIDATED_MATCH":
        return "OPEN", f"validation state is {record.get('state')!r}"
    if record.get("computed_min_parser_version") != \
            record.get("recorded_min_parser_version"):
        return "OPEN", "the record contradicts itself on the parser version"
    return "CLOSED", (
        f"the genuine library computes "
        f"{record['computed_min_parser_version']!r}, matching the stamped "
        f"value, for the model at {digest[:12]}"
    )


def metadata_is_still_environment_blocked() -> tuple[bool, str]:
    """Two things must hold for `ENVIRONMENT_BLOCKED` to still be the truth.

    The row used to assert only the first. That made it a claim about where a
    file lives, when what it actually means is *nobody here can answer the
    question* -- and the second conjunct is the one that will change. The day
    someone installs the genuine library, this row's premise dies and the
    ledger should say so rather than wait to be noticed, which is the same
    bidirectional duty `AUTHORITY_SPOKE` performs for the other authorities.
    """
    hits = [
        p.relative_to(REPO).as_posix()
        for p in REPO.rglob("attach_metadata.py")
        if "build" not in p.parts
    ]
    if hits:
        return False, f"attach_metadata.py is now in this repository: {hits}"

    if importlib.util.find_spec("tflite_support") is not None:
        return False, (
            "tflite_support is importable here, so scripts/ml/"
            "validate_metadata.py can be run and the question answered. "
            "Run it; do not leave this row blocked."
        )
    return True, (
        "attach_metadata.py is outside this worktree (D:\\tools\\"
        "equipment-model) and tflite_support is not importable, so "
        "scripts/ml/validate_metadata.py reports ENVIRONMENT_NOT_RUN"
    )


# -------------------------------------------------------- closure authorities
#
# The only things that may move a non-source row into a terminal state. Each
# answers one question: has the owning authority actually produced something?

def human_qa_labels_returned() -> tuple[bool, str]:
    """CT-1's closing authority is a returned CONTENT review, not a clinical one.

    Wiring this to `clinical_authority_returned` was a modelling error caught
    on review of this module's own first draft. `scripts/ct1/review_import.py`
    refuses to ask whether an exercise is safe, in its own docstring, and that
    refusal is load-bearing: a content reviewer must never be able to produce a
    clinical claim. Letting one closure callable serve both rows would have
    merged the two authorities inside the mechanism built to keep authorities
    apart.
    """
    zero, detail = human_labels_are_zero()
    return (not zero), detail


def clinical_authority_returned() -> tuple[bool, str]:
    """A clinical review is closed by a credentialled human, or not at all.

    Delegated to `clinical_import.validate`, which this repository already owns
    and already runs in CI, rather than re-implemented here. The first version
    was a four-field emptiness check, and a reviewer pointed out what that
    costs: `validate` additionally requires a schema version, a non-blank
    handoff commit, a timezone-aware `reviewed_at` and a `catalogue_sha256`
    matching the CURRENT catalogue. A submission that is genuinely signed but
    stale against a catalogue that has since changed would have satisfied the
    hand-rolled check and been refused by the repository's own validator --
    the ledger would have closed D1 on evidence the clinical importer rejects.
    """
    path = REPO / "core" / "review" / "worklist" / "submission.json"
    if not path.exists():
        return False, "no submission.json exists"
    sys.path.insert(0, str(REPO / "scripts" / "review"))
    import clinical_import  # noqa: E402

    try:
        submission = clinical_import.load_submission(path)
        clinical_import.validate(submission)
    except clinical_import.ClinicalImportError as exc:
        return False, f"the repository's clinical validator refuses it: {exc}"
    except (OSError, ValueError) as exc:
        return False, f"submission unreadable: {exc}"
    return True, "clinical_import.validate accepts the submission"


def operator_decision_recorded(item: str) -> Callable[[], tuple[bool, str]]:
    """An operator decision is a file the operator wrote, not a status word.

    Deliberately a dedicated artefact under `core/decisions/` rather than a
    phrase somewhere in the decision log. A prose match would mean any agent
    that writes a convincing enough sentence can close an operator item, which
    is the laundering this whole module exists to prevent.
    """
    def check() -> tuple[bool, str]:
        path = REPO / "core" / "decisions" / f"{item}.md"
        if not path.exists():
            return False, (
                f"no operator decision record at core/decisions/{item}.md"
            )
        return True, f"operator decision recorded at core/decisions/{item}.md"
    return check


def gym_webhook_still_undisclosed() -> tuple[bool, str]:
    """P-1's premise: a third recipient exists and the policy says there is none.

    Two halves, and the question only stands while BOTH hold. If the dispatch
    is removed, there is no third recipient and nothing to disclose. If the
    processor sentence is amended, it has been disclosed. Either way the
    operator has answered, and a row that went on asking would be the stale
    QUESTION failure this ledger was widened to catch.
    """
    arb = _read("mobile/lib/l10n/app_en.arb")
    claims_two = "Two processors are involved, and no others" in arb
    # The READ, inside the handler. Only two lines in that file mention the
    # symbol and one of them is prose inside a `/* */` doc comment, so with
    # the dispatch deleted the premise stayed satisfied by a sentence
    # describing the thing that no longer existed -- and the operator would
    # have gone on being asked a question that had answered itself.
    handler = _without_comments(_exported_member(
        _read("functions/src/index.ts"),
        "export const reportEquipment = onCall(",
    ))
    dispatches = (
        "maintenanceWebhookUrl" in handler and "await fetch(" in handler
    )
    return claims_two and dispatches, (
        "the privacy body still says two processors and no others, and "
        "reportEquipment still dispatches to a gym-controlled endpoint"
        if claims_two and dispatches else
        f"answered: policy claims two processors = {claims_two}; "
        f"webhook dispatch present = {dispatches}"
    )


def gym_webhook_disclosure_stays_honest() -> tuple[bool, str]:
    """The CLOSED-state twin of `gym_webhook_still_undisclosed`.

    The operator chose DISCLOSE, not REMOVE (2026-08-21,
    `core/decisions/gym-webhook-disclosure.md`): the dispatch stays, the copy
    names the gym as a conditional third recipient instead of claiming there
    are only two processors. True while both halves of that hold.

    Checked on the isolated privacy value in each of six surfaces -- codex
    review, 2026-08-21, across three rounds: (1) reading only the English
    `.arb` and only testing for the OLD sentence's absence meant a Russian-only
    or hosted-page-only regression could pass unnoticed -- fixed by adding the
    other five surfaces; (2) a whole-file substring search on `legal_text.py`
    or an `.arb` matches a decoy anywhere in the file (the *Terms* body, an
    unrelated key, a comment) even with the privacy value itself reverted, so
    a passing check proved nothing about the privacy text specifically --
    fixed by importing `legal_text` and reading `PRIVACY_EN`/`PRIVACY_RU`
    directly (the module import also makes the old raw-text
    line-continuation-stripping workaround unnecessary: Python already
    evaluated the string), and by JSON-parsing each `.arb` for its
    `legalPrivacyBody` key specifically. `public/privacy.html` is generated
    one file per document (`build_legal.py`'s `for doc in DOCS: ... / f"
    {doc}.html"`), so it never contains Terms content to begin with and a
    whole-file check on it is already scoped correctly.

    Also checks that the webhook dispatch itself (`functions/src/index.ts`'s
    `reportEquipment`) is still present -- codex review, round 3: the decision
    record promises this row reopens if the dispatch is removed, but nothing
    here read that file, so removing it could not have reopened anything.
    Mirrors `gym_webhook_still_undisclosed`'s own dispatch check.
    """
    sys.path.insert(0, str(REPO / "scripts" / "legal"))
    import legal_text  # noqa: E402

    en_arb = json.loads(_read("mobile/lib/l10n/app_en.arb"))
    ru_arb = json.loads(_read("mobile/lib/l10n/app_ru.arb"))
    # The published surface Google Play's store listing points at, not just
    # the in-app copy -- codex review, 2026-08-21: a regression landing only
    # on the hosted page (bypassing `build_legal.py`, or a hand-edit after)
    # would otherwise leave this row green.
    privacy_html = _read("public/privacy.html")

    marker_en = "third recipient of"
    marker_ru = "третьим получателем"
    old_claim_en = "Two processors are involved, and no others"
    old_claim_ru = "два обработчика и никакие другие"

    def ok(text: str, marker: str, old_claim: str) -> bool:
        return marker in text and old_claim not in text

    checks = {
        "legal_text.py (en)": ok(legal_text.PRIVACY_EN, marker_en, old_claim_en),
        "legal_text.py (ru)": ok(legal_text.PRIVACY_RU, marker_ru, old_claim_ru),
        "app_en.arb": ok(en_arb.get("legalPrivacyBody", ""), marker_en, old_claim_en),
        "app_ru.arb": ok(ru_arb.get("legalPrivacyBody", ""), marker_ru, old_claim_ru),
        "privacy.html (en)": ok(privacy_html, marker_en, old_claim_en),
        "privacy.html (ru)": ok(privacy_html, marker_ru, old_claim_ru),
    }
    decided = (REPO / "core" / "decisions" / "gym-webhook-disclosure.md").exists()
    handler = _without_comments(_exported_member(
        _read("functions/src/index.ts"),
        "export const reportEquipment = onCall(",
    ))
    dispatches = "maintenanceWebhookUrl" in handler and "await fetch(" in handler

    failing = [k for k, v in checks.items() if not v]
    holds = not failing and decided and dispatches
    return holds, (
        "disclosed and in sync across source, en and ru; decision record "
        "present; dispatch still live"
        if holds else
        f"failing surfaces = {failing or 'none'}; decision record present = "
        f"{decided}; dispatch still live = {dispatches}"
    )


#: A literal assigned to the key, in any quoting style. Narrow on purpose: a
#: loose "long token near the word roboflow" pattern would fire on every sha256
#: in the provenance documents, and a guard that cries wolf is switched off.
#: `ROBOFLOW_API_KEY` is Roboflow's own documented environment-variable name,
#: so the likeliest spelling of a committed key was the one the first pattern
#: missed. Any `ROBOFLOW…KEY`.
_ROBOFLOW_LITERAL = re.compile(
    r"ROBOFLOW[_A-Z]*KEY\s*[=:]\s*[\"\'][^\"\']{8,}"
)


def roboflow_key_not_committed() -> tuple[bool, str]:
    """The half of the credential question this repository can actually answer.

    It cannot know whether the key was reissued -- that is a Roboflow console
    action. It CAN know that the plaintext key has never entered this tree,
    which is the outcome that would turn an exposure into a permanent one.
    Verified at HEAD and across all history with `git log --all -S` when the
    row was enrolled; this guards it going forward.
    """
    files = _tracked_text_files()
    # Fail CLOSED on an empty subject set. `_tracked_text_files` swallows every
    # exception and returns (), so anywhere git is unavailable -- an export, a
    # copied tree, a CI image without git -- this returned a clean bill of
    # health from scanning nothing. On a secrets guard, silence has to mean
    # "unknown", never "fine".
    if not files:
        return False, (
            "git ls-files returned nothing, so this scanned no files at all. "
            "That is not a clean result; it is an unanswered question."
        )
    hits = sorted({
        rel for rel in files if _ROBOFLOW_LITERAL.search(_read(rel))
    })
    return not hits, (
        "no ROBOFLOW_KEY literal is assigned anywhere in this repository"
        if not hits else f"a ROBOFLOW_KEY literal now appears in {hits}"
    )


# ------------------------------------------------------------------- the rows

@dataclass(frozen=True)
class Row:
    item: str
    state: str
    authority: str
    #: The paths a reader should open. A tuple rather than one comma-joined
    #: string, so each can be checked to exist -- a row citing a file that was
    #: deleted or renamed is the same drift this module exists to catch, just
    #: one field over.
    evidence: tuple[str, ...]
    #: Source-provable rows only. Returns the state; the record is compared.
    predicate: Callable[[], tuple[str, str]] | None = None
    #: Any row. Returns whether the premise of the current state still holds.
    invariant: Callable[[], tuple[bool, str]] | None = None
    #: Non-source rows only. Required before a terminal state is permitted.
    closure: Callable[[], tuple[bool, str]] | None = None
    notes: str = ""
    #: Explicit, reviewable admission that no honest local check exists. Only
    #: legal on non-source rows, and it must say why.
    no_local_predicate: str = ""
    #: `(path, verbatim fragment)` from the document that OWNS this item's
    #: narrative. Checked to still be present, so the row cannot go on
    #: summarising a sentence its source has since deleted or reversed.
    quote: tuple[str, str] | None = None


def quoted_source_intact(row: Row) -> tuple[bool, str]:
    """Whether a row's cited fragment is still in the document that owns it.

    A documentation reviewer put this exactly right: `notes` was free prose
    paraphrasing `N05_DISPOSITION.md` and friends, checked by nothing -- which
    is a hand-maintained status table living inside the module written to
    abolish hand-maintained status tables. The narrative still belongs to the
    per-item document; this row may only quote it, and the quote must still be
    there.
    """
    if row.quote is None:
        return True, "no quotation to verify"
    path, fragment = row.quote
    full = REPO / path
    if not full.exists():
        return False, f"cited document {path} does not exist"
    body = full.read_text(encoding="utf-8", errors="replace")
    if fragment not in body:
        return False, (
            f"{path} no longer contains the quoted fragment {fragment!r} -- "
            "the owning document moved on and this row did not"
        )
    return True, f"quotation still present in {path}"


LEDGER: tuple[Row, ...] = (
    Row(
        item="F-prefetch",
        state="CLOSED",
        authority=SOURCE,
        evidence=("mobile/lib/features/equipment/data/clip_url_resolver.dart",
                  "mobile/lib/features/workouts/data/prefetch_outcome.dart",),
        predicate=f_prefetch,
        notes="Recorded OPEN for weeks after the fix landed. This row is the "
              "reason the module exists.",
    ),
    Row(
        item="F2",
        state="CLOSED",
        authority=SOURCE,
        evidence=("mobile/lib/features/equipment/data/video_failure.dart",),
        predicate=f2,
        notes="A quota refusal must not render through the same string as a "
              "fault.",
    ),
    Row(
        item="F5",
        state="CLOSED",
        authority=SOURCE,
        evidence=("functions/src/index.ts",),
        predicate=f5,
        notes="Real-money checkout refused on an account nobody can sign back "
              "into.",
    ),
    Row(
        item="checkout-copy",
        state="CLOSED",
        authority=SOURCE,
        evidence=("mobile/lib/features/subscription/subscription_page.dart",),
        predicate=checkout_copy,
        notes="error.toString() reaches the screen only where the classifier "
              "admits it has no name for the failure.",
    ),
    Row(
        item="metric-provenance-six",
        state="DORMANT",
        authority=SOURCE,
        evidence=("scripts/ml/evaluation_report.py",
                  "core/ml/METRIC_PROVENANCE.md",),
        predicate=metric_provenance_six,
        quote=("core/ml/METRIC_PROVENANCE.md", "UNRESOLVED_BY_DESIGN"),
        notes="Measurement true is not the same as source claim locatable.",
    ),
    Row(
        item="guest-upgrade-outcome",
        state="CLOSED",
        authority=SOURCE,
        evidence=("mobile/lib/features/auth/data/sign_in_outcome.dart",
                  "mobile/lib/features/auth/data/firebase_auth_repository.dart",
                  "mobile/lib/features/auth/login_page.dart",),
        predicate=guest_upgrade_outcome,
        quote=("core/review/N05_DISPOSITION.md",
               "The flow now handles it"),
        notes="The unfixed half of P2, and the last shape of the defect this "
              "programme kept finding: a refusal that arrives dressed as a "
              "success. Linking keeps the uid; falling back signs the person "
              "into their real account and leaves this device's history under "
              "a uid nobody can sign into again. Both returned an AuthUser. "
              "The quoted sentence stays in the disposition document as the "
              "record of what was open; this row is what closed it.",
    ),
    Row(
        item="scanner-dependency-pin",
        state="CLOSED",
        authority=SOURCE,
        evidence=("core/ml/pins/ml_train_env_recovered_2026-08-18.txt",
                  "core/ml/SCANNER_PROVENANCE.md",),
        predicate=scanner_dependency_pin,
        quote=("core/ml/SCANNER_PROVENANCE.md", "Recovered, not historical"),
        notes="Closes the recoverability of the environment, and nothing about "
              "the historical claim. Whether these were the versions v1 was "
              "trained with stays UNKNOWN and is not made recoverable by "
              "having been written down.",
    ),
    Row(
        item="N-05",
        state="OPERATOR_DECISION_REQUIRED",
        authority=OPERATOR,
        evidence=("core/review/N05_DISPOSITION.md", "public/privacy.html"),
        invariant=n05_premise_holds,
        closure=operator_decision_recorded("N-05"),
        quote=("core/review/N05_DISPOSITION.md",
               "per-account uniqueness is not the binding constraint"),
        notes="Narrative belongs to N05_DISPOSITION.md; this row quotes it.",
    ),
    Row(
        item="N-04-gym-association",
        state="OPERATOR_DECISION_REQUIRED",
        authority=OPERATOR,
        evidence=("core/review/N04_EQUIPMENT_REPORT_AUTHORITY.md",
                  "core/DECISION_LOG.md",),
        invariant=no_gym_membership_model,
        closure=operator_decision_recorded("N-04"),
        notes="Whether an equipment report should be tied to a gym is a "
              "product question with no engineering answer available: there "
              "is no membership model to tie it to, and building one to "
              "satisfy a report field would be inventing a feature to justify "
              "a column. Enrolled because the sweep found it in prose only -- "
              "it appears in no status table anywhere.",
    ),
    Row(
        item="F025",
        state="DORMANT",
        authority=OPERATOR,
        evidence=("mobile/test/adversarial/dormant_traps_test.dart",),
        invariant=f025_tripwire_intact,
        closure=operator_decision_recorded("F025"),
        notes="Same disposition as N-07 and for the same reason. The row "
              "tracks the TRIPWIRE, not the dormant code: the code being "
              "unreached is the accepted state, and the guard vanishing is "
              "the change that would matter.",
    ),
    Row(
        item="N-07",
        state="DORMANT",
        authority=OPERATOR,
        evidence=("core/review/N07_TEAM_ACTIVATION_GATE.md",
                  "mobile/test/adversarial/n07_team_activation_test.dart",),
        invariant=n07_still_dormant,
        closure=operator_decision_recorded("N-07"),
        quote=("core/review/N07_TEAM_ACTIVATION_GATE.md", "`N07 = KEEP`"),
        notes="The state is what engineering can OBSERVE -- no caller exists -- "
              "not a product claim. The decision itself is real and lives in "
              "the quoted document; this row deliberately does not restate it, "
              "because a row asserting a decision was taken needs an artefact "
              "from whoever took it, and writing that artefact here would be "
              "engineering signing the operator's name. The closure check stays "
              "attached so that if the operator DOES record one, the row is "
              "flagged for restating rather than quietly left behind.",
    ),
    Row(
        item="D1",
        state="EXTERNAL_AUTHORITY_REQUIRED",
        authority=EXTERNAL,
        evidence=("core/review/CLINICAL_VALIDATION_HANDOFF.md",
                  "core/review/worklist/submission.json",),
        closure=clinical_authority_returned,
        no_local_predicate="Whether a clinician has reviewed the catalogue is "
                           "not a property of this tree. The closure check "
                           "reads the submission; nothing here can invent one.",
    ),
    Row(
        item="H3",
        state="HOLD",
        authority=EXTERNAL,
        evidence=("core/review/CLINICAL_VALIDATION_HANDOFF.md",),
        closure=clinical_authority_returned,
        no_local_predicate="H3 is held by the same missing authority as D1 and "
                           "is released by the same return, not separately.",
    ),
    Row(
        item="CT1-human-labels",
        state="EXTERNAL_AUTHORITY_REQUIRED",
        authority=EXTERNAL,
        evidence=("core/ml/review/",),
        invariant=human_labels_are_zero,
        closure=human_qa_labels_returned,
        notes="HUMAN_REVIEW_LABELS = 0, EVALUATION_LABEL_GAP = OPEN, "
              "CONTINUOUS_RETRAINING_OPERATIONAL = NO. The invariant counts "
              "labels rather than trusting the sentence.",
    ),
    Row(
        item="scanner-metadata",
        state="CLOSED",
        authority=SOURCE,
        evidence=("core/ml/METADATA_VALIDATION.json",
                  "scripts/ml/metadata_validation_recipe.md",
                  "scripts/ml/validate_metadata.py",),
        predicate=scanner_metadata_validated,
        notes="Was ENVIRONMENT_BLOCKED, and should not have been. The blocker "
              "was a pip install failing inside a container, generalised into "
              "a claim about the host -- which reaches PyPI fine. Answered by "
              "the genuine library rather than by widening the stub: "
              "VALIDATED_MATCH. The predicate is digest-bound, so replacing "
              "the model reopens the question instead of inheriting a verdict "
              "earned by a different artefact.",
    ),
    Row(
        item="scanner-pipeline-location",
        state="OPERATOR_DECISION_REQUIRED",
        authority=OPERATOR,
        evidence=("core/ml/SCANNER_PROVENANCE.md",),
        closure=operator_decision_recorded("scanner-pipeline-location"),
        no_local_predicate="Where a 2 GB unversioned recovered pipeline should "
                           "live is a decision about external storage this "
                           "worktree does not own.",
    ),
    Row(
        item="production-image-collection",
        state="DISABLED",
        authority=SOURCE,
        evidence=("mobile/lib/", "functions/src/"),
        predicate=production_image_collection_disabled,
        notes="D3 itself is a decision that was taken and is history. What can "
              "still regress is this invariant, so this row tracks the "
              "invariant rather than the decision -- and it is source-provable, "
              "which the decision is not. Recording it as an OPERATOR row "
              "would have demanded a closure artefact for something the tree "
              "proves on every run.",
    ),
    Row(
        item="gym-webhook-disclosure",
        state="CLOSED",
        authority=OPERATOR,
        evidence=("core/decisions/gym-webhook-disclosure.md",
                  "core/review/N04_EQUIPMENT_REPORT_AUTHORITY.md",
                  "scripts/legal/legal_text.py",
                  "mobile/lib/l10n/app_en.arb",
                  "mobile/lib/l10n/app_ru.arb",
                  "public/privacy.html",
                  "functions/src/index.ts",),
        invariant=gym_webhook_disclosure_stays_honest,
        closure=operator_decision_recorded("gym-webhook-disclosure"),
        no_local_predicate="Whether a gym's maintenance endpoint is a disclosed "
                           "processor is a privacy-policy question. Engineering "
                           "can remove the dispatch or amend the copy; it "
                           "cannot decide which is the product's position.",
        notes="Surfaced while deciding N-04, not by asking N-04's question. "
              "Closed 2026-08-21 (core/decisions/gym-webhook-disclosure.md): the "
              "operator chose to disclose rather than remove the dispatch, "
              "surfaced while porting Gate F (MRD-02) onto master -- Gate F is "
              "the first client code to ever supply a real gymId on a report, "
              "which is what turns the previously-unreachable webhook dispatch "
              "reachable. `legal_text.py` (the single source for the .arb "
              "bodies and public/privacy.html) now names the gym as a "
              "conditional third recipient -- not a GDPR processor, since no "
              "controller-processor agreement governs it.",
    ),
    Row(
        item="roboflow-key-reissue",
        state="OPERATOR_DECISION_REQUIRED",
        authority=OPERATOR,
        evidence=("core/plans/B5_DATA_SOURCES_2026-08-07.md",),
        invariant=roboflow_key_not_committed,
        closure=operator_decision_recorded("roboflow-key-reissue"),
        no_local_predicate="Reissuing an API key is an action in the Roboflow "
                           "console. Nothing here can perform it, and nothing "
                           "here can observe whether it was performed.",
        notes="Stated precisely, because the loose version would be false: NO "
              "key literal is committed to this repository, at HEAD or "
              "anywhere in history. What exists is a 2026-08-07 planning "
              "document recording that the key was pasted into a CONVERSATION "
              "and recommending reissue, with no record of the reissue. The "
              "invariant guards the half this tree can answer.",
    ),
)


# ---------------------------------------------------------------- the checker

@dataclass
class Finding:
    item: str
    kind: str
    detail: str


@dataclass
class Result:
    findings: list[Finding] = field(default_factory=list)
    checked: list[tuple[str, str, str]] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.findings


def source_rows() -> tuple[Row, ...]:
    return tuple(r for r in LEDGER if r.authority == SOURCE)


def _safe(result: "Result", row: "Row", what: str, fn):
    """Run one row's callable, turning a crash into a finding.

    Without this the sweep aborts at the first deleted file or missing ML
    dependency, every later row goes silently unevaluated, and the operator
    reads a traceback instead of a finding list -- a checker that fails to
    check while looking like it merely errored.
    """
    try:
        return (fn(),)
    except Exception as exc:  # noqa: BLE001 -- any failure is a finding
        result.findings.append(Finding(
            row.item, "PREDICATE_ERROR",
            f"{what} raised {type(exc).__name__}: {exc}",
        ))
        return None


def check() -> Result:
    result = Result()

    # A ledger that tracks nothing passes every check it contains. Empty is the
    # defect, not a vacuous pass -- so it is stated before anything is iterated.
    if not LEDGER:
        result.findings.append(Finding("<ledger>", "EMPTY", "the ledger is empty"))
        return result
    if not source_rows():
        result.findings.append(Finding(
            "<ledger>", "EMPTY",
            "no source-provable rows: every state would be self-asserted",
        ))
        return result

    seen: set[str] = set()
    for row in LEDGER:
        if row.item in seen:
            result.findings.append(
                Finding(row.item, "DUPLICATE", "item appears twice")
            )
        seen.add(row.item)

        if row.authority not in AUTHORITIES:
            result.findings.append(Finding(
                row.item, "BAD_AUTHORITY", f"unknown authority {row.authority!r}"
            ))
            continue

        # -- structural rules about the row itself -------------------------
        if row.authority == SOURCE:
            if row.predicate is None:
                result.findings.append(Finding(
                    row.item, "NO_PREDICATE",
                    "a SOURCE row must recompute its own state",
                ))
                continue
            if row.no_local_predicate:
                result.findings.append(Finding(
                    row.item, "CONTRADICTION",
                    "a SOURCE row cannot also claim no local predicate exists",
                ))
        else:
            if row.predicate is not None:
                result.findings.append(Finding(
                    row.item, "SOURCE_OVERREACH",
                    f"{row.authority} state cannot be computed from this tree",
                ))
            if row.invariant is None and not row.no_local_predicate:
                result.findings.append(Finding(
                    row.item, "UNEXPLAINED",
                    "no invariant and no stated reason one cannot exist",
                ))

        if row.state not in STATES:
            result.findings.append(Finding(
                row.item, "UNKNOWN_STATE",
                f"{row.state!r} is not in the vocabulary, so no rule about "
                "closure or openness could be applied to it",
            ))

        # -- the state itself ----------------------------------------------
        if row.predicate is not None:
            outcome = _safe(result, row, "predicate", row.predicate)
            # A crashing stage must not skip the ones after it. The first
            # version `continue`d here and after the invariant, and the
            # closure drill caught what that costs: pointing REPO at a
            # fixture tree made `n07_still_dormant` raise on a missing file,
            # the row bailed out, and the AUTHORITY_SPOKE check below never
            # ran at all. A checker that stops checking on the first error,
            # while still reporting the rows it did reach, is the quiet
            # half-coverage this whole module exists to prevent.
            if outcome is not None:
                computed, detail = outcome[0]
                if computed != row.state:
                    kind = ("STALE" if row.state not in TERMINAL_STATES
                            and computed in TERMINAL_STATES else "FALSE_STATE")
                    result.findings.append(Finding(
                        row.item, kind,
                        f"recorded {row.state}, source says {computed} "
                        f"-- {detail}",
                    ))
                result.checked.append((row.item, computed, detail))

        for cited in row.evidence:
            if not (REPO / cited).exists():
                result.findings.append(Finding(
                    row.item, "EVIDENCE_MISSING",
                    f"cited evidence {cited} does not exist",
                ))

        intact, detail = quoted_source_intact(row)
        if not intact:
            result.findings.append(Finding(row.item, "QUOTE_STALE", detail))

        if row.invariant is not None:
            outcome = _safe(result, row, "invariant", row.invariant)
            if outcome is not None:
                holds, detail = outcome[0]
                if not holds:
                    result.findings.append(Finding(
                        row.item, "PREMISE_BROKEN",
                        f"{row.state} rests on a condition that no longer "
                        f"holds -- {detail}",
                    ))
                result.checked.append(
                    (row.item, f"invariant:{holds}", detail))

        # -- the closing authority, in BOTH directions ----------------------
        #
        # The first version gated this whole block on `row.state in
        # TERMINAL_STATES`, which meant `closure()` was only ever consulted on
        # a row that ALREADY claimed to be closed. A reviewer traced the
        # consequence and it is the module's own founding defect, reproduced in
        # the rows it claims to guard most carefully: when the clinician
        # actually returns the review, `D1` goes on saying
        # EXTERNAL_AUTHORITY_REQUIRED forever and nothing objects. `D1` in fact
        # executed ZERO assertions -- no predicate, no invariant, and a closure
        # check that could not fire.
        #
        # So closure is evaluated on every row that has one, and disagreement
        # is a finding in whichever direction it points.
        if row.authority != SOURCE and needs_closure(row.state):
            if row.closure is None:
                result.findings.append(Finding(
                    row.item, "UNAUTHORISED_CLOSURE",
                    f"{row.authority} row is {row.state} with no closure "
                    "authority defined",
                ))
        if row.closure is not None:
            outcome = _safe(result, row, "closure", row.closure)
            if outcome is not None:
                spoken, detail = outcome[0]
                if needs_closure(row.state) and not spoken:
                    result.findings.append(Finding(
                        row.item, "UNAUTHORISED_CLOSURE",
                        f"{row.state} without {row.authority} authority "
                        f"-- {detail}",
                    ))
                elif not needs_closure(row.state) and spoken:
                    result.findings.append(Finding(
                        row.item, "AUTHORITY_SPOKE",
                        f"the {row.authority} authority has acted, and this "
                        f"row still says {row.state} -- {detail}. Restate it; "
                        "a row claiming work remains after it was done is the "
                        "exact failure this ledger exists to catch.",
                    ))
                result.checked.append((row.item, f"closure:{spoken}", detail))

    for item, where in sorted(untracked_residuals().items()):
        result.findings.append(Finding(
            item, "UNTRACKED_RESIDUAL",
            f"prose in {where} marks RESIDUAL[{item}], which no ledger row "
            "tracks. Either add the row or, if the sentence is historical "
            "narration rather than outstanding work, drop the marker.",
        ))

    # And the opposite failure, which is the one that would actually have
    # happened. Every live marker describes work that becomes due AFTER the
    # operator decides -- "a rider on the decision rather than work due now".
    # The moment that decision is recorded, `AUTHORITY_SPOKE` fires, the row is
    # restated to a terminal state, and until now the marker naming it went
    # silent for ever: the residual survived the closure of the row that gated
    # it, with nothing to announce that it had just come due. A tracked marker
    # that disappears at exactly the moment it matters is worse than no marker,
    # because the convention teaches people it is being watched.
    states = {r.item: r.state for r in LEDGER}
    for item, where in sorted(residual_markers().items()):
        if needs_closure(states.get(item, "")):
            result.findings.append(Finding(
                item, "RESIDUAL_NOW_DUE",
                f"{item} is {states[item]} -- its authority has spoken -- and "
                f"prose in {where} marks RESIDUAL[{item}] as work that becomes "
                "due once it is decided. That work is now due. Do it, or drop "
                "the marker if the decision made it moot.",
            ))
    return result


# --------------------------------------------------------------- the report

def render() -> str:
    """The human-readable table, generated so it cannot be edited into a lie."""
    lines = [
        "# Current state",
        "",
        "**Generated by `python scripts/review/state_ledger.py --report`. Do not",
        "edit this file.** `scripts/review/test_state_ledger.py` regenerates it and",
        "compares byte for byte, so an edit here is a test failure, not a record.",
        "",
        "A row whose authority is `SOURCE` does not have a state of its own: the",
        "predicate recomputes it from the tree on every run and the recorded word",
        "is only ever the thing being checked.",
        "",
        "## What the closure checks do and do not prove",
        "",
        "An earlier version of this page told the reader that a row owned by an",
        "external or operator authority *cannot be closed from this repository at",
        "all*. That was false, and false in the worst direction: it promised",
        "tamper-resistance that does not exist. Both closure artefacts -- a",
        "clinical `submission.json` and a record under `core/decisions/` -- are",
        "ordinary files inside this worktree, writable by anyone or anything with",
        "commit access. No artefact inside a tree that engineering can write will",
        "ever prove that somebody outside the tree acted.",
        "",
        "What the checks actually buy is narrower and still worth having: closing",
        "one of these rows takes a deliberate, separately reviewable edit that",
        "names the authority it is claiming, instead of a single word changed in a",
        "table. The goal is **legibility of forgery in the diff**, not prevention.",
        "A reader deciding how much to trust a closed row should read the commit",
        "that closed it.",
        "",
        "| Item | State | Authority | Evidence |",
        "| --- | --- | --- | --- |",
    ]
    for row in LEDGER:
        lines.append(
            f"| `{row.item}` | **{row.state}** | {row.authority} | "
            f"{', '.join(row.evidence)} |"
        )
    lines += ["", "## What each row rests on", ""]
    for row in LEDGER:
        lines.append(f"### `{row.item}` — {row.state}")
        lines.append("")
        if row.predicate is not None:
            lines.append(
                "State is **recomputed** from source on every check; the word "
                "above is compared, never trusted."
            )
        if row.no_local_predicate:
            lines.append(f"**No local predicate.** {row.no_local_predicate}")
        if row.invariant is not None:
            lines.append(
                "Carries an invariant: source cannot close this row, but it can "
                "reopen the question."
            )
        if row.closure is not None:
            lines.append(
                f"Closing it requires a named artefact from the {row.authority} "
                "authority. **That artefact is repo-writable**, so this check "
                "does not make forgery impossible -- it makes forgery legible "
                "in a diff. See the honesty note at the top."
            )
        if row.notes:
            lines.append("")
            lines.append(row.notes)
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true",
                    help="reconcile every row against source; non-zero on drift")
    ap.add_argument("--report", action="store_true",
                    help="write core/CURRENT_STATE.md from the ledger")
    args = ap.parse_args(argv)

    if args.report:
        # Reconcile first, and refuse to write on findings. Writing an
        # unreconciled document would publish states that no run ever
        # verified, with nothing in the artefact to distinguish it from a
        # verified one -- which is the drift this file is supposed to end.
        result = check()
        if not result.ok:
            for f in result.findings:
                print(f"  FAIL {f.item} [{f.kind}] {f.detail}")
            print("\nRefusing to regenerate the document while the ledger "
                  "disagrees with the tree. Fix the disagreement first.")
            return 1
        CURRENT_STATE_DOC.write_text(render(), encoding="utf-8")
        print(f"wrote {CURRENT_STATE_DOC.relative_to(REPO).as_posix()}")
        return 0

    result = check()
    for item, state, detail in result.checked:
        print(f"  ok   {item}: {state} -- {detail}")
    if result.ok:
        print(f"\n{len(LEDGER)} rows reconciled, "
              f"{len(source_rows())} of them source-provable.")
        return 0
    print("")
    for f in result.findings:
        print(f"  FAIL {f.item} [{f.kind}] {f.detail}")
    print(f"\n{len(result.findings)} finding(s). The ledger disagrees with the "
          "tree; one of them is wrong.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
