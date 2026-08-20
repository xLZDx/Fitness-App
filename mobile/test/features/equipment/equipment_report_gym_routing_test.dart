import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/equipment_detail_page.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart'
    show UserProfile;
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';

/// MRD-02, Gate F. Codex review round 2, 2026-08-21: the equipment-report
/// button now awaits `currentProfileProvider.future` to fix a routing race
/// (see `resolve_equipment_report_gym_id_test.dart`) -- but an unhandled
/// error on that await would have regressed reporting itself, from
/// fire-and-forget-wrong ('unknown', always, before Gate F) to fatal.
const _machine = EquipmentItem(
  id: 'leg_press',
  name: 'Leg Press',
  manufacturer: 'Any',
  category: 'strength',
  description: 'd',
);

Widget _page({required Stream<UserProfile?> profileStream}) => ProviderScope(
      overrides: [
        equipmentByIdProvider.overrideWith((ref, id) async => _machine),
        recommendedExercisesProvider.overrideWith(
          (ref, id) async =>
              const RecommendedExercises(items: [], hiddenForInjury: 0),
        ),
        safetyContextProvider.overrideWith((_) async => SafetyContext(
              screening: screen({for (final q in ParQQuestion.values) q: false}),
            )),
        currentProfileProvider.overrideWith((ref) => profileStream),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EquipmentDetailPage(equipmentId: 'leg_press'),
      ),
    );

void main() {
  testWidgets(
      'REGRESSION (codex round 2): a profile-stream error does not block '
      'the report sheet from opening', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_page(
      profileStream:
          Stream<UserProfile?>.error(Exception('firestore unavailable')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.report_gmailerrorred_outlined));
    await tester.pumpAndSettle();

    // The sheet opened and rendered its fault-category chips -- the button's
    // onPressed handler did not throw past the failed profile read.
    expect(find.byType(ChoiceChip), findsWidgets);
  });
}
