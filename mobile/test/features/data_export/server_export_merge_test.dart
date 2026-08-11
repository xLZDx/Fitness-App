import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/data_export/data_export.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// A3 — the export file must carry the server-held half, and must say so when
/// it could not.
UserProfile _profile() => const UserProfile(uid: 'u1');

Map<String, dynamic> _export({Map<String, dynamic>? server}) => buildExport(
      profile: _profile(),
      workoutLogs: const [],
      scheduledSessions: const [],
      programmes: const [],
      progressPhotos: const [],
      server: server,
    );

void main() {
  test('the server half lands in the file under its own key', () {
    final data = _export(server: {
      'coachBookings': [
        {'id': 'b1'}
      ],
      'debugSessions': [
        {'id': 'd1'}
      ],
      'subscription': {'tier': 'standard'},
    });

    expect(data['serverIncomplete'], isFalse);
    expect((data['server'] as Map)['coachBookings'], hasLength(1));
    // The three the phone cannot read on its own are the whole reason A3 is a
    // Cloud Function; if they stop arriving, this is what notices.
    expect((data['server'] as Map)['debugSessions'], hasLength(1));
    expect((data['server'] as Map)['subscription'], isNotNull);
  });

  test('a failed server call is declared, not silently omitted', () {
    // The failure mode this guards: an export that looks complete while it is
    // short — the same class of lie `progressPhotosIncomplete` already exists
    // to prevent.
    final data = _export(server: null);

    expect(data['serverIncomplete'], isTrue);
    expect(data.containsKey('server'), isFalse);
    expect(
      (data['notes'] as List).join(' '),
      contains('could not be retrieved'),
    );
  });

  test('the note names what is missing, not just that something is', () {
    final notes = (_export(server: null)['notes'] as List).join(' ');

    for (final named in const [
      'subscriptions',
      'coach bookings',
      'equipment reports',
      'recognition history',
    ]) {
      expect(notes, contains(named));
    }
  });

  test('the whole thing still serialises', () {
    // `server` is arbitrary JSON straight off the wire; the export is written
    // to a file the user keeps, so a value that cannot encode would fail at
    // the last step of a flow the user already waited through.
    final json = buildExportJson(
      profile: _profile(),
      workoutLogs: const [],
      scheduledSessions: const [],
      programmes: const [],
      progressPhotos: const [],
      server: {
        'stats': {'total': 12},
        'coachBookings': const [],
      },
    );

    expect(jsonDecode(json)['server']['stats']['total'], 12);
  });
}
