import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/notifications/mock_notification_service.dart';
import 'package:fitness_app/core/notifications/notification_providers.dart';
import 'package:fitness_app/core/notifications/notification_service.dart';
import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';

/// P1. A month after the last photo, nudge the user to take the next one.
///
/// The anchor is the SAVE, not a calendar: every save schedules under one
/// shared id, so the pending reminder moves instead of multiplying. That is
/// what these tests are really pinning — a per-photo id would give a user with
/// a year of history twelve notifications, and nothing else in the app would
/// notice.

final _bytes = Uint8List.fromList(const [1, 2, 3]);

class _FakeRepo implements ProgressPhotosRepository {
  int saves = 0;

  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(const []);

  @override
  Future<Uint8List?> takeShot() async => _bytes;

  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async {
    saves++;
    return ProgressPhoto(
      id: 'p_$saves',
      takenAt: DateTime(2026, 8, 12),
      storagePath: 'test://$saves.bin',
      keyFingerprint: 'fp',
      angle: angle,
    );
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async => _bytes;
}

/// Models a platform that refuses. The photo is already encrypted and on disk
/// by the time this runs, so a refusal here must not reach the user as a
/// failed save.
class _ThrowingNotifications implements NotificationService {
  @override
  Future<bool> init() async => true;
  @override
  Future<bool> ensurePermission() async => true;
  @override
  Future<void> scheduleReminder(session,
          {required String title,
          required String body,
          Duration leadTime = const Duration(minutes: 30)}) async =>
      throw UnimplementedError();
  @override
  Future<void> scheduleAt(String id,
          {required DateTime fireAt,
          required String title,
          required String body}) async =>
      throw StateError('exact alarms revoked');
  @override
  Future<void> cancelReminder(String sessionId) async {}
  @override
  Future<void> cancelAll() async {}
}

ProviderContainer _container({
  required NotificationService notes,
  required _FakeRepo repo,
  bool notificationsEnabled = true,
}) {
  final c = ProviderContainer(overrides: [
    notificationServiceProvider.overrideWithValue(notes),
    progressPhotosRepositoryProvider.overrideWithValue(repo),
    initialSettingsProvider.overrideWithValue(
      AppSettings(notificationsEnabled: notificationsEnabled),
    ),
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _save(ProviderContainer c) => c
    .read(progressPhotosControllerProvider.notifier)
    .save(_bytes, angle: ProgressPhotoAngle.front);

void main() {
  // `AppLocalizations.delegate.load` runs inside the controller, and message
  // loading wants a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saving a photo schedules the next nudge a month out', () async {
    final notes = MockNotificationService();
    final c = _container(notes: notes, repo: _FakeRepo());

    await _save(c);

    expect(notes.scheduled, hasLength(1));
    final r = notes.scheduled.single;
    expect(r.sessionId, kProgressPhotoReminderId);
    final days = r.fireAt.difference(DateTime.now()).inDays;
    expect(days, inInclusiveRange(29, 30),
        reason: 'a month is what the operator chose, and it is what the '
            'compare card needs: at a week the difference is noise');
    expect(r.title, isNotEmpty);
    expect(r.body, isNotEmpty);
  });

  test('a second photo MOVES the reminder instead of adding one', () async {
    // The bug this pins: a per-photo id would leave a user with a year of
    // history holding twelve pending notifications.
    final notes = MockNotificationService();
    final c = _container(notes: notes, repo: _FakeRepo());

    await _save(c);
    await _save(c);

    expect(notes.scheduled, hasLength(1),
        reason: 'one pending nudge, always — the id is shared for this');
  });

  test('with reminders switched off, nothing is scheduled and the photo is '
      'still saved', () async {
    // What makes the Settings switch a real preference rather than a
    // decorative one.
    final notes = MockNotificationService();
    final repo = _FakeRepo();
    final c =
        _container(notes: notes, repo: repo, notificationsEnabled: false);

    await _save(c);

    expect(notes.scheduled, isEmpty);
    expect(repo.saves, 1);
    expect(notes.permissionRequests, 0,
        reason: 'a switched-off reminder must not raise a permission dialog');
  });

  test('a reminder that cannot be registered does not fail the save',
      () async {
    // The photo is encrypted and on disk before this runs. Surfacing a
    // notification failure as a save failure would tell the user their photo
    // was lost when it was not.
    final repo = _FakeRepo();
    final c = _container(notes: _ThrowingNotifications(), repo: repo);

    await expectLater(_save(c), completes);
    expect(repo.saves, 1);
    expect(c.read(progressPhotosControllerProvider).hasError, isFalse,
        reason: 'the save succeeded, so the controller must not report an '
            'error the user would see as a lost photo');
  });
}
