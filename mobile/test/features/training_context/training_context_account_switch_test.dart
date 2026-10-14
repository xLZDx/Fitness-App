import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/features/training_context/widgets/training_context_selector.dart';

const _a = AuthUser(uid: 'A', displayName: 'a');
const _b = AuthUser(uid: 'B', displayName: 'b');

/// Reads fine, but every write fails (throws or reports false).
class _FailingPrefs implements SharedPreferences {
  _FailingPrefs({this.throwOnWrite = true});
  final bool throwOnWrite;
  int writes = 0;

  @override
  String? getString(String key) => null;

  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    if (throwOnWrite) throw StateError('disk full');
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('account switch', () {
    late StreamController<AuthUser?> auth;
    late Completer<SharedPreferences> gateB;
    late ProviderContainer c;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        trainingContextKeyFor('A'): 'yoga',
        trainingContextKeyFor('B'): 'home',
      });
      prefs = await SharedPreferences.getInstance();
      auth = StreamController<AuthUser?>();
      gateB = Completer<SharedPreferences>();
      c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((_) => auth.stream),
        // B's stored value is held back so the loading window is observable.
        trainingContextPrefsProvider.overrideWith((ref) {
          final uid = ref.watch(authUserProvider).valueOrNull?.uid;
          return uid == 'B' ? gateB.future : Future.value(prefs);
        }),
      ]);
      addTearDown(() async {
        c.dispose();
        await auth.close();
      });
      c.listen(activeTrainingContextProvider, (_, __) {});
      auth.add(_a);
      await c.read(trainingContextProvider.future);
    });

    Future<void> switchToB() async {
      auth.add(_b);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    }

    test("A's answer is not exposed to B while B loads", () async {
      expect(c.read(activeTrainingContextProvider), TrainingContext.yoga);
      await switchToB();
      expect(c.read(trainingContextProvider).isLoading, isTrue);
      expect(c.read(activeTrainingContextProvider), isNull);
      gateB.complete(prefs);
      expect(await c.read(trainingContextProvider.future),
          const TrainingContextAnswer.chosen(TrainingContext.home));
      expect(c.read(activeTrainingContextProvider), TrainingContext.home);
    });

    test('a select while B loads is refused and writes nothing', () async {
      await switchToB();
      await c
          .read(trainingContextProvider.notifier)
          .choose(TrainingContext.gymMachines);
      expect(prefs.getString(trainingContextKeyFor('A')), 'yoga');
      expect(prefs.getString(trainingContextKeyFor('B')), 'home');
    });

    test("select after the switch writes under B's key only", () async {
      await switchToB();
      gateB.complete(prefs);
      await c.read(trainingContextProvider.future);
      await c
          .read(trainingContextProvider.notifier)
          .choose(TrainingContext.outdoorMinimal);
      expect(prefs.getString(trainingContextKeyFor('B')), 'outdoorMinimal');
      expect(prefs.getString(trainingContextKeyFor('A')), 'yoga');
    });
  });

  group('failed write', () {
    ProviderContainer make(SharedPreferences p) => ProviderContainer(overrides: [
          authUserProvider.overrideWith((_) => Stream.value(_a)),
          trainingContextPrefsProvider.overrideWithValue(Future.value(p)),
        ]);

    test('setString returning false keeps the state, does not throw',
        () async {
      final p = _FailingPrefs(throwOnWrite: false);
      final c = make(p);
      addTearDown(c.dispose);
      await c.read(trainingContextProvider.future);
      await c
          .read(trainingContextProvider.notifier)
          .choose(TrainingContext.home);
      expect(p.writes, 1);
      expect(c.read(trainingContextProvider).valueOrNull?.context,
          TrainingContext.home);
    });

    testWidgets('a throwing write does not escape the chip tap', (t) async {
      final p = _FailingPrefs();
      await t.pumpWidget(ProviderScope(
        overrides: [
          authUserProvider.overrideWith((_) => Stream.value(_a)),
          trainingContextPrefsProvider.overrideWithValue(Future.value(p)),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: TrainingContextSelector()),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('training-context.home')));
      await t.pumpAndSettle();
      expect(p.writes, 1);
      expect(t.takeException(), isNull);
      // State was updated first, as designed.
      expect(find.byKey(const Key('training-context.skip')), findsNothing);
    });
  });
}
