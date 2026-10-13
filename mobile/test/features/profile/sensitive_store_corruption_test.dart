import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/profile/data/device_health_profile_repository.dart';
import 'package:fitness_app/features/profile/data/local_sensitive_store.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/sensitive_profile.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

/// CR-07. A structurally wrong sensitive blob (valid JSON, wrong types) used to
/// escape `PrefsSensitiveStore.read`'s `on FormatException` as a TypeError and
/// take down every screen watching the profile. The contract now is:
///
///   * missing, valid and corrupt are three DISTINCT outcomes;
///   * a corrupt blob is never silently turned into "no restrictions" -- the
///     profile reads as health-unknown and the screening gate stays closed;
///   * the original bytes are kept (quarantined), never overwritten by a read.

String _key(String uid) => 'profile.sensitive.$uid';
String _quarantine(String uid) => 'profile.sensitive.corrupt.$uid';

/// SharedPreferences reports a failed write by RETURNING false, not by
/// throwing. This wraps a real instance and makes chosen writes fail that way.
class _FailingPrefs implements SharedPreferences {
  _FailingPrefs(this._real, {this.failSet = false, this.failRemove = false});
  final SharedPreferences _real;
  final bool failSet;
  final bool failRemove;
  var setCalls = 0;

  @override
  String? getString(String key) => _real.getString(key);
  @override
  Future<bool> setString(String key, String value) async {
    setCalls++;
    return failSet ? false : _real.setString(key, value);
  }

  @override
  Future<bool> remove(String key) async =>
      failRemove ? false : _real.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _CountingRepo extends MockProfileRepository {
  _CountingRepo() : super(latency: Duration.zero);
  var saves = 0;
  @override
  Future<void> save(UserProfile profile) async {
    saves++;
    return super.save(profile);
  }
}

Future<PrefsSensitiveStore> _storeWith(Map<String, Object> seed) async {
  SharedPreferences.setMockInitialValues(seed);
  return PrefsSensitiveStore(await SharedPreferences.getInstance());
}

void main() {
  group('PrefsSensitiveStore.readChecked', () {
    test('nothing stored is MISSING, not corrupt', () async {
      final s = await _storeWith({});
      expect(await s.readChecked('u'), isA<SensitiveMissing>());
    });

    test('an empty string is MISSING', () async {
      final s = await _storeWith({_key('u'): ''});
      expect(await s.readChecked('u'), isA<SensitiveMissing>());
    });

    test('a well-formed blob is VALID and round-trips', () async {
      final s = await _storeWith({});
      final value = SensitiveProfile(
        health: HealthHistory(
          conditions: const ['asthma'],
          injuries: const [],
          screening: {ParQQuestion.values.first: true},
        ),
        smoking: SmokingHabit.values.first,
      );
      await s.write('u', value);
      final r = await s.readChecked('u');
      expect(r, isA<SensitiveValid>());
      final got = (r as SensitiveValid).profile;
      expect(got.health.conditions, ['asthma']);
      expect(got.health.screening[ParQQuestion.values.first], isTrue);
      expect(got.smoking, SmokingHabit.values.first);
    });

    test('an older blob with missing keys is VALID (schema evolution)', () async {
      final s = await _storeWith({_key('u'): jsonEncode({'smoking': null})});
      final r = await s.readChecked('u');
      expect(r, isA<SensitiveValid>());
      expect((r as SensitiveValid).profile.health.isEmpty, isTrue);
    });

    test('an unknown enum value is tolerated, not corrupt (newer/older build)',
        () async {
      final s = await _storeWith(
          {_key('u'): jsonEncode({'smoking': 'a_value_from_the_future'})});
      expect(await s.readChecked('u'), isA<SensitiveValid>());
    });

    for (final (String name, Object blob) in <(String, Object)>[
      ('truncated JSON', '{"health": {"conditions": ["asth'),
      ('top level is a list', '[]'),
      ('health is a list (the CR-07 shape)', '{"health": []}'),
      ('health is a string', '{"health": "none"}'),
      ('conditions is a string', '{"health": {"conditions": "asthma"}}'),
      ('conditions holds a number', '{"health": {"conditions": [1, 2]}}'),
      ('injuries is a map', '{"health": {"injuries": {"a": 1}}}'),
      ('injuries holds a string', '{"health": {"injuries": ["knee"]}}'),
      ('screening is a list', '{"health": {"screening": []}}'),
      ('otherConcerns is a number', '{"health": {"otherConcerns": 5}}'),
      ('bloodPressure is a number', '{"health": {"bloodPressure": 5}}'),
      ('smoking is a number', '{"smoking": 3}'),
    ]) {
      test('CORRUPT: $name', () async {
        final s = await _storeWith({_key('u'): blob as String});
        final r = await s.readChecked('u');
        expect(r, isA<SensitiveCorrupt>(), reason: name);
        expect((r as SensitiveCorrupt).raw, blob);
        expect(r.reason, isNotEmpty);
      });
    }

    test('reading a corrupt blob does NOT overwrite it, and quarantines a copy',
        () async {
      const blob = '{"health": []}';
      final s = await _storeWith({_key('u'): blob});
      await s.readChecked('u');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key('u')), blob,
          reason: 'a read must never destroy the only copy');
      expect(prefs.getString(_quarantine('u')), blob);
    });

    test('the FIRST quarantined copy is kept, not replaced by a later one',
        () async {
      final s = await _storeWith({_key('u'): '{"health": []}'});
      await s.readChecked('u');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key('u'), '{"health": "later garbage"}');
      await s.readChecked('u');
      expect(prefs.getString(_quarantine('u')), '{"health": []}');
    });

