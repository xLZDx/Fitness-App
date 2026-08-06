import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/camera/camera_session.dart';
import '../../core/camera/centre_crop.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../equipment/state/equipment_providers.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/glass.dart';
import '../visual_equipment/data/live_recognition.dart';
import '../visual_equipment/data/recognition_history.dart';
import '../visual_equipment/data/visual_equipment_match.dart';
import '../visual_equipment/data/machine_card.dart';
import '../visual_equipment/state/live_equipment_providers.dart';
import '../visual_equipment/state/machine_card_providers.dart';
import '../visual_equipment/state/recognition_history_providers.dart';
import '../visual_equipment/state/visual_equipment_providers.dart';
import '../visual_equipment/widgets/live_equipment_preview.dart';
import '../visual_equipment/widgets/machine_card_view.dart';

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
    final card = ref.watch(lastMachineCardProvider);
    final liveOn = ref.watch(liveModeEnabledProvider);
    final liveAsync = ref.watch(liveRecognitionProvider);
    final live = liveAsync.valueOrNull;
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
      // No SafeArea. `FrostedScaffold` sets `extendBodyBehindAppBar`, so the
      // list already starts at y=0 and the 92 below clears the bar exactly as
      // it does on every other page. Wrapping it in a SafeArea counted the
      // status bar a second time, which is the empty band the operator circled
      // — about 128 logical points of nothing between the title and the
      // viewfinder.
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 92, 12, 110),
        children: [
          // As tall as the screen allows. Recognition is aiming, and aiming is
          // the whole screen's job — operator: "камера была почти во весь
          // экран". The guide frame is proportional and mirrors the 75% centre
          // crop the classifier actually receives.
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.68,
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
          const _ScanPrivacyStrip(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppPrimaryButton(
                  key: const Key('scan-recognise-camera'),
                  onPressed: _recogniseWithCamera,
                  icon: Icons.photo_camera_outlined,
                  label: AppLocalizations.of(context).scannerRecogniseMachine,
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
                        .scannerLiveRecognitionFailed(liveAsync.error ?? '')),
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
              child: Text(
                  AppLocalizations.of(context).scannerRecognitionFailed(e)),
            ),
            data: (list) => list.isEmpty
                // Not in the catalog. If the second question came back with
                // something, that IS the answer -- "не удалось понять" is no
                // longer true once we can say what the machine is.
                ? (card != null
                    ? MachineCardView(card: card)
                    : _HintCard(theme: theme, noMatch: _attempted))
                : _Matches(matches: list, onOpen: _openEquipment),
          ),
          const SizedBox(height: 20),
          _HistorySection(onOpen: _openEquipment),
          const _PreparingSection(),
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
    if (entries == null || entries.isEmpty) return const SizedBox.shrink();

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
                        m.equipmentId.replaceAll('_', ' '),
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
                  color: AppSemanticColors.onGradientInk, size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              AppLocalizations.of(context).scannerCameraUnavailable,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context).scannerYouCanStillPickAPhoto(error),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
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
