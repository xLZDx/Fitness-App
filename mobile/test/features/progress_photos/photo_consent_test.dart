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
  String? get uid => null;

  @override
  Future<bool> isAccepted() async => throw StateError('prefs unavailable');

  @override
  Future<void> accept() async {}
}

/// An already-accepted store whose [isAccepted] does not resolve until the
/// test says so. Stands in for the real async gap `resolved.isAccepted()`
/// opens in `_ensurePhotoConsent` — in a real `PrefsPhotoConsentStore` that
/// gap is a disk read; here it is a [Completer] a test can hold open exactly
/// long enough to fire an account change into it.
class _SlowAcceptedStore implements PhotoConsentStore {
  _SlowAcceptedStore(this.uid);

  @override
  final String uid;

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<bool> isAccepted() async {
    await _gate.future;
    return true;
  }

  @override
  Future<void> accept() async {}
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// [consent] null means "do not override the store provider" — the only way to
/// exercise the real uid-scoped one, which is what the account-change test
/// needs. [auth] likewise: supply a stream to drive sign-in state from a test.
Future<void> _host(
  WidgetTester tester, {
  required _RecordingRepo repo,
  PhotoConsentStore? consent,
  _SpySession? session,
  Stream<AuthUser?>? auth,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      progressPhotoCameraProvider.overrideWithValue(session ?? _SpySession()),
      progressPhotosRepositoryProvider.overrideWithValue(repo),
      if (consent != null)
        photoConsentStoreProvider.overrideWith((ref) async => consent),
      if (auth != null) authUserProvider.overrideWith((ref) => auth),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: kTestLocale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Consumer(
        builder: (context, ref, _) {
          // Only when the test drives auth, and it is not decoration: a
          // broadcast stream drops whatever is added before someone listens,
          // and the only reader of `authUserProvider` in this flow is
          // `_ensurePhotoConsent`, which does not run until the button is
          // tapped. Without this watch the sign-in event goes into an empty
          // room and the flow starts against a still-loading account.
          if (auth != null) ref.watch(authUserProvider);
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => runPhotoCaptureFlow(context, ref),
                child: const Text('start'),
              ),
            ),
          );
        },
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

