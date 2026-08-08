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

Future<ProgressPhotoAngle?> _openSheet(
  WidgetTester tester,
  _SpySession session,
) async {
  ProgressPhotoAngle? result;
  var done = false;

  await tester.pumpWidget(ProviderScope(
    overrides: [
      progressPhotoCameraProvider.overrideWithValue(session),
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
  addTearDown(() => expect(done, isTrue));
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

  testWidgets('the shutter returns the CHOSEN angle, not the default',
      (tester) async {
    final session = _SpySession();
    addTearDown(session.dispose);
    ProgressPhotoAngle? chosen;

    await tester.runAsync(() async {});
    await tester.pumpWidget(ProviderScope(
      overrides: [progressPhotoCameraProvider.overrideWithValue(session)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async =>
                    chosen = await PhotoCaptureSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await _settleSheet(tester);

    await tester.tap(find.byKey(const Key('photos.angle.side')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('photos.shutter')));
    await _settleSheet(tester);

    expect(chosen, ProgressPhotoAngle.side);
  });

  testWidgets('backing out returns null, so nothing is captured',
      (tester) async {
    final session = _SpySession();
    addTearDown(session.dispose);
    ProgressPhotoAngle? chosen = ProgressPhotoAngle.back;

    await tester.pumpWidget(ProviderScope(
      overrides: [progressPhotoCameraProvider.overrideWithValue(session)],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async =>
                    chosen = await PhotoCaptureSheet.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await _settleSheet(tester);
    await tester.tap(find.byKey(const Key('photos.captureCancel')));
    await _settleSheet(tester);

    expect(chosen, isNull,
        reason: 'firing a capture after the user backed out is the same bug '
            'in a new place');
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
