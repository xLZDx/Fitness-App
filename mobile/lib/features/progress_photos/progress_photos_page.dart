import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/glass.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'data/progress_photo.dart';
import 'state/progress_photos_providers.dart';

/// Progress photos page. End-to-end encrypted; the device key never
/// leaves SharedPreferences. Free users see the empty-state copy +
/// upgrade CTA (we don't gate the safety-critical features but trend
/// photos are paid-tier only).
class ProgressPhotosPage extends ConsumerWidget {
  const ProgressPhotosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tier = ref.watch(effectiveTierProvider);
    final isPaid = tier != SubscriptionTier.free;
    final photosAsync = ref.watch(progressPhotosProvider);

    return FrostedScaffold(
      appBar: const GlassAppBar(title: 'Progress photos'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          _PrivacyStrip(),
          const SizedBox(height: 16),
          if (!isPaid) ...[
            _UpgradeCard(),
            const SizedBox(height: 16),
          ],
          photosAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => GlassCard(
              tint: theme.colorScheme.error,
              child: Text('Could not load photos: $e'),
            ),
            data: (photos) =>
                _PhotosGrid(photos: photos, locked: !isPaid),
          ),
          const SizedBox(height: 16),
          if (isPaid)
            FilledButton.icon(
              onPressed: () =>
                  ref.read(progressPhotosControllerProvider.notifier).capture(),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take a new photo'),
            ),
        ],
      ),
    );
  }
}

class _PrivacyStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Photos are encrypted on your device with a key that '
              'never leaves the phone. We never sell health data.',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.75),
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
      padding: const EdgeInsets.all(18),
      onTap: () => GoRouter.of(context).go('/subscription'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trend photos are a Supporter benefit',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Compare side-by-side over weeks or months. Stays '
            'encrypted on your device.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PhotosGrid extends StatelessWidget {
  const _PhotosGrid({required this.photos, required this.locked});
  final List<ProgressPhoto> photos;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return GlassCard(
        child: Text(
          locked
              ? 'No photos yet — become a Supporter to start tracking.'
              : 'No photos yet. Tap below to take your first one.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: photos.length,
      itemBuilder: (context, i) => _PhotoTile(photo: photos[i]),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo});
  final ProgressPhoto photo;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: AppPalette.tileGradients[
              photo.id.hashCode.abs() %
                  AppPalette.tileGradients.length]),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Center(child: Icon(Icons.image, color: Colors.white, size: 30)),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Text(
                _date(photo.takenAt),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _date(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}';
  }
}
