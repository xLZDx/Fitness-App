import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/camera/camera_session.dart';
import '../../../core/notifications/notification_providers.dart';
import '../../../core/settings/state/settings_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../data/aes_photo_cipher.dart';
import '../data/local_progress_photos_repository.dart';
import '../data/photo_directory.dart';
import '../data/photo_key_store.dart';
import '../data/photo_store.dart';
import '../data/photo_timeline.dart';
import '../data/progress_photo.dart';

/// The one notification id every progress-photo reminder uses.
///
/// Stable and shared on purpose: scheduling replaces a reminder with the same
/// id, so each save moves the single pending nudge instead of stacking a new
/// one on top of it. A per-photo id would give a user with a year of history
/// twelve pending notifications.
const String kProgressPhotoReminderId = 'progress_photo_next';

/// How long after a photo the next reminder fires. Operator's choice, 2026-08-12.
const Duration kProgressPhotoReminderGap = Duration(days: 30);

/// Repository boundary. Bound to [LocalProgressPhotosRepository] once
/// [progressPhotosStoreProvider] resolves; the mock covers the window before
/// that and the tests that do not care about disk.
abstract class ProgressPhotosRepository {
  Stream<List<ProgressPhoto>> watch();

  /// Takes the picture and hands back its pixels, writing NOTHING.
  ///
  /// Returns null when the user cancelled the camera.
  ///
  /// ## Why this is not one call with [save]
  ///
  /// It used to be: `capture()` took the still and wrote the record in one
  /// step. That left nowhere for the two things standing between them in the
  /// design (`ProgressPhotoModule:3909`) — looking at the shot before keeping
  /// it, and saying what the user weighed when it was taken. Both had to
  /// happen after the shutter and before the write, and a single method has no
  /// such moment.
  ///
  /// The metadata half was not hypothetical. [PhotoStore.put] has taken
  /// `weightKg` and `note` since R7, stores them and reads them back, and the
  /// one caller never passed either — which is why the compare card almost
  /// never had a weight delta to show.
  Future<Uint8List?> takeShot();

  /// Encrypts and files pixels that [takeShot] returned.
  ///
  /// Separate from the shot so the user can be shown what they took, and asked
  /// about it, in between.
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  });

  Future<void> delete(String id);

  /// Decrypted pixels for one photo.
  Future<Uint8List> bytesOf(ProgressPhoto photo);
}

class MockProgressPhotosRepository implements ProgressPhotosRepository {
  final List<ProgressPhoto> _photos = [];

  @override
  Stream<List<ProgressPhoto>> watch() async* {
    yield List.unmodifiable(_photos);
  }

  /// Placeholder pixels, so the review step has something to hand on.
  ///
  /// Deliberately not a decodable image: [bytesOf] below still refuses, and a
  /// demo capture that produced a viewable photo would contradict the banner
  /// telling the user nothing here is being kept.
  @override
  Future<Uint8List?> takeShot() async => Uint8List.fromList(const [0, 0, 0]);

  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async {
    final p = ProgressPhoto(
      id: 'p_${_photos.length + 1}',
      takenAt: DateTime.now(),
      storagePath: 'mock://${_photos.length + 1}.bin',
      keyFingerprint: 'mockfp',
      angle: angle,
      weightKg: weightKg,
      note: note,
    );
    _photos.add(p);
    return p;
  }

  @override
  Future<void> delete(String id) async {
    _photos.removeWhere((p) => p.id == id);
  }

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async {
    // The mock never had pixels. Returning an empty list would render as a
    // broken image with no explanation; throwing is what the demo banner
    // above the grid is already telling the user to expect.
    throw StateError('Demo photos have no pixels.');
  }
}

