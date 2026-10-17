// S04-04 Foreground service, manifest, release on every stop path
// (DT-04-1 .. DT-04-7) and the controller half of S04-05 sampling
// (DT-05-1, DT-05-2, DT-05-3 structural half).
import 'dart:async';
import 'dart:io';

import 'package:fitness_app/features/recording/location/fix.dart';
import 'package:fitness_app/features/recording/location/location_source.dart';
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/pipeline/recording_constants.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recorder_state_constants.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording/recorder_world.dart';
import '../../../support/recording/scan_support.dart';

/// A location source whose release steps can be made to throw.
class ThrowingLocationSource implements LocationSource {
  bool throwOnStop = false;
  bool throwOnCancel = false;
  int stopCalls = 0;
  int cancelCalls = 0;
  StreamController<Fix>? _c;
  final StreamController<void> _detached = StreamController<void>.broadcast();
  bool _listening = false;

  @override
  int get activeSubscriptions => _listening ? 1 : 0;

  @override
  Stream<void> get engineDetached => _detached.stream;

  @override
  Stream<Fix> start(LocationRequest request) {
    _c = StreamController<Fix>(
      onListen: () => _listening = true,
      onCancel: () {
        cancelCalls++;
        _listening = false;
        if (throwOnCancel) throw StateError('cancel failed');
      },
    );
    return _c!.stream;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (throwOnStop) throw StateError('service stop failed');
  }

  @override
  Future<void> setInterval(int seconds) async {}

  void emit(Fix f) => _c?.add(f);
}

List<String> _manifestPermissions(String xml) => RegExp(
        r'<uses-permission[^>]*android:name="([^"]+)"')
    .allMatches(xml)
    .map((m) => m.group(1)!)
    .toList();

