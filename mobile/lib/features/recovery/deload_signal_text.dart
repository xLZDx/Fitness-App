import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'data/deload_detector.dart';

/// Where a deload signal becomes a sentence.
///
/// F027, third site. `deload_detector.dart` is a pure function over the user's
/// history, so every sentence it composed was English by construction — and
/// `deload_banner.dart` rendered `reasons.first` into a `Text` unchanged. A
/// Russian user was told, in English, that their body was asking for a break.
///
/// It survived the l10n guard for a mundane reason worth remembering: the
/// banner's fallback was written with double quotes, and the guard's literal
/// regex matched only `'...'`. The sentence was not hidden behind cleverness.
/// It was hidden behind a quotation mark.
///
/// Same shape as `plan_reason_text.dart`: a `switch` over a sealed type, in
/// the layer that has the locale, so the compiler refuses a new signal that
/// nobody taught the UI to say.
String deloadSignalText(AppLocalizations l10n, DeloadSignal signal) =>
    switch (signal) {
      HardSessionsSignal(:final count) => l10n.recoveryDeloadHardSessions(count),
      MissedSessionsSignal(:final missed, :final scheduled) =>
        l10n.recoveryDeloadMissedSessions(missed, scheduled),
      HrvBelowBaselineSignal(:final percentBelow) =>
        l10n.recoveryDeloadHrvBelowBaseline(percentBelow),
    };
