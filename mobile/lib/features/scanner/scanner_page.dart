import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../ai_coach/ai_coach_context.dart';
import '../ai_coach/ai_coach_sheet.dart';
import '../../core/camera/camera_availability.dart';
import '../../core/camera/camera_session.dart';
import '../../core/camera/centre_crop.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../equipment/state/equipment_providers.dart';
import '../safety/state/eligibility_providers.dart' show safetyContextProvider;
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/experimental_banner.dart';
import '../../shared/widgets/glass.dart';
import '../../shared/widgets/shell_insets.dart';
import '../visual_equipment/data/live_recognition.dart';
import '../visual_equipment/data/scan_outcome.dart';
import '../visual_equipment/data/recognition_history.dart';
import '../visual_equipment/data/visual_equipment_match.dart';
import '../visual_equipment/data/machine_card.dart';
import '../visual_equipment/state/live_equipment_providers.dart';
import '../visual_equipment/state/machine_card_providers.dart';
import '../visual_equipment/state/recognition_history_providers.dart';
import '../visual_equipment/state/visual_equipment_providers.dart';
import '../visual_equipment/widgets/live_equipment_preview.dart';
import '../visual_equipment/widgets/machine_card_view.dart';
import 'widgets/scan_frame.dart';

/// The Scan tab.
///
/// One job: **photograph a machine and recognise it** — point the phone at
/// any piece of equipment, tap Recognise, and it is classified (cloud first,
/// on-device fallback), then routed to the exercises tuned to the user's
/// intake + injuries. QR scanning was removed at the operator's request
/// (2026-07-30, point 7): photo recognition is the one path.
///
/// One camera, one owner. The viewfinder is live the whole time this tab is
/// open, because "I cannot see what I am pointing at" was a real defect. What
/// the Live switch gates is the equipment LABELER, not the camera: that is the
/// expensive part, and it burns battery for nothing when not asked for.
class ScannerPage extends ConsumerStatefulWidget {
  const ScannerPage({super.key});

  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends ConsumerState<ScannerPage>
    with WidgetsBindingObserver {
  bool _handling = false;

  /// Distinguishes "you haven't tried yet" from "we looked and found nothing" —
  /// the two used to render the same hint card.
  bool _attempted = false;

  /// Set when the camera could not be opened at all, so the page can say WHY
  /// instead of showing a placeholder forever.
  ///
  /// R2.9: typed, not a bare `Object`. It used to hold the raw plugin
  /// exception and every cause — permission refused, refused permanently, no
  /// camera at all — rendered the same sentence with the exception appended.
  CameraUnavailable? _cameraFailure;

  /// True while a permission request or retry is in flight, so the action
  /// button can show progress and refuse a second tap.
  bool _retrying = false;

  GoRouter? _router;

  /// Captured at arm time so [_disarm] can release the camera WITHOUT touching
  /// `ref`. Reading a provider from `dispose()` throws "Cannot use ref after the
  /// widget was disposed" — a mistake this codebase has now made three times:
  /// the third came from REMOVING awaits ahead of a `mounted`-guarded read,
  /// which turned a path that always ran post-dispose (guard worked) into a
  /// synchronous one where `mounted` is still true but riverpod's element is
  /// already flagged disposed. Fields, not ref, on every teardown path.
  CameraSession? _session;
  StateController<bool>? _liveMode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _arm());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (router == _router) return;
    _router?.routerDelegate.removeListener(_onRouteChanged);
    _router = router;
    router.routerDelegate.addListener(_onRouteChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router?.routerDelegate.removeListener(_onRouteChanged);
    // The session outlives this page (it is app-lifetime, by design), so a
    // listener left attached would call setState on a defunct element every
    // time the watchdog fired for whoever holds the camera next.
    _session?.selfStopped.removeListener(_onSessionSelfStopped);
    // No live-mode flip here: flipping the provider mid-dispose notifies this
    // very element after it is defunct. It is also unnecessary — the page is
    // going away, so the autoDispose recognition provider detaches the
    // labeler on its own. The flip is for the routes-change path, where this
    // page stays alive under the shell.
    unawaited(_disarm(flipLiveMode: false));
    super.dispose();
  }

  /// Releases the camera whenever this tab is not the visible route.
  ///
  /// Structural on purpose. `/equipment/:id` is a top-level route rendered ABOVE
  /// the shell, so this page is never disposed when the user taps through and
  /// `autoDispose` cannot fire. The previous design asked every call site to
  /// remember to switch live mode off first, and one of them — the photo-match
  /// list — did not, leaving the camera streaming with the indicator lit behind
  /// the page being read. Reacting to the route instead means no call site has
  /// to remember anything.
  void _onRouteChanged() {
    final onScan = (_router?.state.matchedLocation ?? '') == '/scan';
    if (onScan) {
      _arm();
    } else {
      unawaited(_disarm());
    }
  }

