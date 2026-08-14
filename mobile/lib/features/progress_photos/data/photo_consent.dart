import 'package:shared_preferences/shared_preferences.dart';

/// Whether this account has agreed to the app taking progress photos.
///
/// ## Why consent, and not a "has seen the explainer" flag
///
/// R11f left the prototype's privacy screen unbuilt on purpose, and recorded
/// why (`core/DECISION_LOG.md`, 2026-08-12, "Решение 4"): the prototype's
/// version is a one-time explainer, the page already carries a permanent
/// privacy strip, and replacing a standing promise with a card the user sees
/// once would have been a weakening dressed up as a feature. The only shape
/// that adds something is consent — the camera does not open until the answer
/// is yes. That was the operator's decision on 2026-08-13.
///
/// So this gate does not replace the strip. The strip still says, on every
/// visit, what happens to the photos; this says the user was asked before the
/// first one existed.
///
/// ## Why it is scoped to the account, not the device
///
/// Consent is given by a person. Everything else this feature persists is
/// already uid-scoped for the same reason — the directory (`photo_directory.dart`)
/// and the AES key (`photo_key_store.dart`) — after a pre-A2-sec device-wide
/// store showed one account the previous account's photos. A device-wide
/// consent flag would rebuild exactly that shape in miniature: the second
/// person to sign in on a phone would find they had already agreed to
/// something nobody had shown them.
abstract class PhotoConsentStore {
  /// Whose answer this store holds, or null when there is no account.
  ///
  /// On the interface rather than read off `authUserProvider` at the call
  /// site, because this is the uid the write will actually use — comparing
  /// anything else compares the wrong thing. The caller needs it to notice an
  /// account change across the consent sheet, and reading auth directly there
  /// was the first version: it can return null while the provider is still
  /// loading, and the store below it resolves a moment later with a real uid,
  /// so a first capture on a cold start would have compared null against
  /// `alice` and thrown away an answer nobody changed.
  String? get uid;

  Future<bool> isAccepted();

  /// Records the answer. Must leave [isAccepted] true for the rest of the
  /// session even if the durable write fails — see [PrefsPhotoConsentStore].
  Future<void> accept();
}

/// SharedPreferences-backed, one key per account.
class PrefsPhotoConsentStore implements PhotoConsentStore {
  PrefsPhotoConsentStore({required this.uid, SharedPreferences? prefs})
      : _injected = prefs;

  @override
  final String uid;
  final SharedPreferences? _injected;

  /// Set by [accept] BEFORE the disk write, and never cleared.
  ///
  /// This is what decides the failure direction. A preferences write that
  /// throws now costs the user one extra tap on their next launch; without
  /// this flag it would instead re-close the gate on somebody who had just
  /// agreed, so the camera they asked for would refuse to open and the app
  /// would ask the same question again in the same breath.
  bool _acceptedInSession = false;

  /// Versioned like the photo key (`progress_photos.key.v2.<uid>`). If what is
  /// being agreed to ever changes materially, the next version asks again
  /// rather than inheriting an answer to a different question.
  String get key => 'progress_photos.consent.v1.$uid';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  @override
  Future<bool> isAccepted() async {
    if (_acceptedInSession) return true;
    return (await _prefs).getBool(key) ?? false;
  }

  @override
  Future<void> accept() async {
    _acceptedInSession = true;
    // `setBool` reports failure by RETURNING false, not by throwing, and the
    // first draft awaited it for sequencing and dropped the answer. That is
    // the one shape this file's whole failure policy is blind to: a write that
    // quietly did not happen looks exactly like a write that did, so the
    // caller's `catch` never runs, nothing is logged, and the user is asked
    // again on next launch with no trace of why.
    //
    // Raised as an error rather than returned, because every caller of
    // `accept` already has to handle the throwing case and none of them has
    // anywhere to put a boolean. `_acceptedInSession` is set first and stays
    // set, so this session still proceeds -- see the field's own note.
    final written = await (await _prefs).setBool(key, true);
    if (!written) {
      throw StateError('progress photos: preferences refused to store $key');
    }
  }
}

/// Keeps the answer in memory only.
///
/// Two live uses, not just tests. It is also what a signed-out session gets:
/// there is no account to record an answer against, and no photo store either
/// — the mock repository is bound and a capture would vanish on restart. The
/// camera is real in that state regardless, so the gate still has to run; the
/// answer simply lasts as long as the session, which is the same deal the demo
/// banner already describes for the photos themselves.
class InMemoryPhotoConsentStore implements PhotoConsentStore {
  InMemoryPhotoConsentStore({bool accepted = false}) : _accepted = accepted;

  bool _accepted;

  /// Nobody's: this is the signed-out store, and the whole point of it is that
  /// there is no account for the answer to belong to.
  @override
  String? get uid => null;

  /// How many times [accept] was called. Lets a test tell "recorded once" from
  /// "recorded on every capture".
  int acceptCalls = 0;

  @override
  Future<bool> isAccepted() async => _accepted;

  @override
  Future<void> accept() async {
    _accepted = true;
    acceptCalls++;
  }
}
