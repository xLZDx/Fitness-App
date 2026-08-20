import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/equipment_detail_page.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';

/// MRD-02, Gate F. `resolveEquipmentReportGymId` is the routing decision
/// behind the equipment-report button's `gymId` argument -- extracted out of
/// `EquipmentDetailPage`'s `onPressed` so these cases do not have to drive a
/// real `EquipmentReportSheet` bottom sheet to prove.
void main() {
  test('no profile at all (signed out, or raced ahead of the stream) falls '
      'back to unknown', () {
    expect(resolveEquipmentReportGymId(null), 'unknown');
  });

  test('gym access with no gym name typed falls back to unknown', () {
    expect(
      resolveEquipmentReportGymId(
          const EquipmentAccess(location: TrainingLocation.gym)),
      'unknown',
    );
  });

  test('gym access with a gym name forwards it, trimmed', () {
    expect(
      resolveEquipmentReportGymId(const EquipmentAccess(
        location: TrainingLocation.gym,
        gymId: '  Iron Temple  ',
      )),
      'Iron Temple',
    );
  });

  test('mixed access forwards the gym name too', () {
    expect(
      resolveEquipmentReportGymId(const EquipmentAccess(
        location: TrainingLocation.mixed,
        gymId: 'Iron Temple',
      )),
      'Iron Temple',
    );
  });

  test(
      'BLOCKER (codex review, Gate F cherry-pick, 2026-08-21): a gymId left '
      'over from a location the user has since changed away from is never '
      'forwarded -- it would route to the WRONG gym, not just an absent one',
      () {
    // step_equipment.dart's own fix clears gymId on this exact transition,
    // but this function must refuse to forward a stale one regardless of
    // how it got here -- e.g. a profile written by a path this cherry-pick
    // did not touch.
    expect(
      resolveEquipmentReportGymId(const EquipmentAccess(
        location: TrainingLocation.home,
        gymId: 'Iron Temple',
      )),
      'unknown',
    );
    expect(
      resolveEquipmentReportGymId(const EquipmentAccess(
        location: TrainingLocation.outdoor,
        gymId: 'Iron Temple',
      )),
      'unknown',
    );
  });
}
