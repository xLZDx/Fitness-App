# -*- coding: utf-8 -*-
"""What the state ledger must refuse.

    python -m pytest scripts/review/test_state_ledger.py -q

The checker's job is adversarial, so most of these tests break something on
purpose and assert that it is caught. Tests that only confirm the green tree is
green would pass just as happily against a checker that returned success
unconditionally.
"""
from __future__ import annotations

import json
import sys
from dataclasses import replace
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import state_ledger as sl  # noqa: E402


# ------------------------------------------------------------- the live tree

def test_the_ledger_reconciles_against_the_current_tree():
    result = sl.check()
    assert result.ok, [f"{f.item} [{f.kind}] {f.detail}" for f in result.findings]


def test_the_generated_document_is_current():
    """The whole point. `core/CURRENT_STATE.md` cannot be edited into a lie,
    because the only accepted content is what the ledger produces."""
    on_disk = sl.CURRENT_STATE_DOC.read_text(encoding="utf-8")
    assert on_disk == sl.render(), (
        "core/CURRENT_STATE.md is stale or hand-edited. Regenerate it with "
        "`python scripts/review/state_ledger.py --report`."
    )


def test_every_row_is_reachable_and_distinct():
    items = [r.item for r in sl.LEDGER]
    assert items, "the ledger is empty"
    assert len(items) == len(set(items)), "duplicate item ids"
    # Not a hand-maintained count: the assertion is that the ledger covers the
    # boundary items the reconciliation sweep identified, by name.
    required = {
        "F-prefetch", "F2", "F5", "checkout-copy", "metric-provenance-six",
        "N-05", "N-07", "D1", "H3", "CT1-human-labels", "scanner-metadata",
        "scanner-pipeline-location", "production-image-collection",
        "guest-upgrade-outcome", "scanner-dependency-pin",
    }
    assert required <= set(items), f"untracked boundary items: {required - set(items)}"


def test_source_rows_exist_and_carry_predicates():
    rows = sl.source_rows()
    assert rows, "no source-provable rows: every state would be self-asserted"
    for row in rows:
        assert row.predicate is not None, row.item
        assert not row.no_local_predicate, row.item


def test_non_source_rows_cannot_carry_a_source_predicate():
    for row in sl.LEDGER:
        if row.authority != sl.SOURCE:
            assert row.predicate is None, (
                f"{row.item}: {row.authority} state must not be computed here"
            )


def test_every_non_source_row_explains_itself():
    for row in sl.LEDGER:
        if row.authority != sl.SOURCE:
            assert row.invariant is not None or row.no_local_predicate, row.item


# ------------------------------------------------------- attack: stale OPEN

def _swap(item: str, **changes):
    """The ledger with one row replaced. Frozen rows, so this cannot leak."""
    return tuple(
        replace(r, **changes) if r.item == item else r for r in sl.LEDGER
    )


@pytest.fixture
def ledger(monkeypatch):
    def install(rows):
        monkeypatch.setattr(sl, "LEDGER", rows)
    return install


def test_a_stale_open_is_caught(ledger):
    """Attack A. The exact defect the module was built for: the replacement
    implementation is present and correct, and the row still says OPEN."""
    ledger(_swap("F-prefetch", state="OPEN"))
    result = sl.check()
    assert not result.ok
    stale = [f for f in result.findings if f.item == "F-prefetch"]
    assert stale and stale[0].kind == "STALE", result.findings
    assert "source says CLOSED" in stale[0].detail


def test_a_false_closed_is_caught(ledger, monkeypatch):
    """Attack B. The row says CLOSED and the load-bearing evidence is gone."""
    monkeypatch.setattr(
        sl, "f_prefetch", lambda: ("OPEN", "replacement removed")
    )
    ledger(_swap("F-prefetch", predicate=sl.f_prefetch))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "F-prefetch"]
    assert bad and bad[0].kind == "FALSE_STATE", result.findings


def test_an_empty_ledger_fails(ledger):
    """Attack C. A ledger tracking nothing satisfies every rule it contains."""
    ledger(())
    result = sl.check()
    assert not result.ok
    assert result.findings[0].kind == "EMPTY"


