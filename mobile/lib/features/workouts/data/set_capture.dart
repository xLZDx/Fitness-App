/// What the user actually lifted in one set. Null fields mean "declined to
/// say".
///
/// Lives in `data/`, not `widgets/`, because [WorkoutSessionExercise]
/// (`workout_session.dart`) needs it and a data model must not depend on a
/// widget file. `set_capture_sheet.dart` re-exports this so its own public
/// surface is unchanged for existing importers.
typedef SetCapture = ({double? weightKg, int? reps});
