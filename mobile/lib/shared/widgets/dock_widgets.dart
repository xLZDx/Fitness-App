/// The shell dock widgets of S03-07 (contract S-4, 10.4; design 2.6, 6.4):
/// [RecordPill], [RecordingStrip] and [RailRecordSlot].
///
/// They are mounted by `MainShell` (lane L4a) in the dock above the bottom bar
/// or in the pinned Record slot of the side rail. This file decides WHAT is
/// shown; the host decides WHERE (position, animated padding, compaction
/// threshold) and passes `compact` / `extended` in.
///
/// Rules kept here:
///  * Neither widget touches a timer. They read
///    `activeSessionStatusProvider` only; a provider failure there already
///    yields "no session" (F-14), so nothing here can break the shell.
///  * No modal: a tap on the strip navigates (R-S3). The strip is never
///    mounted on pushed routes because only `MainShell` mounts it (R-S2).
///  * Seconds are not part of the semantics: the label carries whole minutes,
///    so it changes only at minute boundaries (R-S4). The visible seconds tick
///    is a widget-local `Timer.periodic`, started only for a rest that counts
///    down against a deadline, inside a `RepaintBoundary`, and it is not an
///    animation (reduced motion needs nothing from it).
///  * Layout uses start/end only and a chevron that mirrors in RTL.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/hud_tokens.dart';
import '../../core/theme/hud_typography.dart';
import '../../features/workouts/state/active_session_status.dart';
import '../../features/workouts/state/rest_timer_providers.dart';
import 'hud/hud_surface.dart';

/// Shell tab routes: reaching one of them replaces (`go`); anything else is a
/// pushed page (`push`), so Back returns to the tab the user was on.
const Set<String> _kShellTabPaths = <String>{
  '/home',
  '/workouts',
  '/scan',
  '/progress',
  '/profile',
};

/// Opens the place a running session lives. No modal (R-S3).
void openActiveSessionDestination(BuildContext context, String destination) {
  final GoRouter router = GoRouter.of(context);
  final String path = destination.split('?').first;
  if (_kShellTabPaths.contains(path)) {
    router.go(destination);
  } else {
    router.push(destination);
  }
}

String _stateWord(AppLocalizations l10n, ActiveSessionState s) => switch (s) {
      ActiveSessionState.running => l10n.stripWorkout,
      ActiveSessionState.paused => l10n.stripPaused,
      ActiveSessionState.resting => l10n.stripResting,
      ActiveSessionState.restFinished => l10n.stripRestDone,
    };

String _railWord(AppLocalizations l10n, ActiveSessionState s) => switch (s) {
      ActiveSessionState.running => l10n.railStateRunning,
      ActiveSessionState.paused => l10n.railStatePaused,
      ActiveSessionState.resting => l10n.railStateResting,
      ActiveSessionState.restFinished => l10n.railStateRestDone,
    };

IconData _stateIcon(ActiveSessionState s) => switch (s) {
      ActiveSessionState.running => Icons.fitness_center_rounded,
      ActiveSessionState.paused => Icons.pause_circle_outline_rounded,
      ActiveSessionState.resting => Icons.hourglass_bottom_rounded,
      ActiveSessionState.restFinished => Icons.check_circle_outline_rounded,
    };

