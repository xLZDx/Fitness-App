import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';
import '../../shared/widgets/demo_data_banner.dart';
import '../../shared/widgets/glass.dart';
import '../subscription/data/subscription_models.dart';
import '../subscription/state/subscription_providers.dart';
import 'data/photo_timeline.dart';
import 'data/progress_photo.dart';
import 'state/progress_photos_providers.dart';
import 'widgets/photo_capture_sheet.dart';

/// Progress photos: a month-grouped timeline plus a before/after card.
///
/// The encryption claim on [_PrivacyStrip] is real as of R7 —
/// [LocalProgressPhotosRepository] writes AES-GCM envelopes into the app's
/// private documents directory and nothing here has a network path. It stays
/// gated on [progressPhotosAreDemoProvider] anyway, because that provider is
/// now false only once the disk store has resolved; during that window the
/// mock is bound and a capture really would vanish.
///
/// There is no share button and no export. That is the feature working as
/// scoped, not a gap: the design had an `ExportScreen`, and the first thing it
/// would do is hand a decrypted JPEG to the system share sheet.
class ProgressPhotosPage extends ConsumerWidget {
  const ProgressPhotosPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tier = ref.watch(effectiveTierProvider);
    final isPaid = tier != SubscriptionTier.free;
    final photosAsync = ref.watch(progressPhotosProvider);
    final isDemo = ref.watch(progressPhotosAreDemoProvider);

    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.profileProgressPhotos),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          DemoDataBanner(
            isDemo: isDemo,
            message: l10n.progressphotosDemoNotSaved,
          ),
          if (!isDemo) ...[
            const _PrivacyStrip(),
            const SizedBox(height: 16),
          ],
          if (!isPaid) ...[
            const _UpgradeCard(),
            const SizedBox(height: 16),
          ],
          photosAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => GlassCard(
              tint: theme.colorScheme.error,
              child: Text(l10n.progressphotosCouldNotLoadPhotos(e)),
            ),
            data: (photos) => _Body(photos: photos, locked: !isPaid),
          ),
          const SizedBox(height: 16),
          if (isPaid)
            AppPrimaryButton(
              key: const Key('photos.capture'),
              // R11f. This used to call `capture()` bare: no angle, so every
              // shot was filed as `front`, and no preview, so the user pressed
              // a button and a picture was taken of wherever the phone
              // happened to point. Both halves of "two shots taken the same
              // way" -- which is the entire feature -- were unaskable.
              onPressed: () async {
                final angle = await PhotoCaptureSheet.show(context);
                // Null is a real answer: the user backed out, and firing a
                // capture anyway is the bug in a new place.
                if (angle == null) return;
                await ref
                    .read(progressPhotosControllerProvider.notifier)
                    .capture(angle: angle);
              },
              icon: Icons.photo_camera_outlined,
              label: l10n.progressphotosTakeANewPhoto,
            ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.photos, required this.locked});

  final List<ProgressPhoto> photos;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    if (photos.isEmpty) {
      return GlassCard(
        child: Text(
          l10n.progressphotosNoPhotosYet,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final pair = defaultComparePair(photos);
    final months = groupByMonth(photos);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CompareCard(pair: pair),
        const SizedBox(height: 20),
        for (final m in months) ...[
          _MonthHeading(month: m),
          const SizedBox(height: 8),
          _PhotoGrid(photos: m.photos),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}

/// Before/after. Shows the widest same-angle span, or says why it can't.
class _CompareCard extends StatelessWidget {
  const _CompareCard({required this.pair});

  final ComparePair? pair;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = pair;
    if (p == null) {
      return GlassCard(
        key: const Key('photos.compare.empty'),
        child: Text(
          l10n.progressphotosNeedTwoSameAngle,
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return GlassCard(
      key: const Key('photos.compare'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l10n.progressphotosCompare,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                l10n.progressphotosCompareSpan(p.daySpan),
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CompareSide(
                  label: l10n.progressphotosBefore,
                  photo: p.before,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CompareSide(
                  label: l10n.progressphotosAfter,
                  photo: p.after,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompareSide extends StatelessWidget {
  const _CompareSide({required this.label, required this.photo});

  final String label;
  final ProgressPhoto photo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        AspectRatio(
          aspectRatio: 0.75,
          child: _PhotoImage(photo: photo),
        ),
        const SizedBox(height: 4),
        Text(
          _fullDate(context, photo.takenAt),
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _MonthHeading extends StatelessWidget {
  const _MonthHeading({required this.month});

  final PhotoMonth month;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          DateFormat.yMMMM(l10n.localeName).format(month.month),
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const Spacer(),
        Text(
          l10n.progressphotosMonthCount(month.count),
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos});

  final List<ProgressPhoto> photos;

  @override
  Widget build(BuildContext context) {
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

class _PhotoTile extends ConsumerWidget {
  const _PhotoTile({required this.photo});

  final ProgressPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PhotoImage(photo: photo),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Text(
              DateFormat.MMMd(l10n.localeName).format(photo.takenAt),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppSemanticColors.onGradientInk,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Decrypts and renders one photo.
///
/// The two failure modes are told apart on purpose. A missing blob is a bug or
/// a half-finished delete; a fingerprint mismatch means the key is gone, which
/// happens after a reinstall and is not recoverable. Collapsing both into one
/// "couldn't load" would leave the user retrying something that can never
/// work.
class _PhotoImage extends ConsumerWidget {
  const _PhotoImage({required this.photo});

  final ProgressPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bytes = ref.watch(photoBytesProvider(photo));
    return bytes.when(
      loading: () => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(6),
        child: Center(
          child: Text(
            e.toString().contains('no longer has')
                ? l10n.progressphotosKeyMissing
                : l10n.progressphotosBlobMissing,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ),
      data: (Uint8List data) => Image.memory(data, fit: BoxFit.cover),
    );
  }
}

class _PrivacyStrip extends StatelessWidget {
  const _PrivacyStrip();

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
              AppLocalizations.of(context).progressphotosStaysOnPhone,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(18),
      onTap: () => GoRouter.of(context).push('/subscription'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.progressphotosTrendPhotosAreASupporterBenefit,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.progressphotosCompareSideBySideOverWeeks,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _fullDate(BuildContext context, DateTime t) =>
    DateFormat.yMMMd(AppLocalizations.of(context).localeName).format(t);
