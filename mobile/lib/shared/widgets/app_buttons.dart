import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';

/// The app's buttons — master prompt §6.
///
/// Built from what the 54 call sites in `lib/` actually did, not from the
/// spec's noun. Three things recurred and are now the component's job:
///
/// **A loading state, hand-rolled eight times.** Every one of them repeated the
/// same three steps — null the callback, swap the label for a sized
/// `CircularProgressIndicator`, and pick its colour. Three of them picked
/// `Colors.white`, and one did so directly under a `foregroundColor:
/// onError` it therefore contradicted. [loading] does all three, and takes the
/// colour from the button's own foreground so it cannot drift again.
///
/// **A compact size, overridden seven times.** Sheets and rows wanted padding
/// 12–14 and radius 14 against the theme's 54-tall, radius-20 default, and each
/// wrote its own `styleFrom`.
///
/// **Two colour escapes.** One destructive (error/onError), one brand
/// (auroraPeach/onGradientInk). Both are now named tones rather than literals
/// at the call site.
///
/// There is deliberately **no `style` parameter**. An escape hatch would let
/// the next one-off slip past instead of surfacing as a missing tone or size —
/// which is the whole point of having the component.
enum AppButtonTone {
  /// The theme's own filled/outlined colours.
  normal,

  /// Irreversible: delete the account, discard the recording.
  destructive,

  /// Brand-coloured call to action — the aurora artwork, so its foreground is
  /// [AppSemanticColors.onGradientInk] rather than a theme colour.
  brand,
}

/// How the button sizes itself.
///
/// This is not only cosmetic. [regular] carries the theme's
/// `minimumSize: Size.fromHeight(54)`, and `Size.fromHeight` is
/// `Size(double.infinity, 54)` — a `Row` hands unbounded width to its non-flex
/// children, so a regular button placed directly in a `Row` resolves to an
/// infinite width and throws. That is not hypothetical: it crashed the
/// set-capture sheet, on the workout-logging path, until 9895c87.
///
/// [compact] sizes to its content and is safe anywhere.
enum AppButtonSize { regular, compact }

/// Filled. The screen's single most important action.
class AppPrimaryButton extends StatelessWidget {
  const AppPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.tone = AppButtonTone.normal,
    this.size = AppButtonSize.regular,
  });

  final String label;

  /// `null` disables the button. [loading] disables it too, so a call site
  /// never has to write `loading ? null : onTap` again.
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final AppButtonTone tone;
  final AppButtonSize size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      AppButtonTone.normal => (null, null),
      AppButtonTone.destructive => (scheme.error, scheme.onError),
      AppButtonTone.brand => (
          AppPalette.auroraPeach,
          AppSemanticColors.onGradientInk
        ),
    };
    final foreground = fg ?? scheme.onPrimary;

    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        padding: size.padding,
        minimumSize: size.minimumSize,
        shape: RoundedRectangleBorder(borderRadius: size.radius),
      ),
      child: _Content(
          label: label, icon: icon, loading: loading, spinner: foreground),
    );
  }
}

/// Outlined. An alternative to the primary action, not a lesser one.
class AppSecondaryButton extends StatelessWidget {
  const AppSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.size = AppButtonSize.regular,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final AppButtonSize size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: loading ? null : onPressed,
      style: OutlinedButton.styleFrom(
        padding: size.padding,
        minimumSize: size.minimumSize,
        shape: RoundedRectangleBorder(borderRadius: size.radius),
      ),
      child: _Content(
          label: label,
          icon: icon,
          loading: loading,
          spinner: scheme.onSurface),
    );
  }
}

/// Text-only. Dismiss, skip, "maybe later" — the way out of a decision.
class AppTertiaryButton extends StatelessWidget {
  const AppTertiaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton(
      onPressed: loading ? null : onPressed,
      child: _Content(
          label: label, icon: icon, loading: loading, spinner: scheme.primary),
    );
  }
}

/// Icon-only, and therefore the one that cannot skip its label.
///
/// [tooltip] is required rather than optional: an icon-only control with no
/// accessible name is invisible to a screen reader. Of the app's 12
/// `IconButton` call sites, five had no [tooltip] at all — a like toggle and
/// two weight steppers, each duplicated once. `AppIconButton` cannot repeat
/// that; there is no way to construct one without a string to announce.
///
/// [size] reuses [AppButtonSize]'s vocabulary, but a bare icon button has no
/// label to make room for, so it means something narrower here: [regular] is
/// `IconButton`'s own default footprint; [compact] tightens the touch target
/// (`VisualDensity.compact`) AND shrinks the glyph to 18 — the shape seven of
/// the twelve call sites already used, un-migrated, for inline controls sitting
/// next to text (a like count, a stepper's numeric readout) rather than
/// standing alone in an app bar.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
    this.tone = AppButtonTone.normal,
    this.size = AppButtonSize.regular,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool loading;
  final AppButtonTone tone;
  final AppButtonSize size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // `brand` has no icon-only call site today; onSurface is the correct
    // fallback rather than adding a third colour nothing asks for.
    final colour = switch (tone) {
      AppButtonTone.normal => scheme.onSurface,
      AppButtonTone.destructive => scheme.error,
      AppButtonTone.brand => scheme.onSurface,
    };
    final compact = size == AppButtonSize.compact;
    return IconButton(
      onPressed: loading ? null : onPressed,
      tooltip: tooltip,
      visualDensity: compact ? VisualDensity.compact : null,
      iconSize: compact ? 18 : null,
      color: tone == AppButtonTone.normal ? null : colour,
      icon: loading
          ? _Spinner(colour: colour, diameter: compact ? 14 : 18)
          : Icon(icon),
    );
  }
}

/// Label, optional leading icon, and the loading swap — shared so the four
/// buttons cannot drift apart in how they show the same three states.
class _Content extends StatelessWidget {
  const _Content({
    required this.label,
    required this.icon,
    required this.loading,
    required this.spinner,
  });

  final String label;
  final IconData? icon;
  final bool loading;
  final Color spinner;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Spinner(colour: spinner, diameter: 18),
          const SizedBox(width: 10),
          // The label stays. A button whose text vanishes while it works
          // leaves the user without the one clue about what is happening.
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      );
    }
    if (icon == null) return Text(label);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.colour, required this.diameter});

  final Color colour;
  final double diameter;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: diameter,
        height: diameter,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation<Color>(colour),
        ),
      );
}

extension on AppButtonSize {
  EdgeInsets get padding => switch (this) {
        AppButtonSize.regular => const EdgeInsets.symmetric(horizontal: 20),
        AppButtonSize.compact =>
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      };

  /// `null` leaves the theme's `Size.fromHeight(54)` in place. `compact`
  /// replaces it with a bounded width — see [AppButtonSize].
  Size? get minimumSize => switch (this) {
        AppButtonSize.regular => null,
        AppButtonSize.compact => const Size(0, 44),
      };

  BorderRadius get radius => switch (this) {
        AppButtonSize.regular => BorderRadius.circular(20),
        AppButtonSize.compact => BorderRadius.circular(14),
      };
}
