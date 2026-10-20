/// The body scan flow page (route `/body-scan`). It renders the pure flow state
/// (`ScanFlowController`) and dispatches user events; effects (weight write,
/// save, upload, estimate) are executed by the job runner, which reports back
/// through the same controller. Capture and review reuse the existing guided
/// capture route.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/body_scan_flags.dart';
import '../progress_photos/scan/scan_access.dart';
import '../progress_photos/scan/ui/scan_gate_view.dart';
import 'data/body_scan_flow_machine.dart';
import 'data/scan_plan_context.dart';
import 'state/body_scan_flow_driver.dart';
import 'state/body_scan_providers.dart';
import 'state/body_scan_settings.dart';
import 'state/scan_flow_controller.dart';
import 'state/scan_plan_context_provider.dart';
import 'widgets/analysis_progress_view.dart';
import 'widgets/cloud_consent_sheet.dart';
import 'widgets/intro_view.dart';
import 'widgets/resume_scan_card.dart';
import 'widgets/weight_prompt_sheet.dart';

/// Id of the scan being processed; set by the job runner when the record is
/// saved, read here to open the result.
final bodyScanActiveScanIdProvider = StateProvider<String?>((_) => null);

/// Maps a flow stage to the progress stage shown to the user.
AnalysisStage analysisStageFor(FlowStage s) => switch (s) {
      FlowStage.savingLocal ||
      FlowStage.queued ||
      FlowStage.uploading =>
        AnalysisStage.photos,
      FlowStage.analysing => AnalysisStage.composition,
      FlowStage.verifying => AnalysisStage.plausibility,
      FlowStage.done => AnalysisStage.saved,
      _ => AnalysisStage.photos,
    };

class BodyScanFlowPage extends ConsumerStatefulWidget {
  const BodyScanFlowPage({super.key});

  @override
  ConsumerState<BodyScanFlowPage> createState() => _BodyScanFlowPageState();
}

class _BodyScanFlowPageState extends ConsumerState<BodyScanFlowPage> {
  DateTime _startedAt = DateTime.now();
  bool _promptOpen = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final c = ref.read(scanFlowControllerProvider.notifier);
      if (ref.read(scanFlowControllerProvider).state.stage == FlowStage.idle) {
        c.dispatch(const FlowEvent(FlowEventKind.open));
      }
    });
  }

  Future<void> _promptWeight() async {
    if (_promptOpen) return;
    _promptOpen = true;
    final days = ref
        .read(scanFlowControllerProvider)
        .context
        .latestWeightAge
        ?.inDays;
    final r = await WeightPromptSheet.show(context, staleDays: days);
    _promptOpen = false;
    if (!mounted) return;
    final c = ref.read(scanFlowControllerProvider.notifier);
    if (r == null || r.skipped) {
      c.dispatch(const FlowEvent(FlowEventKind.skipWeight));
    } else {
      c.dispatch(const FlowEvent(FlowEventKind.weightLogged));
    }
  }

  /// The separate cloud-upload consent (D-5): only when this build uploads
  /// photos (BODY_SCAN_CLOUD) and the stored consent does not cover the current
  /// text. A refusal keeps the scan on the device (provisional estimate).
  Future<void> _askCloudConsent() async {
    if (!ref.read(bodyScanFlagsProvider).cloudPhotos) return;
    final settings =
        ref.read(bodyScanSettingsProvider).valueOrNull ?? const BodyScanSettings();
    if (settings.hasCurrentConsent) return;
    final store = ref.read(bodyScanSettingsStoreProvider);
    final agreed = await CloudConsentSheet.show(context);
    if (!agreed) return;
    try {
      await store.acceptCloudConsent(kBodyScanCloudConsentVersion);
    } catch (_) {
      // Not recorded: the scan stays on the device.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final access = ref.watch(scanAccessProvider);
    final plan = ref.watch(scanPlanContextValueProvider);
    final snap = ref.watch(scanFlowControllerProvider);
    // Executes the machine's effects through the job runner (C14).
    final driver = ref.watch(bodyScanFlowDriverProvider);
    final ctl = ref.read(scanFlowControllerProvider.notifier);
    final stage = snap.state.stage;

    ref.listen(scanFlowControllerProvider, (prev, next) {
      final s = next.state.stage;
      if (prev?.state.stage != s) _startedAt = DateTime.now();
      if (s == FlowStage.weightPrompt) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _promptWeight());
      } else if (s == FlowStage.capturing && prev?.state.stage != s) {
        // The capture screen saves the scan and pops with its id.
        GoRouter.of(context)
            .push<String>('/photos/scan')
            .then(driver.captureReturned);
      } else if (s == FlowStage.done) {
        final id = ref.read(bodyScanActiveScanIdProvider);
        if (id != null) GoRouter.of(context).go('/body-scan/result/$id');
      } else if (s == FlowStage.cancelled) {
        if (GoRouter.of(context).canPop()) GoRouter.of(context).pop();
      }
    });

    Widget body;
    if (access != ScanAccess.allowed) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: Text(scanAccessMessage(l10n, access))),
      );
    } else {
      body = switch (stage) {
        FlowStage.idle ||
        FlowStage.intro ||
        FlowStage.weightPrompt ||
        FlowStage.capturing ||
        FlowStage.reviewing =>
          IntroView(
            provisional: snap.context.localOnly,
            measurementOnly:
                plan.surfaceMode == ScanSurfaceMode.measurementOnly,
            onStart: () async {
              await _askCloudConsent();
              if (!mounted) return;
              ctl.dispatch(const FlowEvent(FlowEventKind.start));
            },
            onClose: () {
              if (GoRouter.of(context).canPop()) GoRouter.of(context).pop();
            },
          ),
        FlowStage.failed => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ResumeScanCard.failed(
                onRetry: () => ctl.dispatch(const FlowEvent(FlowEventKind.retry)),
                onKeep: () {
                  if (GoRouter.of(context).canPop()) GoRouter.of(context).pop();
                },
                onDelete: () {
                  driver.deleteFailedScan();
                  if (GoRouter.of(context).canPop()) GoRouter.of(context).pop();
                },
              ),
            ],
          ),
        _ => AnalysisProgressView(
            key: ValueKey(stage),
            stage: analysisStageFor(stage),
            startedAt: _startedAt,
            photosKeptLocal: snap.context.localOnly,
            onCancel: () => ctl.dispatch(const FlowEvent(FlowEventKind.cancel)),
            onRetry: () => ctl.dispatch(const FlowEvent(FlowEventKind.retry)),
          ),
      };
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.bodyScanTitle)),
      body: SafeArea(child: body),
    );
  }
}
