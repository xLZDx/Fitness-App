// Shared test harness of the S03 EP-2 test files (step 3): chooser, questions,
// switcher, Record sheet. Test code only; no product path is changed.
//
// Contents: FakeModeStore (write spy with sequence numbers, throwing writes,
// delayed reads and writes), FakeAuthRepository (live account switch), a small
// router rig that mounts the REAL `buildS03Routes` next to stub destinations
// and records which stub was built, and pump helpers.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/router/s03_routes.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/data/mode_store.dart';
import 'package:fitness_app/features/modes/state/mode_flags.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/shared/widgets/hud/hud_surface.dart' show HudPanel;

const AuthUser kUserA =
    AuthUser(uid: 'uid-a', displayName: 'A', provider: AuthProvider.google);
const AuthUser kUserB =
    AuthUser(uid: 'uid-b', displayName: 'B', provider: AuthProvider.google);

/// Global call counter shared by every spy, so a store write and a navigation
/// event can be ordered against each other.
int _seq = 0;
int nextSeq() => ++_seq;

class WriteCall {
  WriteCall(this.seq, this.uid, this.state);
  final int seq;
  final String uid;
  final ModeState state;
}

/// In-memory [ModeStore]. `writes` records every write attempt (also the failing
/// ones), so a "no write" assertion would see a write if one happened.
class FakeModeStore implements ModeStore {
  FakeModeStore({this.readDelay, this.writeDelay});

  final Map<String, ModeRead> data = <String, ModeRead>{};
  final List<WriteCall> writes = <WriteCall>[];
  final List<int> readSeqs = <int>[];
  final List<String> readUids = <String>[];
  final Set<String> wiped = <String>{};

  Duration? readDelay;
  Duration? writeDelay;

  /// Every write throws while true.
  bool throwOnWrite = false;

  /// The next [throwTimes] writes throw, later ones succeed.
  int throwTimes = 0;

  /// Writes return `failed` instead of throwing.
  bool failOnWrite = false;

  int reads = 0;

  void seed(String uid,
      {AppMode mode = AppMode.train,
      ChooserStatus status = ChooserStatus.resolved,
      Map<AppMode, ModeAnswer> answers = const <AppMode, ModeAnswer>{}}) {
    data[uid] = ModeReadValue(
        ModeState(selectedMode: mode, chooserStatus: status, answers: answers));
  }

  ModeState? stored(String uid) {
    final r = data[uid];
    return r is ModeReadValue ? r.state : null;
  }

  List<WriteCall> writesFor(String uid) =>
      writes.where((w) => w.uid == uid).toList();

  @override
  Future<ModeRead> read(String uid) async {
    reads++;
    readSeqs.add(nextSeq());
    readUids.add(uid);
    final d = readDelay;
    if (d != null) await Future<void>.delayed(d);
    return data[uid] ?? const ModeReadMissing();
  }

  @override
  Future<ModeWriteResult> write(String uid, ModeState state) async {
    writes.add(WriteCall(nextSeq(), uid, state));
    final d = writeDelay;
    if (d != null) await Future<void>.delayed(d);
    if (throwOnWrite) throw StateError('write failed (test)');
    if (throwTimes > 0) {
      throwTimes--;
      throw StateError('write failed once (test)');
    }
    if (failOnWrite) return ModeWriteResult.failed;
    if (wiped.contains(uid)) return ModeWriteResult.refusedWipedUid;
    data[uid] = ModeReadValue(state);
    return ModeWriteResult.written;
  }

  @override
  void markUidWiped(String uid) => wiped.add(uid);

  @override
  bool isUidWiped(String uid) => wiped.contains(uid);
}

/// Auth repository with a controllable current user (account switch tests).
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this._user);

  AuthUser? _user;
  final StreamController<AuthUser?> _c = StreamController<AuthUser?>.broadcast();

  void emit(AuthUser? u) {
    _user = u;
    _c.add(u);
  }

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _user;
    yield* _c.stream;
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthUser> signInAnonymously() async => _user ?? kUserA;

  @override
  Future<SignInResult> signInWithGoogle() => throw UnimplementedError();

  @override
  Future<void> signOut() async => emit(null);

  void dispose() => _c.close();
}

/// Mutable scan-access value behind `scanAccessProvider`.
final StateProvider<ScanAccess> fakeScanAccessProvider =
    StateProvider<ScanAccess>((_) => ScanAccess.allowed);

/// The stub destination pages the rig mounts, in the order they were built.
class Visits {
  final List<String> built = <String>[];
  String? get last => built.isEmpty ? null : built.last;
  int count(String path) => built.where((p) => p == path).length;
}

class _Stub extends StatefulWidget {
  const _Stub(this.path, this.visits);
  final String path;
  final Visits visits;
  @override
  State<_Stub> createState() => _StubState();
}

class _StubState extends State<_Stub> {
  @override
  void initState() {
    super.initState();
    widget.visits.built.add(widget.path);
  }

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('stub:${widget.path}', key: Key('stub:${widget.path}'))));
}

const List<String> kStubPaths = <String>[
  '/home',
  '/scan',
  '/workouts',
  '/form-check',
  '/body-scan',
  '/nutrition/add',
  '/nutrition/weight',
  '/progress',
  '/profile',
];

