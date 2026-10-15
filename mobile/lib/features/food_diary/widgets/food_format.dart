/// Locale-aware formatting and label lookups shared by the diary widgets
/// (D-85: every number goes through `NumberFormat` with the active locale).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../data/check_these.dart';
import '../data/food_entry.dart';
import '../data/food_source.dart';

/// Whole number in the active locale (kcal, grams of a portion).
String fmtInt(BuildContext context, double v) {
  final locale = Localizations.localeOf(context).toString();
  return NumberFormat.decimalPattern(locale).format(v.isFinite ? v.round() : 0);
}

/// One decimal at most, trailing zero dropped (macro grams).
String fmtGrams(BuildContext context, double v) {
  final locale = Localizations.localeOf(context).toString();
  return NumberFormat('#,##0.#', locale).format(v.isFinite ? v : 0);
}

String slotLabel(AppLocalizations l10n, MealSlot slot) => switch (slot) {
      MealSlot.breakfast => l10n.foodDiarySlotBreakfast,
      MealSlot.lunch => l10n.foodDiarySlotLunch,
      MealSlot.dinner => l10n.foodDiarySlotDinner,
      MealSlot.snack => l10n.foodDiarySlotSnack,
    };

String sourceLabel(AppLocalizations l10n, FoodSource s) => switch (s) {
      FoodSource.off => l10n.foodSourceOff,
      FoodSource.usda => l10n.foodSourceUsda,
      FoodSource.llmEstimate => l10n.foodSourceEstimate,
      FoodSource.user => l10n.foodSourceUser,
      FoodSource.label => l10n.foodSourceLabel,
    };

String confidenceLabel(AppLocalizations l10n, EntryConfidence c) => switch (c) {
      EntryConfidence.low => l10n.foodConfidenceLow,
      EntryConfidence.medium => l10n.foodConfidenceMedium,
      EntryConfidence.high => l10n.foodConfidenceHigh,
    };

String checkTitle(AppLocalizations l10n, CheckCode c) => switch (c) {
      CheckCode.portionUnclear => l10n.foodCheckPortionUnclear,
      CheckCode.hiddenIngredients => l10n.foodCheckHiddenIngredients,
      CheckCode.liquidUnknown => l10n.foodCheckLiquidUnknown,
      CheckCode.cookingMethod => l10n.foodCheckCookingMethod,
      CheckCode.multipleItems => l10n.foodCheckMultipleItems,
      CheckCode.brandUnknown => l10n.foodCheckBrandUnknown,
      CheckCode.foodNotMatched => l10n.foodCheckFoodNotMatched,
      CheckCode.lowConfidenceItem => l10n.foodCheckLowConfidenceItem,
      CheckCode.labelAmbiguous => l10n.foodCheckLabelAmbiguous,
      CheckCode.dataInconsistent => l10n.foodCheckDataInconsistent,
      CheckCode.scaleMissing => l10n.foodCheckScaleMissing,
    };

String checkHelp(AppLocalizations l10n, CheckCode c) => switch (c) {
      CheckCode.portionUnclear => l10n.foodCheckHelpPortionUnclear,
      CheckCode.hiddenIngredients => l10n.foodCheckHelpHiddenIngredients,
      CheckCode.liquidUnknown => l10n.foodCheckHelpLiquidUnknown,
      CheckCode.cookingMethod => l10n.foodCheckHelpCookingMethod,
      CheckCode.multipleItems => l10n.foodCheckHelpMultipleItems,
      CheckCode.brandUnknown => l10n.foodCheckHelpBrandUnknown,
      CheckCode.foodNotMatched => l10n.foodCheckHelpFoodNotMatched,
      CheckCode.lowConfidenceItem => l10n.foodCheckHelpLowConfidenceItem,
      CheckCode.labelAmbiguous => l10n.foodCheckHelpLabelAmbiguous,
      CheckCode.dataInconsistent => l10n.foodCheckHelpDataInconsistent,
      CheckCode.scaleMissing => l10n.foodCheckHelpScaleMissing,
    };
