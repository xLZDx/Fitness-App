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
        "N-04-gym-association", "F025",
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
    """Attack E. N-07 marked CLOSED with no operator decision record. (Was
    N-05, then briefly N-04-gym-association, both of which gained real
    decision files on 2026-09-17 and stopped being attacks at all once they
    did -- N-07 has no decision file and is DORMANT, not a terminal state, so
    it still exercises the unauthorised-closure path.)"""
    ledger(_swap("N-07", state="CLOSED"))
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.item == "N-07"]
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
    "N-04-gym-association": sl.OPERATOR,
    "F025": sl.OPERATOR,
    "D1": sl.EXTERNAL,
    "H3": sl.EXTERNAL,
    "CT1-human-labels": sl.EXTERNAL,
    # Moved ENVIRONMENT -> SOURCE on 2026-08-18, deliberately, and this pin is
    # where that had to be argued rather than performed.
    #
    # The move is the one this test exists to make difficult, so: the row asked
    # whether the shipped model's declared min_parser_version matches what the
    # genuine library computes. ENVIRONMENT asserted nobody here could answer
    # it. That was false -- the blocker was a `pip install` failing inside a
    # container, generalised into a claim about the host.
    #
    # It is not laundering, and the reason is reproducibility rather than
    # confidence: the answer is a deterministic computation any reader can
    # repeat in minutes with `scripts/ml/metadata_validation_recipe.md`, and
    # the predicate re-checks nothing except that the recorded answer is still
    # about the artefact on disk. That is the same shape as
    # `scanner_dependency_pin`. A clinical sign-off could never move this way,
    # because no recipe reproduces a named clinician's judgement.
    "scanner-metadata": sl.SOURCE,
    "gym-webhook-disclosure": sl.OPERATOR,
    "roboflow-key-reissue": sl.OPERATOR,
}


def test_no_row_may_change_the_authority_that_owns_it():
    actual = {r.item: r.authority for r in sl.LEDGER}
    assert actual == EXPECTED_AUTHORITY, (
        "an item's owning authority changed. That is not a refactor: moving a "
        "row to SOURCE lets this repository answer a question it has no "
        "standing to answer."
    )


def test_non_source_rows_exist_for_the_structural_loops():
    """Non-vacuity for the two loops in `check()` that filter on non-SOURCE.

    This used to demand one row of EACH non-source authority, ENVIRONMENT
    included. That became wrong when `scanner-metadata` -- the only ENVIRONMENT
    row there has ever been -- turned out not to be environment-blocked at all.
    The loops need non-SOURCE subjects, which EXTERNAL and OPERATOR supply;
    they do not need one of every label.
    """
    present = {r.authority for r in sl.LEDGER}
    assert present <= set(sl.AUTHORITIES), present - set(sl.AUTHORITIES)
    for authority in (sl.EXTERNAL, sl.OPERATOR):
        assert authority in present, f"no {authority} row left to check"
    assert [r for r in sl.LEDGER if r.authority != sl.SOURCE]


def test_the_environment_authority_is_currently_unused_and_that_is_recorded():
    """ENVIRONMENT has no rows, and the distinction from `TEST` matters.

    `TEST` was deleted because `check()` structurally rejected what it meant --
    a constant whose documented meaning the checker refuses is a trap.
    ENVIRONMENT is not that: it is implementable, it was genuinely used, and it
    is empty only because the one item carrying it was measured and found not
    to be blocked. It stays available.

    Pinned so the emptiness is a fact somebody chose rather than one that crept
    in, and so re-populating it is a visible act.
    """
    assert sl.ENVIRONMENT in sl.AUTHORITIES
    assert not [r for r in sl.LEDGER if r.authority == sl.ENVIRONMENT]


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

    Uses N-07 rather than N-05 (used until 2026-09-17) or N-04-gym-association
    (used briefly the same day): both of the latter gained real decision
    files on disk and swapping them to a closed-shaped state with no matching
    authority stopped being an attack -- the file is real, the closure
    genuinely succeeds. N-07 has no decision file (it is DORMANT, deliberately
    left unrecorded per its own row notes), so it still exercises the
    unauthorised-closure path.
    """
    ledger(_swap("N-07", state=state))
    result = sl.check()
    assert not result.ok, f"{state} escaped the closure gate"
    kinds = {f.kind for f in result.findings if f.item == "N-07"}
    assert "UNAUTHORISED_CLOSURE" in kinds, result.findings


def test_the_open_states_do_not_demand_closure(ledger):
    """The other half: a state that honestly says work remains must not need
    anybody's permission to say so. N-07, not N-05 or N-04-gym-association:
    see the note above -- both of those now have real decision files, so
    swapping either back to OPERATOR_DECISION_REQUIRED would itself trip
    AUTHORITY_SPOKE against the genuine file on disk, which is a different
    (and correct) failure, not the one this test is checking."""
    ledger(_swap("N-07", state="OPERATOR_DECISION_REQUIRED"))
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
PrefetchState get state {
  return quotaExhausted
      ? PrefetchState.partialQuota
      : PrefetchState.partialFailed;
}
"""


