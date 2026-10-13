import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'sensitive_profile.dart';

/// Where the device-only half of a profile is kept.
///
/// An interface rather than a direct SharedPreferences call so the repository
/// that uses it is testable without a platform channel, and so that swapping
/// the backing store later — an encrypted file, a Keystore-wrapped blob — is a
/// binding change rather than a rewrite.
abstract class LocalSensitiveStore {
  /// The three-way answer (CR-07): missing, valid, or corrupt.
  Future<SensitiveRead> readChecked(String uid);

  /// The tolerant answer older callers use: anything but a valid blob reads as
  /// empty. Kept so those callers need not change, but a caller that decides
  /// something SAFETY-relevant from "empty" should use [readChecked] instead,
  /// because empty cannot tell "never answered" from "unreadable".
  Future<SensitiveProfile> read(String uid);

  Future<void> write(String uid, SensitiveProfile value);
  Future<void> clear(String uid);
}

/// SharedPreferences-backed, one JSON string per uid.
///
/// ## What this does and does not protect against
///
/// SharedPreferences is a plain XML file inside the app's private directory.
/// On a non-rooted device the sandbox keeps other apps out, which is the whole
/// threat this gate is about: the data is no longer on a server the operator
/// controls, so it cannot be reached by a server bug, a rules mistake, a
/// subpoena, or a future promotions feature that grows a little too curious.
///
/// It is NOT encryption at rest, and nothing in the UI may say it is. A user
/// with a rooted device, or an attacker with a device unlock, can read this
/// file. Encryption at rest would need a key, the key would need
/// Keystore/Keychain, and that is a dependency this gate does not add — see
/// the progress-photos comments for what happens when a product claims a key
/// that does not exist.
///
/// Android's Auto Backup does include this file in the user's own Google Drive
/// backup, encrypted since Android 9 with a key derived from their lock-screen
/// secret. That is the user's setting and their account; it is deliberately
/// not excluded, because excluding it would take away their only free
/// device-to-device transfer without giving anything back.
class PrefsSensitiveStore implements LocalSensitiveStore {
  PrefsSensitiveStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsSensitiveStore> open() async =>
      PrefsSensitiveStore(await SharedPreferences.getInstance());

  /// Keyed by uid, not a single slot: a shared device with two accounts must
  /// not show one person's injuries to the other.
  static String _key(String uid) => 'profile.sensitive.$uid';

  /// Where an unreadable blob is preserved. Separate from the live key so a
  /// later explicit save can replace the live value without destroying the
  /// evidence, and so the live key is never touched by a READ.
  static String _quarantineKey(String uid) => 'profile.sensitive.corrupt.$uid';

  @override
  Future<SensitiveRead> readChecked(String uid) async {
    final raw = _prefs.getString(_key(uid));
    if (raw == null || raw.isEmpty) return const SensitiveMissing();
    String? problem;
    SensitiveProfile? parsed;
    try {
      final decoded = jsonDecode(raw);
      problem = sensitiveJsonProblem(decoded);
      if (problem == null) {
        parsed = SensitiveProfile.fromJson(
            Map<String, dynamic>.from(decoded as Map));
      }
    } on FormatException catch (e) {
      problem = 'not valid JSON (${e.message})';
    } on TypeError catch (e) {
      // A shape the structural check did not anticipate; still corrupt, still
      // not "nothing stored".
      problem = 'unexpected shape ($e)';
    }
    if (parsed != null) return SensitiveValid(parsed);
    await _quarantine(uid, raw);
    return SensitiveCorrupt(raw: raw, reason: problem ?? 'unreadable');
  }

  @override
  Future<SensitiveProfile> read(String uid) async =>
      switch (await readChecked(uid)) {
        SensitiveValid(:final profile) => profile,
        _ => SensitiveProfile.empty,
      };

  /// Keeps the FIRST unreadable copy. A later, different corrupt value (for
  /// instance the result of a second bad write) must not push out the one that
  /// may still be recoverable.
  Future<void> _quarantine(String uid, String raw) async {
    final key = _quarantineKey(uid);
    if (_prefs.getString(key) != null) return;
    try {
      final saved = await _prefs.setString(key, raw);
      if (!saved) {
        debugPrint('sensitive store: could not quarantine an unreadable blob');
      }
    } catch (e) {
      // Failing to preserve a copy must not turn into failing to read; the
      // live blob is untouched either way. Logged, because without the copy a
      // later explicit save is the end of the only evidence.
      debugPrint('sensitive store: quarantine failed: $e');
    }
  }

  /// SharedPreferences reports a failed write by returning `false`, not by
  /// throwing. Ignoring it let [DeviceHealthProfileRepository.save] publish the
  /// stripped profile to the server while the health answers existed nowhere.
  @override
  Future<void> write(String uid, SensitiveProfile value) async {
    final saved =
        await _prefs.setString(_key(uid), jsonEncode(value.toJson()));
    if (!saved) {
      throw StateError('sensitive profile was not persisted on this device');
    }
  }

  @override
  Future<void> clear(String uid) async {
    final removed = await _prefs.remove(_key(uid));
    if (!removed) {
      throw StateError('sensitive profile could not be removed from this device');
    }
  }
}

/// In-memory, for tests and for the mock repository path.
class InMemorySensitiveStore implements LocalSensitiveStore {
  final Map<String, SensitiveProfile> _byUid = {};

  @override
  Future<SensitiveRead> readChecked(String uid) async {
    final v = _byUid[uid];
    return v == null ? const SensitiveMissing() : SensitiveValid(v);
  }

  @override
  Future<SensitiveProfile> read(String uid) async =>
      _byUid[uid] ?? SensitiveProfile.empty;

  @override
  Future<void> write(String uid, SensitiveProfile value) async {
    _byUid[uid] = value;
  }

  @override
  Future<void> clear(String uid) async {
    _byUid.remove(uid);
  }
}
