import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/data_export/data_export.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart'
    show ExerciseDifficulty;
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';

/// L0c's pure core: assembling everything the app has stored about one user
/// into a JSON shape, with no platform dependency to fake.
///
/// The behaviour under test is what makes this an export rather than a
/// convenience toy: every field actually stored ends up in it (through
/// `UserProfile.toJson`, the same serializer Firestore writes with), and the
/// one thing that must NOT be in it -- the encrypted photo bytes -- stays out
/// even when a caller hands in photo metadata that carries plausible-looking
/// internal fields.

UserProfile _profile() => const UserProfile(
      uid: 'u1',
      personal: PersonalInfo(age: 30, heightCm: 180),
      health: HealthHistory(injuries: [
        Injury(bodyPart: 'left knee', type: 'sprain', region: InjuryRegion.knee),
      ]),
    );

WorkoutLogEntry _log(String id) => WorkoutLogEntry(
      id: id,
      exerciseId: 'squat',
      exerciseTitle: 'Squat',
      completedAt: DateTime(2026, 1, 1),
      durationMinutes: 30,
      weightKg: 60,
      repsCompleted: 8,
    );

ScheduledSession _session(String id) => ScheduledSession(
      id: id,
      exerciseId: 'squat',
      exerciseTitle: 'Squat',
      scheduledFor: DateTime(2026, 1, 2),
      durationMinutes: 30,
    );

Programme _programme(String id) => Programme(
      id: id,
      templateId: 'strength_base',
      title: 'Силовая база',
      goal: ProgrammeGoal.strength,
      level: ExerciseDifficulty.intermediate,
      weeks: 8,
      daysPerWeek: 4,
      startedAt: DateTime(2026, 1, 1),
    );

ProgressPhoto _photo(String id) => ProgressPhoto(
      id: id,
      takenAt: DateTime(2026, 1, 3),
      storagePath: 'users/u1/photos/$id.enc',
      keyFingerprint: 'fp_real',
      weightKg: 82.5,
      note: 'after week 4',
    );

