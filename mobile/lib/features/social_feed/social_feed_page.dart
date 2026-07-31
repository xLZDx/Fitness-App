import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../auth/state/auth_providers.dart';
import 'data/social_post.dart';
import 'state/social_feed_providers.dart';

/// Hevy-style global community feed. Anyone can post, anyone can like.
/// No follow graph yet — chronological feed of all opted-in posts.
class SocialFeedPage extends ConsumerWidget {
  const SocialFeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(socialFeedProvider);
    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).profileCommunity),
      body: Stack(
        children: [
          feedAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text(AppLocalizations.of(context).catalogError(e))),
            data: (posts) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
              children: [
                for (final p in posts) ...[
                  _PostCard(post: p),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton.extended(
              onPressed: () => _composeSheet(context, ref),
              icon: const Icon(Icons.edit),
              label: Text(AppLocalizations.of(context).socialfeedPost),
            ),
          ),
        ],
      ),
    );
  }

  void _composeSheet(BuildContext context, WidgetRef ref) {
    final ctl = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(sheet).viewInsets.bottom + 16,
        ),
        child: GlassCard(
          floating: true,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctl,
                maxLines: 4,
                decoration: InputDecoration(
                    hintText:
                        AppLocalizations.of(context).socialfeedShareSomething),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final me = ref.read(authUserProvider).valueOrNull;
                  if (me == null) return;
                  if (ctl.text.trim().isEmpty) {
                    Navigator.of(sheet).pop();
                    return;
                  }
                  await ref.read(socialFeedRepositoryProvider).post(
                        authorUid: me.uid,
                        authorDisplay: me.displayName,
                        body: ctl.text.trim(),
                      );
                  if (sheet.mounted) Navigator.of(sheet).pop();
                },
                child: Text(AppLocalizations.of(context).socialfeedPost),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostCard extends ConsumerWidget {
  const _PostCard({required this.post});
  final SocialPost post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppPalette.auroraTeal,
                child: Text(
                  post.authorDisplay.isEmpty ? '?' : post.authorDisplay[0],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(post.authorDisplay,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(_ago(post.createdAt), style: theme.textTheme.labelSmall),
            ],
          ),
          const SizedBox(height: 8),
          Text(post.body, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  post.likedByMe ? Icons.favorite : Icons.favorite_outline,
                  color: post.likedByMe ? AppPalette.auroraPink : null,
                ),
                onPressed: () async {
                  final me = ref.read(authUserProvider).valueOrNull;
                  if (me == null) return;
                  final repo = ref.read(socialFeedRepositoryProvider);
                  if (post.likedByMe) {
                    await repo.unlike(post.id, uid: me.uid);
                  } else {
                    await repo.like(post.id, uid: me.uid);
                  }
                },
              ),
              Text('${post.likes}'),
            ],
          ),
        ],
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
