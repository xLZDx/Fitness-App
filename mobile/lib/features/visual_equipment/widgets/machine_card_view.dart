import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../equipment/state/equipment_providers.dart';
import '../../safety/state/eligibility_providers.dart';
import '../data/machine_card.dart';

/// What the user sees when they photographed a real machine the app has no
/// page for.
///
/// The old answer here was "Не удалось понять, что это" and nothing else,
/// which is both unhelpful and, once the second question exists, untrue — we
/// DID work out what it is, we just have no clip. Operator: *"объяснить
/// человеку, что за железка перед ним и что на нем можно делать"*, and the
/// card is the user's, marked honestly: *"пользователю тоже видна как «контент
/// готовится»"*.
///
/// The button out is the other half of the instruction — *"а клиенту
/// посоветовать ролик на ютюбе или еще где пока мы не добавим новый
/// контент"*. Sending someone to a video that exists beats an empty page.
/// ## Why `uses` is conditional (F016)
///
/// `uses` is free text the model wrote about a machine that is, by
/// definition, not in the catalogue — `MachineDescriber` is asked only after
/// recognition came back empty. It carries no `contraindications` field and
/// nothing can attach one, so `isContraindicated` would return false for
/// every line of it however the user is injured.
///
/// That is the same problem `equipment_providers.dart:481-482` already
/// solved for `ai::` exercises, and it takes the same answer: withheld for a
/// user there is anything to screen against, rather than shown unscreened.
/// Matching each `uses` LINE against the MACHINE catalogue was considered and
/// rejected here — a machine this card exists for has no catalogue entry by
/// construction (`MachineDescriber` only runs after machine recognition came
/// back empty), so that particular match would suppress the list for
/// everybody and delete the feature instead of making it safe.
///
/// That rejection is about the machine, not the individual EXERCISE NAMES
/// inside `uses`, which is a different check on a different entity — G-C's
/// original remediation conflated the two and claimed the hazard closed on
/// the strength of the machine-catalogue reasoning above; it does not follow
/// from it. The actual per-line check happens HERE, in [build], every
/// render, via `exerciseNameMatcherProvider` — regardless of `showUses`,
/// and regardless of how or when [card] reached this widget: a fresh scan,
/// a stored/legacy card streamed from Firestore, anything future that
/// writes a card without going through the scan flow at all. That is
/// deliberate, not incidental: a first version filtered once, at write
/// time, in `visual_equipment_providers.dart`'s `_describeInstead`, and two
/// independent reviews (GPT-PM's round-19, plus this repo's own internal
/// flutter/security specialists) both caught that a write-time-only filter
/// protects nothing streamed in from storage by any OTHER path — this
/// widget is the only place `card.uses` is ever consumed, so this is the
/// only place validation can actually guarantee coverage. `card` itself is
/// never filtered or rewritten anywhere upstream; what's stored is always
/// the model's raw, unvalidated text, and it stays that way — safe only
/// because nothing downstream of storage ever trusts it unchecked.
///
/// `showUses` below is a second, independent gate on top of the content
/// check: it withholds the (already-validated) list entirely for a user
/// who has something to screen against, the same all-or-nothing shape
/// `equipment_providers.dart:481-482` uses for `ai::` exercises. An
/// un-onboarded/clear user still sees the list — but only the validated
/// remainder of it, and only the matched CATALOGUE title for each line
/// that validates, never the model's own wording: `exerciseNameMatcherProvider`
/// resolves a line like "Leg Press With Torso Rotation" to "Leg Press" and
/// discards the rest, rather than accepting the whole line just because a
/// real title appears somewhere inside it — see that provider's own doc
/// comment for why a boolean check alone was unsafe here.
class MachineCardView extends ConsumerWidget {
  const MachineCardView({
    super.key,
    required this.card,
    this.onWatchElsewhere,
    this.showPhoto = true,
  });

  final MachineCard card;

  /// Injectable so the test does not open a browser. Defaults to a YouTube
  /// search for [MachineCard.searchQuery].
  final Future<bool> Function(Uri uri)? onWatchElsewhere;

  final bool showPhoto;

  Future<void> _watch() async {
    final uri = Uri.https(
      'www.youtube.com',
      '/results',
      {'search_query': card.searchQuery},
    );
    final open = onWatchElsewhere ??
        ((Uri u) => launchUrl(u, mode: LaunchMode.externalApplication));
    await open(uri);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final photo = card.photoPath;

    // Null while the context is still resolving. Withholding until it lands
    // is the safe direction: the list reappears a frame later for a user with
    // nothing to screen, whereas showing first and retracting would put
    // unscreened movements in front of an injured user for exactly as long as
    // it takes them to read one.
    final safety = ref.watch(safetyContextProvider).valueOrNull;
    // `allowsAnyTraining` is deliberately NOT the test — see
    // `SafetyContext.blockedByAStatedAnswer`, which is where that distinction
    // is defined and argued. Someone who has told us nothing has nothing to
    // screen against, and `SafetyDisclosure` is what states that honestly
    // rather than hiding content over it.
    final showUses = safety != null &&
        !safety.blockedByAStatedAnswer &&
        safety.injuries.isEmpty &&
        safety.health.restrictions.isEmpty;

    // G-C/F016: the actual content-validation boundary — see this class's
    // own doc comment above for why it lives here and not at write time.
    // `ref.watch`, not a one-time read: while the catalogue is still loading
    // this returns an empty matcher (fails closed, nothing shown yet) and
    // rebuilds the moment it resolves, recovering a legitimate suggestion
    // without needing a rescan — safe specifically because `card.uses` is
    // never destroyed or rewritten anywhere before it gets here.
    final validatedUses =
        ref.watch(exerciseNameMatcherProvider).filter(card.uses);

    return HudPanel(
      key: const Key('machine-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showPhoto && photo != null && File(photo).existsSync()) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(photo),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                // The photo is a nicety; a file that has since been swept out
                // of the cache must not take the explanation down with it.
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  card.name,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              _PreparingBadge(label: l.machineCardPreparing),
            ],
          ),
          const SizedBox(height: 6),
          Text(card.summary, style: theme.textTheme.bodyMedium),
          if (validatedUses.isNotEmpty && showUses) ...[
            const SizedBox(height: 12),
            Text(
              l.machineCardWhatYouCanDo,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            for (final use in validatedUses)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: theme.textTheme.bodyMedium),
                    Expanded(
                      child: Text(use, style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ] else if (validatedUses.isNotEmpty) ...[
            // Says why, rather than silently rendering a shorter card. A list
            // that vanishes without explanation reads as the app having
            // nothing to say about the machine, which is a different and
            // untrue claim.
            //
            // Gated on `validatedUses`, not `card.uses`: a card whose lines
            // are ALL unvalidated must fall through to neither branch here,
            // same as a card with no uses at all -- "withheld for safety
            // reasons" would be a false claim about content that was never
            // going to be shown regardless of the viewer's safety answers.
            const SizedBox(height: 12),
            Text(
              l.machineCardUsesWithheld,
              key: const Key('machine-card.uses-withheld'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colors.textSecondary),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: AppSecondaryButton(
              key: const Key('machine-card-watch'),
              onPressed: _watch,
              icon: Icons.play_circle_outline,
              label: l.machineCardWatchElsewhere,
            ),
          ),
        ],
      ),
    );
  }
}

/// The honest label. Not an error, not a promise with a date on it.
class _PreparingBadge extends StatelessWidget {
  const _PreparingBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
