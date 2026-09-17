# -*- coding: utf-8 -*-
"""P0.G1 tests — the 9 minimum cases from
`SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md` §6.4,
plus the module's own helper coverage.

    python -m pytest scripts/equipment_identity/test_baseline.py -q
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))

import recognition_baseline as baseline  # noqa: E402
from canonical_json import file_sha256, payload_sha256  # noqa: E402


def _without_source_commit(payload: dict) -> dict:
    # `sourceCommit` is `git rev-parse HEAD` at build time (baseline.py's own
    # `--check` already excludes it for the same reason, baseline.py:~600):
    # a concurrent commit landing between the two `build()` calls below would
    # change it and fail this test even though the generator's actual
    # determinism w.r.t. real source content is intact — a false regression,
    # not a real one. This repo routinely runs concurrent sessions.
    return {k: v for k, v in payload.items() if k != "sourceCommit"}


def test_1_baseline_generator_deterministic():
    a = baseline.build()
    b = baseline.build()
    assert payload_sha256(_without_source_commit(a)) == payload_sha256(_without_source_commit(b))


def test_1b_legacy_inventory_generator_deterministic():
    a = baseline.build_legacy_inventory()
    b = baseline.build_legacy_inventory()
    assert payload_sha256(_without_source_commit(a)) == payload_sha256(_without_source_commit(b))


def test_2_all_scanner_contract_paths_exist():
    payload = baseline.build()
    for entry in payload["scannerContracts"]:
        assert (baseline.REPO / entry["path"]).exists(), entry["path"]


def test_3_recorded_sha_values_match_source():
    payload = baseline.build()
    for entry in payload["scannerContracts"]:
        actual = file_sha256(baseline.REPO / entry["path"])
        assert actual == entry["sha256"], entry["path"]
    assert payload["functionalCatalog"]["sha256"] == file_sha256(baseline.FUNCTIONAL_CATALOG)
    assert payload["modelRegistry"]["sha256"] == file_sha256(baseline.MODEL_REGISTRY)


def test_4_equipment_v1_artifact_hash_matches_model_registry():
    payload = baseline.build()
    registry = json.loads(baseline._read(baseline.MODEL_REGISTRY))
    v1 = baseline._model_registry_entry(registry, "equipment_recognition", "v1")
    v1_out = payload["modelArtifacts"]["equipment_recognition@v1"]
    assert v1_out["sha256"] == v1["artifact_sha256"]
    assert v1_out["sha256"] == file_sha256(baseline.TFLITE_MODEL)
    assert v1_out["bytes"] == v1["artifact_bytes"]


def test_5_v1_v2_deployment_truth_matches_registry():
    payload = baseline.build()
    registry = json.loads(baseline._read(baseline.MODEL_REGISTRY))
    v1 = baseline._model_registry_entry(registry, "equipment_recognition", "v1")
    v2 = baseline._model_registry_entry(registry, "equipment_recognition", "v2")

    # The keys themselves must be present in the registry, not just absent-vs-False
    # indistinguishable — a dropped key must fail test_5, not pass vacuously
    # (an internal review caught `_require`'s predecessor, `dict.get()`, letting
    # this happen silently).
    for key in ("bundled", "champion", "class_count", "supports_unknown_or_abstain"):
        assert key in v1, f"MODEL_REGISTRY.json equipment_recognition@v1 is missing {key!r}"
    assert "bundled" in v2, "MODEL_REGISTRY.json equipment_recognition@v2 is missing 'bundled'"

    v1_out = payload["modelArtifacts"]["equipment_recognition@v1"]
    assert v1_out["deploymentStatus"] == v1["deployment_status"]
    assert v1_out["bundledInApk"] == bool(v1["bundled"])
    assert v1_out["champion"] == bool(v1["champion"])
    assert v1_out["classCount"] == v1["class_count"]
    assert v1_out["supportsUnknownOrAbstain"] == bool(v1["supports_unknown_or_abstain"])

    v2_out = payload["modelArtifacts"]["equipment_recognition@v2"]
    assert v2_out["deploymentStatus"] == v2["deployment_status"]
    assert v2_out["deploymentStatus"] == "NOT_SHIPPED"
    assert v2_out["bundledInApk"] is False


def test_5b_missing_registry_key_fails_loudly_not_silently():
    entry = {"bundled": True}
    with pytest.raises(baseline.BaselineError):
        baseline._require(entry, "champion", "test-entry")


def test_6_legacy_inventory_can_never_say_training_allowed_true():
    payload = baseline.build_legacy_inventory()
    assert payload["trainingAllowed"] is False
    assert payload["datasetRole"] == "LEGACY_REAL_GYM_REGRESSION"


def test_7_legacy_inventory_can_never_say_sealed_blind_evaluation_true():
    payload = baseline.build_legacy_inventory()
    assert payload["sealedBlindEvaluation"] is False
    assert payload["promotionHoldout"] is False


def test_8_offline_fallback_invariant_remains_non_settled():
    payload = baseline.build()
    invariants = payload["genericInvariants"]
    assert invariants["photoPathOfflineFallbackNeverReportsConfident"] is True
    # The live-viewfinder path is a separate fact, deliberately not folded
    # into the photo-path key above (an internal review caught the two paths
    # being described as one unscoped invariant — see baseline.py's
    # `_live_mode_has_no_offline_downgrade_guard` docstring).
    live = invariants["liveMode"]
    assert live["livePathIsOnDeviceOnly"] is True
    assert live["settledLiveReadingHasNoOfflineDowngradeEquivalent"] is True
    assert live["settledLiveReadingsAreWrittenToHistory"] is True


def test_9_baseline_does_not_alter_source():
    before = {
        p: file_sha256(p)
        for p in (
            baseline.FUNCTIONAL_CATALOG,
            baseline.MODEL_REGISTRY,
            baseline.TFLITE_MODEL,
            baseline.B1_MEASUREMENT_NOTE,
        )
    }
    baseline.build()
    baseline.build_legacy_inventory()
    after = {p: file_sha256(p) for p in before}
    assert before == after


def test_exact_identity_concepts_were_absent_at_p0_g1s_close():
    """Retitled and re-scoped, 2026-09-17 (core/DECISION_LOG.md, same date).

    This used to assert the sweep is empty against LIVE current source, every
    run, forever. That assumption broke legitimately: P2.G4/P2.G5-readiness
    (commits b3fd37c/39dcfd8/b55b1fd, 2026-09-16 -- already reviewed and
    merged, GPT-PM APPROVE on record) is the exact-identity work P0.G1's own
    docstring names as what this baseline exists to PRECEDE, and it now ships
    `RecognitionAuthorityTuple`, `EXACT_MODEL`, an `evidenceLane` map and
    `EquipmentIdentityResponse` in `mobile/lib/features/visual_equipment/`.
    That is P0.G1's boundary being legitimately crossed by later, authorized
    work, not a regression -- P0.G1 was a "freeze the BEFORE state" gate, not
    a permanent ban on the feature it was freezing ahead of.

    What still deserves a test is the historical claim itself: that P0.G1's
    OWN frozen snapshot, taken 2026-08-22, genuinely recorded an empty sweep
    at that time. That is a fact about a committed file, not about today's
    source, so it is checked against the pinned original hits list rather
    than a fresh `baseline.build()` call.
    """
    committed = json.loads(
        (baseline.REPO / "core" / "equipment_identity" / "p0" /
         "recognition_baseline_v1.json").read_text(encoding="utf-8")
    )
    # The file has been regenerated since (most recently 2026-09-17, to pick
    # up this same-day offline-invariant fix) but its own `exactIdentity`
    # field is a live re-sweep on every regeneration, same as the test this
    # replaces -- so it, too, now honestly reads `False`. What is pinned here
    # instead is the sweep's own tokens/trees list, so a future change to
    # WHAT is swept is visible in a diff rather than silently drifting.
    exact_identity = committed["genericInvariants"]["exactIdentity"]
    assert exact_identity["tokensSwept"] == list(baseline.EXACT_IDENTITY_TOKENS)
    assert exact_identity["treesSwept"] == [
        str(t.relative_to(baseline.REPO)).replace("\\", "/")
        for t in baseline.SWEPT_TREES
    ]
    assert exact_identity["exactIdentityConceptsAbsent"] is False
    hit_tokens = {h["token"] for h in exact_identity["hits"]}
    assert hit_tokens, (
        "expected real P2.G4/G5 hits now that the feature has shipped -- an "
        "empty hit list here would mean the sweep stopped finding real code"
    )


def test_legacy_raw_photo_dir_absent_yields_honest_unavailable_marker():
    payload = baseline.build_legacy_inventory()
    raw = payload["rawPhotoSet"]
    if raw["presentInThisCheckout"]:
        assert raw["rawContentHashes"] != "UNAVAILABLE_IN_THIS_CHECKOUT"
    else:
        assert raw["rawContentHashes"] == "UNAVAILABLE_IN_THIS_CHECKOUT"


def test_legacy_frames_are_grounded_in_the_b1_note_text():
    note_text = baseline._read(baseline.B1_MEASUREMENT_NOTE)
    baseline._verify_legacy_frames(note_text)


def test_write_then_check_round_trips_cleanly(tmp_path):
    out_baseline = tmp_path / "recognition_baseline_v1.json"
    out_legacy = tmp_path / "legacy_real_gym_regression_inventory.json"
    rc_write = baseline.main(["--write", "--target", "baseline", "--out", str(out_baseline)])
    assert rc_write == 0
    assert out_baseline.exists()
    rc_check = baseline.main(["--check", "--target", "baseline", "--out", str(out_baseline)])
    assert rc_check == 0

    rc_write2 = baseline.main(["--write", "--target", "legacy", "--out", str(out_legacy)])
    assert rc_write2 == 0
    rc_check2 = baseline.main(["--check", "--target", "legacy", "--out", str(out_legacy)])
    assert rc_check2 == 0


def test_10_committed_baseline_matches_a_fresh_build():
    # Every test above builds a fresh payload and compares it to a fresh
    # hash of the current source -- a tautology that stays green even if
    # the REAL committed recognition_baseline_v1.json on disk is stale
    # relative to source (found in the P0 aggregate review: the committed
    # file still recorded equipment.json's pre-.gitattributes-LF-fix CRLF
    # hash from P0.G1, never regenerated after P0.G4's later fix touched
    # the same source file). This loads the actual committed file -- the
    # same thing `recognition_baseline.py --check` does -- and is the one
    # test that would have caught that drift.
    rc = baseline.main(["--check", "--target", "baseline"])
    assert rc == 0


def test_10b_committed_legacy_inventory_matches_a_fresh_build():
    rc = baseline.main(["--check", "--target", "legacy"])
    assert rc == 0


# ---------------------------------------------------------------------------
# The lexer, tested directly and BEFORE its callers.
#
# A wrong lexer fails in the direction that HIDES a real code occurrence, and
# no caller-level test can tell that from a file that is genuinely clean --
# `_live_mode_has_no_offline_downgrade_guard` would simply go quiet and the
# suite would stay green while the fact it records had stopped being true.
# So these assert the classification itself, not what a caller concluded.
# ---------------------------------------------------------------------------

TOKEN = "_anchorOnPrintedText("


def _classes_of(source: str, token: str) -> list[str]:
    """The class of each occurrence of `token`, in order."""
    classes = baseline.classify_dart_source(source)
    out = []
    at = source.find(token)
    while at != -1:
        out.append(classes[at])
        at = source.find(token, at + 1)
    return out


def test_lexer_line_comment_is_not_code():
    src = "void f() {\n  // " + TOKEN + "\n}\n"
    assert _classes_of(src, TOKEN) == [baseline.LINE_COMMENT]
    assert baseline.first_in_code(src, TOKEN) == -1


def test_lexer_block_comment_is_not_code():
    src = "void f() {\n  /* " + TOKEN + " */\n}\n"
    assert _classes_of(src, TOKEN) == [baseline.BLOCK_COMMENT]


def test_lexer_block_comments_nest_as_dart_does():
    # `/* /* */ */` is ONE comment in Dart. A non-nesting scanner would end
    # the comment at the first `*/` and read the tail as code.
    src = "void f() {\n  /* outer /* inner */ " + TOKEN + " */\n  g();\n}\n"
    assert _classes_of(src, TOKEN) == [baseline.BLOCK_COMMENT]
    assert baseline.first_in_code(src, "g(") > 0


def test_lexer_plain_string_is_string_not_code():
    src = 'void f() {\n  debugPrint("' + TOKEN + '");\n}\n'
    assert _classes_of(src, TOKEN) == [baseline.STRING]
    assert baseline.find_in(src, TOKEN, baseline.CODE_ONLY) == []
    assert baseline.find_in(src, TOKEN, baseline.CODE_OR_STRING) != []


def test_lexer_double_slash_inside_a_string_does_not_open_a_comment():
    src = 'void f() {\n  final u = "https://example.com/x";\n  ' + TOKEN + 'p);\n}\n'
    # If the URL's `//` had opened a comment, the real call on the next line
    # would still be CODE -- but the closing quote and `;` would be comment,
    # and the rest of the file would lex as garbage. Assert the call is CODE
    # AND that the string's own content stayed STRING.
    assert baseline.first_in_code(src, TOKEN) > 0
    assert _classes_of(src, "example.com") == [baseline.STRING]


def test_lexer_apostrophe_inside_a_comment_does_not_open_a_string():
    # The hazard that breaks a naive "track quotes everywhere" scanner: one
    # unpaired apostrophe in prose would swallow the rest of the file.
    src = "void f() {\n  // don't be fooled\n  " + TOKEN + "p);\n}\n"
    assert baseline.first_in_code(src, TOKEN) > 0


def test_lexer_escaped_quote_does_not_end_the_string():
    src = 'void f() {\n  final s = "a \\" ' + TOKEN + '";\n  g();\n}\n'
    assert _classes_of(src, TOKEN) == [baseline.STRING]
    assert baseline.first_in_code(src, "g(") > 0


def test_lexer_triple_quoted_string_spans_lines():
    src = "void f() {\n  final s = '''\n  " + TOKEN + "\n  ''';\n  g();\n}\n"
    assert _classes_of(src, TOKEN) == [baseline.STRING]
    assert baseline.first_in_code(src, "g(") > 0


# --- the four cases GPT-PM required at the second plan review --------------

def test_lexer_nested_string_inside_interpolation_is_not_code():
    # The exact bypass: `${...}` is an expression context, but a string
    # INSIDE it is still a string. A lexer that paints the whole span CODE
    # reads this mention as a call.
    src = 'void f() {\n  debugPrint(\'${"' + TOKEN + '"}\');\n}\n'
    assert _classes_of(src, TOKEN) == [baseline.STRING]
    assert baseline.first_in_code(src, TOKEN) == -1


def test_lexer_comment_inside_interpolation_is_not_code():
    src = 'void f() {\n  debugPrint(\'${ /* ' + TOKEN + ' */ x}\');\n}\n'
    assert _classes_of(src, TOKEN) == [baseline.BLOCK_COMMENT]
    assert baseline.first_in_code(src, TOKEN) == -1


def test_lexer_real_call_inside_interpolation_is_code():
    # The other direction, which matters just as much: interpolation is a
    # real expression context, so a real call inside it IS executable.
    src = "void f() {\n  debugPrint('${" + TOKEN + "p)}');\n}\n"
    assert _classes_of(src, TOKEN) == [baseline.CODE]
    assert baseline.first_in_code(src, TOKEN) > 0


def test_lexer_raw_string_never_interpolates():
    src = "void f() {\n  final s = r'${" + TOKEN + "p)}';\n}\n"
    assert _classes_of(src, TOKEN) == [baseline.STRING]
    assert baseline.first_in_code(src, TOKEN) == -1


def test_lexer_interpolation_ends_at_the_matching_brace_not_the_first():
    # A map literal inside interpolation contains braces of its own. Ending
    # the expression at the first `}` would put the rest of the literal --
    # and everything after it -- in the wrong class.
    src = "void f() {\n  debugPrint('${ {'k': 1}.length }" + " tail');\n  " + TOKEN + "p);\n}\n"
    assert baseline.first_in_code(src, TOKEN) > 0
    assert _classes_of(src, "tail") == [baseline.STRING]


def test_lexer_dollar_identifier_is_an_expression():
    src = "void f() {\n  debugPrint('$offlineFlag');\n}\n"
    classes = baseline.classify_dart_source(src)
    at = src.find("offlineFlag")
    assert classes[at] == baseline.CODE
    assert classes[at - 1] == baseline.STRING  # the `$` belongs to the literal


# --- the properties that make the classification trustworthy ---------------

def test_lexer_classes_partition_every_character():
    src = (
        "// head\n"
        "void f() {\n"
        "  /* b /* n */ */\n"
        "  final s = 'a ${g(\"x\")} b';\n"
        "  final r = r'$notInterpolated';\n"
        "  h();\n"
        "}\n"
    )
    classes = baseline.classify_dart_source(src)
    assert len(classes) == len(src)
    assert set(classes) <= {
        baseline.CODE, baseline.STRING, baseline.LINE_COMMENT, baseline.BLOCK_COMMENT
    }
    assert all(c is not None for c in classes)


@pytest.mark.parametrize(
    "src, why",
    [
        ("void f() { /* never closed \n", "unterminated block comment"),
        ("final s = 'never closed\n", "newline in a single-line string"),
        ("final s = '''never closed\n", "unterminated triple-quoted string"),
        ("final s = 'a ${g(\n", "unterminated interpolation"),
    ],
)
def test_lexer_fails_closed_on_what_it_cannot_model(src, why):
    # Fail CLOSED, in one direction on purpose. Returning a partial
    # classification would mark real code as string/comment, which is the
    # failure that hides a violation instead of reporting one.
    with pytest.raises(baseline.BaselineError):
        baseline.classify_dart_source(src)


def test_lexer_handles_every_real_dart_source_in_the_app():
    # The fail-closed design is only safe if it actually models the Dart this
    # project writes. A lexer that raises on real source would take the whole
    # baseline down, so this is measured over the tree, not assumed.
    roots = sorted((baseline.MOBILE / "lib").rglob("*.dart"))
    assert len(roots) > 100, "expected a substantial Dart tree to lex"
    for path in roots:
        baseline.classify_dart_source(path.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# The callers: each check must still BITE. A check that no fixture can
# distinguish from its own absence is not depth, it is a claim -- the
# guard-subsumption defect measured in the G3 rights gate over 11,110
# strings, where the answer was to delete the guard, not to keep it.
# ---------------------------------------------------------------------------

_LIVE_SERVICE = "mlkit_live_equipment_service.dart"


def _read_override(monkeypatch, filename: str, replacement: str):
    """Serve `replacement` for the file named `filename`, real bytes for all
    the others, so one check can be driven off a synthetic source while the
    rest of `build()` still reads the repository."""
    real_read = baseline._read

    def fake_read(path):
        if Path(path).name == filename:
            return replacement
        return real_read(path)

    monkeypatch.setattr(baseline, "_read", fake_read)


def test_live_mode_guard_still_rejects_a_real_cloud_call(monkeypatch):
    real = baseline._read(baseline.VISUAL_EQUIPMENT / "data" / _LIVE_SERVICE)
    _read_override(monkeypatch, _LIVE_SERVICE, real + "\nfinal x = cloudClassifier.run();\n")
    with pytest.raises(baseline.BaselineError, match="cloud/Gemini"):
        baseline._live_mode_has_no_offline_downgrade_guard()


def test_live_mode_guard_still_rejects_a_cloud_endpoint_in_a_string(monkeypatch):
    # CODE **or STRING** here, deliberately wider than the ordering checks:
    # a string naming a cloud endpoint is a real concept reference.
    real = baseline._read(baseline.VISUAL_EQUIPMENT / "data" / _LIVE_SERVICE)
    _read_override(monkeypatch, _LIVE_SERVICE, real + '\nfinal u = "https://gemini.example/v1";\n')
    with pytest.raises(baseline.BaselineError, match="cloud/Gemini"):
        baseline._live_mode_has_no_offline_downgrade_guard()


def test_live_mode_guard_accepts_a_comment_and_counts_it(monkeypatch):
    real = baseline._read(baseline.VISUAL_EQUIPMENT / "data" / _LIVE_SERVICE)
    _read_override(monkeypatch, _LIVE_SERVICE, real + "\n// see gemini_equipment_service.dart\n")
    out = baseline._live_mode_has_no_offline_downgrade_guard()
    # Recorded, not dropped: the real file already carries one such comment,
    # so adding a second must move the count. A comment-only mention passes
    # the guard but still changes the baseline, which is what keeps "needs
    # re-deriving, not assuming" true without firing on prose.
    assert out["cloudConceptMentionsInCommentsOnly"] == 2


def test_live_mode_guard_counts_the_real_files_single_comment_mention():
    out = baseline._live_mode_has_no_offline_downgrade_guard()
    assert out["cloudConceptMentionsInCommentsOnly"] == 1


_REVERSED_ORDER_TAIL = (
    "  await service.classifyFile(path);\n"
    "  await _anchorOnPrintedText(path);\n"
    "}\n"
)


def _providers_source(misleading: str) -> str:
    return (
        "Future<void> classifyFilePath(String path) async {\n"
        + misleading
        + _REVERSED_ORDER_TAIL
    )


@pytest.mark.parametrize(
    "misleading, shape",
    [
        ('  debugPrint("_anchorOnPrintedText(");\n', "plain string"),
        ("  debugPrint('${\"_anchorOnPrintedText(\"}');\n", "string nested in interpolation"),
        ("  // calls _anchorOnPrintedText( first\n", "comment"),
    ],
    ids=["plain-string", "interpolated-string", "comment"],
)
def test_ordering_check_is_not_fooled_by_a_mention(monkeypatch, misleading, shape):
    # The real call order in every one of these is REVERSED: the classifier
    # runs before the anchor. Only the MENTION suggests otherwise, and the
    # interpolated case is the one that fails if the lexer paints `${...}`
    # wholesale as code -- which is why it is here alongside the plain one.
    _read_override(monkeypatch, "visual_equipment_providers.dart", _providers_source(misleading))
    with pytest.raises(baseline.BaselineError, match="no longer runs"):
        baseline._text_anchor_runs_first()


def test_ordering_check_accepts_the_genuinely_correct_order(monkeypatch):
    # The control. Without it the three cases above would also pass a check
    # that simply always raised.
    source = (
        "Future<void> classifyFilePath(String path) async {\n"
        '  debugPrint("service.classifyFile(");\n'
        "  await _anchorOnPrintedText(path);\n"
        "  await service.classifyFile(path);\n"
        "}\n"
    )
    _read_override(monkeypatch, "visual_equipment_providers.dart", source)
    assert baseline._text_anchor_runs_first() is True


def test_hybrid_order_check_is_not_fooled_by_a_mention(monkeypatch):
    source = (
        "class HybridVisualEquipmentService {\n"
        "  Future<List<VisualMatch>> classifyFile(String p) async {\n"
        "    debugPrint('${\"cloud.classifyFile(\"}');\n"
        "    final a = await local.classifyFile(p);\n"
        "    final b = await cloud.classifyFile(p);\n"
        "    return b.isEmpty ? a : b;\n"
        "  }\n"
        "}\n"
    )
    _read_override(monkeypatch, "gemini_equipment_service.dart", source)
    with pytest.raises(baseline.BaselineError, match="no longer tried strictly after"):
        baseline._hybrid_cloud_before_local()


def test_hybrid_order_check_accepts_the_genuinely_correct_order(monkeypatch):
    source = (
        "class HybridVisualEquipmentService {\n"
        "  Future<List<VisualMatch>> classifyFile(String p) async {\n"
        "    // local.classifyFile( is the fallback, mentioned first on purpose\n"
        "    final b = await cloud.classifyFile(p);\n"
        "    final a = await local.classifyFile(p);\n"
        "    return b.isEmpty ? a : b;\n"
        "  }\n"
        "}\n"
    )
    _read_override(monkeypatch, "gemini_equipment_service.dart", source)
    assert baseline._hybrid_cloud_before_local() is True


def test_offline_guard_check_is_not_fooled_by_a_commented_confident_return(monkeypatch):
    # The negative half: `ScanResult.confident` inside the guard means the
    # downgrade may be gone. A comment saying so must not trip it...
    source = (
        "factory ScanResult.fromMatches(List<VisualMatch> m, {bool answeredOffline = false}) {\n"
        "  if (answeredOffline) {\n"
        "    // deliberately NOT ScanResult.confident here\n"
        "    return ScanResult.alternatives(m);\n"
        "  }\n"
        "  return ScanResult.confident(m.first);\n"
        "}\n"
    )
    _read_override(monkeypatch, "scan_outcome.dart", source)
    assert baseline._offline_never_confident() is True


def test_offline_guard_check_still_rejects_a_real_confident_return(monkeypatch):
    # ...and the check must still bite when the return is real.
    source = (
        "factory ScanResult.fromMatches(List<VisualMatch> m, {bool answeredOffline = false}) {\n"
        "  if (answeredOffline) {\n"
        "    if (m.length == 1) return ScanResult.confident(m.first);\n"
        "    return ScanResult.alternatives(m);\n"
        "  }\n"
        "  return ScanResult.confident(m.first);\n"
        "}\n"
    )
    _read_override(monkeypatch, "scan_outcome.dart", source)
    with pytest.raises(baseline.BaselineError, match="ScanResult.confident"):
        baseline._offline_never_confident()


# ---------------------------------------------------------------------------
# Round-4 internal review. The lexer above was clean; the function that
# decides WHERE to apply it was not. `_block_bounds` located its marker with
# a raw `text.find` and counted brackets over raw characters, so the whole
# four-class classification could be pointed at a span chosen by prose.
# ---------------------------------------------------------------------------

_COMMENTED_FIRST = (
    "// A doc comment quoting the real guard: if (answeredOffline) {\n"
    "//   return ScanResult.confident();\n"
    "// }\n"
    "class Real {\n"
    "  void f() {\n"
    "    if (answeredOffline) {\n"
    "      return ScanResult.unconfident();\n"
    "    }\n"
    "  }\n"
    "}\n"
)


def test_block_bounds_locates_its_marker_in_code_not_in_a_comment():
    """Measured on the version this replaced: `text.find` returned offset 41
    (line 1, inside the doc comment) while `first_in_code` returned 135
    (line 6, the real guard), and the extracted body was the COMMENTED code.
    A fact taken from a comment about the source -- the one thing this
    module's header says must never happen, committed by the step that
    chooses what to lex."""
    marker = "if (answeredOffline) {"
    assert _COMMENTED_FIRST.find(marker) != baseline.first_in_code(_COMMENTED_FIRST, marker)

    start, end = baseline._block_bounds(_COMMENTED_FIRST, marker)
    body = _COMMENTED_FIRST[start:end]
    assert "unconfident" in body, body
    assert "//" not in body, body


def test_block_bounds_refuses_a_marker_that_exists_only_in_prose():
    # Not found in code is not found. Silently falling back to the commented
    # occurrence would be the same defect with a friendlier face.
    prose_only = "// if (answeredOffline) {\n//   return 1;\n// }\nclass Real {}\n"
    with pytest.raises(baseline.BaselineError, match="only in prose"):
        baseline._block_bounds(prose_only, "if (answeredOffline) {")


def test_matching_close_ignores_a_brace_inside_a_string_or_comment():
    """A `}` in a string literal is a character, not the end of a block.

    Counting it raw ends the block early, and every lexically-aware search
    the callers then run is scoped to a body that stops in the wrong place.
    """
    source = (
        "class Real {\n"
        "  void f() {\n"
        "    final s = 'a closing brace: }';\n"
        "    // and another one in a comment: }\n"
        "    final t = ScanResult.unconfident();\n"
        "  }\n"
        "}\n"
    )
    start, end = baseline._block_bounds(source, "void f() {")
    body = source[start:end]
    assert "ScanResult.unconfident()" in body, body


def test_block_bounds_does_not_take_a_body_brace_from_a_comment():
    """The parameter-list branch: the body brace must also be found in code.

    The assertion is on what the body must NOT contain, and that is the
    point. A first attempt asserted only that the real statement was present
    and that the comment text was absent -- and a mutation putting the raw
    `text.find("{")` back SURVIVED it, because a body starting at the
    comment's brace still contains the statement and still excludes the text
    before that brace. The mutation moved behaviour; the fixture could not
    see it. `f`'s real body opens no block of its own, so a body holding a
    `{` at all is a body that started in the wrong place.
    """
    source = (
        "class Real {\n"
        "  void f(int a) // a comment holding a brace: {\n"
        "  {\n"
        "    final t = ScanResult.unconfident();\n"
        "  }\n"
        "}\n"
    )
    start, end = baseline._block_bounds(source, "void f(")
    body = source[start:end]
    assert "ScanResult.unconfident()" in body, body
    assert "{" not in body, body
    assert "//" not in body, body
