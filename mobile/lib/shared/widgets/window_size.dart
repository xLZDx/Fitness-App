/// The one window-size class every S03 layout decision reads (contract 10.1,
/// C-14, WS-1; design 2.6).
///
/// No screen compares raw widths: it asks [WindowSizeInfo.of] and branches on
/// [WindowSizeInfo.sizeClass], [WindowSizeInfo.isShort] or
/// [WindowSizeInfo.usesRail]. The thresholds live only in [classifyWindow].
///
/// ## Reactive, not a static lookup (RV-18b)
///
/// [WindowSizeInfo.of] registers a dependency, so a window resize or a test
/// override rebuilds only the widgets that asked. Two paths feed it:
///
///  * [WindowSizeScope] (a Riverpod consumer placed once above the router)
///    watches [windowSizeOverrideProvider] and `MediaQuery.sizeOf`, and
///    publishes the result through an `InheritedModel`. Dependants that ask for
///    one [WindowSizeAspect] are notified only when that aspect changes, so a
///    resize inside one class rebuilds nobody.
///  * Without a scope, [WindowSizeInfo.of] still depends on
///    `MediaQuery.sizeOf` (so it is live, but rebuilds on every size change)
///    and reads the override from the enclosing `ProviderScope` at build time.
///    Install [WindowSizeScope] to get the class-granular behaviour and a live
///    override.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Material 3 width classes. Lower bound inclusive: 600 is [medium], 840 is
/// [expanded].
enum WindowSizeClass { compact, medium, expanded }

/// Width below which the window is [WindowSizeClass.compact] (exclusive).
const double kWindowMediumMinWidth = 600;

/// Width from which the window is [WindowSizeClass.expanded] (inclusive).
const double kWindowExpandedMinWidth = 840;

/// Height below which the window is "short" (exclusive upper bound).
const double kWindowShortMaxHeight = 480;

/// What a layout needs to know about the window.
@immutable
class WindowSizeInfo {
  const WindowSizeInfo({
    required this.sizeClass,
    required this.isShort,
    required this.usesRail,
  });

  /// A synthetic value for tests and previews. [usesRail] follows the same
  /// rule as [classifyWindow]: expanded, or medium and short.
  factory WindowSizeInfo.forClass(
    WindowSizeClass sizeClass, {
    bool isShort = false,
  }) =>
      WindowSizeInfo(
        sizeClass: sizeClass,
        isShort: isShort,
        usesRail: _usesRail(sizeClass, isShort),
      );

  final WindowSizeClass sizeClass;

  /// Window height under 480 dp (landscape phone, small desktop window).
  final bool isShort;

  /// Rail presentation: width 840 or more, or width 600 or more when short
  /// (contract 10.1).
  final bool usesRail;

  /// The live info for [context]. See the library comment for the two paths.
  ///
  /// [aspect] narrows what the caller depends on when a [WindowSizeScope] is
  /// above; null depends on the whole value.
  static WindowSizeInfo of(BuildContext context, {WindowSizeAspect? aspect}) {
    final _WindowSizeModel? model = InheritedModel.inheritFrom<_WindowSizeModel>(
      context,
      aspect: aspect ?? WindowSizeAspect.all,
    );
    if (model != null) return model.info;
    return _fallback(context);
  }

  static WindowSizeInfo _fallback(BuildContext context) {
    final UncontrolledProviderScope? scope =
        context.getInheritedWidgetOfExactType<UncontrolledProviderScope>();
    final WindowSizeInfo? override =
        scope?.container.read(windowSizeOverrideProvider);
    // Depend on the size even when an override wins, so removing the override
    // later still produces a correct, live value.
    final Size size = MediaQuery.sizeOf(context);
    return override ?? classifyWindow(size);
  }

  @override
  bool operator ==(Object other) =>
      other is WindowSizeInfo &&
      other.sizeClass == sizeClass &&
      other.isShort == isShort &&
      other.usesRail == usesRail;

  @override
  int get hashCode => Object.hash(sizeClass, isShort, usesRail);

  @override
  String toString() =>
      'WindowSizeInfo($sizeClass, isShort: $isShort, usesRail: $usesRail)';
}

bool _usesRail(WindowSizeClass c, bool isShort) =>
    c == WindowSizeClass.expanded || (c == WindowSizeClass.medium && isShort);

/// The only place the thresholds exist. Pure: compares the unrounded logical
/// [size]; 599.5 is compact, 600 is medium, 839.5 is medium, 840 is expanded.
///
/// [textScale] is accepted for call-site symmetry but does NOT enter the class
/// (design 2.6: it only changes the rail form, measured by the rail itself).
WindowSizeInfo classifyWindow(Size size, {double textScale = 1.0}) {
  final WindowSizeClass c = size.width >= kWindowExpandedMinWidth
      ? WindowSizeClass.expanded
      : (size.width >= kWindowMediumMinWidth
          ? WindowSizeClass.medium
          : WindowSizeClass.compact);
  final bool isShort = size.height < kWindowShortMaxHeight;
  return WindowSizeInfo(
    sizeClass: c,
    isShort: isShort,
    usesRail: _usesRail(c, isShort),
  );
}

/// Test seam: null by default (the real `MediaQuery` size decides); a test sets
/// a value and every [WindowSizeInfo.of] caller sees it instead of the view.
final StateProvider<WindowSizeInfo?> windowSizeOverrideProvider =
    StateProvider<WindowSizeInfo?>((Ref ref) => null);

/// Which part of [WindowSizeInfo] a dependant cares about.
enum WindowSizeAspect { sizeClass, isShort, usesRail, all }

/// Publishes [WindowSizeInfo] to the subtree. Place it once above the router
/// (inside `ProviderScope`; it needs `MediaQuery` above it, which
/// `MaterialApp.builder` provides).
class WindowSizeScope extends ConsumerWidget {
  const WindowSizeScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WindowSizeInfo? override = ref.watch(windowSizeOverrideProvider);
    final WindowSizeInfo info =
        override ?? classifyWindow(MediaQuery.sizeOf(context));
    return _WindowSizeModel(info: info, child: child);
  }
}

class _WindowSizeModel extends InheritedModel<WindowSizeAspect> {
  const _WindowSizeModel({required this.info, required super.child});

  final WindowSizeInfo info;

  @override
  bool updateShouldNotify(_WindowSizeModel oldWidget) => info != oldWidget.info;

  @override
  bool updateShouldNotifyDependent(
    _WindowSizeModel oldWidget,
    Set<WindowSizeAspect> dependencies,
  ) {
    for (final WindowSizeAspect a in dependencies) {
      final bool changed = switch (a) {
        WindowSizeAspect.sizeClass => info.sizeClass != oldWidget.info.sizeClass,
        WindowSizeAspect.isShort => info.isShort != oldWidget.info.isShort,
        WindowSizeAspect.usesRail => info.usesRail != oldWidget.info.usesRail,
        WindowSizeAspect.all => info != oldWidget.info,
      };
      if (changed) return true;
    }
    return false;
  }
}
