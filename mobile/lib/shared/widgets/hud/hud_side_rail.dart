/// The side navigation rail (C-13, contract 10.4; S03-05).
///
/// Built from the same [HudNavItem] list as the bottom bar. A pinned Record
/// slot sits on top; the destinations below scroll if they do not fit. The
/// form (96 dp compact / 240 dp extended) is chosen by the caller through
/// `railLabelMeasurerProvider`; this widget only draws what it is told.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import 'hud_scaffold.dart' show HudNavItem;
import 'hud_surface.dart';

class HudSideRail extends StatefulWidget {
  const HudSideRail({
    Key? key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.recordSlot,
    required this.semanticsLabel,
    this.extended = false,
    this.shortWindow = false,
    this.focusNodes,
  }) : super(key: key ?? const ValueKey<String>('shell.rail'));

  /// Destination focus nodes owned by the caller (the shell), so focus
  /// survives a rail-to-bar layout switch. Null: the rail owns its own nodes.
  final List<FocusNode>? focusNodes;

  final List<HudNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// The pinned Record slot (`RailRecordSlot`, or a placeholder).
  final Widget recordSlot;

  /// Label of the container node ("Main navigation").
  final String semanticsLabel;

  /// 240 dp form: icon and label in one row.
  final bool extended;

  /// Window height under 480 dp: destinations are 48 dp instead of 56.
  final bool shortWindow;

  @override
  State<HudSideRail> createState() => _HudSideRailState();
}

class _HudSideRailState extends State<HudSideRail> {
  late List<FocusNode> _nodes;
  bool _ownsNodes = true;

  @override
  void initState() {
    super.initState();
    _ownsNodes = widget.focusNodes == null;
    _nodes = widget.focusNodes ?? _makeNodes(widget.items.length);
  }

  List<FocusNode> _makeNodes(int n) => <FocusNode>[
        for (int i = 0; i < n; i++) FocusNode(debugLabel: 'shell.rail.item.$i'),
      ];

  @override
  void didUpdateWidget(HudSideRail old) {
    super.didUpdateWidget(old);
    if (!identical(old.focusNodes, widget.focusNodes) ||
        old.items.length != widget.items.length) {
      if (_ownsNodes) {
        for (final FocusNode n in _nodes) {
          n.dispose();
        }
      }
      _ownsNodes = widget.focusNodes == null;
      _nodes = widget.focusNodes ?? _makeNodes(widget.items.length);
    }
  }

  @override
  void dispose() {
    if (_ownsNodes) {
      for (final FocusNode n in _nodes) {
        n.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final double itemHeight = widget.shortWindow ? 48 : 56;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticsLabel,
      child: HudSurface(
        glass: t.navBar,
        borderRadius: BorderRadius.circular(HudTokens.radiusDevice),
        child: FocusTraversalGroup(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                child: widget.recordSlot,
              ),
              Expanded(
                // Home and End act only while focus is inside the rail.
                child: CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.home): () {
                      if (_nodes.isNotEmpty) _nodes.first.requestFocus();
                    },
                    const SingleActivator(LogicalKeyboardKey.end): () {
                      if (_nodes.isNotEmpty) _nodes.last.requestFocus();
                    },
                  },
                  child: SingleChildScrollView(
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < widget.items.length; i++)
                          _RailTile(
                            item: widget.items[i],
                            selected: i == widget.selectedIndex,
                            extended: widget.extended,
                            height: itemHeight,
                            focusNode: _nodes[i],
                            onTap: () => widget.onSelect(i),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.item,
    required this.selected,
    required this.extended,
    required this.height,
    required this.focusNode,
    required this.onTap,
  });

  final HudNavItem item;
  final bool selected;
  final bool extended;
  final double height;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    // Text-secondary tier when idle (not the bar's literal ink, contract 10.4
    // contrast), text-primary when selected.
    final Color ink = selected ? t.textPrimary : t.textSecondary;
    final Widget dot = Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? t.accent : Colors.transparent,
      ),
    );
    final TextStyle style = extended
        ? HudType.label(t, size: 11, em: 0.08, color: ink)
        : HudType.navLabel(t, color: ink);
    // Never truncated in the rail: no ellipsis, no wrapping.
    final Text label = Text(
      item.label.toUpperCase(),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textAlign: extended ? TextAlign.start : TextAlign.center,
      style: style,
    );

    final Widget body = extended
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                Icon(item.icon, size: 20, color: ink),
                const SizedBox(width: 12),
                Expanded(child: label),
                dot,
              ],
            ),
          )
        : Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(item.icon, size: 20, color: ink),
                  const SizedBox(height: 4),
                  label,
                ],
              ),
              Positioned(bottom: 3, child: dot),
            ],
          );

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: HudKeyboardActivation(
          onActivate: onTap,
          handlesKeys: false,
          showFocusRing: true,
          borderRadius: BorderRadius.circular(22),
          child: InkResponse(
            focusNode: focusNode,
            onTap: onTap,
            containedInkWell: true,
            highlightShape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(22),
            onFocusChange: (bool focused) {
              if (focused && context.mounted) {
                Scrollable.ensureVisible(context,
                    alignment: 0.5, duration: Duration.zero);
              }
            },
            child: ExcludeSemantics(child: body),
          ),
        ),
      ),
    );
  }
}
