// C16 functional tests for the compare screen additions (design s17, D-54):
// the ?mode=baseline|previous initial selection, the second-scan prompt when
// only the baseline exists, and the deleteScanFiles refactor that
// confirmAndDeleteScan now shares with the body-scan delete-photos flow.
import 'dart:convert';
import 'dart:typed_data';

import 'package:fitness_app/core/notifications/notification_service.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_reminder.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_compare_screen.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../../helpers/test_app.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

ScanRecord _scan(String id, int day) => ScanRecord(
      id: id,
      createdAt: DateTime(2026, 9, day),
      shots: {
        for (final p in ScanPose.ordered)
          p: ScanShot(photoId: '$id-${p.name}', landmarks: const []),
      },
    );

class _Scans implements ScanRepository {
  _Scans(List<ScanRecord> items) : items = List.of(items);
  final List<ScanRecord> items;
  @override
  Future<List<ScanRecord>> list() async => List.of(items);
  @override
  Future<void> save(ScanRecord r) async => items.add(r);
  @override
  Future<void> delete(String id) async => items.removeWhere((r) => r.id == id);
}

class _Photos implements ProgressPhotosRepository {
  final deleted = <String>[];
  String? failOn;
  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(const []);
  @override
  Future<Uint8List?> takeShot() async => null;
  @override
  Future<ProgressPhoto> save(Uint8List bytes,
          {required ProgressPhotoAngle angle,
          double? weightKg,
          String? note}) async =>
      throw UnimplementedError();
  @override
  Future<void> delete(String id) async {
    if (id == failOn) throw StateError('io');
    deleted.add(id);
  }

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async => Uint8List(0);
}

class _Reminder extends ScanReminderNotifier {
  @override
  bool build() => false;
  @override
  Future<ReminderOutcome?> sync({int? weekday, int? minutes}) async => null;
}

class _Env {
  _Env(this.scans, this.photos, this.location);
  final _Scans scans;
  final _Photos photos;
  final List<String> location;
}

Future<_Env> _pump(
  WidgetTester t,
  List<ScanRecord> history, {
  ScanCompareStart start = ScanCompareStart.baseline,
}) async {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final scans = _Scans(history);
  final photos = _Photos();
  final visited = <String>[];
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => ScanCompareScreen(start: start)),
    GoRoute(
      path: '/body-scan',
      builder: (_, s) {
        visited.add(s.uri.toString());
        return const Scaffold(body: Text('BODY SCAN HOME'));
      },
    ),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: [
      scanAccessProvider.overrideWithValue(ScanAccess.allowed),
      scanRepositoryProvider.overrideWithValue(scans),
      progressPhotosRepositoryProvider.overrideWithValue(photos),
      scanReminderEnabledProvider.overrideWith(_Reminder.new),
      scanShotBytesProvider.overrideWith((ref, id) async => _png),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await t.pump();
  await t.pump();
  return _Env(scans, photos, visited);
}

String? _picked(WidgetTester t, String which) => t
    .state<FormFieldState<String>>(find.byKey(Key('scan.compare.pick.$which')))
    .value;

