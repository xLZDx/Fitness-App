// Test-only: a shared-preferences platform store whose n-th `getAll` waits for
// a gate, so the open of an AccountScopedConsentStore can be held at an exact
// point (S02 test epic 14a). Install it, then use `forgetPrefs()` so a later
// `getInstance` reads the platform store again (an independent open).
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const consentKeyA = 'flutter.activity.cloudStreamsConsent.A';
const consentKeyB = 'flutter.activity.cloudStreamsConsent.B';

class GatedPrefsStore extends InMemorySharedPreferencesStore {
  GatedPrefsStore.withData(super.data) : super.withData();

  /// 1-based call number of `getAll` -> gate.
  final Map<int, Completer<void>> gateOnCall = {};
  int calls = 0;

  /// Gates the NEXT `getAll` and returns its gate.
  Completer<void> gateNext() {
    final g = Completer<void>();
    gateOnCall[calls + 1] = g;
    return g;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    final n = ++calls;
    final g = gateOnCall[n];
    if (g != null) await g.future;
    return super.getAll();
  }
}

/// Installs a gated platform store and forgets the cached instance.
GatedPrefsStore installPrefs([Map<String, Object> data = const {}]) {
  final s = GatedPrefsStore.withData(Map<String, Object>.of(data));
  SharedPreferencesStorePlatform.instance = s;
  SharedPreferences.resetStatic();
  return s;
}

void forgetPrefs() => SharedPreferences.resetStatic();
