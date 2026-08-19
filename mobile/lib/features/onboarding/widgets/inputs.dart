import 'package:flutter/material.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_surface.dart';

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
    final HudTokens t = context.hud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: HudType.heroTitle(t).copyWith(fontSize: 26).overPhoto(t)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: HudType.body(t, size: 13).overPhoto(t)),
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
    final HudTokens t = context.hud;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(label, style: HudType.label(t, size: 11).overPhoto(t)),
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
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final opt in options)
          HudChip(
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
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final opt in options)
          HudChip(
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
    final HudTokens t = context.hud;
    final Color ink = selected ? t.accent : t.textSecondary;
    // `selected` carries the answer, and colour is the only thing that says so.
    // Without this a screen reader reads a list of sentences with no indication
    // that any of them is pressable or that one is already chosen.
    return Semantics(
      button: true,
      selected: selected,
      child: HudKeyboardActivation(
        onActivate: onTap,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: HudTokens.minTapTarget),
            child: HudSurface(
              // `subPanel` is the lightest glass tier — right for a row inside a
              // step's content rather than a whole-screen card. Selection reuses
              // the same accent recipe `HudChip` already carries (gradient wash
              // plus a matching hairline) rather than a bespoke lime-alpha fill,
              // so "selected" reads identically everywhere the app says it.
              glass: t.subPanel,
              overlay: selected ? t.accentChipGradient : null,
              border: selected ? t.accentChipBorder : null,
              topHighlight: selected ? t.accentChipTopHighlight : null,
              borderRadius: BorderRadius.circular(18),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              // No `ExcludeSemantics` here: the outer `Semantics(button:
              // true, selected: ...)` carries no `label` of its own, so
              // excluding the child would announce a selectable button with
              // no text at all. Left to merge naturally, a screen reader
              // reads title, subtitle and the selected state together —
              // exactly what this row shows.
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 22, color: ink),
                    const SizedBox(width: 14),
                  ],
                  // Flexible, not fixed: these titles are questionnaire
                  // answers and the Russian ones are the longest strings in
                  // the flow. A row that cannot shrink is the `/scan`
                  // overflow again.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title, style: HudType.rowTitle(t, strong: true)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: HudType.body(t, size: 12)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // The ring reads as "chosen" without relying on the fill
                  // colour, which matters for anyone who cannot separate the
                  // accent tint from the muted surface behind it.
                  Icon(
                    selected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: ink,
                  ),
                ],
              ),
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
    final HudTokens t = context.hud;
    return TextFormField(
      controller: _controller,
      onChanged: widget.onChanged,
      keyboardType: widget.keyboardType,
      maxLines: widget.maxLines,
      style: HudType.body(t, size: 15).copyWith(color: t.textPrimary),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: HudType.body(t, size: 15).copyWith(color: t.textTertiary),
        filled: true,
        fillColor: t.subPanel.fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: t.subPanel.innerBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: t.subPanel.innerBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: t.accent.withValues(alpha: 0.60), width: 1.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