def test_a_ledger_with_no_source_rows_fails(ledger):
    """The subtler half of attack C: rows remain, but every state is now
    self-asserted because nothing recomputes anything."""
    ledger(tuple(r for r in sl.LEDGER if r.authority != sl.SOURCE))
    result = sl.check()
    assert not result.ok
    assert result.findings[0].kind == "EMPTY"


# ------------------------------- attack: authority that was never exercised

def test_external_authority_cannot_be_declared_from_here(ledger):
    """Attack D. D1 marked CLOSED while the submission is still a blank
    template. No amount of local engineering may produce this transition."""
    ledger(_swap("D1", state="CLOSED"))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "D1"]
    assert bad and bad[0].kind == "UNAUTHORISED_CLOSURE", result.findings
    # The detail must show the REPOSITORY'S OWN clinical validator refusing,
    # not a re-implementation. A ledger that accepts a submission
    # `clinical_import` rejects would close D1 on evidence the importer
    # refuses.
    assert "clinical validator refuses it" in bad[0].detail


def test_operator_authority_cannot_be_declared_from_here(ledger):
    """Attack E. N-05 marked CLOSED with no operator decision record."""
    ledger(_swap("N-05", state="CLOSED"))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "N-05"]
    assert bad and bad[0].kind == "UNAUTHORISED_CLOSURE", result.findings


def test_closure_without_any_authority_defined_is_refused(ledger):
    """The loophole the two attacks above would otherwise leave: delete the
    closure check and the terminal state becomes free."""
    ledger(_swap("D1", state="CLOSED", closure=None))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "D1"]
    assert bad and bad[0].kind == "UNAUTHORISED_CLOSURE", result.findings


def test_a_source_predicate_cannot_be_attached_to_an_external_row(ledger):
    """The laundering route: give D1 a local predicate and let the tree answer
    a clinical question."""
    ledger(_swap("D1", predicate=lambda: ("CLOSED", "the tree says so")))
    result = sl.check()
    assert not result.ok
    kinds = {f.kind for f in result.findings if f.item == "D1"}
    assert "SOURCE_OVERREACH" in kinds, result.findings


# ------------------------------- attack: the row's own prose drifts instead

def test_a_quotation_its_source_no_longer_contains_is_caught(ledger):
    """The finding that produced this check: `notes` was free paraphrase of
    documents that own the narrative, verified by nothing -- a hand-maintained
    status table inside the module built to abolish hand-maintained status
    tables. A row may now only quote, and the quote is checked."""
    ledger(_swap("N-05", quote=("core/review/N05_DISPOSITION.md",
                                "a sentence that document does not contain")))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "N-05"]
    assert bad and bad[0].kind == "QUOTE_STALE", result.findings


def test_a_quotation_from_a_deleted_document_is_caught(ledger):
    ledger(_swap("N-05", quote=("core/review/GONE.md", "anything")))
    result = sl.check()
    assert not result.ok
    assert [f for f in result.findings if f.kind == "QUOTE_STALE"]


def test_every_quotation_currently_resolves():
    """Non-vacuous by construction: assert some row actually quotes something,
    so this cannot pass by there being nothing to check."""
    quoted = [r for r in sl.LEDGER if r.quote is not None]
    assert quoted, "no row quotes its owning document"
    for row in quoted:
        ok, detail = sl.quoted_source_intact(row)
        assert ok, f"{row.item}: {detail}"


def test_cited_evidence_that_does_not_exist_is_caught(ledger):
    ledger(_swap("F2", evidence=("mobile/lib/features/nowhere.dart",)))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "F2"]
    assert bad and bad[0].kind == "EVIDENCE_MISSING", result.findings


def test_every_row_cites_at_least_one_path_and_all_of_them_exist():
    for row in sl.LEDGER:
        assert row.evidence, f"{row.item} cites no evidence at all"
        for cited in row.evidence:
            assert (sl.REPO / cited).exists(), f"{row.item}: {cited}"


# ------------------------------------------ attack: metric claim relabelled

