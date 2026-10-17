/// Pure layout arithmetic of the mode chooser (design 2.3, contract 10.5
/// "Grid rule"; AC-CH-9 to AC-CH-12).
///
/// The number of columns is decided by the AVAILABLE GRID WIDTH, never by the
/// window height alone: 4x1 only on a short window whose grid is wide enough for
/// four cards at the floor width, otherwise 2x2 and the page scrolls vertically.
library;

import '../../../shared/widgets/window_size.dart';

/// Gap between cards, dp.
const double kChooserGap = 12;

/// Side padding of the page, dp.
const double kChooserSidePadding = 16;

/// Card width floor in every grid except the Medium 2x2 grid, dp.
const double kChooserCardMinWidth = 136;

/// Grid width from which a short window may use a 4x1 grid:
/// 4 x 136 + 3 x 12 = 580 dp.
const double kChooserShortGridMinWidth =
    4 * kChooserCardMinWidth + 3 * kChooserGap;

/// Content width cap on Medium, dp.
const double kChooserMediumMaxWidth = 640;

/// Content width cap on Expanded (grid pane plus detail panel), dp.
const double kChooserExpandedMaxWidth = 960;

/// Width of the Expanded detail panel, dp.
const double kChooserDetailPanelWidth = 320;

/// Gap between the grid pane and the detail panel on Expanded, dp.
const double kChooserPaneGap = 16;

/// Below this card width a 4x1 card drops its blurb, dp.
const double kChooserBlurbDropWidth = 150;

/// The column count of the Compact and Medium grid for a grid [gridWidth] wide.
///
/// 4 only when [isShort] AND [gridWidth] is at least 580 dp; otherwise 2.
int chooserGridColumns(double gridWidth, bool isShort) =>
    (isShort && gridWidth >= kChooserShortGridMinWidth) ? 4 : 2;

/// The grid width of a Compact or Medium window [windowWidth] wide: the content
/// width (capped at 640 dp on Medium) minus 2 x 16 dp of side padding.
double chooserGridWidth(double windowWidth, WindowSizeClass sizeClass) {
  final double content = sizeClass == WindowSizeClass.compact
      ? windowWidth
      : (windowWidth < kChooserMediumMaxWidth
          ? windowWidth
          : kChooserMediumMaxWidth);
  final double grid = content - 2 * kChooserSidePadding;
  return grid < 0 ? 0 : grid;
}

/// The width of one card in a grid [gridWidth] wide with [columns] columns.
double chooserCardWidth(double gridWidth, int columns) {
  if (columns <= 0) return gridWidth;
  return (gridWidth - (columns - 1) * kChooserGap) / columns;
}

/// Whether a card of [cardWidth] in a grid of [columns] shows its blurb. Only
/// the 4x1 grid drops it, below 150 dp (contract 10.5, Medium row).
bool chooserShowsBlurb(int columns, double cardWidth) =>
    !(columns == 4 && cardWidth < kChooserBlurbDropWidth);
