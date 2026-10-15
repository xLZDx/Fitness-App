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
import 'package:fitness_app/features/progress_photos/scan/ui/scan_gate_view.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import '../../../../helpers/test_app.dart';

ScanRecord _scan(String id, int day) => ScanRecord(
      id: id,
      createdAt: DateTime(2026, 9, day),
      shots: {
        for (final p in ScanPose.ordered)
          p: ScanShot(photoId: '$id-${p.name}', landmarks: const []),
      },
    );

class _Scans implements ScanRepository {
  _Scans(this.items);
  final List<ScanRecord> items;
  @override
  Future<List<ScanRecord>> list() async => List.of(items);
  @override
  Future<void> save(ScanRecord r) async => items.add(r);
  @override
  Future<void> delete(String id) async =>
      items.removeWhere((r) => r.id == id);
}

class _Photos implements ProgressPhotosRepository {
  final deleted = <String>[];
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
  Future<void> delete(String id) async => deleted.add(id);
  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async => Uint8List(0);
}

class _Reminder extends ScanReminderNotifier {
  @override
  bool build() => false;
  @override
  Future<ReminderOutcome?> sync({int? weekday, int? minutes}) async => null;
}

Future<void> _pump(WidgetTester t, ScanAccess access, _Scans scans,
    _Photos photos) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      scanRepositoryProvider.overrideWithValue(scans),
      scanHistoryProvider.overrideWith((ref) => scans.list()),
      progressPhotosRepositoryProvider.overrideWithValue(photos),
      scanReminderEnabledProvider.overrideWith(_Reminder.new),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ScanGateView(access: access)),
    ),
  ));
  await t.pump();
  await t.pump();
}

void main() {
  for (final access in [
    ScanAccess.needsSupporter,
    ScanAccess.underage,
    ScanAccess.ageUnknown,
  ]) {
    testWidgets('refused as ${access.name}: saved scans can still be deleted',
        (t) async {
      final scans = _Scans([_scan('a', 1), _scan('b', 2)]);
      final photos = _Photos();
      await _pump(t, access, scans, photos);
      await t.tap(find.byKey(const Key('scan.gate.deleteAll')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('scan.delete.confirm')));
      await t.pumpAndSettle();
      expect(scans.items, isEmpty);
      expect(photos.deleted, hasLength(2 * ScanPose.ordered.length));
      expect(find.byKey(const Key('scan.gate.deleteAll')), findsNothing);
    });
  }

  testWidgets('no saved scans: no delete action', (t) async {
    await _pump(t, ScanAccess.underage, _Scans([]), _Photos());
    expect(find.byKey(const Key('scan.gate.deleteAll')), findsNothing);
  });

  testWidgets('cancel keeps the scans', (t) async {
    final scans = _Scans([_scan('a', 1)]);
    await _pump(t, ScanAccess.needsSupporter, scans, _Photos());
    await t.tap(find.byKey(const Key('scan.gate.deleteAll')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('scan.delete.cancel')));
    await t.pumpAndSettle();
    expect(scans.items, hasLength(1));
  });
}