  /// Android hands the camera to other apps freely; release it on the way out.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onRouteChanged();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_disarm());
    }
  }

  /// Opens the camera. Idempotent.
  ///
  /// [requestPermission] is false on every automatic path — arrival, route
  /// change, app resume. The system dialog belongs to the moment the user
  /// asks for the camera, not to every foreground event; without that split
  /// a refusal re-prompted on each resume.
  Future<void> _arm({bool requestPermission = false}) async {
    if (!mounted) return;
    try {
      // Inside the try, not above it: these are `ref` reads on a path that
      // also runs from lifecycle callbacks, and a throw here used to escape
      // _arm entirely — past its own catch, out through the retry button's
      // `unawaited`, leaving the spinner cleared and nothing on screen.
      _session ??= ref.read(scanCameraSessionProvider);
      _liveMode ??= ref.read(liveModeEnabledProvider.notifier);
      // A session that stops ITSELF (the frame-stall watchdog) throws nothing
      // — nobody is awaiting it. Without this listener the preview simply fell
      // back to its warming spinner and stayed there, with none of the
      // reason-and-retry UI, until the user happened to leave and come back.
      _session!.selfStopped.removeListener(_onSessionSelfStopped);
      _session!.selfStopped.addListener(_onSessionSelfStopped);
      await _session!.start(requestPermission: requestPermission);
      if (!mounted) return;
      if (_cameraFailure != null) setState(() => _cameraFailure = null);
    } catch (e) {
      // Permission refused, refused for good, no camera at all, or a failed
      // init. Surfaced with its reason, because a viewfinder that never
      // appears with no explanation is the defect this page was reported for,
      // and one message for four causes only tells the user something is
      // wrong — not which of the four fixes is theirs.
      if (!mounted) return;
      setState(() => _cameraFailure = classifyCameraFailure(e));
    }
  }

  /// Mirrors a session that stopped itself into the page's failure state, so
  /// the same overlay and retry button handle it.
  void _onSessionSelfStopped() {
    final failure = _session?.selfStopped.value;
    if (!mounted || failure == null) return;
    setState(() => _cameraFailure = failure);
  }

  /// Retries after a failure the user can plausibly have fixed.
  ///
  /// Goes through [_arm] rather than calling `start()` directly so a retry
  /// runs the permission gate again — the whole point when the user has just
  /// returned from granting access in Settings. Requests the permission,
  /// because reaching this button IS the user asking for the camera.
  Future<void> _retryCamera() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await _arm(requestPermission: true);
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  /// Sends the user to the system settings page for this app.
  ///
  /// No retry is scheduled here: leaving for Settings backgrounds the app, and
  /// `didChangeAppLifecycleState` re-arms on resume, which is the same path a
  /// successful grant would take anyway.
  Future<void> _openCameraSettings() async {
    // The result is checked, not discarded. This is the ONLY action offered
    // for a permanently-refused permission, so a platform that declines to
    // open Settings — some locked-down Android builds do — would otherwise
    // leave the user tapping a button that does nothing, with no feedback and
    // no other way forward.
    var opened = false;
    try {
      opened = await ref.read(cameraPermissionGateProvider).openSettings();
    } catch (e) {
      debugPrint('open app settings failed: $e');
    }
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).scannerCouldNotOpenSettings),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _disarm({bool flipLiveMode = true}) async {
    // Fields only — no `ref` anywhere on this path, it also runs from
    // dispose(). The try guards the teardown race where the ProviderScope is
    // being destroyed right after this page (test teardown, app shutdown).
    if (flipLiveMode) {
      try {
        final live = _liveMode;
        if (live != null && live.state) live.state = false;
      } catch (e) {
        debugPrint('live-mode off on disarm skipped: $e');
      }
    }
    await _session?.stop();
  }

  /// Every confident identification is remembered, whatever found it.
  /// The last live reading actually written, per machine.
  ///
  /// The repository dedups by *value* — it merges a new sighting into the
  /// existing row rather than adding one — so it collapses rows and not
  /// writes. Every settled frame still cost a `get()` plus a `set()` on the
  /// same document, and `RecognitionSmoother` reports settled on every frame
  /// once its window fills, not once per sighting. That is a read-modify-write
  /// at labeler frame rate against one document, past Firestore's sustained
  /// limit of one write per second, with two in-flight frames able to read the
  /// same stale row and the later `set` discarding the higher confidence the
  /// merge exists to keep.
  ///
  /// Gating the write here rather than the value there is what actually stops
  /// it: nothing is sent at all inside the window.
  final Map<String, DateTime> _lastLiveWrite = {};

  /// Matches the repository's own dedup window, so the gate cannot suppress a
  /// sighting the repository would have treated as new.
  static const _liveWriteInterval = Duration(minutes: 5);

  /// True if a live reading for [equipmentId] is worth a write right now.
  bool _shouldWriteLive(String equipmentId, DateTime now) {
    final last = _lastLiveWrite[equipmentId];
    if (last != null && now.difference(last) < _liveWriteInterval) return false;
    _lastLiveWrite[equipmentId] = now;
    return true;
  }

  void _remember(
      String equipmentId, double confidence, RecognitionSource source) {
    // Fire-and-forget by design — a failed history write must never block
    // routing to the exercises. But it must not vanish either: this is the only
    // place record() is called, so an unhandled rejection here would be the
    // whole feature failing invisibly.
    unawaited(
      ref
          .read(recognitionHistoryRepositoryProvider)
          .record(
            RecognitionEntry(
              equipmentId: equipmentId,
              recognisedAt: DateTime.now(),
              confidence: confidence,
              source: source,
            ),
          )
          .catchError((Object e, StackTrace st) {
        debugPrint('recognition history write failed ($equipmentId): $e');
        debugPrintStack(stackTrace: st);
      }),
    );
  }

  /// Navigates away. The route listener releases the camera on its own.
  Future<void> _openEquipment(String id) async {
    if (!mounted) return;
    await GoRouter.of(context).push('/equipment/$id');
  }

  /// Primary action: photograph the machine WITHOUT leaving the app.
  ///
  /// Shoots through the same session the viewfinder shows. The old path used
  /// `ImagePicker(source: camera)`, which hands off to the system camera as a
  /// separate activity — the app backgrounds, the preview freezes on return,
  /// and it is not what was asked for.
  Future<void> _recogniseWithCamera() async {
    if (_handling) return;
    _handling = true;
    try {
      final shot = await ref.read(scanCameraSessionProvider).captureStill();
      if (shot == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).scannerCameraUnavailable),
        ));
        return;
      }
      // Classify what the user FRAMED, not the whole crowded gym: the shot is
      // cropped to the same central region the guide frame shows. Gallery
      // picks are deliberately not cropped — the user composed those.
      await _classify(await centreCropForClassification(shot.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).scannerCouldNotCapture(e)),
      ));
    } finally {
      _handling = false;
    }
  }

  /// Secondary action: classify a photo the user already has.
  Future<void> _recogniseFromGallery() async {
    if (_handling) return;
    _handling = true;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 88,
      );
      if (picked == null) return;
      await _classify(picked.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).scannerCouldNotCapture(e)),
      ));
    } finally {
      _handling = false;
    }
  }

  /// The image the last scan ran on, so a timeout or a failure can be retried
  /// without making the user photograph the machine again.
  String? _lastScannedPath;

  Future<void> _classify(String path) async {
    if (mounted) setState(() => _attempted = true);
    _lastScannedPath = path;
    await ref
        .read(visualEquipmentControllerProvider.notifier)
        .classifyFilePath(path);
    final result = ref.read(visualEquipmentControllerProvider).valueOrNull;
    // The rule lives on ScanResult, not as an `if` here: this method needs a
    // real camera file to run, so a decision written inline would be one no
    // host test can reach. See ScanResult.isWorthRemembering.
    if (result != null && result.isWorthRemembering) {
      final top = result.matches.firstOrNull;
      if (top != null) {
        _remember(top.equipmentId, top.confidence, RecognitionSource.photo);
      }
    }
  }

  /// Re-runs recognition on the same shot. Offered only for outcomes where a
  /// second attempt can genuinely differ (timeout, failure) — never for
  /// "not in the catalogue", where the same image and model produce the same
  /// answer and the button would be a loop with a friendly label.
  ///
  /// Guarded by the same `_handling` flag the capture paths use. Without it a
  /// double tap — which a card headed "recognition took too long" actively
  /// invites — fired two concurrent recognitions racing on the controller's
  /// state, the machine card and the history write: two paid cloud calls, two
  /// history rows, last-write-wins on screen.
  Future<void> _retryLastScan() async {
    final path = _lastScannedPath;
    if (path == null || _handling) return;
    setState(() => _handling = true);
    try {
      await _classify(path);
    } finally {
      if (mounted) setState(() => _handling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scan = ref.watch(visualEquipmentControllerProvider);
    final card = ref.watch(lastMachineCardProvider);
    final liveOn = ref.watch(liveModeEnabledProvider);
    final session = ref.watch(scanCameraSessionProvider);
    // Record settled live readings, at most one write per machine per window.
    //
    // The old comment here said the repository's dedup kept a camera held on
    // one machine from writing a row per frame. True about rows, false about
    // writes: the dedup merges values, it never says "skip this one", so a
    // held camera produced a get+set per settled frame on a single document.
    ref.listen<AsyncValue<LiveRecognition?>>(liveRecognitionProvider,
        (prev, next) {
      final r = next.valueOrNull;
      // Tentative readings are feedback for the user, not evidence — only a
      // settled vote is worth remembering.
      if (r == null || !r.settled) return;
      if (!_shouldWriteLive(r.equipmentId, DateTime.now())) return;
      _remember(r.equipmentId, r.confidence, RecognitionSource.live);
    });
    return FrostedScaffold(
      // R11c: no app bar, no page-level list. The design hands this screen to
      // the camera (`App.tsx:2565-2720`) -- the preview fills it edge to edge,
      // the chrome floats on glass over it, and everything else lives in a
      // sheet the user pulls up.
      //
      // The screen was already most of the way there in intent: the preview
      // was 68% of the height because "recognition is aiming, and aiming is
      // the whole screen's job" (operator: "камера была почти во весь экран").
      // It was still a card in a scroll view, so aiming scrolled away.
      body: Stack(
        children: [
          Positioned.fill(
            child: Stack(
              fit: StackFit.expand,
              children: [
                  if (_cameraFailure != null)
                    _CameraUnavailable(
                      failure: _cameraFailure!,
                      busy: _retrying,
                      onRetry: _retryCamera,
                      onOpenSettings: _openCameraSettings,
                    )
                  else ...[
                    LiveEquipmentPreview(session: session),
                    // R2.2 state 9. Over the viewfinder, not instead of it:
                    // the guidance is "add light", and a user who cannot see
                    // what the camera sees cannot tell whether they followed
                    // it. Non-blocking by construction.
                    ValueListenableBuilder<bool>(
                      valueListenable: session.isLowLight,
                      builder: (context, dark, _) => dark
                          ? Align(
                              alignment: Alignment.topCenter,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: _ViewfinderBanner(
                                  key: const Key('scan-low-light'),
                                  icon: Icons.light_mode_outlined,
                                  text: AppLocalizations.of(context)
                                      .scannerLowLight,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    // Only over a live viewfinder. An aiming frame drawn on
                    // top of "camera access is blocked" tells the user to aim
                    // at something that is not there — and, being the topmost
                    // Stack child, it also sat over the overlay's own action
                    // button. IgnorePointer because it is decoration: it must
                    // never be what a tap lands on.
                    //
                    // R11c: corner brackets with a sweep line, and a pulse
                    // while a capture is classified (`App.tsx:2592-2614`).
                    // The plain outline this replaces marked the right area
                    // and said nothing else -- a two-second classification
                    // looked like a frozen screen, because nothing on the
                    // viewfinder distinguished "aim" from "working".
                    IgnorePointer(
                      child: ScanFrame(
                        key: const Key('scan-frame'),
                        phase: scan.isLoading
                            ? ScanFramePhase.analyzing
                            : ScanFramePhase.ready,
                      ),
                    ),
                  ],
                ],
            ),
          ),
          // The design's top chrome (`App.tsx:2584-2590`): a title pill on
          // glass, with the live-labelling toggle where its capture-mode
          // button sits. No back arrow -- the design's returns to Home, and
          // here Scan IS a root tab, so the bottom nav already does that. A
          // second control doing the same thing is one more thing to explain.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: ScanTopBar(
                live: liveOn,
                onLive: (on) =>
                    ref.read(liveModeEnabledProvider.notifier).state = on,
              ),
            ),
          ),
          // Everything that is not the viewfinder. A sheet rather than a list
          // under the camera: at rest it shows the capture controls and the
          // top of the answer, and it pulls up over the preview when the user
          // wants the history or the alternatives.
          // Sized in PIXELS, not in a fraction of the screen.
          //
          // `MainShell` sets `extendBody: true`, so this Stack is laid out
          // against the full height and the nav bar is then painted over its
          // bottom ~110-130px. The old `minChildSize: 0.24` ignored that: on a
          // 780px phone the sheet's lowest position was 187px tall, of which
          // 128 were behind the bar — the caption under the shutter was gone
          // and the scrollable strip, the ONLY surface that can drag the sheet
          // back up, was entirely hidden. The sheet became unrecoverable, not
          // merely cramped, which is exactly what the operator hit.
          //
          // LayoutBuilder rather than `MediaQuery.sizeOf`: `FrostedScaffold`
          // decides this body's height, and a screen-height guess would be
          // wrong by the status bar in the unsafe direction.
          LayoutBuilder(builder: (context, box) {
            const maxFrac = 0.92;
            final obstruction = shellBottomObstruction(context);
            double frac(double content, double designed) => sheetMinChildSize(
                  viewportHeight: box.maxHeight,
                  obstruction: obstruction,
                  visibleContentNeeded: content,
                  floor: designed,
                  ceiling: maxFrac,
                );
            // The design's own 0.24 / 0.34 are kept as the FLOOR. On a screen
            // tall enough for them they are what the sheet uses, unchanged;
            // the pixel budget only lifts them where the bar would otherwise
            // eat the controls.
            final minFrac = frac(_kScanSheetHead + _kScanSheetDragStrip, 0.24);
            final restFrac = frac(
                _kScanSheetHead +
                    _kScanSheetRestingPeek +
                    _kScanSheetBannerAllowance,
                0.34);
            return DraggableScrollableSheet(
            initialChildSize: restFrac,
            minChildSize: minFrac,
            maxChildSize: maxFrac,
            snap: true,
            builder: (context, controller) => _ScanSheet(
              controller: controller,
              bottomInset: obstruction,
              capture: _CaptureCluster(
                onCamera: _recogniseWithCamera,
                onGallery: _recogniseFromGallery,
              ),
              children: [
          const _ScanPrivacyStrip(),
          // Also gated on `_cameraFailure == null`, the same condition the
          // viewfinder itself branches on above: without it, denying camera
          // permission left this card showing regardless, its `_LiveCard`
          // spinner stuck on "Ищем..." forever -- no frames were ever going
          // to arrive to settle it, and nothing on screen said why.
          if (liveOn && _cameraFailure == null) ...[
            const SizedBox(height: 14),
            _LiveSection(onOpen: _openEquipment),
          ],
          const SizedBox(height: 14),
          scan.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            // Kept for a state the controller no longer produces — it now
            // converts every failure into a ScanResult so the outcome, not an
            // exception, drives the screen. Left as a safety net rather than
            // a `!`: an unexpected AsyncError must not blank the page.
            error: (e, _) => GlassCard(
              tint: theme.colorScheme.error,
              child: Text(
                  AppLocalizations.of(context).scannerRecognitionFailed(e)),
            ),
            data: (result) => switch (result.outcome) {
              ScanOutcome.confident || ScanOutcome.alternatives => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // R2.8. Only for a confident answer: the coach needs ONE
                    // subject, and `alternatives` is the app saying it does
                    // not know which of them the user is standing at. Offering
                    // "ask about this machine" there would pick one silently —
                    // the same thing the alternatives list exists to avoid.
                    if (result.outcome == ScanOutcome.confident &&
                        result.matches.isNotEmpty) ...[
                      _ScanAiCoachEntry(match: result.matches.first),
                      const SizedBox(height: 10),
                    ],
                    // R2.2 state 12. The hybrid recogniser falls back to the
                    // on-device model "silently-but-logged" — the user got the
                    // weaker answer and was never told why it was weaker, so a
                    // low-confidence result in a basement gym read as the app
                    // being bad rather than the network being absent.
                    if (result.answeredOffline) ...[
                      _ScanNote(
                        key: const Key('scan-offline-answer'),
                        icon: Icons.cloud_off_rounded,
                        text: AppLocalizations.of(context)
                            .scannerOfflineAnswer,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _Matches(matches: result.matches, onOpen: _openEquipment),
                  ],
                ),
              // Not in the catalogue, but the describer could name it. That
              // card IS the answer -- "не удалось понять" stops being true the
              // moment the app can say what the machine is.
              ScanOutcome.unknown => card != null
                  ? MachineCardView(card: card)
                  : _HintCard(theme: theme, noMatch: _attempted),
              // Nothing machine-like in the frame. Distinct from unknown:
              // telling someone pointing at a wall that their machine is
              // missing from our catalogue is a lie about our data.
              ScanOutcome.noEquipment =>
                _HintCard(theme: theme, noMatch: _attempted),
              ScanOutcome.timeout => _ScanProblemCard(
                  key: const Key('scan-timeout'),
                  title: AppLocalizations.of(context).scannerTimeoutTitle,
                  body: AppLocalizations.of(context).scannerTimeoutBody,
                  busy: _handling,
                  onRetry: _retryLastScan,
                ),
              ScanOutcome.failed => _ScanProblemCard(
                  key: const Key('scan-failed'),
                  title: AppLocalizations.of(context).scannerFailedTitle,
                  body: AppLocalizations.of(context).scannerFailedBody,
                  busy: _handling,
                  onRetry: _retryLastScan,
                ),
            },
          ),
          const SizedBox(height: 20),
          _HistorySection(onOpen: _openEquipment),
          const _PreparingSection(),
              ],
            ),
            );
          }),
        ],
      ),
    );
  }
}

