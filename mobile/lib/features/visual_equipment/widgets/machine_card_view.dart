import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/glass.dart';
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
class MachineCardView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final photo = card.photoPath;

    return GlassCard(
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
          if (card.uses.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l.machineCardWhatYouCanDo,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            for (final use in card.uses)
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
