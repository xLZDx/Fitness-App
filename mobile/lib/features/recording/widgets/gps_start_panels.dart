/// Start screen pieces (S04-D 6, 7): the sport row, the auto-pause row, the
/// privacy line, the battery note and the permission/denial panels
/// (`gps.start.panel.<id>`). Panels are inline, never dialogs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/hud/hud_metric.dart' show HudSettingRow, HudToggle;
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../activity/data/sport_type.dart';
import 'gps_common_widgets.dart';
import 'gps_format.dart';
import 'gps_start_flow.dart';

/// Single-choice sport chips (exclusive group, wraps at large text scale).
class GpsSportRow extends StatelessWidget {
  const GpsSportRow({super.key, required this.selected, required this.onChanged});

  final SportType selected;
  final ValueChanged<SportType> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final s in kGpsStartSports)
          HudChip(
            key: ValueKey<String>('gps.start.sport.${s.name}'),
            label: gpsSportLabel(l10n, s),
            selected: s == selected,
            minHeight: 48,
            maxLines: 2,
            onTap: () => onChanged(s),
            showFocusRing: true,
            hoverStyle: true,
            cursor: true,
          ),
      ],
    );
  }
}

/// Auto-pause row with a toggle.
class GpsAutoPauseRow extends StatelessWidget {
  const GpsAutoPauseRow({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HudPanel(
      secondary: true,
      child: HudSettingRow(
        key: const ValueKey<String>('gps.start.autoPause'),
        icon: Icons.pause_circle_outline,
        title: l10n.gpsAutoPause,
        subtitle: l10n.gpsAutoPauseHint,
        divider: false,
        mergeSemantics: true,
        trailing: HudToggle(
          value: value,
          semanticLabel: l10n.gpsAutoPause,
          onChanged: onChanged,
        ),
        onTap: () => onChanged(!value),
      ),
    );
  }
}

/// The always-visible privacy line (what / where / who, GPS-PRIV-006).
class GpsPrivacyLine extends StatelessWidget {
  const GpsPrivacyLine({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HudPanel(
      key: const ValueKey<String>('gps.start.privacy'),
      secondary: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const ExcludeSemantics(child: Icon(Icons.lock_outline, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: GpsBodyText(l10n.gpsPrivacyLine, size: 13)),
        ],
      ),
    );
  }
}

/// RS-5: battery 4 to 10 percent, not charging.
class GpsBatteryStartNote extends ConsumerWidget {
  const GpsBatteryStartNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(gpsStartBatteryProvider).valueOrNull;
    if (r == null || r.charging || r.percent < 4 || r.percent > 10) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GpsBodyText(l10n.gpsBatteryStartNote(r.percent), secondary: true, size: 13),
    );
  }
}

/// The active panel above the Start button. Returns an empty box for
/// [GpsStartPanelId.none].
class GpsStartPanelView extends ConsumerWidget {
  const GpsStartPanelView({
    super.key,
    required this.panel,
    required this.resumeMode,
    required this.onAddManually,
    this.onReview,
    this.onOpenPrivacySettings,
    this.onBackToOffer,
  });

  final GpsStartPanelId panel;

  /// RS-8: resume mode hides `blockedByJournal` (the journal is what resumes).
  final bool resumeMode;

  /// Opens the manual entry route (S4-7). Provided by the route lane.
  final VoidCallback onAddManually;

  /// Opens the recovery offer (S4-5) from `blockedByJournal`.
  final VoidCallback? onReview;

  /// Opens the Settings privacy section (consent withdrawn).
  final VoidCallback? onOpenPrivacySettings;
  final VoidCallback? onBackToOffer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final flow = ref.read(gpsStartFlowProvider.notifier);
    final working = ref.watch(gpsStartFlowProvider.select((s) => s.working));
    final notifPermanent =
        ref.watch(gpsStartFlowProvider.select((s) => s.notifPermanent));

    Widget card(String id, String title, String? body, List<Widget> buttons,
            {Widget? extra}) =>
        GpsPanelCard(
          key: ValueKey<String>('gps.start.panel.$id'),
          title: title,
          body: body,
          extra: extra,
          buttons: buttons,
        );
    Widget manual() =>
        GpsButton(label: l10n.gpsAddManually, onPressed: onAddManually);