/// The glass strip over the top of the viewfinder.
///
/// Public so its layout can be pumped at a given width and locale without a
/// camera. It was private, and the only way to reach it was through the whole
/// scanner page — which is why the 12px Russian overflow it shipped with was
/// found by a device walk rather than by a widget test that costs milliseconds.
/// Testability is a design property; see `scan_strip_overflow_test.dart`.
class ScanTopBar extends StatelessWidget {
  const ScanTopBar({super.key, required this.live, required this.onLive});

  final bool live;
  final ValueChanged<bool> onLive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      // Both pills shrink; neither is allowed to push the row past the screen.
      //
      // This strip overflowed by 12px on a real device in Russian, and the
      // reason it was never caught is worth keeping: the host suite renders in
      // English (`kTestLocale`), where these read "Scan" and "Live". Production
      // pins Russian — "Распознавание" and "Живой режим" — so the overflow was
      // visible to every actual user and to none of the 2,039 host tests. The
      // device walk found it on the first run.
      // Both pills shrink; neither may push the row past the screen.
      //
      // This strip overflowed on a real device in Russian, and the reason no
      // host test saw it is worth keeping: the suite renders in English
      // (`kTestLocale`), where these read "Scan" and "Live" -- four characters
      // each. Production pins Russian (`main.dart`): "Распознавание" and
      // "Живой режим". Measured against the pre-fix layout, the overflow was
      // 142px at 320 logical pixels, 102px at 360 and 51px at 411 -- so it was
      // visible to every Russian-speaking user, worst on the cheapest phones,
      // and invisible to all 2,039 host tests. The device walk found it on its
      // first run; `scan_strip_overflow_test.dart` now holds it.
      child: Row(
        // Keeps the two pills at opposite ends the way `Spacer` did, without
        // `Spacer`'s side effect: it takes every pixel the children do not,
        // which makes the row's minimum width the sum of two unshrinkable
        // pills plus a Switch, whatever the screen is.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colors.cameraOverlay,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                l10n.scannerScan,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Gates the labeler, not the camera. On the scrim rather than in a
          // bar, so it stays the same control it was -- the tests that drive
          // `scan-live-toggle` still find a Switch.
          Flexible(
            child: Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                color: theme.colors.cameraOverlay,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      l10n.scannerLive,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: Colors.white),
                    ),
                  ),
                  // The Switch keeps its intrinsic size on purpose: an
                  // ellipsised label is still readable, a squeezed toggle is
                  // not reliably tappable.
                  Switch(
                    key: const Key('scan-live-toggle'),
                    value: live,
                    onChanged: onLive,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gallery, shutter, and the room the design leaves for a flash control.
///
/// The shutter is a 68px circle rather than the old full-width filled button,
/// per `App.tsx:2636-2700`. Both keys are unchanged (`scan-recognise-camera`,
/// `scan-recognise-gallery`) because they are what every scanner test drives,
/// and this gate changes where the controls sit, not what they do.
class _CaptureCluster extends StatelessWidget {
  const _CaptureCluster({required this.onCamera, required this.onGallery});

  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Not `AppIconButton`: that wraps `IconButton`, which drops the
        // visible outline this control has always had. `Tooltip` is the same
        // fix `IconButton.tooltip` applies internally, applied by hand.
        SizedBox(
          width: 56,
          child: Tooltip(
            message: l10n.scannerPickFromGallery,
            child: OutlinedButton(
              key: const Key('scan-recognise-gallery'),
              onPressed: onGallery,
              child: const Icon(Icons.photo_library_outlined),
            ),
          ),
        ),
        const SizedBox(width: 28),
        Tooltip(
          message: l10n.scannerRecogniseMachine,
          child: Semantics(
            button: true,
            label: l10n.scannerRecogniseMachine,
            child: Material(
              color: theme.colors.accentPrimary,
              shape: const CircleBorder(),
              child: InkWell(
                key: const Key('scan-recognise-camera'),
                customBorder: const CircleBorder(),
                onTap: onCamera,
                child: SizedBox(
                  width: 68,
                  height: 68,
                  child: Icon(Icons.photo_camera_outlined,
                      size: 28, color: theme.colors.onAccent),
                ),
              ),
            ),
          ),
        ),
        // The design's third slot is a flash toggle. Left empty rather than
        // faked: `CameraSession` has no torch API, and a button that cannot
        // turn the light on is worse than a gap. Balanced so the shutter stays
        // centred.
        const SizedBox(width: 28),
        const SizedBox(width: 56),
      ],
        ),
        const SizedBox(height: 6),
        // The design's shutter is a bare circle. This app names its controls:
        // an icon-only PRIMARY action is discoverable only to someone who
        // already knows what it does, and `gallery_button_a11y_test.dart`
        // exists because that exact gap was found here before. The caption
        // keeps the design's shape and the control's name.
        Text(
          l10n.scannerRecogniseMachine,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colors.textSecondary),
        ),
      ],
    );
  }
}

