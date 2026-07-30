import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/camera/camera_session.dart';
import '../../core/camera/centre_crop.dart';
import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../visual_equipment/data/live_recognition.dart';
import '../visual_equipment/data/recognition_history.dart';
import '../visual_equipment/data/visual_equipment_match.dart';
import '../visual_equipment/state/live_equipment_providers.dart';
import '../visual_equipment/state/recognition_history_providers.dart';
import '../visual_equipment/state/visual_equipment_providers.dart';
import '../visual_equipment/widgets/live_equipment_preview.dart';

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

  /// Set when the camera could not be opened at all, so the page can say so
  /// instead of showing a placeholder forever.
  Object? _cameraError;

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
  Future<void> _arm() async {
    if (!mounted) return;
    // `??=` on a nullable field yields a nullable static type even though the
    // provider cannot return null, hence the separate non-null read.
    _session ??= ref.read(scanCameraSessionProvider);
    _liveMode ??= ref.read(liveModeEnabledProvider.notifier);
    final session = _session!;
    try {
      await session.start();
      if (!mounted) return;
      if (_cameraError != null) setState(() => _cameraError = null);
    } catch (e) {
      // Permission denied, camera busy, no camera at all. Surfaced, because a
      // viewfinder that never appears with no explanation is the defect this
      // page was reported for.
      if (!mounted) return;
      setState(() => _cameraError = e);
    }
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

  Future<void> _classify(String path) async {
    if (mounted) setState(() => _attempted = true);
    await ref
        .read(visualEquipmentControllerProvider.notifier)
        .classifyFilePath(path);
    final top =
        ref.read(visualEquipmentControllerProvider).valueOrNull?.firstOrNull;
    if (top != null) {
      _remember(top.equipmentId, top.confidence, RecognitionSource.photo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches = ref.watch(visualEquipmentControllerProvider);
    final liveOn = ref.watch(liveModeEnabledProvider);
    final liveAsync = ref.watch(liveRecognitionProvider);
    final live = liveAsync.valueOrNull;
    final session = ref.watch(scanCameraSessionProvider);
    // Record settled live readings. The repository's 5-minute dedup keeps a
    // camera held on one machine from writing a row per frame.
    ref.listen<AsyncValue<LiveRecognition?>>(liveRecognitionProvider,
        (prev, next) {
      final r = next.valueOrNull;
      // Tentative readings are feedback for the user, not evidence — only a
      // settled vote is worth remembering.
      if (r == null || !r.settled) return;
      _remember(r.equipmentId, r.confidence, RecognitionSource.live);
    });
    return FrostedScaffold(
      appBar: GlassAppBar(
        title: AppLocalizations.of(context).scannerScan,
        actions: [
          // Gates the labeler, not the camera.
          Row(
            children: [
              Text(AppLocalizations.of(context).scannerLive,
                  style: theme.textTheme.labelLarge),
              Switch(
                key: const Key('scan-live-toggle'),
                value: liveOn,
                onChanged: (on) =>
                    ref.read(liveModeEnabledProvider.notifier).state = on,
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 88, 20, 110),
          children: [
            // Full width, 3:4 — the old fixed 300px strip with a 220x200
            // frame could not fit a machine standing two steps away
            // (operator point 4). The guide frame is proportional and mirrors
            // the 75% centre crop the classifier actually receives.
            AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_cameraError != null)
                      _CameraUnavailable(error: _cameraError!)
                    else
                      LiveEquipmentPreview(session: session),
                    Center(
                      child: FractionallySizedBox(
                        widthFactor: 0.75,
                        heightFactor: 0.75,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('scan-recognise-camera'),
                    onPressed: _recogniseWithCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(
                        AppLocalizations.of(context).scannerRecogniseMachine),
                  ),
                ),
                const SizedBox(width: 8),
                // The app theme gives buttons minimumSize Size.fromHeight(54),
                // i.e. minWidth == infinity. In a Row's non-flex slot the width
                // constraint is unbounded, so an unwrapped button forces an
                // infinite width and the whole page fails to lay out (blank
                // screen, no red error). Always bound button width outside
                // Expanded.
                SizedBox(
                  width: 56,
                  child: OutlinedButton(
                    key: const Key('scan-recognise-gallery'),
                    onPressed: _recogniseFromGallery,
                    child: const Icon(Icons.photo_library_outlined),
                  ),
                ),
              ],
            ),
            if (liveOn) ...[
              const SizedBox(height: 14),
              // An error here means the model or the labeler failed, which is
              // NOT the same as "no machine recognised yet" — spinning forever
              // on a broken model was a real defect.
              liveAsync.hasError
                  ? GlassCard(
                      key: const Key('scan-live-error'),
                      tint: theme.colorScheme.error,
                      child: Text(AppLocalizations.of(context)
                          .scannerLiveRecognitionFailed(
                              liveAsync.error ?? '')),
                    )
                  : _LiveCard(recognition: live, onOpen: _openEquipment),
            ],
            const SizedBox(height: 14),
            matches.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => GlassCard(
                tint: theme.colorScheme.error,
                child:
                    Text(AppLocalizations.of(context).scannerRecognitionFailed(e)),
              ),
              data: (list) => list.isEmpty
                  ? _HintCard(theme: theme, noMatch: _attempted)
                  : _Matches(matches: list, onOpen: _openEquipment),
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
            noMatch ? l.scannerCouldnTTellWhatThatIs : l.scannerPointAtAMachineAndTapRecognise,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            noMatch
                ? l.scannerTryFillingTheFrameWithOne
                : l.scannerWeIdentifyTheEquipmentOnDevice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

/// Live-mode readout. What the camera has settled on, how much of the vote
/// agreed, and a way straight into the exercises.
class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.recognition, required this.onOpen});
  final LiveRecognition? recognition;
  final Future<void> Function(String equipmentId) onOpen;

  @override
  Widget build(BuildContext context) {
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
                        r.equipmentId.replaceAll('_', ' '),
                        (r.confidence * 100).toStringAsFixed(0)),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    AppLocalizations.of(context).scannerKeepAiming,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.65),
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
                  r.equipmentId.replaceAll('_', ' '),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  AppLocalizations.of(context).scannerOfFramesAgree(
                      (r.confidence * 100).toStringAsFixed(0),
                      (r.agreement * 100).toStringAsFixed(0)),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
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

class _Matches extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unsure =
        matches.isEmpty || matches.first.confidence < _unsureBelow;
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
                        m.equipmentId.replaceAll('_', ' '),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        AppLocalizations.of(context).scannerConfidence(
                            (m.confidence * 100).toStringAsFixed(0)),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.65),
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

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black.withValues(alpha: 0.65),
      padding: const EdgeInsets.all(24),
      child: Center(
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
              child: const Icon(Icons.camera_alt_outlined,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.of(context).scannerCameraUnavailable,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context)
                  .scannerYouCanStillPickAPhoto(error),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
