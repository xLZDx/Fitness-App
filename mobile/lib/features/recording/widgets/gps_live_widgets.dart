/// Pieces of the recording screen S4-2, the stop panel S4-3 and the summary of
/// S4-4 (S04-D 8, 9, 11, 15). Live numerals are capped at text scale 1.3 and
/// fit the width (G-2); words keep scaling. No looping animation (G-6).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_metric.dart' show HudMetricRow;
import '../../../shared/widgets/hud/hud_surface.dart';
import '../state/recorder_providers.dart';
import 'gps_common_widgets.dart';
import 'gps_format.dart';

// ----------------------------------------------------------------- announce

/// Announces [text] politely (or assertively) with the ambient direction.
void gpsAnnounce(BuildContext context, String text, {bool assertive = false}) {
  final dir = Directionality.of(context);
  // ignore: deprecated_member_use
  unawaited(SemanticsService.announce(
    text,
    dir,
    assertiveness: assertive ? Assertiveness.assertive : Assertiveness.polite,
  ));
}

/// Anti-chatter for machine-originated kinds (G-7): the same kind within 30 s
/// is suppressed. The user's own actions never go through this.
class GpsAnnounceGate {
  final Map<String, DateTime> _last = <String, DateTime>{};

  bool allow(String kind, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final prev = _last[kind];
    if (prev != null && t.difference(prev) < const Duration(seconds: 30)) {
      return false;
    }
    _last[kind] = t;
    return true;
  }
}

// ----------------------------------------------------------------- signal

enum GpsSignalLevel { none, weak, good }

class GpsSignalIndicator extends StatelessWidget {
  const GpsSignalIndicator({super.key, required this.level});

  final GpsSignalLevel level;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final l10n = AppLocalizations.of(context);
    final lit = switch (level) {
      GpsSignalLevel.none => 0,
      GpsSignalLevel.weak => 1,
      GpsSignalLevel.good => 3,
    };
    final word = l10n.gpsSignal(level.name);
    return Semantics(
      key: const ValueKey<String>('gps.rec.signal'),
      label: word,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 3),
              child: Container(
                width: 6,
                height: 8.0 + 5 * i,
                decoration: BoxDecoration(
                  color: i < lit ? t.textPrimary : t.textPrimary.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          const SizedBox(width: 6),
          Flexible(child: Text(word, style: HudType.body(t, size: 13))),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- metrics

/// A big fit-to-width numeral whose own scale stops at 1.3.
class GpsNumeral extends StatelessWidget {
  const GpsNumeral(this.text, {super.key, required this.size});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3)),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: HudType.mono(t, size: size, weight: FontWeight.w600, em: 0),
        ),
      ),
    );
  }
}

/// Time, distance and pace or speed as one readable node (summary node,
/// re-read on focus, NOT a live region). Missing values read "No data".
class GpsMetricBlock extends StatelessWidget {
  const GpsMetricBlock({
    super.key,
    required this.movingTimeMs,
    required this.distanceM,
    required this.pace,
    required this.speed,
    required this.useSpeed,
    required this.stacked,
  });

  final int movingTimeMs;
  final double distanceM;
  final double? pace;
  final double? speed;
  final bool useSpeed;

