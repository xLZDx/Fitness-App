import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
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

  /// F009 — the account id must not reach anything that gets written down.
  ///
  /// `secureKeyFor(uid)` is the string this file passes around, so every log
  /// line and every exception message that names the slot named the user. Two
  /// sites, not the one the audit recorded: the corrupt-key `debugPrint` here,
  /// and `PhotoKeyUnavailable.toString()`, which
  /// `progress_photos_providers.dart` prints on the ORDINARY store-unavailable
  /// path.
  ///
  /// A debug console is not nothing: it is what a bug report attaches, what a
  /// tethered device shows anyone holding it, and what a crash reporter picks
  /// up when an exception's `toString()` is the message.
  group('F009: the uid stays out of the logs', () {
    const uid = 'auth0|9f3c-REAL-USER-ID';

    test('the exception message names the slot, not the person', () {
      final message = PhotoKeyUnavailable(
        SecurePhotoKeyStore.secureKeyFor(uid),
        StateError('keystore unavailable'),
      ).toString();

      expect(message, isNot(contains(uid)));
      expect(message, contains('progress_photos.key.v2.<uid>'),
          reason: 'which slot failed is the diagnostic worth keeping');
      expect(message, contains('keystore unavailable'),
          reason: 'the cause must survive redaction');
    });

    test('a corrupt stored key logs the slot, not the person', () async {
      final storage = _FakeStorage()
        ..values[SecurePhotoKeyStore.secureKeyFor(uid)] = 'not base64 at all';

      final lines = <String?>[];
      final outer = debugPrint;
      debugPrint = (m, {int? wrapWidth}) => lines.add(m);
      try {
        await SecurePhotoKeyStore(
          uid: uid,
          storage: storage,
          prefs: await prefsWith({}),
        ).loadOrCreate();
      } finally {
        debugPrint = outer;
      }

      expect(lines, isNotEmpty, reason: 'the corrupt-key path must still say so');
      final logged = lines.join(' ');
      expect(logged, isNot(contains(uid)));
      expect(logged, contains('progress_photos.key.v2.<uid>'));
    });

    test('the legacy install-wide key is not redacted, having no uid in it',
        () {
      // Redaction that ate an unrelated name would cost the diagnostic for
      // nothing: the pre-A2-sec key is one per install and names nobody.
      expect(redactedKeyName(SecurePhotoKeyStore.legacyPrefsKey),
          SecurePhotoKeyStore.legacyPrefsKey);
    });
  });
}
