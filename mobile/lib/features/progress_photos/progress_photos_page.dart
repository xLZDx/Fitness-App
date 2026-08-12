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
import 'widgets/photo_bitmap.dart';
import 'widgets/photo_capture_sheet.dart';
import 'widgets/photo_details_sheet.dart';
import 'widgets/photo_review_screen.dart';

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
          if (!isPaid && ref.watch(entitlementResolvedProvider)) ...[
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
            // Keyed so the paging cursor survives. `_Body` sits in a list
            // whose shape changes with the demo banner, the upgrade card and
            // the capture button, and an unkeyed child in a shifting list is
            // matched by position: the day both ends of the list change in one
            // rebuild, `_visible` would silently reset and the user would find
            // themselves back at the newest thirty.
            data: (photos) => _Body(
              key: const Key('photos.body'),
              photos: photos,
              locked: !isPaid,
            ),
          ),
          const SizedBox(height: 16),
          if (isPaid)
            AppPrimaryButton(
              key: const Key('photos.capture'),
              onPressed: () => runPhotoCaptureFlow(context, ref),
              icon: Icons.photo_camera_outlined,
              label: l10n.progressphotosTakeANewPhoto,
            ),
        ],
      ),
    );
  }
}

/// Shoot, look, describe, file.
///
/// The order is the design's (`ProgressPhotoModule:3909`) and each step earns
/// its place: the angle is what makes two photos comparable, the review is the
/// only chance to notice a bad frame while it can still be retaken, and the
/// details are what put a weight on the compare card. Before R11f the button
/// did all four at once — it called `capture()` bare, so every shot was filed
/// as `front`, unseen, with no weight.
///
/// **Retake loops, it does not exit.** Answering "retake" reopens the camera
/// rather than dropping the user back on the timeline to press the button
/// again; the first draft returned, which turned one bad frame into three taps
/// to fix.
///
/// Top-level rather than a method on the page: nothing here reads the widget,
/// and a free function is directly callable from a test without pumping a
/// timeline first.
Future<void> runPhotoCaptureFlow(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context);
  // Captured BEFORE the first await. Every step below is an async gap, and
  // reaching for the messenger after one of them is the classic
  // use-BuildContext-across-an-async-gap fault.
  final messenger = ScaffoldMessenger.of(context);
  final controller = ref.read(progressPhotosControllerProvider.notifier);

  try {
    while (true) {
      // At the TOP of the loop, not before `continue`. A retake comes back
      // here through several async gaps, and checking on the way out of the
      // previous pass says nothing about the state of this one.
      if (!context.mounted) return;
      // The shot is taken INSIDE the sheet, while its camera is demonstrably
      // open — see the note on PhotoCaptureSheet for why that placement is
      // load-bearing rather than tidy.
      final shot = await PhotoCaptureSheet.show(context);
      if (shot == null) return; // backed out of the camera
      if (!context.mounted) return;

      final choice = await PhotoReviewScreen.show(
        context,
        bytes: shot.bytes,
        angle: shot.angle,
      );
      // Dismissed the review outright: the shot is discarded, and nothing was
      // written, so there is nothing to undo.
      if (choice == null) return;
      if (choice == PhotoReviewChoice.retake) continue;
      if (!context.mounted) return;

      final details = await PhotoDetailsSheet.show(context);
      if (details == null) return; // changed their mind before it was filed

      await controller.save(
        shot.bytes,
        angle: shot.angle,
        weightKg: details.weightKg,
        note: details.note,
      );
      return;
    }
  } catch (e) {
    // The write failing used to be recorded in a provider nothing rendered, so
    // a photo the user posed for could vanish without a word.
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.photosSaveFailed(e))),
    );
  }
}

/// How many photos the timeline shows before the user asks for more.
///
/// Ten rows of three. Enough that the first screen and a scroll or two are
/// already there, small enough that opening the page is a bounded amount of
/// decryption no matter how long the history is.
const int kPhotoPageSize = 30;

class _Body extends ConsumerStatefulWidget {
  const _Body({super.key, required this.photos, required this.locked});

  final List<ProgressPhoto> photos;
  final bool locked;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  int _visible = kPhotoPageSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final photos = widget.photos;
    if (photos.isEmpty) {
      return GlassCard(
        child: Text(
          l10n.progressphotosNoPhotosYet,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    // The compare pair is chosen from the WHOLE history, not from the visible
    // page. Its whole point is the widest span the user has, and that lives at
    // the oldest end — the end paging hides. It is two photos.
    final pair = defaultComparePair(photos);
    final all = groupByMonth(photos);
    final total = totalPhotos(all);
    final months = newestMonths(all, _visible);
    final remaining = total - _visible;
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
        if (remaining > 0)
          AppSecondaryButton(
            key: const Key('photos.showMore'),
            onPressed: () => setState(() => _visible += kPhotoPageSize),
            label: l10n.progressphotosShowMore(remaining),
          ),
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
      data: (Uint8List data) => PhotoBitmap(bytes: data),
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