/// A running app made from the real S03 routes plus stubs.
class Rig {
  Rig({
    required this.store,
    required this.auth,
    this.locale = const Locale('en'),
    this.flags = const ModeFlags(),
    this.initial = '/mode-chooser',
    this.extraOverrides = const <Override>[],
    this.textScale = 1.0,
    this.platform,
    Map<String, WidgetBuilder>? replace,
  }) : replace = replace ?? const <String, WidgetBuilder>{};

  final FakeModeStore store;
  final FakeAuthRepository auth;
  final Locale locale;
  final ModeFlags flags;
  final String initial;
  final List<Override> extraOverrides;
  final double textScale;
  final TargetPlatform? platform;
  final Map<String, WidgetBuilder> replace;

  final Visits visits = Visits();
  late final GoRouter router = GoRouter(
    initialLocation: initial,
    routes: <RouteBase>[
      ...buildS03Routes(availability: flags.availabilityTable),
      for (final p in kStubPaths)
        GoRoute(
          path: p,
          builder: (ctx, st) =>
              replace[p]?.call(ctx) ?? _Stub(p, visits),
        ),
    ],
  );

  late final SharedPreferences prefs;
  late ProviderContainer container;

  Widget build() {
    return ProviderScope(
      overrides: <Override>[
        authRepositoryProvider.overrideWith((ref) => auth),
        modeStoreProvider.overrideWithValue(store),
        modeFlagsProvider.overrideWithValue(flags),
        trainingContextPrefsProvider
            .overrideWith((ref) => Future<SharedPreferences>.value(prefs)),
        scanAccessProvider.overrideWith((ref) => ref.watch(fakeScanAccessProvider)),
        ...extraOverrides,
      ],
      child: Builder(builder: (ctx) {
        container = ProviderScope.containerOf(ctx);
        return MaterialApp.router(
          theme: platform == null
              ? AppTheme.dark()
              : AppTheme.dark().copyWith(platform: platform),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child ?? const SizedBox.shrink(),
          ),
        );
      }),
    );
  }

  Future<void> dispose() async {
    router.dispose();
    auth.dispose();
  }
}

/// Builds a rig, sets the window and pumps the first frames.
Future<Rig> pumpRig(
  WidgetTester tester, {
  required FakeModeStore store,
  AuthUser? user = kUserA,
  Size size = const Size(360, 800),
  Locale locale = const Locale('en'),
  ModeFlags flags = const ModeFlags(),
  String initial = '/mode-chooser',
  List<Override> overrides = const <Override>[],
  double textScale = 1.0,
  TargetPlatform? platform,
  Map<String, String> prefValues = const <String, String>{},
  Map<String, WidgetBuilder>? replace,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(<String, Object>{...prefValues});
  final rig = Rig(
    store: store,
    auth: FakeAuthRepository(user),
    locale: locale,
    flags: flags,
    initial: initial,
    extraOverrides: overrides,
    textScale: textScale,
    platform: platform,
    replace: replace,
  );
  rig.prefs = await SharedPreferences.getInstance();
  addTearDown(rig.dispose);
  await tester.pumpWidget(rig.build());
  if (settle) await settleFrames(tester);
  return rig;
}

/// Bounded pumping (no `pumpAndSettle`: the chooser owns a 300 ms timer and the
/// sky background may animate).
Future<void> settleFrames(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AppLocalizations l10nOf(String lang) =>
    lookupAppLocalizations(Locale(lang));

Finder byKeyS(String k) => find.byKey(Key(k));

/// Semantics of the node that carries [finder]'s widget.
SemanticsNode sem(WidgetTester tester, Finder finder) =>
    tester.getSemantics(finder);

bool isSelectedNode(SemanticsNode n) =>
    // ignore: deprecated_member_use
    n.hasFlag(SemanticsFlag.isSelected);

bool isEnabledNode(SemanticsNode n) =>
    // ignore: deprecated_member_use
    n.hasFlag(SemanticsFlag.hasEnabledState) ? n.hasFlag(SemanticsFlag.isEnabled) : true;

/// All semantic text of a node subtree (label, hint, value).
String allText(SemanticsNode n) => '${n.label} ${n.hint} ${n.value}';

/// The HudPanel ancestor-or-self of [finder] (used to read `selected`).
HudPanel panelOf(WidgetTester tester, Finder finder) =>
    tester.widget<HudPanel>(find
        .descendant(of: finder, matching: find.byType(HudPanel))
        .first);

/// Counts every call on the permission, camera, location and picker channels.
class MockPermissionChannel {
  MockPermissionChannel(TestWidgetsFlutterBinding binding) {
    for (final name in channels) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(name), (MethodCall call) async {
        calls.add('$name/${call.method}');
        return null;
      });
    }
  }

  static const List<String> channels = <String>[
    'flutter.baseflow.com/permissions/methods',
    'flutter.baseflow.com/geolocator',
    'plugins.flutter.io/camera',
    'plugins.flutter.io/image_picker',
  ];

  final List<String> calls = <String>[];

  void dispose(TestWidgetsFlutterBinding binding) {
    for (final name in channels) {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
  }
}
