import 'dart:async' show TimeoutException;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/experimental_banner.dart';
import '../../shared/widgets/glass.dart';
import '../form_check/data/mlkit_pose_detector_service.dart';
import '../form_check/data/pose_detector_service.dart';
import '../form_check/state/form_check_providers.dart'
    show poseDetectorServiceProvider, poseErrorProvider;
import '../form_check/widgets/camera_flip_button.dart';
import 'data/measured_posture_config.dart';
import 'state/posture_providers.dart';

/// Static-stand posture check. Unlike [FormCheckPage] there is no
/// repetition to count and no target silhouette to match -- the user stands
/// still for one fixed window (see [postureCaptureDurationProvider]) and the
/// screen reports how that stand compared to the measured ranges in
/// `measured_posture_config.dart`.
class PosturePage extends ConsumerStatefulWidget {
  const PosturePage({super.key});

  @override
  ConsumerState<PosturePage> createState() => _PosturePageState();
}

class _PosturePageState extends ConsumerState<PosturePage>
    with WidgetsBindingObserver {
  bool _started = false;
  Object? _startError;

  /// Same bound as `FormCheckPage`, and the same reason: a hung native start
  /// call must not spin a spinner forever.
  static const _startTimeout = Duration(seconds: 15);

  int _lifecycle = 0;
  Future<void>? _stopping;
  PoseDetectorService? _service;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cleared on a fresh mount only, same as `RepSessionController.resetSet`
    // in Form Check: the session outlives the page, so a lifecycle resume
    // (background/foreground) must not wipe a result the user just saw.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(postureSessionControllerProvider.notifier).reset();
    });
    _startDetector(requestPermission: true);
  }

  void _startDetector({bool requestPermission = false}) {
    final token = ++_lifecycle;
    _started = false;
    _startError = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final stopping = _stopping;
        if (stopping != null) {
          await stopping;
          _stopping = null;
        }
        if (!mounted || token != _lifecycle) return;

        final svc = ref.read(poseDetectorServiceProvider);
        _service = svc;
        if (requestPermission) {
          await svc.ensurePermission();
          if (!mounted || token != _lifecycle) return;
        }
        await svc.start().timeout(_startTimeout);
        if (!mounted || token != _lifecycle) return;
        setState(() {
          _started = true;
          _startError = null;
        });
      } catch (e) {
        if (!mounted || token != _lifecycle) return;
        setState(() => _startError = e);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final PoseDetectorService svc =
          _service ?? ref.read(poseDetectorServiceProvider);
      _service = svc;
      _lifecycle++;
      _stopping = svc.stop();
      if (mounted) setState(() => _started = false);
    } else if (state == AppLifecycleState.resumed && mounted && !_started) {
      _startDetector();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // `ref` may not be touched here -- by the time dispose() runs the
    // ConsumerStatefulElement itself is already unmounting, and reading a
    // provider throws "Cannot use ref after the widget was disposed" (found
    // by the widget test, not by inspection). `_service` is a plain field
    // captured at first use for exactly this reason; the session reset
    // moved to the next mount's postFrameCallback instead.
    _service?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final svc = ref.watch(poseDetectorServiceProvider);
    final session = ref.watch(postureSessionControllerProvider);
    final failure = _startError ?? ref.watch(poseErrorProvider);

    return FrostedScaffold(
      appBar: GlassAppBar(
        title: l10n.postureTitle,
        // The screen this control was asked for. Every posture number is a
        // line through the WHOLE body -- shoulder tilt, pelvis tilt, the head
        // over the shoulders -- and the front camera at arm's length frames a
        // torso. A mirror plus the back lens is how the user gets far enough
        // away and still reads the result.
        actions: [CameraFlipButton(svc: svc)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          // A1. Above the intro, not folded into it: `ML_STRATEGY` puts posture
          // closest to medical advice of anything in the product
          // (`ML_STRATEGY_2026-08-11.md:203-209`), and a qualification a reader
          // has to find inside a paragraph of description is one they can miss.
          ExperimentalBanner(message: l10n.experimentalPosture),
          GlassCard(
            child: Text(
              l10n.postureIntro,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                color: Colors.black.withValues(alpha: 0.85),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (failure != null)
                      Center(
                        child: _StartFailure(
                          failure: failure,
                          onRetry: () =>
                              _startDetector(requestPermission: true),
                        ),
                      )
                    else if (!_started)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    else
                      _CameraPreview(svc: svc),
                    if (failure == null && _started)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _CaptureBand(session: session),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: switch (session.phase) {
              PostureCapturePhase.capturing => const SizedBox(
                  height: 44,
                  child: Center(child: CircularProgressIndicator()),
                ),
              _ => AppPrimaryButton(
                  key: const Key('posture.start'),
                  onPressed: (failure == null && _started)
                      ? () => ref
                          .read(postureSessionControllerProvider.notifier)
                          .start()
                      : null,
                  label: session.phase == PostureCapturePhase.done
                      ? l10n.postureCheckAgain
                      : l10n.postureStart,
                ),
            },
          ),
          if (session.phase == PostureCapturePhase.done &&
              session.result != null) ...[
            const SizedBox(height: 16),
            _ResultSection(result: session.result!),
          ],
          const SizedBox(height: 16),
          GlassCard(
            child: Text(
              l10n.postureDisclaimer,
              key: const Key('posture.disclaimer'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreview extends StatelessWidget {
  const _CameraPreview({required this.svc});
  final PoseDetectorService svc;

  @override
  Widget build(BuildContext context) {
    final svc = this.svc;
    if (svc is! MlKitPoseDetectorService) {
      return const Center(
        child: Icon(Icons.videocam_outlined, color: Colors.white24, size: 80),
      );
    }
    return ValueListenableBuilder<CameraController?>(
      valueListenable: svc.session.surface,
      builder: (context, ctl, _) {
        if (ctl == null) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
        return ValueListenableBuilder<CameraValue>(
          valueListenable: ctl,
          builder: (context, value, __) => value.isInitialized
              ? CameraPreview(ctl)
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
        );
      },
    );
  }
}

class _StartFailure extends StatelessWidget {
  const _StartFailure({required this.failure, required this.onRetry});
  final Object failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final timedOut = failure is TimeoutException;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timedOut
                ? l10n.formcheckCameraTimedOut
                : l10n.formcheckCameraUnavailable,
            key: const Key('posture.error'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          AppTertiaryButton(
            key: const Key('posture.retry'),
            onPressed: onRetry,
            label: l10n.formcheckTryAgain,
          ),
        ],
      ),
    );
  }
}

/// Over the camera during capture: a plain "hold still" band, the same slot
/// `_CueCard` occupies on the Form Check screen.
class _CaptureBand extends StatelessWidget {
  const _CaptureBand({required this.session});
  final PostureSessionState session;

  @override
  Widget build(BuildContext context) {
    if (session.phase != PostureCapturePhase.capturing) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        AppLocalizations.of(context).postureCapturing,
        key: const Key('posture.capturing'),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.result});
  final PostureResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (result.isEmpty) {
      return GlassCard(
        child: Text(
          l10n.postureNoBodyDetected,
          key: const Key('posture.no_body'),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: Theme.of(context).colors.textSecondary),
        ),
      );
    }
    return Column(
      children: [
        _MetricCard(
          keyName: 'shoulder_asymmetry',
          label: l10n.postureShoulderAsymmetry,
          metric: result.shoulderAsymmetry,
        ),
        const SizedBox(height: 12),
        _MetricCard(
          keyName: 'pelvis_tilt',
          label: l10n.posturePelvisTilt,
          metric: result.pelvisTilt,
        ),
        const SizedBox(height: 12),
        _MetricCard(
          keyName: 'forward_head',
          label: l10n.postureForwardHead,
          metric: result.forwardHead,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.keyName,
    required this.label,
    required this.metric,
  });

  final String keyName;
  final String label;
  final PostureMetricResult? metric;

  Color _verdictColor(PostureVerdict v) => switch (v) {
        PostureVerdict.typical => AppPalette.auroraTeal,
        PostureVerdict.mild => AppPalette.auroraPeach,
        PostureVerdict.notable => AppPalette.auroraPink,
      };

  String _verdictLabel(AppLocalizations l10n, PostureVerdict v) => switch (v) {
        PostureVerdict.typical => l10n.postureVerdictTypical,
        PostureVerdict.mild => l10n.postureVerdictMild,
        PostureVerdict.notable => l10n.postureVerdictNotable,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final m = metric;
    return GlassCard(
      key: Key('posture.metric.$keyName'),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (m == null)
            Text(
              l10n.postureMetricUnavailable,
              key: Key('posture.metric.$keyName.unavailable'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colors.textSecondary),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _verdictColor(m.verdict).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _verdictLabel(l10n, m.verdict),
                key: Key('posture.metric.$keyName.verdict'),
                style: const TextStyle(
                  color: AppSemanticColors.onGradientInk,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