void main() {
  group('buildExport', () {
    test('carries the profile through the same serializer Firestore uses',
        () {
      final out = buildExport(
        profile: _profile(),
        workoutLogs: const [],
        scheduledSessions: const [],
        programmes: const [],
        progressPhotos: const [],
      );
      // Not a re-derivation -- literally the same map UserProfile.toJson()
      // produces, plus the uid. Two implementations of this shape drifting
      // is exactly the bug S1a fixed once already for Injury alone.
      expect(out['profile'], {..._profile().toJson(), 'uid': 'u1'});
    });

    test('every workout log and every session is included, unwindowed', () {
      final logs = List.generate(5, (i) => _log('log_$i'));
      final sessions = List.generate(5, (i) => _session('sess_$i'));
      final out = buildExport(
        profile: _profile(),
        workoutLogs: logs,
        scheduledSessions: sessions,
        programmes: const [],
        progressPhotos: const [],
      );
      expect(out['workoutLogs'], hasLength(5));
      expect(out['scheduledSessions'], hasLength(5));
    });

    // The programme entity (Gate P) is a fourth first-class collection
    // alongside logs/sessions/photos -- a user who enrolled in a programme
    // and never got it back in their own export would have real data this
    // function silently dropped.
    test('every enrolled programme is included', () {
      final programmes = List.generate(3, (i) => _programme('prog_$i'));
      final out = buildExport(
        profile: _profile(),
        workoutLogs: const [],
        scheduledSessions: const [],
        programmes: programmes,
        progressPhotos: const [],
      );
      expect(out['programmes'], hasLength(3));
      final first = (out['programmes'] as List).first as Map;
      expect(first['id'], 'prog_0');
      expect(first['title'], 'Силовая база');
    });

    test('a photo carries its metadata but never its storage path or key',
        () {
      // The whole reason this function exists rather than just calling
      // toJson() on everything: a naive `.toJson()` sweep would have
      // included storagePath and keyFingerprint, and packaging either into a
      // shareable file is a materially different promise than the app makes
      // today -- the AES key never otherwise leaves the device.
      final out = buildExport(
        profile: _profile(),
        workoutLogs: const [],
        scheduledSessions: const [],
        programmes: const [],
        progressPhotos: [_photo('p1')],
      );
      final photo = (out['progressPhotos'] as List).single as Map;
      expect(photo['id'], 'p1');
      expect(photo['weightKg'], 82.5);
      expect(photo['note'], 'after week 4');
      expect(photo.containsKey('storagePath'), isFalse);
      expect(photo.containsKey('keyFingerprint'), isFalse);
    });

    test('marks itself complete by default', () {
      final out = buildExport(
        profile: _profile(),
        workoutLogs: const [],
        scheduledSessions: const [],
        programmes: const [],
        progressPhotos: const [],
      );
      expect(out['progressPhotosIncomplete'], isFalse);
    });

    test('an incomplete photo read is marked, not read as "you have none"',
        () {
      // The finding this closes: a stalled read that falls back to an empty
      // list must not look identical to a user who genuinely has zero
      // photos. Someone auditing a GDPR export has no other way to tell.
      final out = buildExport(
        profile: _profile(),
        workoutLogs: const [],
        scheduledSessions: const [],
        programmes: const [],
        progressPhotos: const [],
        progressPhotosIncomplete: true,
      );
      expect(out['progressPhotosIncomplete'], isTrue);
      expect(
        (out['notes'] as List).join(' '),
        contains('may be incomplete'),
      );
    });

    test('says plainly that photo image data is not included', () {
      final out = buildExport(
        profile: _profile(),
        workoutLogs: const [],
        scheduledSessions: const [],
        programmes: const [],
        progressPhotos: const [],
      );
      expect((out['notes'] as List).join(' '), contains('not included'));
    });

    /// The note used to continue "The encryption key never leaves this
    /// device." That sentence was written into a file the user downloads and
    /// keeps -- the most durable copy of the claim in the whole product --
    /// while `AesPhotoCipher` had no caller and the only bound repository was
    /// the in-memory mock. Nothing is encrypted and there is no key.
    ///
    /// Asserted as the absence of a word rather than as the exact note text,
    /// so that R7 restoring a key sentence has to come past this test on
    /// purpose.
    test('claims nothing about a key while nothing is encrypted', () {
      final out = buildExport(
        profile: _profile(),
        workoutLogs: const [],
        scheduledSessions: const [],
        programmes: const [],
        progressPhotos: const [],
        progressPhotosIncomplete: true,
      );
      final notes = (out['notes'] as List).join(' ').toLowerCase();
      expect(notes, isNot(contains('key')));
      expect(notes, isNot(contains('encrypt')));
    });

    test('carries a format version, for a reader written before the next '
        'field is added', () {
      final out = buildExport(
        profile: _profile(),
        workoutLogs: const [],
        scheduledSessions: const [],
        programmes: const [],
        progressPhotos: const [],
      );
      expect(out['exportFormatVersion'], 1);
    });
  });

  group('buildExportJson', () {
    test('is valid, round-trippable JSON', () {
      final json = buildExportJson(
        profile: _profile(),
        workoutLogs: [_log('a')],
        scheduledSessions: [_session('b')],
        programmes: [_programme('p')],
        progressPhotos: [_photo('c')],
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['profile']['uid'], 'u1');
      expect((decoded['workoutLogs'] as List), hasLength(1));
    });

    test('is indented, for a user who opens it in a text app', () {
      final json = buildExportJson(
        profile: _profile(),
        workoutLogs: const [],
        scheduledSessions: const [],
        programmes: const [],
        progressPhotos: const [],
      );
      expect(json, contains('\n  '));
    });
  });
}
