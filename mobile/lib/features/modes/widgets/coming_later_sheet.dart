/// The Coming-later sheet (design 2.3, 6.2; contract S-1, S-3; S03-10).
///
/// Opened through [AdaptiveSurface] as a dialog-kind surface (bottom sheet on
/// Compact, centred dialog on Medium and up). It NEVER writes anything: it only
/// reports whether the user asked for "Choose Train for now"; the caller (the
/// chooser or the switcher) then applies that choice through its own path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/adaptive_surface.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../data/mode_models.dart';

bool _comingLaterOpen = false;

/// Opens the Coming-later sheet for [mode] (ride or explore). One instance at a
/// time: a second call while it is open returns false at once. Completes with
/// true only when the user tapped "Choose Train for now"; dismissal (scrim,
/// Back, Esc) completes with false. Writes nothing.
Future<bool> showComingLaterSheet(BuildContext context, AppMode mode) async {
  if (_comingLaterOpen) return false;
  _comingLaterOpen = true;
  try {
    final String label =
        AppLocalizations.of(context).modeComingLaterSheetTitle(mode.name);
    final bool? chose = await AdaptiveSurface.show<bool>(
      context,
      (BuildContext ctx) => ComingLaterSheet(mode: mode),
      kind: AdaptiveSurfaceKind.dialog,
      semanticLabel: label,
    );
    return chose == true;
  } finally {
    _comingLaterOpen = false;
  }
}

class ComingLaterSheet extends StatelessWidget {
  const ComingLaterSheet({super.key, required this.mode});

  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          key: const Key('comingLater.sheet'),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Focus(
                autofocus: true,
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.modeComingLaterSheetTitle(mode.name),
                    key: const Key('comingLater.title'),
                    style: HudType.rowTitle(t, strong: true)
                        .copyWith(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.modeComingLaterSheetBody,
                key: const Key('comingLater.body'),
                style: HudType.body(t, size: 13),
              ),
              const SizedBox(height: 20),
              HudButton(
                key: const Key('comingLater.chooseTrain'),
                label: l10n.modeComingLaterSheetAction,
                tone: HudButtonTone.accent,
                centered: true,
                wrap: true,
                showFocusRing: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 8),
              HudButton(
                key: const Key('comingLater.back'),
                label: l10n.commonBack,
                centered: true,
                wrap: true,
                showFocusRing: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
