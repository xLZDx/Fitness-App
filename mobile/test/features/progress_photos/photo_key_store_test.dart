import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/progress_photos/data/photo_encryption.dart';
import 'package:fitness_app/features/progress_photos/data/photo_key_store.dart';

/// A2-sec, after the Act gate.
///
/// This file exists because `SecurePhotoKeyStore` had NO tests when it was
/// written, and the two worst defects in it were both key-loss paths that no
/// other test could reach. Every case below is "does an existing user still
/// have their photos afterwards".
class _FakeStorage implements SecureKeyStorage {
  _FakeStorage({this.throwOnRead = false});

  final Map<String, String> values = {};
  bool throwOnRead;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) throw StateError('keystore unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

String _key32(int fill) =>
    base64Encode(Uint8List.fromList(List.filled(32, fill)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SharedPreferences> prefsWith(Map<String, Object> v) async {
    SharedPreferences.setMockInitialValues(v);
    return SharedPreferences.getInstance();
  }

  test('mints and persists a key on first run', () async {
    final storage = _FakeStorage();
    final store = SecurePhotoKeyStore(
      uid: 'u1',
      storage: storage,
      prefs: await prefsWith({}),
    );

    final key = await store.loadOrCreate();

    expect(key, hasLength(32));
    expect(storage.values['progress_photos.key.v2.u1'], isNotNull);
  });

  test('returns the same key on a second call, without rewriting', () async {
    final storage = _FakeStorage()
      ..values['progress_photos.key.v2.u1'] = _key32(7);
    final store = SecurePhotoKeyStore(
      uid: 'u1',
      storage: storage,
      prefs: await prefsWith({}),
    );

    final a = await store.loadOrCreate();
    final b = await store.loadOrCreate();

    expect(a, b);
    expect(storage.writes, 0);
  });

  test('two accounts never share a key', () async {
    final storage = _FakeStorage();
    final prefs = await prefsWith({});

    final a = await SecurePhotoKeyStore(
      uid: 'alice',
      storage: storage,
      prefs: prefs,
    ).loadOrCreate();
    final b = await SecurePhotoKeyStore(
      uid: 'bob',
      storage: storage,
      prefs: prefs,
    ).loadOrCreate();

    expect(a, isNot(b));
    expect(storage.values.keys, containsAll(<String>[
      'progress_photos.key.v2.alice',
      'progress_photos.key.v2.bob',
    ]));
  });

  group('the legacy prefs key', () {
    test('is adopted rather than replaced', () async {
      // Minting instead would make every already-captured photo permanently
      // unreadable.
      final legacy = _key32(3);
      final storage = _FakeStorage();
      final prefs = await prefsWith({'progress_photos.key.v1': legacy});

      final key = await SecurePhotoKeyStore(
        uid: 'u1',
        storage: storage,
        prefs: prefs,
      ).loadOrCreate();

      expect(keyToBase64(key), legacy);
      expect(storage.values['progress_photos.key.v2.u1'], legacy);
    });

    test('stops existing in plaintext once it is adopted', () async {
      final prefs = await prefsWith({'progress_photos.key.v1': _key32(3)});

      await SecurePhotoKeyStore(
        uid: 'u1',
        storage: _FakeStorage(),
        prefs: prefs,
      ).loadOrCreate();

      expect(prefs.getString('progress_photos.key.v1'), isNull);
    });

    test('a malformed legacy value is discarded, not adopted', () async {
      final prefs = await prefsWith({'progress_photos.key.v1': 'not-a-key'});

      final key = await SecurePhotoKeyStore(
        uid: 'u1',
        storage: _FakeStorage(),
        prefs: prefs,
      ).loadOrCreate();

      expect(key, hasLength(32));
      expect(prefs.getString('progress_photos.key.v1'), isNull);
    });
  });

  group('a secure store that will not open', () {
    test('never overwrites the key it failed to read', () async {
      // THE regression. The first version could not tell "read threw" from
      // "no key", so a transient Keystore error minted a new key over the
      // still-valid one and orphaned every photo on the device.
      final storage = _FakeStorage()
        ..values['progress_photos.key.v2.u1'] = _key32(9);
      storage.throwOnRead = true;

      await expectLater(
        SecurePhotoKeyStore(
          uid: 'u1',
          storage: storage,
          prefs: await prefsWith({}),
        ).loadOrCreate(),
        throwsA(isA<PhotoKeyUnavailable>()),
      );

      expect(storage.writes, 0, reason: 'nothing may be written after a '
          'failed read -- that is the data loss');
      expect(storage.values['progress_photos.key.v2.u1'], _key32(9));
    });

    test('does not consume the legacy key either', () async {
      // The migration must not fire on an unreadable store: it would delete
      // the plaintext original after writing into a store that is not
      // answering, leaving no copy anywhere.
      final prefs = await prefsWith({'progress_photos.key.v1': _key32(4)});

      await expectLater(
        SecurePhotoKeyStore(
          uid: 'u1',
          storage: _FakeStorage(throwOnRead: true),
          prefs: prefs,
        ).loadOrCreate(),
        throwsA(isA<PhotoKeyUnavailable>()),
      );

      expect(prefs.getString('progress_photos.key.v1'), _key32(4));
    });

    test('recovers on the next launch once the store answers again', () async {
      // The failure has to be transient, not a permanent demo-mode trap.
      final storage = _FakeStorage(throwOnRead: true)
        ..values['progress_photos.key.v2.u1'] = _key32(9);
      final prefs = await prefsWith({});

      await expectLater(
        SecurePhotoKeyStore(uid: 'u1', storage: storage, prefs: prefs)
            .loadOrCreate(),
        throwsA(isA<PhotoKeyUnavailable>()),
      );

      storage.throwOnRead = false;
      final key = await SecurePhotoKeyStore(
        uid: 'u1',
        storage: storage,
        prefs: prefs,
      ).loadOrCreate();

      expect(keyToBase64(key), _key32(9));
    });
  });

  test('a stored value that is not base64 mints rather than stranding',
      () async {
    // Corrupt, not unreadable: the store answered. Whatever wrote the blobs is
    // unrecoverable either way, so refusing forever would trap the user in
    // demo mode with no way out.
    final storage = _FakeStorage()
      ..values['progress_photos.key.v2.u1'] = '!!! not base64 !!!';

    final key = await SecurePhotoKeyStore(
      uid: 'u1',
      storage: storage,
      prefs: await prefsWith({}),
    ).loadOrCreate();

    expect(key, hasLength(32));
  });

  test('a stored key of the wrong length is replaced', () async {
    final storage = _FakeStorage()
      ..values['progress_photos.key.v2.u1'] =
          base64Encode(Uint8List.fromList(List.filled(16, 1)));

    final key = await SecurePhotoKeyStore(
      uid: 'u1',
      storage: storage,
      prefs: await prefsWith({}),
    ).loadOrCreate();

    expect(key, hasLength(32));
  });

  test('forget removes only that account\'s key', () async {
    final storage = _FakeStorage()
      ..values['progress_photos.key.v2.u1'] = _key32(1)
      ..values['progress_photos.key.v2.u2'] = _key32(2);

    await SecurePhotoKeyStore.forget('u1', storage: storage);

    expect(storage.values.containsKey('progress_photos.key.v2.u1'), isFalse);
    expect(storage.values['progress_photos.key.v2.u2'], _key32(2));
  });
}
