/// The ONE list of shell destinations (contract 5.3, design 2.6; S03-04).
///
/// Both presentations of the shell (the floating bottom bar and the side rail)
/// are built from [kShellDestinations]: same order, icons, labels and paths.
/// A later change of the tab set is a one-place edit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'hud/hud_scaffold.dart' show HudNavItem;

/// One shell destination.
@immutable
class ShellDestination {
  const ShellDestination({
    required this.path,
    required this.icon,
    required this.labelOf,
  });

  /// Router location of the tab (replaced with `context.go`).
  final String path;

  final IconData icon;

  /// Resolves the localised label. Labels are looked up per build so a locale
  /// change is picked up (a static list of strings would freeze the first one).
  final String Function(AppLocalizations l10n) labelOf;
}

String _labelHome(AppLocalizations l10n) => l10n.homeHome;

// `workoutsTrain` ("Тренировка") is the Workouts page's own title; the tab
// names a section, which the prototype labels "Тренировки".
String _labelWorkouts(AppLocalizations l10n) => l10n.navWorkouts;

// `scannerScan` is the page's own title and stays that. A nav label is one word
// wide: the long form wrapped to two lines on the operator's phone.
String _labelScan(AppLocalizations l10n) => l10n.navScan;

String _labelProgress(AppLocalizations l10n) => l10n.progressProgress;

String _labelProfile(AppLocalizations l10n) => l10n.profileProfile;

/// Home, Workouts, Scan, Progress, Profile, in this order (contract F2).
const List<ShellDestination> kShellDestinations = <ShellDestination>[
  ShellDestination(
    path: '/home',
    icon: Icons.grid_view_rounded,
    labelOf: _labelHome,
  ),
  ShellDestination(
    path: '/workouts',
    icon: Icons.fitness_center_rounded,
    labelOf: _labelWorkouts,
  ),
  ShellDestination(
    path: '/scan',
    icon: Icons.radio_button_checked_rounded,
    labelOf: _labelScan,
  ),
  ShellDestination(
    path: '/progress',
    icon: Icons.north_east_rounded,
    labelOf: _labelProgress,
  ),
  ShellDestination(
    path: '/profile',
    icon: Icons.person_outline_rounded,
    labelOf: _labelProfile,
  ),
];

/// The selected destination for [location]: the first whose path prefixes it,
/// else 0 (exactly the previous `MainShell._indexFor`).
int shellDestinationIndexFor(String location) {
  final int i =
      kShellDestinations.indexWhere((d) => location.startsWith(d.path));
  return i < 0 ? 0 : i;
}

/// The nav items for the bar and the rail, resolved against [l10n].
List<HudNavItem> shellNavItems(AppLocalizations l10n) => <HudNavItem>[
      for (final ShellDestination d in kShellDestinations)
        HudNavItem(icon: d.icon, label: d.labelOf(l10n)),
    ];
