/// The reference clip, played as the Form Coach's demonstration.
///
/// G17. The design reference's figure is not a drawing: `core/design/
/// reference/fitness_hud_v1/Fitness Form Coach Phone.dc.html` puts a VIDEO of
/// a real person squatting side-on with a lit skeleton behind the HUD, and the
/// operator's requirement (2026-09-04) is that the demonstration looks exactly
/// like that. Every drawn stand-in shipped before this — a stick figure, a
/// filled outline, a composed outline — was rejected on a real phone, and the
/// last one was rejected while every test and review of it was green. So the
/// demonstration for the squat is the clip itself, bundled.
///
/// ## Lifecycle contract
///
/// A video decoder is not a repeating `AnimationController`, and the old
/// demonstration was careful even about that one: it ran only while on
/// screen, because anything ticking next to a live camera and a pose detector
/// on a phone nobody is holding is battery spent on nothing. This widget is
/// held to the same rule, mechanically (GPT-PM, G17 plan review, MAJOR):
///
/// - it plays only while [active] — the host sets that false the moment the
///   clip is no longer what the user is looking at, and does so AFTER the
///   cross-fade that hides it has finished, so a hidden loop never keeps
///   decoding underneath a tracked body;
/// - it pauses when the app leaves the foreground and resumes only if it is
///   still [active] when the app comes back;
/// - under the platform's reduce-motion setting it never plays at all — the
///   poster is the demonstration then, a still of the standing frame;
/// - it disposes its controller on unmount, always.
///
/// ## Failure contract
///
/// The clip is a bundled asset declared in pubspec, so a decoder that cannot
/// open it, refuses to play it, or drops it mid-loop is a build or device
/// defect, not a network condition. Every one of those is observed — the
/// `initialize` future, the `play`/`pause` futures, and the controller's own
/// error channel (`value.hasError`) after a successful open — and handled
/// the same way, terminally: the poster stays, the platform view comes
/// down, and a decoder that had actually opened is detached and disposed
/// right there rather than left running behind the poster until unmount (a
/// refused `pause` must not keep a decoder alive beside the camera; GPT-PM,
/// G17 commit review). A controller whose `initialize` threw has no native
/// player behind it and is only dropped — the real `dispose` would wait
/// forever on a creation that never finished. Nothing retries after a
/// failure. The failure is reported through Crashlytics with the same guard
/// every other call site in this app uses (telemetry must never break the
/// feature it instruments, and has no app to report against in
/// `flutter test`). A still where a loop was promised is exactly the kind of
/// defect that gets called a design choice; `debugPrint` alone would keep it
/// invisible on the one build that matters, the release on someone's phone.
///
/// The controller comes from [coachDemoControllerFactoryProvider], so a widget
/// test can hand in a `VideoPlayerController` subclass that records
/// initialize/play/pause/dispose without a platform underneath it, and every
/// clause above is a test rather than a promise.
library;

import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/hud_tokens.dart' show HudMotionX;

/// Builds the controller for a bundled clip. The default is the real asset
/// controller; tests override it.
typedef CoachDemoControllerFactory = VideoPlayerController Function(
    String asset);

final coachDemoControllerFactoryProvider =
    Provider<CoachDemoControllerFactory>(
        (_) => (asset) => VideoPlayerController.asset(asset));

class CoachDemoClip extends ConsumerStatefulWidget {
  const CoachDemoClip({
    super.key,
    required this.asset,
    required this.poster,
    required this.active,
  });

  /// Bundled MP4, e.g. `assets/coach_demo/squat_side.mp4`.
  ///
  /// Fixed for the life of the widget: the one clip source today is the
  /// squat's, and `CoachDemo` mounts the clip under a key of its own, so a
  /// change of movement is a new widget, never an update of this field. A
  /// second clip would need either an asset-derived key in `CoachDemo` or a
  /// reopen in `didUpdateWidget` — recorded in the G17 decision-log entry.
  final String asset;

  /// Its first frame, shown until the decoder is ready, kept if it never is,
  /// and the whole demonstration under reduce-motion.
  final String poster;

  /// Whether the clip is what the user is looking at right now. See the
  /// lifecycle contract in the library doc.
  final bool active;

  @override
  ConsumerState<CoachDemoClip> createState() => _CoachDemoClipState();
}

