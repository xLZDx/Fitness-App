import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../shared/widgets/app_buttons.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../onboarding/widgets/inputs.dart';
import '../../profile/state/profile_providers.dart';
import '../data/equipment_setup_note.dart';
import '../state/equipment_setup_note_providers.dart';

/// MRD-03/04/05 (Gate G): the user's own free-text setup reminder for this
/// equipment TYPE at their gym -- "seat 4, pin 8". See
/// [EquipmentSetupNote]'s doc comment for why the key is (equipmentId,
/// gymId) rather than a genuine single-physical-machine id, which nothing in
/// this app can currently produce.
///
/// Hidden entirely when the profile has no `gymId` set: without a gym, the
/// (equipmentId, gymId) key this note lives under has no second half, and a
/// note with no location scope would just be a worse version of the free-text
/// box the workout-session `notes` field already offers. Same restraint
/// [LastSessionCard] uses for a confirmed no-history equipment type -- an
/// empty state that has nothing to add earns no screen space.
class SetupNoteCard extends ConsumerStatefulWidget {
  const SetupNoteCard({super.key, required this.equipmentId});
  final String equipmentId;

  @override
  ConsumerState<SetupNoteCard> createState() => _SetupNoteCardState();
}

class _SetupNoteCardState extends ConsumerState<SetupNoteCard> {
  // Seeded once per (equipmentId, gymId) pair from the loaded note, then
  // owned entirely by this widget -- the same `??=`-on-first-load shape
  // `InjuriesPage` uses, keyed additionally on [_seededGymId] because unlike
  // `InjuriesPage` this card's data source can change identity under the
  // same State object: `gymId` comes from the live profile, and a user who
  // edits it (Profile -> "edit your answers") while this page is still on
  // screen must not have their next keystroke land in the old gym's note, or
  // -- worse -- Save write the old gym's draft text under the new gym's key.
  //
  // Deliberately NOT re-passed to `GlassTextField.value` on every rebuild
  // once seeded for a given key: Gate F's review found that feeding a
  // controlled `GlassTextField` a value that changes for a reason other than
  // its own `onChanged` mid-typing forces it to resync its controller and can
  // eat characters. Seeding once per key and then never touching `value`
  // again for that key (this widget's `onChanged` only updates `_draft`,
  // never calls `setState` on its own) means the prop this card hands
  // `GlassTextField` never disagrees with what the field itself holds while
  // the user is actively typing.
  String? _draft;
  String? _seededGymId;
  bool _saving = false;

  Future<void> _save(String equipmentId, String gymId) async {
    setState(() => _saving = true);
    await ref.read(equipmentSetupNoteRepositoryProvider).save(
          EquipmentSetupNote(
            equipmentId: equipmentId,
            gymId: gymId,
            note: (_draft ?? '').trim(),
            updatedAt: DateTime.now(),
          ),
        );
    // Without this, `equipmentSetupNoteProvider` (a plain, non-autoDispose
    // FutureProvider.family) keeps serving the pre-save result it already
    // cached for this key -- so leaving and reopening this same page shows
    // the note as blank again, and a second Save on that stale draft would
    // silently overwrite the real one with nothing. Reviewer-found MAJOR
    // (Gate G flutter-reviewer pass): every other write-then-reread flow in
    // this app already invalidates its read provider after a mutation
    // (`workout_log_providers.dart`, `progress_photos_providers.dart`); this
    // was the one write path that skipped it.
    ref.invalidate(equipmentSetupNoteProvider((equipmentId: equipmentId, gymId: gymId)));
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).equipmentSetupNoteSaved),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final gymId =
        ref.watch(currentProfileProvider).valueOrNull?.equipment.gymId?.trim();
    if (gymId == null || gymId.isEmpty) return const SizedBox.shrink();

    final noteAsync = ref.watch(
      equipmentSetupNoteProvider((equipmentId: widget.equipmentId, gymId: gymId)),
    );
    if (!noteAsync.hasValue) return const SizedBox.shrink();
    if (_seededGymId != gymId) {
      _seededGymId = gymId;
      _draft = noteAsync.value?.note ?? '';
    }

    return HudPanel(
      key: const Key('equipment.setupNote'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.equipmentSetupNoteHeadline,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            l10n.equipmentSetupNoteAtGym(gymId),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colors.textSecondary),
          ),
          const SizedBox(height: 10),
          GlassTextField(
            key: const Key('equipment.setupNote.field'),
            value: _draft!,
            maxLines: 3,
            hint: l10n.equipmentSetupNoteHint,
            onChanged: (v) => _draft = v,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: AppSecondaryButton(
              key: const Key('equipment.setupNote.save'),
              label: l10n.equipmentSetupNoteSave,
              loading: _saving,
              onPressed: () => _save(widget.equipmentId, gymId),
            ),
          ),
        ],
      ),
    );
  }
}
