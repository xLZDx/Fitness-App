import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../data/check_these.dart';
import 'food_format.dart';

/// The "Check these" chips of an entry (design s17.10, a11y F13).
///
/// Every chip carries a text state ("Needs checking" / "Checked") plus an icon,
/// so state never rides on colour alone; the count is announced ONCE when the
/// list first appears; tapping a chip calls [onTap] (which opens the
/// resolution sheet), and after a chip becomes resolved focus moves to the
/// next unresolved chip, or to the heading when none is left.
class CheckTheseChips extends StatefulWidget {
  const CheckTheseChips({super.key, required this.items, required this.onTap});

  final List<CheckItem> items;
  final ValueChanged<CheckItem> onTap;

  @override
  State<CheckTheseChips> createState() => _CheckTheseChipsState();
}

class _CheckTheseChipsState extends State<CheckTheseChips> {
  final FocusNode _heading = FocusNode(debugLabel: 'check.heading');
  final Map<CheckCode, FocusNode> _nodes = {};
  bool _announced = false;

  FocusNode _node(CheckCode c) =>
      _nodes.putIfAbsent(c, () => FocusNode(debugLabel: 'check.${c.name}'));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_announced) return;
    final open = CheckThese.unresolved(widget.items).length;
    if (open > 0) {
      _announced = true;
      final l10n = AppLocalizations.of(context);
      final dir = Directionality.of(context);
      final text = l10n.foodCheckCount(open);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        SemanticsService.announce(text, dir);
      });
    }
  }

  @override
  void didUpdateWidget(CheckTheseChips old) {
    super.didUpdateWidget(old);
    final was = CheckThese.unresolved(old.items).length;
    final now = CheckThese.unresolved(widget.items);
    if (now.length < was) {
      final target = now.isEmpty ? _heading : _node(now.first.code);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) target.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _heading.dispose();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          focusNode: _heading,
          child: Semantics(
            header: true,
            child: Text(l10n.foodCheckHeading, style: theme.textTheme.titleSmall),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in widget.items)
              _Chip(
                item: item,
                focusNode: _node(item.code),
                onTap: () => widget.onTap(item),
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.item, required this.focusNode, required this.onTap});

  final CheckItem item;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = checkTitle(l10n, item.code);
    final state = item.resolved ? l10n.foodCheckDone : l10n.foodCheckNeeds;
    return Semantics(
      button: true,
      label: l10n.foodCheckChipLabel(title, state),
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: ActionChip(
          focusNode: focusNode,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          avatar: Icon(
            item.resolved ? Icons.check_circle_outline : Icons.help_outline,
            size: 18,
          ),
          label: Text('$title - $state'),
          onPressed: onTap,
        ),
      ),
    );
  }
}