class _CoachDemoClipState extends ConsumerState<CoachDemoClip>
    with WidgetsBindingObserver {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;
  bool _foreground = true;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  Future<void> _open() async {
    final ctrl = ref.read(coachDemoControllerFactoryProvider)(widget.asset);
    _ctrl = ctrl;
    try {
      // Looping and muted are set before `initialize` on purpose: the
      // controller stores both and re-applies them to the native player from
      // its own initialized event (`video_player` 2.10.0,
      // `_applyLooping`/`_applyVolume` in `initialize`), so there is no
      // window in which the clip plays once, or audibly. Muted, always: the
      // reference clip is silent and the coach speaks over this screen; a
      // demonstration with its own audio would talk over it.
      await ctrl.setLooping(true);
      await ctrl.setVolume(0);
      await ctrl.initialize();
      // Unmounted while the decoder was opening: `dispose` has already run
      // and disposed this controller. Nothing to do, and certainly not a
      // second dispose.
      if (!mounted) return;
      ctrl.addListener(_onValue);
      setState(() => _ready = true);
      _sync();
    } catch (e, st) {
      _fail('failed to load', e, st);
    }
  }

  /// The controller's own error channel, for a decoder that opened and then
  /// dropped the clip: the poster is still underneath, and the platform view
  /// over it comes down with `_failed`.
  void _onValue() {
    final ctrl = _ctrl;
    if (ctrl == null || _failed || !ctrl.value.hasError) return;
    _fail('decoder error', ctrl.value.errorDescription ?? 'no description',
        StackTrace.current);
  }

  /// Failure is terminal AND quiescent: the controller is shut down here, not
  /// merely hidden. Hiding alone would leave a decoder whose `pause` had just
  /// been refused running behind the poster for as long as the panel is
  /// mounted — beside a live camera and a pose detector, the exact thing the
  /// lifecycle contract exists to prevent (GPT-PM, G17 commit review, MAJOR).
  /// `_ctrl` is nulled first so `dispose()` cannot reach it a second time.
  void _fail(String what, Object error, StackTrace stack) {
    debugPrint('coach demo clip $what: ${widget.asset}: $error');
    try {
      unawaited(FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        fatal: false,
        reason: 'coach demo clip $what: ${widget.asset}',
      ));
    } catch (_) {
      // Reporting failure is not itself reportable — same guard as every
      // other Crashlytics call site in this app.
    }
    final ctrl = _ctrl;
    _ctrl = null;
    // Only a decoder that actually opened has anything native to release. A
    // controller whose `initialize` threw has no player behind it, and the
    // real `dispose` would wait forever on the creation it never finished
    // (`video_player` 2.10.0, `_creatingCompleter`).
    if (ctrl != null && _ready) {
      ctrl.removeListener(_onValue);
      unawaited(ctrl.dispose().catchError((Object e) {
        debugPrint('coach demo clip dispose after $what: ${widget.asset}: $e');
      }));
    }
    if (!mounted || _failed) return;
    setState(() => _failed = true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = context.reduceMotion;
    _sync();
  }

  @override
  void didUpdateWidget(CoachDemoClip old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  /// One place decides whether the decoder runs, from every input at once, so
  /// the four clauses of the contract cannot disagree with each other.
  void _sync() {
    final ctrl = _ctrl;
    if (ctrl == null || !_ready || _failed) return;
    final shouldPlay = widget.active && _foreground && !_reduceMotion;
    if (shouldPlay && !ctrl.value.isPlaying) {
      _observe('play', ctrl.play());
    } else if (!shouldPlay && ctrl.value.isPlaying) {
      _observe('pause', ctrl.pause());
    }
  }

  /// A rejected `play`/`pause` is a failure of the same kind as a failed
  /// open, not a future nobody is holding.
  void _observe(String op, Future<void> future) {
    unawaited(future.catchError((Object e, StackTrace st) {
      _fail('$op failed', e, st);
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.removeListener(_onValue);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    final playing = _ready && !_failed && ctrl != null && !_reduceMotion;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          widget.poster,
          key: const Key('form_check.demo_poster'),
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
        if (playing)
          // Cover-fitted like the reference's `object-fit: cover`: the clip is
          // 9:16 and so is the panel, so this crops nothing on the phones the
          // panel was designed for and only trims the edges on the others.
          FittedBox(
            key: const Key('form_check.demo_video'),
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: ctrl.value.size.width,
              height: ctrl.value.size.height,
              child: VideoPlayer(ctrl),
            ),
          ),
      ],
    );
  }
}
