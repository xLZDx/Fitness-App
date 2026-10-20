/// The Home lens: which order the existing Home sections appear in for the
/// selected mode, and which pane each belongs to in the wide layout (design 2.4,
/// 3.3, 6.6; contract S-6 and 10.5; AC-HM-1, AC-HM-2, AC-LS-1, AC-LS-2).
///
/// Pure Dart over plain section names, so the tests compare lists, not pixels.
/// The lens only REORDERS; every lens returns the same set of names (nothing is
/// removed). The names are the suffixes of the stable `home.section.<name>`
/// keys that `HomePage` puts on its existing children.
library;

import '../../modes/data/mode_models.dart' show AppMode;
import '../../modes/widgets/mode_question_plan.dart'
    show kBodyStartFood;

/// Stable section names (the suffix of `home.section.<name>`).
abstract final class HomeSection {
  static const String greeting = 'greeting';
  static const String identity = 'identity';
  static const String dayPanel = 'dayPanel';
  static const String week = 'week';
  static const String recovery = 'recovery';
  static const String quickScan = 'quickScan';
  static const String bodyScan = 'bodyScan';
  static const String nutrition = 'nutrition';
  static const String deload = 'deload';
  static const String summary = 'summary';
  static const String upcoming = 'upcoming';
  static const String more = 'more';
  static const String suggestions = 'suggestions';
}

/// Pre-S03 order of the Home children (the TRAIN lens, unchanged).
const List<String> kHomeTrainSectionOrder = <String>[
  HomeSection.greeting,
  HomeSection.identity,
  HomeSection.dayPanel,
  HomeSection.week,
  HomeSection.recovery,
  HomeSection.quickScan,
  HomeSection.bodyScan,
  HomeSection.nutrition,
  HomeSection.deload,
  HomeSection.summary,
  HomeSection.upcoming,
  HomeSection.more,
  HomeSection.suggestions,
];

/// The lenses. Ride and Explore are "coming later" and use the TRAIN lens.
enum HomeLens { train, body }

/// The lens of [mode].
HomeLens homeLensOf(AppMode mode) =>
    mode == AppMode.body ? HomeLens.body : HomeLens.train;

/// The section names in single-column (Compact) order for [lens].
///
/// BODY: the body-scan and nutrition cards sit directly under the day panel and
/// the gym quick-scan row and the gym suggestions move below "More". When the
/// stored BODY answer is [kBodyStartFood] the nutrition card comes first,
/// otherwise the body-scan card does. Global panels keep their place.
List<String> homeSectionOrder(HomeLens lens, {String? bodyStart}) {
  if (lens == HomeLens.train) return kHomeTrainSectionOrder;
  final bool foodFirst = bodyStart == kBodyStartFood;
  const Set<String> moved = <String>{
    HomeSection.bodyScan,
    HomeSection.nutrition,
    HomeSection.quickScan,
    HomeSection.suggestions,
  };
  final List<String> out = <String>[];
  for (final String name in kHomeTrainSectionOrder) {
    if (moved.contains(name)) continue;
    out.add(name);
    if (name == HomeSection.dayPanel) {
      out
        ..add(foodFirst ? HomeSection.nutrition : HomeSection.bodyScan)
        ..add(foodFirst ? HomeSection.bodyScan : HomeSection.nutrition);
    }
  }
  out
    ..add(HomeSection.quickScan)
    ..add(HomeSection.suggestions);
  return out;
}

/// The two panes of the wide layout (contract 10.5).
enum HomePane { main, side }

/// The pane of [section] in the wide layout. Within a pane the order is the one
/// of [homeSectionOrder]; the reading order is the main pane, then the side pane.
HomePane homePaneOf(String section, HomeLens lens) {
  switch (section) {
    case HomeSection.greeting:
    case HomeSection.identity:
    case HomeSection.dayPanel:
    case HomeSection.week:
    case HomeSection.deload:
      return HomePane.main;
    case HomeSection.bodyScan:
    case HomeSection.nutrition:
      return lens == HomeLens.body ? HomePane.main : HomePane.side;
    default:
      return HomePane.side;
  }
}

/// Content-pane width from which Home uses two panes (dp).
const double kHomeTwoPaneMinWidth = 880;

/// Fixed width of the side pane (dp).
const double kHomeSidePaneWidth = 340;

/// Gap between the panes (dp).
const double kHomePaneGap = 16;

/// Max content width of the single-column layout (dp).
const double kHomeSingleColumnMaxWidth = 640;

/// Max content width of the two-pane layout (dp).
const double kHomeTwoPaneMaxWidth = 1120;
