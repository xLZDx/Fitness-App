/// The Record sheet S-5 (design 2.3, 6.5; contract S-5; S03-11).
///
/// The single place where "start something" is offered for the current mode. It
/// creates no capability: every row navigates into an existing flow, and opening
/// or closing the sheet performs no write. It is not opened while a session is
/// running (the dock shows the strip instead; the check here is a second guard).
///
/// Wiring: the app root provides [openRecordSheet] as the value of
/// `shellRecordSheetOpenerProvider`.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/adaptive_surface.dart';
import '../../../shared/widgets/hud/hud_metric.dart' show HudSettingRow;
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../progress_photos/scan/scan_access.dart'
    show ScanAccess, scanAccessProvider;
import '../../progress_photos/scan/ui/scan_gate_view.dart'
    show scanAccessMessage;
import '../../workouts/data/scheduled_session.dart';
import '../../workouts/data/session_digest.dart';
import '../../workouts/state/active_session_status.dart'
    show activeSessionStatusProvider;
import '../../workouts/state/session_digest_providers.dart';
import '../data/mode_models.dart';
import '../state/mode_providers.dart';

/// Row ids (keys `recordSheet.row.<id>`).
const String kRecordTrainScan = 'trainScan';
const String kRecordTrainToday = 'trainToday';
const String kRecordTrainChoose = 'trainChoose';
const String kRecordTrainForm = 'trainForm';
const String kRecordBodyScan = 'bodyScan';
const String kRecordBodyMeal = 'bodyMeal';
const String kRecordBodyWeight = 'bodyWeight';

/// One row of the sheet, without any text (labels come from ARB at render time).
class RecordRowSpec {
  const RecordRowSpec({
    required this.id,
    required this.destination,
    this.enabled = true,
    this.refusedBy,
  });

  final String id;

  /// An existing route, opened with `push`.
  final String destination;

  /// False when the existing access gate refuses the row; the reason is then
  /// [refusedBy] and the row is shown disabled.
  final bool enabled;
  final ScanAccess? refusedBy;
}

/// The rows of [mode], in order (the first is the primary row). Pure.
///
///  * [todayPath] is the start target of a workout scheduled today, or null
///    (then the "Today's workout" row is absent).
///  * [scanAccess] is the existing body-scan gate. Only `allowed` and
///    `needsConsent` open the flow (the flow asks for consent itself); every
///    other outcome gives a disabled row with the gate's reason.
///  * Ride and Explore have no rows in S03.
List<RecordRowSpec> recordRowsFor(
  AppMode mode, {
  String? todayPath,
  ScanAccess scanAccess = ScanAccess.allowed,
}) {
  switch (mode) {
    case AppMode.train:
      return <RecordRowSpec>[
        const RecordRowSpec(id: kRecordTrainScan, destination: '/scan'),
        if (todayPath != null)
          RecordRowSpec(id: kRecordTrainToday, destination: todayPath),
        const RecordRowSpec(id: kRecordTrainChoose, destination: '/workouts'),
        const RecordRowSpec(id: kRecordTrainForm, destination: '/form-check'),
      ];
    case AppMode.body:
      final bool scanOk = scanAccess == ScanAccess.allowed ||
          scanAccess == ScanAccess.needsConsent;
      return <RecordRowSpec>[
        RecordRowSpec(
          id: kRecordBodyScan,
          destination: '/body-scan',
          enabled: scanOk,
          refusedBy: scanOk ? null : scanAccess,
        ),
        const RecordRowSpec(id: kRecordBodyMeal, destination: '/nutrition/add'),
        const RecordRowSpec(
            id: kRecordBodyWeight, destination: '/nutrition/weight'),
      ];
    case AppMode.ride:
    case AppMode.explore:
      return const <RecordRowSpec>[];
  }
}

/// The start target of a workout scheduled TODAY in [digest], or null. Same
/// target as the Home day panel: `/workout/<exerciseId>?day=<sessionId>`.
String? todayWorkoutPath(SessionDigest digest, DateTime now) {
  if (digest.sessions.isEmpty) return null;
  final ScheduledSession s = digest.sessions.first;
  final DateTime d = s.scheduledFor;
  final bool today = d.year == now.year && d.month == now.month && d.day == now.day;
  if (!today || s.status != ScheduledSessionStatus.pending) return null;
  return '/workout/${Uri.encodeComponent(s.exerciseId)}?day=${Uri.encodeComponent(s.id)}';
}

bool _recordOpen = false;

