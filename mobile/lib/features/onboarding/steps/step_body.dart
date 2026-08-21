import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../profile/data/profile_models.dart';
import '../state/questionnaire_notifier.dart';
import '../widgets/body_zone_map.dart';
import '../widgets/inputs.dart';
import 'step_health.dart';

/// O6 — the body screen: what to avoid, and what to prioritise.
///
/// ## Two questions, one screen, two tabs
///
/// They look like the same question and are opposites. "My knee hurts" must
/// remove exercises; "I want to work my legs" must add them. Asking both on one
/// tab would produce a list where a tap means whichever the user assumed.
///
/// ## Where the answers go
///
/// Limitations write [Injury.region] — the enum, the tag vocabulary and the
/// filter's matching already existed (`exercise_filter.dart`); onboarding
/// simply never wrote into them, so every injury arrived as free text with a
/// null region. Priorities write [FitnessGoals.focusZones], which is new
/// because nothing in the model expressed "train this more".
///
/// ## The medical questions did not go anywhere
///
/// They are under the disclosure at the bottom, unchanged, because the operator
/// asked for that screen to be left alone. It moved; it was not rewritten.
class StepBody extends ConsumerStatefulWidget {
  const StepBody({super.key});

  @override
  ConsumerState<StepBody> createState() => _StepBodyState();
}

class _StepBodyState extends ConsumerState<StepBody> {
  int _tab = 0;
  bool _medicalOpen = false;

  /// Adds or removes a limitation for [region].
  ///
  /// Removal only takes entries this screen could have created — a region with
  /// no injury type. An injury the user typed out ("колено: растяжение") keeps
  /// its region and its words: untapping a chip must not delete something they
  /// wrote on another screen, and the chip stays lit because a real injury for
  /// that region still exists.
  void _toggleRegion(InjuryRegion region, String label) {
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    final current = ref.read(questionnaireDraftProvider).health.injuries;
    final already = current.any((i) => i.region == region);
    notifier.updateHealth((h) => h.copyWith(
          injuries: already
              ? [
                  for (final i in current)
                    if (!(i.region == region && i.type.isEmpty)) i,
                ]
              : [
                  ...current,
                  // `bodyPart` is normally what the user typed. Nothing was
                  // typed here, so it carries the region's own name — the
                  // field stays readable instead of empty, and `region` is the
                  // part anything downstream actually matches on.
                  Injury(bodyPart: label, type: '', region: region),
                ],
        ));
  }

