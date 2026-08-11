import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Erases everything about a user that lives on the DEVICE.
///
/// A1 exists because "delete my account" was a server-only operation: the
/// Cloud Function removed the Firestore side and the client did nothing but
/// sign out. Two consequences, both in `core/DATA_INVENTORY_2026-08-11.md`:
///
///   1. The health/injury blob (`profile.sensitive.{uid}`) stayed in
///      SharedPreferences after the account that owned it was gone.
///   2. Progress photos and their AES key are not uid-scoped at all
///      (`<docs>/progress_photos/`, `progress_photos.key.v1`), so the next
///      account signed in on the same device opened the previous account's
///      photos with the previous account's key.
///
/// (2) is why this class deletes the photo directory WHOLE rather than
/// walking the index and deleting the photos it lists. A2 is about to
/// restructure that directory into per-uid subdirectories; an index-driven
/// wipe would be silently wrong the day that lands, while `dir.delete(
/// recursive: true)` keeps meaning "no photos remain" under either layout.
///
/// Best-effort by design, and the caller must treat it that way: the account
/// IS deleted server-side by the time this runs. A failure here is a
/// leftover file on one phone, not a failed deletion, and reporting it as the
/// latter would tell the user something untrue.
abstract class LocalDataWipe {
  Future<void> wipe(String uid);
}

class DeviceLocalDataWipe implements LocalDataWipe {
  DeviceLocalDataWipe({SharedPreferences? prefs, Directory? documentsDir})
      : _injectedPrefs = prefs,
        _injectedDir = documentsDir;

  final SharedPreferences? _injectedPrefs;
  final Directory? _injectedDir;

  /// Keys that describe a PERSON. Everything under `moment.` is a counter
  /// about how this user has used the app, and `settings.tier_override` is a
  /// debug entitlement that must not outlive the account it was set for.
  ///
  /// The health blob is matched by its EXACT key, `profile.sensitive.{uid}`,
  /// not by the `profile.sensitive.` prefix. The prefix would also erase a
  /// different, still-existing account's blob on a shared phone — deleting
  /// someone else's health data as a side effect of deleting yours. Their own
  /// deletion is what removes theirs.
  static const _personalPrefixes = <String>['moment.'];
  static const _personalKeys = <String>[
    'progress_photos.key.v1',
    'settings.tier_override',
  ];

  /// Deliberately KEPT: `settings.language` and `settings.theme_mode`. They
  /// describe how this phone should look, not who was signed in, and wiping
  /// them would drop a Russian user back to an English login screen as a side
  /// effect of deleting an account. `settings.notifications_enabled` is kept
  /// for the same reason — the OS-level permission it mirrors is not revoked
  /// by an account deletion either, and a mismatch between the two is a worse
  /// state than a stale toggle.
  static const kept = <String>[
    'settings.language',
    'settings.theme_mode',
    'settings.notifications_enabled',
  ];

  @override
  Future<void> wipe(String uid) async {
    final prefs = _injectedPrefs ?? await SharedPreferences.getInstance();

    final personalKeys = {..._personalKeys, 'profile.sensitive.$uid'};

    // Guarded separately from the directory below, and deliberately so: a
    // platform-channel hiccup on one `remove` used to abort this method before
    // the photos were touched at all, which meant the LARGER leak was the one
    // that survived the smaller failure. Each half now runs regardless of the
    // other.
    try {
      for (final key in prefs.getKeys().toList()) {
        final personal =
            personalKeys.contains(key) || _personalPrefixes.any(key.startsWith);
        if (personal) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('local data wipe: could not clear preferences: $e');
    }

    try {
      final dir = _injectedDir ?? await getApplicationDocumentsDirectory();
      final photos = Directory('${dir.path}/progress_photos');
      if (await photos.exists()) {
        await photos.delete(recursive: true);
      }
    } catch (e) {
      // A locked or missing directory must not turn a completed server-side
      // deletion into an error the user sees as "your account was not
      // deleted". Logged, not thrown -- same contract as the sign-out step in
      // the caller.
      debugPrint('local data wipe: could not delete progress photos: $e');
    }
  }
}

/// Test double: records what it was asked to wipe and touches nothing.
class RecordingLocalDataWipe implements LocalDataWipe {
  final List<String> wiped = [];

  @override
  Future<void> wipe(String uid) async => wiped.add(uid);
}
