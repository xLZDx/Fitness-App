/// Small helpers shared by the meal photo, barcode and label pages.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../nutrition_plan/state/weight_providers.dart';
import '../state/diary_providers.dart';
import '../state/food_api.dart';

/// The `yyyy-MM-dd` day from the route query, else today.
String resolveScanDay(WidgetRef ref, String? day) =>
    (day != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day))
        ? day
        : dayKeyOf(ref.read(nutritionClockProvider)());

/// `ru` or `en`, the two languages the callables accept.
String scanLanguageCode(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ru' ? 'ru' : 'en';

/// Calm, closed-set text for a failed food call; [generic] is the page's own
/// "could not finish" sentence. Raw server text never reaches the UI (D-67).
String scanFailureMessage(
  AppLocalizations l10n,
  FoodApiException e, {
  required String generic,
}) {
  if (e.isNotAvailableYet) return l10n.foodDiaryNotAvailableYet;
  switch (e.failure) {
    case FoodApiFailure.rateLimited:
      return l10n.foodScanRateLimited;
    case FoodApiFailure.notAllowed:
      return l10n.foodScanNotAllowed;
    default:
      return generic;
  }
}
