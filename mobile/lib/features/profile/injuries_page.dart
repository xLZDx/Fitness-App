import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/glass.dart';
import '../../shared/widgets/smooth_scroll_list.dart';
import '../onboarding/widgets/inputs.dart';
import 'data/injury_regions.dart';
import 'data/profile_models.dart';
import 'state/profile_providers.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../shared/widgets/app_buttons.dart';

/// The screen that makes a stored injury editable.
///
/// ## Why this exists rather than a fix to "Edit your answers"
///
/// `ProfileRepository.save()` had two call sites, both inside
/// `features/onboarding/`. The affordance meant to reach them — the
/// questionnaire tile on the profile page — routes to `/onboarding`, and
/// `resolveRedirect` sends anyone who has onboarded straight back to `/home`.
/// So an existing user could not change a stored injury by any path.
///
/// Patching that redirect was the other option in the plan and is the larger
/// one: it re-opens the entire eight-step questionnaire as an edit surface,
/// with every step's save semantics to re-answer. This is one screen with one
/// save call, and it is the surface the structured region actually needs.
///
/// ## Why the region is chosen, never inferred
///
/// [suggestRegion] proposes; the user decides. A proposal applied silently is
/// a safety decision nobody saw, and the app has just spent two gates removing
/// exactly that pattern. Declining every proposal is a real answer —
/// [Injury.confirmed] records it, so a rib injury is asked about once rather
/// than on every load forever.
class InjuriesPage extends ConsumerStatefulWidget {
  const InjuriesPage({super.key});

  @override
  ConsumerState<InjuriesPage> createState() => _InjuriesPageState();
}

class _InjuriesPageState extends ConsumerState<InjuriesPage> {
  List<Injury>? _draft;
  bool _dirty = false;

  /// Stable identities for the rows, so removing the second injury does not
  /// hand its text-field state to the third. `TextFormField(initialValue:)`
  /// keeps whatever the element already had.
  final _rowIds = <int>[];
  int _nextRowId = 0;

  void _seed(List<Injury> stored) {
    // Proposals are computed once, on load, and shown as pre-selected chips
    // the user can change or reject. Nothing is written until Save.
    _draft = [
      for (final i in stored)
        i.region == null && !i.confirmed
            ? i.copyWith(region: suggestRegion(i.bodyPart))
            : i,
    ];
    // A proposal IS an unsaved change, so Save has to be reachable for it.
    // Leaving the button disabled here would show the user a pre-selected
    // region they could not accept without first changing something else --
    // and the accepted proposal is the entire delivery mechanism for the
    // structured region.
    _dirty = _draft!.length != stored.length ||
        List.generate(stored.length, (n) => n)
            .any((n) => _draft![n] != stored[n]);
    _rowIds
      ..clear()
      ..addAll(List.generate(_draft!.length, (_) => _nextRowId++));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider);
    final saving = ref.watch(profileSubmitProvider).isLoading;