/// Builds the on-disk store for the SIGNED-IN account, or null when there is
/// no account to build one for.
///
/// A2-sec made both halves uid-scoped: the directory
/// (`<docs>/progress_photos/<uid>/`, see `photo_directory.dart`) and the key
/// (`progress_photos.key.v2.<uid>` in platform secure storage, see
/// [SecurePhotoKeyStore]). Watching [authUserProvider] rather than reading a
/// uid once is what makes a sign-out actually close the previous account's
/// store instead of leaving it live behind a stale provider.
///
/// Async because the documents directory, the migration and the Keystore are
/// all platform channels.
final progressPhotosStoreProvider = FutureProvider<PhotoStore?>((ref) async {
  // `.future`, not `.valueOrNull`. `authUserProvider` is a StreamProvider and
  // has not emitted anything on a cold start, where `valueOrNull` is null and
  // therefore indistinguishable from signed-out — which would show a
  // signed-in user the demo grid until the stream caught up. Awaiting the
  // first emission removes that window entirely.
  final uid = (await ref.watch(authUserProvider.future))?.uid;
  // Signed out: no store at all, rather than a shared one. The repository
  // below falls back to the demo mock, which is what the banner already
  // describes, and no bytes are written anywhere they could outlive the
  // session.
  if (uid == null || uid.isEmpty) return null;

  final documents = await getApplicationDocumentsDirectory();
  final dir = await resolvePhotoDir(documents: documents, uid: uid);
  final key = await SecurePhotoKeyStore(uid: uid).loadOrCreate();
  return PhotoStore(dir: dir, cipher: AesPhotoCipher(key));
});

/// The camera used for progress shots.
///
/// Its own session rather than a share of `scanCameraSessionProvider`: the
/// scanner's session is front-or-back depending on what it is doing and is
/// started and stopped by the scanner's own page lifecycle. Borrowing it would
/// couple a photo capture to whether the user had recently scanned a machine.
final progressPhotoCameraProvider = Provider<CameraSession>((ref) {
  final session = CameraSession();
  ref.onDispose(session.dispose);
  return session;
});

final progressPhotosRepositoryProvider =
    Provider<ProgressPhotosRepository>((ref) {
  final async = ref.watch(progressPhotosStoreProvider);
  // `.valueOrNull` flattens loading, signed-out and FAILED into one null, and
  // the third is not benign: a `PhotoKeyUnavailable` means a user with photos
  // is looking at the demo grid. The fallback is still right — it is the only
  // safe thing to show — but it must not be the only trace that anything went
  // wrong.
  if (async.hasError) {
    debugPrint('progress photos: store unavailable — ${async.error}');
  }
  final store = async.valueOrNull;
  if (store == null) return MockProgressPhotosRepository();
  return LocalProgressPhotosRepository(
    store: store,
    source: CameraSessionPhotoSource(ref.watch(progressPhotoCameraProvider)),
  );
});

/// True while [progressPhotosRepositoryProvider] is still the mock.
///
/// Two states reach it since A2-sec: the disk store has not resolved yet, or
/// there is no signed-in account to scope it to. The banner has to exist for
/// both — in either window a capture really does vanish on restart.
final progressPhotosAreDemoProvider = Provider<bool>((ref) {
  return ref.watch(progressPhotosRepositoryProvider)
      is MockProgressPhotosRepository;
});

final progressPhotosProvider = StreamProvider<List<ProgressPhoto>>((ref) {
  return ref.watch(progressPhotosRepositoryProvider).watch();
});

/// Timeline sections, newest month first.
final photoMonthsProvider = Provider<List<PhotoMonth>>((ref) {
  final photos = ref.watch(progressPhotosProvider).valueOrNull ?? const [];
  return groupByMonth(photos);
});

/// The pair the compare card opens on, or null when nothing is comparable.
final defaultComparePairProvider = Provider<ComparePair?>((ref) {
  final photos = ref.watch(progressPhotosProvider).valueOrNull ?? const [];
  return defaultComparePair(photos);
});

