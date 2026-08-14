import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/progress_photos/data/photo_consent.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/progress_photos_page.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import '../../helpers/test_app.dart';

/// R11f-1 — the privacy gate, built as CONSENT.
///
/// The distinction is the whole point and it is what these tests pin. An
/// explainer that appears once and then gets out of the way would pass a test
/// that only checked "the sheet was shown"; what makes this consent is that
/// the camera does not open until the answer is yes, and that saying no leaves
/// nothing behind.
///
/// The failure this guards against is not cosmetic. `PhotoCaptureSheet` starts
/// a real camera session and asks the OS for the camera permission in its own
/// `initState`, so "gated" has to mean the sheet never opens — not that a
/// question appears over a camera that is already running.

class _SpySession extends CameraSession {
  int starts = 0;

  @override
  Future<void> start({bool requestPermission = false}) async {
    starts++;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<XFile?> captureStill() async => null;
}

class _RecordingRepo implements ProgressPhotosRepository {
  int shots = 0;
  final List<ProgressPhotoAngle> saved = [];

  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(const []);

  @override
  Future<Uint8List?> takeShot() async {
    shots++;
    return Uint8List.fromList(const [1, 2, 3]);
  }

  @override
  Future<ProgressPhoto> save(
    Uint8List bytes, {
    required ProgressPhotoAngle angle,
    double? weightKg,
    String? note,
  }) async {
    saved.add(angle);
    return ProgressPhoto(
      id: 'p_${saved.length}',
      takenAt: DateTime(2026, 8, 14),
      storagePath: 'test://x.bin',
      keyFingerprint: 'fp',
      angle: angle,
      weightKg: weightKg,
      note: note,
    );
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async =>
      Uint8List.fromList(const [1, 2, 3]);
}

/// A store whose read fails, standing in for preferences that cannot be
/// opened.
class _BrokenConsentStore implements PhotoConsentStore {
  @override
  Future<bool> isAccepted() async => throw StateError('prefs unavailable');

