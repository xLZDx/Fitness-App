import 'dart:convert';

import '../profile/data/profile_models.dart';
import '../programmes/data/programme.dart';
import '../progress_photos/data/progress_photo.dart';
import '../workouts/data/scheduled_session.dart';
import '../workouts/data/workout_log.dart';

/// L0c — everything the app has stored about one user, as JSON.
///
/// ## Scope
///
/// Structured, textual data: the profile (including injuries), full workout
/// history, full schedule, and progress-photo metadata. Deliberately NOT
/// included: the encrypted photo bytes themselves. Decrypting and packaging
/// binary blobs from `ProgressPhotosRepository` is a materially larger
/// feature -- a different code path with its own failure modes (the AES key
/// lives in SharedPreferences and never leaves the device, so bundling a
/// decrypted image into a shareable file changes that guarantee) -- and is
/// out of this gate's scope. [ProgressPhotoExport] carries everything about a
/// photo except the pixels, which at least lets a user audit how many they
/// have and when each was taken.
///
/// ## Why full history, not the windowed view every screen renders
///
/// `WorkoutLogRepository.watch()` and `ScheduledSessionRepository.watch()`
/// both cap at a window (N2) so a cold start does not re-download a decade of
/// history. Reusing that here would silently truncate a user's own export --
/// false confidence that "I have my data" while part of it is missing, which
/// is worse than no export at all. Both repositories' `exportAll()` reads the
/// full collection with no limit; this is the one caller allowed to pay for
/// that.
Map<String, dynamic> buildExport({
  required UserProfile profile,
  required List<WorkoutLogEntry> workoutLogs,
  required List<ScheduledSession> scheduledSessions,
  required List<Programme> programmes,
  required List<ProgressPhoto> progressPhotos,
  // True when the caller could not confirm it read every progress photo --
  // today only a stalled read (data_export_providers.dart's 5s timeout), but
  // the flag is about what the caller KNOWS, not about why. An export that
  // could not finish reading must not read the same as one that read
  // everything and found nothing: the first is "we don't know", the second
  // is "you have none", and collapsing them is a GDPR export lying about its
  // own completeness by omission.
  bool progressPhotosIncomplete = false,
  // A3. Everything only the server can read -- `debug_sessions`,
  // `coach_bookings`, `equipment_reports`, plus the subscription, machine
  // cards, recognition history, generated exercises and stats. Null when the
  // callable failed, which is NOT the same as "you have none of it": the note
  // below says so in the file the user keeps.
  Map<String, dynamic>? server,
}) {
  // One sentence, not two. The second used to read "The encryption key never
  // leaves this device", which was written into a file the user downloads and
  // keeps -- the most durable copy of the claim anywhere in the product, and
  // there is no key: `AesPhotoCipher` has no caller and the only repository
  // bound is the in-memory mock. Whoever adds photo bytes here in R7 restores
  // a sentence about the key at the same time, when it is true.
  final notes = <String>[
    'Progress photo image data is not included in this export.',
  ];
  if (server == null) {
    notes.add(
      'The server-held part of your data (subscriptions, coach bookings, '
      'equipment reports, saved machines, recognition history and diagnostic '
      'sessions) could not be retrieved. Re-run the export to try again.',
    );
  }
  if (progressPhotosIncomplete) {
    notes.add(
      'The list of progress photos below may be incomplete: reading it '
      'did not finish in time. Re-run the export to try again.',
    );
  }
  return {
    'exportFormatVersion': 1,
    'profile': profile.toJson()..['uid'] = profile.uid,
    'workoutLogs': workoutLogs.map((e) => e.toJson()).toList(),
    'scheduledSessions': scheduledSessions.map((s) => s.toJson()).toList(),
    'programmes': programmes.map((p) => p.toJson()).toList(),
    'progressPhotosIncomplete': progressPhotosIncomplete,
    'progressPhotos': progressPhotos
        .map((p) => {
              'id': p.id,
              'takenAt': p.takenAt.toIso8601String(),
              'angle': p.angle.name,
              if (p.weightKg != null) 'weightKg': p.weightKg,
              if (p.bodyFatPercent != null)
                'bodyFatPercent': p.bodyFatPercent,
              if (p.note != null) 'note': p.note,
              // Deliberately excluded: storagePath, keyFingerprint. Neither
              // is personal data -- they are internal plumbing (an object key
              // and a key-rotation marker) -- and the photo bytes they point
              // at are exactly what this export does not decrypt.
            })
        .toList(),
    'serverIncomplete': server == null,
    if (server != null) 'server': server,
    'notes': notes,
  };
}

/// [buildExport] plus formatting, for the one caller that wants a file.
String buildExportJson({
  required UserProfile profile,
  required List<WorkoutLogEntry> workoutLogs,
  required List<ScheduledSession> scheduledSessions,
  required List<Programme> programmes,
  required List<ProgressPhoto> progressPhotos,
  bool progressPhotosIncomplete = false,
  Map<String, dynamic>? server,
}) {
  final data = buildExport(
    profile: profile,
    workoutLogs: workoutLogs,
    scheduledSessions: scheduledSessions,
    programmes: programmes,
    progressPhotos: progressPhotos,
    progressPhotosIncomplete: progressPhotosIncomplete,
    server: server,
  );
  return const JsonEncoder.withIndent('  ').convert(data);
}
