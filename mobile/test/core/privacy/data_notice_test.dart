import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/config/body_scan_flags.dart';
import 'package:fitness_app/core/privacy/data_notice.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';

/// PRIV-23 (first-use data notice, D-79), client half owned by C03.
///
/// Covers the store (key shape, versioning, persistence, durable-write
/// failure), the providers (signed-in vs signed-out) and the sheet gate
/// [ensureDataNoticeAcknowledged] in EN and RU, with the food-AI paragraph only
/// when `foodAi` is on. Every assertion would fail if the guarded behaviour
/// were broken: a gate that returns true without a tap, a key that ignores the
/// version or the uid, or a failed write that re-closes the gate.

/// `SharedPreferences` whose writes report failure, like a full disk.
class _RefusingPrefs extends Fake implements SharedPreferences {
  final Map<String, Object> reads = {};
  int setBoolCalls = 0;

  @override
  bool? getBool(String key) => reads[key] as bool?;

  @override
  Future<bool> setBool(String key, bool value) async {
    setBoolCalls++;
    return false;
  }
}

Widget _host({
  required DataNoticeStore store,
  required Future<bool> Function(BuildContext, WidgetRef) onTap,
  BodyScanFlags flags = const BodyScanFlags(),
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      dataNoticeStoreProvider.overrideWith((ref) async => store),
      bodyScanFlagsProvider.overrideWithValue(flags),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Center(
            child: ElevatedButton(
              key: const Key('trigger'),
              onPressed: () => onTap(context, ref),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dataNoticeKey / version', () {
    test('the current version is 1 and the key embeds version and uid', () {
      expect(kDataNoticeVersion, 1);
      expect(dataNoticeKey('abc'), 'data_notice.v1.abc');
    });

    test('a version bump changes the key (a new notice asks again)', () {
      expect(dataNoticeKey('abc', version: 2), 'data_notice.v2.abc');
      expect(dataNoticeKey('abc', version: 2), isNot(dataNoticeKey('abc')));
    });

    test('different accounts never share a key', () {
      expect(dataNoticeKey('u1'), isNot(dataNoticeKey('u2')));
    });
  });

  group('PrefsDataNoticeStore', () {
    test('is NOT acknowledged on a fresh install', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsDataNoticeStore(uid: 'u1');
      expect(await store.isAcknowledged(), isFalse);
      expect(store.uid, 'u1');
      expect(store.key, 'data_notice.v1.u1');
    });

    test('acknowledge persists under the versioned per-uid key only', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PrefsDataNoticeStore(uid: 'u1');
      await store.acknowledge();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('data_notice.v1.u1'), isTrue);
      expect(prefs.getKeys(), {'data_notice.v1.u1'});
      // A brand new store instance (new launch) still sees it.
      expect(await PrefsDataNoticeStore(uid: 'u1').isAcknowledged(), isTrue);
    });

    test('an answer for one account does not acknowledge another', () async {
      SharedPreferences.setMockInitialValues({});
      await PrefsDataNoticeStore(uid: 'u1').acknowledge();
      expect(await PrefsDataNoticeStore(uid: 'u2').isAcknowledged(), isFalse);
    });

    test('an answer to an OLDER notice version does not count', () async {
      SharedPreferences.setMockInitialValues({
        // What a hypothetical v0 notice would have stored.
        'data_notice.v0.u1': true,
      });
      expect(await PrefsDataNoticeStore(uid: 'u1').isAcknowledged(), isFalse);
    });

    test('an explicit false in prefs is not an acknowledgement', () async {
      SharedPreferences.setMockInitialValues({'data_notice.v1.u1': false});
      expect(await PrefsDataNoticeStore(uid: 'u1').isAcknowledged(), isFalse);
    });

    test('an injected SharedPreferences instance is used', () async {
      SharedPreferences.setMockInitialValues({'data_notice.v1.u9': true});
      final prefs = await SharedPreferences.getInstance();
      expect(
          await PrefsDataNoticeStore(uid: 'u9', prefs: prefs).isAcknowledged(),
          isTrue);
    });

    test('a refused durable write throws StateError but the session stays '
        'acknowledged', () async {
      final prefs = _RefusingPrefs();
      final store = PrefsDataNoticeStore(uid: 'u1', prefs: prefs);
      expect(await store.isAcknowledged(), isFalse);
      await expectLater(store.acknowledge(), throwsStateError);
      expect(prefs.setBoolCalls, 1);
      // Cost of a failed write: one extra tap NEXT launch, never a re-closed
      // gate in the same session.
      expect(await store.isAcknowledged(), isTrue);
      // A fresh store over the same (failed) prefs has no answer.
      expect(
          await PrefsDataNoticeStore(uid: 'u1', prefs: prefs).isAcknowledged(),
          isFalse);
    });
  });

  group('InMemoryDataNoticeStore', () {
    test('starts unacknowledged with no uid, counts acknowledge calls',
        () async {
      final store = InMemoryDataNoticeStore();
      expect(store.uid, isNull);
      expect(await store.isAcknowledged(), isFalse);
      expect(store.acknowledgeCalls, 0);
      await store.acknowledge();
      expect(await store.isAcknowledged(), isTrue);
      expect(store.acknowledgeCalls, 1);
    });

    test('can start acknowledged', () async {
      expect(await InMemoryDataNoticeStore(acknowledged: true).isAcknowledged(),
          isTrue);
    });
  });

  group('providers', () {
    test('signed out -> in-memory store, not acknowledged', () async {
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(null)),
      ]);
      addTearDown(c.dispose);
      final store = await c.read(dataNoticeStoreProvider.future);
      expect(store, isA<InMemoryDataNoticeStore>());
      expect(await c.read(dataNoticeAcknowledgedProvider.future), isFalse);
    });

    test('signed in -> prefs store for THAT uid, reflecting stored answer',
        () async {
      SharedPreferences.setMockInitialValues({'data_notice.v1.u7': true});
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) =>
            Stream.value(const AuthUser(uid: 'u7', displayName: 'Seven'))),
      ]);
      addTearDown(c.dispose);
      final store = await c.read(dataNoticeStoreProvider.future);
      expect(store, isA<PrefsDataNoticeStore>());
      expect(store.uid, 'u7');
      expect(await c.read(dataNoticeAcknowledgedProvider.future), isTrue);
    });

    test('signed in as a different uid is NOT acknowledged', () async {
      SharedPreferences.setMockInitialValues({'data_notice.v1.u7': true});
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) =>
            Stream.value(const AuthUser(uid: 'u8', displayName: 'Eight'))),
      ]);
      addTearDown(c.dispose);
      expect(await c.read(dataNoticeAcknowledgedProvider.future), isFalse);
    });

    test('an empty uid is treated as no account (in-memory)', () async {
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) =>
            Stream.value(const AuthUser(uid: '', displayName: 'Nobody'))),
      ]);
      addTearDown(c.dispose);
      expect(await c.read(dataNoticeStoreProvider.future),
          isA<InMemoryDataNoticeStore>());
    });
  });

  group('ensureDataNoticeAcknowledged (sheet gate)', () {
    testWidgets('already acknowledged: returns true and shows NO sheet',
        (tester) async {
      final store = InMemoryDataNoticeStore(acknowledged: true);
      bool? result;
      await tester.pumpWidget(_host(
        store: store,
        onTap: (c, r) async =>
            result = await ensureDataNoticeAcknowledged(c, r),
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.text('Got it'), findsNothing);
      expect(store.acknowledgeCalls, 0);
    });

    testWidgets('not acknowledged: shows the sheet, tap records ONE '
        'acknowledgement and resolves true', (tester) async {
      final store = InMemoryDataNoticeStore();
      bool? result;
      await tester.pumpWidget(_host(
        store: store,
        onTap: (c, r) async =>
            result = await ensureDataNoticeAcknowledged(c, r),
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      // Sheet is up, nothing resolved or recorded yet.
      expect(find.text('How your body and food data is stored'),
          findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      expect(result, isNull);
      expect(store.acknowledgeCalls, 0);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(store.acknowledgeCalls, 1);
      expect(await store.isAcknowledged(), isTrue);
      expect(find.text('Got it'), findsNothing);
    });

    testWidgets('dismissing the sheet resolves false and records nothing '
        '(the write must be deferred, not sent)', (tester) async {
      final store = InMemoryDataNoticeStore();
      bool? result;
      await tester.pumpWidget(_host(
        store: store,
        onTap: (c, r) async =>
            result = await ensureDataNoticeAcknowledged(c, r),
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      expect(find.text('Got it'), findsOneWidget);

      // Tap the scrim above the sheet to dismiss.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Got it'), findsNothing);
      expect(result, isFalse);
      expect(store.acknowledgeCalls, 0);
      expect(await store.isAcknowledged(), isFalse);
    });

    testWidgets('a failing durable write still lets the user through',
        (tester) async {
      final prefs = _RefusingPrefs();
      final store = PrefsDataNoticeStore(uid: 'u1', prefs: prefs);
      bool? result;
      await tester.pumpWidget(_host(
        store: store,
        onTap: (c, r) async =>
            result = await ensureDataNoticeAcknowledged(c, r),
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(prefs.setBoolCalls, 1);
      expect(result, isTrue);
      expect(await store.isAcknowledged(), isTrue);
    });

    testWidgets('after acknowledging, the next call shows no sheet',
        (tester) async {
      final store = InMemoryDataNoticeStore();
      final results = <bool>[];
      await tester.pumpWidget(_host(
        store: store,
        onTap: (c, r) async {
          final ok = await ensureDataNoticeAcknowledged(c, r);
          results.add(ok);
          return ok;
        },
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      expect(results, [true, true]);
      expect(find.text('Got it'), findsNothing);
      expect(store.acknowledgeCalls, 1);
    });
  });

  group('sheet content', () {
    testWidgets('foodAi OFF: the Vertex AI paragraph is absent', (tester) async {
      await tester.pumpWidget(_host(
        store: InMemoryDataNoticeStore(),
        onTap: (c, r) => ensureDataNoticeAcknowledged(c, r),
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your weigh-ins, nutrition targets'),
          findsOneWidget);
      expect(find.textContaining('Vertex AI'), findsNothing);
    });

    testWidgets('foodAi ON: the Vertex AI paragraph is present',
        (tester) async {
      await tester.pumpWidget(_host(
        store: InMemoryDataNoticeStore(),
        flags: const BodyScanFlags(foodAi: true),
        onTap: (c, r) => ensureDataNoticeAcknowledged(c, r),
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your weigh-ins, nutrition targets'),
          findsOneWidget);
      expect(find.textContaining('Vertex AI'), findsOneWidget);
    });

    testWidgets('cloudPhotos / foodLookup alone do NOT add the AI paragraph',
        (tester) async {
      await tester.pumpWidget(_host(
        store: InMemoryDataNoticeStore(),
        flags: const BodyScanFlags(cloudPhotos: true, foodLookup: true),
        onTap: (c, r) => ensureDataNoticeAcknowledged(c, r),
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Vertex AI'), findsNothing);
    });

    testWidgets('the title is a semantics header', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(
        store: InMemoryDataNoticeStore(),
        onTap: (c, r) => ensureDataNoticeAcknowledged(c, r),
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      final node = tester.getSemantics(
          find.text('How your body and food data is stored'));
      // ignore: deprecated_member_use
      expect(node.hasFlag(SemanticsFlag.isHeader), isTrue);
      handle.dispose();
    });

    testWidgets('RU locale renders the Russian title, body and button',
        (tester) async {
      await tester.pumpWidget(_host(
        store: InMemoryDataNoticeStore(),
        locale: const Locale('ru'),
        flags: const BodyScanFlags(foodAi: true),
        onTap: (c, r) => ensureDataNoticeAcknowledged(c, r),
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      expect(find.text('Как хранятся данные о вашем теле и питании'),
          findsOneWidget);
      expect(find.textContaining('Ваши взвешивания'), findsOneWidget);
      expect(find.textContaining('Vertex AI'), findsOneWidget);
      expect(find.text('Понятно'), findsOneWidget);
    });

    testWidgets('large text (scale 2.0) in RU does not overflow and keeps the '
        'button reachable', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(
            size: Size(360, 640), textScaler: TextScaler.linear(2.0)),
        child: _host(
          store: InMemoryDataNoticeStore(),
          locale: const Locale('ru'),
          flags: const BodyScanFlags(foodAi: true),
          onTap: (c, r) => ensureDataNoticeAcknowledged(c, r),
        ),
      ));
      await tester.tap(find.byKey(const Key('trigger')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The body is scrollable, so the button can always be scrolled into view.
      await tester.ensureVisible(find.text('Понятно'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Понятно'), findsOneWidget);
    });
  });
}
