// S04-01 Location seam and import guard (R-003, R-005): rows DT-01-1 .. DT-01-7.
import 'dart:async';

import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/recording/location/fake_location_source.dart';
import 'package:fitness_app/features/recording/location/fix.dart';
import 'package:fitness_app/features/recording/location/location_source.dart';
import 'package:fitness_app/features/recording/permissions/fake_permission_service.dart';
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/state/recorder_phase.dart';
import 'package:fitness_app/features/recording/state/recording_journal_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recording/recorder_world.dart';
import '../../../support/recording/scan_support.dart';

void main() {
  group('DT-01-1 no collection outside a recording', () {
    test('/launch: cold start and idle time never subscribe', () async {
      final w = RecorderWorld.create();
      expect(w.location.activeSubscriptions, 0);
      expect(w.location.startCount, 0);
      await w.advance(const Duration(seconds: 30));
      expect(w.location.activeSubscriptions, 0);
      expect(w.location.startCount, 0);
      // The permission service is not even asked at launch.
      expect(w.permissions.totalCalls, 0);
      // The unfinished-recording check at app start does not start collection.
      await w.run(() => unawaited(w.controller.checkUnfinished()));
      await w.advance(const Duration(seconds: 5));
      expect(w.location.activeSubscriptions, 0);
      expect(w.location.startCount, 0);
      await w.dispose();
    });

    test('/sign-out: an account stop in idle starts nothing; during a '
        'recording it releases within 2 s', () async {
      final w = RecorderWorld.create();
      await w.run(() => unawaited(
          w.controller.stopAutomatically(StopReason.account)));
      expect(w.location.startCount, 0);
      expect(w.location.activeSubscriptions, 0);

      await w.start();
      await w.walk(5);
      expect(w.location.activeSubscriptions, 1);
      await w.run(() => unawaited(
          w.controller.stopAutomatically(StopReason.account)));
      await w.advance(const Duration(seconds: 2));
      expect(w.location.activeSubscriptions, 0);
      expect(w.journal.eventKinds, contains(JournalEventKind.stoppedAccount));
      await w.dispose();
    });

    test('/boot-start: a boot with an unfinished journal waits for the user',
        () async {
      final w = RecorderWorld.create();
      w.journal.unfinished = const [
        UnfinishedRecording(
            recordingId: 'old',
            status: UnfinishedStatus.readable,
            startUtcMs: 1,
            sport: SportType.walking,
            lastOffsetMs: 4000,
            sampleCount: 4)
      ];
      await w.run(() => unawaited(w.controller.checkUnfinished()));
      expect(w.phase, RecorderPhase.restoring);
      await w.advance(const Duration(minutes: 5));
      expect(w.location.startCount, 0,
          reason: 'recovery offers a choice; it never starts by itself');
      expect(w.location.activeSubscriptions, 0);
      await w.dispose();
    });

    test('/recording-end: one subscription exactly while recording', () async {
      final w = RecorderWorld.create();
      expect(w.location.activeSubscriptions, 0);
      await w.start();
      expect(w.location.activeSubscriptions, 1);
      expect(w.location.startCount, 1);
      await w.walk(5);
      await w.stop();
      await w.advance(const Duration(seconds: 2));
      expect(w.location.activeSubscriptions, 0);
      expect(w.location.stopCount, 1);
      // Nothing resubscribes afterwards.
      await w.advance(const Duration(seconds: 60));
      expect(w.location.activeSubscriptions, 0);
      expect(w.location.startCount, 1);
      await w.dispose();
    });

    test('a refused start (no consent / no permission) never subscribes',
        () async {
      final w = RecorderWorld.create(
          permission: LocationPermissionStatus.denied);
      await w.start();
      expect(w.location.startCount, 0);
      expect(w.location.activeSubscriptions, 0);
      expect(w.phase, RecorderPhase.idle);
      await w.dispose();

      final w2 = RecorderWorld.create();
      w2.env.locationConsentGranted = false;
      await w2.start();
      expect(w2.location.startCount, 0);
      expect(w2.phase, RecorderPhase.idle);
      await w2.dispose();
    });
  });

  group('DT-01-2 only one file imports the location plugin', () {
    test('geolocator is imported only by the adapter under recording/location',
        () {
      final all = allLibSources();
      const plugins = [
        'package:geolocator',
        'package:location/',
        'package:background_location',
        'package:flutter_background_geolocation',
        'package:flutter_location',
        'package:geolocator_android',
        'package:geolocator_apple',
      ];
      final importers = <String>[];
      for (final f in all) {
        for (final l in f.importLines) {
          if (plugins.any(l.contains)) importers.add(f.path);
        }
      }
      expect(importers.toSet().toList(), [
        'lib/features/recording/location/geolocator_location_source.dart'
      ]);
    });

    test('sanity: the adapter exists and implements the seam', () {
      final adapter = recordingSources().singleWhere((f) =>
          f.path.endsWith('location/geolocator_location_source.dart'));
      expect(
          adapter.text.contains('implements LocationSource') ||
              adapter.text.contains('extends StreamLocationSource'),
          isTrue);
    });
  });

  group('DT-01-3 no map or network import in the recorder', () {
    test('recording/** imports no map, http, dio, socket or connectivity', () {
      const banned = [
        'package:http',
        'package:dio',
        'package:flutter_map',
        'package:google_maps_flutter',
        'package:mapbox',
        'package:latlong2',
        'package:connectivity',
        'package:web_socket',
        'package:cloud_firestore',
        'package:firebase_',
        'package:internet_connection_checker',
      ];
      final hits = <String>[];
      for (final f in recordingSources()) {
        for (final l in f.importLines) {
          if (banned.any(l.contains)) hits.add('${f.path}: $l');
        }
        if (RegExp(r'\b(HttpClient|Socket|WebSocket|InternetAddress)\b')
            .hasMatch(f.code)) {
          hits.add('${f.path}: dart:io network class');
        }
      }
      expect(hits, isEmpty);
    });
  });

  group('DT-01-4 a full run needs no network', () {
    test('Start, 120 s of fixes, pause, resume, Stop, hand-off, Done with '
        'every network-ish adapter absent', () async {
      // The recorder has no network port at all (DT-01-3 proves it by import
      // scan); the world offers none, so a network need would not compile or
      // would throw. The run must succeed end to end.
      final w = RecorderWorld.create();
      await w.start();
      var x = await w.walk(60);
      await w.pause();
      await w.advance(const Duration(seconds: 5));
      await w.resume();
      x = await w.walk(60, fromEastM: x);
      expect(w.phase, RecorderPhase.recording);
      await w.stop();
      expect(w.phase, RecorderPhase.finished);
      expect(w.journal.begun.length, 1);
      expect(w.journal.seals.length, 1);
      expect(w.journal.handOffCount, 1);
      await w.acknowledge();
      expect(w.phase, RecorderPhase.idle);
      expect(w.state.handOffFailed, isFalse);
      await w.dispose();
    });
  });

  group('DT-01-5 the fakes can fail', () {
    test('FakeLocationSource: error event, closed stream, engine detach, '
        'second start, startError', () async {
      final src = FakeLocationSource();
      final events = <Object>[];
      var done = false;
      final stream = src.start(const LocationRequest(intervalSeconds: 1));
      final sub = stream.listen((f) => events.add(f),
          onError: (Object e) => events.add(e), onDone: () => done = true);
      expect(src.activeSubscriptions, 1);
      src.emit(const Fix(
          timeUtcMs: 1, latitude: 1, longitude: 2, accuracyMeters: 3));
      src.emitError(StateError('perm'));
      await Future<void>.delayed(Duration.zero);
      expect(events.length, 2);
      expect(events[1], isA<StateError>());
      expect(() => src.start(const LocationRequest()), throwsStateError,
          reason: 'a second concurrent start is a programming error');
      var detached = 0;
      final dSub = src.engineDetached.listen((_) => detached++);
      src.emitEngineDetached();
      await Future<void>.delayed(Duration.zero);
      expect(detached, 1);
      await src.stop();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue, reason: 'stop closes the stream');
      expect(src.activeSubscriptions, 0);
      expect(src.stopCount, 1);
      src.startError = StateError('boom');
      expect(() => src.start(const LocationRequest()), throwsStateError);
      await sub.cancel();
      await dSub.cancel();
      await src.dispose();
    });

    test('FakeLocationSource: cancel ends the subscription and a later start '
        'is allowed; setInterval is recorded only while started', () async {
      final src = FakeLocationSource();
      await src.setInterval(5);
      expect(src.intervalCalls, isEmpty);
      final sub = src.start(const LocationRequest()).listen((_) {});
      await src.setInterval(10);
      expect(src.intervalCalls, [10]);
      await sub.cancel();
      expect(src.activeSubscriptions, 0);
      final again = src.start(const LocationRequest()).listen((_) {});
      expect(src.activeSubscriptions, 1);
      expect(src.startCount, 2);
      await again.cancel();
      await src.dispose();
    });

    test('FakePermissionService reports a permission change mid-run and '
        'counts every call', () async {
      final p = FakePermissionService(
          location: LocationPermissionStatus.grantedPrecise);
      expect(await p.locationStatus(), LocationPermissionStatus.grantedPrecise);
      p.location = LocationPermissionStatus.denied;
      expect(await p.locationStatus(), LocationPermissionStatus.denied);
      p.locationStatusError = StateError('read failed');
      await expectLater(p.locationStatus(), throwsStateError);
      expect(p.locationStatusCount, 3);
      p.location = LocationPermissionStatus.permanentlyDenied;
      p.locationRequestResult = LocationPermissionStatus.grantedPrecise;
      expect(await p.requestLocation(),
          LocationPermissionStatus.permanentlyDenied,
          reason: 'a permanently denied permission never prompts');
      expect(p.requestCount, 1);
    });

    test('permission loss mid-recording is observable by the controller',
        () async {
      final w = RecorderWorld.create();
      await w.start();
      await w.walk(3);
      w.permissions.location = LocationPermissionStatus.denied;
      await w.advance(const Duration(seconds: 3));
      expect(w.phase, RecorderPhase.permissionRevoked);
      expect(w.location.activeSubscriptions, 0);
      await w.dispose();
    });
  });

  group('DT-01-6 permission calls live in one place', () {
    test('location/notification permission symbols appear only in '
        'recording/permissions and the user-tap start flow', () {
      final hits = <String>[];
      for (final f in allLibSources()) {
        final inPerm = f.path.contains('lib/features/recording/permissions/');
        final isFlow =
            f.path.endsWith('lib/features/recording/widgets/gps_start_flow.dart');
        final isAdapter = f.path.endsWith(
            'lib/features/recording/location/geolocator_location_source.dart');
        final uses = RegExp(
                r'Permission\.(location|locationWhenInUse|locationAlways|notification)\b|Geolocator\.(request|check)Permission|\.requestLocation\(|\.requestNotification\(')
            .hasMatch(f.code);
        if (uses && !inPerm && !isFlow && !isAdapter) hits.add(f.path);
      }
      expect(hits, isEmpty);
    });

    test('no permission request from launch, router, home or onboarding code',
        () {
      final hits = <String>[];
      for (final f in allLibSources()) {
        final launchy = f.path == 'lib/main.dart' ||
            f.path.startsWith('lib/core/router/') ||
            f.path.startsWith('lib/features/home/') ||
            f.path.contains('onboarding');
        if (!launchy) continue;
        if (RegExp(r'\.requestLocation\(|\.requestNotification\(|locationStatus\(')
            .hasMatch(f.code)) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty);
    });
  });

  group('DT-01-7 the pipeline stays a pure layer', () {
    test('pipeline/ imports no Flutter, dart:io, dart:ui or Riverpod', () {
      final pipeline = recordingSources()
          .where((f) => f.path.contains('lib/features/recording/pipeline/'))
          .toList();
      expect(pipeline.length, greaterThanOrEqualTo(10));
      final hits = <String>[];
      for (final f in pipeline) {
        for (final l in f.importLines) {
          if (l.contains('package:flutter') ||
              l.contains('dart:io') ||
              l.contains('dart:ui') ||
              l.contains('riverpod')) {
            hits.add('${f.path}: $l');
          }
        }
      }
      expect(hits, isEmpty);
    });
  });
}
