/// The sign-out sheets of S03-16 (design 2.5, 6.9; contract S-10, J10): the
/// warning for activities stored only on this device, the "cannot check" sheet,
/// the second confirmation of the deletion and the error sheet. Each is one
/// centred dialog through [AdaptiveSurface] (`AdaptiveSurfaceKind.dialog`) and
/// completes with the user's choice; a dismissal (scrim, Esc, system Back) is
/// [SignOutChoice.cancel]. The sheets only ask; the guard in
/// `state/sign_out_guard.dart` acts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/adaptive_surface.dart';
import '../../../shared/widgets/hud/hud_surface.dart';

/// What the user picked in a sign-out sheet.
enum SignOutChoice {
  /// Warning sheet: export the activities first.
  exportFirst,

  /// Warning sheet: sign out and delete from this device (needs the second
  /// confirmation).
  signOutAndDelete,

  /// Warning sheet: sign out and keep the data on this device.
  signOutKeep,

  /// Cannot-check sheet: retry the journal bind.
  tryAgain,

  /// Cannot-check sheet: sign out without checking.
  anyway,

  /// Confirmation sheet: delete now.
  confirmDelete,

  /// Error sheet: run the failed step again.
  retry,

  /// Cancel or dismissal.
  cancel,
}

Future<SignOutChoice> _show(
  BuildContext context,
  String semanticLabel,
  Widget Function(BuildContext) builder,
) async {
  final SignOutChoice? choice = await AdaptiveSurface.show<SignOutChoice>(
    context,
    builder,
    kind: AdaptiveSurfaceKind.dialog,
    semanticLabel: semanticLabel,
  );
  return choice ?? SignOutChoice.cancel;
}

/// The sheet shown for a non-empty open journal ("You have n activities stored
/// only on this device").
Future<SignOutChoice> showSignOutWarningSheet(
  BuildContext context, {
  required int count,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String title = l10n.signOutWarningTitle(count);
  return _show(
    context,
    title,
    (BuildContext ctx) => _SheetFrame(
      title: title,
      actions: <_Action>[
        _Action(
          const Key('signOut.exportFirst'),
          l10n.signOutExportFirst,
          SignOutChoice.exportFirst,
          HudButtonTone.accent,
        ),
        _Action(
          const Key('signOut.andDelete'),
          l10n.signOutAndDelete,
          SignOutChoice.signOutAndDelete,
        ),
        _Action(
          const Key('signOut.keep'),
          l10n.signOutPlain,
          SignOutChoice.signOutKeep,
        ),
        _Action(
          const Key('signOut.cancel'),
          l10n.signOutCancel,
          SignOutChoice.cancel,
        ),
      ],
    ),
  );
}

/// The sheet shown when the journal cannot be checked (F-42). Try again is
/// offered only when [canRetry].
Future<SignOutChoice> showSignOutCannotCheckSheet(
  BuildContext context, {
  required bool canRetry,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String title = l10n.signOutCannotCheckTitle;
  return _show(
    context,
    title,
    (BuildContext ctx) => _SheetFrame(
      title: title,
      body: l10n.signOutCannotCheckBody,
      actions: <_Action>[
        if (canRetry)
          _Action(
            const Key('signOut.tryAgain'),
            l10n.activityJournalRetry,
            SignOutChoice.tryAgain,
            HudButtonTone.accent,
          ),
        _Action(
          const Key('signOut.anyway'),
          l10n.signOutAnyway,
          SignOutChoice.anyway,
        ),
        _Action(
          const Key('signOut.cancel'),
          l10n.signOutCancel,
          SignOutChoice.cancel,
        ),
      ],
    ),
  );
}

/// The second confirmation; nothing is deleted before the user picks
/// [SignOutChoice.confirmDelete].
Future<SignOutChoice> showSignOutConfirmDeleteSheet(
  BuildContext context, {
  required int count,
}) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String title = l10n.signOutConfirmDelete(count);
  return _show(
    context,
    title,
    (BuildContext ctx) => _SheetFrame(
      title: title,
      actions: <_Action>[
        _Action(
          const Key('signOut.confirmDelete'),
          l10n.signOutAndDelete,
          SignOutChoice.confirmDelete,
        ),
        _Action(
          const Key('signOut.cancel'),
          l10n.signOutCancel,
          SignOutChoice.cancel,
          HudButtonTone.accent,
        ),
      ],
    ),
  );
}

/// The error sheet of a failed export or deletion; the user is still signed in.
Future<SignOutChoice> showSignOutErrorSheet(BuildContext context) {
  final AppLocalizations l10n = AppLocalizations.of(context);
  final String title = l10n.signOutErrorTitle;
  return _show(
    context,
    title,
    (BuildContext ctx) => _SheetFrame(
      title: title,
      actions: <_Action>[
        _Action(
          const Key('signOut.retry'),
          l10n.commonRetry,
          SignOutChoice.retry,
          HudButtonTone.accent,
        ),
        _Action(
          const Key('signOut.cancel'),
          l10n.signOutCancel,
          SignOutChoice.cancel,
        ),
      ],
    ),
  );
}

class _Action {
  const _Action(this.key, this.label, this.choice,
      [this.tone = HudButtonTone.glass]);

  final Key key;
  final String label;
  final SignOutChoice choice;
  final HudButtonTone tone;
}

/// Title (header, first focus), optional body and a column of buttons. It
/// scrolls itself: the surface gives bounded constraints.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.actions, this.body});

  final String title;
  final String? body;
  final List<_Action> actions;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final String? bodyText = body;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Focus(
            autofocus: true,
            child: Semantics(
              header: true,
              child: Text(title, style: HudType.panelHeading(t)),
            ),
          ),
          if (bodyText != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(bodyText, style: HudType.body(t, size: 12.5)),
          ],
          const SizedBox(height: 16),
          for (final _Action a in actions) ...<Widget>[
            HudButton(
              key: a.key,
              label: a.label,
              tone: a.tone,
              centered: true,
              showFocusRing: true,
              hoverStyle: true,
              cursor: true,
              onPressed: () => Navigator.of(context).pop(a.choice),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
