/// MK.3 — cycle-aware programming, rebuilt in Gate O.
///
/// ## What was here, and why it could not stay
///
/// A calendar day went in and a physiological claim came out. Day 14 of an
/// assumed 28-day cycle produced *"Peak performance day. PR attempts welcome"*
/// and a 1.10 multiplier on the prescribed working weight — a 10% load increase
/// issued to a person the app has never measured, on the strength of arithmetic.
///
/// Two things are wrong with that and only one of them is the wording.
///
/// **The evidence does not support it.** The largest synthesis available —
/// McNulty et al., *Sports Medicine* 50 (2020), on the effects of menstrual
/// cycle phase on exercise performance — reports trivial average effects with
/// very large between-individual variation, and rates the body of evidence low
/// quality. "Trivial on average, enormous variance" is the worst possible shape
/// for a deterministic per-user prescription: the average says do nothing and
/// the variance says you cannot predict who is the exception.
///
/// **And the input is an estimate, not an observation.** A cycle day is
/// counted forward from a date the user typed. Cycle length varies within the
/// same person from month to month, ovulation timing more so. The app does not
/// measure ovulation and never will from a calendar.
///
/// ## The rule this file now follows
///
/// A calendar estimate may PROMPT. It may not PRESCRIBE.
///
/// So the phase produces a question and a note, and nothing else. What changes
/// the dose is [CycleSelfReport] — what the user says they feel today — which
/// is an observation about themselves rather than an inference about them.
///
/// This is the same split Gate L made between a difficulty rating and a volume
/// deficit, and it is made for the same reason: two different questions had one
/// answer standing in for both.
///
/// ## And the adjustment only ever goes down
///
/// [CycleAdjustment.intensityCeiling] is capped at 1.0 by construction. There
/// is no state in which this feature tells anyone to lift more. A signal this
/// uncertain may reduce a dose — the cost of being wrong is an easy session —
/// and may not raise one, where the cost of being wrong is an injury.
library;

/// The four-phase model. Menstrual / follicular / ovulatory / luteal.
///
/// Kept because it is the vocabulary users recognise, and it names the
/// estimate. It no longer names a prescription.
enum CyclePhase { menstrual, follicular, ovulatory, luteal }

/// Why no phase is being estimated.
enum CycleUnavailable {
  /// The user has not turned cycle tracking on.
  notTracked,

  /// The user has told us it does not apply — pregnancy, postpartum, or any
  /// other reason they chose not to give.
  ///
  /// Deliberately ONE value covering all of them. Splitting it into medical
  /// categories would make this app hold a pregnancy status and reason about
  /// it, which is a different product with a different regulatory position.
  /// What it needs to know is whether cycle-derived suggestions are valid, and
  /// that is a yes/no.
  notApplicable,

  /// Tracked, but the arithmetic cannot produce a phase.
  ///
  /// Out-of-range day, a cycle length outside anything the model covers, or a
  /// last-period date in the future. The old `phaseFor` returned
  /// [CyclePhase.luteal] for `cycleDay < 1` — a fabricated normal answer for
  /// input that was nonsense.
  outOfRange,

  /// Tracked, and the user has told us their cycle is irregular.
  ///
  /// A 28-day model applied to an irregular cycle is not a worse estimate, it
  /// is a meaningless one.
  irregular,
}

/// What the app knows about where the user is in their cycle.
sealed class CycleState {
  const CycleState();

  /// The estimated phase, or null when there is not one.
  CyclePhase? get phase => null;
}

/// No phase, and the reason.
final class CycleUnknown extends CycleState {
  const CycleUnknown(this.reason);
  final CycleUnavailable reason;

  @override
  String toString() => 'CycleUnknown(${reason.name})';
}

/// A phase ESTIMATED from the calendar.
///
/// The name is the contract. Nothing downstream may treat it as a measurement,
/// and the type says so at every call site rather than in a comment one file
/// away.
final class CycleEstimated extends CycleState {
  const CycleEstimated(this._phase);
  final CyclePhase _phase;

  @override
  CyclePhase get phase => _phase;

  @override
  String toString() => 'CycleEstimated(${_phase.name})';
}

/// What the user says they feel today.
///
/// The only cycle-related input that changes a prescription, because it is the
/// only one that is an observation rather than an inference.
enum CycleSelfReport {
  /// Nothing out of the ordinary.
  asUsual,

  /// Tired, heavy, off.
  lowEnergy,

  /// Cramping, pain, or symptoms that make normal training a bad idea today.
  significantSymptoms,
}