def test_a_dormant_metric_claim_cannot_be_relabelled(ledger, monkeypatch):
    """Attack F. One of the six declared MATCHES without source equivalence.
    The count is recomputed from the locator, so the relabelling shows up as a
    changed count rather than as a document that says something new."""
    monkeypatch.setattr(sl, "metric_provenance_six",
                        lambda: ("EXECUTABLE_ENGINEERING_WORK",
                                 "NOT_LOCATABLE=5 (expected 6)"))
    ledger(_swap("metric-provenance-six", predicate=sl.metric_provenance_six))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "metric-provenance-six"]
    assert bad and bad[0].kind == "FALSE_STATE", result.findings


def test_the_metric_predicate_reads_the_real_locator():
    """Compared against an independently computed audit, not parsed from the
    predicate's own sentence.

    The first version asserted `"NOT_LOCATABLE=6" in detail` and that the
    trailing number parsed. A mutation replacing the whole body with a
    hard-coded string containing those substrings SURVIVED it -- the test
    proved a string was well-formed, which is precisely the failure it claimed
    in its own docstring to be guarding against.
    """
    sys.path.insert(0, str(sl.REPO / "scripts" / "ml"))
    import evaluation_report

    truth = evaluation_report.audit()

    # Comparing numbers is not enough on its own: a body replaced by a
    # hard-coded string carrying today's true counts SURVIVED that version of
    # this test, because the constant and the measurement agreed. So watch
    # that the locator is actually reached.
    calls = []
    real = evaluation_report.audit
    evaluation_report.audit = lambda *a, **k: (calls.append(1), real(*a, **k))[1]
    try:
        state, detail = sl.metric_provenance_six()
    finally:
        evaluation_report.audit = real
    assert calls, "the predicate returned without consulting the locator"
    assert state == "DORMANT"
    # Every number in the sentence must equal one the locator just produced.
    assert f"NOT_LOCATABLE={truth['counts']['NOT_LOCATABLE']}" in detail
    assert f"DRIFTED={truth['counts']['DRIFTED']}" in detail
    assert f"SOURCE_MISSING={truth['counts']['SOURCE_MISSING']}" in detail
    assert f"total claims={truth['claims']}" in detail
    assert truth["claims"] > 6, "fewer claims than the six dormant ones"


# ---------------------------------------- attack: premise quietly withdrawn

def test_a_broken_premise_reopens_an_operator_row(ledger, monkeypatch):
    """Source may not close N-05, but it must be able to reopen the question.
    If the published deletion promise changed, the conflict N-05 rests on may
    no longer exist and the operator is being asked the wrong question."""
    monkeypatch.setattr(sl, "n05_premise_holds",
                        lambda: (False, "the deletion promise changed"))
    ledger(_swap("N-05", invariant=sl.n05_premise_holds))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "N-05"]
    assert bad and bad[0].kind == "PREMISE_BROKEN", result.findings


def test_a_wired_team_route_is_caught(ledger, monkeypatch):
    """N-07's dormancy is the absence of a caller. Wiring one does not make the
    feature ready; it makes the recorded state wrong."""
    monkeypatch.setattr(sl, "n07_still_dormant",
                        lambda: (False, "navigations from lib/: ['a.dart']"))
    ledger(_swap("N-07", invariant=sl.n07_still_dormant))
    result = sl.check()
    assert not result.ok
    assert [f for f in result.findings if f.kind == "PREMISE_BROKEN"]


# ----------------------------------------- the predicates, against real code

def test_predicates_are_not_satisfied_by_prose():
    """Every predicate that watches for a construct must ignore a comment
    quoting it. This is not hypothetical: the first version of the image
    predicate reported `programme_specs.dart` because a comment used the word
    `training`, and the first version of the checkout predicate reported the
    Stripe service because a comment quotes the wrapper it removed."""
    body = "\n".join([
        "  Future<void> startFreeTrial(SubscriptionTier tier) async {",
        "    // this used to be `throw StripeCheckoutException('x')`",
        "    await _call();",
        "  }",
    ])
    trial = sl._without_comments(sl._member_body(body, "Future<void> startFreeTrial("))
    assert trial, "the method body was not located"
    assert "StripeCheckoutException" not in trial


