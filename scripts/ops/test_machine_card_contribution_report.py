# -*- coding: utf-8 -*-
"""MRD-07: what `aggregate()` actually promises, exercised without Firestore.

The network half of `machine_card_contribution_report.py` -- `find_machine_card_docs`,
`access_token` -- has no local test, matching `strip_health_from_profiles.py`'s
own precedent (a live REST call is not something a unit test should be
faking its way around). What IS pure -- decoding, aggregating, ranking --
gets exercised here, because that is the part a wrong answer would be
silent about: a report that quietly undercounts one machine's real demand
looks identical to a correct one until someone reads it wrong.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from machine_card_contribution_report import (  # noqa: E402
    aggregate,
    parse_card_doc,
    render,
    _decode_value,
    _display_name,
    _earlier,
    _later,
)


def _card(id_, name, times_seen, *, uid, status='preparing',
          first_seen='2026-08-01T00:00:00.000Z',
          last_seen='2026-08-01T00:00:00.000Z'):
    return {
        'id': id_,
        'name': name,
        'timesSeen': times_seen,
        'status': status,
        'firstSeenAt': first_seen,
        'lastSeenAt': last_seen,
        'uid': uid,
    }


class TestAggregate:
    def test_sums_sightings_across_different_users(self):
        rows = aggregate([
            _card('leg_press', 'Leg Press', 3, uid='u1'),
            _card('leg_press', 'Leg Press', 2, uid='u2'),
        ])
        assert len(rows) == 1
        assert rows[0].total_sightings == 5
        assert rows[0].distinct_user_count == 2

    def test_two_different_machines_stay_separate_rows(self):
        rows = aggregate([
            _card('leg_press', 'Leg Press', 3, uid='u1'),
            _card('cable_fly', 'Cable Fly', 1, uid='u1'),
        ])
        assert {r.id for r in rows} == {'leg_press', 'cable_fly'}

    def test_ranks_the_most_photographed_machine_first(self):
        rows = aggregate([
            _card('a', 'A', 1, uid='u1'),
            _card('b', 'B', 9, uid='u1'),
            _card('c', 'C', 4, uid='u2'),
        ])
        assert [r.id for r in rows] == ['b', 'c', 'a']

    def test_a_tie_on_total_sightings_breaks_on_distinct_users(self):
        # 6 sightings from one enthusiastic photographer must not outrank 6
        # sightings spread across three separate people -- the repository's
        # own reason for existing is "what do people, plural, want filmed".
        # Named so alphabetical order alone would rank them the WRONG way
        # (name-only tiebreak would put "AAA Solo" first) -- a real test of
        # the distinct-user tiebreak, not one that happens to agree with it.
        rows = aggregate([
            _card('solo', 'AAA Solo', 6, uid='u1'),
            _card('shared', 'ZZZ Shared', 2, uid='u1'),
            _card('shared', 'ZZZ Shared', 2, uid='u2'),
            _card('shared', 'ZZZ Shared', 2, uid='u3'),
        ])
        assert [r.id for r in rows] == ['shared', 'solo']

    def test_first_seen_is_the_earliest_and_last_seen_the_latest_across_users(self):
        rows = aggregate([
            _card('a', 'A', 1, uid='u1', first_seen='2026-08-10T00:00:00.000Z',
                  last_seen='2026-08-10T00:00:00.000Z'),
            _card('a', 'A', 1, uid='u2', first_seen='2026-08-01T00:00:00.000Z',
                  last_seen='2026-08-15T00:00:00.000Z'),
        ])
        assert rows[0].first_seen_at == '2026-08-01T00:00:00.000Z'
        assert rows[0].last_seen_at == '2026-08-15T00:00:00.000Z'

    def test_a_card_resolved_by_every_sighting_is_flagged_resolved(self):
        rows = aggregate([_card('a', 'A', 1, uid='u1', status='inCatalog')])
        assert rows[0].is_still_unresolved is False

    def test_a_card_still_preparing_in_at_least_one_sighting_stays_unresolved(self):
        # Mixed statuses for one card id would mean one user's sighting
        # somehow saw it promoted while another's didn't -- not possible
        # under today's write path (nothing ever writes inCatalog/declined,
        # per the D0 note), but the aggregate must not hide a machine from
        # the report on partial evidence that it's resolved everywhere.
        rows = aggregate([
            _card('a', 'A', 1, uid='u1', status='preparing'),
            _card('a', 'A', 1, uid='u2', status='inCatalog'),
        ])
        assert rows[0].is_still_unresolved is True
        assert rows[0].statuses == {'preparing', 'inCatalog'}


class TestParseCardDoc:
    def test_decodes_the_shape_MachineCard_toJson_actually_writes(self):
        doc = {
            'name': 'projects/p/databases/(default)/documents/users/u1/machine_cards/leg_press',
            'fields': {
                'id': {'stringValue': 'leg_press'},
                'name': {'stringValue': 'Leg Press'},
                'summary': {'stringValue': 'A machine.'},
                'uses': {'arrayValue': {'values': [{'stringValue': 'quads'}]}},
                'timesSeen': {'integerValue': '3'},
                'status': {'stringValue': 'preparing'},
                'firstSeenAt': {'stringValue': '2026-08-01T00:00:00.000Z'},
            },
        }
        parsed = parse_card_doc(doc)
        # summary/uses are present in the raw doc (a full, unfiltered fetch
        # could still include them even though the live query's `select`
        # never requests them) and must be correctly ignored, not surfaced.
        assert parsed == {
            'id': 'leg_press',
            'name': 'Leg Press',
            'timesSeen': 3,
            'status': 'preparing',
            'firstSeenAt': '2026-08-01T00:00:00.000Z',
            'lastSeenAt': None,
            'uid': 'u1',
        }

    def test_skips_a_document_whose_timesSeen_is_a_boolean(self):
        # bool is a subclass of int in Python -- without an explicit check,
        # a hand-edited timesSeen: true would pass isinstance(x, int) and
        # silently contribute a phantom sighting instead of being skipped
        # as malformed (python-reviewer finding).
        doc = {
            'name': 'projects/p/databases/(default)/documents/users/u1/machine_cards/x',
            'fields': {
                'id': {'stringValue': 'x'},
                'name': {'stringValue': 'X'},
                'timesSeen': {'booleanValue': True},
            },
        }
        assert parse_card_doc(doc) is None

    def test_decodes_a_timestampValue_date_field(self):
        # firestore_machine_cards.dart's own read side documents dates
        # arriving as native Firestore Timestamps ("what a console edit or
        # a server-side write produces"), not only the ISO strings the app
        # itself writes.
        doc = {
            'name': 'projects/p/databases/(default)/documents/users/u1/machine_cards/x',
            'fields': {
                'id': {'stringValue': 'x'},
                'name': {'stringValue': 'X'},
                'timesSeen': {'integerValue': '1'},
                'firstSeenAt': {'timestampValue': '2026-08-01T00:00:00.000000Z'},
            },
        }
        parsed = parse_card_doc(doc)
        assert parsed['firstSeenAt'] == '2026-08-01T00:00:00.000000Z'

    def test_skips_a_document_missing_a_required_field_rather_than_guessing(self):
        doc = {
            'name': 'projects/p/databases/(default)/documents/users/u1/machine_cards/x',
            'fields': {'name': {'stringValue': 'X'}},  # no id, no timesSeen
        }
        assert parse_card_doc(doc) is None

    def test_skips_a_document_whose_path_has_no_uid(self):
        # Should not happen for real writes (always users/{uid}/machine_cards/{id}),
        # but a malformed path must not crash the report or silently attribute
        # the sighting to nobody.
        doc = {
            'name': 'projects/p/databases/(default)/documents/machine_cards/x',
            'fields': {
                'id': {'stringValue': 'x'},
                'name': {'stringValue': 'X'},
                'timesSeen': {'integerValue': '1'},
            },
        }
        assert parse_card_doc(doc) is None


class TestDecodeValue:
    @pytest.mark.parametrize('raw,expected', [
        ({'stringValue': 'hi'}, 'hi'),
        ({'integerValue': '7'}, 7),
        ({'doubleValue': 0.5}, 0.5),
        ({'booleanValue': True}, True),
        ({'nullValue': None}, None),
        ({'arrayValue': {'values': [{'stringValue': 'a'}, {'integerValue': '2'}]}}, ['a', 2]),
        ({'mapValue': {'fields': {'k': {'stringValue': 'v'}}}}, {'k': 'v'}),
        ({'timestampValue': '2026-08-01T00:00:00.000000Z'}, '2026-08-01T00:00:00.000000Z'),
    ])
    def test_decodes_every_value_shape_MachineCard_can_produce(self, raw, expected):
        assert _decode_value(raw) == expected


class TestEarlierLater:
    def test_regression_variable_width_fractional_seconds_do_not_sort_backwards(self):
        # Dart's toIso8601String() prints milliseconds always, microseconds
        # only when nonzero -- so the SAME millisecond can appear as
        # "...500Z" (zero microseconds) or "...500001Z" (nonzero), and a
        # raw string comparison reads the shorter one as "later" because
        # 'Z' > '0' at the first differing character. This is the exact
        # scenario that made the old string-comparison version wrong.
        zero_micros = '2026-08-19T09:00:00.500Z'
        nonzero_micros = '2026-08-19T09:00:00.500001Z'  # 1 microsecond later
        assert _later(zero_micros, nonzero_micros) == nonzero_micros
        assert _earlier(zero_micros, nonzero_micros) == zero_micros
        # and the reverse call order, since the bug was order-dependent too
        assert _later(nonzero_micros, zero_micros) == nonzero_micros
        assert _earlier(nonzero_micros, zero_micros) == zero_micros

    def test_none_on_either_side_defers_to_whichever_is_real(self):
        assert _earlier(None, '2026-08-19T09:00:00.000Z') == '2026-08-19T09:00:00.000Z'
        assert _earlier('2026-08-19T09:00:00.000Z', None) == '2026-08-19T09:00:00.000Z'
        assert _earlier(None, None) is None

    def test_an_unparseable_string_loses_to_a_real_one_rather_than_crashing(self):
        assert _earlier('not a date', '2026-08-19T09:00:00.000Z') == '2026-08-19T09:00:00.000Z'
        assert _later('not a date', '2026-08-19T09:00:00.000Z') == '2026-08-19T09:00:00.000Z'


class TestDisplayName:
    def test_a_short_name_is_shown_in_full(self):
        assert _display_name('Leg Press') == 'Leg Press'

    def test_a_long_name_is_truncated_with_a_visible_marker(self):
        long_name = 'A' * 40
        out = _display_name(long_name)
        assert len(out) == 32
        assert out.endswith('~')

    def test_two_names_agreeing_for_32_characters_are_still_distinguishable_by_id(self):
        # render() itself can't fully disambiguate two names this similar,
        # but aggregate() must never merge them -- the truncation marker is
        # a display hint, not a substitute for keying on the real id.
        shared_prefix = 'B' * 40
        rows = aggregate([
            {'id': 'a', 'name': shared_prefix + 'X', 'timesSeen': 1, 'status': 'preparing',
             'firstSeenAt': None, 'lastSeenAt': None, 'uid': 'u1'},
            {'id': 'b', 'name': shared_prefix + 'Y', 'timesSeen': 1, 'status': 'preparing',
             'firstSeenAt': None, 'lastSeenAt': None, 'uid': 'u1'},
        ])
        assert {r.id for r in rows} == {'a', 'b'}


class TestRender:
    def test_never_prints_a_uid_or_document_path(self):
        rows = aggregate([_card('leg_press', 'Leg Press', 3, uid='some-real-uid-123')])
        out = render(rows, top=25)
        assert 'some-real-uid-123' not in out
        assert 'machine_cards' not in out

    def test_respects_the_top_n_cutoff(self):
        rows = aggregate([
            _card('a', 'A', 3, uid='u1'),
            _card('b', 'B', 2, uid='u1'),
            _card('c', 'C', 1, uid='u1'),
        ])
        out = render(rows, top=2)
        assert 'A' in out and 'B' in out
        assert 'C' not in out