  /// Adds or removes [zone] from the priorities.
  ///
  /// Enum order, not tap order — the list is persisted and compared. Same rule
  /// as the equipment chips in O4.
  void _toggleFocus(FocusZone zone) {
    final notifier = ref.read(questionnaireDraftProvider.notifier);
    final current = ref.read(questionnaireDraftProvider).goals.focusZones;
    final next = current.contains(zone)
        ? (current.toSet()..remove(zone))
        : (current.toSet()..add(zone));
    notifier.updateGoals(
      (g) => g.copyWith(
        focusZones: [
          for (final z in FocusZone.values)
            if (next.contains(z)) z,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = ref.watch(questionnaireDraftProvider);
    final regions =
        draft.health.injuries.map((i) => i.region).whereType<InjuryRegion>().toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StepTitle(
          title: l10n.onbBodyTitle,
          subtitle: l10n.onbBodySubtitle,
        ),
        const SizedBox(height: 16),
        _TabBar(
          labels: [l10n.onbBodyTabLimits, l10n.onbBodyTabFocus],
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 16),
        if (_tab == 0) ...[
          Center(
            child: SizedBox(
              width: 190,
              child: BodyZoneMap.limitations(
                selected: regions,
                onToggle: (r) => _toggleRegion(r, _regionLabel(l10n, r)),
              ),
            ),
          ),
          FieldLabel(l10n.onbBodyLimitsLabel),
          MultiChoiceChips<InjuryRegion>(
            options: InjuryRegion.values,
            labelOf: (r) => _regionLabel(l10n, r),
            values: regions,
            // Routed through the same toggle as the drawing, one region at a
            // time, rather than diffing the whole set: the set the chips hand
            // back cannot say which typed-out injuries it stands for, and
            // rebuilding the list from it would erase them.
            onChanged: (next) {
              final added = next.difference(regions);
              final removed = regions.difference(next);
              for (final r in [...added, ...removed]) {
                _toggleRegion(r, _regionLabel(l10n, r));
              }
            },
          ),
        ] else ...[
          // Same figure as the limitations tab, per the operator: asking two
          // questions about the body and drawing it for only one of them made
          // the second look like a lesser question.
          Center(
            child: SizedBox(
              width: 190,
              child: BodyZoneMap.priorities(
                selected: draft.goals.focusZones.toSet(),
                onToggle: (z) => _toggleFocus(z),
              ),
            ),
          ),
          FieldLabel(l10n.onbBodyFocusLabel),
          MultiChoiceChips<FocusZone>(
            options: FocusZone.values,
            labelOf: (z) => _focusLabel(l10n, z),
            values: draft.goals.focusZones.toSet(),
            // Routed through the same toggle as the drawing, one zone at a
            // time — same shape as the limitations tab above, so the two
            // controls cannot disagree about what a tap means.
            onChanged: (next) {
              final current = draft.goals.focusZones.toSet();
              for (final z in [
                ...next.difference(current),
                ...current.difference(next),
              ]) {
                _toggleFocus(z);
              }
            },
          ),
        ],
        const SizedBox(height: 8),
        _Disclosure(
          title: l10n.onbBodyMedicalDisclosure,
          open: _medicalOpen,
          onToggle: () => setState(() => _medicalOpen = !_medicalOpen),
          // The health step's own widget, called as-is. Copying its fields into
          // this file would have created a second set of controls writing the
          // same model — the drift every other duplicated shape in this
          // codebase has already caused once.
          child: const StepHealth(showTitle: false),
        ),
      ],
    );
  }
}

/// Two-segment selector for the screen's tabs.
///
/// A `TabBar` needs a `TabController` and therefore a `TickerProvider` and a
/// `TabBarView`, which would put both tabs' subtrees in the widget tree at once
/// — including the body drawing — for a screen that shows one at a time inside
/// an already-scrolling page. Two buttons and an int do the same job here.
class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.subPanel.fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.subPanel.innerBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    // The fill is the selection state itself, so keep an
                    // instant change under reduce motion instead of losing
                    // which tab is selected.
                    duration: context.hudMotionDuration(
                      const Duration(milliseconds: 180),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: i == index
                          ? t.accent.withValues(alpha: 0.20)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      style: HudType.rowTitle(t, strong: i == index).copyWith(
                          color: i == index ? t.textPrimary : t.textSecondary),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A header that reveals its child.
///
/// Not `ExpansionTile`: that paints its own Material surface and dividers,
/// which read as a settings row in the middle of a questionnaire.
class _Disclosure extends StatelessWidget {
  const _Disclosure({
    required this.title,
    required this.open,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final bool open;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: GestureDetector(
            onTap: onToggle,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: HudType.rowTitle(t, strong: true)
                            .copyWith(color: t.textSecondary)
                            .overPhoto(t)),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    color: t.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (open) child,
      ],
    );
  }
}

String _regionLabel(AppLocalizations l, InjuryRegion r) => switch (r) {
      InjuryRegion.neck => l.bodyRegionNeck,
      InjuryRegion.upperBack => l.bodyRegionUpperBack,
      InjuryRegion.shoulder => l.bodyRegionShoulder,
      InjuryRegion.elbow => l.bodyRegionElbow,
      InjuryRegion.wrist => l.bodyRegionWrist,
      InjuryRegion.lowerBack => l.bodyRegionLowerBack,
      InjuryRegion.hip => l.bodyRegionHip,
      InjuryRegion.knee => l.bodyRegionKnee,
      InjuryRegion.ankle => l.bodyRegionAnkle,
    };

String _focusLabel(AppLocalizations l, FocusZone z) => switch (z) {
      FocusZone.chest => l.focusZoneChest,
      FocusZone.back => l.focusZoneBack,
      FocusZone.shoulders => l.focusZoneShoulders,
      FocusZone.arms => l.focusZoneArms,
      FocusZone.core => l.focusZoneCore,
      FocusZone.glutes => l.focusZoneGlutes,
      FocusZone.legs => l.focusZoneLegs,
      FocusZone.fullBody => l.focusZoneFullBody,
    };
