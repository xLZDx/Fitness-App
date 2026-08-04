import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/theme/app_palette.dart';
import '../../shared/widgets/demo_data_banner.dart';
import '../../shared/widgets/glass.dart';
import 'data/coach_listing.dart';
import 'state/marketplace_providers.dart';

/// Coach marketplace page (TX.5). Lists vetted coaches with their
/// price + rating. Tapping a card opens the booking flow which calls
/// [bookCoachSession] under the hood.
class MarketplacePage extends ConsumerWidget {
  const MarketplacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final listAsync = ref.watch(coachListingsProvider);
    final isDemo = ref.watch(marketplaceListingsAreDemoProvider);
    return FrostedScaffold(
      appBar: GlassAppBar(title: AppLocalizations.of(context).marketplaceCoaches),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
        children: [
          DemoDataBanner(
            isDemo: isDemo,
            message: AppLocalizations.of(context).marketplaceDemoListings,
          ),
          GlassCard(
            child: Text(
              AppLocalizations.of(context).marketplaceVettedCoachesWhoRun11,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          listAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => GlassCard(child: Text(AppLocalizations.of(context).catalogError(e))),
            data: (list) => Column(
              children: [
                for (final c in list) ...[
                  _CoachCard(coach: c, bookingDisabled: isDemo),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachCard extends ConsumerWidget {
  const _CoachCard({required this.coach, required this.bookingDisabled});
  final CoachListing coach;

  /// True while the list is demo data. `GlassCard`'s own `onTap != null`
  /// check is what marks a card as tappable to a screen reader
  /// (`Semantics(button:)` in `glass.dart`), so `onTap: null` here is not
  /// cosmetic — it is what makes "booking is disabled" in the banner above
  /// actually true, instead of a card that still looks and announces as
  /// tappable and only fails two round trips later inside `_bookSheet`.
  final bool bookingDisabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      onTap: bookingDisabled ? null : () => _bookSheet(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppPalette.auroraViolet,
                child: Text(
                  coach.displayName.isEmpty
                      ? '?'
                      : coach.displayName[0],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(coach.displayName,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800)),
                        if (coach.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 16),
                        ],
                      ],
                    ),
                    Text(
                      coach.formattedPrice,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (coach.ratingAverage != null)
                Column(
                  children: [
                    Text(coach.ratingAverage!.toStringAsFixed(1),
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(AppLocalizations.of(context).marketplaceReviews(coach.ratingCount),
                        style: theme.textTheme.labelSmall),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(coach.bio, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in coach.specialties)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                  child: Text(s,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _bookSheet(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(coachMarketplaceServiceProvider);
    final scaffoldCtx = context;
    final result = await svc.bookSession(
      coachUid: coach.uid,
      startsAt: DateTime.now().add(const Duration(days: 1)),
    );
    if (!scaffoldCtx.mounted) return;
    ScaffoldMessenger.of(scaffoldCtx).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).marketplaceBookedBooking(coach.displayName, result.bookingId)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
