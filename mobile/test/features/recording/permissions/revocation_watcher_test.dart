// S04-19 (DT-19-1, DT-19-2, DT-19-4): revocation DETECTION. Stopping and the
// Keep/Delete decision are other lanes; this guards the detector contract.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/recording/permissions/fake_permission_service.dart';
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/permissions/permission_revocation_watcher.dart';

class _SlowPermissions extends FakePermissionService {
  _SlowPermissions(this.gate) : super(location: LocationPermissionStatus.grantedPrecise);
  final Completer<void> gate;
  @override
  Future<LocationPermissionStatus> locationStatus() async {
    locationStatusCount++;
    await gate.future;
    return location;
  }
}

void main() {
  group('check()', () {
    test('precise granted -> stillGranted', () async {
      final w = PermissionRevocationWatcher(FakePermissionService(
          location: LocationPermissionStatus.grantedPrecise));
      expect(await w.check(), RevocationCheck.stillGranted);
    });

    for (final s in LocationPermissionStatus.values
        .where((s) => s != LocationPermissionStatus.grantedPrecise)) {
      test('${s.name} -> revoked (incl. precise->approximate downgrade)',
          () async {
        final w = PermissionRevocationWatcher(FakePermissionService(location: s));
        expect(await w.check(), RevocationCheck.revoked);
      });
    }

    test('a failing platform read is unknown, never revoked, never throws',
        () async {
      final f = FakePermissionService(
          location: LocationPermissionStatus.grantedPrecise)
        ..locationStatusError = Exception('lat=12.3456789 lon=-98.7654321');
      final w = PermissionRevocationWatcher(f);
      expect(await w.check(), RevocationCheck.unknown);
    });

    test('check never requests a permission (request counter unchanged)',
        () async {
      final f = FakePermissionService(location: LocationPermissionStatus.denied);
      final w = PermissionRevocationWatcher(f);
      await w.check();
      await w.check();
      expect(f.requestCount, 0);
      expect(f.openSettingsCount, 0);
    });
  });

  group('timer', () {
    test('start is idempotent and sets isRunning; stop is idempotent', () {
      fakeAsync((a) {
        final w = PermissionRevocationWatcher(FakePermissionService(
            location: LocationPermissionStatus.grantedPrecise));
        expect(w.isRunning, isFalse);
        w.start();
        w.start();
        expect(w.isRunning, isTrue);
        w.stop();
        w.stop();
        expect(w.isRunning, isFalse);
        a.flushMicrotasks();
      });
    });

    test('revocation is detected within 2 s of fake time (DT-19-1)', () {
      fakeAsync((a) {
        final f = FakePermissionService(
            location: LocationPermissionStatus.grantedPrecise);
        final w = PermissionRevocationWatcher(f);
        var fired = 0;
        w.onRevoked.listen((_) => fired++);
        w.start();
        a.elapse(const Duration(milliseconds: 3500));
        expect(fired, 0, reason: 'still granted: no event');
        f.location = LocationPermissionStatus.denied;
        a.elapse(const Duration(seconds: 2));
        expect(fired, 1);
        w.stop();
      });
    });

    test('fires once per start even while denial persists (DT-19-4)', () {
      fakeAsync((a) {
        final f =
            FakePermissionService(location: LocationPermissionStatus.denied);
        final w = PermissionRevocationWatcher(f);
        var fired = 0;
        w.onRevoked.listen((_) => fired++);
        w.start();
        a.elapse(const Duration(seconds: 10));
        expect(fired, 1);
        w.stop();
      });
    });

    test('granting again does not auto-resume or re-fire; a fresh start '
        're-arms', () {
      fakeAsync((a) {
        final f =
            FakePermissionService(location: LocationPermissionStatus.denied);
        final w = PermissionRevocationWatcher(f);
        var fired = 0;
        w.onRevoked.listen((_) => fired++);
        w.start();
        a.elapse(const Duration(seconds: 2));
        expect(fired, 1);
        f.location = LocationPermissionStatus.grantedPrecise;
        a.elapse(const Duration(seconds: 3));
        f.location = LocationPermissionStatus.denied;
        a.elapse(const Duration(seconds: 3));
        expect(fired, 1, reason: 'one event per start');
        w.stop();
        w.start();
        a.elapse(const Duration(seconds: 2));
        expect(fired, 2);
        w.stop();
      });
    });

    test('an unknown read never fires; later revocation still does', () {
      fakeAsync((a) {
        final f = FakePermissionService(
            location: LocationPermissionStatus.grantedPrecise)
          ..locationStatusError = StateError('boom');
        final w = PermissionRevocationWatcher(f);
        var fired = 0;
        w.onRevoked.listen((_) => fired++);
        w.start();
        a.elapse(const Duration(seconds: 5));
        expect(fired, 0);
        f.locationStatusError = null;
        f.location = LocationPermissionStatus.denied;
        a.elapse(const Duration(seconds: 2));
        expect(fired, 1);
        w.stop();
      });
    });

    test('no overlapping reads while one is in flight', () {
      fakeAsync((a) {
        final gate = Completer<void>();
        final f = _SlowPermissions(gate);
        final w = PermissionRevocationWatcher(f);
        w.start();
        a.elapse(const Duration(seconds: 5));
        expect(f.locationStatusCount, 1, reason: 'ticks skipped while busy');
        gate.complete();
        a.flushMicrotasks();
        a.elapse(const Duration(seconds: 1));
        expect(f.locationStatusCount, 2);
        w.stop();
      });
    });

    test('stop while a read is in flight suppresses the event', () {
      fakeAsync((a) {
        final gate = Completer<void>();
        final f = _SlowPermissions(gate)
          ..location = LocationPermissionStatus.denied;
        final w = PermissionRevocationWatcher(f);
        var fired = 0;
        w.onRevoked.listen((_) => fired++);
        w.start();
        a.elapse(const Duration(seconds: 1));
        w.stop();
        gate.complete();
        a.flushMicrotasks();
        expect(fired, 0);
      });
    });

    test('custom period is honoured', () {
      fakeAsync((a) {
        final f = FakePermissionService(
            location: LocationPermissionStatus.grantedPrecise);
        final w = PermissionRevocationWatcher(f,
            period: const Duration(milliseconds: 250));
        w.start();
        a.elapse(const Duration(seconds: 1));
        expect(f.locationStatusCount, 4);
        w.stop();
      });
    });

    test('a stopped watcher makes no further reads', () {
      fakeAsync((a) {
        final f = FakePermissionService(
            location: LocationPermissionStatus.grantedPrecise);
        final w = PermissionRevocationWatcher(f);
        w.start();
        a.elapse(const Duration(seconds: 2));
        final n = f.locationStatusCount;
        w.stop();
        a.elapse(const Duration(seconds: 10));
        expect(f.locationStatusCount, n);
      });
    });

    test('the watcher never requests a permission while detecting', () {
      fakeAsync((a) {
        final f =
            FakePermissionService(location: LocationPermissionStatus.denied);
        final w = PermissionRevocationWatcher(f);
        w.start();
        a.elapse(const Duration(seconds: 10));
        expect(f.requestCount, 0);
        w.stop();
      });
    });

    test('dispose stops the timer and closes the stream', () async {
      final w = PermissionRevocationWatcher(FakePermissionService(
          location: LocationPermissionStatus.grantedPrecise));
      final done = Completer<void>();
      w.onRevoked.listen((_) {}, onDone: done.complete);
      w.start();
      await w.dispose();
      expect(w.isRunning, isFalse);
      await done.future.timeout(const Duration(seconds: 2));
    });
  });
}