/// `m:ss`, never negative.
String _formatClock(Duration d) {
  final int total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final int m = total ~/ 60;
  final int s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The accessible name of the strip: state word, optional title, mode, and
/// whole minutes. No seconds, so it is stable inside a minute (R-S4).
String _stripLabel(
  AppLocalizations l10n,
  ActiveSessionStatus status,
  DateTime now,
) {
  final List<String> parts = <String>[
    _stateWord(l10n, status.state),
    if (status.title.isNotEmpty) status.title,
    l10n.stripModeLabel(status.mode),
  ];
  final Duration? left = status.remainingAt(now);
  if (left != null && left.inMinutes > 0) {
    parts.add(l10n.stripSpokenMinutes(left.inMinutes));
  }
  return parts.join(', ');
}

/// Starts a 1 Hz repaint only while [need] is true (a rest counting down
/// against its deadline) and cancels it otherwise and on dispose.
mixin _DeadlineTicker<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  Timer? _tick;

  void syncTicker(bool need) {
    if (need && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!need && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tick = null;
    super.dispose();
  }
}

bool _needsTicker(ActiveSessionStatus? s) =>
    s != null &&
    s.state == ActiveSessionState.resting &&
    s.restEndsAt != null;

/// The idle dock control: opens the Record sheet (S-5). Key
/// `shell.dock.recordPill`.
///
/// [compact] collapses it to a 48 x 48 icon button with the same accessible
/// name and a tooltip (contract S-4 compaction; the host decides when the
/// visible height above the dock is under 240 dp).
class RecordPill extends StatelessWidget {
  const RecordPill({
    Key? key,
    required this.onPressed,
    this.compact = false,
  }) : super(key: key ?? const ValueKey<String>('shell.dock.recordPill'));

  /// Opens S-5.
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (compact) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Tooltip(
          message: l10n.recordPill,
          child: SizedBox(
            width: 48,
            height: 48,
            child: HudPanel(
              dense: true,
              radius: 24,
              padding: EdgeInsets.zero,
              onTap: onPressed,
              semanticLabel: l10n.recordPill,
              showFocusRing: true,
              hoverStyle: true,
              cursor: true,
              child: Center(
                child: Icon(
                  Icons.fiber_manual_record_rounded,
                  size: 22,
                  color: context.hud.textPrimary,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: HudButton(
        label: l10n.recordPill,
        icon: Icons.fiber_manual_record_rounded,
        centered: true,
        minHeight: 48,
        onPressed: onPressed,
        showFocusRing: true,
        hoverStyle: true,
        cursor: true,
      ),
    );
  }
}

/// The running-session strip. Reads `activeSessionStatusProvider` itself and
/// renders nothing when there is no session, so a host may mount it
/// unconditionally. Key `shell.dock.strip`.
///
/// [compact]: a single line, 48 dp high (short windows). [onOpen] overrides the
/// default navigation (`openActiveSessionDestination`) for hosts and tests.
class RecordingStrip extends ConsumerStatefulWidget {
  const RecordingStrip({
    Key? key,
    this.compact = false,
    this.onOpen,
  }) : super(key: key ?? const ValueKey<String>('shell.dock.strip'));

  final bool compact;

  /// Receives the destination route. Null navigates with GoRouter.
  final void Function(String destination)? onOpen;

  @override
  ConsumerState<RecordingStrip> createState() => _RecordingStripState();
}

class _RecordingStripState extends ConsumerState<RecordingStrip>
    with _DeadlineTicker<RecordingStrip> {
  @override
  Widget build(BuildContext context) {
    final ActiveSessionStatus? status = ref.watch(activeSessionStatusProvider);
    syncTicker(_needsTicker(status));
    if (status == null) return const SizedBox.shrink();

    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final DateTime now = ref.read(restClockProvider)();
    final Duration? left = status.remainingAt(now);
    final bool compact = widget.compact;

    final Widget words = compact
        ? Text(
            _stateWord(l10n, status.state),
            style: HudType.panelTitle(t),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_stateWord(l10n, status.state),
                  style: HudType.panelTitle(t)),
              if (status.title.isNotEmpty)
                Text(status.title, style: HudType.rowTitle(t)),
              Text(l10n.stripModeLabel(status.mode),
                  style: HudType.rowMeta(t)),
            ],
          );

    return RepaintBoundary(
      child: HudPanel(
        dense: true,
        radius: compact ? 24 : 28,
        padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 10, 8),
        onTap: () {
          final void Function(String)? open = widget.onOpen;
          if (open != null) {
            open(status.destination);
          } else {
            openActiveSessionDestination(context, status.destination);
          }
        },
        semanticLabel: _stripLabel(l10n, status, now),
        semanticHint: l10n.stripResumeHint,
        showFocusRing: true,
        hoverStyle: true,
        cursor: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 32 : 40),
          child: Row(
            children: <Widget>[
              Icon(_stateIcon(status.state), size: 20, color: t.accent),
              const SizedBox(width: 10),
              Expanded(child: words),
              if (left != null) ...<Widget>[
                const SizedBox(width: 8),
                Text(_formatClock(left), style: HudType.mono(t, size: 13)),
              ],
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: t.textSecondary,
                // Mirrors in RTL (contract RTL row).
                textDirection: Directionality.of(context),
                semanticLabel: null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pinned Record slot of the side rail (contract 10.4). Key
/// `shell.rail.record`.
///
/// Always mounted on all five tabs, so the destinations below never move:
///  * idle: an enabled Record button ([onRecord] opens S-5) with a visible
///    one-word label (icon above the label in the compact form);
///  * running, compact form: state icon, short state word and whole minutes on
///    two visible lines; the accessible name is the full strip label;
///  * running, extended form: the full [RecordingStrip].
///
/// The slot reserves at least 64 dp (compact) or 56 dp (extended) of height and
/// grows instead of overflowing at large text scales.
class RailRecordSlot extends ConsumerWidget {
  const RailRecordSlot({
    Key? key,
    required this.onRecord,
    this.extended = false,
    this.onOpenSession,
  }) : super(key: key ?? const ValueKey<String>('shell.rail.record'));

  /// Opens S-5 from the idle slot.
  final VoidCallback onRecord;

  /// Extended (240 dp) rail form.
  final bool extended;

  /// Receives the destination when the running slot is tapped. Null navigates
  /// with GoRouter.
  final void Function(String destination)? onOpenSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ActiveSessionStatus? status = ref.watch(activeSessionStatusProvider);
    final double reserved = extended ? 56 : 64;
    final Widget body;
    if (status == null && ref.watch(activeSessionForeignOwnerProvider)) {
      // A session of another account: no Record control, same reserved height.
      // The idle control is laid out invisibly so both states have the same size.
      body = ExcludeSemantics(
        child: ExcludeFocus(
          child: IgnorePointer(
            child: Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: _IdleRecord(onRecord: () {}, extended: extended),
            ),
          ),
        ),
      );
    } else if (status == null) {
      body = _IdleRecord(onRecord: onRecord, extended: extended);
    } else if (extended) {
      body = RecordingStrip(onOpen: onOpenSession);
    } else {
      body = _CompactRunning(onOpen: onOpenSession);
    }
    return RepaintBoundary(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: reserved),
        child: Align(alignment: Alignment.center, child: body),
      ),
    );
  }
}

class _IdleRecord extends StatelessWidget {
  const _IdleRecord({required this.onRecord, required this.extended});

  final VoidCallback onRecord;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final Icon icon = Icon(
      Icons.fiber_manual_record_rounded,
      size: 22,
      color: t.textPrimary,
    );
    final Text label = Text(
      l10n.recordPill,
      style: HudType.panelTitle(t),
      textAlign: TextAlign.center,
    );
    return HudPanel(
      dense: true,
      radius: 22,
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
      onTap: onRecord,
      semanticLabel: l10n.recordPill,
      showFocusRing: true,
      hoverStyle: true,
      cursor: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40, minWidth: 48),
        child: extended
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  icon,
                  const SizedBox(width: 9),
                  Flexible(child: label),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[icon, const SizedBox(height: 2), label],
              ),
      ),
    );
  }
}

