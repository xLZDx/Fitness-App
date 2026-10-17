/// The visible Back control of pushed pages on Apple desktop (contract 10.8,
/// AC-KB-8; design 2.6, S03-17).
///
/// Android has the system Back button and iPhone/iPad have the edge swipe, but
/// a Mac window has neither, so every pushed page that S03 touches or frames
/// mounts this widget in its header. On any other platform it takes no space
/// at all, so the touch layouts do not change (AC-KB-7).
///
/// Key `shell.back`; a HUD button (button role) labelled with the ARB key
/// `shellBack` ("Back").
///
/// Usage by a page: `const ShellBackButton()` at the start of its header. The
/// default action pops the current page; when the page is the only route left
/// (a deep link) it goes to `/home`, exactly like the system Back would end.
library;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

import 'hud/hud_surface.dart';

/// Test and page seam for the key of the control.
const Key kShellBackKey = ValueKey<String>('shell.back');

class ShellBackButton extends StatelessWidget {
  const ShellBackButton({
    super.key,
    this.onPressed,
    this.alwaysVisible = false,
  });

  /// Replaces the default action (pop, else `/home`). Null keeps the default.
  final VoidCallback? onPressed;

  /// Shows the control on every platform. Default false: only on macOS.
  /// Tests and pages that always need a visible Back (for example a framed page
  /// in a desktop window) pass true.
  final bool alwaysVisible;

  /// Whether the control shows for [platform]: Apple desktop only.
  static bool visibleOn(TargetPlatform platform) =>
      platform == TargetPlatform.macOS;

  void _back(BuildContext context) {
    final VoidCallback? custom = onPressed;
    if (custom != null) {
      custom();
      return;
    }
    final NavigatorState? navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!alwaysVisible && !visibleOn(Theme.of(context).platform)) {
      return const SizedBox.shrink();
    }
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48),
        child: HudButton(
          key: kShellBackKey,
          label: l10n.shellBack,
          leading: const Icon(Icons.arrow_back_rounded, size: 20),
          centered: true,
          minHeight: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          showFocusRing: true,
          hoverStyle: true,
          cursor: true,
          onPressed: () => _back(context),
        ),
      ),
    );
  }
}
