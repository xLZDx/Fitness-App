/// Which first-run questions a mode asks, their options, and the stored answer
/// tokens (design 2.3, contract S-2; AC-Q-1, AC-Q-4, AC-Q-6).
///
/// Pure: no widget, no provider. The chooser uses [unansweredQuestionsFor] to
/// decide whether Continue goes to the questions at all; the question page uses
/// it once, at its start, to fix the list (so the counter "Question n of N" stays
/// stable while answers arrive).
///
/// Stored tokens (read by the Home lens, lane L7): the BODY answer
/// `answers[body]` holds one of [kBodyStartPhotos], [kBodyStartFood],
/// [kBodyStartWeight]; the TRAIN answer holds one of the TRAIN option ids and is
/// mirrored into the existing `TrainingContext` answer.
library;

import '../../progress_photos/scan/scan_access.dart' show ScanAccess;
import '../../training_context/data/training_context.dart';
import '../data/mode_models.dart';

/// The questions of S03. Ride and Explore ask none while they are coming later.
enum ModeQuestionId { trainWhere, bodyStart }

/// Most questions one mode may ask (DQ-6).
const int kMaxModeQuestions = 3;

/// One choice of a question. [id] is also the stored answer value and the key
/// suffix (`modeQuestion.option.<id>`).
class ModeQuestionOption {
  const ModeQuestionOption(this.id, {this.trainingContext});

  final String id;

  /// The existing `TrainingContext` this option writes (TRAIN question only).
  final TrainingContext? trainingContext;
}

const String kTrainWhereGym = 'gym';
const String kTrainWhereAtHome = 'atHome';
const String kTrainWhereOutdoors = 'outdoors';
const String kTrainWhereYoga = 'yoga';

/// Stored `answers[body]` values; Home puts the nutrition card first for
/// [kBodyStartFood] and the body-scan card first for [kBodyStartPhotos].
const String kBodyStartPhotos = 'photos';
const String kBodyStartFood = 'food';
const String kBodyStartWeight = 'weight';

const List<ModeQuestionOption> kTrainWhereOptions = <ModeQuestionOption>[
  ModeQuestionOption(kTrainWhereGym, trainingContext: TrainingContext.gymMachines),
  ModeQuestionOption(kTrainWhereAtHome, trainingContext: TrainingContext.home),
  ModeQuestionOption(kTrainWhereOutdoors,
      trainingContext: TrainingContext.outdoorMinimal),
  ModeQuestionOption(kTrainWhereYoga, trainingContext: TrainingContext.yoga),
];

const List<ModeQuestionOption> kBodyStartOptions = <ModeQuestionOption>[
  ModeQuestionOption(kBodyStartPhotos),
  ModeQuestionOption(kBodyStartFood),
  ModeQuestionOption(kBodyStartWeight),
];

/// The options of [question].
List<ModeQuestionOption> optionsOfQuestion(ModeQuestionId question) =>
    switch (question) {
      ModeQuestionId.trainWhere => kTrainWhereOptions,
      ModeQuestionId.bodyStart => kBodyStartOptions,
    };

/// The questions [mode] still has to ask, in order, at most
/// [kMaxModeQuestions]. Only unknown things are asked:
///  * TRAIN asks "where" only when BOTH the mode answer and the existing
///    `TrainingContext` answer are unanswered (an answered OR skipped context
///    asks nothing, AC-Q-1);
///  * BODY asks "start with" while its mode answer is unanswered (a skipped
///    answer is never asked again, AC-Q-2);
///  * every other mode asks nothing.
List<ModeQuestionId> unansweredQuestionsFor(
  AppMode mode, {
  required ModeState modeState,
  required TrainingContextAnswer trainingContext,
}) {
  final List<ModeQuestionId> out = <ModeQuestionId>[];
  switch (mode) {
    case AppMode.train:
      if (modeState.answerFor(AppMode.train).kind == ModeAnswerKind.unanswered &&
          !trainingContext.answered) {
        out.add(ModeQuestionId.trainWhere);
      }
    case AppMode.body:
      if (modeState.answerFor(AppMode.body).kind == ModeAnswerKind.unanswered) {
        out.add(ModeQuestionId.bodyStart);
      }
    case AppMode.ride:
    case AppMode.explore:
      break;
  }
  return out.length > kMaxModeQuestions
      ? out.sublist(0, kMaxModeQuestions)
      : out;
}

/// Whether the existing access gate refuses [optionId]. Only the progress-photos
/// option is gated, and only by the AGE outcomes of the gate (underage, age
/// unknown); a missing supporter tier or photo consent is handled by the photo
/// flow itself later, because this answer only orders cards and opens nothing
/// (contract S-2: "opens nothing, requests nothing").
bool isQuestionOptionRefused(ScanAccess access, String optionId) =>
    optionId == kBodyStartPhotos &&
    (access == ScanAccess.underage || access == ScanAccess.ageUnknown);