def test_a_commented_navigation_does_not_end_dormancy(monkeypatch):
    """Found by mutation, not by review. The first version of the dormancy
    predicate was killed by inserting `// context.go('/team/1')` as a COMMENT,
    which would have reported a documented example as a wired route. A real
    navigation must still be caught; a mention of one must not."""
    router = "mobile/lib/core/router/app_router.dart"
    real = {router: "onExit: (c, s) { c.go('/team/1'); }, path: '/team/:teamId',"}
    prose = {router: "// c.go('/team/1') is what activation would look like\n"
                     "path: '/team/:teamId',"}

    monkeypatch.setattr(sl, "_dart_sources", lambda: prose)
    assert sl.n07_still_dormant()[0], "a comment was mistaken for a caller"

    monkeypatch.setattr(sl, "_dart_sources", lambda: real)
    assert not sl.n07_still_dormant()[0], "a real navigation went unnoticed"


def test_member_body_stops_at_its_own_closing_brace():
    body = "\n".join([
        "  void a() {",
        "    if (x) { y(); }",
        "  }",
        "  void b() { forbidden(); }",
    ])
    sliced = sl._member_body(body, "void a(")
    assert "y();" in sliced
    assert "forbidden" not in sliced, "the slice ran past its own method"


def test_symbol_absence_is_word_bounded():
    ok, detail = sl._symbol_absent("resolveAll")
    assert ok, detail
    # The symbol that replaced it is present, and must not be mistaken for it.
    assert not sl._symbol_absent("resolveBatch")[0]


def test_human_label_count_reports_a_denominator(tmp_path, monkeypatch):
    """Zero from a scan that visited nothing is not evidence of zero.

    The first version returned `HUMAN_REVIEW_LABELS = 0` whether it had read
    eleven files or none, so renaming the directory produced the reassuring
    answer. It also watched only `core/ml/review/` -- the batches sent OUT --
    while `human_eval.py --out` defaults to `core/ml/datasets/`, which is where
    a returned label actually lands. A guard aimed at the wrong surface is
    worse than an untested one: it reports zero forever.
    """
    ok, detail = sl.human_labels_are_zero()
    assert ok, detail
    scanned = int(detail.split(" of ")[1].split(" files")[0])
    assert scanned > 0, "the scan visited no files, so its zero means nothing"

    # A label appearing in EITHER root must break it.
    for root in sl.HUMAN_LABEL_ROOTS:
        d = tmp_path / root
        d.mkdir(parents=True)
        (d / "returned.json").write_text(
            '{"source": "HUMAN_REVIEWED_QA_LABEL"}', encoding="utf-8"
        )
        monkeypatch.setattr(sl, "REPO", tmp_path)
        broken, detail = sl.human_labels_are_zero()
        assert not broken, f"a human label under {root} went unnoticed"
        assert "HUMAN_REVIEW_LABELS = 1" in detail
        monkeypatch.undo()
        (d / "returned.json").unlink()


def test_the_ct1_closure_is_not_the_clinical_one():
    """Content review and clinical review are different authorities, and this
    repository separates them deliberately -- `review_import.py` refuses to ask
    whether an exercise is safe. Pointing both rows at one closure callable
    would merge them inside the mechanism built to keep them apart."""
    ct1 = next(r for r in sl.LEDGER if r.item == "CT1-human-labels")
    d1 = next(r for r in sl.LEDGER if r.item == "D1")
    assert ct1.closure is not d1.closure
    assert ct1.closure is sl.human_qa_labels_returned


def test_the_clinical_submission_is_still_an_unfilled_template():
    """If this ever fails, a clinician has returned work and D1 changes -- by
    that authority, not by this one."""
    spoken, detail = sl.clinical_authority_returned()
    assert not spoken, detail
    assert "clinical validator refuses it" in detail


# --------------------------------------------- attack: the authority itself

#: Pinned per item, not derived. Two structural rules in `check()` filter on
#: `authority != SOURCE`, so an authority flip escapes both: relabel `D1` as
#: SOURCE, drop its `no_local_predicate`, attach a lambda returning its current
#: state, regenerate the document, and the whole suite goes green with a
#: clinical row answered by the tree. That is the laundering route the module's
#: own docstring calls worse than no check at all, and only naming the expected
#: authority closes it.
EXPECTED_AUTHORITY = {
    "F-prefetch": sl.SOURCE,
    "F2": sl.SOURCE,
    "F5": sl.SOURCE,
    "checkout-copy": sl.SOURCE,
    "metric-provenance-six": sl.SOURCE,
    "production-image-collection": sl.SOURCE,
    "guest-upgrade-outcome": sl.SOURCE,
    "scanner-dependency-pin": sl.SOURCE,
    "N-05": sl.OPERATOR,
    "N-07": sl.OPERATOR,
    "scanner-pipeline-location": sl.OPERATOR,
    "D1": sl.EXTERNAL,
    "H3": sl.EXTERNAL,
    "CT1-human-labels": sl.EXTERNAL,
    "scanner-metadata": sl.ENVIRONMENT,
}


