# -*- coding: utf-8 -*-
"""Tier A item 7 (OBS-1 item 7 / row 26): does this sweep touch only what it says it does.

`strip_health_from_profiles.py` deletes production user data. The loudest,
most concrete gap this file closes is that the script had no test at all --
nothing proved `has_target_fields()` or the update mask `strip()` sends
actually stay confined to `health`, `lifestyle.smoking` and
`lifestyle.alcohol`, as the module's own doc comment claims.

Matching this repo's own established convention (`test_machine_card_contribution_report.py`'s
own doc comment): the live REST call (`find_profiles`, `strip`'s actual network
send, `access_token`) is not faked in a unit test. What IS pure -- deciding
whether a document still carries a targeted field, and building the exact
request that would remove them -- gets exercised here, because a sweep that
silently detects (or deletes) the wrong fields is exactly the kind of defect
a live smoke test would not catch until real data was already gone.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
import strip_health_from_profiles as shp  # noqa: E402
from strip_health_from_profiles import (  # noqa: E402
    TARGET_PATHS,
    _strip_url,
    exit_code,
    find_profiles,
    has_target_fields,
    is_expected_profile_path,
    main,
)


def _doc(fields: dict) -> dict:
    return {'name': 'projects/p/databases/(default)/documents/users/u1/profile/main',
            'fields': fields}


class TestTargetPaths:
    def test_pinned_to_exactly_the_three_declared_fields(self):
        # A test pinning this constant is the direct guard against the sweep
        # quietly growing to cover a field nobody decided to delete.
        assert TARGET_PATHS == ('health', 'lifestyle.smoking', 'lifestyle.alcohol')


class TestIsExpectedProfilePath:
    # GPT-PM round 1 BLOCKER, 2026-09-16: the collection-group query matches
    # ANY collection literally named "profile" anywhere in the database, not
    # specifically users/{uid}/profile/main -- this is the fail-closed guard
    # find_profiles() now filters every result through.

    def test_the_real_app_shape_is_accepted(self):
        name = ('projects/p/databases/(default)/documents/'
                'users/1W6hoUVfU9hdBTEON5c2UWyhkZH2/profile/main')
        assert is_expected_profile_path(name) is True

    def test_a_profile_document_under_an_unrelated_collection_is_rejected(self):
        # The exact decoy shape GPT-PM's finding named: a future/unrelated
        # top-level collection that happens to have its own "profile"
        # subcollection must never be swept, no matter what fields it holds.
        name = ('projects/p/databases/(default)/documents/'
                'organizations/x/profile/main')
        assert is_expected_profile_path(name) is False

    def test_a_profile_document_nested_deeper_than_expected_is_rejected(self):
        name = ('projects/p/databases/(default)/documents/'
                'users/u1/somethingElse/y/profile/main')
        assert is_expected_profile_path(name) is False

    def test_a_document_id_other_than_main_is_rejected(self):
        name = ('projects/p/databases/(default)/documents/'
                'users/u1/profile/backup')
        assert is_expected_profile_path(name) is False

    def test_a_bare_users_collection_document_with_no_profile_segment_is_rejected(self):
        name = 'projects/p/databases/(default)/documents/users/u1'
        assert is_expected_profile_path(name) is False

    def test_a_name_with_no_documents_marker_at_all_is_rejected(self):
        assert is_expected_profile_path('not-a-firestore-resource-name') is False


class TestHasTargetFields:
    def test_health_block_present(self):
        assert has_target_fields(_doc({'health': {'mapValue': {'fields': {
            'conditions': {'arrayValue': {'values': []}},
        }}}})) is True

    def test_health_block_present_but_empty_is_still_true(self):
        # "Presence, not truthiness" per the module's own docstring -- an
        # empty health map is still a field the app should not be
        # maintaining, and a stale document must not slip past a truthiness
        # check just because the last migration already cleared its values.
        assert has_target_fields(_doc({'health': {'mapValue': {'fields': {}}}})) is True

    def test_lifestyle_smoking_present(self):
        doc = _doc({'lifestyle': {'mapValue': {'fields': {
            'smoking': {'stringValue': 'never'},
        }}}})
        assert has_target_fields(doc) is True

    def test_lifestyle_smoking_present_but_null_is_still_true(self):
        # Presence, not truthiness, applies to the lifestyle sub-fields too --
        # `has_target_fields` is a pure key-membership check, but only a
        # test exercising a nullValue proves that (python-reviewer finding:
        # this case was covered for `health` but not for the two lifestyle
        # sub-fields, an asymmetric gap in exactly this file's own subject).
        doc = _doc({'lifestyle': {'mapValue': {'fields': {
            'smoking': {'nullValue': None},
        }}}})
        assert has_target_fields(doc) is True

    def test_lifestyle_alcohol_present(self):
        doc = _doc({'lifestyle': {'mapValue': {'fields': {
            'alcohol': {'stringValue': 'occasionally'},
        }}}})
        assert has_target_fields(doc) is True

    def test_lifestyle_alcohol_present_but_null_is_still_true(self):
        doc = _doc({'lifestyle': {'mapValue': {'fields': {
            'alcohol': {'nullValue': None},
        }}}})
        assert has_target_fields(doc) is True

    def test_both_lifestyle_subfields_present(self):
        doc = _doc({'lifestyle': {'mapValue': {'fields': {
            'smoking': {'stringValue': 'never'},
            'alcohol': {'stringValue': 'occasionally'},
        }}}})
        assert has_target_fields(doc) is True

    def test_a_profile_with_none_of_the_three_fields_is_false(self):
        doc = _doc({
            'height': {'doubleValue': 180.0},
            'weight': {'doubleValue': 82.0},
            'goals': {'arrayValue': {'values': [{'stringValue': 'strength'}]}},
        })
        assert has_target_fields(doc) is False

    def test_an_empty_document_is_false(self):
        assert has_target_fields(_doc({})) is False

    def test_lifestyle_present_but_without_smoking_or_alcohol_is_false(self):
        # This is the "nothing broader" case that matters most: a
        # `lifestyle` map exists (so a shallow "is lifestyle present" check
        # would wrongly flag it), but neither targeted subfield does.
        # `has_target_fields` must look inside the map, not just at its key.
        doc = _doc({'lifestyle': {'mapValue': {'fields': {
            'diet': {'stringValue': 'omnivore'},
            'sleepHours': {'integerValue': '7'},
        }}}})
        assert has_target_fields(doc) is False

    def test_fitness_info_fields_alone_never_trigger_a_false_positive(self):
        # Height, weight, goals, level, equipment and motivation are Play
        # "Fitness info", deliberately left on the server -- see the
        # module's own "WHAT IT TOUCHES" doc comment. A regression here
        # would mean the sweep starts flagging profiles it was never meant
        # to touch.
        doc = _doc({
            'height': {'doubleValue': 165.0},
            'weight': {'doubleValue': 60.0},
            'level': {'stringValue': 'intermediate'},
            'equipment': {'arrayValue': {'values': [{'stringValue': 'dumbbells'}]}},
            'motivation': {'stringValue': 'general fitness'},
        })
        assert has_target_fields(doc) is False

    def test_a_document_with_no_fields_key_at_all_is_false(self):
        # Firestore's REST shape omits `fields` entirely for a document with
        # no fields at all -- must not KeyError.
        assert has_target_fields({'name': 'projects/p/.../profile/main'}) is False


class TestStripUrl:
    def test_mask_is_the_exact_expected_query_string(self):
        # An exact-equality assertion, not just count()==3 plus substring
        # checks -- a malformed separator (e.g. joining with '' instead of
        # '&') would still leave all 3 substrings present and the count at 3,
        # and pass the weaker version of this test undetected (python-reviewer
        # finding).
        name = 'projects/p/databases/(default)/documents/users/u1/profile/main'
        url = _strip_url(name)
        # `(` and `)` are not in urllib's default-safe set, so the fixed
        # "(default)" database segment comes out percent-encoded too --
        # verified live against real Firestore (2026-09-16, a read-only GET)
        # that this resolves identically to the unescaped literal.
        assert url == (
            'https://firestore.googleapis.com/v1/'
            'projects/p/databases/%28default%29/documents/users/u1/profile/main'
            '?updateMask.fieldPaths=health'
            '&updateMask.fieldPaths=lifestyle.smoking'
            '&updateMask.fieldPaths=lifestyle.alcohol'
        )

    def test_mask_contains_exactly_the_three_declared_paths_and_nothing_else(self):
        url = _strip_url(
            'projects/p/databases/(default)/documents/users/u1/profile/main')
        assert url.count('updateMask.fieldPaths=') == 3
        assert 'updateMask.fieldPaths=health' in url
        assert 'updateMask.fieldPaths=lifestyle.smoking' in url
        assert 'updateMask.fieldPaths=lifestyle.alcohol' in url

    def test_mask_is_built_from_target_paths_not_a_second_hardcoded_list(self):
        # A mutation swapping TARGET_PATHS for a wider tuple must show up
        # here immediately -- this is the direct guard the refactor exists
        # to make possible without faking the live call.
        url = _strip_url('projects/p/databases/(default)/documents/x')
        for path in TARGET_PATHS:
            assert f'updateMask.fieldPaths={path}' in url

    def test_the_document_path_itself_is_preserved_in_the_url(self):
        # No '(', ')' in this name -- nothing for quoting to change, so the
        # literal name is still a valid prefix to assert against.
        name = 'projects/p/databases/default/documents/users/u1/profile/main'
        url = _strip_url(name)
        assert url.startswith(f'https://firestore.googleapis.com/v1/{name}?')

    def test_a_query_character_in_the_document_name_cannot_inject_a_fourth_mask_param(self):
        # Defense in depth (security review, 2026-09-16): Firestore document
        # ids are not restricted to Firebase Auth's alphanumeric uid charset,
        # so a name containing '?' or '&' must not be able to smuggle in an
        # extra updateMask.fieldPaths= param -- it must come out escaped,
        # still exactly 3 real mask params.
        name = 'projects/p/databases/(default)/documents/users/weird&uid?x/profile/main'
        url = _strip_url(name)
        assert url.count('updateMask.fieldPaths=') == 3
        assert '&uid?x' not in url

    def test_the_request_body_a_caller_would_send_is_never_this_function_s_job(self):
        # strip() sends payload={'fields': {}} separately -- _strip_url only
        # ever returns a URL string, never anything resembling a body, so a
        # future change cannot accidentally start smuggling field values
        # through the one function this module never logs the output of.
        url = _strip_url('projects/p/databases/(default)/documents/x')
        assert isinstance(url, str)
        assert '{' not in url and '}' not in url


class TestExitCode:
    # GPT-PM round 1 MAJOR, 2026-09-16: --fail-on-residue is the one new
    # behavior a future scheduled check depends on, and had no test proving
    # it. exit_code() is the pure decision main() defers to, so these prove
    # the actual contract a monitor would rely on.

    def test_dry_run_no_residue_no_flag_is_zero(self):
        assert exit_code(apply=False, stale_count=0, fail_on_residue=False) == 0

    def test_dry_run_no_residue_with_flag_is_still_zero(self):
        assert exit_code(apply=False, stale_count=0, fail_on_residue=True) == 0

    def test_dry_run_residue_without_the_flag_is_zero(self):
        # This is the exact gap that made a scheduled check meaningless
        # before this flag existed -- dry-run residue alone must NOT fail
        # unless the caller opted in, or every human's routine local dry run
        # would start exiting nonzero too.
        assert exit_code(apply=False, stale_count=39, fail_on_residue=False) == 0

    def test_dry_run_residue_with_the_flag_is_one(self):
        # The behavior a scheduled monitor actually depends on.
        assert exit_code(apply=False, stale_count=39, fail_on_residue=True) == 1

    def test_apply_with_no_failures_is_zero_regardless_of_the_flag(self):
        assert exit_code(apply=True, stale_count=5, fail_on_residue=True,
                          failed_count=0) == 0
        assert exit_code(apply=True, stale_count=5, fail_on_residue=False,
                          failed_count=0) == 0

    def test_apply_with_any_failure_is_one_regardless_of_the_flag(self):
        # A real write failure is always an error -- --fail-on-residue only
        # changes what a DRY RUN finding counts as; it never softens --apply.
        assert exit_code(apply=True, stale_count=5, fail_on_residue=False,
                          failed_count=1) == 1
        assert exit_code(apply=True, stale_count=5, fail_on_residue=True,
                          failed_count=1) == 1


def _run_query_response(names):
    return [{'document': {'name': n, 'fields': {}}} for n in names]


class TestFindProfilesAppliesTheBoundary:
    # GPT-PM round 2 MAJOR, 2026-09-16: is_expected_profile_path() itself was
    # tested, but nothing proved find_profiles() actually calls it -- a
    # refactor could silently drop the filtering line while every pure
    # predicate test stayed green. This monkeypatches only the network
    # transport (api()), never simulates real HTTP behavior, and exercises
    # find_profiles()'s own filtering line directly.

    def test_a_decoy_document_outside_users_profile_main_is_excluded(self, monkeypatch, capsys):
        allowed = ('projects/p/databases/(default)/documents/'
                   'users/u1/profile/main')
        decoy = ('projects/p/databases/(default)/documents/'
                 'organizations/x/profile/main')

        def fake_api(url, token, method='GET', payload=None, **kw):
            return _run_query_response([allowed, decoy])

        monkeypatch.setattr(shp, 'api', fake_api)
        docs = find_profiles('p', 'fake-token')
        assert [d['name'] for d in docs] == [allowed]
        assert 'WARNING' in capsys.readouterr().out

    def test_no_decoys_produces_no_warning(self, monkeypatch, capsys):
        allowed = ('projects/p/databases/(default)/documents/'
                   'users/u1/profile/main')

        def fake_api(url, token, method='GET', payload=None, **kw):
            return _run_query_response([allowed])

        monkeypatch.setattr(shp, 'api', fake_api)
        docs = find_profiles('p', 'fake-token')
        assert [d['name'] for d in docs] == [allowed]
        assert 'WARNING' not in capsys.readouterr().out


class TestMainCliWiring:
    # GPT-PM round 2 MAJOR, 2026-09-16: exit_code() itself was tested, but
    # nothing proved --fail-on-residue is actually wired to argparse and to
    # main()'s real exit path. Network calls are stubbed (access_token,
    # find_profiles), never faked at the HTTP level -- this proves the CLI
    # wiring, not the transport.

    def _run(self, monkeypatch, argv, *, stale_names):
        monkeypatch.setattr(sys, 'argv', ['strip_health_from_profiles.py'] + argv)
        monkeypatch.setattr(shp, 'access_token', lambda: 'fake-token')
        monkeypatch.setattr(
            shp, 'find_profiles',
            lambda project, token: _stale_docs(stale_names))
        with pytest.raises(SystemExit) as exc_info:
            main()
        return exc_info.value.code

    def test_residue_with_the_flag_exits_1(self, monkeypatch):
        code = self._run(monkeypatch, ['--project', 'default', '--fail-on-residue'],
                          stale_names=['x'])
        assert code == 1

    def test_residue_without_the_flag_exits_0(self, monkeypatch):
        code = self._run(monkeypatch, ['--project', 'default'], stale_names=['x'])
        assert code == 0

    def test_zero_residue_with_the_flag_exits_0(self, monkeypatch):
        code = self._run(monkeypatch, ['--project', 'default', '--fail-on-residue'],
                          stale_names=[])
        assert code == 0


def _stale_docs(names):
    return [{'name': ('projects/p/databases/(default)/documents/'
                       f'users/{n}/profile/main'),
             'fields': {'health': {'mapValue': {'fields': {}}}}}
            for n in names]
