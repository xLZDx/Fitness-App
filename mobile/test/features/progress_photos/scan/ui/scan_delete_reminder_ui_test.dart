import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/notifications/notification_service.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_reminder.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_compare_screen.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_entry_card.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
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

class _Log {
  final List<String> events = [];
}

class _LoggingScans implements ScanRepository {
  _LoggingScans(this.log, this.items);
  final _Log log;
  final List<ScanRecord> items;
  @override
  Future<List<ScanRecord>> list() async => List.of(items);
  @override
  Future<void> save(ScanRecord r) async => items.add(r);
  @override
  Future<void> delete(String id) async {
    log.events.add('scan:$id');
    items.removeWhere((r) => r.id == id);
  }
}

class _LoggingPhotos implements ProgressPhotosRepository {
  _LoggingPhotos(this.log, {this.failOn});
  final _Log log;
  final String? failOn;
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
    if (id == failOn) throw StateError('disk');
    log.events.add('photo:$id');
  }

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async => _png;
}

class _RecReminder extends ScanReminderNotifier {
  _RecReminder(this.log);
  final _Log log;
  @override
  bool build() => false;
  @override
  Future<ReminderOutcome?> sync({int? weekday, int? minutes}) async {
    log.events.add('sync');
    return null;
  }
}

class _DeniedReminder extends ScanReminderNotifier {
  @override
  bool build() => false;
  @override
  Future<ReminderOutcome?> setEnabled(bool enabled) async {
    state = enabled; // like the real notifier: flip, ask, fall back
    await Future<void>.delayed(Duration.zero);
    state = false;
    return enabled ? ReminderOutcome.denied : null;
  }
}

class _FailedReminder extends ScanReminderNotifier {
  @override
  bool build() => false;
  @override
  Future<ReminderOutcome?> setEnabled(bool enabled) async {
    state = enabled;
    await Future<void>.delayed(Duration.zero);
    state = false;
    return enabled ? ReminderOutcome.failed : null;
  }
}

Future<void> _pump(WidgetTester tester, Widget home, List<Override> o) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      scanAccessProvider.overrideWithValue(ScanAccess.allowed),
      scanShotBytesProvider.overrideWith((ref, id) async => _png),
      ...o,
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('scan delete', () {
    late _Log log;
    late _LoggingScans scans;

    List<Override> overrides({String? failPhoto}) => [
          scanRepositoryProvider.overrideWithValue(scans),
          scanHistoryProvider.overrideWith((ref) => scans.list()),
          progressPhotosRepositoryProvider
              .overrideWithValue(_LoggingPhotos(log, failOn: failPhoto)),
          scanReminderEnabledProvider.overrideWith(() => _RecReminder(log)),
        ];

    setUp(() {
      log = _Log();
      scans = _LoggingScans(log, [_scan('new', 28), _scan('old', 1)]);
    });

    testWidgets('cancel keeps everything', (tester) async {
      await _pump(tester, const ScanCompareScreen(), overrides());
      await tester.tap(find.byKey(const Key('scan.compare.delete.earlier')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('scan.delete.dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('scan.delete.cancel')));
      await tester.pumpAndSettle();
      expect(log.events, isEmpty);
      expect(scans.items, hasLength(2));
    });

    testWidgets(
        'confirm deletes photos first, then the scan, then syncs the reminder, '
        'and the history refreshes', (tester) async {
      await _pump(tester, const ScanCompareScreen(), overrides());
      // Default: earlier = oldest scan.
      await tester.tap(find.byKey(const Key('scan.compare.delete.earlier')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan.delete.confirm')));
      await tester.pumpAndSettle();
      expect(log.events, [
        for (final p in ScanPose.ordered) 'photo:old-${p.name}',
        'scan:old',
        'sync',
      ]);
      expect(scans.items.map((s) => s.id), ['new']);
      // One scan left: the compare view degrades to the need-two message
      // (history was invalidated) and still offers delete for the last one.
      expect(find.byKey(const Key('scan.compare.needTwo')), findsOneWidget);
      expect(find.byKey(const Key('scan.compare.delete.single')),
          findsOneWidget);
      expect(find.text('Scan deleted.'), findsOneWidget);
    });

    testWidgets('a failing photo delete stops before the scan record',
        (tester) async {
      await _pump(tester, const ScanCompareScreen(),
          overrides(failPhoto: 'old-side'));
      await tester.tap(find.byKey(const Key('scan.compare.delete.earlier')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('scan.delete.confirm')));
      await tester.pumpAndSettle();
      expect(log.events.where((e) => e.startsWith('scan:')), isEmpty);
      expect(log.events, isNot(contains('sync')));
      expect(scans.items, hasLength(2));
      expect(find.textContaining('Could not delete the scan'), findsOneWidget);
    });
  });

  group('reminder denied', () {
    testWidgets('toggle reverts and the reason is shown', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: SingleChildScrollView(child: ScanEntryCard())),
        [scanReminderEnabledProvider.overrideWith(_DeniedReminder.new)],
      );
      final sw = find.byKey(const Key('scan.entry.reminder'));
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<SwitchListTile>(sw).value, isFalse);
      expect(find.byKey(const Key('scan.entry.reminderDenied')),
          findsOneWidget);
      expect(find.textContaining('Notifications are off'), findsOneWidget);
    });

    testWidgets('a failed schedule reverts the toggle and shows the generic error',
        (tester) async {
      await _pump(
        tester,
        const Scaffold(body: SingleChildScrollView(child: ScanEntryCard())),
        [scanReminderEnabledProvider.overrideWith(_FailedReminder.new)],
      );
      final sw = find.byKey(const Key('scan.entry.reminder'));
      await tester.ensureVisible(sw);
      await tester.tap(sw);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<SwitchListTile>(sw).value, isFalse);
      expect(find.byKey(const Key('scan.entry.reminderFailed')),
          findsOneWidget);
      expect(find.byKey(const Key('scan.entry.reminderDenied')), findsNothing);
    });
  });
}
