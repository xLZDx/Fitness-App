import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
import '../../core/debug/g3_step10b_probe.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../core/theme/hud_tokens.dart';
import '../../core/theme/hud_typography.dart';
import '../equipment/data/catalog_labels.dart';
import '../equipment/state/equipment_providers.dart';
import '../equipment/widgets/last_session_card.dart';
import '../safety/state/eligibility_providers.dart' show safetyContextProvider;
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/experimental_banner.dart';
import '../../shared/widgets/hud/hud_scaffold.dart';
import '../../shared/widgets/hud/hud_surface.dart';
import '../visual_equipment/data/live_recognition.dart';
import '../visual_equipment/data/scan_outcome.dart';
import '../visual_equipment/data/recognition_history.dart';
import '../visual_equipment/data/visual_equipment_match.dart';
import '../visual_equipment/data/machine_card.dart';
import '../visual_equipment/state/live_equipment_providers.dart';
import '../visual_equipment/state/machine_card_providers.dart';
import '../visual_equipment/state/recognition_history_providers.dart';
import '../visual_equipment/state/visual_equipment_providers.dart';
import '../visual_equipment/widgets/machine_card_view.dart';
import 'scan_evidence.dart';
import 'state/scan_match_providers.dart';
import 'state/scan_preview_provider.dart';
import 'widgets/scan_frame.dart';
import 'widgets/scan_glyph.dart';
import 'widgets/scan_match_card.dart';
import 'widgets/scan_viewfinder.dart';

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
///
/// ## SCAN-G1: the screen is the reference's Scan screen
///
/// `core/SCAN_G1_SCOPE.md`. The layout is `core/design/reference/
/// fitness_hud_v1/Fitness Glass Phone v1 - Sunset.dc.html:180-226` (and
/// `Light.dc.html`, same lines) reproduced element for element, and it is
/// held to that by a mechanical gate rather than by anyone's eye:
/// `tools/design/render_reference_scan.js` renders the reference itself to
/// `test/golden/reference/`, `scan_reference_geometry_test.dart` places every
/// element against the DOM anchors it extracts, and
/// `tools/design/scan_fidelity_check.py` diffs the app's pixels with the
/// reference's. Top to bottom: title and subtitle ([HudScreenTitle]), the
/// 230px viewfinder card ([ScanViewfinder]), the match card when a machine
/// is locked ([ScanMatchCard]), the one primary button ("Recognise" /
/// "Scan again"). Everything the reference does not model -- the gallery
/// path, the live labeler toggle, the disclosure, the AI coach entry,
/// history -- sits BELOW that button, where the reference has nothing, so
/// production capability is kept without the reference's own region ever
/// carrying an element the reference does not draw.
///
/// The full-bleed camera with a pull-up sheet that stood here before was a
/// legitimate production decision at the time; it is replaced because the
/// operator's instruction for this gate was that the screen look like the
/// reference, both states, so the Form Coach story (a screen "in the spirit
/// of" the reference, ten rounds of "no, like the picture") does not repeat.
class ScannerPage extends ConsumerStatefulWidget {
  const ScannerPage({super.key});

  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends ConsumerState<ScannerPage>
    with WidgetsBindingObserver {
  bool _handling = false;

  /// Distinguishes "you haven't tried yet" from "we looked and found nothing" —
  /// the two used to render the same hint card. Also what flips the primary
  /// button from "Recognise" to "Scan again".
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

  /// The viewfinder card, so a capture can read the size the user actually
  /// framed through (SCAN-G1, R7) instead of assuming the reference's 358px.
  final GlobalKey _viewfinderKey = GlobalKey(debugLabel: 'scan-viewfinder');

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
    } catch (e, stackTrace) {
      // Permission refused, refused for good, no camera at all, or a failed
      // init. Surfaced with its reason, because a viewfinder that never
      // appears with no explanation is the defect this page was reported for,
      // and one message for four causes only tells the user something is
      // wrong — not which of the four fixes is theirs.
      final failure = classifyCameraFailure(e);
      // Only `initializationFailed` is an operational incident. The other
      // three reasons are expected user/device states (permission refused,
      // refused for good, or no camera on the device) and reporting those to
      // Crashlytics would turn a normal permission denial into an alert.
      if (failure.reason == CameraUnavailableReason.initializationFailed) {
        // Same guard as main.dart's Crashlytics calls: telemetry must never
        // break the feature it instruments (and has no app to report against
        // at all in a plain `flutter test` run).
        try {
          // Branch at the call site -- see gemini_equipment_service.dart's
          // matching comment. G3_STEP10B_PROBE=false (every normal build)
          // must call FirebaseCrashlytics directly, with no
          // g3_step10b_probe.dart frame in between.
          if (G3Step10bProbe.kEnabled) {
            unawaited(
              G3Step10bProbe.recordError(
                e,
                stackTrace,
                fatal: false,
                reason: 'camera initialization failed',
              ),
            );
          } else {
            unawaited(
              FirebaseCrashlytics.instance.recordError(
                e,
                stackTrace,
                fatal: false,
                reason: 'camera initialization failed',
              ),
            );
          }
        } catch (_) {
          // Reporting failure is not itself reportable -- see above.
        }
      }
      if (!mounted) return;
      setState(() => _cameraFailure = failure);
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
    try {
      await _session?.stop();
    } catch (e) {
      debugPrint('camera session stop on disarm failed: $e');
    }
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

  /// The viewfinder card's rendered size right now, or the reference's own
  /// 358x230 if the card has not laid out (it always has by the time a
  /// button under it can be tapped; the fallback is for completeness).
  Size _viewfinderSize() {
    final RenderObject? box = _viewfinderKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.size;
    return const Size(358, ScanViewfinder.height);
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
      // cropped to the bracket window of the card they aimed through, mapped
      // back through the preview's cover fit (SCAN-G1, R3/R7). Gallery picks
      // are deliberately not cropped — the user composed those.
      final Size card = _viewfinderSize();
      final String cropped = await cropToViewfinder(
        shot.path,
        viewport: card,
        windowNormalized: ScanViewfinder.windowNormalized(card),
      );
      if (kScanEvidence) await saveScanEvidenceCrop(cropped);
      await _classify(cropped);
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
    // Same mistake this file's own dispose/route-change/lifecycle paths
    // guard against (see the class doc): a `ref.read` after an `await` can
    // run once the page's Element is unmounted (a genuine `dispose()` mid
    // classification -- logout, a full tree rebuild, shutdown), and would
    // throw there instead of just being a no-op.
    if (!mounted) return;
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

  /// "Scan again" (SCAN-G1, R4): back to the aiming state. The controller
  /// forgets its answer, the match card leaves, the hint returns to "align",
  /// and the button reads "Recognise" once more. The camera never stopped.
  void _scanAgain() {
    if (_handling) return;
    ref.read(visualEquipmentControllerProvider.notifier).reset();
    setState(() {
      _attempted = false;
      _lastScannedPath = null;
    });
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

  /// "Strength · Lats, Biceps": the catalogue's category for the machine,
  /// then the muscles its exercises are for, both localised. Either half may
  /// be missing (catalogue still loading, no exercises); the line is whatever
  /// is known, never a placeholder.
  String _matchSubtitle(AppLocalizations l10n, String equipmentId) {
    final String? category =
        (ref.watch(equipmentListProvider).valueOrNull ?? const [])
            .where((eq) => eq.id == equipmentId)
            .map((eq) => eq.category)
            .firstOrNull;
    final List<String> muscles =
        ref.watch(scanMatchMusclesProvider(equipmentId)).valueOrNull ??
            const <String>[];
    final List<String> parts = <String>[
      if (category != null && category.isNotEmpty)
        CatalogLabels.category(l10n, category),
      if (muscles.isNotEmpty)
        muscles.map((m) => CatalogLabels.muscle(l10n, m)).join(', '),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
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

    final ScanResult? result = scan.valueOrNull;
    // "Locked": one confident answer. Only that state gets the reference's
    // match card and the MACHINE LOCKED hint; `alternatives` is the app
    // saying it does not know which, and is listed below the button instead.
    final VisualMatch? locked = !scan.isLoading &&
            result != null &&
            result.outcome == ScanOutcome.confident &&
            result.matches.isNotEmpty
        ? result.matches.first
        : null;
    // The same honesty rule as `_MatchDetails`: only a printed-text
    // identification is captioned "read on the machine". Kept OUTSIDE
    // `ScanMatchCard` and rendered below the primary button, with the rest
    // of what the reference does not model -- the invariant is that the
    // canonical found surface is the match card ending at its CTA, then the
    // one button; a production-only string inside the card would grow it
    // past the reference on exactly the branch the fidelity gate's fixture
    // never exercises (SCAN-G1 review).
    final String? printedTextNote =
        locked != null && locked.source == MatchSource.printedText && locked.labelHint != null
            ? l10n.scannerReadOnMachine(locked.labelHint!.toUpperCase())
            : null;
    final bool scanned = _attempted && !scan.isLoading;
    final String hint = scan.isLoading
        ? l10n.scannerHintRecognising
        : locked != null
            ? l10n.scannerHintLocked
            : l10n.scannerHintAlign;

    // A transparent Material: the shell's Scaffold provides one in the app,
    // but this page is also pumped as a bare route, and the Material widgets
    // below the reference region (chips, expansion tiles, the Switch) assert
    // one. The `FrostedScaffold` this replaces used to be that ancestor.
    return Material(
      type: MaterialType.transparency,
      child: HudScreenBody(
      // The reference's screen starts at the status bar and its title block
      // carries the only top padding (`padding:6px 20px 14px`, line 182):
      // title at y=52 with a 46px inset. `HudScreenBody`'s own 6px would
      // double it.
      topPadding: 0,
      children: <Widget>[
        HudScreenTitle(
          l10n.scannerTitle,
          subtitle: l10n.scannerSubtitle,
          bottomPadding: 14,
          // Lines 183-184 declare no text-shadow; the cards below do.
          readabilityShadow: false,
          subtitleColor: t.brightness == Brightness.dark
              ? const Color(0xB8FFFFFF) // rgba(255,255,255,.72), line 184
              : const Color(0xC71B2030), // rgba(27,32,48,.78)
          // The handoff declares no tracking here; `HudType.body`'s shared
          // default is left alone for every other screen (R5), so Scan pins
          // its own subtitle instead.
          subtitleLetterSpacing: 0,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ScanViewfinder(
            key: _viewfinderKey,
            phase: scan.isLoading
                ? ScanFramePhase.analyzing
                : ScanFramePhase.ready,
            hint: hint,
            // No aiming frame over "camera access is blocked" — it would tell
            // the user to aim at something that is not there. Evidence mode
            // (R1) draws the bare preview so screenshots prove liveness.
            guides: _cameraFailure == null && !kScanEvidence,
            preview: _cameraFailure != null
                ? _CameraUnavailable(
                    failure: _cameraFailure!,
                    busy: _retrying,
                    onRetry: _retryCamera,
                    onOpenSettings: _openCameraSettings,
                  )
                : ref.watch(scanPreviewBuilderProvider)(session),
            // R2.2 state 9. Over the viewfinder, not instead of it: the
            // guidance is "add light", and a user who cannot see what the
            // camera sees cannot tell whether they followed it.
            banner: _cameraFailure == null
                ? ValueListenableBuilder<bool>(
                    valueListenable: session.isLowLight,
                    builder: (context, dark, _) => dark
                        ? _ViewfinderBanner(
                            key: const Key('scan-low-light'),
                            icon: Icons.light_mode_outlined,
                            text: l10n.scannerLowLight,
                          )
                        : const SizedBox.shrink(),
                  )
                : null,
            corner: kScanEvidence && _cameraFailure == null
                ? ScanEvidenceCounter(session: session)
                : null,
          ),
        ),
        if (locked != null) ...<Widget>[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ScanMatchCard(
              confidence: locked.confidence,
              name: equipmentDisplayName(ref, locked.equipmentId),
              subtitle: _matchSubtitle(l10n, locked.equipmentId),
              onOpen: () => unawaited(_openEquipment(locked.equipmentId)),
            ),
          ),
        ],
        // `margin:14px 16px 18px` -- the one primary button. Its key is the
        // one every scanner test has always driven; the shutter it replaces
        // carried the same key, so the tests' contract is unchanged.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          child: HudButton(
            key: const Key('scan-recognise-camera'),
            label: scanned ? l10n.scannerScanAgain : l10n.scannerRecognise,
            onPressed: scanned ? _scanAgain : _recogniseWithCamera,
            enabled: !scan.isLoading,
            glass: t.scanPrimaryButton,
            // See `HudSurface.shadowOutsideOnly`'s doc -- Scan opts in, the
            // panel-family default (every other button) does not.
            shadowOutsideOnly: true,
            radius: 24,
            padding: const EdgeInsets.all(16),
            // `font:700 14px` at line-height normal -- a 15px line box
            // (`scan_anchors.json` `primary_label`). Height set explicitly
            // because the Material ancestor's `DefaultTextStyle` would
            // otherwise lend the label its 1.43 body line-height, which is
            // where a 52px button quietly became 56; letter-spacing pinned
            // to 0 for the same reason `scan_match_card.dart`'s styles are --
            // the handoff declares none, `HudType.panelTitle`'s shared
            // default is left alone for every other button (R5).
            //
            // The light button (`Light.dc.html:221`) carries the light
            // panel's `text-shadow:0 1px 12px rgba(255,255,255,.9)`; the dark
            // one (`Sunset.dc.html:221`) declares none.
            labelStyle: t.brightness == Brightness.dark
                ? HudType.panelTitle(t)
                    .copyWith(height: 15 / 14, letterSpacing: 0)
                : HudType.panelTitle(t)
                    .copyWith(height: 15 / 14, letterSpacing: 0)
                    .overPhoto(t),
            centered: true,
            leading: ScanGlyph(
              codePoint: scanned
                  ? ScanGlyph.refresh
                  : ScanGlyph.centerFocusStrong,
              size: 20,
              color: t.textPrimary,
            ),
          ),
        ),
        // Everything the reference does not model, below its last element.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ScanControlsRow(
                onGallery: _recogniseFromGallery,
                live: liveOn,
                onLive: (on) =>
                    ref.read(liveModeEnabledProvider.notifier).state = on,
              ),
              const SizedBox(height: 10),
              // A1. The claim this qualifies is "that machine is a lat
              // pulldown", and this is where it is made. Right under the
              // answer and the button, still on the first screen.
              ExperimentalBanner(message: l10n.experimentalScanner),
              if (locked != null) ...<Widget>[
                // Level-1 equipment-type memory, right where the user just
                // identified the machine -- not inside the match card,
                // because a "last time here" fact and a "how sure the
                // classifier is" fact come from two different sources of
                // truth and must not read as one (and SCAN-G1 R4: the card
                // ends at its CTA). Same widget the equipment detail page
                // uses, unchanged: it hides itself for a confirmed
                // no-history and only ever shows real logged numbers.
                const SizedBox(height: 10),
                LastSessionCard(equipmentId: locked.equipmentId),
                // R2.8. Only for a confident answer: the coach needs ONE
                // subject, and `alternatives` is the app saying it does not
                // know which of them the user is standing at.
                const SizedBox(height: 10),
                _ScanAiCoachEntry(match: locked),
                if (printedTextNote != null) ...<Widget>[
                  const SizedBox(height: 10),
                  _ScanNote(
                    key: const Key('scan-match-note'),
                    icon: Icons.text_fields_rounded,
                    text: printedTextNote,
                  ),
                ],
              ],
              // R2.2 state 12. The hybrid recogniser falls back to the
              // on-device model "silently-but-logged" — the user got the
              // weaker answer and was never told why it was weaker.
              if (result != null && !scan.isLoading && result.answeredOffline)
                ...<Widget>[
                const SizedBox(height: 10),
                _ScanNote(
                  key: const Key('scan-offline-answer'),
                  icon: Icons.cloud_off_rounded,
                  text: l10n.scannerOfflineAnswer,
                ),
              ],
              const SizedBox(height: 10),
              scan.when(
                // The viewfinder already says RECOGNISING and pulses; a
                // second spinner here would compete with it.
                loading: () => const SizedBox.shrink(),
                // Kept for a state the controller no longer produces — it
                // now converts every failure into a ScanResult so the
                // outcome, not an exception, drives the screen. Left as a
                // safety net rather than a `!`: an unexpected AsyncError
                // must not blank the page.
                error: (e, _) => HudPanel(
                  tone: HudPanelTone.error,
                  child: Text(l10n.scannerRecognitionFailed(e)),
                ),
                data: (result) => switch (result.outcome) {
                  // The locked match is the card above; the runners-up are
                  // listed here so a wrong first guess is one tap from the
                  // right one.
                  ScanOutcome.confident => result.matches.length > 1
                      ? _Matches(
                          matches: result.matches.skip(1).toList(),
                          heading: l10n.scannerBestMatches,
                          onOpen: _openEquipment,
                        )
                      : const SizedBox.shrink(),
                  ScanOutcome.alternatives => _Matches(
                      matches: result.matches,
                      heading: l10n.scannerNotSureClosest,
                      onOpen: _openEquipment,
                    ),
                  // Not in the catalogue, but the describer could name it.
                  // That card IS the answer -- "не удалось понять" stops
                  // being true the moment the app can say what the machine
                  // is.
                  ScanOutcome.unknown => card != null
                      ? MachineCardView(card: card)
                      : _attempted
                          ? _HintCard(theme: theme, noMatch: true)
                          : const SizedBox.shrink(),
                  // Nothing machine-like in the frame. Distinct from unknown:
                  // telling someone pointing at a wall that their machine is
                  // missing from our catalogue is a lie about our data. Before
                  // any attempt this is the controller's initial state, and
                  // the subtitle under the title already says what to do.
                  ScanOutcome.noEquipment => _attempted
                      ? _HintCard(theme: theme, noMatch: true)
                      : const SizedBox.shrink(),
                  ScanOutcome.timeout => _ScanProblemCard(
                      key: const Key('scan-timeout'),
                      title: l10n.scannerTimeoutTitle,
                      body: l10n.scannerTimeoutBody,
                      busy: _handling,
                      onRetry: _retryLastScan,
                    ),
                  ScanOutcome.failed => _ScanProblemCard(
                      key: const Key('scan-failed'),
                      title: l10n.scannerFailedTitle,
                      body: l10n.scannerFailedBody,
                      busy: _handling,
                      onRetry: _retryLastScan,
                    ),
                },
              ),
              // Also gated on `_cameraFailure == null`, the same condition the
              // viewfinder itself branches on: without it, denying camera
              // permission left this card showing regardless, its `_LiveCard`
              // spinner stuck on "Ищем..." forever -- no frames were ever
              // going to arrive to settle it, and nothing on screen said why.
              if (liveOn && _cameraFailure == null) ...<Widget>[
                const SizedBox(height: 10),
                _LiveSection(onOpen: _openEquipment),
              ],
              const SizedBox(height: 10),
              const _ScanPrivacyStrip(),
              const SizedBox(height: 20),
              _HistorySection(onOpen: _openEquipment),
              const _PreparingSection(),
            ],
          ),
        ),
      ],
      ),
    );
  }
}