/// The scan sheet's fixed head: `8 + 4` for the drag handle, `12`, then the
/// capture cluster (a 68px shutter, a 6px gap and its ~18px caption), then 12.
///
/// Named because the sheet's minimum height is DERIVED from it. Written as the
/// sum rather than as `128` so that changing the shutter changes the number
/// that keeps it on screen.
const double _kScanSheetHead = 8 + 4 + 12 + 68 + 6 + 18 + 12;

/// The scrollable strip kept visible when the sheet is at its lowest.
///
/// This is the load-bearing one. The head does not scroll, so the list is the
/// only surface a drag can reach, and `DraggableScrollableSheet` grows the
/// sheet from that list's overscroll. A minimum that hides the list leaves the
/// sheet with no way back up at all.
const double _kScanSheetDragStrip = 72;

/// How much of the answer sits under the head when the sheet is at rest.
///
/// A1 note: the disclosure banner is now the first thing in this list, so this
/// budget alone no longer describes what is visible — the banner eats into it
/// before the answer starts. [_kScanSheetBannerAllowance] is added at the call
/// site so the answer keeps the visibility this number was chosen for.
const double _kScanSheetRestingPeek = 150;

/// Room for the experimental disclosure that now precedes the answer.
///
/// An allowance, not a measurement: the banner is two text lines at default
/// scale and grows with the user's text size, so no constant can be exactly
/// right. It is sized for the default case, which is the one where a too-small
/// value would silently push the scan result under the fold.
///
/// The cost is a slightly taller sheet at rest, i.e. slightly less viewfinder.
/// That is the deliberate trade: this screen's job is aiming, but a disclosure
/// the user must drag to discover is not a disclosure, and an answer they must
/// drag to discover is not an answer either. Both fit instead.
const double _kScanSheetBannerAllowance = 96;

