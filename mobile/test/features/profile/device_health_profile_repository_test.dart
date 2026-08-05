import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/profile/data/device_health_profile_repository.dart';
import 'package:fitness_app/features/profile/data/local_sensitive_store.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/data/sensitive_profile.dart';

/// H1a — the health block must not reach the server.
///
/// Nothing on the server ever read it: no Cloud Function touches
/// `users/{uid}/profile/main`. Holding it there bought full GDPR Article 9
/// exposure and a Play "Health info" declaration in exchange for nothing.
///
/// These tests assert on what the INNER repository was handed, because that is
/// the thing that would have been written to Firestore. Asserting on what the
/// decorator returns would pass just as well with no split at all.

/// Records what it was asked to persist, so a test can inspect it.
class _RecordingRepository implements ProfileRepository {
  UserProfile? saved;
  UserProfile? stored;
  int deletes = 0;
  int saveCount = 0;
  bool failSaves = false;

  @override
  Stream<UserProfile?> watch(String uid) => Stream.value(stored);

  @override
  UserProfile? cached(String uid) => stored;

  @override
  Future<UserProfile?> load(String uid) async => stored;

  @override
  Future<void> save(UserProfile profile) async {
    if (failSaves) throw StateError('offline');
    saveCount++;
    saved = profile;
    stored = profile;
  }

  @override
  Future<void> delete(String uid) async {
    deletes++;
    stored = null;
  }
}

UserProfile _withHealth(String uid) => UserProfile(
      uid: uid,
      personal: const PersonalInfo(age: 34, heightCm: 181),
      health: const HealthHistory(
        conditions: ['hypertension'],
        medications: ['ramipril'],
        recentSurgeries: ['acl reconstruction 2024'],
        injuries: [Injury(bodyPart: 'knee', type: 'ligament')],
        bloodPressure: BloodPressure.high,
        otherConcerns: 'dizzy on standing',
      ),
      lifestyle: const Lifestyle(
        smoking: SmokingHabit.regular,
        alcohol: AlcoholHabit.moderate,
        sleepHoursPerNight: 7,
      ),
    );

