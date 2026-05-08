import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';

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
            child: Icon(icon, color: Colors.white, size: 22),
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
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.65),
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
          color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
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
          gradient: selected
              ? const LinearGradient(colors: [
                  AppPalette.auroraPink,
                  AppPalette.auroraViolet,
                ])
              : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.32),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppPalette.auroraViolet.withValues(alpha: 0.30),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : theme.colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// A glass-style numeric / text input.
class GlassTextField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      initialValue: value,
      onChanged: onChanged,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: hint,
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