/// The production controls under the reference's button: the gallery path
/// and the live-labeler toggle, in one row.
///
/// Public so its layout can be pumped at a given width and locale without a
/// camera: the strip this replaces overflowed by 12px in Russian on a real
/// device while every host test rendered it in English
/// (`scan_strip_overflow_test.dart`). Both keys are the ones every scanner
/// test drives (`scan-recognise-gallery`, `scan-live-toggle`).
class ScanControlsRow extends StatelessWidget {
  const ScanControlsRow({
    super.key,
    required this.onGallery,
    required this.live,
    required this.onLive,
  });

  final VoidCallback onGallery;
  final bool live;
  final ValueChanged<bool> onLive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    return Row(
      children: <Widget>[
        // The gallery button shrinks (its label ellipsises); the toggle keeps
        // its intrinsic size, because an ellipsised label is still readable
        // and a squeezed Switch is not reliably tappable.
        Expanded(
          child: HudButton(
            key: const Key('scan-recognise-gallery'),
            label: l10n.scannerFromGallery,
            onPressed: onGallery,
            centered: true,
            leading: ScanGlyph(
              codePoint: ScanGlyph.photoLibrary,
              size: 20,
              color: t.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        HudPanel(
          radius: HudTokens.radiusButton,
          padding: const EdgeInsets.fromLTRB(14, 2, 4, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Gates the labeler, not the camera.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  l10n.scannerLive,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: HudType.rowTitle(t),
                ),
              ),
              // `Switch` asserts a `Material` ancestor. The shell's Scaffold
              // is one in the app; a bare route in a test is not, and the
              // HUD surfaces this row sits on are not Material either.
              Material(
                type: MaterialType.transparency,
                child: Switch(
                  key: const Key('scan-live-toggle'),
                  value: live,
                  onChanged: onLive,
                ),
              ),
            ],
          ),
        ),
      ],
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
    return HudPanel(
      key: Key('scan-preparing-${card.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Theme(
        // The default divider draws a line through a glass panel.
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
    return HudPanel(
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

/// Live-mode readout. What the camera has settled on, how much of the vote
/// agreed, and a way straight into the exercises.
class _LiveCard extends ConsumerWidget {
  const _LiveCard({required this.recognition, required this.onOpen});
  final LiveRecognition? recognition;
  final Future<void> Function(String equipmentId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final r = recognition;
    if (r == null) {
      return HudPanel(
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
      return HudPanel(
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
    return HudPanel(
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

/// A headed list of plain match rows: the runners-up under a locked match,
/// or every candidate of an undecided (`alternatives`) result.
///
/// No hero here any more: the confident top match is the reference's match
/// card ([ScanMatchCard]), drawn by the page above the primary button.
class _Matches extends ConsumerWidget {
  const _Matches({
    required this.matches,
    required this.heading,
    required this.onOpen,
  });

  /// Routed through the page so navigation is uniform; the route listener is
  /// what releases the camera.
  final Future<void> Function(String equipmentId) onOpen;
  final List<VisualMatch> matches;
  final String heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        for (final m in matches) ...[
          HudPanel(
            onTap: () => onOpen(m.equipmentId),
            child: Row(
              children: [
                Expanded(
                  child: _MatchDetails(
                    match: m,
                    name: equipmentDisplayName(ref, m.equipmentId),
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

/// The name/confidence/printed-text-hint column of a plain match row -- one
/// place, so the honesty rule on [VisualMatch.labelHint] (only captioned
/// "read on the machine" for [MatchSource.printedText]) cannot drift.
class _MatchDetails extends StatelessWidget {
  const _MatchDetails({required this.match, required this.name});

  final VisualMatch match;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(
          AppLocalizations.of(context)
              .scannerConfidence((match.confidence * 100).toStringAsFixed(0)),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colors.textSecondary),
        ),
        if (match.source == MatchSource.printedText && match.labelHint != null)
          Text(
            AppLocalizations.of(context)
                .scannerReadOnMachine(match.labelHint!.toUpperCase()),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
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
    final liveAsync = ref.watch(liveRecognitionProvider);
    // An error here means the model or the labeler failed, which is NOT the
    // same as "no machine recognised yet" — spinning forever on a broken
    // model was a real defect.
    if (liveAsync.hasError) {
      return HudPanel(
        key: const Key('scan-live-error'),
        tone: HudPanelTone.error,
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

    return HudPanel(
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
    return HudPanel(
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
    return HudPanel(
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

/// The camera-off state, inside the viewfinder card, with the reason and the
/// action that fixes it.
///
/// R2.9. The previous version took a raw `Object error`, printed one title for
/// every cause, and interpolated the exception into the body — which is both
/// the "never show internal exceptions" prohibition and, for a user who had
/// simply refused the permission, no path back: there was no button at all.
///
/// SCAN-G1: it now fills the 230px card rather than the whole screen, so the
/// rest of the reference layout (title, button, the gallery path that still
/// works without a camera) stays where the reference puts it.
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
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
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

    // The dark token set explicitly: this is drawn where the camera would
    // be, and the camera is dark whatever theme the app is in.
    final AppSemanticColors dark = AppSemanticColors.dark;
    return ColoredBox(
      key: const Key('scan-camera-unavailable'),
      color: dark.cameraOverlay,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon, color: dark.textPrimary, size: 28),
                const SizedBox(height: 8),
                Text(
                  _title(l10n),
                  textAlign: TextAlign.center,
                  style: HudType.panelTitle(t).copyWith(color: dark.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  _body(l10n),
                  style: HudType.body(t, size: 11.5)
                      .copyWith(color: dark.textSecondary),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (action != null) ...[
                  const SizedBox(height: 10),
                  HudButton(
                    key: action.key,
                    label: action.label,
                    onPressed: busy ? null : () => unawaited(action.onPressed()),
                    enabled: !busy,
                    centered: true,
                    padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                    foreground: dark.textPrimary,
                  ),
                ],
              ],
            ),
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
    return HudPanel(
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