/// Decrypted pixels for one photo. Two tiles showing the same photo share one
/// decrypt — [ProgressPhoto] carries value equality for exactly this.
///
/// `autoDispose` is what bounds the memory. A plain family keeps every entry
/// for the life of the container, so a decrypted JPEG stayed resident after
/// its tile was gone and after the screen itself was gone; the ceiling was the
/// user's whole photo history, reached by scrolling once and never given back.
/// With it, the bytes live exactly as long as something is showing them, and
/// the timeline's paging (see `newestMonths`) is what bounds how many that can
/// be at one time.
///
/// The cost is a re-decrypt when the user comes back to the screen. That is
/// one AES-GCM pass over a few tens of kilobytes per visible tile, and it is
/// the right side of the trade against holding the history in RAM.
final photoBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, ProgressPhoto>((ref, photo) async {
  return ref.watch(progressPhotosRepositoryProvider).bytesOf(photo);
});

class ProgressPhotosController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  /// Takes the picture. Must be called while the camera is still open — see
  /// the note on [PhotoCaptureSheet].
  ///
  /// Records the failure in [state] AND rethrows. Recording alone was what the
  /// old `capture()` did, and nothing in the app watches this provider's
  /// value: a camera that refused to shoot set an error nobody rendered, and
  /// the user saw a button that did nothing. Rethrowing is what gives the
  /// caller something to show.
  Future<Uint8List?> takeShot() async {
    try {
      return await ref.read(progressPhotosRepositoryProvider).takeShot();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(progressPhotosRepositoryProvider).save(
            bytes,
            angle: angle,
            weightKg: weightKg,
            note: note,
          );
      ref.invalidate(progressPhotosProvider);
      await _scheduleNextReminder();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Nudge the user to take the next shot in a month.
  ///
  /// ## Why the anchor is the save, not a calendar
  ///
  /// Each save schedules one reminder under the SAME id, which replaces the
  /// previous one. So the reminder is always "a month after the last photo",
  /// and it self-corrects: somebody who shoots early simply moves their own
  /// reminder, and nobody who has stopped keeps being reminded on a schedule
  /// they set months ago. No background job, no stored due-date, nothing to
  /// drift.
  ///
  /// ## Why a month
  ///
  /// Operator's choice (2026-08-12), and it matches the feature: the compare
  /// card exists to show a difference, and at a week the difference is noise.
  /// A reminder that keeps announcing "nothing has changed" teaches the user
  /// to swipe it away.
  ///
  /// Best-effort throughout — the photo is already encrypted and on disk, and
  /// a reminder that could not be registered must never surface as a failed
  /// save. Logged rather than swallowed: a silent catch here is how the
  /// workouts path once hid a localisation-load failure that stopped every
  /// reminder being registered at all.
  Future<void> _scheduleNextReminder() async {
    // The Settings switch is what makes it a real preference rather than a
    // decorative one: with reminders off the photo is still saved, it just
    // stays silent.
    if (!ref.read(settingsControllerProvider).notificationsEnabled) return;
    try {
      // Loaded from the delegate, not a BuildContext: this is a provider, and
      // the reminder text has to be in the user's language wherever it is
      // built from.
      final l = await AppLocalizations.delegate
          .load(Locale(ref.read(effectiveLanguageCodeProvider)));
      await ref.read(notificationServiceProvider).scheduleAt(
            kProgressPhotoReminderId,
            fireAt: DateTime.now().add(kProgressPhotoReminderGap),
            title: l.photosReminderTitle,
            body: l.photosReminderBody,
          );
    } catch (e) {
      debugPrint('progress photo reminder not scheduled: $e');
    }
  }

  Future<void> delete(String id) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(progressPhotosRepositoryProvider).delete(id);
      ref.invalidate(progressPhotosProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final progressPhotosControllerProvider =
    NotifierProvider<ProgressPhotosController, AsyncValue<void>>(
        ProgressPhotosController.new);
