import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import 'package:fitness_app/features/progress_photos/widgets/photo_capture_sheet.dart';
import '../../helpers/test_app.dart';

/// R11f. "Take a new photo" used to call `capture()` bare — no angle, so every
/// shot was filed as `front`, and no preview, so the user pressed a button and
/// a picture was taken of wherever the phone happened to point.
///
/// The angle is not cosmetic: `defaultComparePair` refuses to pair across
/// angles, so a library where everything is silently `front` cannot tell a
/// real front-to-front comparison from two unrelated pictures.

/// A session that never touches a platform channel.
class _SpySession extends CameraSession {
  bool started = false;
  bool stopped = false;

  @override
  Future<void> start({bool requestPermission = false}) async {
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<XFile?> captureStill() async => null;
}

/// Known pixels, so a test can tell the sheet's own bytes from any other
/// source's.
final _shotBytes = Uint8List.fromList(const [7, 7, 7, 7]);

/// Stands in for the disk repository. Bound explicitly rather than left to the
/// real provider chain, which reaches `getApplicationDocumentsDirectory()` and
/// Firebase Auth — neither of which exists in a widget test.
class _SpyRepo implements ProgressPhotosRepository {
  int shots = 0;
  Object? failWith;

  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(const []);

  @override
  Future<Uint8List?> takeShot() async {
    shots++;
    if (failWith != null) throw failWith!;
    return _shotBytes;
  }

  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async =>
      throw UnimplementedError('the sheet must not write anything');

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async =>
      throw UnimplementedError();
}

/// What the most recent [_openSheet] resolved to.
///
/// A file-level variable because the sheet's future completes long after
/// `_openSheet` returns — the helper opens it, the test drives it, and the
/// answer lands somewhere in between.
PhotoShot? _lastShot;

Future<PhotoShot?> _openSheet(
  WidgetTester tester,
  _SpySession session, {
  _SpyRepo? repo,
  /// Whether the test is expected to leave the sheet closed. False for the
  /// failure case, where staying open IS the assertion.
  bool closes = true,
}) async {
  PhotoShot? result;
  var done = false;
  _lastShot = null;

  await tester.pumpWidget(ProviderScope(
    overrides: [
      progressPhotoCameraProvider.overrideWithValue(session),
      progressPhotosRepositoryProvider.overrideWithValue(repo ?? _SpyRepo()),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await PhotoCaptureSheet.show(context);
                _lastShot = result;
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open'));
  await _settleSheet(tester);
  // The caller reads `result` after the sheet closes; `done` exists so a test
  // can assert the future actually resolved rather than silently hanging.
  if (closes) addTearDown(() => expect(done, isTrue));
  return result;
}

/// `LiveEquipmentPreview` renders a spinner until a real camera surface
/// arrives, and a spinner never settles — so `pumpAndSettle` times out here by
/// construction. Fixed pumps advance the sheet's own transition instead.
Future<void> _settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('offers every angle and opens the camera', (tester) async {
    final session = _SpySession();
    addTearDown(session.dispose);

    await _openSheet(tester, session);

    for (final a in ProgressPhotoAngle.values) {
      expect(find.byKey(Key('photos.angle.${a.name}')), findsOneWidget);
    }
    expect(session.started, isTrue,
        reason: 'a capture sheet with no live preview is the bug it replaces');

    await tester.tap(find.byKey(const Key('photos.captureCancel')));
    await _settleSheet(tester);
  });

  testWidgets('the shutter hands back the PIXELS and the chosen angle',
      (tester) async {
    // R11f moved the shutter into the sheet. Before, this returned an angle
    // and the page captured afterwards -- by which time `dispose` had stopped
    // the camera, so the shot raced a teardown it usually, but not always,
    // beat. With a review screen in between it would have lost every time,
    // and `awaitReady`'s timeout returns null: indistinguishable one layer up
    // from "the user backed out".
    final session = _SpySession();
    final repo = _SpyRepo();
    addTearDown(session.dispose);

    await _openSheet(tester, session, repo: repo);

    await tester.tap(find.byKey(const Key('photos.angle.side')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('photos.shutter')));
    await _settleSheet(tester);

    expect(repo.shots, 1, reason: 'the sheet takes the picture itself now');
    expect(_lastShot?.angle, ProgressPhotoAngle.side);
    expect(_lastShot?.bytes, _shotBytes,
        reason: 'the pixels must travel with the angle, or the review screen '
            'has nothing to show');
  });

  testWidgets('backing out returns null, and never fires the shutter',
      (tester) async {
    final session = _SpySession();
    final repo = _SpyRepo();
    addTearDown(session.dispose);

    await _openSheet(tester, session, repo: repo);
    await tester.tap(find.byKey(const Key('photos.captureCancel')));
    await _settleSheet(tester);

    expect(_lastShot, isNull,
        reason: 'firing a capture after the user backed out is the same bug '
            'in a new place');
    expect(repo.shots, 0);
  });

  testWidgets('a camera that fails says so, and the sheet stays open',
      (tester) async {
    // The shutter is the one moment the user is standing still waiting for a
    // result. Silence here reads as a dead button -- and silence is what the
    // old code produced: `capture()` recorded the error in a provider nothing
    // rendered.
    final session = _SpySession();
    final repo = _SpyRepo()..failWith = StateError('camera is held elsewhere');
    addTearDown(session.dispose);

    await _openSheet(tester, session, repo: repo, closes: false);
    await tester.tap(find.byKey(const Key('photos.shutter')));
    await _settleSheet(tester);

    expect(find.byKey(const Key('photos.shotError')), findsOneWidget);
    expect(find.byKey(const Key('photos.shutter')), findsOneWidget,
        reason: 'closing the sheet on a failure would discard the pose the '
            'user is still holding');
  });

  testWidgets('closing the sheet releases the camera', (tester) async {
    final session = _SpySession();
    addTearDown(session.dispose);

    await _openSheet(tester, session);
    await tester.tap(find.byKey(const Key('photos.captureCancel')));
    await _settleSheet(tester);

    expect(session.stopped, isTrue,
        reason: 'a camera left running behind a closed sheet is why the phone '
            'shows a recording dot for no reason');
  });
}