    return FrostedScaffold(
      appBar: GlassAppBar(title: l10n.injuriesTitle),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(l10n.homeCouldNotLoad('$e'))),
        data: (stored) {
          _draft ??= () {
            _seed(stored?.health.injuries ?? const []);
            return _draft!;
          }();
          final draft = _draft!;
          final unresolved = unresolvedInjuries(draft).length;

          return SmoothScrollList(
            padding: const EdgeInsets.fromLTRB(20, 92, 20, 110),
            children: [
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.injuriesWhatThisDoes,
                        style: Theme.of(context).textTheme.bodyMedium),
                    if (unresolved > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.injuriesNeedAnArea(unresolved),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                                color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (draft.isEmpty)
                GlassCard(child: Text(l10n.injuriesNoneListed))
              else
                for (var i = 0; i < draft.length; i++) ...[
                  _InjuryCard(
                    key: ValueKey(_rowIds[i]),
                    injury: draft[i],
                    onChanged: (next) => setState(() {
                      draft[i] = next;
                      _dirty = true;
                    }),
                    onRemove: () => setState(() {
                      draft.removeAt(i);
                      _rowIds.removeAt(i);
                      _dirty = true;
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  draft.add(const Injury(bodyPart: '', type: ''));
                  _rowIds.add(_nextRowId++);
                  _dirty = true;
                }),
                icon: const Icon(Icons.add),
                label: Text(l10n.injuriesAdd),
              ),
              const SizedBox(height: 20),
              AppPrimaryButton(
                // Same invisible-spinner shape as backup and video upload.
                loading: saving,
                onPressed: !_dirty ? null : () => _save(draft),
                label: l10n.injuriesSave,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(List<Injury> draft) async {
    final l10n = AppLocalizations.of(context);
    // Blank rows are dropped rather than saved: an injury with no body part is
    // not something the screening can use, and refusing the whole save over an
    // empty row the user forgot about would be worse than ignoring it.
    final cleaned = [
      for (final i in draft)
        if (i.bodyPart.trim().isNotEmpty) i,
    ];
    await ref.read(profileSubmitProvider.notifier).saveInjuries(cleaned);
    if (!mounted) return;
    final result = ref.read(profileSubmitProvider);
    final messenger = ScaffoldMessenger.of(context);
    result.when(
      data: (_) {
        setState(() => _dirty = false);
        messenger.showSnackBar(SnackBar(content: Text(l10n.injuriesSaved)));
      },
      loading: () {},
      error: (e, _) => messenger
          .showSnackBar(SnackBar(content: Text(l10n.homeCouldNotLoad('$e')))),
    );
  }
}

class _InjuryCard extends StatelessWidget {
  const _InjuryCard({
    super.key,
    required this.injury,
    required this.onChanged,
    required this.onRemove,
  });

  final Injury injury;
  final ValueChanged<Injury> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.injuriesBodyPart,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              AppIconButton(
                onPressed: onRemove,
                icon: Icons.delete_outline,
                tooltip: l10n.injuriesRemove,
              ),
            ],
          ),
          GlassTextField(
            value: injury.bodyPart,
            hint: l10n.injuriesBodyPartHint,
            onChanged: (v) => onChanged(injury.copyWith(bodyPart: v)),
          ),
          FieldLabel(l10n.injuriesType),
          GlassTextField(
            value: injury.type,
            hint: l10n.injuriesTypeHint,
            onChanged: (v) => onChanged(injury.copyWith(type: v)),
          ),
          FieldLabel(l10n.injuriesArea),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final region in InjuryRegion.values)
                ChoiceChip(
                  label: Text(_regionLabel(l10n, region)),
                  selected: injury.region == region,
                  onSelected: (_) => onChanged(
                    injury.copyWith(region: region, confirmed: false),
                  ),
                ),
              // Declining is a decision, and it is stored as one. Without it
              // the app cannot tell "nobody has looked at this" from "no
              // region fits", and would ask about a rib injury forever.
              ChoiceChip(
                label: Text(l10n.injuriesAreaNotListed),
                selected: injury.region == null && injury.confirmed,
                onSelected: (_) => onChanged(
                  injury.copyWith(clearRegion: true, confirmed: true),
                ),
              ),
            ],
          ),
          if (injury.region == null && injury.confirmed) ...[
            const SizedBox(height: 8),
            Text(l10n.injuriesNotScreenedForThis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colors.textSecondary,
                )),
          ],
          FieldLabel(l10n.injuriesNote),
          GlassTextField(
            value: injury.note ?? '',
            hint: l10n.injuriesNoteHint,
            maxLines: 2,
            onChanged: (v) => onChanged(injury.copyWith(note: v)),
          ),
        ],
      ),
    );
  }
}

String _regionLabel(AppLocalizations l10n, InjuryRegion region) {
  switch (region) {
    case InjuryRegion.neck:
      return l10n.injuryRegionNeck;
    case InjuryRegion.shoulder:
      return l10n.injuryRegionShoulder;
    case InjuryRegion.elbow:
      return l10n.injuryRegionElbow;
    case InjuryRegion.wrist:
      return l10n.injuryRegionWrist;
    case InjuryRegion.lowerBack:
      return l10n.injuryRegionLowerBack;
    case InjuryRegion.hip:
      return l10n.injuryRegionHip;
    case InjuryRegion.knee:
      return l10n.injuryRegionKnee;
    case InjuryRegion.ankle:
      return l10n.injuryRegionAnkle;
  }
}
