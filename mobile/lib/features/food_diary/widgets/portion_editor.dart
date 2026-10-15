import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../data/food_entry.dart';
import 'food_format.dart';

/// Edits one item's portion in grams: a numeric field plus 48 dp less/more
/// buttons (non-drag alternative), and the likely range as text. Calls
/// [onChanged] only with a positive value (a collapsed range = the user's
/// exact value).
class PortionEditor extends StatefulWidget {
  const PortionEditor({
    super.key,
    required this.grams,
    required this.onChanged,
    this.step = 10,
  });

  final MacroRange grams;
  final ValueChanged<double> onChanged;
  final double step;

  @override
  State<PortionEditor> createState() => _PortionEditorState();
}

class _PortionEditorState extends State<PortionEditor> {
  late final TextEditingController _c =
      TextEditingController(text: _text(widget.grams.mid));
  bool _invalid = false;

  String _text(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  void didUpdateWidget(PortionEditor old) {
    super.didUpdateWidget(old);
    final parsed = double.tryParse(_c.text.replaceAll(',', '.'));
    if (parsed != widget.grams.mid) _c.text = _text(widget.grams.mid);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    final ok = v != null && v.isFinite && v > 0 && v <= 10000;
    setState(() => _invalid = !ok);
    if (ok) widget.onChanged(v);
  }

  void _nudge(double delta) {
    final next = widget.grams.mid + delta;
    if (next <= 0) return;
    _c.text = _text(next);
    setState(() => _invalid = false);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final g = widget.grams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: l10n.foodDetailPortionLess,
              onPressed: () => _nudge(-widget.step),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: TextField(
                controller: _c,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  labelText: l10n.foodDetailPortion,
                  errorText: _invalid ? l10n.foodDetailPortionInvalid : null,
                ),
                onChanged: _commit,
              ),
            ),
            IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              tooltip: l10n.foodDetailPortionMore,
              onPressed: () => _nudge(widget.step),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (g.high > g.low)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.foodDetailPortionRange(fmtInt(context, g.low), fmtInt(context, g.high)),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