  @override
  Future<void> accept() async {}
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _host(
  WidgetTester tester, {
  required _RecordingRepo repo,
  required PhotoConsentStore consent,
  _SpySession? session,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      progressPhotoCameraProvider.overrideWithValue(session ?? _SpySession()),
      progressPhotosRepositoryProvider.overrideWithValue(repo),
      photoConsentStoreProvider.overrideWith((ref) async => consent),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => runPhotoCaptureFlow(context, ref),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    ),
  ));
}

void main() {
  group('the camera is gated on consent, not merely preceded by a notice', () {
    testWidgets('a first capture asks instead of opening the camera',
        (tester) async {
      final repo = _RecordingRepo();
      final session = _SpySession();
      await _host(
        tester,
        repo: repo,
        consent: InMemoryPhotoConsentStore(),
        session: session,
      );

      await tester.tap(find.text('start'));
      await _settle(tester);

      expect(find.byKey(const Key('photos.consent')), findsOneWidget);
      expect(find.byKey(const Key('photos.shutter')), findsNothing,
          reason: 'the capture sheet starts a real camera in initState, so a '
              'gate that let it open would be asking after the fact');
      expect(session.starts, 0);
      expect(repo.shots, 0);
    });

    testWidgets('saying no leaves the camera closed and writes nothing',
        (tester) async {
      final repo = _RecordingRepo();
      final session = _SpySession();
      final consent = InMemoryPhotoConsentStore();
      await _host(tester, repo: repo, consent: consent, session: session);

      await tester.tap(find.text('start'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('photos.consent.decline')));
      await _settle(tester);

      expect(find.byKey(const Key('photos.shutter')), findsNothing);
      expect(session.starts, 0);
      expect(repo.shots, 0);
      expect(repo.saved, isEmpty);
      expect(await consent.isAccepted(), isFalse,
          reason: 'declining must not be recorded as an answer of any kind');
      expect(consent.acceptCalls, 0);
    });

    testWidgets('dismissing the sheet counts as no', (tester) async {
      // A swipe-down or a tap outside pops null. Reading that as anything but
      // "no" would let a mistaken tap open the camera.
      final repo = _RecordingRepo();
      final session = _SpySession();
      await _host(
        tester,
        repo: repo,
        consent: InMemoryPhotoConsentStore(),
        session: session,
      );

      await tester.tap(find.text('start'));
      await _settle(tester);
      // Outside the sheet: the barrier.
      await tester.tapAt(const Offset(200, 40));
      await _settle(tester);

      expect(find.byKey(const Key('photos.consent')), findsNothing);
      expect(find.byKey(const Key('photos.shutter')), findsNothing);
      expect(session.starts, 0);
    });

    testWidgets('saying yes opens the camera without a second tap',
        (tester) async {
      // Consent is given in direct answer to "take a photo", so it continues
      // into the thing that was asked for. Dropping the user back on the
      // timeline would make agreeing cost an extra tap for no reason.
      final repo = _RecordingRepo();
      final consent = InMemoryPhotoConsentStore();
      await _host(tester, repo: repo, consent: consent);

      await tester.tap(find.text('start'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('photos.consent.accept')));
      await _settle(tester);

      expect(find.byKey(const Key('photos.shutter')), findsOneWidget);
      expect(await consent.isAccepted(), isTrue);
      expect(consent.acceptCalls, 1);
    });

    testWidgets('an account that already agreed is not asked again',
        (tester) async {
      final repo = _RecordingRepo();
      final consent = InMemoryPhotoConsentStore(accepted: true);
      await _host(tester, repo: repo, consent: consent);

      await tester.tap(find.text('start'));
      await _settle(tester);

      expect(find.byKey(const Key('photos.consent')), findsNothing);
      expect(find.byKey(const Key('photos.shutter')), findsOneWidget);
      expect(consent.acceptCalls, 0,
          reason: 're-recording an existing answer on every capture would make '
              'the flag say when the last photo was taken, not when consent '
              'was given');
    });

    testWidgets('consent is recorded once, not on every capture',
        (tester) async {
      final repo = _RecordingRepo();
      final consent = InMemoryPhotoConsentStore();
      await _host(tester, repo: repo, consent: consent);

      await tester.tap(find.text('start'));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('photos.consent.accept')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('photos.captureCancel')));
      await _settle(tester);

      await tester.tap(find.text('start'));
      await _settle(tester);

      expect(find.byKey(const Key('photos.consent')), findsNothing,
          reason: 'the answer has to survive within the session, or the gate '
              'is a nag rather than a consent');
      expect(find.byKey(const Key('photos.shutter')), findsOneWidget);
      expect(consent.acceptCalls, 1);
    });

    testWidgets('preferences that cannot be read ask again rather than '
        'opening the camera', (tester) async {
      // Fail-closed. A read that throws is indistinguishable from "never
      // asked", and only one of the two possible readings is safe.
      final repo = _RecordingRepo();
      final session = _SpySession();
      await _host(
        tester,
        repo: repo,
        consent: _BrokenConsentStore(),
        session: session,
      );

      await tester.tap(find.text('start'));
      await _settle(tester);

      expect(find.byKey(const Key('photos.consent')), findsOneWidget);
      expect(session.starts, 0);
    });
  });

  group('the answer belongs to an account, not to a phone', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('one account agreeing does not answer for another', () async {
      final prefs = await SharedPreferences.getInstance();
      final alice = PrefsPhotoConsentStore(uid: 'alice', prefs: prefs);
      final bob = PrefsPhotoConsentStore(uid: 'bob', prefs: prefs);

      await alice.accept();

      expect(await alice.isAccepted(), isTrue);
      expect(await bob.isAccepted(), isFalse,
          reason: 'the second person to sign in on a phone must not find they '
              'have already agreed to something nobody showed them');
      expect(alice.key, isNot(bob.key));
    });

    test('the answer survives a restart of the same account', () async {
      final prefs = await SharedPreferences.getInstance();
      await PrefsPhotoConsentStore(uid: 'alice', prefs: prefs).accept();

      // A fresh instance is what the next launch builds.
      expect(
        await PrefsPhotoConsentStore(uid: 'alice', prefs: prefs).isAccepted(),
        isTrue,
      );
    });

    test('a failed write still lets this session through', () async {
      // The direction matters: losing the write costs one extra tap next
      // launch, whereas treating it as a refusal would close the camera on
      // somebody who had just agreed to open it.
      final store = PrefsPhotoConsentStore(uid: 'alice', prefs: _DeadPrefs());

      await expectLater(store.accept(), throwsA(isA<StateError>()));
      expect(await store.isAccepted(), isTrue);
    });
  });

  group('the store follows the account, not the phone it runs on', () {
    // `progress_photos_providers.dart` claims in prose that a sign-out closes
    // the previous account's answer. Every widget test above overrides
    // `photoConsentStoreProvider` wholesale and so walks straight past the
    // provider that would have to do it — the claim was asserted and never
    // run. This group runs it.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    AuthUser user(String uid) => AuthUser(uid: uid, displayName: uid);

    test('signing out closes the gate; signing back in reopens only the '
        'account that agreed', () async {
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);
      final container = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => auth.stream),
      ]);
      addTearDown(container.dispose);

      // Subscribed BEFORE the first event. A broadcast stream drops what is
      // added while nobody is listening, and the listener here is the provider
      // itself — reading it first would mean the first sign-in went into an
      // empty room and the read below waited for it forever.
      addTearDown(container.listen(photoConsentStoreProvider, (_, __) {}).close);

      Future<PhotoConsentStore> current() async {
        // auth stream -> authUserProvider -> photoConsentStoreProvider is
        // three async hops; drain them all rather than guessing at one.
        await pumpEventQueue();
        return container.read(photoConsentStoreProvider.future);
      }

      auth.add(user('alice'));
      final alice = await current();
      expect(alice, isA<PrefsPhotoConsentStore>());
      expect((alice as PrefsPhotoConsentStore).key, contains('alice'));
      await alice.accept();
      expect(await alice.isAccepted(), isTrue);

      auth.add(null);
      final signedOut = await current();
      expect(signedOut, isA<InMemoryPhotoConsentStore>(),
          reason: 'signed out there is no account to have agreed, so the '
              'answer must not be a device-wide flag');
      expect(await signedOut.isAccepted(), isFalse,
          reason: 'this is the sign-out closing the gate — the claim the '
              'provider makes in prose');

      auth.add(user('bob'));
      final bob = await current();
      expect((bob as PrefsPhotoConsentStore).key, contains('bob'));
      expect(await bob.isAccepted(), isFalse);

      auth.add(user('alice'));
      final aliceAgain = await current();
      expect(await aliceAgain.isAccepted(), isTrue,
          reason: 'the gate closes on sign-out, it does not forget');
    });
  });

  group('the gate cannot be walked around', () {
    /// Source with `//` comments removed, so a comment naming the sheet does
    /// not read as a call site. Same helper the system-camera rule uses in
    /// `test/features/visual_equipment/live_preview_test.dart`.
    String code(String src) => src
        .split('\n')
        .map((l) {
          final i = l.indexOf('//');
          return i == -1 ? l : l.substring(0, i);
        })
        .join('\n');

    test('runPhotoCaptureFlow is the only place lib/ opens the capture sheet',
        () {
      // The gate lives in that one function. A second entry point would not
      // fail any behavioural test above — it would simply be ungated — so the
      // guarantee has to be structural.
      final callers = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (!code(f.readAsStringSync()).contains('PhotoCaptureSheet.show(')) {
          continue;
        }
        callers.add(f.path.replaceAll(r'\', '/'));
      }
      expect(callers, [
        'lib/features/progress_photos/progress_photos_page.dart',
      ]);
    });
  });
}

/// Preferences whose write throws. `SharedPreferences` cannot be subclassed
/// usefully here, so only the one method the store touches is implemented.
class _DeadPrefs implements SharedPreferences {
  @override
  bool? getBool(String key) => false;

  @override
  Future<bool> setBool(String key, bool value) async =>
      throw StateError('disk full');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
