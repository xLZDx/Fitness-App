// S04-17 (DT-17-1, DT-17-4, DT-17-5, DT-17-15): the permission seam and its
// scripted fake. The fake mirrors the real contract, so these tests guard the
// contract the controller relies on.
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/recording/permissions/fake_permission_service.dart';
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';

void main() {
  group('LocationPermissionStatus', () {
    test('only grantedPrecise allows recording (S04-R-023)', () {
      for (final s in LocationPermissionStatus.values) {
        expect(s.allowsRecording, s == LocationPermissionStatus.grantedPrecise,
            reason: s.name);
      }
    });

    test('needsSettings is true only for permanentlyDenied and restricted', () {
      final settings = LocationPermissionStatus.values
          .where((s) => s.needsSettings)
          .toSet();
      expect(settings, {
        LocationPermissionStatus.permanentlyDenied,
        LocationPermissionStatus.restricted,
      });
    });

    test('approximate is neither recording-capable nor settings-only', () {
      expect(LocationPermissionStatus.grantedApproximate.allowsRecording,
          isFalse);
      expect(LocationPermissionStatus.grantedApproximate.needsSettings,
          isFalse);
    });

    test('notification isGranted only for granted', () {
      expect(NotificationPermissionStatus.granted.isGranted, isTrue);
      expect(NotificationPermissionStatus.denied.isGranted, isFalse);
      expect(NotificationPermissionStatus.permanentlyDenied.isGranted, isFalse);
    });
  });

  group('FakePermissionService', () {
    test('a fresh fake has zero calls (launch requests nothing, DT-17-1)', () {
      final f = FakePermissionService();
      expect(f.totalCalls, 0);
      expect(f.requestCount, 0);
    });

    test('status reads never request and count separately', () async {
      final f = FakePermissionService(
          location: LocationPermissionStatus.grantedPrecise);
      expect(await f.locationStatus(), LocationPermissionStatus.grantedPrecise);
      expect(await f.notificationStatus(), NotificationPermissionStatus.granted);
      expect(f.locationStatusCount, 1);
      expect(f.notificationStatusCount, 1);
      expect(f.requestCount, 0);
      expect(f.totalCalls, 2);
    });

    test('requestLocation applies the scripted result and counts once',
        () async {
      final f = FakePermissionService(
          locationRequestResult: LocationPermissionStatus.grantedPrecise);
      expect(await f.requestLocation(), LocationPermissionStatus.grantedPrecise);
      expect(f.locationRequestCount, 1);
      expect(f.location, LocationPermissionStatus.grantedPrecise);
    });

    test('requestLocation with no scripted result leaves the status', () async {
      final f = FakePermissionService();
      expect(await f.requestLocation(), LocationPermissionStatus.denied);
      expect(f.location, LocationPermissionStatus.denied);
    });

    test('permanently denied never changes on request (DT-17-5)', () async {
      final f = FakePermissionService(
        location: LocationPermissionStatus.permanentlyDenied,
        locationRequestResult: LocationPermissionStatus.grantedPrecise,
      );
      for (var i = 0; i < 5; i++) {
        expect(await f.requestLocation(),
            LocationPermissionStatus.permanentlyDenied);
      }
      expect(f.location, LocationPermissionStatus.permanentlyDenied);
    });

    test('restricted never changes on request (DT-17-16)', () async {
      final f = FakePermissionService(
        location: LocationPermissionStatus.restricted,
        locationRequestResult: LocationPermissionStatus.grantedPrecise,
      );
      expect(await f.requestLocation(), LocationPermissionStatus.restricted);
    });

    test('approximate can be upgraded by a request', () async {
      final f = FakePermissionService(
        location: LocationPermissionStatus.grantedApproximate,
        locationRequestResult: LocationPermissionStatus.grantedPrecise,
      );
      expect(await f.requestLocation(), LocationPermissionStatus.grantedPrecise);
    });

    test('notification permanently denied is sticky, denied can move',
        () async {
      final sticky = FakePermissionService(
        notification: NotificationPermissionStatus.permanentlyDenied,
        notificationRequestResult: NotificationPermissionStatus.granted,
      );
      expect(await sticky.requestNotification(),
          NotificationPermissionStatus.permanentlyDenied);

      final movable = FakePermissionService(
        notification: NotificationPermissionStatus.denied,
        notificationRequestResult: NotificationPermissionStatus.granted,
      );
      expect(await movable.requestNotification(),
          NotificationPermissionStatus.granted);
      expect(movable.notificationRequestCount, 1);
    });

    test('requestCount sums location and notification requests', () async {
      final f = FakePermissionService();
      await f.requestLocation();
      await f.requestLocation();
      await f.requestNotification();
      expect(f.requestCount, 3);
      expect(f.locationRequestCount, 2);
      expect(f.notificationRequestCount, 1);
    });

    test('openSettings counts and returns the scripted result', () async {
      final f = FakePermissionService();
      expect(await f.openSettings(), isTrue);
      f.openSettingsResult = false;
      expect(await f.openSettings(), isFalse);
      expect(f.openSettingsCount, 2);
      expect(f.requestCount, 0, reason: 'opening settings is not a request');
    });

    test('locationStatusError makes the read throw (scripted platform error)',
        () async {
      final f = FakePermissionService()..locationStatusError = StateError('x');
      await expectLater(f.locationStatus(), throwsStateError);
      expect(f.locationStatusCount, 1);
    });

    test('flipping the status models a revocation', () async {
      final f = FakePermissionService(
          location: LocationPermissionStatus.grantedPrecise);
      expect(await f.locationStatus(), LocationPermissionStatus.grantedPrecise);
      f.location = LocationPermissionStatus.denied;
      expect(await f.locationStatus(), LocationPermissionStatus.denied);
    });

    test('20 scripted requests on a denied-forever status stay 20 calls, no '
        'status change (DT-17-15 seam)', () async {
      final f = FakePermissionService(
          location: LocationPermissionStatus.permanentlyDenied);
      for (var i = 0; i < 20; i++) {
        await f.requestLocation();
      }
      expect(f.locationRequestCount, 20);
      expect(f.location, LocationPermissionStatus.permanentlyDenied);
    });
  });
}
