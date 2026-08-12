import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/inputs.dart';

List<String> _splitTags(String input) => input
    .split(RegExp(r'[,\n]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

/// O4 — screen 2: where you train, and what with.
///
/// ## What replaced what
///
/// The screen used to ask a yes/no "gym access?" and take everything else as
/// free text. Free text cannot be matched against a catalogue, so the equipment
/// answer was collected and then not used by anything that picks exercises.
///
/// Now the place is one of four ([TrainingLocation]) and the kit is a closed set
/// ([EquipmentKind]). The free-text box survives for what the set cannot hold —
/// deleting it would have quietly discarded whatever people had already typed
/// there, and it is the only place an unusual machine can be recorded at all.
///
/// `hasGymAccess` is no longer asked directly: it is derived from the place.
/// Asking both would let a user answer "at home" and "yes, I have a gym", and
/// then something downstream has to decide which one to believe.
class StepEquipment extends ConsumerWidget {
  const StepEquipment({super.key});

  static const _locations = TrainingLocation.values;
  static const _kinds = EquipmentKind.values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final eq = ref.watch(questionnaireDraftProvider).equipment;
    final notifier = ref.read(questionnaireDraftProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: l10n.onbPlaceTitle,
          subtitle: l10n.onbPlaceSubtitle,
        ),
        const SizedBox(height: 18),
        for (final loc in _locations) ...[
          ChoiceCard(
            key: Key('onb.place.${loc.name}'),
            title: _placeTitle(l10n, loc),
            subtitle: _placeSubtitle(l10n, loc),
            icon: _placeIcon(loc),
            selected: eq.location == loc,
            onTap: () =>
                notifier.updateEquipment((s) => s.copyWith(location: loc)),
          ),
          const SizedBox(height: 10),
        ],
        FieldLabel(l10n.onbEquipmentAvailable),
        MultiChoiceChips<EquipmentKind>(
          options: _kinds,
          labelOf: (k) => _kindLabel(l10n, k),
          values: eq.available.toSet(),
          onChanged: (next) => notifier.updateEquipment(
            // Ordered by the enum, not by the order the user tapped: this list
            // is persisted and compared, and a set that serialises differently
            // depending on tap order makes two identical answers look different.
            (s) => s.copyWith(
              available: [
                for (final k in _kinds)
                  if (next.contains(k)) k,
              ],
            ),
          ),
        ),
        FieldLabel(l10n.onbHomeEquipment),
        GlassTextField(
          value: eq.homeEquipment.join(', '),
          maxLines: 2,
          hint: l10n.onbHomeEquipmentHint,
          onChanged: (v) => notifier.updateEquipment(
            (s) => s.copyWith(homeEquipment: _splitTags(v)),
          ),
        ),
      ],
    );
  }
}

String _placeTitle(AppLocalizations l, TrainingLocation p) => switch (p) {
      TrainingLocation.gym => l.onbPlaceGym,
      TrainingLocation.home => l.onbPlaceHome,
      TrainingLocation.outdoor => l.onbPlaceOutdoor,
      TrainingLocation.mixed => l.onbPlaceMixed,
    };

String _placeSubtitle(AppLocalizations l, TrainingLocation p) => switch (p) {
      TrainingLocation.gym => l.onbPlaceGymSub,
      TrainingLocation.home => l.onbPlaceHomeSub,
      TrainingLocation.outdoor => l.onbPlaceOutdoorSub,
      TrainingLocation.mixed => l.onbPlaceMixedSub,
    };

IconData _placeIcon(TrainingLocation p) => switch (p) {
      TrainingLocation.gym => Icons.fitness_center_rounded,
      TrainingLocation.home => Icons.home_rounded,
      TrainingLocation.outdoor => Icons.park_rounded,
      TrainingLocation.mixed => Icons.shuffle_rounded,
    };

String _kindLabel(AppLocalizations l, EquipmentKind k) => switch (k) {
      EquipmentKind.fullGym => l.onbKitFullGym,
      EquipmentKind.machines => l.onbKitMachines,
      EquipmentKind.dumbbells => l.onbKitDumbbells,
      EquipmentKind.barbell => l.onbKitBarbell,
      EquipmentKind.kettlebells => l.onbKitKettlebells,
      EquipmentKind.bands => l.onbKitBands,
      EquipmentKind.bodyweight => l.onbKitBodyweight,
      EquipmentKind.cameraScan => l.onbKitCameraScan,
    };