    test('a write that returns false is a failure, not a success', () async {
      // The failure `SharedPreferences` actually has, as opposed to the one
      // above. `setBool` reports refusal by RETURNING false; it does not
      // throw. The first version awaited the future purely for sequencing and
      // discarded the answer, so this case took the success path: nothing
      // raised, nothing logged, and the user asked again next launch with no
      // record of why.
      final store = PrefsPhotoConsentStore(uid: 'alice', prefs: _SullenPrefs());

      await expectLater(store.accept(), throwsA(isA<StateError>()));
      expect(await store.isAccepted(), isTrue,
          reason: 'same direction as the throwing case — this session goes on');
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

    testWidgets('an account that merely finishes loading is not an account '
        'change', (tester) async {
      // The false-abort this guard can produce if it compares the wrong two
      // things, found before it shipped rather than after. Reading auth
      // synchronously at the top of the flow returns null while the provider
      // is still loading — a cold start, where the first thing the user does
      // is open Photos — and the store below it then resolves a moment later
      // with a real uid. Comparing that null against `alice` after the sheet
      // reads an ordinary first capture as an account change and throws away
      // an answer nobody changed: the user taps "I agree" and nothing happens.
      //
      // Comparing against `store.uid` instead cannot see this, because the
      // store does not exist until auth has resolved.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);
      final repo = _RecordingRepo();
      final session = _SpySession();

      await _host(tester, repo: repo, session: session, auth: auth.stream);
      // No event yet, and no settle: auth is genuinely still loading when the
      // flow starts, which is the whole scenario.
      await tester.tap(find.text('start'));
      await tester.pump();

      auth.add(AuthUser(uid: 'alice', displayName: 'alice'));
      await _settle(tester);
      expect(find.byKey(const Key('photos.consent')), findsOneWidget);

      await tester.tap(find.byKey(const Key('photos.consent.accept')));
      await _settle(tester);

      expect(prefs.getBool('progress_photos.consent.v1.alice'), isTrue,
          reason: 'nothing changed accounts; the answer belongs to Alice');
      expect(session.starts, 1,
          reason: 'and the camera she asked for opens');
    });

    testWidgets('an account change while the sheet is open discards the '
        'answer instead of filing it against the wrong person',
        (tester) async {
      // The store is resolved before the sheet opens, so without the second
      // uid read the sequence below ends with Bob's tap writing Alice's key —
      // Alice carrying an answer to a question she was never shown, which is
      // the single sentence this whole gate exists to make impossible. The
      // flow then walked on into the camera holding a controller resolved for
      // Alice while Bob was signed in.
      //
      // No consent-store override here, unlike every other widget test in this
      // file: the real uid-scoped provider is the thing under test.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);
      final repo = _RecordingRepo();
      final session = _SpySession();

      await _host(
        tester,
        repo: repo,
        session: session,
        auth: auth.stream,
      );
      auth.add(AuthUser(uid: 'alice', displayName: 'alice'));
      await _settle(tester);

      await tester.tap(find.text('start'));
      await _settle(tester);
      expect(find.byKey(const Key('photos.consent')), findsOneWidget,
          reason: 'Alice has not agreed, so she is asked');

      // The background sign-out: a modal cannot be signed out of from inside,
      // so this is a token revocation or a session ending elsewhere.
      auth.add(AuthUser(uid: 'bob', displayName: 'bob'));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('photos.consent.accept')));
      await _settle(tester);

      expect(prefs.getBool('progress_photos.consent.v1.alice'), isNull,
          reason: 'Bob tapped agree; Alice must not end up holding the answer');
      expect(prefs.getBool('progress_photos.consent.v1.bob'), isNull,
          reason: 'nor Bob, whose store was never the one this flow resolved');
      expect(session.starts, 0,
          reason: 'and the camera stays shut rather than opening against a '
              'repository resolved for the account that just left');
      expect(repo.saved, isEmpty);
    });

