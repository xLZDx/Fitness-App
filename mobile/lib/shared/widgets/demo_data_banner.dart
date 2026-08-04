import 'package:flutter/material.dart';

/// Says the list on screen is not real yet.
///
/// ## Why this exists
///
/// Three features ship with an in-memory mock repository as their ONLY
/// implementation — `main.dart` overrides every other repository provider in
/// the app with a real one, and these three are the exception. Nothing
/// visible on their pages said so. The marketplace's mock went further than
/// silence: its two seed listings carried fabricated licensure claims
/// ("NSCA-CSCS", "Doctor of Physical Therapy"), a hardcoded `isVerified:
/// true` that renders a verification badge, and invented rating counts that
/// render real-looking stars — a real user had no way to tell "Maria Lopez,
/// DPT, 5.0 (12 reviews)" from an actual vetted coach.
///
/// Same failure shape S0a spent two gates on: a claim the product does not
/// actually back. `MockCoachListingRepository` no longer carries fabricated
/// credentials (see its seed data), and this banner is the second half —
/// naming the whole list as sample data, not just detoxifying the two rows.
///
/// ## Why it removes itself rather than being deleted at cutover time
///
/// `isDemo` is computed from the actual runtime type of the bound provider
/// (`repo is MockXxxRepository`), not from a manually-flipped constant. The
/// day `main.dart` wires a real backend for one of these three, its banner
/// disappears on its own — nobody has to remember this file exists, the same
/// reasoning `SafetyDisclosure` and the S3b honesty banner already use.
class DemoDataBanner extends StatelessWidget {
  const DemoDataBanner({
    super.key,
    required this.isDemo,
    required this.message,
  });

  final bool isDemo;
  final String message;

  @override
  Widget build(BuildContext context) {
    if (!isDemo) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colour = theme.colorScheme.tertiary;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colour.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, size: 20, color: colour),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
