import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';

/// Section title rendered above each step's body. Optional [icon] and
/// [iconGradient] render a small gradient tile to the left.
class StepTitle extends StatelessWidget {
  const StepTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconGradient,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Color>? iconGradient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: iconGradient ??
                    [AppPalette.auroraPink, AppPalette.auroraViolet],
              ),
              boxShadow: [
                BoxShadow(
                  color: (iconGradient?.last ?? AppPalette.auroraViolet)
                      .withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: AppSemanticColors.onGradientInk, size: 22),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Field-level label, used above an input.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colors.textSecondary,
        ),
      ),
    );
  }
}

/// Multi-line tag-style chip selector, single-select.
class SingleChoiceChips<T> extends StatelessWidget {
  const SingleChoiceChips({
    super.key,
    required this.options,
    required this.labelOf,
    required this.value,
    required this.onChanged,
  });

  final List<T> options;
  final String Function(T) labelOf;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final opt in options)
          _ChoicePill(
            label: labelOf(opt),
            selected: value == opt,
            onTap: () => onChanged(opt),
          ),
      ],
    );
  }
}

/// Multi-select variant of the chip selector.
class MultiChoiceChips<T> extends StatelessWidget {
  const MultiChoiceChips({
    super.key,
    required this.options,
    required this.labelOf,
    required this.values,
    required this.onChanged,
  });

  final List<T> options;
  final String Function(T) labelOf;
  final Set<T> values;
  final ValueChanged<Set<T>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final opt in options)
          _ChoicePill(
            label: labelOf(opt),
            selected: values.contains(opt),
            onTap: () {
              final next = {...values};
              if (!next.add(opt)) next.remove(opt);
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          // R9: the "selected" indicator, one colour everywhere a pill is
          // chosen -- moved off the pre-R9 pink/violet pair onto lime.
          gradient: selected
              ? const LinearGradient(colors: [
                  AppPalette.auroraLime,
                  AppPalette.auroraLimeDeep,
                ])
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.32),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppPalette.auroraLime.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? AppSemanticColors.onGradientInk
                : theme.colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// A glass-style numeric / text input.
///
/// Owns a [TextEditingController] rather than using `TextFormField`'s
/// `initialValue` -- `initialValue` is read once in `initState` and never
/// again, so a [value] that changes for a reason other than this field's own
/// [onChanged] (the onboarding draft rehydrating from a cached profile once
/// `authUserProvider` resolves, `questionnaire_notifier.dart:16-23`) left the
/// field showing stale or blank text while the provider already held the
/// real answer.
class GlassTextField extends StatefulWidget {
  const GlassTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  State<GlassTextField> createState() => _GlassTextFieldState();
}

class _GlassTextFieldState extends State<GlassTextField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant GlassTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the two disagree: overwriting the controller on every
    // rebuild -- including the one this field's own onChanged just
    // triggered -- would reset the cursor to the end on every keystroke.
    if (widget.value != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: _controller,
      onChanged: widget.onChanged,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: widget.hint,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.40),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
            width: 1.4,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
