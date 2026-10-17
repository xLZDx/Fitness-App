/// Consent withdrawal row S4-11 for the Settings Privacy section (S04-D 18.1,
/// S04-33, S04-R-054). Lane R9 mounts it (only when the GPS_RECORDER flag is
/// on) under the privacy-zone row. The confirmation is inline, never a dialog.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/hud/hud_metric.dart' show HudSettingRow, HudToggle;
import '../consent/location_consent.dart';
import '../consent/location_consent_providers.dart';
import 'gps_common_widgets.dart';
import 'gps_live_widgets.dart' show gpsAnnounce;

class GpsConsentRow extends ConsumerStatefulWidget {
  const GpsConsentRow({super.key, this.onOpenPrivacyText, this.onDeleteData});

  /// Opens the privacy text / where-stored statement; the link row is hidden
  /// when null.
  final VoidCallback? onOpenPrivacyText;

  /// Leads to the existing data-deletion path; hidden when null.
  final VoidCallback? onDeleteData;

  @override
  ConsumerState<GpsConsentRow> createState() => _GpsConsentRowState();
}

class _GpsConsentRowState extends ConsumerState<GpsConsentRow> {
  bool _confirming = false;
  bool _busy = false;
  final FocusNode _switchFocus = FocusNode(debugLabel: 'gps.consent.switch');

  @override
  void dispose() {
    _switchFocus.dispose();
    super.dispose();
  }

  Future<void> _withdraw() async {
    setState(() => _busy = true);
    try {
      await ref.read(locationConsentProvider.notifier).withdraw();
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
        _switchFocus.requestFocus();
      }
    }
  }

  Future<void> _grant() async {
    setState(() => _busy = true);
    try {
      await ref.read(locationConsentProvider.notifier).grant();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final consent = ref.watch(locationConsentProvider).valueOrNull ?? LocationConsent.none;
    final st = consent.recordingState;
    final record = consent.recordOf(LocationConsentPurpose.locationWhileRecording);

    final subtitle = switch (st) {
      ConsentState.granted =>
        l10n.gpsConsentOn(record?.textVersion ?? l10n.gpsConsentTextVersion),
      ConsentState.withdrawn => l10n.gpsConsentOff,
      ConsentState.none => l10n.gpsConsentNone,
    };

    // Never consented: no switch (S04-D 18.1), only the links.
    final Widget? trailing = st == ConsentState.none
        ? const SizedBox.shrink()
        : Focus(
            focusNode: _switchFocus,
            child: HudToggle(
              value: st == ConsentState.granted,
              semanticLabel: st == ConsentState.granted
                  ? l10n.gpsConsentWithdraw
                  : l10n.gpsConsentGrant,
              onChanged: _busy
                  ? null
                  : (_) {
                      if (st == ConsentState.granted) {
                        setState(() => _confirming = true);
                      } else {
                        unawaited(_grant());
                      }
                    },
            ),
          );

    return Column(
      key: const ValueKey<String>('settings.gpsConsent'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        HudSettingRow(
          icon: Icons.location_on_outlined,
          title: l10n.gpsConsentTitle,
          subtitle: subtitle,
          mergeSemantics: true,
          divider: !widget.hasLinks,
          trailing: trailing,
        ),
        if (_confirming)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GpsPanelCard(
              title: l10n.gpsConsentWithdraw,
              body: l10n.gpsConsentWithdrawConfirm,
              buttons: <Widget>[
                GpsButton(
                    label: l10n.gpsConsentWithdraw,
                    enabled: !_busy,
                    onPressed: () async {
                      await _withdraw();
                      if (mounted) {
                        // ignore: use_build_context_synchronously
                        gpsAnnounce(context, l10n.gpsConsentOff);
                      }
                    }),
                GpsButton(
                  label: l10n.gpsKeep,
                  primary: true,
                  onPressed: () {
                    setState(() => _confirming = false);
                    _switchFocus.requestFocus();
                  },
                ),
              ],
            ),
          ),
        if (widget.onOpenPrivacyText != null)
          HudSettingRow(
            icon: Icons.privacy_tip_outlined,
            title: l10n.gpsConsentLinks,
            onTap: widget.onOpenPrivacyText,
            divider: widget.onDeleteData != null,
          ),
        if (widget.onDeleteData != null)
          HudSettingRow(
            icon: Icons.delete_outline,
            title: l10n.gpsConsentDeleteData,
            onTap: widget.onDeleteData,
            divider: false,
          ),
      ],
    );
  }
}

extension on GpsConsentRow {
  bool get hasLinks => onOpenPrivacyText != null || onDeleteData != null;
}