    testWidgets('an account change WHILE an already-accepted store is being '
        'read discards that answer too', (tester) async {
      // The gap the sheet-open test above does not cover, found by Codex on
      // its second pass. `_ensurePhotoConsent` resolves the store and then
      // awaits `isAccepted()` — TWO awaits — before it ever checks whether the
      // account is still the one it started with. If Alice already agreed on
      // a previous visit and the account changes to Bob during either await,
      // the fast `if (already) return true` path used to return true on
      // Alice's stored answer with no check at all, opening the camera for
      // Bob against the controller that had already been captured for Alice.
      //
      // `_SlowAcceptedStore` holds `isAccepted()` open with a `Completer` so
      // this test can fire the account change from inside that exact window,
      // which a real disk read cannot be made to pause for on demand.
      final repo = _RecordingRepo();
      final session = _SpySession();
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);
      final slowStore = _SlowAcceptedStore('alice');

      await tester.pumpWidget(ProviderScope(
        overrides: [
          progressPhotoCameraProvider.overrideWithValue(session),
          progressPhotosRepositoryProvider.overrideWithValue(repo),
          authUserProvider.overrideWith((ref) => auth.stream),
          photoConsentStoreProvider.overrideWith((ref) async {
            final uid = (await ref.watch(authUserProvider.future))?.uid;
            return uid == 'alice' ? slowStore : InMemoryPhotoConsentStore();
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          locale: kTestLocale,
          localizationsDelegates: kTestLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              ref.watch(authUserProvider);
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => runPhotoCaptureFlow(context, ref),
                    child: const Text('start'),
                  ),
                ),
              );
            },
          ),
        ),
      ));
      auth.add(AuthUser(uid: 'alice', displayName: 'alice'));
      await _settle(tester);

      await tester.tap(find.text('start'));
      // Pumps, not `_settle`: settling would run the event loop past the
      // still-open `_gate` and the whole race would be over before the
      // account change below has a chance to land inside it.
      await tester.pump();
      await tester.pump();

      auth.add(AuthUser(uid: 'bob', displayName: 'bob'));
      await tester.pump();

      slowStore.release();
      await _settle(tester);

      expect(find.byKey(const Key('photos.shutter')), findsNothing,
          reason: 'the camera must not open for Bob on an answer Alice gave');
      expect(session.starts, 0);
      expect(repo.saved, isEmpty);
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
      // Counted, not just located. Listing the FILE was the first version and
      // it left the hole it was written to close: a second, ungated
      // `PhotoCaptureSheet.show` added anywhere in `progress_photos_page.dart`
      // — the one file most likely to grow one — produces the same
      // one-element list and the same green tick. The count is what makes the
      // second call visible.
      final callSites = <String, int>{};
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final n = 'PhotoCaptureSheet.show('
            .allMatches(code(f.readAsStringSync()))
            .length;
        if (n == 0) continue;
        callSites[f.path.replaceAll(r'\', '/')] = n;
      }
      expect(callSites, {
        'lib/features/progress_photos/progress_photos_page.dart': 1,
      });
    });

    test('Android backup is told to leave the photos alone', () {
      // The sheet says "there is no copy on a server" and "there is no backup
      // ... nobody can restore them for you". Nothing in Dart can make either
      // sentence true: Android Auto Backup is on by default and sweeps the
      // whole app data directory, so before these rules existed the encrypted
      // envelopes went to the user's Google Drive and the app said otherwise
      // on the way. The promise is kept by the platform config or not at all.
      //
      // Structural, and that is a real limit rather than a preference — only a
      // device can prove a backup did not happen. What this catches is the
      // realistic regression: one of these three files edited or replaced
      // without the other two, which leaves the copy lying again with every
      // Dart test still green. The merged manifest was checked by hand once,
      // at the commit that added them.
      const dir = 'android/app/src/main';
      final manifest = File('$dir/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'),
          reason: 'Android 11 and below read this one');
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
        reason: 'Android 12+ read this one, and ignore the other',
      );

      const excluded = 'domain="root" path="app_flutter/progress_photos"';
      final pre12 = File('$dir/res/xml/backup_rules.xml').readAsStringSync();
      expect(pre12, contains('<exclude $excluded'));

      final post12 =
          File('$dir/res/xml/data_extraction_rules.xml').readAsStringSync();
      // Both sections, because cloud backup and phone-to-phone transfer are
      // separate routes off the device and excluding one leaves the other.
      expect(post12, contains('<cloud-backup>'));
      expect(post12, contains('<device-transfer>'));
      expect('<exclude $excluded'.allMatches(post12).length, 2,
          reason: 'one exclusion per section, not one shared by both');
    });

    test('neither res/xml file has a double-hyphen inside its comment',
        () {
      // Found live, not designed up front: shipped once with `--` used as a
      // prose dash inside both files' header comments (the ASCII-dash
      // convention `.ps1`/`.bat` files use, applied here by habit) and the
      // Android build failed at `:app:mergeReleaseResources` --
      // `javax.xml.stream.XMLStreamException: The string "--" is not
      // permitted within comments`. Every other check in this file reads
      // Dart's own string content and would stay green; only a real Gradle
      // build surfaces this, which is exactly why it needs a permanent,
      // cheap, non-Gradle guard instead of relying on remembering the rule.
      const dir = 'android/app/src/main/res/xml';
      for (final name in ['backup_rules.xml', 'data_extraction_rules.xml']) {
        final text = File('$dir/$name').readAsStringSync();
        final start = text.indexOf('<!--') + '<!--'.length;
        final end = text.indexOf('-->');
        expect(start, greaterThan('<!--'.length - 1), reason: name);
        expect(end, greaterThan(start), reason: name);
        expect(text.substring(start, end), isNot(contains('--')),
            reason: '$name: XML forbids "--" anywhere inside a comment, not '
                'just at the delimiters');
      }
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

/// Preferences whose write fails the way the real one does: quietly, by
/// returning false. `_DeadPrefs` models the loud failure; this models the one
/// that used to slip through.
class _SullenPrefs implements SharedPreferences {
  @override
  bool? getBool(String key) => false;

  @override
  Future<bool> setBool(String key, bool value) async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
