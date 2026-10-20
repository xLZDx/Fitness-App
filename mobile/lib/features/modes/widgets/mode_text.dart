/// Localized names, blurbs and descriptions of the four modes, and their icons.
///
/// One lookup for every mode surface (chooser now, switcher and sheets later),
/// so a mode word comes from one ARB key each and is never interpolated into a
/// sentence (design 6, rule 1).
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../data/mode_models.dart';

String modeNameOf(AppLocalizations l10n, AppMode mode) => switch (mode) {
      AppMode.train => l10n.modeTrainName,
      AppMode.ride => l10n.modeRideName,
      AppMode.explore => l10n.modeExploreName,
      AppMode.body => l10n.modeBodyName,
    };

String modeBlurbOf(AppLocalizations l10n, AppMode mode) => switch (mode) {
      AppMode.train => l10n.modeTrainBlurb,
      AppMode.ride => l10n.modeRideBlurb,
      AppMode.explore => l10n.modeExploreBlurb,
      AppMode.body => l10n.modeBodyBlurb,
    };

String modeDescOf(AppLocalizations l10n, AppMode mode) => switch (mode) {
      AppMode.train => l10n.modeTrainDesc,
      AppMode.ride => l10n.modeRideDesc,
      AppMode.explore => l10n.modeExploreDesc,
      AppMode.body => l10n.modeBodyDesc,
    };

IconData modeIconOf(AppMode mode) => switch (mode) {
      AppMode.train => Icons.fitness_center_rounded,
      AppMode.ride => Icons.directions_bike_rounded,
      AppMode.explore => Icons.hiking_rounded,
      AppMode.body => Icons.monitor_weight_outlined,
    };
