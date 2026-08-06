import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_semantic_colors.dart';

class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<GlassNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = Colors.white.withValues(alpha: isDark ? 0.10 : 0.55);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(34),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.06),
              blurRadius: 40,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
            child: Container(
              height: 72,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(34),
              ),
              child: LayoutBuilder(builder: (context, constraints) {
                final segWidth = constraints.maxWidth / items.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                      left: selectedIndex * segWidth + 10,
                      top: 8,
                      bottom: 8,
                      width: segWidth - 20,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: items[selectedIndex].gradient,
                          ),
                          borderRadius: BorderRadius.circular(26),
                          boxShadow: [
                            BoxShadow(
                              color: items[selectedIndex].gradient.last
                                  .withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(items.length, (i) {
                        final selected = i == selectedIndex;
                        final item = items[i];
                        return Expanded(
                          child: InkResponse(
                            onTap: () => onSelect(i),
                            radius: 40,
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 240),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: selected
                                    ? AppSemanticColors.onGradientInk
                                    : context.colors.textSecondary,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 240),
                                    child: Icon(
                                      selected
                                          ? item.iconSelected
                                          : item.icon,
                                      key: ValueKey(selected),
                                      size: 24,
                                      color: selected
                                          ? AppSemanticColors.onGradientInk
                                          : context.colors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(item.label),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class GlassNavItem {
  const GlassNavItem({
    required this.icon,
    required this.iconSelected,
    required this.label,
    required this.gradient,
  });

  final IconData icon;
  final IconData iconSelected;
  final String label;
  final List<Color> gradient;
}