/// The pull-up sheet holding everything that is not the viewfinder.
class _ScanSheet extends StatelessWidget {
  const _ScanSheet({
    required this.controller,
    required this.capture,
    required this.children,
    required this.bottomInset,
  });

  final ScrollController controller;
  final Widget capture;
  final List<Widget> children;

  /// Pixels at the bottom covered by the nav bar. The list pads past it so its
  /// last row can be scrolled clear of the bar instead of resting under it.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        // Opaque, not the card's translucent fill: this sheet sits over a live
        // camera frame, and at card opacity the preview reads straight through
        // the text on top of it -- the same defect `GlassCard.floating`
        // documents for bottom sheets.
        color: theme.colors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: theme.colors.outline)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colors.textDisabled,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: capture,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              controller: controller,
              // Was a flat `110`, which was a guess at the bar's height and
              // ignored the gesture inset underneath it entirely.
              padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset + 12),
              children: [
                // A1. In the sheet rather than over the viewfinder: the claim
                // this qualifies is "that machine is a lat pulldown", and the
                // sheet is where it is made. A permanent band across a camera
                // whose whole job is aiming would be read once and then be in
                // the way for every scan after.
                ExperimentalBanner(
                    message: AppLocalizations.of(context).experimentalScanner),
                ...children,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "My machines" — every machine this user has ever identified, newest
/// first, one tap back to its exercises. The store existed and was written
/// on every recognition; this is the first UI that READS it (operator
/// point 9: "сохраняй все распознанные тренажёры").
class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.onOpen});
  final Future<void> Function(String equipmentId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(recognitionHistoryProvider).valueOrNull;
    // Still loading is not the same as empty. Rendering the empty state here
    // would flash "nothing yet" at a user who has a full list arriving.
    if (entries == null) return const SizedBox.shrink();
    if (entries.isEmpty) {
      // R2.6 requires an empty history to have a useful state. This section
      // used to vanish entirely when empty, which meant a user could not
      // learn the feature existed until they had already used it — the one
      // moment the explanation is worthless.
      return Column(
        key: const Key('scan-history-empty'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).scannerMyMachines,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).scannerMyMachinesEmpty,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
        ],
      );
    }

    // Catalog names are localized; while the catalog is still loading (or
    // for ids from older builds) fall back to a prettified id rather than
    // hiding the row.
    final names = <String, String>{
      for (final eq in ref.watch(equipmentListProvider).valueOrNull ?? const [])
        eq.id: eq.name,
    };

    return Column(
      key: const Key('scan-history'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).scannerMyMachines,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in entries.take(12))
              ActionChip(
                key: Key('scan-history-${e.equipmentId}'),
                avatar: const Icon(Icons.history, size: 16),
                label: Text(
                    names[e.equipmentId] ?? e.equipmentId.replaceAll('_', ' ')),
                onPressed: () => onOpen(e.equipmentId),
              ),
          ],
        ),
      ],
    );
  }
}

