/// The dock host of the bar presentation (design 2.6; S03-05): position,
/// animated padding and a `RepaintBoundary`. WHAT it shows (pill or strip) is
/// decided by the caller (`MainShell`) from the L4b widgets.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/hud_tokens.dart';

/// Opens the Record sheet (S-5). The sheet belongs to lane L6; until it is
/// wired the default is null and the Record controls do nothing on tap.
typedef ShellRecordSheetOpener = void Function(BuildContext context,
    {GlobalKey? anchorKey});

/// Mount seam for the Record sheet (L6). `MainShell` reads it when the pill or
/// the rail Record slot is tapped.
final Provider<ShellRecordSheetOpener?> shellRecordSheetOpenerProvider =
    Provider<ShellRecordSheetOpener?>((Ref ref) => null);

/// Positions [child] directly above the bottom bar. Must be a child of the
/// shell body's `Stack`. Key `shell.dock`.
class ShellDock extends StatelessWidget {
  const ShellDock({
    Key? key,
    required this.bottomOffset,
    required this.child,
    this.maxWidth = double.infinity,
  }) : super(key: key ?? const ValueKey<String>('shell.dock'));

  /// Distance from the window bottom to the dock bottom.
  final double bottomOffset;

  /// Width cap (560 on Medium).
  final double maxWidth;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool reduce = MediaQuery.disableAnimationsOf(context);
    return Positioned.fill(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedPadding(
          duration: reduce ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: bottomOffset,
            left: HudTokens.navBarInset,
            right: HudTokens.navBarInset,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: SizedBox(
              width: double.infinity,
              child: RepaintBoundary(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