def _tree(monkeypatch, resolver=_GOOD_RESOLVER, outcome=_GOOD_OUTCOME,
          extra=""):
    files = {
        "mobile/lib/features/equipment/data/clip_url_resolver.dart": resolver,
        "mobile/lib/features/workouts/data/prefetch_outcome.dart": outcome,
        # Added when `f_prefetch` gained the two conjuncts that check the
        # refusal is CARRIED and SHOWN, not merely declared. Without them this
        # helper builds a tree where the wire is missing, and every case below
        # would pass for that reason instead of the one it names.
        "mobile/lib/features/workouts/state/offline_video_providers.dart":
            "return PrefetchOutcome(quotaExhausted: batch.quotaExhausted);",
        "mobile/lib/features/workouts/workouts_page.dart": _ARMS,
        "mobile/lib/l10n/app_en.arb": _PREFETCH_ARB,
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
    card = ("final reason = classifyVideoFailure(error);\n"
            "VideoFailureReason.quotaExhausted => l10n.clipQuotaReached,\n"
            "VideoFailureReason.linkUnavailable => l10n.clipGenericFault,")
    # The classifier line is part of the healthy fixture now: `f2` gained a
    # conjunct requiring that something actually PRODUCES the reason, and
    # without it this test's CLOSED case would fail for that reason rather
    # than proving anything about the ARB.
    failure = ("enum VideoFailureReason { quotaExhausted, linkUnavailable } "
               "if (error is ClipQuotaExhausted) return VideoFailureReason"
               ".quotaExhausted;")
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


_GUARD = ('    if (auth.token?.firebase?.sign_in_provider === "anonymous") {\n'
          '      throw new HttpsError("failed-precondition", "no",\n'
          '        { reason: CHECKOUT_REFUSAL.ANONYMOUS_ACCOUNT });\n'
          '    }\n')


def _index_ts(*, trial: bool = True, paid: bool = True,
              paid_commented: bool = False) -> str:
    """Two handlers, because the whole question is which one holds the guard.

    The previous version of this test passed the predicate a bare fragment
    with no handler in it at all. Every case it asserted was therefore about
    substring presence in a two-line string -- which is precisely the property
    that turned out not to be the one that mattered, and is why a predicate
    that computed CLOSED with F5's defect restored had three green tests
    sitting on top of it.
    """
    paid_guard = _GUARD if paid else ""
    if paid_commented:
        paid_guard = "".join("    // " + ln.lstrip() + "\n"
                            for ln in _GUARD.splitlines())
    return (
        "export const startFreeTrial = onCall(\n"
        "  { ...INTERACTIVE },\n"
        "  async (request) => {\n"
        + (_GUARD if trial else "")
        + "    return grantTrial();\n  },\n);\n\n"
        "export const createCheckoutSession = onCall(\n"
        "  { ...INTERACTIVE, secrets: [STRIPE_SECRET_KEY] },\n"
        "  async (request) => {\n"
        + paid_guard
        + "    return session.url;\n  },\n);\n\n"
        "export const stripeWebhook = onRequest(async (req, res) => {});\n"
    )


@pytest.mark.parametrize("kwargs,expected,why", [
    ({}, "CLOSED", "both handlers guarded is the shipped tree"),
    ({"paid": False}, "OPEN",
     "F5's defect restored: real money, anonymous caller, and the guard the "
     "predicate can still see belongs to the free trial"),
    ({"trial": False}, "CLOSED",
     "F5 is not about startFreeTrial; touching it must not move this row"),
    ({"paid": False, "trial": False}, "OPEN", "neither handler guarded"),
    ({"paid_commented": True}, "OPEN",
     "a commented-out guard refuses nobody"),
])
def test_f5_reads_the_paid_handler_and_not_the_free_one(monkeypatch, kwargs,
                                                        expected, why):
    monkeypatch.setattr(sl, "_read", lambda rel: _index_ts(**kwargs))
    assert sl.f5()[0] == expected, why


def test_f5_fails_closed_when_the_handler_is_renamed(monkeypatch):
    """A predicate that cannot find its subject must not report success.

    `_exported_member` returns "" for an absent signature, and "" contains
    neither substring, so the row computes OPEN. Stated as a test because the
    alternative -- a scoped check that silently degrades to vacuous agreement
    -- is the failure mode scoping was introduced to remove.
    """
    monkeypatch.setattr(
        sl, "_read",
        lambda rel: _index_ts().replace("createCheckoutSession", "startPaidPlan"),
    )
    assert sl.f5()[0] == "OPEN"


def test_the_exported_member_slice_stops_at_the_next_export():
    ts = _index_ts()
    region = sl._exported_member(ts, "export const createCheckoutSession = onCall(")
    assert "grantTrial" not in region, "the slice reached back into startFreeTrial"
    assert "stripeWebhook" not in region, "the slice ran past its own handler"
    assert "session.url" in region


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


def _membership_sources(monkeypatch, *, dart="", ts="", rules=""):
    monkeypatch.setattr(sl, "_dart_sources",
                        lambda: {"mobile/lib/x.dart": dart})
    monkeypatch.setattr(
        sl, "_read",
        lambda rel: {"functions/src/index.ts": ts,
                     "firestore.rules": rules}.get(rel, ""),
    )


def test_nothing_anywhere_is_the_premise_holding(monkeypatch):
    _membership_sources(monkeypatch)
    holds, detail = sl.no_gym_membership_model()
    assert holds
    # The detail has to name every surface searched. A premise guard that says
    # "nothing exists" without saying where it looked is unfalsifiable prose.
    assert "mobile/lib" in detail
    for surface in sl.MEMBERSHIP_SURFACES:
        assert surface in detail


@pytest.mark.parametrize("where,payload", [
    ("dart", "class GymMembership {}"),
    ("dart", "final r = MembershipRepository();"),
    ("ts", "export const joinGym = onCall(INTERACTIVE, async (r) => {});"),
    ("ts", "await db.doc(`memberships/${auth.uid}`).set({});"),
    ("ts", 'db.collection("memberships").doc(uid)'),
    ("rules", "match /memberships/{id} { allow read: if true; }"),
])
def test_a_membership_model_anywhere_breaks_the_premise(monkeypatch, where,
                                                       payload):
    """The server cases are the ones that were invisible.

    `reportEquipment` writes through the Admin SDK, which bypasses
    `firestore.rules` entirely, so a membership that actually BOUND anything
    has to be enforced server-side -- and the original scan read `mobile/lib`
    and nothing else. Measured before the fix: a complete `joinGym` callable
    plus a `memberships/` collection added to `functions/src/index.ts` left the
    invariant returning True, so the operator would have gone on being asked a
    question whose premise had died.
    """
    _membership_sources(monkeypatch, **{where: payload})
    holds, detail = sl.no_gym_membership_model()
    assert not holds, f"a membership model in {where} was not seen"
    assert "now exists" in detail


@pytest.mark.parametrize("where", ["dart", "ts", "rules"])
def test_prose_about_membership_is_not_a_membership_model(monkeypatch, where):
    """Every surface must strip comments, not just the Dart one.

    This document argues about `joinGym` and `memberships/` constantly. A
    guard that fires on the discussion is a guard people switch off.
    """
    _membership_sources(
        monkeypatch,
        **{where: "// joinGym and memberships/ were considered and rejected"},
    )
    assert sl.no_gym_membership_model()[0]


def test_the_membership_surfaces_are_files_that_exist():
    """A surface list that drifts into naming a deleted file searches nothing.

    `_read` returns "" for a missing path, so a typo or a rename would turn a
    conjunct into a permanent True without a single test going red.
    """
    for rel in sl.MEMBERSHIP_SURFACES:
        assert (sl.REPO / rel).exists(), rel
        assert _real_read(rel).strip(), rel


def _real_read(rel):
    return (sl.REPO / rel).read_text(encoding="utf-8", errors="replace")


def test_the_metadata_tool_being_local_breaks_the_premise(monkeypatch,
                                                          tmp_path):
    monkeypatch.setattr(sl, "REPO", tmp_path)
    monkeypatch.setattr(sl.importlib.util, "find_spec", lambda name: None)
    assert sl.metadata_is_still_environment_blocked()[0]
    (tmp_path / "attach_metadata.py").write_text("x", encoding="utf-8")
    assert not sl.metadata_is_still_environment_blocked()[0]


def test_installing_the_genuine_library_breaks_the_premise(monkeypatch,
                                                           tmp_path):
    """The conjunct that will actually fire one day.

    `ENVIRONMENT_BLOCKED` means nobody here can answer the question. Once
    `tflite_support` imports, somebody can -- and the row has to stop saying
    otherwise on its own, because the person who ran `pip install` is not
    thinking about a ledger.
    """
    monkeypatch.setattr(sl, "REPO", tmp_path)
    monkeypatch.setattr(sl.importlib.util, "find_spec", lambda name: object())

    holds, detail = sl.metadata_is_still_environment_blocked()
    assert not holds
    assert "validate_metadata.py" in detail


def test_the_metadata_row_points_at_the_script_that_would_answer_it(monkeypatch):
    """A blocked row that does not say what would unblock it is a dead end."""
    row = next(r for r in sl.LEDGER if r.item == "scanner-metadata")
    assert "scripts/ml/validate_metadata.py" in row.evidence
    assert (sl.REPO / "scripts/ml/validate_metadata.py").exists()


# =========================================================== the closure drill
#
# Every AUTHORITY_SPOKE test above this line replaces the closure callable with
# a lambda. That proves `check()` branches; it does not prove the real closure
# predicates can ever return True, and this repository has already been bitten
# once by exactly that gap -- a mutation restoring the original auth defect
# survived twelve tests because all twelve ran against a mock.
#
# So these drills build REAL artefacts, in a temporary tree, and run the REAL
# closure predicates against them.
#
# Safety, and it is not decoration: no fixture here is ever written under the
# repository. Each one lives in pytest's `tmp_path` with `sl.REPO` repointed at
# it, and each carries FIXTURE in the field a human name would occupy. A fake
# authority artefact committed into the real tree would close a clinical row on
# a reviewer who does not exist, which is the single thing this whole mechanism
# exists to make impossible.

def _fixture_submission():
    """A submission the repository's own clinical validator accepts.

    Built at call time rather than checked in as a file: `catalogue_sha256`
    must match the CURRENT catalogue or `validate` rejects it as stale, and a
    frozen fixture would rot into testing the staleness path instead of the
    acceptance path.
    """
    sys.path.insert(0, str(sl.REPO / "scripts" / "review"))
    import clinical_import as ci

    return {
        "schema_version": ci.SCHEMA_VERSION,
        "handoff_commit": "0" * 40,
        "catalogue_sha256": ci.catalogue_digest(),
        "reviewer_name": "FIXTURE ONLY -- not a real reviewer",
        "reviewer_credentials": "FIXTURE ONLY",
        "reviewer_authority": "FIXTURE ONLY",
        "reviewed_at": "2026-08-18T12:00:00+00:00",
        "rows": [{"item_id": ci._rows()[0]["id"], "disposition": "ACCEPT"}],
    }


def _repo_at(tmp_path, monkeypatch):
    monkeypatch.setattr(sl, "REPO", tmp_path)
    return tmp_path


def test_the_fixture_is_one_the_real_validator_accepts(tmp_path, monkeypatch):
    """The control for the three drills below.

    Without it, each of them could be passing because the fixture is malformed
    in some way that happens to produce the expected finding -- and a drill
    that cannot tell a valid submission from a broken one proves nothing about
    what happens when a real one arrives.
    """
    sub = _fixture_submission()
    worklist = tmp_path / "core" / "review" / "worklist"
    worklist.mkdir(parents=True)
    (worklist / "submission.json").write_text(json.dumps(sub), encoding="utf-8")

    _repo_at(tmp_path, monkeypatch)
    spoken, detail = sl.clinical_authority_returned()
    assert spoken, detail


def test_the_fixture_never_touches_the_real_worklist():
    """The submission in the repository must still be an unfilled template.

    Stated as a test rather than a comment because the failure it guards
    against -- a fixture written to the real path -- would close D1 silently
    and look like ordinary test scaffolding in a diff.
    """
    real = (sl.REPO / "core" / "review" / "worklist" / "submission.json")
    body = json.loads(real.read_text(encoding="utf-8"))
    for field in ("reviewer_name", "reviewer_credentials", "reviewer_authority"):
        assert not str(body.get(field, "")).strip(), (
            f"{field} is filled in the REAL submission. If a clinician truly "
            "returned work this is correct and D1 must be restated; if a test "
            "wrote it, a fictional reviewer is one commit from closing a "
            "clinical row"
        )


def test_a_returned_clinical_review_makes_the_stale_row_fail(tmp_path,
                                                             monkeypatch,
                                                             ledger):
    """D1 says EXTERNAL_AUTHORITY_REQUIRED. The clinician returns. The row is
    now wrong, and nothing about the source tree changed to say so."""
    sub = _fixture_submission()
    worklist = tmp_path / "core" / "review" / "worklist"
    worklist.mkdir(parents=True)
    (worklist / "submission.json").write_text(json.dumps(sub), encoding="utf-8")
    _repo_at(tmp_path, monkeypatch)

    # The ledger is untouched -- D1 still carries its real recorded state.
    result = sl.check()

    spoke = [f for f in result.findings
             if f.item in ("D1", "H3") and f.kind == "AUTHORITY_SPOKE"]
    assert spoke, [f"{f.item} [{f.kind}]" for f in result.findings]
    assert "Restate it" in spoke[0].detail


def test_returned_human_labels_make_the_ct1_row_fail(tmp_path, monkeypatch,
                                                     ledger):
    """CT-1's authority is a returned CONTENT review, and it closes by the
    labels existing -- so the drill is a label file, not a submission."""
    for root in sl.HUMAN_LABEL_ROOTS:
        d = tmp_path / root
        d.mkdir(parents=True, exist_ok=True)
    (tmp_path / sl.HUMAN_LABEL_ROOTS[1] / "returned.json").write_text(
        '{"source": "HUMAN_REVIEWED_QA_LABEL"}', encoding="utf-8"
    )
    _repo_at(tmp_path, monkeypatch)

    result = sl.check()

    kinds = {(f.item, f.kind) for f in result.findings}
    assert ("CT1-human-labels", "AUTHORITY_SPOKE") in kinds, kinds
    # And the invariant must ALSO object, because its premise -- that the
    # count is zero -- stopped being true.
    assert ("CT1-human-labels", "PREMISE_BROKEN") in kinds, kinds


def test_a_recorded_product_decision_makes_the_dormant_row_fail(tmp_path,
                                                                monkeypatch,
                                                                ledger):
    """N-07 is DORMANT on engineering's observation that nothing calls it. If
    the operator records an actual decision, the row is no longer the whole
    truth and must be restated rather than left standing."""
    decisions = tmp_path / "core" / "decisions"
    decisions.mkdir(parents=True)
    (decisions / "N-07.md").write_text(
        "FIXTURE ONLY. Not an operator decision.", encoding="utf-8"
    )
    _repo_at(tmp_path, monkeypatch)

    result = sl.check()

    kinds = {(f.item, f.kind) for f in result.findings}
    assert ("N-07", "AUTHORITY_SPOKE") in kinds, kinds


def test_no_operator_decision_records_exist_in_the_real_tree():
    """The counterpart to the worklist assertion.

    `core/decisions/` is the path the closure checks read. If a file appears
    there, an operator item is being closed -- which is legitimate when a
    person wrote it and a forgery when a test did. Either way it must not
    happen unnoticed.

    `gym-webhook-disclosure.md` is the one expected exception: the operator
    decided DISCLOSE in a live session, 2026-08-21, while Gate F's port onto
    master turned the previously-unreachable `maintenanceWebhookUrl` dispatch
    reachable (see the file itself, and the matching `gym-webhook-disclosure`
    row in `RULES`, restated to `CLOSED` in the same commit as the decision
    record, per this test's own instruction above).

    `roboflow-key-reissue.md` and `scanner-pipeline-location.md` joined the
    same way, 2026-09-17: the operator recorded both decisions in a live
    session (accept-the-risk / do-not-reissue for the API key, S-1/S-2/S-3
    for the pipeline's location), and both matching `RULES` rows were
    restated to `CLOSED` in the same commit as these two files.

    `N-05.md` joined the same way, same day: the operator reviewed their own
    GCP billing console live and confirmed 3a+4 (budget alert already
    configured, residual risk accepted), while explicitly declining to
    authorize the App Check production redeploy in the same decision.

    `N-04.md` joined the same way, same day: the operator deferred both P-1
    and P-2 (leave the gym-association code path dormant) rather than force
    a premature product call.
    """
    decisions = sl.REPO / "core" / "decisions"
    present = sorted(p.name for p in decisions.glob("*.md")) \
        if decisions.exists() else []
    expected = [
        "N-04.md",
        "N-05.md",
        "gym-webhook-disclosure.md",
        "roboflow-key-reissue.md",
        "scanner-pipeline-location.md",
    ]
    assert present == expected, (
        f"decision records exist: {present}, expected only {expected}. If an "
        "operator wrote a new one, the matching ledger row must be restated "
        "and this assertion updated in the same commit. If anything else "
        "wrote them, that is the forgery this mechanism is built to make "
        "visible."
    )


# ============================================ the residual-marker convention

def test_no_marked_residual_is_untracked():
    """The live check. Empty is the correct answer when nothing is
    outstanding, and it is honest here in a way an empty subject-set usually
    is not: every ledger row is independently checked, so 'no untracked
    residuals' is not the only thing standing between this suite and a green
    run over nothing."""
    assert sl.untracked_residuals() == {}


def test_a_marker_naming_an_unknown_item_is_caught(tmp_path):
    doc = tmp_path / "core" / "DECISION_LOG.md"
    doc.parent.mkdir(parents=True)
    doc.write_text(
        "The importer still drops the second page. RESIDUAL[importer-paging]\n",
        encoding="utf-8",
    )
    untracked = sl.untracked_residuals(
        docs=("core/DECISION_LOG.md",), repo=tmp_path
    )
    assert untracked == {"importer-paging": ["core/DECISION_LOG.md"]}


def test_a_marker_naming_a_tracked_item_is_accepted(tmp_path):
    """The control. Without it the test above could pass because the marker
    regex matches nothing at all, which would make the guard useless in the
    one direction that matters."""
    doc = tmp_path / "core" / "DECISION_LOG.md"
    doc.parent.mkdir(parents=True)
    doc.write_text("Still open. RESIDUAL[N-05]\n", encoding="utf-8")
    assert sl.residual_markers(("core/DECISION_LOG.md",), tmp_path) == {
        "N-05": ["core/DECISION_LOG.md"]
    }
    assert sl.untracked_residuals(("core/DECISION_LOG.md",), tmp_path) == {}


def test_the_marker_does_not_fire_on_ordinary_prose(tmp_path):
    """Why this is a marker and not a word search.

    The sentence below is exactly the shape that made prose-scanning
    unworkable: it contains 'still', 'unfixed' and 'open', and it is correct
    historical narration about work that IS done. A guard that flags it is a
    guard that gets switched off.
    """
    doc = tmp_path / "core" / "DECISION_LOG.md"
    doc.parent.mkdir(parents=True)
    doc.write_text(
        "The row was recorded as still open and unfixed for weeks after the "
        "code landed, which is the failure this mechanism exists to prevent.\n",
        encoding="utf-8",
    )
    assert sl.residual_markers(("core/DECISION_LOG.md",), tmp_path) == {}


def test_the_governed_document_list_is_not_empty():
    assert sl.RESIDUAL_DOCS
    for rel in sl.RESIDUAL_DOCS:
        assert (sl.REPO / rel).exists(), rel


def test_check_reports_an_untracked_residual(monkeypatch, ledger):
    """Wiring, proven separately from the function.

    The fixture tests above prove `untracked_residuals` reads markers
    correctly. This proves `check()` actually consults it -- the two halves
    fail differently, and this repository has already been caught once
    believing a stub proved the real thing.
    """
    monkeypatch.setattr(
        sl, "untracked_residuals",
        lambda *a, **k: {"importer-paging": ["core/DECISION_LOG.md"]},
    )
    result = sl.check()
    assert not result.ok
    bad = [f for f in result.findings if f.kind == "UNTRACKED_RESIDUAL"]
    assert bad and bad[0].item == "importer-paging", result.findings


# ================================================== the two rows enrolled today
#
# Both were surfaced by a decision council rather than by an audit, and both are
# the kind of item this ledger exists for: real, bounded, owned by somebody who
# is not engineering, and previously recorded in prose alone.


def _p1(monkeypatch, *, claims_two=True, dispatches=True, in_comment=False):
    arb = ("Two processors are involved, and no others: Google and Stripe."
           if claims_two else "Three processors are involved.")
    ts = ("export const reportEquipment = onCall(INTERACTIVE, async (r) => {\n"
          "  const url = snap.data()?.maintenanceWebhookUrl;\n"
          "  await fetch(url, { method: 'POST' });\n"
          "});\n") if dispatches else (
          "export const reportEquipment = onCall(INTERACTIVE, async (r) => {});")
    if in_comment:
        # A `/* */` doc comment, which is the shape that actually defeated this
        # invariant: `_without_comments` stripped only `//` lines, so prose
        # DESCRIBING the deleted dispatch kept the premise alive.
        ts = ("/**\n * gyms/{gymId}.maintenanceWebhookUrl -- dispatch removed.\n"
              " * await fetch(url) used to live here.\n */\n"
              "export const reportEquipment = onCall(INTERACTIVE, async (r) => {});")
    monkeypatch.setattr(
        sl, "_read",
        lambda rel: {"mobile/lib/l10n/app_en.arb": arb,
                     "functions/src/index.ts": ts}.get(rel, ""),
    )


def test_the_disclosure_question_stands_while_both_halves_hold(monkeypatch):
    _p1(monkeypatch)
    assert sl.gym_webhook_still_undisclosed()[0]


@pytest.mark.parametrize("kwargs,why", [
    ({"claims_two": False}, "the policy was amended, so it was disclosed"),
    ({"dispatches": False}, "the dispatch is gone, so there is no third party"),
])
def test_either_answer_retires_the_disclosure_question(monkeypatch, kwargs, why):
    """A row that goes on asking after it was answered is the stale QUESTION.

    Both resolutions are legitimate and they are opposites, so the invariant
    has to fail on either -- not merely on the one the recommendation favours.
    """
    _p1(monkeypatch, **kwargs)
    holds, detail = sl.gym_webhook_still_undisclosed()
    assert not holds, why
    assert "answered" in detail


def test_a_webhook_that_survives_only_in_a_comment_is_not_a_dispatch(monkeypatch):
    _p1(monkeypatch, in_comment=True)
    assert not sl.gym_webhook_still_undisclosed()[0]


_DISCLOSED_EN = "A gym you name in a report can be a third recipient of its contents."
_DISCLOSED_RU = "Указанный вами зал может стать третьим получателем содержимого."
_OLD_CLAIM_EN = "Two processors are involved, and no others: Google and Stripe."
_OLD_CLAIM_RU = "Задействованы два обработчика и никакие другие: Google и Stripe."


def _p1_decided(
    monkeypatch, tmp_path, *,
    source_en=_DISCLOSED_EN, source_ru=_DISCLOSED_RU,
    en_arb=_DISCLOSED_EN, ru_arb=_DISCLOSED_RU,
    privacy_html=_DISCLOSED_EN + " " + _DISCLOSED_RU,
    record_present=True,
):
    """Six independently-controllable surfaces plus the decision record --
    codex review, 2026-08-21, across three rounds: the first version of this
    fixture only varied one file (missed a stale generated surface or a
    Russian-only regression); the second omitted `public/privacy.html`
    entirely (missed a regression landing only on the hosted page); the third
    faked `legal_text.py`/the `.arb`s as whole-file text, which could not
    prove the check reads the *privacy* value specifically rather than any
    text anywhere in the file (see
    `test_closure_ignores_a_decoy_marker_in_an_unrelated_arb_key` below) --
    fixed by monkeypatching the imported `legal_text` module's own
    `PRIVACY_EN`/`PRIVACY_RU` attributes and by JSON-encoding the `.arb`
    fakes under their real `legalPrivacyBody` key.
    """
    _p1(monkeypatch, dispatches=True)
    ts_text = sl._read("functions/src/index.ts")

    real_repo = sl.REPO
    sys.path.insert(0, str(real_repo / "scripts" / "legal"))
    import legal_text
    monkeypatch.setattr(legal_text, "PRIVACY_EN", source_en)
    monkeypatch.setattr(legal_text, "PRIVACY_RU", source_ru)

    texts = {
        "mobile/lib/l10n/app_en.arb": json.dumps({"legalPrivacyBody": en_arb}),
        "mobile/lib/l10n/app_ru.arb": json.dumps({"legalPrivacyBody": ru_arb}),
        "public/privacy.html": privacy_html,
        "functions/src/index.ts": ts_text,
    }
    monkeypatch.setattr(sl, "_read", lambda rel: texts.get(rel, ""))
    monkeypatch.setattr(sl, "REPO", tmp_path)
    if record_present:
        decisions = tmp_path / "core" / "decisions"
        decisions.mkdir(parents=True)
        (decisions / "gym-webhook-disclosure.md").write_text(
            "decided", encoding="utf-8")


def test_closure_stays_honest_once_disclosed_and_recorded(monkeypatch, tmp_path):
    _p1_decided(monkeypatch, tmp_path)
    holds, detail = sl.gym_webhook_disclosure_stays_honest()
    assert holds, detail


@pytest.mark.parametrize("kwargs", [
    {"source_en": _OLD_CLAIM_EN},
    {"source_ru": _OLD_CLAIM_RU},
    {"en_arb": _OLD_CLAIM_EN},
    {"ru_arb": _OLD_CLAIM_RU},
    {"privacy_html": _OLD_CLAIM_EN},
    {"privacy_html": _OLD_CLAIM_RU},
])
def test_closure_breaks_if_any_one_surface_reverts_to_no_others(
        monkeypatch, tmp_path, kwargs):
    """Each of the six texts can regress independently -- a source edit that
    never got rebuilt, a rebuild that only touched one locale, or a
    hosted-page-only hand-edit that bypassed the build script entirely -- and
    each alone must be enough to break the closure."""
    _p1_decided(monkeypatch, tmp_path, **kwargs)
    holds, detail = sl.gym_webhook_disclosure_stays_honest()
    assert not holds, detail


def test_closure_breaks_if_a_surface_loses_the_marker_without_reverting(
        monkeypatch, tmp_path):
    """The gap the first version actually had: absence of the old sentence
    was treated as proof of disclosure. Deleting the disclosure paragraph
    entirely satisfies "not old_claim" without satisfying "discloses
    anything"."""
    _p1_decided(monkeypatch, tmp_path, en_arb="(disclosure paragraph removed)")
    holds, detail = sl.gym_webhook_disclosure_stays_honest()
    assert not holds, detail


def test_closure_breaks_if_the_decision_record_disappears(monkeypatch, tmp_path):
    _p1_decided(monkeypatch, tmp_path, record_present=False)
    assert not sl.gym_webhook_disclosure_stays_honest()[0]


def test_closure_ignores_a_decoy_marker_in_an_unrelated_arb_key(
        monkeypatch, tmp_path):
    """Codex round 3, verbatim: 'An app_en.arb with the disclosure removed
    from legalPrivacyBody but "third recipient of" placed in an unrelated key
    still passes.' `legalPrivacyBody` itself still carries the old claim;
    only a neighboring `legalTermsBody` key carries the marker -- a whole-file
    substring search would wrongly call this disclosed."""
    _p1_decided(monkeypatch, tmp_path, en_arb=_OLD_CLAIM_EN)
    decoyed = json.dumps({
        "legalPrivacyBody": _OLD_CLAIM_EN,
        "legalTermsBody": _DISCLOSED_EN,
    })
    monkeypatch.setattr(
        sl, "_read",
        lambda rel, _orig=sl._read: (
            decoyed if rel == "mobile/lib/l10n/app_en.arb" else _orig(rel)
        ),
    )
    holds, detail = sl.gym_webhook_disclosure_stays_honest()
    assert not holds, detail


def test_closure_breaks_if_the_webhook_dispatch_is_removed(monkeypatch, tmp_path):
    """Codex round 3: the decision record promises this row reopens if the
    dispatch in `functions/src/index.ts` is removed; nothing read that file
    before, so removing it could not have reopened anything."""
    _p1_decided(monkeypatch, tmp_path)
    no_dispatch_ts = (
        "export const reportEquipment = onCall(INTERACTIVE, async (r) => {});"
    )
    monkeypatch.setattr(
        sl, "_read",
        lambda rel, _orig=sl._read: (
            no_dispatch_ts if rel == "functions/src/index.ts" else _orig(rel)
        ),
    )
    holds, detail = sl.gym_webhook_disclosure_stays_honest()
    assert not holds, detail
    assert "dispatch" in detail


def test_no_roboflow_key_literal_is_committed():
    """The live assertion, not a fixture one. This is the fact being guarded."""
    holds, detail = sl.roboflow_key_not_committed()
    assert holds, detail


def test_the_credential_guard_has_a_non_empty_subject_set():
    """A guard over zero files reports clean for ever.

    `_tracked_text_files` shells out to git; if that failed it would return an
    empty tuple and the invariant above would pass by scanning nothing.
    """
    files = sl._tracked_text_files()
    assert len(files) > 100, len(files)
    assert "scripts/review/state_ledger.py" in files


#: Built at runtime, never written as a literal. The first draft of these
#: fixtures spelled the banned pattern out -- and the guard promptly reported
#: this test file as carrying a committed key, which is a true positive on a
#: false subject. A guard that its own tests trip is a guard that gets muted.
_KEY_NAME = "ROBOFLOW" + "_KEY"
_FAKE = "abcd1234" + "efgh5678"


@pytest.mark.parametrize("sep,quote", [(" = ", '"'), ("=", "'"), (": ", '"')])
def test_a_committed_key_literal_is_seen(monkeypatch, sep, quote):
    literal = f"{_KEY_NAME}{sep}{quote}{_FAKE}{quote}"
    monkeypatch.setattr(sl, "_tracked_text_files", lambda: ("some/file.md",))
    monkeypatch.setattr(sl, "_read", lambda rel: literal)
    holds, detail = sl.roboflow_key_not_committed()
    assert not holds
    assert "now appears" in detail


@pytest.mark.parametrize("shape", [
    "{k} = os.environ[\"{k}\"]",
    "the key is read from {k} in the environment",
    "sha256: 6ae6e7db8c4f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b",
])
def test_the_credential_guard_does_not_cry_wolf(monkeypatch, shape):
    benign = shape.format(k=_KEY_NAME)
    """Measured false-positive control.

    A loose "long token near the word roboflow" pattern would fire on every
    sha256 in the provenance documents, and a guard people learn to ignore
    protects nothing -- the same reasoning that rejected prose word-scanning.
    """
    monkeypatch.setattr(sl, "_tracked_text_files", lambda: ("some/file.md",))
    monkeypatch.setattr(sl, "_read", lambda rel: benign)
    assert sl.roboflow_key_not_committed()[0]


# ============================== what the final falsification review confirmed
#
# Four defects, all the same family as f5: a predicate whose conjuncts prove
# the DECLARATIONS exist and never prove anything USES them. Each is pinned
# here by the mutation that found it.


def _files(monkeypatch, files: dict):
    """A whole synthetic tree, keyed by repo-relative path.

    Named apart from `_tree` above deliberately: the first draft called both
    `_tree`, the later definition silently shadowed the earlier one, and four
    passing tests went red for a reason unrelated to what they test.
    """
    monkeypatch.setattr(sl, "_read", lambda rel: files.get(rel, ""))


_GETTER = ("PrefetchState get state {\n"
           "  return quotaExhausted\n"
           "      ? PrefetchState.partialQuota\n"
           "      : PrefetchState.partialFailed;\n"
           "}")

_ARMS = ("PrefetchState.partialQuota => l10n.partialLimit,\n"
         "PrefetchState.partialFailed => l10n.partialFailed,")

_PREFETCH_ARB = json.dumps({
    "partialLimit": "38 of 84 saved — daily limit reached",
    "partialFailed": "38 of 84 saved — some downloads failed",
})

_PREFETCH_FILES = {
    "mobile/lib/features/equipment/data/clip_url_resolver.dart":
        "class ClipBatch { final bool quotaExhausted; }",
    "mobile/lib/features/workouts/data/prefetch_outcome.dart":
        "enum PrefetchState { partialQuota, partialFailed }\n" + _GETTER,
    "mobile/lib/features/workouts/state/offline_video_providers.dart":
        "return PrefetchOutcome(quotaExhausted: batch.quotaExhausted);",
    "mobile/lib/features/workouts/workouts_page.dart": _ARMS,
    "mobile/lib/l10n/app_en.arb": _PREFETCH_ARB,
}


def test_f_prefetch_is_closed_when_the_refusal_is_declared_carried_and_shown(
    monkeypatch,
):
    _files(monkeypatch, dict(_PREFETCH_FILES))
    assert sl.f_prefetch()[0] == "CLOSED"


@pytest.mark.parametrize("rel,replacement,why", [
    ("mobile/lib/features/workouts/state/offline_video_providers.dart",
     "return PrefetchOutcome(quotaExhausted: false);",
     "the wire is cut, so every quota refusal renders as a fault -- which is "
     "F-prefetch's literal defect, and the row used to still read CLOSED"),
    ("mobile/lib/features/workouts/workouts_page.dart",
     "PrefetchState.partialQuota => l10n.partialFailed,\n"
     "PrefetchState.partialFailed => l10n.partialFailed,",
     "both states reach the person as the same sentence, which is the F2 "
     "defect wearing F-prefetch's clothes"),
    ("mobile/lib/features/workouts/data/prefetch_outcome.dart",
     "enum PrefetchState { partialQuota, partialFailed }\n"
     "PrefetchState get state { return PrefetchState.partialFailed; }",
     "the getter no longer maps the flag to the state -- the one line "
     "between a carried flag and a rendered state"),
])
def test_f_prefetch_needs_the_refusal_to_actually_reach_a_person(
    monkeypatch, rel, replacement, why
):
    files = dict(_PREFETCH_FILES)
    files[rel] = replacement
    _files(monkeypatch, files)
    assert sl.f_prefetch()[0] == "OPEN", why


def test_a_comment_quoting_the_wire_is_not_the_wire(monkeypatch):
    files = dict(_PREFETCH_FILES)
    files["mobile/lib/features/workouts/state/offline_video_providers.dart"] = (
        "// quotaExhausted: batch.quotaExhausted used to be here\n"
        "return PrefetchOutcome(quotaExhausted: false);"
    )
    # `_read` is patched, so the ARB has to come from the fixture too.
    _files(monkeypatch, files)
    assert sl.f_prefetch()[0] == "OPEN"


_F2_FILES = {
    "mobile/lib/features/equipment/data/video_failure.dart":
        "enum VideoFailureReason { quotaExhausted, linkUnavailable }\n"
        "if (error is ClipQuotaExhausted) return VideoFailureReason"
        ".quotaExhausted;",
    "mobile/lib/features/equipment/widgets/exercise_reference.dart":
        "final reason = classifyVideoFailure(error);\n"
        "VideoFailureReason.quotaExhausted => l10n.clipQuotaReached,\n"
        "VideoFailureReason.linkUnavailable => l10n.clipGenericFault,",
    "mobile/lib/l10n/app_en.arb": json.dumps({
        "clipQuotaReached": "Daily clip limit reached",
        "clipGenericFault": "The clip link is unavailable",
    }),
}


def test_f2_needs_something_to_produce_the_reason(monkeypatch):
    """The gap the review found: three conjuncts, none of them a producer.

    The enum member exists, the card maps it, the two strings differ -- and no
    code path returns it. The user reads "The clip link is unavailable" for a
    quota refusal, which IS F2, while the row prints the correct refusal string
    as its own evidence.
    """
    _files(monkeypatch, dict(_F2_FILES))
    assert sl.f2()[0] == "CLOSED"

    files = dict(_F2_FILES)
    files["mobile/lib/features/equipment/data/video_failure.dart"] = (
        "enum VideoFailureReason { quotaExhausted, linkUnavailable }"
    )
    _files(monkeypatch, files)
    assert sl.f2()[0] == "OPEN"


def _trap(tmp_path, monkeypatch, body):
    d = tmp_path / "mobile" / "test" / "adversarial"
    d.mkdir(parents=True)
    (d / "dormant_traps_test.dart").write_text(body, encoding="utf-8")
    monkeypatch.setattr(sl, "REPO", tmp_path)


_LIVE_TRAP = (
    "test('nothing reads dailyWorkouts', () {\n"
    "  for (final f in dartSources('lib')) {}\n"
    "  expect(readers, isEmpty, reason: 'a reader appeared');\n"
    "  expect(seed, contains(\"'squat'\"));\n"
    "});\n"
)


def test_f025_reads_the_tripwires_assertions_not_its_name(tmp_path, monkeypatch):
    _trap(tmp_path, monkeypatch, _LIVE_TRAP)
    assert sl.f025_tripwire_intact()[0]


def test_a_gutted_tripwire_that_still_says_f025_is_not_a_tripwire(
    tmp_path, monkeypatch
):
    """`flutter test` passes on an empty main, and the old check passed too.

    F025's mitigation is this suite and nothing else, so a suite reduced to a
    comment bearing its name is not a weaker guard -- it is an absent one.
    """
    _trap(tmp_path, monkeypatch, "// F025: tripwire deleted.\nvoid main() {}\n")
    holds, detail = sl.f025_tripwire_intact()
    assert not holds
    assert "no longer makes these assertions" in detail


def test_a_missing_tripwire_file_is_still_caught(tmp_path, monkeypatch):
    monkeypatch.setattr(sl, "REPO", tmp_path)
    assert not sl.f025_tripwire_intact()[0]


def test_a_residual_comes_due_when_its_row_is_closed(ledger, monkeypatch):
    """The failure that would actually have happened.

    Every live marker describes work due AFTER the operator decides. The moment
    the decision lands, AUTHORITY_SPOKE fires, the row is restated terminal --
    and the marker naming it used to go silent for ever, at exactly the moment
    it came due. A tracked marker that vanishes when it matters is worse than
    none, because the convention teaches people it is being watched.

    Injects a synthetic marker rather than reading real prose. This test used
    to assert against whatever `RESIDUAL[...]` marker happened to still be
    live in the tree, on the assumption there would always be at least one.
    2026-09-17 disproved that: the last three live markers
    (scanner-pipeline-location, roboflow-key-reissue's row had none, then
    N-04-gym-association) were all retired the same day their decisions
    landed, and this test started failing with "no live markers" -- not
    because the mechanism broke, but because the fixture depended on a
    contingent fact about the current tree's prose instead of testing the
    mechanism itself.
    """
    monkeypatch.setattr(
        sl, "residual_markers",
        lambda *a, **k: {"F-prefetch": ["synthetic_test_fixture.md"]},
    )
    ledger(_swap("F-prefetch", state="CLOSED",
                 closure=lambda: (True, "the operator decided")))
    due = [f for f in sl.check().findings if f.kind == "RESIDUAL_NOW_DUE"]
    assert due and due[0].item == "F-prefetch", sl.check().findings
    assert "now due" in due[0].detail


def test_an_open_row_does_not_make_its_residual_due():
    """The control. Today every marked row is open, so nothing is due."""
    assert not [f for f in sl.check().findings if f.kind == "RESIDUAL_NOW_DUE"]


def test_the_clinical_handoff_is_read_for_residuals():
    """A marker in the document that owns D1 and H3 was not read at all."""
    assert "core/review/CLINICAL_VALIDATION_HANDOFF.md" in sl.RESIDUAL_DOCS
    for rel in sl.RESIDUAL_DOCS:
        assert (sl.REPO / rel).exists(), rel


# =========================== the row that was never environment-blocked
#
# `scanner-metadata` read ENVIRONMENT_BLOCKED for several passes because a
# `pip install` failed INSIDE a container -- the interception CA is in the
# Windows trust store and absent from `python:3-slim`'s bundle -- and that was
# generalised into a claim about the host. The host reaches PyPI fine.
# Downloading the manylinux wheels there and installing offline in the
# container needs no TLS bypass, and the genuine library then answers.


def _record(tmp_path, monkeypatch, model=b"TFL3", **overrides):
    (tmp_path / "mobile" / "assets" / "models").mkdir(parents=True)
    (tmp_path / "mobile" / "assets" / "models" / "m.tflite").write_bytes(model)
    import hashlib
    rec = {
        "input_path": "mobile/assets/models/m.tflite",
        "input_sha256": hashlib.sha256(model).hexdigest(),
        "recorded_min_parser_version": "1.0.0",
        "computed_min_parser_version": "1.0.0",
        "state": "VALIDATED_MATCH",
    }
    rec.update(overrides)
    monkeypatch.setattr(sl, "REPO", tmp_path)
    monkeypatch.setattr(sl, "_read", lambda rel: json.dumps(rec))
    return rec


def test_a_validated_model_closes_the_row(tmp_path, monkeypatch):
    _record(tmp_path, monkeypatch)
    state, detail = sl.scanner_metadata_validated()
    assert state == "CLOSED"
    assert "'1.0.0'" in detail


def test_swapping_the_model_reopens_the_question(tmp_path, monkeypatch):
    """The conjunct the whole design rests on.

    The record is an answer about ONE artefact. A verdict earned by a different
    file is not evidence about this one, and inheriting it silently is exactly
    the drift this ledger exists to refuse -- here it would mean an unvalidated
    binary shipping under a validated model's reputation.
    """
    _record(tmp_path, monkeypatch, model=b"TFL3-original")
    (tmp_path / "mobile" / "assets" / "models" / "m.tflite").write_bytes(
        b"TFL3-a-different-model"
    )
    state, detail = sl.scanner_metadata_validated()
    assert state == "OPEN"
    assert "not the one that was validated" in detail


@pytest.mark.parametrize("overrides,why", [
    ({"state": "ENVIRONMENT_NOT_RUN"}, "a record that never reached a verdict"),
    ({"state": "VALIDATED_MISMATCH"}, "a record that reached the wrong one"),
    ({"computed_min_parser_version": "1.3.0"},
     "a record that contradicts itself"),
    ({"input_path": "mobile/assets/models/gone.tflite"},
     "a record about a file that is not there"),
])
def test_the_record_cannot_claim_more_than_it_holds(tmp_path, monkeypatch,
                                                    overrides, why):
    _record(tmp_path, monkeypatch, **overrides)
    assert sl.scanner_metadata_validated()[0] == "OPEN", why


@pytest.mark.parametrize("body", ["null", "[]", '{"state": "VALIDATED_MATCH"',
                                  '"VALIDATED_MATCH"'])
def test_a_malformed_record_opens_the_row_rather_than_crashing(
    tmp_path, monkeypatch, body
):
    """`null` parses cleanly and is not a record.

    Found by a mutation that emptied the file and made the predicate raise.
    `check()` would have reported PREDICATE_ERROR, so nothing was ever silently
    green -- but a guard that says OPEN and why is more use than a traceback.
    """
    monkeypatch.setattr(sl, "REPO", tmp_path)
    monkeypatch.setattr(sl, "_read", lambda rel: body)
    assert sl.scanner_metadata_validated()[0] == "OPEN"


def test_the_live_record_is_about_the_model_that_ships():
    """Not a fixture. The claim itself, against the real tree."""
    record = json.loads(
        (sl.REPO / "core" / "ml" / "METADATA_VALIDATION.json").read_text(
            encoding="utf-8"
        )
    )
    assert record["state"] == "VALIDATED_MATCH"
    assert record["input_path"] == "mobile/assets/models/equipment_v1.tflite"
    assert sl.scanner_metadata_validated()[0] == "CLOSED"
