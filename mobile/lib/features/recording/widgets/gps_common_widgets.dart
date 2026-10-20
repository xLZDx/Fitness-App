/// Small shared building blocks of the GPS recording screens (S04-D 15):
/// the screen frame, a visible Back control, the panel card with a focus-taking
/// header, and the standard button. No new colour, blur or type family: only
/// the S03 HUD primitives and tokens (S04-D principle 1).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_scaffold.dart' show HudScreenTitle;
import '../../../shared/widgets/hud/hud_surface.dart';

/// Keys of the S4 screens (AC-D4 ids map to these).
const Key kGpsBackKey = ValueKey<String>('gps.back');

/// Content width cap on wide windows (S04-D 11, 19: centred at 640 dp).
const double kGpsMaxContentWidth = 640;

/// The frame of every S4 screen: transparent scaffold, safe area, a centred
/// column capped at [kGpsMaxContentWidth], an optional pinned [bottom].
class GpsScreenFrame extends StatelessWidget {
  const GpsScreenFrame({
    super.key,
    required this.body,
    this.bottom,
    this.title,
    this.back,
    this.scaffoldKey,
  });

  /// Scrolling content (already a scrollable or a column of children).
  final List<Widget> body;

  /// Controls pinned under the scrolling body (null: none).
  final Widget? bottom;

  /// Screen title (a header node) shown under the Back control.
  final String? title;

  /// The Back control; null shows none.
  final Widget? back;
  final Key? scaffoldKey;

  @override
  Widget build(BuildContext context) {
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (back != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Align(alignment: AlignmentDirectional.centerStart, child: back),
          ),
        if (title != null)
          Semantics(header: true, child: HudScreenTitle(title!)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: body,
          ),
        ),
        if (bottom != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: bottom,
          ),
      ],
    );
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kGpsMaxContentWidth),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// A visible Back control (48 dp, focus ring). The recording screen passes
/// `gpsBackLabel` as the spoken name (S04-D 8.1).
class GpsBackButton extends StatelessWidget {
  const GpsBackButton({super.key, required this.onPressed, this.spokenLabel});

  final VoidCallback onPressed;
  final String? spokenLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final button = HudButton(
      key: kGpsBackKey,
      label: l10n.shellBack,
      leading: const Icon(Icons.arrow_back_rounded, size: 20),
      centered: true,
      minHeight: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      showFocusRing: true,
      hoverStyle: true,
      cursor: true,
      onPressed: onPressed,
    );
    if (spokenLabel == null) return button;
    return Semantics(
      container: true,
      button: true,
      label: spokenLabel,
      onTap: onPressed,
      child: ExcludeSemantics(child: button),
    );
  }
}

/// A standard S4 button: centred label, focus ring, hover and cursor on.
class GpsButton extends StatelessWidget {
  const GpsButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.enabled = true,
    this.semanticHint,
    this.minHeight = 56,
    this.minWidth,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool enabled;
  final String? semanticHint;
  final double minHeight;
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final bool live = enabled && onPressed != null;
    final button = HudButton(
      label: label,
      centered: true,
      wrap: true,
      tone: primary ? HudButtonTone.accent : HudButtonTone.glass,
      enabled: live,
      minHeight: minHeight,
      semanticHint: semanticHint,
      showFocusRing: true,
      hoverStyle: true,
      cursor: true,
      onPressed: live ? onPressed : null,
    );
    if (minWidth == null) return button;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth!),
      child: button,
    );
  }
}

/// An inline panel (never a dialog): header that takes focus when it appears,
/// body text, then up to three buttons stacked in visible order.
class GpsPanelCard extends StatelessWidget {
  const GpsPanelCard({
    super.key,
    required this.title,
    this.body,
    this.buttons = const <Widget>[],
    this.autofocus = true,
    this.extra,
    this.headerFocusNode,
  });

  final String title;
  final String? body;
  final List<Widget> buttons;
  final Widget? extra;

  /// Moves focus to the header when the panel appears (S04-D 6, 15).
  final bool autofocus;
  final FocusNode? headerFocusNode;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return HudPanel(
      dense: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Focus(
            autofocus: autofocus,
            focusNode: headerFocusNode,
            canRequestFocus: true,
            child: Semantics(
              header: true,
              focusable: true,
              child: Text(title, style: HudType.panelHeading(t)),
            ),
          ),
          if (body != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(body!, style: HudType.body(t, size: 14)),
          ],
          if (extra != null) ...<Widget>[const SizedBox(height: 8), extra!],
          for (final b in buttons) ...<Widget>[const SizedBox(height: 10), b],
        ],
      ),
    );
  }
}

/// A plain text line in the screen body.
class GpsBodyText extends StatelessWidget {
  const GpsBodyText(this.text, {super.key, this.secondary = false, this.size = 14});

  final String text;
  final bool secondary;
  final double size;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final style = HudType.body(t, size: size);
    return Text(
      text,
      style: secondary ? style.copyWith(color: t.textSecondary) : style,
    );
  }
}
