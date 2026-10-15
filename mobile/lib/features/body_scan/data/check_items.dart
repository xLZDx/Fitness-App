/// The closed set of "check these" items attached to a body-scan result
/// (design s12.7). Pure Dart, no Flutter imports.
///
/// Free text from any provider is NEVER displayed: the set is closed so each
/// code is translatable and no provider string can reach the screen (a prompt
/// injection surface). An unknown string is dropped.
library;

/// What the user can do about a check item.
enum CheckAction {
  /// Nothing to do; the item is informational.
  none,
  retakeLighting,
  retakeFraming,
  retakePose,
  logWeight,
  confirmWeight,
}

enum CheckCode {
  provisionalEstimator(CheckAction.none),
  manualCapture(CheckAction.none),
  poorLighting(CheckAction.retakeLighting),
  partialBody(CheckAction.retakeFraming),
  looseClothing(CheckAction.retakeFraming),
  poseMismatch(CheckAction.retakePose),
  weightMissing(CheckAction.logWeight),
  weightStale(CheckAction.logWeight),
  weightJump(CheckAction.confirmWeight),
  wideRange(CheckAction.none),
  estimateFarFromProfile(CheckAction.confirmWeight),
  largeJumpVsTrend(CheckAction.none),
  blurUnavailable(CheckAction.retakeFraming);

  const CheckCode(this.action);

  /// The action the result screen offers for this item.
  final CheckAction action;

  /// The l10n key of the item text (`checkCode<Name>`), keyed by closed code.
  String get l10nKey => 'checkCode${name[0].toUpperCase()}${name.substring(1)}';

  /// A recorded weight older than this many days raises [weightStale].
  static const int weightStaleAfterDays = 7;

  static CheckCode? byName(Object? name) {
    if (name is! String) return null;
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// Parses a list of provider/stored strings into known codes: unknown values
/// and duplicates are dropped, the result is in the stable declaration order.
List<CheckCode> parseCheckCodes(Object? raw) {
  if (raw is! List) return const [];
  final found = <CheckCode>{};
  for (final e in raw) {
    final c = CheckCode.byName(e);
    if (c != null) found.add(c);
  }
  return [
    for (final c in CheckCode.values)
      if (found.contains(c)) c,
  ];
}