  /// Text scale above 1.3: one field per row (G-8).
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final paceText = useSpeed ? gpsFormatSpeed(speed) : gpsFormatPace(pace);
    final noData = l10n.gpsNoData;
    final distanceText = distanceM > 0 ? gpsFormatDistance(distanceM) : noData;
    final spokenPace = useSpeed
        ? (paceText ?? l10n.gpsNoDataSpoken)
        : (paceText == null
            ? l10n.gpsNoDataSpoken
            : l10n.gpsPaceSpoken(paceText.replaceAll(' /km', '')));
    final spoken = l10n.gpsSummarySpoken(
      gpsSpokenDuration(l10n, movingTimeMs),
      distanceM > 0 ? gpsSpokenDistance(l10n, distanceM) : l10n.gpsNoDataSpoken,
      spokenPace,
    );
    Widget field(String text) => GpsNumeral(text, size: 32);
    final second = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              field(distanceText),
              const SizedBox(height: 6),
              field(paceText ?? noData),
            ],
          )
        : Row(
            children: <Widget>[
              Expanded(child: field(distanceText)),
              const SizedBox(width: 12),
              Expanded(child: field(paceText ?? noData)),
            ],
          );
    return Semantics(
      key: const ValueKey<String>('gps.rec.summary'),
      label: spoken,
      excludeSemantics: true,
      focusable: true,
      child: HudPanel(
        dense: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            KeyedSubtree(
              key: const ValueKey<String>('gps.rec.time'),
              child: GpsNumeral(gpsFormatDuration(movingTimeMs), size: 56),
            ),
            const SizedBox(height: 10),
            second,
            // TODO(R7): confirm HudType.mono weight/size against the contract
            // contrast target (7:1) in the visual review.
            SizedBox(height: 0, child: Text('', style: TextStyle(color: t.textPrimary))),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- banner

class GpsBannerView extends StatelessWidget {
  const GpsBannerView({super.key, required this.text, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return HudPanel(
      key: const ValueKey<String>('gps.rec.banner'),
      secondary: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ExcludeSemantics(child: Icon(icon, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: GpsBodyText(text, size: 14)),
        ],
      ),
    );
  }
}

class GpsChipRow extends StatelessWidget {
  const GpsChipRow({super.key, required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final l in labels)
          HudChip(label: l, selected: false, maxLines: 3, minHeight: 44),
      ],
    );
  }
}

// ---------------------------------------------------------------- controls

/// Pause/Resume and Stop: at least 72 dp high, 120 dp wide, 16 dp apart (G-3).
class GpsLiveControls extends StatelessWidget {
  const GpsLiveControls({
    super.key,
    required this.paused,
    required this.pauseEnabled,
    required this.onPauseResume,
    required this.onStop,
    this.stopFocusNode,
  });