def test_no_row_may_change_the_authority_that_owns_it():
    actual = {r.item: r.authority for r in sl.LEDGER}
    assert actual == EXPECTED_AUTHORITY, (
        "an item's owning authority changed. That is not a refactor: moving a "
        "row to SOURCE lets this repository answer a question it has no "
        "standing to answer."
    )


def test_at_least_one_row_of_each_non_source_authority_exists():
    """Non-vacuity for the two structural loops that filter on non-SOURCE."""
    present = {r.authority for r in sl.LEDGER}
    for authority in (sl.EXTERNAL, sl.OPERATOR, sl.ENVIRONMENT):
        assert authority in present, f"no {authority} row left to check"


def test_the_state_vocabulary_is_closed(ledger):
    """`row.state` was a free string, so any word outside the terminal tuple
    was non-terminal by default and walked past the closure gate. `RESOLVED`
    on an operator row read as finished to a human and as open to the check."""
    ledger(_swap("N-05", state="RESOLVED"))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "N-05"]
    assert bad and bad[0].kind == "UNKNOWN_STATE", result.findings


def test_the_states_that_need_closure_are_pinned():
    """Pinned, not derived.

    The first attempt parametrised over `sl.TERMINAL_STATES +
    sl.SETTLED_STATES` -- and shrinking `TERMINAL_STATES` to `("CLOSED",)`
    still passed, because removing a word from the tuple simply removed the
    case that tested it. A guard whose subject list comes from the thing it
    guards shrinks silently to nothing. The words are therefore written out
    here, where deleting one is a failure rather than one fewer test.
    """
    assert set(sl.TERMINAL_STATES) == {"CLOSED", "NOT_A_DEFECT"}
    assert set(sl.SETTLED_STATES) == {"SETTLED_BY_DECISION"}
    for state in ("CLOSED", "NOT_A_DEFECT", "SETTLED_BY_DECISION"):
        assert sl.needs_closure(state), state
    for state in sl.OPEN_STATES:
        assert not sl.needs_closure(state), state


@pytest.mark.parametrize("state", ["CLOSED", "NOT_A_DEFECT",
                                   "SETTLED_BY_DECISION"])
def test_every_state_that_needs_closure_actually_demands_it(ledger, state):
    """Parametrised over the real tuples, so a word cannot be quietly dropped.

    `TERMINAL_STATES = ("CLOSED",)` -- removing `NOT_A_DEFECT` -- survived the
    whole suite, because no test had ever used that word. Any non-source row
    could then have been parked in it with no authority at all.
    """
    ledger(_swap("N-05", state=state))
    result = sl.check()
    assert not result.ok, f"{state} escaped the closure gate"
    kinds = {f.kind for f in result.findings if f.item == "N-05"}
    assert "UNAUTHORISED_CLOSURE" in kinds, result.findings


def test_the_open_states_do_not_demand_closure(ledger):
    """The other half: a state that honestly says work remains must not need
    anybody's permission to say so."""
    ledger(_swap("N-05", state="OPERATOR_DECISION_REQUIRED"))
    assert sl.check().ok


def test_a_settled_state_needs_the_same_permission_as_a_closed_one(ledger):
    """The escape, in the form it actually shipped: a word asserting a decision
    was TAKEN, which is semantically closed, sitting outside the terminal set."""
    ledger(_swap("N-07", state="SETTLED_BY_DECISION"))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "N-07"]
    assert bad and bad[0].kind == "UNAUTHORISED_CLOSURE", result.findings