/// "Готовится" — the machines this user scanned that the catalog has no page
/// for, sitting under "мои тренажёры" rather than in it.
///
/// Kept separate on purpose: the machines above lead somewhere (their
/// exercises), and these do not yet. Mixing them would make a chip a coin
/// flip between a workout and a dead end.
class _PreparingSection extends ConsumerWidget {
  const _PreparingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cards = ref.watch(machineCardsProvider).valueOrNull ?? const [];
    // A card promoted to `inCatalog` has a real page now; it belongs to the
    // list above, and `declined` is our own bookkeeping, not the user's news.
    final preparing = cards
        .where((c) => c.status == MachineCardStatus.preparing)
        .toList(growable: false);
    if (preparing.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        key: const Key('scan-preparing'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).machineCardSectionTitle,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final c in preparing.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PreparingTile(card: c),
            ),
        ],
      ),
    );
  }
}

/// One row, expanding into the full explanation. Collapsed by default: the
/// user opened the Scan tab to scan, not to read the last five machines.
class _PreparingTile extends ConsumerWidget {
  const _PreparingTile({required this.card});
  final MachineCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return GlassCard(
      key: Key('scan-preparing-${card.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Theme(
        // The default divider draws a line through a glass card.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: Key('scan-preparing-tile-${card.id}'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(card.name,
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${l.machineCardNotInCatalogYet} · '
            '${l.machineCardSeenTimes(card.timesSeen)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          children: [
            // No photo here: the tile is a list row, and a 160px image per
            // machine turns the section into a gallery the user did not ask
            // for.
            MachineCardView(card: card, showPhoto: false),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: AppTertiaryButton(
                key: Key('scan-preparing-remove-${card.id}'),
                onPressed: () => ref
                    .read(machineCardRepositoryProvider)
                    .remove(card.id),
                icon: Icons.delete_outline,
                label: l.machineCardRemove,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.theme, this.noMatch = false});
  final ThemeData theme;

  /// True once a photo has been classified with no confident match, so the copy
  /// stops reading like the user never pressed the button.
  final bool noMatch;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            noMatch
                ? l.scannerCouldnTTellWhatThatIs
                : l.scannerPointAtAMachineAndTapRecognise,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            noMatch
                ? l.scannerTryFillingTheFrameWithOne
                : l.scannerWeIdentifyTheEquipmentOnDevice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live-mode readout. What the camera has settled on, how much of the vote
/// agreed, and a way straight into the exercises.
/// The catalogue's own localised name for [equipmentId], or the prettified id
/// while the catalogue is still loading.
///
/// Four call sites rendered `equipmentId.replaceAll('_', ' ')` straight onto
/// the screen, which is why a Russian UI showed the bare English `treadmill`
/// (operator screenshot 2026-08-06, `Screenshot_20260806_140916.jpg`). The ids
/// are English on purpose — they drive filtering and the alias index — so
/// every screen that shows one has to translate it, and doing that in one
/// function is what stops the next screen from forgetting.
///
/// The loading fallback is the same one the history chips already used: a
/// prettified id names the right machine, and waiting would show nothing.
String equipmentDisplayName(WidgetRef ref, String equipmentId) =>
    (ref.watch(equipmentListProvider).valueOrNull ?? const [])
        .where((eq) => eq.id == equipmentId)
        .map((eq) => eq.name)
        .firstOrNull ??
    equipmentId.replaceAll('_', ' ');

class _LiveCard extends ConsumerWidget {
  const _LiveCard({required this.recognition, required this.onOpen});
  final LiveRecognition? recognition;
  final Future<void> Function(String equipmentId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final r = recognition;
    if (r == null) {
      return GlassCard(
        key: const Key('scan-live-searching'),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.of(context).scannerLookingHoldTheCameraOnOne,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }
    if (!r.settled) {
      // The vote has a leader but hasn't passed its bars. Honest progress
      // beats an infinite spinner: name the leader, show its REAL numbers,
      // still let the user tap through if they can see it's right.
      return GlassCard(
        key: const Key('scan-live-tentative'),
        onTap: () => onOpen(r.equipmentId),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).scannerPossibly(
                        equipmentDisplayName(ref, r.equipmentId),
                        (r.confidence * 100).toStringAsFixed(0)),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    AppLocalizations.of(context).scannerKeepAiming,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
    }
    return GlassCard(
      key: const Key('scan-live-result'),
      onTap: () => onOpen(r.equipmentId),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  equipmentDisplayName(ref, r.equipmentId),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).scannerOfFramesAgree(
                      (r.confidence * 100).toStringAsFixed(0),
                      (r.agreement * 100).toStringAsFixed(0)),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _Matches extends ConsumerWidget {
  const _Matches({required this.matches, required this.onOpen});

  /// Routed through the page so navigation is uniform; the route listener is
  /// what releases the camera.
  final Future<void> Function(String equipmentId) onOpen;
  final List<VisualMatch> matches;

  /// Below this the header stops claiming "best matches" and says the app is
  /// not sure. With honest (un-renormalised) confidences a weak top match is
  /// visible again — the old pipeline inflated any lone survivor to 100%.
  static const _unsureBelow = 0.45;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unsure = matches.isEmpty || matches.first.confidence < _unsureBelow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          unsure
              ? AppLocalizations.of(context).scannerNotSureClosest
              : AppLocalizations.of(context).scannerBestMatches,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final m in matches) ...[
          GlassCard(
            onTap: () => onOpen(m.equipmentId),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        equipmentDisplayName(ref, m.equipmentId),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        AppLocalizations.of(context).scannerConfidence(
                            (m.confidence * 100).toStringAsFixed(0)),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                      ),
                      // Only for a match that came from text printed on the
                      // machine. The classifier fills `labelHint` too, but
                      // with its own internal label (`treadmill`, `bench`) --
                      // captioning that "read on the machine" would be a
                      // straight lie, which is why the source is checked and
                      // not merely the presence of the hint.
                      if (m.source == MatchSource.printedText &&
                          m.labelHint != null)
                        Text(
                          AppLocalizations.of(context)
                              .scannerReadOnMachine(m.labelHint!.toUpperCase()),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// The live-recognition card, watching the live stream on its own.
///
/// A separate widget because the page's `build` used to `ref.watch` the live
/// recognition directly, and that stream emits on essentially every processed
/// frame while Live mode is on — so the whole page (camera stack, buttons,
/// matches, history) rebuilt at inference rate. Scoping the watch here keeps
/// the rebuild to the one card whose contents actually changed. The same
/// pattern the low-light banner already uses two levels up.
class _LiveSection extends ConsumerWidget {
  const _LiveSection({required this.onOpen});

  final Future<void> Function(String equipmentId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final liveAsync = ref.watch(liveRecognitionProvider);
    // An error here means the model or the labeler failed, which is NOT the
    // same as "no machine recognised yet" — spinning forever on a broken
    // model was a real defect.
    if (liveAsync.hasError) {
      return GlassCard(
        key: const Key('scan-live-error'),
        tint: theme.colorScheme.error,
        child: Text(AppLocalizations.of(context)
            .scannerLiveRecognitionFailed(liveAsync.error ?? '')),
      );
    }
    return _LiveCard(recognition: liveAsync.valueOrNull, onOpen: onOpen);
  }
}

/// Opens the existing AI Coach sheet for a recognised machine.
///
/// R2.8. Reuses `AiCoachSheet` and its service unchanged — the same entry the
/// equipment page already offers, moved one step earlier to the moment the
/// user is standing in front of the machine with the answer on screen. No
/// second chat implementation, no second service, no new context type.
class _ScanAiCoachEntry extends ConsumerWidget {
  const _ScanAiCoachEntry({required this.match});

  final VisualMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // The catalogue's own localised name where it is loaded, the prettified
    // id otherwise — the same fallback the history chips use, so a coach
    // opened mid-catalogue-load still names the right machine rather than
    // waiting or showing nothing.
    final name = equipmentDisplayName(ref, match.equipmentId);

    // N04 (G-B/B4): the second ungated route to a prescription. Same rule and
    // same reasoning as `equipment_detail_page.dart` — hidden for a user who
    // has STATED something that refuses them (not merely one who has not
    // answered yet; see `SafetyContext.blockedByAStatedAnswer`), and hidden
    // while the answer is still resolving, rather than opened then refused.
    final safety = ref.watch(safetyContextProvider).valueOrNull;
    if (safety == null || safety.blockedByAStatedAnswer) {
      return const SizedBox.shrink();
    }

    return GlassCard(
      key: const Key('scan-ai-coach'),
      onTap: () => AiCoachSheet.show(
        context,
        source: AiCoachSource.equipment,
        subjectId: match.equipmentId,
        subjectName: name,
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).aiCoachButton,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  AppLocalizations.of(context).aiCoachButtonHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colors.textSecondary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

/// A qualifier attached to a result — how it was produced, not what it says.
class _ScanNote extends StatelessWidget {
  const _ScanNote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A short, non-blocking message drawn over the viewfinder.
///
/// Deliberately small and translucent: the camera stays the dominant surface,
/// per the rule that the viewfinder must not be covered by large cards.
class _ViewfinderBanner extends StatelessWidget {
  const _ViewfinderBanner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The DARK token set explicitly, not the app's current one: this sits on a
    // camera preview, which is dark whatever theme the app is in. Tokens
    // rather than literal whites because the design system's own guard test
    // counts hardcoded `Colors.white` and refuses new ones — correctly: two
    // more here is how a palette stops being a palette.
    final ink = AppSemanticColors.dark.textPrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppSemanticColors.dark.cameraOverlay,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: ink, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(color: ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A recognition attempt that ended without an answer, and the retry for it.
///
/// R2.2 states 11 and 13. Both were previously invisible: a timeout had no
/// representation at all (the call was unbounded, so the spinner simply never
/// stopped) and a failure rendered the caught exception into the card.
class _ScanProblemCard extends StatelessWidget {
  const _ScanProblemCard({
    super.key,
    required this.title,
    required this.body,
    required this.busy,
    required this.onRetry,
  });

  final String title;
  final String body;

  /// Disables the button while a retry is in flight. The card invites
  /// impatience by definition, so an enabled button during the retry is an
  /// invitation to fire a second one.
  final bool busy;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded,
                  color: theme.colorScheme.error, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colors.textSecondary)),
          const SizedBox(height: 12),
          AppSecondaryButton(
            key: const Key('scan-retry-recognition'),
            onPressed: busy ? null : () => unawaited(onRetry()),
            loading: busy,
            icon: Icons.refresh_rounded,
            label: AppLocalizations.of(context).scannerRetry,
          ),
        ],
      ),
    );
  }
}

/// The camera-off overlay, with the reason and the action that fixes it.
///
/// R2.9. The previous version took a raw `Object error`, printed one title for
/// every cause, and interpolated the exception into the body — which is both
/// the "never show internal exceptions" prohibition and, for a user who had
/// simply refused the permission, no path back: there was no button at all.
class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({
    required this.failure,
    required this.busy,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final CameraUnavailable failure;
  final bool busy;
  final Future<void> Function() onRetry;
  final Future<void> Function() onOpenSettings;

  /// Icon chosen per cause, so the state is not distinguished by wording
  /// alone — the same reason the app pairs colour with an icon elsewhere.
  IconData get _icon => switch (failure.reason) {
        CameraUnavailableReason.permissionDenied => Icons.lock_outline_rounded,
        CameraUnavailableReason.permissionPermanentlyDenied =>
          Icons.settings_outlined,
        CameraUnavailableReason.noCamera => Icons.no_photography_outlined,
        CameraUnavailableReason.initializationFailed =>
          Icons.camera_alt_outlined,
      };

  /// `permissionDenied` renders the EXPLANATION, not an accusation.
  /// `PermissionStatus.denied` means "never asked" and "asked once, refused"
  /// alike on Android — the platform does not separate them — so this card is
  /// the first thing a new user sees, and "Camera access denied" would be a
  /// false statement to half of the people reading it. Explaining what the
  /// camera is for, next to the button that asks, is the contextual request.
  String _title(AppLocalizations l10n) => switch (failure.reason) {
        CameraUnavailableReason.permissionDenied => l10n.scannerPermissionTitle,
        CameraUnavailableReason.permissionPermanentlyDenied =>
          l10n.scannerPermissionBlockedTitle,
        CameraUnavailableReason.noCamera => l10n.scannerNoCameraTitle,
        CameraUnavailableReason.initializationFailed =>
          l10n.scannerCameraFailedTitle,
      };

  String _body(AppLocalizations l10n) => switch (failure.reason) {
        CameraUnavailableReason.permissionDenied => l10n.scannerPermissionBody,
        CameraUnavailableReason.permissionPermanentlyDenied =>
          l10n.scannerPermissionBlockedBody,
        CameraUnavailableReason.noCamera => l10n.scannerNoCameraBody,
        CameraUnavailableReason.initializationFailed =>
          l10n.scannerCameraFailedBody,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // Settings for a permission only Settings can change; retry for anything
    // the user could plausibly have just fixed. `noCamera` gets neither —
    // offering a retry for absent hardware would be a lie with a button on it.
    final action = failure.needsSettings
        ? (
            key: const Key('scan-camera-open-settings'),
            label: l10n.scannerOpenSettings,
            onPressed: onOpenSettings,
          )
        : failure.isRetryable
            ? (
                key: const Key('scan-camera-retry'),
                label: failure.reason == CameraUnavailableReason.permissionDenied
                    ? l10n.scannerPermissionAllow
                    : l10n.scannerRetry,
                onPressed: onRetry,
              )
            : null;

    return Container(
      key: const Key('scan-camera-unavailable'),
      color: Colors.black.withValues(alpha: 0.65),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(colors: [
                    AppPalette.auroraViolet,
                    AppPalette.auroraBlue,
                  ]),
                ),
                child: Icon(_icon,
                    color: AppSemanticColors.onGradientInk, size: 36),
              ),
              const SizedBox(height: 14),
              Text(
                _title(l10n),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                _body(l10n),
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: 16),
                AppPrimaryButton(
                  key: action.key,
                  onPressed: busy ? null : () => unawaited(action.onPressed()),
                  loading: busy,
                  label: action.label,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Says out loud that recognising a machine sends the photo to Google.
///
/// It does: `GeminiVisualEquipmentService` puts the JPEG in a Firebase AI Logic
/// request, and the hybrid service tries the cloud FIRST, falling back to the
/// on-device model only when that fails. Until 2026-07-31 nothing on this
/// screen said so — while the form-check screen, one tab away, promised the
/// user "no frames are uploaded, your camera stays private". Two shipped
/// screens contradicting each other is not a nuance; in a gym the frame also
/// contains other people.
///
/// Modelled on `_PrivacyStrip` in `progress_photos_page.dart`, which is the
/// pattern this app already uses when it is being honest about where an image
/// goes.
class _ScanPrivacyStrip extends StatelessWidget {
  const _ScanPrivacyStrip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).scannerCloudDisclosure,
              key: const Key('scan-privacy-strip'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