void main() {
  group('DeviceHealthProfileRepository', () {
    test('the inner repository is never handed the health block', () async {
      final inner = _RecordingRepository();
      final repo = DeviceHealthProfileRepository(inner, InMemorySensitiveStore());

      await repo.save(_withHealth('u1'));

      final sent = inner.saved!;
      expect(sent.health.conditions, isEmpty);
      expect(sent.health.medications, isEmpty);
      expect(sent.health.recentSurgeries, isEmpty);
      expect(sent.health.injuries, isEmpty);
      expect(sent.health.bloodPressure, isNull);
      expect(sent.health.otherConcerns, isNull);
      // And the same through the serializer, which is what actually reaches
      // Firestore -- a model field cleared but still serialised would not be.
      final json = sent.toJson()['health'] as Map<String, dynamic>;
      expect(json['medications'], isEmpty);
      expect(json['bloodPressure'], isNull);
      expect(json['otherConcerns'], isNull);
    });

    /// `Lifestyle.copyWith` cannot clear a nullable field: `smoking ??
    /// this.smoking` keeps the value it was asked to remove. `stripSensitive`
    /// rebuilds the object instead. Without this test the copyWith version
    /// looks correct and ships smoking habits to the server anyway.
    test('smoking and alcohol are cleared, not merely asked to be', () async {
      final inner = _RecordingRepository();
      final repo = DeviceHealthProfileRepository(inner, InMemorySensitiveStore());

      await repo.save(_withHealth('u1'));

      expect(inner.saved!.lifestyle.smoking, isNull);
      expect(inner.saved!.lifestyle.alcohol, isNull);
      // Everything else in the same object survives.
      expect(inner.saved!.lifestyle.sleepHoursPerNight, 7);
      expect(inner.saved!.personal.age, 34);
    });

    test('what was stripped comes back on load', () async {
      final inner = _RecordingRepository();
      final repo = DeviceHealthProfileRepository(inner, InMemorySensitiveStore());

      await repo.save(_withHealth('u1'));
      final back = (await repo.load('u1'))!;

      expect(back.health.medications, ['ramipril']);
      expect(back.health.injuries.single.bodyPart, 'knee');
      expect(back.health.bloodPressure, BloodPressure.high);
      expect(back.lifestyle.smoking, SmokingHabit.regular);
      expect(back.lifestyle.alcohol, AlcoholHabit.moderate);
    });

    test('and on watch', () async {
      final inner = _RecordingRepository();
      final repo = DeviceHealthProfileRepository(inner, InMemorySensitiveStore());

      await repo.save(_withHealth('u1'));
      final back = (await repo.watch('u1').first)!;

      expect(back.health.medications, ['ramipril']);
      expect(back.lifestyle.smoking, SmokingHabit.regular);
    });

    /// Anyone who onboarded before this class existed has their health block
    /// in Firestore and an empty local store. Whatever the plumbing does with
    /// it, the answer handed back must still contain their injuries: a
    /// contraindication filter that silently starts reporting none is the one
    /// wrong answer it must never give.
    test('a profile still carrying health on the server keeps it', () async {
      final inner = _RecordingRepository()..stored = _withHealth('u1');
      final repo = DeviceHealthProfileRepository(inner, InMemorySensitiveStore());

      final back = (await repo.load('u1'))!;

      expect(back.health.injuries.single.bodyPart, 'knee');
      expect(back.lifestyle.smoking, SmokingHabit.regular);
    });

    /// H1b, the client half: reading a pre-split profile moves the block down
    /// and clears it upstream. Asserted on `inner.stored`, because "we stopped
    /// writing it" and "it is no longer there" are different claims and only
    /// the second one lets H1c say the data is gone.
    test('reading a pre-split profile clears it on the server', () async {
      final inner = _RecordingRepository()..stored = _withHealth('u1');
      final store = InMemorySensitiveStore();
      final repo = DeviceHealthProfileRepository(inner, store);

      final back = (await repo.load('u1'))!;

      // The user loses nothing.
      expect(back.health.medications, ['ramipril']);
      expect(back.lifestyle.smoking, SmokingHabit.regular);
      // The server keeps nothing.
      expect(inner.stored!.health.medications, isEmpty);
      expect(inner.stored!.health.injuries, isEmpty);
      expect(inner.stored!.lifestyle.smoking, isNull);
      // And the device has it.
      expect((await store.read('u1')).health.medications, ['ramipril']);
    });

    test('migration runs once, not on every stream emission', () async {
      final inner = _RecordingRepository()..stored = _withHealth('u1');
      final repo = DeviceHealthProfileRepository(inner, InMemorySensitiveStore());

      await repo.load('u1');
      final savesAfterFirst = inner.saveCount;
      await repo.load('u1');
      await repo.load('u1');

      expect(savesAfterFirst, 1);
      expect(inner.saveCount, 1);
    });

    /// A failed migration -- offline, or a rules rejection -- must not take
    /// down every screen watching the profile over a housekeeping write, and
    /// must not mark the account done.
    test('a failed migration leaves the profile readable and retryable',
        () async {
      final inner = _RecordingRepository()
        ..stored = _withHealth('u1')
        ..failSaves = true;
      final repo = DeviceHealthProfileRepository(inner, InMemorySensitiveStore());

      final back = (await repo.load('u1'))!;
      expect(back.health.medications, ['ramipril']);

      inner.failSaves = false;
      await repo.load('u1');
      expect(inner.stored!.health.medications, isEmpty);
    });

    test('the local copy wins when both exist', () async {
      final inner = _RecordingRepository()..stored = _withHealth('u1');
      final store = InMemorySensitiveStore();
      await store.write(
        'u1',
        const SensitiveProfile(
          health: HealthHistory(
            injuries: [Injury(bodyPart: 'shoulder', type: 'impingement')],
          ),
        ),
      );
      final repo = DeviceHealthProfileRepository(inner, store);

      final back = (await repo.load('u1'))!;

      expect(back.health.injuries.single.bodyPart, 'shoulder');
    });

    /// `cached` is synchronous and the store is not, so before the first async
    /// read the mirror is empty. It must fall through to the server profile
    /// rather than return one with the health block blanked.
    test('cached does not blank health before the first async read', () {
      final inner = _RecordingRepository()..stored = _withHealth('u1');
      final repo = DeviceHealthProfileRepository(inner, InMemorySensitiveStore());

      expect(repo.cached('u1')!.health.injuries, hasLength(1));
    });

    test('delete clears the device copy as well as the server one', () async {
      final inner = _RecordingRepository();
      final store = InMemorySensitiveStore();
      final repo = DeviceHealthProfileRepository(inner, store);

      await repo.save(_withHealth('u1'));
      await repo.delete('u1');

      expect(inner.deletes, 1);
      expect((await store.read('u1')).isEmpty, isTrue);
    });

    test('two accounts on one device do not see each other', () async {
      final inner = _RecordingRepository();
      final store = InMemorySensitiveStore();
      final repo = DeviceHealthProfileRepository(inner, store);

      await repo.save(_withHealth('u1'));
      inner.stored = UserProfile.empty('u2');

      expect((await store.read('u2')).isEmpty, isTrue);
      expect((await repo.load('u2'))!.health.injuries, isEmpty);
    });
  });

  group('SensitiveProfile', () {
    test('round-trips through JSON', () {
      final original = extractSensitive(_withHealth('u1'));
      final back = SensitiveProfile.fromJson(original.toJson());

      expect(back.health.medications, ['ramipril']);
      expect(back.health.injuries.single.type, 'ligament');
      expect(back.health.bloodPressure, BloodPressure.high);
      expect(back.smoking, SmokingHabit.regular);
      expect(back.alcohol, AlcoholHabit.moderate);
    });

    test('an unanswered profile reads as empty, not as stored-and-blank', () {
      expect(extractSensitive(UserProfile.empty('u1')).isEmpty, isTrue);
      expect(SensitiveProfile.fromJson(const {}).isEmpty, isTrue);
    });

    test('an unknown enum name degrades instead of throwing', () {
      final back = SensitiveProfile.fromJson(const {
        'smoking': 'chain_smoker_9000',
        'health': {'bloodPressure': 'stratospheric'},
      });
      expect(back.smoking, isNull);
      expect(back.health.bloodPressure, isNull);
    });
  });
}