void main() {
  group('ScanCompareStart.parse', () {
    test('only "previous" selects the previous pair; everything else is the '
        'baseline', () {
      expect(ScanCompareStart.parse('previous'), ScanCompareStart.previous);
      expect(ScanCompareStart.parse('baseline'), ScanCompareStart.baseline);
      expect(ScanCompareStart.parse(null), ScanCompareStart.baseline);
      expect(ScanCompareStart.parse(''), ScanCompareStart.baseline);
      expect(ScanCompareStart.parse('PREVIOUS'), ScanCompareStart.baseline);
      expect(ScanCompareStart.parse('../x'), ScanCompareStart.baseline);
    });
  });

  group('initial selection', () {
    final history = [_scan('new', 28), _scan('mid', 14), _scan('old', 1)];

    testWidgets('baseline: newest against the OLDEST scan', (t) async {
      await _pump(t, history);
      expect(_picked(t, 'later'), 'new');
      expect(_picked(t, 'earlier'), 'old');
    });

    testWidgets('previous: newest against the scan just before it', (t) async {
      await _pump(t, history, start: ScanCompareStart.previous);
      expect(_picked(t, 'later'), 'new');
      expect(_picked(t, 'earlier'), 'mid');
    });

    testWidgets('with exactly two scans both starts pick the same pair',
        (t) async {
      final two = [_scan('new', 28), _scan('old', 1)];
      await _pump(t, two);
      expect((_picked(t, 'earlier'), _picked(t, 'later')), ('old', 'new'));
      await _pump(t, two, start: ScanCompareStart.previous);
      expect((_picked(t, 'earlier'), _picked(t, 'later')), ('old', 'new'));
    });

    testWidgets('the start only sets the initial value: the user can still '
        'change the earlier scan', (t) async {
      await _pump(t, history, start: ScanCompareStart.previous);
      await t.tap(find.byKey(const Key('scan.compare.pick.earlier')));
      await t.pumpAndSettle();
      await t.tap(find.text('Scan Sep 1, 2026').last);
      await t.pumpAndSettle();
      expect(_picked(t, 'earlier'), 'old');
    });
  });

  group('second-scan prompt', () {
    testWidgets('only the baseline: need-two text, baseline-only text and a '
        '"take second scan" button that opens /body-scan', (t) async {
      final env = await _pump(t, [_scan('only', 1)]);
      final l10n =
          AppLocalizations.of(t.element(find.byType(ScanCompareScreen)));
      expect(find.byKey(const Key('scan.compare.needTwo')), findsOneWidget);
      expect(find.text(l10n.bodyScanCompareBaselineOnly), findsOneWidget);
      expect(find.text(l10n.bodyScanCompareTakeSecond), findsOneWidget);

      await t.tap(find.byKey(const Key('scan.compare.takeSecond')));
      await t.pumpAndSettle();
      expect(env.location, ['/body-scan']);
      expect(find.text('BODY SCAN HOME'), findsOneWidget);
    });

    testWidgets('no scans: need-two only, no second-scan prompt', (t) async {
      await _pump(t, const []);
      expect(find.byKey(const Key('scan.compare.needTwo')), findsOneWidget);
      expect(find.byKey(const Key('scan.compare.baselineOnly')), findsNothing);
      expect(find.byKey(const Key('scan.compare.takeSecond')), findsNothing);
    });

    testWidgets('two scans: the compare body, no prompt', (t) async {
      await _pump(t, [_scan('b', 2), _scan('a', 1)]);
      expect(find.byKey(const Key('scan.compare.needTwo')), findsNothing);
      expect(find.byKey(const Key('scan.compare.takeSecond')), findsNothing);
      expect(find.byKey(const Key('scan.compare.sideBySide')), findsOneWidget);
    });

    testWidgets('the lone baseline can still be deleted from the prompt',
        (t) async {
      final env = await _pump(t, [_scan('only', 1)]);
      await t.tap(find.byKey(const Key('scan.compare.delete.single')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('scan.delete.confirm')));
      await t.pumpAndSettle();
      expect(env.scans.items, isEmpty);
      expect(env.photos.deleted, hasLength(3));
    });
  });

  group('deleteScanFiles (shared delete path)', () {
    ProviderContainer container(_Scans scans, _Photos photos) {
      final c = ProviderContainer(overrides: [
        scanRepositoryProvider.overrideWithValue(scans),
        progressPhotosRepositoryProvider.overrideWithValue(photos),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('removes every shot photo and then the scan record', () async {
      final scan = _scan('a', 1);
      final scans = _Scans([scan, _scan('b', 2)]);
      final photos = _Photos();
      final c = container(scans, photos);
      await deleteScanFiles(c.read, scan);

      expect(photos.deleted.toSet(), {'a-front', 'a-side', 'a-back'});
      expect(scans.items.map((r) => r.id), ['b'],
          reason: 'only the targeted scan is removed');
    });

    test('stops at the first photo failure, keeps the record so a retry can '
        'finish', () async {
      final scan = _scan('a', 1);
      final scans = _Scans([scan]);
      final photos = _Photos()..failOn = 'a-side';
      final c = container(scans, photos);

      await expectLater(deleteScanFiles(c.read, scan), throwsA(anything));
      expect(photos.deleted, ['a-front']);
      expect(scans.items, hasLength(1),
          reason: 'the record is only removed after all photos');

      photos.failOn = null;
      await deleteScanFiles(c.read, scan);
      expect(scans.items, isEmpty);
    });
  });

  group('confirmAndDeleteScan keeps its behaviour', () {
    final history = [_scan('new', 28), _scan('old', 1)];

    testWidgets('confirm: files and record deleted, success snackbar, list '
        'refreshes to the one-scan prompt', (t) async {
      final env = await _pump(t, history);
      await t.tap(find.byKey(const Key('scan.compare.delete.later')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('scan.delete.dialog')), findsOneWidget);
      await t.tap(find.byKey(const Key('scan.delete.confirm')));
      await t.pumpAndSettle();

      expect(env.scans.items.map((r) => r.id), ['old']);
      expect(env.photos.deleted, hasLength(3));
      final l10n =
          AppLocalizations.of(t.element(find.byType(ScanCompareScreen)));
      expect(find.text(l10n.scanDeleted), findsOneWidget);
      expect(find.byKey(const Key('scan.compare.takeSecond')), findsOneWidget);
    });

    testWidgets('cancel deletes nothing', (t) async {
      final env = await _pump(t, history);
      await t.tap(find.byKey(const Key('scan.compare.delete.later')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('scan.delete.cancel')));
      await t.pumpAndSettle();
      expect(env.scans.items, hasLength(2));
      expect(env.photos.deleted, isEmpty);
    });

    testWidgets('a failure shows the failure snackbar and leaves the record',
        (t) async {
      final env = await _pump(t, history);
      env.photos.failOn = 'new-side';
      await t.tap(find.byKey(const Key('scan.compare.delete.later')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('scan.delete.confirm')));
      await t.pumpAndSettle();

      final l10n =
          AppLocalizations.of(t.element(find.byType(ScanCompareScreen)));
      expect(find.text(l10n.scanDeleteFailed), findsOneWidget);
      expect(env.scans.items, hasLength(2));
      expect(env.photos.deleted, ['new-front']);
    });
  });
}