def test_an_authority_that_has_spoken_is_reported(ledger, monkeypatch):
    """The other direction, and the one the first version could not see at all.

    Closure used to be evaluated only on rows that already claimed to be
    closed, so when the clinician finally returns the review, `D1` would go on
    saying EXTERNAL_AUTHORITY_REQUIRED forever with nothing objecting -- this
    module's founding defect, reproduced in the row it guards hardest.
    """
    monkeypatch.setattr(sl, "clinical_authority_returned",
                        lambda: (True, "a credentialled reviewer signed it"))
    ledger(_swap("D1", closure=sl.clinical_authority_returned))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "D1"]
    assert bad and bad[0].kind == "AUTHORITY_SPOKE", result.findings


def test_a_crashing_predicate_becomes_a_finding_not_a_traceback(ledger):
    """Without isolation the sweep aborts at the first deleted file and every
    later row goes silently unevaluated."""
    def boom():
        raise FileNotFoundError("a source file was deleted")

    ledger(_swap("F2", predicate=boom))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "F2"]
    assert bad and bad[0].kind == "PREDICATE_ERROR", result.findings
    # And the sweep must have continued past it.
    assert any(item == "production-image-collection"
               for item, _, _ in result.checked)


# ----------------------------- the predicates, proven in the FAILING direction
#
# Every test above this line proves the CHECKER branches. These prove the
# PREDICATES see damage -- the gap a reviewer identified: with the live tree
# green, a predicate replaced by `return ("CLOSED", "")` passed everything, and
# so did dropping any single conjunct from one.

_GOOD_RESOLVER = """
class ClipBatch {
  const ClipBatch({required this.urls, this.quotaExhausted = false});
  final bool quotaExhausted;
}
abstract class ClipUrlResolver {
  Future<ClipBatch> resolveBatch(Iterable<String> references);
}
"""
_GOOD_OUTCOME = """
enum PrefetchState { nothingScheduled, complete, noneQuota, noneFailed,
  partialQuota, partialFailed }
"""


def _tree(monkeypatch, resolver=_GOOD_RESOLVER, outcome=_GOOD_OUTCOME,
          extra=""):
    files = {
        "mobile/lib/features/equipment/data/clip_url_resolver.dart": resolver,
        "mobile/lib/features/workouts/data/prefetch_outcome.dart": outcome,
    }
    monkeypatch.setattr(
        sl, "_dart_sources", lambda: dict(files, **{"x.dart": extra})
    )
    monkeypatch.setattr(sl, "_read", lambda rel: files.get(rel, ""))


def test_f_prefetch_is_closed_on_a_healthy_synthetic_tree(monkeypatch):
    """The control. Without it the four failure tests below could all be
    passing because the synthetic tree is malformed rather than damaged."""
    _tree(monkeypatch)
    assert sl.f_prefetch()[0] == "CLOSED"


@pytest.mark.parametrize("what,resolver,outcome,extra", [
    ("the old swallowing symbol came back", _GOOD_RESOLVER, _GOOD_OUTCOME,
     "Future<Map<String, String>> resolveAll(Iterable<String> r);"),
    ("the batch type is gone",
     _GOOD_RESOLVER.replace("class ClipBatch", "class ClipThing"),
     _GOOD_OUTCOME, ""),
    ("the quota flag is gone",
     _GOOD_RESOLVER.replace("final bool quotaExhausted;", ""),
     _GOOD_OUTCOME, ""),
    ("the partial-quota state is gone", _GOOD_RESOLVER,
     _GOOD_OUTCOME.replace("partialQuota,", ""), ""),
])
def test_f_prefetch_sees_each_conjunct_removed(monkeypatch, what, resolver,
                                               outcome, extra):
    _tree(monkeypatch, resolver, outcome, extra)
    assert sl.f_prefetch()[0] == "OPEN", what


