import 'package:flutter/foundation.dart';

import '../../visual_equipment/data/machine_card.dart' show machineCardId;

/// A user's own free-text reminder for one equipment TYPE at one gym --
/// "seat 4, pin 8", "incline 15, strap tight". MRD-03/04/05 (Gate G).
///
/// ## Why (equipmentId, gymId), not a real physical-machine id
///
/// Gate G's own reconnaissance (`core/product/GATE_G_..._D0_NOTE.md`) found
/// no physical-machine-instance concept anywhere in this codebase, working or
/// dead: no QR/barcode scanning exists, no photo or location survives a scan
/// past classification, and `MachineCard` is deliberately TYPE-scoped (its own
/// doc comment: "two people photographing the same thing in two gyms should
/// raise the count on one card"). Building genuine single-physical-unit
/// identity would mean inventing a whole new capture mechanism (a barcode
/// scanner, a location-tagged photo store) with no evidence of which one
/// users would actually want -- exactly the kind of unrequested feature
/// invention this project's own gates avoid.
///
/// `(equipmentId, gymId)` is the best approximation the current data actually
/// supports: it distinguishes "the leg press at Gold's Gym" from "the leg
/// press at Planet Fitness" using only fields that already exist post-Gate-F
/// (the catalog's own type id, and the user's own free-text `gymId`). It does
/// **not** distinguish two identical leg-press units inside the same large
/// gym -- a note saved for one applies to "whichever leg press you use at
/// this gym", the same honest type-level limitation Gate D already accepted
/// for equipment memory generally, now further scoped by location. Copy in
/// [SetupNoteCard] is worded to match ("at {gym}", never "on this machine").
@immutable
class EquipmentSetupNote {
  EquipmentSetupNote({
    required this.equipmentId,
    required this.gymId,
    required this.note,
    required this.updatedAt,
  }) : assert(
          gymId.trim().isNotEmpty,
          'gymId must not be empty or whitespace-only -- a setup note has no '
          '(equipmentId, gymId) key to live under without one; construct via '
          'SetupNoteCard, which never calls this with an unset gym',
        );

  /// Catalog type id, e.g. `leg_press`.
  final String equipmentId;

  /// The gym name the user typed in onboarding (`EquipmentAccess.gymId`),
  /// trimmed. Never empty -- a note is only ever created once a gym is set;
  /// see [SetupNoteCard], which hides entirely without one.
  final String gymId;

  /// The reminder itself. Free text, no structured fields (seat height, pin
  /// position, incline...): no evidence of which fields users would actually
  /// fill in, so one open box beats guessing a schema nobody asked for.
  final String note;

  final DateTime updatedAt;

  /// The stable Firestore document id for this (equipmentId, gymId) pair.
  String get id => equipmentSetupNoteId(equipmentId: equipmentId, gymId: gymId);

  Map<String, dynamic> toJson() => {
        'equipmentId': equipmentId,
        'gymId': gymId,
        'note': note,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  /// Null for a document that cannot be a valid note -- a missing/blank
  /// `gymId` or `equipmentId`, from hand-edited or corrupted Firestore data.
  /// Deliberately not thrown/asserted here (unlike the constructor): this is
  /// the one path that reads data this process did not just write, and a
  /// corrupted document degrading to "no note found" is the honest, safe
  /// outcome -- silently constructing a note whose own invariant is already
  /// broken would be worse (Gate G type-design review).
  static EquipmentSetupNote? fromJson(Map<String, dynamic> j) {
    final equipmentId = j['equipmentId'] as String? ?? '';
    final gymId = j['gymId'] as String? ?? '';
    if (equipmentId.trim().isEmpty || gymId.trim().isEmpty) return null;
    return EquipmentSetupNote(
      equipmentId: equipmentId,
      gymId: gymId,
      note: j['note'] as String? ?? '',
      updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EquipmentSetupNote &&
      other.equipmentId == equipmentId &&
      other.gymId == gymId &&
      other.note == note &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(equipmentId, gymId, note, updatedAt);
}

/// The stable Firestore document id for a (equipmentId, gymId) pair.
///
/// [gymId] is free text and unsafe as a raw doc-id component (may contain
/// `/`, be empty, exceed length limits) -- reuses [machineCardId]'s slugging
/// rather than duplicating that normalisation a second time. **Coupling
/// note** (Gate G type-design review): [machineCardId] is owned by the
/// unrelated `machine_card.dart` feature for machine-NAME deduplication: if
/// its normalisation rules ever change for a machine-card reason, every
/// previously-saved setup note whose gym name is affected becomes
/// unreachable under a new id, with no error -- `get()` just returns null, as
/// if the note had never been saved. [equipmentSetupNoteIdSlugRegressionSeed]
/// exists to catch that drift in CI before it ships.
///
/// Throws on an empty/whitespace-only [gymId] rather than silently falling
/// through to [machineCardId]'s own `'machine'` empty-input fallback, which
/// would otherwise collide every equipment type's "no real gym" case into one
/// shared bucket -- the [EquipmentSetupNote] constructor's `assert` catches
/// this from model construction, but the repository's `get`/`delete` reach
/// this function directly with a raw `gymId` string, bypassing that assert
/// entirely.
String equipmentSetupNoteId({
  required String equipmentId,
  required String gymId,
}) {
  final trimmed = gymId.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError.value(gymId, 'gymId',
        'must not be empty or whitespace-only -- a setup note has no gym to '
        'scope it to without one');
  }
  return '${equipmentId}__${machineCardId(trimmed)}';
}