    test('legacy read() on a corrupt blob does not throw and reads as empty',
        () async {
      final s = await _storeWith({_key('u'): '{"health": []}'});
      expect((await s.read('u')).isEmpty, isTrue);
    });

    test('two uids on one device stay independent', () async {
      final s = await _storeWith({
        _key('a'): '{"health": []}',
        _key('b'): jsonEncode({'smoking': SmokingHabit.values.first.name}),
      });
      expect(await s.readChecked('a'), isA<SensitiveCorrupt>());
      final b = await s.readChecked('b');
      expect(b, isA<SensitiveValid>());
      expect((b as SensitiveValid).profile.smoking, SmokingHabit.values.first);
    });
  });

  group('DeviceHealthProfileRepository over a corrupt local blob', () {
    late MockProfileRepository inner;

    Future<DeviceHealthProfileRepository> repo(
        PrefsSensitiveStore store, UserProfile server) async {
      inner = MockProfileRepository(latency: Duration.zero);
      await inner.save(server);
      return DeviceHealthProfileRepository(inner, store);
    }

    test('load does not throw; health reads as unknown and screening is unanswered',
        () async {
      final store = await _storeWith({_key('u'): '{"health": []}'});
      final r = await repo(store, UserProfile.empty('u'));
      final p = await r.load('u');
      expect(p, isNotNull);
      expect(p!.health.screening, isEmpty,
          reason: 'unanswered screening blocks -- the fail-closed direction');
      expect(r.isSensitiveCorrupt('u'), isTrue);
    });

    test('a corrupt blob is never replaced just by loading the profile', () async {
      const blob = '{"health": []}';
      final store = await _storeWith({_key('u'): blob});
      final r = await repo(store, UserProfile.empty('u'));
      await r.load('u');
      await r.load('u');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key('u')), blob);
    });

    test('an explicit save by the user replaces the live blob; the original stays quarantined',
        () async {
      const blob = '{"health": []}';
      final store = await _storeWith({_key('u'): blob});
      final r = await repo(store, UserProfile.empty('u'));
      final loaded = (await r.load('u'))!;
      await r.save(loaded.copyWith(
          health: const HealthHistory(conditions: ['asthma'])));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_quarantine('u')), blob);
      expect(prefs.getString(_key('u')), isNot(blob));
      expect(r.isSensitiveCorrupt('u'), isFalse,
          reason: 'after the user re-enters it the live value is valid again');
      final again = await r.load('u');
      expect(again!.health.conditions, ['asthma']);
    });

    test('a save that never touched health leaves the corrupt blob and the flag',
        () async {
      const blob = '{"health": []}';
      final store = await _storeWith({_key('u'): blob});
      final r = await repo(store, UserProfile.empty('u'));
      final loaded = (await r.load('u'))!;
      await r.save(loaded);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_key('u')), blob,
          reason: 'an empty-but-valid blob must not replace unreadable data');
      expect(r.isSensitiveCorrupt('u'), isTrue);
    });

    test('a pre-split server copy still repairs a corrupt local blob', () async {
      final store = await _storeWith({_key('u'): '{"health": []}'});
      final server = UserProfile.empty('u').copyWith(
          health: const HealthHistory(conditions: ['asthma']));
      final r = await repo(store, server);
      final p = await r.load('u');
      expect(p!.health.conditions, ['asthma'],
          reason: 'the server still holds the answers, so they are not lost');
    });

    test('another uid on the same device is unaffected', () async {
      final store = await _storeWith({
        _key('u'): '{"health": []}',
        _key('w'): jsonEncode({
          'health': {
            'conditions': ['asthma']
          }
        }),
      });
      final r = await repo(store, UserProfile.empty('w'));
      final p = await r.load('w');
      expect(p!.health.conditions, ['asthma']);
      expect(r.isSensitiveCorrupt('w'), isFalse);
    });
  });

  group('a write the platform reports as failed (returns false)', () {
    test('write throws instead of reporting success', () async {
      SharedPreferences.setMockInitialValues({});
      final real = await SharedPreferences.getInstance();
      final store = PrefsSensitiveStore(_FailingPrefs(real, failSet: true));
      expect(
          () => store.write(
              'u', const SensitiveProfile(health: HealthHistory(conditions: ['asthma']))),
          throwsStateError);
    });

    test('clear throws instead of reporting success', () async {
      SharedPreferences.setMockInitialValues({_key('u'): '{}'});
      final real = await SharedPreferences.getInstance();
      final store = PrefsSensitiveStore(_FailingPrefs(real, failRemove: true));
      expect(() => store.clear('u'), throwsStateError);
    });

    test('the repository does not publish the stripped profile when the local write failed',
        () async {
      SharedPreferences.setMockInitialValues({});
      final real = await SharedPreferences.getInstance();
      final failing = _FailingPrefs(real, failSet: true);
      final inner = _CountingRepo();
      await inner.save(UserProfile.empty('u'));
      final before = inner.saves;
      final r = DeviceHealthProfileRepository(inner, PrefsSensitiveStore(failing));
      await expectLater(
          r.save(UserProfile.empty('u')
              .copyWith(health: const HealthHistory(conditions: ['asthma']))),
          throwsStateError);
      expect(inner.saves, before,
          reason: 'local first: the server copy must not be written when the '
              'device copy was not');
    });

    test('a failed quarantine still reads as corrupt and leaves the live blob',
        () async {
      const blob = '{"health": []}';
      SharedPreferences.setMockInitialValues({_key('u'): blob});
      final real = await SharedPreferences.getInstance();
      final store = PrefsSensitiveStore(_FailingPrefs(real, failSet: true));
      final r = await store.readChecked('u');
      expect(r, isA<SensitiveCorrupt>());
      expect(real.getString(_key('u')), blob);
    });
  });
}
