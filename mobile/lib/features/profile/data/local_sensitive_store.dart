import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sensitive_profile.dart';

/// Where the device-only half of a profile is kept.
///
/// An interface rather than a direct SharedPreferences call so the repository
/// that uses it is testable without a platform channel, and so that swapping
/// the backing store later — an encrypted file, a Keystore-wrapped blob — is a
/// binding change rather than a rewrite.
abstract class LocalSensitiveStore {
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

  @override
  Future<SensitiveProfile> read(String uid) async {
    final raw = _prefs.getString(_key(uid));
    if (raw == null || raw.isEmpty) return SensitiveProfile.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return SensitiveProfile.empty;
      return SensitiveProfile.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      // A corrupted blob reads as "nothing stored", which lets the merge fall
      // through to whatever the server still has. Rethrowing here would take
      // down every screen that watches the profile, over a value the user can
      // simply re-enter.
      return SensitiveProfile.empty;
    }
  }

  @override
  Future<void> write(String uid, SensitiveProfile value) async {
    await _prefs.setString(_key(uid), jsonEncode(value.toJson()));
  }

  @override
  Future<void> clear(String uid) async {
    await _prefs.remove(_key(uid));
  }
}

/// In-memory, for tests and for the mock repository path.
class InMemorySensitiveStore implements LocalSensitiveStore {
  final Map<String, SensitiveProfile> _byUid = {};

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
