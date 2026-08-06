import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/demo_data_banner.dart';
import '../../shared/widgets/glass.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'data/progress_photo.dart';
import 'state/progress_photos_providers.dart';
import 'package:intl/intl.dart';

/// Progress photos page. Free users see the empty-state copy + upgrade CTA
/// (we don't gate the safety-critical features but trend photos are
/// paid-tier only).
///
/// This comment used to open with "End-to-end encrypted; the device key never
/// leaves SharedPreferences", and every word of that was wrong in a way worth
/// recording. No photo is encrypted, because no photo exists: the only
/// repository is [MockProgressPhotosRepository], which fabricates records and
/// touches no bytes. There is no device key. And had there been one,
/// SharedPreferences would have been the wrong home for it — it is a plain
/// XML file on Android, readable by anything with the app's uid, which is
/// exactly what a key must not be.
///
/// [AesPhotoCipher] is real AES-256-GCM and is correct; it simply has no
/// caller. Until one exists, every encryption claim on this page is gated on
/// [progressPhotosAreDemoProvider] — the same self-removing flag the demo
/// banner uses. Bind a real repository and the promises reappear on their own,
/// because by then they will be true.
class ProgressPhotosPage extends ConsumerWidget {
  const ProgressPhotosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tier = ref.watch(effectiveTierProvider);
    final isPaid = tier != SubscriptionTier.free;
    final photosAsync = ref.watch(progressPhotosProvider);
    final isDemo = ref.watch(progressPhotosAreDemoProvider);

    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).profileProgressPhotos),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          DemoDataBanner(
            isDemo: isDemo,
            message: AppLocalizations.of(context).progressphotosDemoNotSaved,
          ),
          if (!isDemo) ...[
            _PrivacyStrip(),
            const SizedBox(height: 16),
          ],
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
              child: Text(AppLocalizations.of(context).progressphotosCouldNotLoadPhotos(e)),
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
              label: Text(AppLocalizations.of(context).progressphotosTakeANewPhoto),
            ),
        ],
      ),
    );
  }
}

/// The encryption promise. Rendered only when a real repository is bound —
/// see the gate at the call site, and the library comment for why.
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
              AppLocalizations.of(context).progressphotosPhotosAreEncryptedOnYourDevice,
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colors.textSecondary,
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
      onTap: () => GoRouter.of(context).push('/subscription'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).progressphotosTrendPhotosAreASupporterBenefit,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context).progressphotosCompareSideBySideOverWeeks,
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
              ? AppLocalizations.of(context).progressphotosNoPhotosYet
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
            const Center(child: Icon(Icons.image, color: AppSemanticColors.onGradientInk, size: 30)),
            Positioned(
              left: 6,
              right: 6,
              bottom: 6,
              child: Text(
                _date(context, photo.takenAt),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: AppSemanticColors.onGradientInk, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Locale-correct, not two hard-coded English arrays. Russian dates
  /// decline — "20 мая", never "мая 20" — and `DateFormat` knows that for
  /// every locale Flutter ships.
  String _date(BuildContext context, DateTime t) =>
      DateFormat.MMMd(AppLocalizations.of(context).localeName).format(t);
}
