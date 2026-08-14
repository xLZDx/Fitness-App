import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/progress/progress_page.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';
import '../helpers/test_app.dart';

Future<void> _setLargeSurface(WidgetTester tester) async {
  // The page packs a headline row + three chart cards + the photo block + a
  // records list + recent activity. The default 800x600 test viewport clips
  // the lower sections and ListView won't lazily build them, so set a tall
  // surface.
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// A repository with a fixed set of photos, so the compare card's three
/// states can each be rendered without touching disk or a camera.
class _FixedPhotosRepository implements ProgressPhotosRepository {
  _FixedPhotosRepository(this.photos);
  final List<ProgressPhoto> photos;

  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(photos);

  @override
  Future<Uint8List?> takeShot() async => null;

  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async =>
      throw StateError('no pixels in this test');
}

ProgressPhoto _photo(
  String id,
  DateTime at, {
  ProgressPhotoAngle angle = ProgressPhotoAngle.front,
  double? weightKg,
}) =>
    ProgressPhoto(
      id: id,
      takenAt: at,
      storagePath: 'test://$id',
      keyFingerprint: 'testfp',
      angle: angle,
      weightKg: weightKg,
    );

/// Not `testHarness`: that helper opens its own [ProviderScope], which would
/// shadow the override below and leave the page reading the real repository.
/// The scope has to be the outermost one.
Widget _harness(List<ProgressPhoto> photos) => ProviderScope(
      overrides: [
        progressPhotosRepositoryProvider
            .overrideWithValue(_FixedPhotosRepository(photos)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AuroraBackground(child: ProgressPage()),
      ),
    );

void main() {
  // R11g rebuilt this screen's top and added the block the design puts in its
  // middle. The old assertions pinned a 2x2 grid of gradient stat tiles
  // ("Total workouts" / "This week" / "Current streak" / "Longest"), which the
  // design does not have — see `_HeadlineStats`.
  group('ProgressPage (empty state)', () {
    testWidgets('renders the three headline numbers the design specifies',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(testHarness(child: const ProgressPage()));
      await tester.pump();

      expect(find.text('workouts'), findsOneWidget);
      expect(find.text('day streak'), findsOneWidget);
      expect(find.text('records'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3));
    });

    testWidgets('keeps this-week and longest-streak, which the design row '
        'has no slot for', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(testHarness(child: const ProgressPage()));
      await tester.pump();

      expect(find.textContaining('This week: 0'), findsOneWidget);
      expect(find.textContaining('Longest streak: 0d'), findsOneWidget);
    });

    testWidgets('shows Last 8 weeks + Recent activity sections',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(testHarness(child: const ProgressPage()));
      await tester.pump();

      expect(find.text('Last 8 weeks'), findsOneWidget);
      expect(find.textContaining('Log a workout'), findsOneWidget);
      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.textContaining('start your history'), findsOneWidget);
    });
  });

  /// H1. `workoutSessionHistoryProvider` emits one row per exercise, which is
  /// what every other consumer needs. This list is the exception: a scheduled
  /// day of four exercises is ONE workout, and four rows both read as four
  /// separate ones and use up the whole five-card list.
  group('Recent activity counts workouts, not exercises', () {
    WorkoutLogEntry row(
      String sessionId,
      String exerciseId,
      String title, {
      int index = 0,
      DateTime? at,
    }) =>
        WorkoutLogEntry(
          id: '${sessionId}_$index',
          sessionId: sessionId,
          exerciseId: exerciseId,
          exerciseTitle: title,
          completedAt: at ?? DateTime(2026, 8, 14),
          durationMinutes: 45,
        );

    Widget host(List<WorkoutLogEntry> logs) => ProviderScope(
          overrides: [
            workoutSessionHistoryProvider.overrideWithValue(logs),
            progressPhotosRepositoryProvider
                .overrideWithValue(_FixedPhotosRepository(const [])),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            locale: kTestLocale,
            localizationsDelegates: kTestLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AuroraBackground(child: ProgressPage()),
          ),
        );

    testWidgets('a four-exercise day is one card, named and counted',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(host([
        row('day_d1', 'e1', 'Squat'),
        row('day_d1', 'e2', 'Bench press', index: 1),
        row('day_d1', 'e3', 'Row', index: 2),
        row('day_d1', 'e4', 'Plank', index: 3),
      ]));
      await tester.pump();

      expect(find.text('Squat  +3'), findsOneWidget);
      expect(find.text('Bench press'), findsNothing,
          reason: 'exercises two onward belong to the same workout and must '
              'not each open their own card');
      expect(find.text('Row'), findsNothing);
      expect(find.text('Plank'), findsNothing);
    });

    testWidgets('a single-exercise workout is unchanged — no bare "+0"',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(host([row('s1', 'e1', 'Squat')]));
      await tester.pump();

      expect(find.text('Squat'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('one long day no longer fills the list and hides the rest',
        (tester) async {
      // The regression in plain terms: before grouping, the six rows of one
      // day took every slot of a five-card list and the earlier workout was
      // pushed off the screen entirely.
      await _setLargeSurface(tester);
      await tester.pumpWidget(host([
        for (var i = 0; i < 6; i++)
          row('day_d1', 'e$i', 'Exercise $i',
              index: i, at: DateTime(2026, 8, 14)),
        row('s_old', 'e9', 'Yesterday run', at: DateTime(2026, 8, 13)),
      ]));
      await tester.pump();

      expect(find.text('Exercise 0  +5'), findsOneWidget);
      expect(find.text('Yesterday run'), findsOneWidget,
          reason: 'the older workout has to survive a long day above it');
    });

    test('grouping keeps the order the provider produced', () {
      final grouped = bySession([
        row('b', 'e1', 'B1'),
        row('a', 'e2', 'A1'),
        row('b', 'e3', 'B2', index: 1),
      ]);

      expect(grouped.map((g) => g.first.sessionId).toList(), ['b', 'a'],
          reason: 're-sorting here would silently override whatever order the '
              'provider chose');
      expect(grouped.first.length, 2);
    });
  });

  group('ProgressPage photo block', () {
    testWidgets('with no photos it invites the first one', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_harness(const []));
      await tester.pump();

      expect(find.byKey(const Key('progress.photos')), findsOneWidget);
      expect(find.byKey(const Key('progress.photosEmpty')), findsOneWidget);
      expect(find.text('Add your first photo'), findsOneWidget);
      expect(find.byKey(const Key('progress.photoCompare')), findsNothing);
    });

    testWidgets('two photos at DIFFERENT angles are not offered as a pair',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_harness([
        _photo('a', DateTime(2026, 6, 1)),
        _photo('b', DateTime(2026, 8, 1), angle: ProgressPhotoAngle.side),
      ]));
      await tester.pump();

      expect(find.byKey(const Key('progress.photoCompare')), findsNothing,
          reason: 'front vs side is two pictures, not a comparison');
      expect(find.byKey(const Key('progress.photosEmpty')), findsOneWidget);
      expect(find.text('Add your first photo'), findsNothing,
          reason: 'photos exist; the ask is for a matching angle');
    });

    testWidgets('a real pair shows the span and the weight delta',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_harness([
        _photo('a', DateTime(2026, 6, 1), weightKg: 88.0),
        _photo('b', DateTime(2026, 8, 1), weightKg: 81.2),
      ]));
      await tester.pump();

      expect(find.byKey(const Key('progress.photoCompare')), findsOneWidget);
      expect(find.text('Compare'), findsOneWidget);
      expect(find.textContaining('Jun 1'), findsOneWidget);
      expect(find.text('-6.8 kg'), findsOneWidget,
          reason: 'the sign is the information, and it is not praised either '
              'way — this screen does not know if the user is cutting');
    });

    testWidgets('a pair with only one weight shows no delta', (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_harness([
        _photo('a', DateTime(2026, 6, 1), weightKg: 88.0),
        _photo('b', DateTime(2026, 8, 1)),
      ]));
      await tester.pump();

      expect(find.byKey(const Key('progress.photoCompare')), findsOneWidget);
      // Scoped to the card: the page's own "Volume (kg)" heading is elsewhere
      // on the screen and a bare textContaining('kg') matches it.
      expect(
        find.descendant(
          of: find.byKey(const Key('progress.photoCompare')),
          matching: find.textContaining('kg'),
        ),
        findsNothing,
        reason: 'a delta against a missing number is no delta at all',
      );
    });

    testWidgets('a photo whose pixels cannot be decrypted says so',
        (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(_harness([
        _photo('a', DateTime(2026, 6, 1)),
        _photo('b', DateTime(2026, 8, 1)),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('Preview unavailable'), findsNWidgets(2),
          reason: 'better than a broken image tile with no explanation');
    });
  });
}