def test_f2_reads_the_arb_and_not_the_key_name(monkeypatch):
    """The false CLOSED a reviewer found: rename the key to something that no
    longer contains `unavailable`, leave its VALUE as the generic failure
    string, and an identifier check reports the defect as fixed."""
    card = ("VideoFailureReason.quotaExhausted => l10n.clipQuotaReached,\n"
            "VideoFailureReason.linkUnavailable => l10n.clipGenericFault,")
    failure = "enum VideoFailureReason { quotaExhausted, linkUnavailable }"
    generic = "The clip link is unavailable"

    def read(rel, same):
        if rel.endswith("video_failure.dart"):
            return failure
        if rel.endswith("exercise_reference.dart"):
            return card
        return json.dumps({
            "clipQuotaReached": generic if same else "Daily clip limit reached",
            "clipGenericFault": generic,
        })

    monkeypatch.setattr(sl, "_read", lambda rel: read(rel, True))
    assert sl.f2()[0] == "OPEN", (
        "a renamed key pointing at the generic string was reported CLOSED"
    )
    monkeypatch.setattr(sl, "_read", lambda rel: read(rel, False))
    assert sl.f2()[0] == "CLOSED"


@pytest.mark.parametrize("ts,expected", [
    ('sign_in_provider === "anonymous"\n'
     'reason: CHECKOUT_REFUSAL.ANONYMOUS_ACCOUNT', "CLOSED"),
    ('reason: CHECKOUT_REFUSAL.ANONYMOUS_ACCOUNT', "OPEN"),
    ('sign_in_provider === "anonymous"', "OPEN"),
])
def test_f5_needs_both_the_guard_and_the_named_reason(monkeypatch, ts,
                                                      expected):
    monkeypatch.setattr(sl, "_read", lambda rel: ts)
    assert sl.f5()[0] == expected


_GOOD_PAGE = ("Text(checkoutLine(AppLocalizations.of(context), error)),\n"
              "if (CheckoutFailure.of(error).isUnclassified) ...[")
_GOOD_SVC = ("  Future<void> startFreeTrial(SubscriptionTier tier) async {\n"
             "    await _call();\n  }")


@pytest.mark.parametrize("page,svc,expected", [
    (_GOOD_PAGE, _GOOD_SVC, "CLOSED"),
    (_GOOD_PAGE.replace("checkoutLine(AppLocalizations.of(context), error)",
                        "error.toString()"), _GOOD_SVC, "OPEN"),
    (_GOOD_PAGE.replace(
        "if (CheckoutFailure.of(error).isUnclassified) ...[", ""),
     _GOOD_SVC, "OPEN"),
    (_GOOD_PAGE,
     "  Future<void> startFreeTrial(SubscriptionTier tier) async {\n"
     "    throw StripeCheckoutException('wrapped again');\n  }", "OPEN"),
    (_GOOD_PAGE, "nothing resembling the method", "OPEN"),
])
def test_checkout_copy_needs_every_conjunct(monkeypatch, page, svc, expected):
    monkeypatch.setattr(
        sl, "_read",
        lambda rel: page if rel.endswith("subscription_page.dart") else svc,
    )
    assert sl.checkout_copy()[0] == expected


@pytest.mark.parametrize("dart,expected", [
    ("final x = 1;", "DISABLED"),
    ("FirebaseStorage.instance.ref().putData(bytes);", "ENABLED"),
    ("await ref.putFile(f);", "ENABLED"),
    ("UploadTask t;", "ENABLED"),
])
def test_image_collection_watches_machinery(monkeypatch, tmp_path, dart,
                                            expected):
    monkeypatch.setattr(sl, "_dart_sources", lambda: {"a.dart": dart})
    monkeypatch.setattr(sl, "REPO", tmp_path)  # no functions/ tree here
    assert sl.production_image_collection_disabled()[0] == expected


def test_the_n05_premise_is_actually_read(monkeypatch):
    """Untested entirely at first: replacing the body with `return True` left
    the suite green, so nothing proved the published policy was ever opened."""
    monkeypatch.setattr(sl, "_read", lambda rel: "we keep your data forever")
    assert not sl.n05_premise_holds()[0]
    monkeypatch.setattr(
        sl, "_read",
        lambda rel: "It is irreversible: afterwards there is nothing left to "
                    "restore, including for us.",
    )
    assert sl.n05_premise_holds()[0]


def test_the_metadata_tool_being_local_breaks_the_premise(monkeypatch,
                                                          tmp_path):
    monkeypatch.setattr(sl, "REPO", tmp_path)
    assert sl.metadata_tool_is_not_local()[0]
    (tmp_path / "attach_metadata.py").write_text("x", encoding="utf-8")
    assert not sl.metadata_tool_is_not_local()[0]
