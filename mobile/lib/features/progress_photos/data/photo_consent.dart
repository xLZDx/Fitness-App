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
  Future<bool> isAccepted();

  /// Records the answer. Must leave [isAccepted] true for the rest of the
  /// session even if the durable write fails — see [PrefsPhotoConsentStore].
  Future<void> accept();
}

/// SharedPreferences-backed, one key per account.
class PrefsPhotoConsentStore implements PhotoConsentStore {
  PrefsPhotoConsentStore({required this.uid, SharedPreferences? prefs})
      : _injected = prefs;

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
    await (await _prefs).setBool(key, true);
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