void main() {
  group('DT-04-1 manifest permissions (source manifest)', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    // XML comments may mention names; permissions are read from live tags only.
    final live = manifest.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    final declared = _manifestPermissions(live);

    test('the forbidden permissions are absent', () {
      for (final p in [
        'android.permission.ACCESS_BACKGROUND_LOCATION',
        'android.permission.ACTIVITY_RECOGNITION',
        'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      ]) {
        expect(declared, isNot(contains(p)), reason: p);
      }
    });

    test('the source manifest declares no location or foreground-service '
        'entry: the flag-gated build transform owns them (design 2.3)', () {
      for (final p in [
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_LOCATION',
      ]) {
        expect(declared, isNot(contains(p)),
            reason: '$p must come only from the gated merge');
      }
      expect(declared, contains('android.permission.POST_NOTIFICATIONS'));
    });

    test('the manifest comment block explains the gate and the exclusions',
        () {
      expect(manifest, contains('S04 GPS recorder'));
      expect(manifest, contains('GpsManifestGate'));
      expect(manifest, contains('ACCESS_BACKGROUND_LOCATION'));
      expect(manifest, contains('ACTIVITY_RECOGNITION'));
    });

    test('the build gate lists exactly the approved set and strips the '
        'background permission always', () {
      final gradle = File('android/app/build.gradle').readAsStringSync();
      for (final p in [
        'android.permission.ACCESS_FINE_LOCATION',
        'android.permission.ACCESS_COARSE_LOCATION',
        'android.permission.FOREGROUND_SERVICE',
        'android.permission.FOREGROUND_SERVICE_LOCATION',
      ]) {
        expect(gradle, contains("'$p'"), reason: p);
      }
      expect(gradle,
          contains("backgroundPermission = 'android.permission.ACCESS_BACKGROUND_LOCATION'"));
      expect(gradle, contains('Always: background location is never declared'));
      // Flag off removes the entries; flag on fails a build without the set.
      expect(gradle, contains('if (!gpsRecorder.get())'));
      expect(gradle, contains('throw new GradleException'));
      expect(gradle, isNot(contains('REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')));
      expect(gradle, isNot(contains('ACTIVITY_RECOGNITION')));
    });
  });

  group('DT-04-2 service element', () {
    test('the app manifest declares no second or exported location service',
        () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync()
          .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      final services =
          RegExp(r'<service\b[^>]*>').allMatches(manifest).map((m) => m.group(0)!);
      for (final s in services) {
        expect(s.contains('foregroundServiceType'), isFalse,
            reason: 'a location service declared in the app manifest would '
                'duplicate the plugin one: $s');
      }
    });

    test('NOT_RUN part: the merged plugin manifest (exported="false", '
        'foregroundServiceType="location") needs a build', () {
      // Recorded as NOT_RUN in the findings file; the gate task itself
      // matches the service by type or by the plugin class name.
      final gradle = File('android/app/build.gradle').readAsStringSync();
      expect(gradle, contains('GeolocatorLocationService'));
      expect(gradle, contains("contains('location')"));
    });
  });

  group('DT-04-3 collection starts only from a user tap', () {
    test('requestStart and resumeRecovered are called only by the start flow',
        () {
      final callers = <String>{};
      for (final f in allLibSources()) {
        if (f.path.endsWith('recorder_controller.dart')) continue;
        if (RegExp(r'\.requestStart\(|\.resumeRecovered\(').hasMatch(f.code)) {
          callers.add(f.path);
        }
      }
      expect(callers, {'lib/features/recording/widgets/gps_start_flow.dart'});
    });

    test('LocationSource.start is called only from the controller', () {
      final callers = <String>{};
      for (final f in allLibSources()) {
        if (RegExp(r'\.start\(\s*(const\s+)?LocationRequest\(')
            .hasMatch(f.code)) {
          callers.add(f.path);
        }
      }
      expect(callers,
          {'lib/features/recording/state/recorder_controller.dart'});
    });

    test('native code and launch paths contain no location start', () {
      final kt = Directory('android/app/src/main');
      for (final e in kt.listSync(recursive: true)) {
        if (e is File &&
            (e.path.endsWith('.kt') || e.path.endsWith('.java'))) {
          final t = e.readAsStringSync();
          expect(
              RegExp(r'requestLocationUpdates|startForeground\(|LocationManager')
                  .hasMatch(t),
              isFalse,
              reason: e.path);
        }
      }
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('requestStart('), isFalse);
      expect(main.contains('resumeRecovered('), isFalse);
    });
  });

  group('DT-04-4 every stop path releases within 2 s', () {
    Future<RecorderWorld> recording() async {
      final w = RecorderWorld.create();
      await w.start();
      await w.walk(5);
      expect(w.phase, RecorderPhase.recording);
      expect(w.location.activeSubscriptions, 1);
      expect(w.fa.periodicTimerCount, greaterThan(0),
          reason: 'tick and permission watcher run while recording');
      return w;
    }

    void expectReleased(RecorderWorld w) {
      expect(w.location.activeSubscriptions, 0);
      expect(w.location.stopCount, 1, reason: 'service stop called once');
      expect(w.fa.periodicTimerCount, 0, reason: 'timers cancelled');
    }

    test('/stop', () async {
      final w = await recording();
      await w.stop();
      await w.advance(const Duration(seconds: 2));
      expectReleased(w);
      expect(w.phase, RecorderPhase.finished);
      await w.dispose();
    });

    test('/discard', () async {
      final w = await recording();
      await w.discard();
      await w.advance(const Duration(seconds: 2));
      expectReleased(w);
      expect(w.phase, RecorderPhase.idle);
      expect(w.journal.deletes.length, 1);
      await w.dispose();
    });

    test('/permission-loss', () async {
      final w = await recording();
      w.permissions.location = LocationPermissionStatus.denied;
      await w.advance(const Duration(seconds: 2));
      expectReleased(w);
      expect(w.phase, RecorderPhase.permissionRevoked);
      await w.dispose();
    });

    test('/battery-finish', () async {
      final w = await recording();
      await w.run(() => w.battery.emit(2));
      await w.advance(const Duration(seconds: 2));
      expectReleased(w);
      expect(w.phase, RecorderPhase.finished);
      expect(w.journal.eventKinds, contains(JournalEventKind.stoppedBattery));
      expect(w.state.autoStopNotice?.reason, StopReason.battery);
      await w.dispose();
    });

    test('/sign-out', () async {
      final w = await recording();
      await w.run(() =>
          unawaited(w.controller.stopAutomatically(StopReason.account)));
      await w.advance(const Duration(seconds: 2));
      expectReleased(w);
      expect(w.phase, RecorderPhase.finished);
      await w.dispose();
    });

    test('a stop from acquiring with no fix discards and releases', () async {
      final w = RecorderWorld.create();
      await w.start();
      expect(w.phase, RecorderPhase.acquiring);
      await w.stop();
      await w.advance(const Duration(seconds: 2));
      expectReleased(w);
      expect(w.phase, RecorderPhase.idle);
      expect(w.journal.seals, isEmpty, reason: 'nothing recorded: nothing saved');
      expect(w.journal.deletes.length, 1);
      await w.dispose();
    });

    test('disposing the container while recording stops the service and '
        'cancels the timers', () async {
      final w = await recording();
      await w.dispose();
      expect(w.location.activeSubscriptions, 0);
      expect(w.location.stopCount, greaterThanOrEqualTo(1));
      expect(w.fa.periodicTimerCount, 0);
    });
  });

  group('DT-04-5 one failing release step does not skip the others', () {
    test('/service-stop-throws: the journal is flushed, sealed and handed '
        'off; the subscription count is 0', () async {
      final src = ThrowingLocationSource()..throwOnStop = true;
      final w2 = _worldWith(src);
      await w2.start();
      src.emit(w2.fixAt(1, 1.4, speed: 1.4));
      await w2.advance(const Duration(seconds: 1));
      src.emit(w2.fixAt(2, 2.8, speed: 1.4));
      await w2.advance(const Duration(seconds: 1));
      await w2.stop();
      await w2.advance(const Duration(seconds: 2));
      expect(src.stopCalls, 1);
      expect(src.cancelCalls, 1, reason: 'the subscription was cancelled');
      expect(src.activeSubscriptions, 0);
      expect(w2.journal.flushCount, greaterThan(0));
      expect(w2.journal.seals.length, 1);
      expect(w2.journal.handOffCount, 1);
      expect(w2.phase, RecorderPhase.finished);
      expect(w2.fa.periodicTimerCount, 0);
      await w2.dispose();
    });

    test('/subscription-cancel-throws: the service is still stopped and the '
        'recording is still saved', () async {
      final src = ThrowingLocationSource()..throwOnCancel = true;
      final w = _worldWith(src);
      await w.start();
      src.emit(w.fixAt(1, 1.4, speed: 1.4));
      await w.advance(const Duration(seconds: 1));
      src.emit(w.fixAt(2, 2.8, speed: 1.4));
      await w.advance(const Duration(seconds: 1));
      await w.stop();
      await w.advance(const Duration(seconds: 2));
      expect(src.stopCalls, 1);
      expect(src.activeSubscriptions, 0);
      expect(w.journal.seals.length, 1);
      expect(w.phase, RecorderPhase.finished);
      await w.dispose();
    });

    test('a failing journal flush still seals and hands off', () async {
      final w = RecorderWorld.create();
      await w.start();
      await w.walk(4);
      w.journal.flushError = StateError('disk');
      await w.stop();
      await w.advance(const Duration(seconds: 2));
      expect(w.location.stopCount, 1);
      expect(w.journal.seals.length, 1);
      expect(w.journal.handOffCount, 1);
      expect(w.phase, RecorderPhase.finished);
      await w.dispose();
    });

    test('a failing hand-off leaves a kept recording and reports it', () async {
      final w = RecorderWorld.create();
      await w.start();
      await w.walk(4);
      w.journal.handOffResult = HandOffResult.failedKept;
      await w.stop();
      expect(w.phase, RecorderPhase.idle);
      expect(w.state.handOffFailed, isTrue);
      expect(w.location.activeSubscriptions, 0);
      await w.dispose();
    });
  });

  group('DT-04-6 / DT-04-7 notification content and Stop action', () {
    test('the foreground notification text comes from the environment, '
        'contains no coordinate and is passed on the start request', () async {
      final w = RecorderWorld.create();
      await w.start();
      final req = w.location.startRequests.single;
      expect(req.notificationTitle, w.env.notificationTitle);
      expect(req.notificationText, w.env.notificationText);
      final text = '${req.notificationTitle} ${req.notificationText}';
      expect(RegExp(r'\d+\.\d{3,}').hasMatch(text), isFalse,
          reason: 'no coordinate in the notification');
      await w.dispose();
    });

    test('NOT_RUN: the notification content builder (/content-per-state, '
        '/throttle) and the FakeNotificationHost Finish action have no '
        'production symbol yet', () {
      // Search proves the symbols do not exist; the row stays NOT_RUN.
      final all = allLibSources();
      final builders = all.where((f) => f.code.contains('NotificationContentBuilder') ||
          f.code.contains('FakeNotificationHost'));
      expect(builders, isEmpty,
          reason: 'when these appear, write DT-04-6 and DT-04-7 for real');
    });
  });

  group('DT-05-1 / DT-05-2 sampling configuration', () {
    test('3600 s run: one request at 1 s, no interval change, every fix kept',
        () async {
      final w = RecorderWorld.create();
      await w.start();
      await w.walk(3600);
      expect(w.location.startRequests.length, 1);
      final req = w.location.startRequests.single;
      expect(req.intervalSeconds, 1);
      expect(req.intervalSeconds * 1000, kSamplingIntervalMs);
      expect(req.distanceFilterMeters, 0, reason: 'no min distance');
      expect(w.location.intervalCalls, isEmpty,
          reason: 'the rate is never raised or lowered while moving');
      expect(w.journal.samples.length, 3600);
      expect(w.state.metrics!.keptCount, 3600);
      await w.dispose();
    });

    test('constants: 1 s sampling, 5 s at battery critical, 10 s manual pause',
        () {
      expect(kSamplingIntervalMs, 1000);
      expect(kBatteryCriticalIntervalMs, 5000);
      expect(kManualPauseIntervalMs, 10000);
    });

    test('battery critical switches the interval to 5 s and back to 1 s',
        () async {
      final w = RecorderWorld.create();
      await w.start();
      await w.walk(3);
      await w.run(() => w.battery.emit(9));
      expect(w.location.intervalCalls.last, 5);
      expect(w.journal.flushIntervals.last, kBatteryCriticalFlushIntervalMs);
      expect(w.journal.eventKinds, contains(JournalEventKind.batteryCritical));
      // Hysteresis: 11 percent is still critical, 12 leaves it.
      await w.run(() => w.battery.emit(11));
      expect(w.state.flags.batteryCritical, isTrue);
      await w.run(() => w.battery.emit(12));
      expect(w.state.flags.batteryCritical, isFalse);
      expect(w.location.intervalCalls.last, 1);
      expect(w.journal.flushIntervals.last, kFlushIntervalMs);
      await w.dispose();
    });

    test('charging at 5 percent is not critical; 3 percent charging does not '
        'finish', () async {
      final w = RecorderWorld.create();
      await w.start();
      await w.walk(3);
      await w.run(() => w.battery.emit(5, charging: true));
      expect(w.state.flags.batteryCritical, isFalse);
      await w.run(() => w.battery.emit(3, charging: true));
      expect(w.phase, RecorderPhase.recording);
      await w.run(() => w.battery.emit(3));
      await w.advance(const Duration(seconds: 2));
      expect(w.phase, RecorderPhase.finished);
      await w.dispose();
    });
  });

  group('DT-05-3 only the approved fields exist (structural half)', () {
    test('Fix declares exactly time, lat, lon, accuracy, altitude, speed', () {
      final fix = File('lib/features/recording/location/fix.dart')
          .readAsStringSync();
      final fields = RegExp(r'^\s*final\s+[\w?]+\s+(\w+);', multiLine: true)
          .allMatches(fix)
          .map((m) => m.group(1)!)
          .toList();
      expect(fields, [
        'timeUtcMs',
        'latitude',
        'longitude',
        'accuracyMeters',
        'altitudeMeters',
        'speedMps',
      ]);
    });

    test('the adapter builds a Fix from the approved fields only', () {
      final adapter = File(
              'lib/features/recording/location/geolocator_location_source.dart')
          .readAsStringSync();
      final i = adapter.indexOf('=> Fix(');
      expect(i, greaterThan(0));
      final call = adapter.substring(i, adapter.indexOf(');', i));
      for (final bad in [
        'heading',
        'bearing',
        'provider',
        'satellite',
        'deviceId',
        'isMocked',
        'floor',
      ]) {
        expect(call.contains(bad), isFalse, reason: bad);
      }
      for (final good in [
        'timeUtcMs',
        'latitude',
        'longitude',
        'accuracyMeters',
        'altitudeMeters',
        'speedMps'
      ]) {
        expect(call.contains(good), isTrue, reason: good);
      }
    });
  });
}

/// A world around a custom location source (the stock one is replaced by
/// overriding the provider on a second container).
RecorderWorld _worldWith(LocationSource source) =>
    RecorderWorld.createWithLocation(source);