class _CompactRunning extends ConsumerStatefulWidget {
  const _CompactRunning({this.onOpen});

  final void Function(String destination)? onOpen;

  @override
  ConsumerState<_CompactRunning> createState() => _CompactRunningState();
}

class _CompactRunningState extends ConsumerState<_CompactRunning>
    with _DeadlineTicker<_CompactRunning> {
  @override
  Widget build(BuildContext context) {
    final ActiveSessionStatus? status = ref.watch(activeSessionStatusProvider);
    syncTicker(_needsTicker(status));
    if (status == null) return const SizedBox.shrink();

    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final DateTime now = ref.read(restClockProvider)();
    final Duration? left = status.remainingAt(now);

    return HudPanel(
      dense: true,
      radius: 22,
      padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 6, 6),
      onTap: () {
        final void Function(String)? open = widget.onOpen;
        if (open != null) {
          open(status.destination);
        } else {
          openActiveSessionDestination(context, status.destination);
        }
      },
      semanticLabel: _stripLabel(l10n, status, now),
      semanticHint: l10n.stripResumeHint,
      showFocusRing: true,
      hoverStyle: true,
      cursor: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_stateIcon(status.state), size: 18, color: t.accent),
            Text(
              _railWord(l10n, status.state),
              style: HudType.rowTitle(t),
              textAlign: TextAlign.center,
            ),
            if (left != null && left.inMinutes > 0)
              Text(
                l10n.railMinutes(left.inMinutes),
                style: HudType.rowMeta(t),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