  final bool paused;
  final bool pauseEnabled;
  final VoidCallback onPauseResume;
  final VoidCallback onStop;
  final FocusNode? stopFocusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: KeyedSubtree(
            key: const ValueKey<String>('gps.rec.pause'),
            child: GpsButton(
              label: paused ? l10n.gpsResume : l10n.gpsPause,
              primary: true,
              enabled: pauseEnabled,
              minHeight: 72,
              minWidth: 120,
              semanticHint: pauseEnabled ? null : l10n.gpsPauseDisabledHint,
              onPressed: onPauseResume,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Focus(
            focusNode: stopFocusNode,
            canRequestFocus: stopFocusNode != null,
            child: KeyedSubtree(
              key: const ValueKey<String>('gps.rec.stop'),
              child: GpsButton(
                label: l10n.gpsStop,
                minHeight: 72,
                minWidth: 120,
                semanticHint: l10n.gpsStopHint,
                onPressed: onStop,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Inline stop panel `gps.rec.stopPanel` (not a dialog). Recording continues.
class GpsStopPanel extends StatelessWidget {
  const GpsStopPanel({
    super.key,
    required this.onFinish,
    required this.onKeepRecording,
    required this.onDiscard,
    this.busy = false,
    this.headerFocusNode,
  });

  final VoidCallback onFinish;
  final VoidCallback onKeepRecording;
  final VoidCallback onDiscard;
  final bool busy;
  final FocusNode? headerFocusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GpsPanelCard(
      key: const ValueKey<String>('gps.rec.stopPanel'),
      title: l10n.gpsStopTitle,
      body: l10n.gpsStopStillRecording,
      headerFocusNode: headerFocusNode,
      buttons: <Widget>[
        GpsButton(
            label: l10n.gpsFinishSave,
            primary: true,
            enabled: !busy,
            minHeight: 56,
            onPressed: onFinish),
        GpsButton(label: l10n.gpsKeepRecording, minHeight: 56, onPressed: onKeepRecording),
        GpsButton(label: l10n.gpsDiscard, minHeight: 56, enabled: !busy, onPressed: onDiscard),
      ],
    );
  }
}

/// Second inline step `gps.rec.discardConfirm`: states what would be lost.
/// Also used by recovery (S4-5) and the revoked screen (S4-6).
class GpsDiscardConfirm extends StatelessWidget {
  const GpsDiscardConfirm({
    super.key,
    required this.distanceM,
    required this.movingTimeMs,
    required this.onDelete,
    required this.onKeep,
    this.keepLabel,
    this.deleteLabel,
    this.busy = false,
    this.headerFocusNode,
  });

  final double distanceM;
  final int movingTimeMs;
  final VoidCallback onDelete;
  final VoidCallback onKeep;
  final String? keepLabel;
  final String? deleteLabel;
  final bool busy;
  final FocusNode? headerFocusNode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GpsPanelCard(
      key: const ValueKey<String>('gps.rec.discardConfirm'),
      title: l10n.gpsDiscard,
      body: l10n.gpsDiscardConfirm(
          gpsFormatDistance(distanceM), gpsFormatDuration(movingTimeMs)),
      headerFocusNode: headerFocusNode,
      buttons: <Widget>[
        GpsButton(
            label: deleteLabel ?? l10n.gpsDelete,
            enabled: !busy,
            onPressed: onDelete),
        GpsButton(label: keepLabel ?? l10n.gpsKeep, primary: true, onPressed: onKeep),
      ],
    );
  }
}

// ----------------------------------------------------------------- summary

/// Summary rows of the finish screen: each value "No data" when undefined.
class GpsSummaryPanel extends StatelessWidget {
  const GpsSummaryPanel({
    super.key,
    required this.movingTimeMs,
    required this.elapsedMs,
    required this.distanceM,
    required this.pace,
    required this.speed,
    required this.useSpeed,
    required this.ascentM,
    required this.descentM,
  });

  final int movingTimeMs;
  final int? elapsedMs;
  final double distanceM;
  final double? pace;
  final double? speed;
  final bool useSpeed;
  final double? ascentM;
  final double? descentM;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final noData = l10n.gpsNoData;
    String m(double? v) => v == null ? noData : '${v.round()} m';
    // TODO(R8): these row labels have no ARB keys yet (gpsLabel*); see report.
    return HudPanel(
      key: const ValueKey<String>('gps.finish.summary'),
      dense: true,
      child: Column(
        children: <Widget>[
          HudMetricRow(label: l10n.gpsLabelMovingTime, value: gpsFormatDuration(movingTimeMs)),
          HudMetricRow(
              label: l10n.gpsLabelElapsed,
              value: elapsedMs == null ? noData : gpsFormatDuration(elapsedMs!)),
          HudMetricRow(
              label: l10n.gpsLabelDistance,
              value: distanceM > 0 ? gpsFormatDistance(distanceM) : noData),
          HudMetricRow(
              label: useSpeed ? l10n.gpsLabelAvgSpeed : l10n.gpsLabelAvgPace,
              value: (useSpeed ? gpsFormatSpeed(speed) : gpsFormatPace(pace)) ?? noData),
          HudMetricRow(label: l10n.gpsLabelAscent, value: m(ascentM)),
          HudMetricRow(label: l10n.gpsLabelDescent, value: m(descentM), divider: false),
        ],
      ),
    );
  }
}

// ------------------------------------------------- background reporter (R9)

/// Mount once under the app root: reports app visibility to the recorder so
/// the `background` condition is current on every screen (S04-D 8.3).
class GpsBackgroundReporter extends ConsumerStatefulWidget {
  const GpsBackgroundReporter({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GpsBackgroundReporter> createState() => _GpsBackgroundReporterState();
}

class _GpsBackgroundReporterState extends ConsumerState<GpsBackgroundReporter>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      ref
          .read(recorderControllerProvider.notifier)
          .setBackground(state != AppLifecycleState.resumed);
    } catch (_) {
      // An unwired recorder must not break the lifecycle.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
