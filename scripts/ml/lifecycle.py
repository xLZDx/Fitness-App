# -*- coding: utf-8 -*-
"""ML promotion lifecycle — the transitions that are legal, and the two that are not.

    python scripts/ml/lifecycle.py            # audit the registry
    python -m pytest scripts/ml/test_ml_contracts.py -q

``core/ml/MODEL_REGISTRY.json`` already declares nine lifecycle states, and a
Dart test checks that every model's state is one of the nine. That is
membership, not legality: it cannot tell ``TRAINED`` from ``CHAMPION``, and it
would accept a model that moved from one to the other in a single edit.

## The two implications this exists to deny

    TRAINED     does NOT imply CHALLENGER
    CHALLENGER  does NOT imply CHAMPION

Both are the same mistake at different scales — treating the fact that
something was BUILT as evidence that it is BETTER, and treating the fact that
it is better as authority to SHIP it. The first skips evaluation. The second
skips the promotion decision, which is a human one.

## CT != CD

A continuous-training cycle may legitimately end at ``REJECTED``. That is a
successful cycle, not a failed one: the point of evaluating a challenger is
that it might lose. So no training-side state may carry deployment authority,
and ``assert_no_train_deploy_coupling`` refuses a registry entry that claims
one — a model in a pre-champion state with a live ``deployment_status`` is a
model that shipped without anybody deciding to ship it.

## Two consumers, which is why this is shared rather than CT-1-specific

``content_qa`` (the deterministic CT-1 champion) and ``equipment_recognition``
(the scanner, v1 champion and v2 evaluated-not-shipped) are both in the
registry and both need the same answer to "may this move". A third would not
change the rules.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
REGISTRY = REPO / "core" / "ml" / "MODEL_REGISTRY.json"

#: What may follow what. Read as: from -> the set it may move to.
#:
#: Every edge is here because somebody could argue for it. What is NOT here is
#: the interesting part: there is no edge from TRAINED to anything but
#: EVALUATED or REJECTED, and none from any state directly to CHAMPION except
#: PROMOTION_REVIEW.
TRANSITIONS: dict[str, frozenset[str]] = {
    # Built. Says nothing about quality.
    "TRAINED": frozenset({"EVALUATED", "REJECTED"}),
    # Measured offline against a holdout. Still says nothing about shipping.
    "EVALUATED": frozenset({"CHALLENGER_CANDIDATE", "REJECTED"}),
    # Beat the champion offline by enough to be worth running for real.
    "CHALLENGER_CANDIDATE": frozenset({"SHADOW_READY", "REJECTED"}),
    # Packaged for a shadow run: an artefact exists and is addressable.
    "SHADOW_READY": frozenset({"SHADOW", "REJECTED"}),
    # Running alongside the champion, its output recorded and not used.
    "SHADOW": frozenset({"PROMOTION_REVIEW", "REJECTED"}),
    # A human decision, and the only door to CHAMPION.
    "PROMOTION_REVIEW": frozenset({"CHAMPION", "REJECTED"}),
    # Champions leave by being replaced or withdrawn, never by being promoted.
    "CHAMPION": frozenset({"RETIRED", "REJECTED"}),
    # Terminal-ish. A rejected candidate may be retrained, which produces a NEW
    # version rather than moving this one, so REJECTED goes nowhere.
    "REJECTED": frozenset(),
    "RETIRED": frozenset(),
}

#: States in which a model may be deployed. Exactly one.
#:
#: `SHADOW` is deliberately absent: a shadow model runs, but its output is
#: recorded and discarded, which is not deployment. If shadow running ever
#: needs a deployment_status, it needs its own word for it.
DEPLOYABLE = frozenset({"CHAMPION"})

#: Deployment values that mean "this is live somewhere".
LIVE_DEPLOYMENT = frozenset({"deployed", "live", "production", "shipped", "active"})


class LifecycleError(AssertionError):
    """A model movement that would ship something nobody decided to ship."""


def assert_transition(before: str, after: str) -> None:
    """Refuse an illegal move between lifecycle states."""
    if before not in TRANSITIONS:
        raise LifecycleError(
            f"{before!r} is not a lifecycle state. Known: {sorted(TRANSITIONS)}"
        )
    if after not in TRANSITIONS:
        raise LifecycleError(
            f"{after!r} is not a lifecycle state. Known: {sorted(TRANSITIONS)}"
        )
    if before == after:
        return
    if after not in TRANSITIONS[before]:
        allowed = sorted(TRANSITIONS[before]) or ["nothing -- it is terminal"]
        raise LifecycleError(
            f"{before} -> {after} is not a legal transition. From {before} a "
            f"model may go to: {allowed}. "
            + (
                "Being trained is not evidence of being better; that is what "
                "EVALUATED is for. "
                if before == "TRAINED" else ""
            )
            + (
                "Being better is not authority to ship; that is what "
                "PROMOTION_REVIEW is for, and it is a human decision. "
                if after == "CHAMPION" else ""
            )
        )


def assert_states_declared(registry: dict[str, Any]) -> None:
    """The registry's own declared list and this module must agree.

    If they drift, one of them is enforcing a lifecycle the other does not
    have, and neither reader can tell which.
    """
    declared = set(registry.get("lifecycle_states") or [])
    if declared != set(TRANSITIONS):
        raise LifecycleError(
            "MODEL_REGISTRY.lifecycle_states and lifecycle.TRANSITIONS "
            f"disagree. Only in the registry: {sorted(declared - set(TRANSITIONS))}; "
            f"only here: {sorted(set(TRANSITIONS) - declared)}"
        )


def assert_no_train_deploy_coupling(registry: dict[str, Any]) -> list[str]:
    """CT != CD. Nothing may be live that is not a champion.

    Returns the entries it checked, so "the coupling guard passed" cannot be a
    claim about an empty registry.
    """
    models = registry.get("models") or []
    if not models:
        raise LifecycleError(
            "the registry lists no models. An empty registry satisfies every "
            "check below, which is the failure this returns a count to prevent"
        )
    checked = []
    for m in models:
        name = f"{m.get('model_id')}@{m.get('model_version')}"
        state = m.get("lifecycle_state")
        if state not in TRANSITIONS:
            raise LifecycleError(f"{name}: {state!r} is not a lifecycle state")
        status = str(m.get("deployment_status") or "").lower()
        if status in LIVE_DEPLOYMENT and state not in DEPLOYABLE:
            raise LifecycleError(
                f"{name} is in state {state} and reports deployment_status="
                f"{m.get('deployment_status')!r}. A continuous-training cycle "
                "may end at REJECTED and that is a success; nothing on the "
                "training side carries authority to ship. Only "
                f"{sorted(DEPLOYABLE)} may be live"
            )
        checked.append(name)
    return checked


def audit(registry: dict[str, Any]) -> dict[str, Any]:
    """Everything this module can say about a registry, without changing it."""
    assert_states_declared(registry)
    checked = assert_no_train_deploy_coupling(registry)
    models = registry.get("models") or []
    return {
        "models_checked": checked,
        "by_state": {
            state: sorted(
                f"{m.get('model_id')}@{m.get('model_version')}"
                for m in models if m.get("lifecycle_state") == state
            )
            for state in sorted(TRANSITIONS)
            if any(m.get("lifecycle_state") == state for m in models)
        },
        "champions": sorted(
            f"{m.get('model_id')}@{m.get('model_version')}"
            for m in models if m.get("lifecycle_state") == "CHAMPION"
        ),
        "verdict": "LIFECYCLE_CONSISTENT",
        "scope": (
            "Declared states agree with the transition table, and nothing "
            "outside CHAMPION reports a live deployment. This does NOT verify "
            "that any recorded transition actually happened in the order the "
            "table allows -- the registry stores a current state, not a "
            "history, so a model edited straight from TRAINED to CHAMPION in "
            "one commit is invisible here and visible only in git."
        ),
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--registry", default=str(REGISTRY))
    args = ap.parse_args(argv)
    registry = json.loads(Path(args.registry).read_text(encoding="utf-8"))
    report = audit(registry)
    print(f"{report['verdict']}  {len(report['models_checked'])} models")
    for state, names in report["by_state"].items():
        print(f"  {state:22} {', '.join(names)}")
    print(f"\n  {report['scope']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