/// Estimates the phase, or says why it cannot.
///
/// Day 1 is the first day of menstruation. The 28-day model with mid-cycle
/// ovulation is the textbook one and is used here only to LABEL the estimate.
///
/// Returns [CycleUnknown] rather than a phase for anything outside the model:
/// a day below 1, a day past the cycle length, or a cycle length outside
/// 21–35 days (the range within which the textbook model is a defensible
/// approximation at all).
CycleState estimatePhase({
  required int cycleDay,
  int cycleLength = 28,
  bool irregular = false,
  bool applicable = true,
}) {
  if (!applicable) return const CycleUnknown(CycleUnavailable.notApplicable);
  if (irregular) return const CycleUnknown(CycleUnavailable.irregular);
  if (cycleLength < 21 || cycleLength > 35) {
    return const CycleUnknown(CycleUnavailable.outOfRange);
  }
  if (cycleDay < 1 || cycleDay > cycleLength) {
    return const CycleUnknown(CycleUnavailable.outOfRange);
  }
  if (cycleDay <= 5) return const CycleEstimated(CyclePhase.menstrual);
  final ovulation = (cycleLength / 2).round();
  if (cycleDay < ovulation - 1) {
    return const CycleEstimated(CyclePhase.follicular);
  }
  if (cycleDay <= ovulation + 1) {
    return const CycleEstimated(CyclePhase.ovulatory);
  }
  return const CycleEstimated(CyclePhase.luteal);
}

/// What the phase estimate is allowed to say.
///
/// A note and a question. No multiplier, no tags to upweight, no claim about
/// today's capacity. [PhaseHint.intensityFactor] used to live here and is gone
/// — see the library doc.
class PhaseNote {
  const PhaseNote({required this.phase, required this.body});

  final CyclePhase phase;

  /// Neutral, and phrased as an estimate.
  ///
  /// Every one of these used to be a claim: *"Strength + speed window. Push the
  /// heavy days now"*, *"Peak performance day. PR attempts welcome"*. They are
  /// now statements about where the calendar says the user is, plus the one
  /// thing this app can honestly do with that, which is ask.
  final String body;
}

PhaseNote noteFor(CyclePhase p) => switch (p) {
      CyclePhase.menstrual => const PhaseNote(
          phase: CyclePhase.menstrual,
          body: 'By your calendar this is around the start of your cycle. '
              'How today actually feels is the part that decides the session — '
              'tell us and we will adjust.',
        ),
      CyclePhase.follicular => const PhaseNote(
          phase: CyclePhase.follicular,
          body: 'By your calendar you are in the follicular phase. Research '
                  'finds no reliable performance difference between phases, so '
                  'we do not change your training for it — how you feel today '
                  'is what we act on.',
        ),
      CyclePhase.ovulatory => const PhaseNote(
          phase: CyclePhase.ovulatory,
          body: 'By your calendar you are around mid-cycle. This used to be '
              'labelled a peak-performance day; the evidence does not support '
              'that, so nothing about your session changes because of it.',
        ),
      CyclePhase.luteal => const PhaseNote(
          phase: CyclePhase.luteal,
          body: 'By your calendar you are in the luteal phase. Some people feel '
              'flatter here and many notice nothing. Tell us how today feels '
              'and we will adjust the session.',
        ),
    };

/// What a self-report does to the session.
///
/// The only place in this feature that touches a prescription, and it only ever
/// reduces one.
class CycleAdjustment {
  const CycleAdjustment._(this.intensityCeiling, this.rationale);

  /// A cap, never a target. Null means "no opinion".
  final double? intensityCeiling;

  /// Why, for the plan's rationale. Empty when there is no adjustment.
  final String rationale;

  static const none = CycleAdjustment._(null, '');
}

/// Derives the adjustment from what the user said, not from the calendar.
///
/// [CycleSelfReport.asUsual] deliberately yields no adjustment at all, in any
/// phase. That is the whole reform: a person who says they feel fine gets their
/// normal session even if the calendar says day 2.
CycleAdjustment adjustmentFor(CycleSelfReport? report) => switch (report) {
      null || CycleSelfReport.asUsual => CycleAdjustment.none,
      CycleSelfReport.lowEnergy => const CycleAdjustment._(
          0.9,
          'You told us your energy is low today, so intensity is capped at 90%.',
        ),
      CycleSelfReport.significantSymptoms => const CycleAdjustment._(
          0.7,
          'You told us you have significant symptoms today, so this session is '
              'capped at 70% and leans on lighter work.',
        ),
    };
