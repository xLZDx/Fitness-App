import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/glass.dart';
import '../auth/state/auth_providers.dart';
import 'data/community_video.dart';
import 'state/catalog_providers.dart';

/// Moderator-only page. Lists pending community-video submissions and
/// lets a moderator approve / reject. Server-side rules enforce the
/// moderator-claim check; client UI is just the operator console.
class CatalogModerationPage extends ConsumerWidget {
  const CatalogModerationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pending = ref.watch(pendingSubmissionsProvider);
    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).catalogModerationQueue),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(AppLocalizations.of(context).catalogError(e))),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  AppLocalizations.of(context).catalogNothingToModerateGreatWork,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
            children: [
              for (final v in list) ...[
                _SubmissionCard(video: v),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SubmissionCard extends ConsumerWidget {
  const _SubmissionCard({required this.video});
  final CommunityVideo video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppLocalizations.of(context).catalogExercise(video.exerciseId),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          SelectableText(
            video.url,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 6),
          Text(
            AppLocalizations.of(context).catalogBy(video.contributorDisplay),
            style: theme.textTheme.labelSmall,
          ),
          if (video.notes != null) ...[
            const SizedBox(height: 6),
            Text(AppLocalizations.of(context).catalogNote(video.notes!)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: AppSecondaryButton(
                  onPressed: () async {
                    final me = ref.read(authUserProvider).valueOrNull;
                    if (me == null) return;
                    await ref
                        .read(communityVideoRepositoryProvider)
                        .reject(video.id,
                            moderatorUid: me.uid,
                            reason: 'Not approved');
                    ref.invalidate(pendingSubmissionsProvider);
                  },
                  icon: Icons.close_rounded,
                  label: AppLocalizations.of(context).catalogReject,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppPrimaryButton(
                  onPressed: () async {
                    final me = ref.read(authUserProvider).valueOrNull;
                    if (me == null) return;
                    await ref
                        .read(communityVideoRepositoryProvider)
                        .approve(video.id, moderatorUid: me.uid);
                    ref.invalidate(pendingSubmissionsProvider);
                    ref.invalidate(approvedSubmissionsProvider);
                  },
                  icon: Icons.check_rounded,
                  label: AppLocalizations.of(context).catalogApprove,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
