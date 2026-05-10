import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'state/form_check_providers.dart';

/// Live form-check page. Shows the camera preview placeholder + a
/// floating "cue card" that updates from the active rule classifiers.
///
/// Marketing line per the assessment: "form feedback on commodity
/// Android — no $2,500 hardware required."
class FormCheckPage extends ConsumerWidget {
  const FormCheckPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tier = ref.watch(effectiveTierProvider);
    final isPremium = tier == SubscriptionTier.celebrityTrainer;
    final feedback = ref.watch(formFeedbackControllerProvider);

    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Form coach'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          if (!isPremium) ...[
            _UpgradeCard(),
            const SizedBox(height: 16),
          ],
          AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Container(
                color: Colors.black.withValues(alpha: 0.85),
                child: Stack(
                  children: [
                    const Center(
                      child: Icon(Icons.videocam_outlined,
                          color: Colors.white24, size: 80),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _CueCard(feedback: feedback),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          GlassCard(
            child: Text(
              'Form coach runs on-device using MediaPipe pose detection. '
              'No frames are uploaded — your camera stays private.',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      onTap: () => GoRouter.of(context).go('/subscription'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Form coach is a Sustainer benefit',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            r'Free of $2,500 hardware. Works on your phone — no '
            'depth-camera required.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _CueCard extends StatelessWidget {
  const _CueCard({this.feedback});
  final dynamic feedback; // FormFeedback?

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (feedback == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          'Stand back so your full body fits in the frame.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    final severity = feedback.severity as int;
    final colour = severity >= 2
        ? AppPalette.auroraPink
        : severity == 1
            ? AppPalette.auroraPeach
            : AppPalette.auroraTeal;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        feedback.cue as String,
        style: theme.textTheme.titleSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
