/// What an offline prefetch actually achieved, and why it stopped.
///
/// ## Why a type rather than `AsyncValue<void>`
///
/// The prefetch used to report two things: it finished, or it threw. Between
/// those sits the case that actually happens — some clips are on the device and
/// some are not — and the app had no way to say it. Worse, the two reasons a
/// clip can be absent are opposites:
///
///   * **Something failed.** Signing, the network, the object. The user can do
///     nothing about it and it may be gone next time they look.
///   * **The daily limit was reached.** Nothing failed. The backend refused on
///     purpose, said so, and the refusal ends by itself at the next UTC
///     midnight.
///
/// Telling the second as the first is the defect this programme keeps meeting:
/// a deliberate, self-resolving refusal rendered as a fault, sending someone to
/// look for a problem in a system that is behaving correctly.
///
/// So the type carries counts and one flag, and the SCREEN decides the words.
/// Nothing here is a sentence, in any language: refusal text composed in a
/// state layer is text no translator ever sees.
library;

/// Why a prefetch never started.
///
/// Distinct from a prefetch that ran and delivered part of a week. These three
/// are decided before a single clip is asked for.
enum PrefetchRefusal {
  /// The subscription is still unknown, and guessing would either deny a
  /// paying member something they bought or promise a free one something they
  /// did not.
  planUnknown,

  /// A real answer, and the answer is free tier.
  notSubscribed,

  /// No signed-in account to prefetch for.
  signedOut,
}

/// Thrown when a prefetch is refused before it begins.
///
/// It carries the REASON and not a message. The previous version threw
/// `StateError('Offline downloads are a Supporter+ benefit.')` from a Riverpod
/// notifier and the card rendered `'${action.error}'` — an English sentence
/// written in a state layer, shipped to every locale, and formatted by
/// `toString()`.
class PrefetchRefused implements Exception {
  const PrefetchRefused(this.reason);

  final PrefetchRefusal reason;

  @override
  String toString() => 'PrefetchRefused(${reason.name})';
}

/// The result of a prefetch that ran.
class PrefetchOutcome {
  const PrefetchOutcome({
    required this.requested,
    required this.ready,
    this.quotaExhausted = false,
  })  : assert(requested >= 0),
        assert(ready >= 0),
        assert(ready <= requested);

  /// Distinct clips the week needs.
  final int requested;

  /// Clips now on the device. Includes ones that were already there: the
  /// question the user is asking is "can I train offline", not "what did this
  /// tap download".
  final int ready;

  /// The backend refused on the daily budget partway through.
  final bool quotaExhausted;

  /// Clips the week needs and does not have.
  int get missing => requested - ready;

  /// Nothing was asked for — an empty week, not a failure.
  bool get nothingScheduled => requested == 0;

  /// Everything the week needs is on the device.
  bool get complete => missing == 0;

  /// Ran, and delivered none of what it asked for.
  bool get emptyHanded => requested > 0 && ready == 0;

  /// The five states this type exists to keep apart. Exhaustive and mutually
  /// exclusive by construction, so a caller cannot forget one.
  PrefetchState get state {
    if (nothingScheduled) return PrefetchState.nothingScheduled;
    if (complete) return PrefetchState.complete;
    if (emptyHanded) {
      return quotaExhausted
          ? PrefetchState.noneQuota
          : PrefetchState.noneFailed;
    }
    return quotaExhausted
        ? PrefetchState.partialQuota
        : PrefetchState.partialFailed;
  }

  @override
  String toString() => 'PrefetchOutcome($ready/$requested'
      '${quotaExhausted ? ", quota" : ""})';
}

/// The distinguishable outcomes of a prefetch that ran.
///
/// Named rather than left to the caller's own `if` chain: two screens deriving
/// "partial because of the limit" independently is how the second one ends up
/// saying something the first does not.
enum PrefetchState {
  nothingScheduled,
  complete,
  partialQuota,
  partialFailed,
  noneQuota,
  noneFailed,
}
