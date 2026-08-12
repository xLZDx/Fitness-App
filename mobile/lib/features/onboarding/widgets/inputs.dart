import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_semantic_colors.dart';

/// The question, rendered above each step's body.
///
/// Typography traced from the design's own onboarding header
/// (`App.tsx:1215-1216`): 30pt at weight 800 with a tight 1.1 line height, and
/// the supporting line at 13pt in the secondary colour.
///
/// The gradient icon tile that used to sit to the left is gone. The design puts
/// nothing beside its onboarding titles, and the tile was a pre-R9 flourish
/// painted from `AppPalette` directly — the exact class of hardcoded artwork
/// colour the semantic-token layer exists to retire.
class StepTitle extends StatelessWidget {
  const StepTitle({
    super.key,
    required this.title,
    this.subtitle,
  });

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.1,
            color: theme.colors.textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              height: 1.5,
              color: theme.colors.textSecondary,
            ),
          ),
        ],
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

/// A full-width radio card: icon, title, supporting line, selection ring.
///
/// The design uses these wherever a screen asks ONE question with a handful of
/// answers that each need a sentence of explanation (`App.tsx:1290-1332`) —
/// "Набрать мышечную массу / Рост силы и объёма" reads as a choice; the same
/// text squeezed into a chip reads as a tag.
///
/// Chips are still right for multi-select and for short answers; this is not
/// their replacement. Deferred out of O1 deliberately, until a screen actually
/// needed one — a shared widget with no consumer is a guess about what the
/// second consumer will want.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // `selected` carries the answer, and colour is the only thing that says so.
    // Without this a screen reader reads a list of sentences with no indication
    // that any of them is pressable or that one is already chosen.
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? AppPalette.auroraLime.withValues(alpha: 0.16)
                : theme.colors.surfaceInteractive,
            border: Border.all(
              color: selected ? AppPalette.auroraLime : theme.colors.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 22,
                  color: selected
                      ? AppPalette.auroraLimeDeep
                      : theme.colors.textSecondary,
                ),
                const SizedBox(width: 14),
              ],
              // Flexible, not fixed: these titles are questionnaire answers and
              // the Russian ones are the longest strings in the flow. A row
              // that cannot shrink is the `/scan` overflow again.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: theme.colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // The ring reads as "chosen" without relying on the fill colour,
              // which matters for anyone who cannot separate the lime tint from
              // the muted surface behind it.
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected
                    ? AppPalette.auroraLimeDeep
                    : theme.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
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
    // Выбранность здесь несёт только градиент. Для скринридера пилюля была
    // просто текстом: ни что по ней можно нажать, ни какая из них выбрана —
    // а это единственный способ ответить на вопрос анкеты.
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
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
