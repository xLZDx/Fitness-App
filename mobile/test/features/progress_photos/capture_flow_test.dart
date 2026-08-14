import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/progress_photos/data/photo_consent.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/progress_photos_page.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import '../../helpers/test_app.dart';

/// R11f, the whole order in one place: shoot -> look -> keep or retake ->
/// describe -> file (`ProgressPhotoModule:3909`).
///
/// Each of these steps was absent before. The button called `capture()` bare,
/// which took the picture and wrote it in the same breath — no angle, so every
/// photo was filed as `front`; no review, so a cut-off head joined the
/// timeline with the same authority as a good shot; and no metadata, so
/// `PhotoStore`'s `weightKg` column, which has existed and been read back
/// since R7, was null for every row ever written.
///
/// The steps are tested as a SEQUENCE rather than one by one because the
/// sequence is the thing that was wrong. Each screen in isolation would pass
/// while the flow still wrote before it asked.

final _shotBytes = Uint8List.fromList(const [9, 9, 9, 9]);

class _SpySession extends CameraSession {
  @override
  Future<void> start({bool requestPermission = false}) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<XFile?> captureStill() async => null;
}

class _RecordingRepo implements ProgressPhotosRepository {
  int shots = 0;
  final List<({ProgressPhotoAngle angle, double? weightKg, String? note})>
      saved = [];
  Object? saveFailsWith;

  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(const []);

  @override
  Future<Uint8List?> takeShot() async {
    shots++;
    return _shotBytes;
  }

  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async {
    if (saveFailsWith != null) throw saveFailsWith!;
    saved.add((angle: angle, weightKg: weightKg, note: note));
    return ProgressPhoto(
      id: 'p_${saved.length}',
      takenAt: DateTime(2026, 8, 12),
      storagePath: 'test://${saved.length}.bin',
      keyFingerprint: 'fp',
      angle: angle,
      weightKg: weightKg,
      note: note,
    );
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async => _shotBytes;
}

/// A spinner never settles — `LiveEquipmentPreview` shows one until a real
/// camera surface arrives, which never happens here. Fixed pumps advance the
/// transitions instead.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _host(WidgetTester tester, _RecordingRepo repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      progressPhotoCameraProvider.overrideWithValue(_SpySession()),
      progressPhotosRepositoryProvider.overrideWithValue(repo),
      // An account that agreed on some earlier day. These tests are about the
      // order of the capture steps, and the consent gate is a step before all
      // of them — it has its own file (`photo_consent_test.dart`).
      photoConsentStoreProvider.overrideWith(
          (ref) async => InMemoryPhotoConsentStore(accepted: true)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => runPhotoCaptureFlow(context, ref),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    ),
  ));
}

/// Opens the flow and gets as far as the review screen.
Future<void> _shoot(WidgetTester tester, {String angle = 'side'}) async {
  await tester.tap(find.text('start'));
  await _settle(tester);
  await tester.tap(find.byKey(Key('photos.angle.$angle')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('photos.shutter')));
  await _settle(tester);
}

void main() {
  testWidgets('nothing is written until the user has seen the shot',
      (tester) async {
    final repo = _RecordingRepo();
    await _host(tester, repo);
    await _shoot(tester);

    expect(find.byKey(const Key('photos.review.keep')), findsOneWidget,
        reason: 'the review screen is the only chance to notice a bad frame '
            'while it can still be retaken');
    expect(repo.shots, 1);
    expect(repo.saved, isEmpty,
        reason: 'the old capture() wrote here, before anyone had looked');
  });

  testWidgets('retake goes back to the camera, not back to the timeline',
      (tester) async {
    // The first draft returned to the page on "retake", which turned one bad
    // frame into three taps to fix.
    final repo = _RecordingRepo();
    await _host(tester, repo);
    await _shoot(tester);

    await tester.tap(find.byKey(const Key('photos.review.retake')));
    await _settle(tester);

    expect(find.byKey(const Key('photos.shutter')), findsOneWidget,
        reason: 'retake means take another one, right now');
    expect(repo.saved, isEmpty);

    await tester.tap(find.byKey(const Key('photos.shutter')));
    await _settle(tester);
    expect(repo.shots, 2);
  });

  testWidgets('the weight the user types is the weight that gets filed',
      (tester) async {
    // The gap this closes: `PhotoStore.put` has taken `weightKg` since R7 and
    // the only caller never passed it, which is why the compare card so rarely
    // had a delta to show.
    final repo = _RecordingRepo();
    await _host(tester, repo);
    await _shoot(tester);

    await tester.tap(find.byKey(const Key('photos.review.keep')));
    await _settle(tester);

    await tester.enterText(
        find.byKey(const Key('photos.details.weight')), '81.4');
    await tester.enterText(
        find.byKey(const Key('photos.details.note')), 'after the long run');
    await tester.tap(find.byKey(const Key('photos.details.save')));
    await _settle(tester);

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.weightKg, 81.4);
    expect(repo.saved.single.note, 'after the long run');
    expect(repo.saved.single.angle, ProgressPhotoAngle.side,
        reason: 'the angle chosen at the start has to survive two screens, or '
            'every photo is filed as front again');
  });

  testWidgets('both fields are optional and an empty form still saves',
      (tester) async {
    final repo = _RecordingRepo();
    await _host(tester, repo);
    await _shoot(tester, angle: 'back');

    await tester.tap(find.byKey(const Key('photos.review.keep')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('photos.details.save')));
    await _settle(tester);

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.weightKg, isNull);
    expect(repo.saved.single.note, isNull);
    expect(repo.saved.single.angle, ProgressPhotoAngle.back);
  });

  testWidgets('a weight that is not a weight blocks the save rather than '
      'quietly filing null', (tester) async {
    // Dropping it silently would be indistinguishable from "did not answer",
    // and would throw away what the user actually typed.
    final repo = _RecordingRepo();
    await _host(tester, repo);
    await _shoot(tester);

    await tester.tap(find.byKey(const Key('photos.review.keep')));
    await _settle(tester);
    await tester.enterText(
        find.byKey(const Key('photos.details.weight')), '814');
    await tester.tap(find.byKey(const Key('photos.details.save')));
    await _settle(tester);

    expect(repo.saved, isEmpty);
    expect(find.byKey(const Key('photos.details.save')), findsOneWidget,
        reason: 'the sheet has to stay open for the number to be corrected');
  });

  testWidgets('a failed write is said out loud', (tester) async {
    // It used to be recorded in a provider nothing renders, so a photo the
    // user had posed for could vanish without a word.
    final repo = _RecordingRepo()..saveFailsWith = StateError('disk full');
    await _host(tester, repo);
    await _shoot(tester);

    await tester.tap(find.byKey(const Key('photos.review.keep')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('photos.details.save')));
    await _settle(tester);

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
