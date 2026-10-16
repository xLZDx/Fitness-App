import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:fitness_app/core/diagnostics/debug_telemetry.dart';
import 'package:fitness_app/core/diagnostics/debug_telemetry_sink.dart';

SessionIdentity _identity() => const SessionIdentity(
      appVersion: '1.0.0',
      buildNumber: '14',
      gitSha: 'b37d18a',
      platform: 'android',
      builtAt: '2026-08-07T12:00:00Z',
    );

void main() {
  group('redact', () {
    test('removes email addresses', () {
      expect(redact('signed in as korostelev@example.com ok'),
          'signed in as [email] ok');
    });

    test('removes long opaque tokens', () {
      expect(
        redact('Bearer eyJhbGciOiJIUzI1NiwidHlwIjoiSldUIn0'),
        'Bearer [token]',
      );
    });

    test('removes android and windows user paths', () {
      expect(redact('wrote /data/user/0/com.fitnessapp/files/a.jpg'),
          'wrote [path]');
      expect(redact(r'opened C:\Users\koros\secret.json'), 'opened [path]');
    });

    test('removes long digit runs', () {
      expect(redact('uid 380671234567 synced'), 'uid [number] synced');
    });

    test('leaves ordinary diagnostic text intact', () {
      // The control. Redaction that ate everything would pass every test
      // above while making the log useless.
      const line = 'scanner: cloud timeout after 20s, falling back on-device';
      expect(redact(line), line);
    });

    test('does not mangle a short confidence value', () {
      expect(redact('treadmill 0.892'), 'treadmill 0.892');
    });
  });

  group('DebugTelemetry', () {
    test('identity is carried in the payload', () {
      // The whole reason this class exists: a log that cannot name its build
      // cannot settle "is your APK older than the fix?".
      final t = DebugTelemetry(identity: _identity());
      final json = t.toJson();
      expect((json['identity']! as Map)['gitSha'], 'b37d18a');
      expect((json['identity']! as Map)['builtAt'], '2026-08-07T12:00:00Z');
    });

    test('redacts on the way in, not on the way out', () {
      final t = DebugTelemetry(identity: _identity());
      t.log('auth', 'login for korostelev@example.com');
      expect(t.events.single.message, 'login for [email]');
    });

    test('drops the oldest events past capacity and counts them', () {
      // A live-recognition session emits per frame. Unbounded here is an OOM
      // caused by the diagnostics themselves.
      final t = DebugTelemetry(identity: _identity(), capacity: 3);
      for (var i = 0; i < 5; i++) {
        t.log('scanner', 'frame $i');
      }
      expect(t.events.map((e) => e.message), ['frame 2', 'frame 3', 'frame 4']);
      expect(t.droppedCount, 2,
          reason: 'a truncated log must not read as a complete one');
    });

    test('a log that fits drops nothing', () {
      final t = DebugTelemetry(identity: _identity(), capacity: 3);
      t.log('scanner', 'one');
      expect(t.droppedCount, 0);
    });

    test('events carry level and area', () {
      final t = DebugTelemetry(
        identity: _identity(),
        now: () => DateTime.utc(2026, 8, 7, 12),
      );
      t.log('camera', 'permission permanently denied', level: LogLevel.error);
      final e = t.events.single;
      expect(e.area, 'camera');
      expect(e.level, LogLevel.error);
      expect(e.at, DateTime.utc(2026, 8, 7, 12));
      expect(e.toJson()['level'], 'error');
    });
  });
  group('captureDebugPrint', () {
    test('routes debugPrint into the log and still prints', () {
      final t = DebugTelemetry(identity: _identity());
      final seen = <String?>[];
      final outer = debugPrint;
      debugPrint = (m, {int? wrapWidth}) => seen.add(m);

      final restore = captureDebugPrint(t);
      debugPrint('camera: permission denied');
      restore();
      debugPrint = outer;

      expect(t.events.single.message, 'camera: permission denied');
      expect(seen, ['camera: permission denied'],
          reason: 'capturing must not take the console away');
    });

    test('restoring puts the previous debugPrint back', () {
      // Without this, a capture left installed by one test silently swallows
      // every later test's output into a dead object.
      final t = DebugTelemetry(identity: _identity());
      final before = debugPrint;
      final restore = captureDebugPrint(t);
      expect(identical(debugPrint, before), isFalse);
      restore();
      expect(identical(debugPrint, before), isTrue);
    });

    test('captured lines are redacted like any other', () {
      final t = DebugTelemetry(identity: _identity());
      final outer = debugPrint;
      debugPrint = (m, {int? wrapWidth}) {};
      final restore = captureDebugPrint(t);
      debugPrint('sync failed for korostelev@example.com');
      restore();
      debugPrint = outer;
      expect(t.events.single.message, 'sync failed for [email]');
    });
  });

  // S02 test epic 3, U26: the client redaction also removes location and
  // heart-rate shaped values (design 8, "additional defence").
  group('U26 redaction of location, heart-rate and place values', () {
    const sentinels = <String, String>{
      'coordinate pair': 'at 51.507351, -0.127758 now',
      'coordinate pair no comma': 'at 51.507351 -0.127758 now',
      'labelled lat/lon': 'fix lat=51.507351 lon=-0.127758 ok',
      'geohash labelled': 'cell geohash: gcpvj0duq ok',
      'geohash bare': 'cell gcpvj0duq ok',
      'hr value': 'sample hr 173.25 ok',
      'heart rate words': 'heart rate: 173 recorded',
      'bpm suffix': 'peak 173.25 bpm ok',
      'place name': 'started at place=Hyde Park Corner',
      'city label': 'city: London, UK',
    };
    const secrets = <String, List<String>>{
      'coordinate pair': ['51.507351', '0.127758'],
      'coordinate pair no comma': ['51.507351', '0.127758'],
      'labelled lat/lon': ['51.507351', '0.127758'],
      'geohash labelled': ['gcpvj0duq'],
      'geohash bare': ['gcpvj0duq'],
      'hr value': ['173.25'],
      'heart rate words': ['173'],
      'bpm suffix': ['173.25'],
      'place name': ['Hyde Park'],
      'city label': ['London'],
    };
    for (final e in sentinels.entries) {
      test('${e.key} does not survive redact()', () {
        final out = redact(e.value);
        for (final s in secrets[e.key]!) {
          expect(out, isNot(contains(s)), reason: out);
        }
      });
    }

    test('ordinary diagnostic text is left alone (controls)', () {
      for (final line in [
        'scanner: cloud timeout after 20s, falling back on-device',
        'treadmill 0.892',
        'retry 3 of 5 after 120 ms',
        'build 1.0.0+14 started',
        'component sync finished',
      ]) {
        expect(redact(line), line);
      }
    });
  });

}
