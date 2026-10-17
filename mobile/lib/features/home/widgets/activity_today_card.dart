/// "Activity today" card of Home (S03-12; contract S-6 item 3 and C-5; design
/// 3.3). Reads only [activityTodayProvider], which is empty unless the journal
/// is `open` and loaded, so while the journal is binding or failed the card is
/// simply absent: never an empty card, never an error text (AC-HM-5).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_metric.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../activity/data/activity_aggregates.dart';
import '../../activity/state/activity_dashboard_providers.dart';
import '../../progress/widgets/progress_activity_format.dart';

/// Rows shown before the non-interactive "+n" line.
const int kActivityTodayMaxRows = 3;

class ActivityTodayCard extends ConsumerWidget {
  const ActivityTodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<SessionDigest> today = ref.watch(activityTodayProvider);
    if (today.isEmpty) return const SizedBox.shrink();
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final String locale = l10n.localeName;
    final ZoneFn? zone = ref.watch(activityZoneProvider);
    final List<SessionDigest> shown =
        today.length > kActivityTodayMaxRows
            ? today.sublist(0, kActivityTodayMaxRows)
            : today;
    final int more = today.length - shown.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          HudTokens.screenGutter, 0, HudTokens.screenGutter, 14),
      child: HudPanel(
        key: const Key('home.activityToday'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.homeActivityToday,
                style: HudType.panelTitle(t).inPanel(t)),
            const SizedBox(height: 8),
            for (int i = 0; i < shown.length; i++)
              _TodayRow(
                digest: shown[i],
                locale: locale,
                zone: zone,
                divider: i < shown.length - 1,
              ),
            if (more > 0) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context).activityTodayMore(more),
                key: const Key('home.activityToday.more'),
                style: HudType.body(t, size: 12).inPanel(t),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({
    required this.digest,
    required this.locale,
    required this.zone,
    required this.divider,
  });

  final SessionDigest digest;
  final String locale;
  final ZoneFn? zone;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final DateTime utc = digest.startUtc;
    final DateTime local = zone == null ? utc.toLocal() : zone!(utc.toUtc());
    final String time = DateFormat.Hm(locale).format(local);
    final String noData = l10n.activityNoData;
    final double? secs = digest.movingTimeS;
    final double? metres = digest.distanceM;
    final SourceLabel src = sourceLabelOf(digest);
    String source = _sourceText(l10n, src.key);
    if (src.moreSources > 0) {
      source = '$source ${l10n.activitySourcesMore(src.moreSources)}';
    }
    final String metrics = '$time · '
        '${secs == null ? noData : l10n.commonMinutes(progressMinutesOf(secs))} · '
        '${metres == null ? noData : formatProgressDistance(metres, locale, l10n.activityUnitKm)}';
    return MergeSemantics(
      child: HudSettingRow(
        icon: _icon(digest.sportGroup),
        title: _name(l10n, digest.sportGroup),
        subtitle: <String>[
          metrics,
          source,
          if (digest.streamLost) l10n.activityStreamLost,
        ].join('\n'),
        divider: divider,
        trailing: const SizedBox.shrink(),
      ),
    );
  }
}

String _name(AppLocalizations l10n, SportGroup g) => switch (g) {
      SportGroup.walkHike => l10n.sportGroupWalkHike,
      SportGroup.run => l10n.sportGroupRun,
      SportGroup.ride => l10n.sportGroupRide,
      SportGroup.swim => l10n.sportGroupSwim,
      SportGroup.row => l10n.sportGroupRow,
      SportGroup.other => l10n.sportGroupOther,
    };

IconData _icon(SportGroup g) => switch (g) {
      SportGroup.walkHike => Icons.directions_walk,
      SportGroup.run => Icons.directions_run,
      SportGroup.ride => Icons.directions_bike,
      SportGroup.swim => Icons.pool,
      SportGroup.row => Icons.rowing,
      SportGroup.other => Icons.fitness_center,
    };

String _sourceText(AppLocalizations l10n, SourceLabelKey k) => switch (k) {
      SourceLabelKey.app => l10n.sourceLabelApp,
      SourceLabelKey.healthConnect => l10n.sourceHealthConnect,
      SourceLabelKey.healthKit => l10n.sourceLabelHealthPlatform,
      SourceLabelKey.watch => l10n.sourceWatch,
      SourceLabelKey.sensor => l10n.sourceLabelSensor,
      SourceLabelKey.healthPlatform => l10n.sourceLabelHealthPlatform,
      SourceLabelKey.service => l10n.sourceLabelService,
      SourceLabelKey.companionApp => l10n.sourceLabelCompanionApp,
      SourceLabelKey.fileImport => l10n.sourceLabelFileImport,
      SourceLabelKey.unknown => l10n.sourceLabelUnknown,
    };