/// Opens the Record sheet. Matches `ShellRecordSheetOpener`. A second call while
/// open, or while a session is running, is a no-op. [anchorKey] is the rail
/// Record slot on Expanded (without a mounted anchor: a centred dialog).
void openRecordSheet(BuildContext context, {GlobalKey? anchorKey}) {
  if (_recordOpen) return;
  try {
    final ProviderContainer container =
        ProviderScope.containerOf(context, listen: false);
    if (container.read(activeSessionStatusProvider) != null) return;
  } on StateError {
    // No ProviderScope: nothing to check; the sheet itself needs one.
    return;
  }
  _recordOpen = true;
  try {
    final String label = AppLocalizations.of(context)
        .recordSheetTitle(_modeNameForTitle(context));
    unawaited(
      AdaptiveSurface.show<void>(
        context,
        (BuildContext ctx) => const RecordSheet(),
        anchorKey: anchorKey,
        semanticLabel: label,
      ).whenComplete(() => _recordOpen = false),
    );
  } catch (_) {
    _recordOpen = false;
    rethrow;
  }
}

String _modeNameForTitle(BuildContext context) {
  try {
    final ProviderContainer c =
        ProviderScope.containerOf(context, listen: false);
    return c.read(modeStateProvider).valueOrNull?.selectedMode.name ?? 'train';
  } on StateError {
    return 'train';
  }
}

class RecordSheet extends ConsumerWidget {
  const RecordSheet({super.key});

  IconData _icon(String id) => switch (id) {
        kRecordTrainScan => Icons.qr_code_scanner_rounded,
        kRecordTrainToday => Icons.play_circle_outline_rounded,
        kRecordTrainChoose => Icons.fitness_center_rounded,
        kRecordTrainForm => Icons.accessibility_new_rounded,
        kRecordBodyScan => Icons.camera_alt_outlined,
        kRecordBodyMeal => Icons.restaurant_rounded,
        _ => Icons.monitor_weight_outlined,
      };

  String _label(AppLocalizations l10n, String id) => switch (id) {
        kRecordTrainScan => l10n.recordTrainScan,
        kRecordTrainToday => l10n.recordTrainToday,
        kRecordTrainChoose => l10n.recordTrainChoose,
        kRecordTrainForm => l10n.recordTrainForm,
        kRecordBodyScan => l10n.recordBodyScan,
        kRecordBodyMeal => l10n.recordBodyMeal,
        _ => l10n.recordBodyWeight,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final AppMode mode =
        ref.watch(modeStateProvider).valueOrNull?.selectedMode ?? AppMode.train;
    final ScanAccess access =
        mode == AppMode.body ? ref.watch(scanAccessProvider) : ScanAccess.allowed;
    final String? today = mode == AppMode.train
        ? todayWorkoutPath(ref.watch(todayDigestProvider), DateTime.now())
        : null;
    final List<RecordRowSpec> specs =
        recordRowsFor(mode, todayPath: today, scanAccess: access);

    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < specs.length; i++) {
      final RecordRowSpec s = specs[i];
      final String? reason =
          s.refusedBy == null ? null : scanAccessMessage(l10n, s.refusedBy!);
      rows.add(
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: HudSettingRow(
            key: Key('recordSheet.row.${s.id}'),
            icon: _icon(s.id),
            title: _label(l10n, s.id),
            subtitle: reason,
            mergeSemantics: true,
            semanticHint: reason,
            enabled: s.enabled,
            trailing: i == 0 && s.enabled
                ? Icon(Icons.fiber_manual_record, size: 10, color: t.accent)
                : null,
            showFocusRing: true,
            hoverStyle: true,
            cursor: true,
            onTap: s.enabled
                ? () {
                    // Close first, then navigate: no write, no state change.
                    final GoRouter router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    unawaited(router.push<void>(s.destination));
                  }
                : null,
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          key: const Key('recordSheet'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Focus(
                autofocus: true,
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.recordSheetTitle(mode.name),
                    style: HudType.rowTitle(t, strong: true)
                        .copyWith(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty) ...<Widget>[
                Text(
                  l10n.recordNothingHere,
                  key: const Key('recordSheet.empty'),
                  style: HudType.body(t, size: 13),
                ),
                const SizedBox(height: 16),
                HudButton(
                  key: const Key('recordSheet.openTrain'),
                  label: l10n.recordOpenTrain,
                  centered: true,
                  onPressed: () {
                    final ModeNotifier notifier =
                        ref.read(modeStateProvider.notifier);
                    Navigator.of(context).pop();
                    unawaited(notifier.selectMode(AppMode.train));
                  },
                ),
              ] else
                ...rows,
            ],
          ),
        ),
      ),
    );
  }
}
