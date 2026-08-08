import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
import '../data/session_digest.dart';
import 'session_screening_providers.dart';

/// The day's digest, from the same list Home already renders underneath it.
///
/// Built on [screenedUpcomingSessionsProvider] rather than the raw schedule so
/// the hero and the list below it cannot disagree: both see one screening of
/// one set of rows. A hero that counted eight while the list showed seven
/// would be worse than the single-exercise hero it replaces.
///
/// The catalog is turned into a map here, in a provider, rather than at the
/// call site: Riverpod rebuilds this only when the catalog or the schedule
/// actually changes, while a map built inside `build` would rebuild 1,887
/// entries on every frame Home repaints.
///
/// Empty while either half resolves — the same empty the screened stream
/// itself starts from, so the card shows its "nothing scheduled" state rather
/// than a flash of zeros.
final todayDigestProvider = Provider<SessionDigest>((ref) {
  final screened =
      ref.watch(screenedUpcomingSessionsProvider).valueOrNull ??
          const <ScreenedSession>[];
  final catalog =
      ref.watch(safeCatalogProvider).valueOrNull ?? const <ExerciseItem>[];

  return digestForDay(
    [for (final s in screened) s.session],
    {for (final e in catalog) e.id: e},
  );
});
