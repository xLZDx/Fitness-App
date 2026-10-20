// S03-01 DT-01-20 (RV-14) and DT-01-24 (F-18): the account-deletion wipe
// removes the departing account's `activity.mode.v1.<uid>` key and nothing of
// another account, and a mode write that is in flight when the account is
// wiped never resurrects the key.
import 'dart:async';
import 'dart:io';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/data/mode_store.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/mode_fakes.dart';

/// Real prefs, but `setString` of the mode key waits for [gate].
class _GatedPrefs implements SharedPreferences {
  _GatedPrefs(this.real, this.gate);
  final SharedPreferences real;
  Completer<void>? gate;

  @override
  Object? get(String key) => real.get(key);
  @override
  Future<bool> setString(String key, String value) async {
    final g = gate;
    gate = null;
    if (g != null) await g.future;
    return real.setString(key, value);
  }

  @override
  Future<bool> remove(String key) => real.remove(key);
  @override
  Set<String> getKeys() => real.getKeys();
  @override
  String? getString(String key) => real.getString(key);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late Directory docs;
  setUp(() => docs = Directory.systemTemp.createTempSync('s03_mode_wipe_'));
  tearDown(() {
    try {
      docs.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('DT-01-24 wipe(uid) removes the departing mode key and keeps the '
      'second account key', () async {
    SharedPreferences.setMockInitialValues({
      modeStorageKeyFor('gone'): '{"v":1,"mode":"body","chooser":"resolved"}',
      modeStorageKeyFor('stay'): '{"v":1,"mode":"train","chooser":"pending"}',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(modeStorageKeyFor('gone')), isNotNull,
        reason: 'positive control: the seeded key exists');
    final wipe = DeviceLocalDataWipe(
        prefs: prefs, documentsDir: docs, forgetPhotoKey: (_) async {});
    await wipe.wipe('gone');
    expect(prefs.getString(modeStorageKeyFor('gone')), isNull,
        reason: 'account deletion left the mode key behind');
    expect(prefs.getString(modeStorageKeyFor('stay')),
        '{"v":1,"mode":"train","chooser":"pending"}');
  });

  test('DT-01-20 a write in flight when the account is wiped never '
      'resurrects the key (also after a migration re-run)', () async {
    SharedPreferences.setMockInitialValues({});
    final real = await SharedPreferences.getInstance();
    final gated = _GatedPrefs(real, null);
    final store = PrefsModeStore(prefs: () async => gated);
    final env = ModeEnv(realStore: store, initialUid: 'u1');
    await env.load();
    // Start the guard feed (the notifier watches it) before the deletion.
    final gate = Completer<void>();
    gated.gate = gate;
    final pending = env.notifier.selectMode(AppMode.body);
    await pumpEventQueue();
    // Account deletion starts: guard first, then the device wipe.
    env.container.read(accountBeingDeletedUidProvider.notifier).state = 'u1';
    expect(store.isUidWiped('u1'), isTrue,
        reason: 'the guard feed marks the uid before the wipe');
    final wipe = DeviceLocalDataWipe(
        prefs: real, documentsDir: docs, forgetPhotoKey: (_) async {});
    await wipe.wipe('u1');
    // Re-run the migration path: refused.
    expect(await env.notifier.initIfAbsent(InitSource.migration),
        ModeSaveResult.saveFailed);
    gate.complete();
    final r = await pending;
    expect(r, ModeSaveResult.saveFailed);
    expect(real.getString(modeStorageKeyFor('u1')), isNull,
        reason: 'a late write resurrected state after deletion');
  });

  test('DT-01-20 the wiped uid is refused before the write starts', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsModeStore();
    store.markUidWiped('u1');
    expect(
        await store.write('u1', ModeState.initial()), ModeWriteResult.refusedWipedUid);
    final p = await SharedPreferences.getInstance();
    expect(p.getKeys(), isEmpty);
    expect(await store.read('u1'), isA<ModeReadMissing>());
  });
}