    switch (panel) {
      case GpsStartPanelId.none:
        return const SizedBox.shrink();
      case GpsStartPanelId.preprompt:
        return card('preprompt', l10n.gpsPrePromptReason, null, <Widget>[
          GpsButton(
              label: l10n.gpsContinue,
              primary: true,
              enabled: !working,
              onPressed: flow.continuePrePrompt),
          GpsButton(label: l10n.gpsNotNow, onPressed: flow.declinePrePrompt),
        ], extra: GpsBodyText(l10n.gpsPrePromptPrecise, secondary: true, size: 13));
      case GpsStartPanelId.preparing:
        // Static text, no spinner, Back only (S04-D 6).
        return card('preparing', l10n.gpsStarting, l10n.gpsPreparingBody, const <Widget>[]);
      case GpsStartPanelId.cannotStart:
        return card('cannotStart', l10n.gpsCannotStartTitle, l10n.gpsCannotStartBody,
            <Widget>[
              GpsButton(
                  label: l10n.gpsTryAgain,
                  primary: true,
                  enabled: !working,
                  onPressed: flow.tryAgain),
              manual(),
            ]);
      case GpsStartPanelId.startFailed:
        return card('startFailed', l10n.gpsStartFailedTitle, l10n.gpsStartFailedBody,
            <Widget>[
              GpsButton(
                  label: l10n.gpsTryAgain,
                  primary: true,
                  enabled: !working,
                  onPressed: flow.tryAgain),
              manual(),
            ]);
      case GpsStartPanelId.consentWithdrawn:
        return card('consentWithdrawn', l10n.gpsConsentOffTitle, l10n.gpsConsentOffBody,
            <Widget>[
              GpsButton(
                  label: l10n.gpsOpenPrivacySettings,
                  primary: true,
                  onPressed: onOpenPrivacySettings),
              manual(),
            ]);
      case GpsStartPanelId.restricted:
        // Open settings is NOT offered: settings cannot lift a restriction.
        return card('restricted', l10n.gpsRestrictedTitle, l10n.gpsRestrictedBody,
            <Widget>[manual()]);
      case GpsStartPanelId.deniedOnce:
        return card('deniedOnce', l10n.gpsDeniedOnceTitle, l10n.gpsDeniedOnceBody,
            <Widget>[
              GpsButton(
                  label: l10n.gpsTryAgain,
                  primary: true,
                  enabled: !working,
                  onPressed: flow.tryAgain),
              manual(),
            ]);
      case GpsStartPanelId.deniedForever:
        return card('deniedForever', l10n.gpsDeniedOnceTitle, l10n.gpsDeniedForeverBody,
            <Widget>[
              GpsButton(
                  label: l10n.gpsOpenSettings,
                  primary: true,
                  onPressed: flow.openSettings),
              manual(),
            ]);
      case GpsStartPanelId.approximateOnly:
        return card('approximateOnly', l10n.gpsApproxTitle, l10n.gpsApproxBody,
            <Widget>[
              GpsButton(
                  label: l10n.gpsOpenSettings,
                  primary: true,
                  onPressed: flow.openSettings),
              manual(),
            ]);
      case GpsStartPanelId.servicesOff:
        return card('servicesOff', l10n.gpsServicesOffTitle, l10n.gpsServicesOffBody,
            <Widget>[
              GpsButton(
                  label: l10n.gpsOpenLocationSettings,
                  primary: true,
                  onPressed: flow.openLocationSettings),
              manual(),
            ]);
      case GpsStartPanelId.notifOff:
        return card('notifOff', l10n.gpsNotifOffTitle, l10n.gpsNotifOffBody,
            <Widget>[
              notifPermanent
                  ? GpsButton(
                      label: l10n.gpsOpenSettings,
                      primary: true,
                      onPressed: flow.openSettings)
                  : GpsButton(
                      label: l10n.gpsAllowNotif,
                      primary: true,
                      enabled: !working,
                      onPressed: flow.allowNotifications),
              // TODO(DN-3): variant B "Record without notification"
              // (l10n.gpsRecordWithoutNotif) is not built; default is refuse.
              manual(),
            ],
            extra: GpsBodyText(l10n.gpsNotifReason, secondary: true, size: 13));
      case GpsStartPanelId.noGps:
        return card('noGps', l10n.gpsRowNoGps, l10n.gpsNoGpsBody, <Widget>[manual()]);
      case GpsStartPanelId.blockedByJournal:
        if (resumeMode) return const SizedBox.shrink();
        return card('blockedByJournal', l10n.gpsRecoveryTitle, l10n.gpsBlockedBody,
            <Widget>[
              GpsButton(label: l10n.gpsReview, primary: true, onPressed: onReview),
              manual(),
            ]);
      case GpsStartPanelId.batteryTooLow:
        return card('batteryTooLow', l10n.gpsCannotStartTitle, l10n.gpsBatteryTooLow,
            <Widget>[manual()]);
      case GpsStartPanelId.gymTimerRunning:
        return card('gymTimerRunning', l10n.gpsCannotStartTitle, l10n.gpsRowGymRunning,
            <Widget>[manual()]);
    }
  }
}

/// Muted note under the title, used for `gpsNothingRecorded`.
class GpsNoteLine extends StatelessWidget {
  const GpsNoteLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        liveRegion: false,
        child: Text(text, style: TextStyle(color: t.textSecondary, fontSize: 14)),
      ),
    );
  }
}
