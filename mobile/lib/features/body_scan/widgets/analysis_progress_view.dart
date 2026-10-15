/// Named-stage analysis progress (design s10 honest timing UI, D-41, D-81).
///
/// Announcement contract: ONE polite live region carries only stage changes
/// and the 20 s "taking longer" notice; the 25 s timeout is announced once
/// assertively and focus moves to Retry. The elapsed counter is a plain element
/// (never a live region, never part of an announcement). Cancel is first in
/// focus and semantics order. With reduced motion there is no animation, only
/// static text and "Step n of 5".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/hud_tokens.dart';
import '../../../shared/widgets/glass.dart';

/// The five user-visible stages, in order.
enum AnalysisStage { photos, composition, plausibility, trend, saved }

const Duration kSlowNoticeAfter = Duration(seconds: 20);
const Duration kTimeoutAfter = Duration(seconds: 25);

/// `m:ss` elapsed text (digits only, locale independent).
String formatElapsed(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class AnalysisProgressView extends StatefulWidget {
  const AnalysisProgressView({
    super.key,
    required this.stage,
    required this.startedAt,
    required this.onCancel,
    required this.onRetry,
    this.photosKeptLocal = false,
    this.now = DateTime.now,
  });

  final AnalysisStage stage;
  final DateTime startedAt;

  /// The provider needs no photos: stage 1 reads "kept on this device".
  final bool photosKeptLocal;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final DateTime Function() now;

  @override
  State<AnalysisProgressView> createState() => _AnalysisProgressViewState();
}

class _AnalysisProgressViewState extends State<AnalysisProgressView> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _keepWaiting = false;
  bool _timeoutAnnounced = false;
  final FocusNode _retryFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final e = widget.now().difference(widget.startedAt);
    if (!mounted) return;
    setState(() => _elapsed = e);
    if (e >= kTimeoutAfter && !_timeoutAnnounced) {
      _timeoutAnnounced = true;
      final l10n = AppLocalizations.of(context);
      SemanticsService.announce(
        l10n.bodyScanTimeout,
        Directionality.of(context),
        assertiveness: Assertiveness.assertive,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _retryFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retryFocus.dispose();
    super.dispose();
  }

  String _stageName(AppLocalizations l10n, AnalysisStage s) => switch (s) {
        AnalysisStage.photos => widget.photosKeptLocal
            ? l10n.bodyScanStagePhotosLocal
            : l10n.bodyScanStagePhotos,
        AnalysisStage.composition => l10n.bodyScanStageComposition,
        AnalysisStage.plausibility => l10n.bodyScanStagePlausibility,
        AnalysisStage.trend => l10n.bodyScanStageTrend,
        AnalysisStage.saved => l10n.bodyScanStageSaved,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hud = context.hud;
    final total = AnalysisStage.values.length;
    final current = widget.stage.index;
    final timedOut = _elapsed >= kTimeoutAfter;
    final slow = _elapsed >= kSlowNoticeAfter && !timedOut;
    final stageText = l10n.bodyScanStageAnnounce(
        current + 1, total, _stageName(l10n, widget.stage));
    // Only stage changes and the slow notice ever enter the live region.
    final live = timedOut
        ? ''
        : slow && !_keepWaiting
            ? '$stageText. ${l10n.bodyScanSlowNotice}'
            : stageText;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: ListView(
        padding: const EdgeInsets.all(HudTokens.screenGutter),
        children: [
          FocusTraversalOrder(
            order: const NumericFocusOrder(0),
            child: Semantics(
              sortKey: const OrdinalSortKey(0),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('bodyScan.progress.cancel'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: widget.onCancel,
                  child: Text(l10n.bodyScanCancel),
                ),
              ),
            ),
          ),
          Semantics(
            sortKey: const OrdinalSortKey(1),
            header: true,
            child: Text(l10n.bodyScanAnalysingTitle,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(color: hud.textPrimary)),
          ),
          const SizedBox(height: 12),
          Semantics(
            key: const Key('bodyScan.progress.live'),
            sortKey: const OrdinalSortKey(2),
            liveRegion: true,
            container: true,
            child: Text(live,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: hud.textPrimary)),
          ),
          const SizedBox(height: 12),
          GlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in AnalysisStage.values)
                  _StageRow(
                    name: _stageName(l10n, s),
                    state: s.index < current
                        ? l10n.bodyScanStageDone
                        : s.index == current
                            ? l10n.bodyScanStageActive
                            : l10n.bodyScanStagePending,
                    icon: s.index < current
                        ? Icons.check_circle_outline
                        : s.index == current
                            ? Icons.timelapse
                            : Icons.radio_button_unchecked,
                  ),
                const SizedBox(height: 12),
                if (!context.reduceMotion && !timedOut)
                  const LinearProgressIndicator(
                      key: Key('bodyScan.progress.indicator')),
                const SizedBox(height: 8),
                // Plain element: not a live region.
                ExcludeSemantics(
                  excluding: false,
                  child: Text(l10n.bodyScanElapsed(formatElapsed(_elapsed)),
                      key: const Key('bodyScan.progress.elapsed'),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: hud.textSecondary)),
                ),
              ],
            ),
          ),
          if (slow) ...[
            const SizedBox(height: 12),
            Text(l10n.bodyScanSlowNotice,
                key: const Key('bodyScan.progress.slow'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: hud.textSecondary)),
            if (!_keepWaiting)
              TextButton(
                key: const Key('bodyScan.progress.keepWaiting'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => setState(() => _keepWaiting = true),
                child: Text(l10n.bodyScanKeepWaiting),
              ),
          ],
          if (timedOut) ...[
            const SizedBox(height: 12),
            Text(l10n.bodyScanTimeout,
                key: const Key('bodyScan.progress.timeout'),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: context.colors.danger)),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('bodyScan.progress.retry'),
              focusNode: _retryFocus,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: widget.onRetry,
              child: Text(l10n.bodyScanRetry),
            ),
          ],
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  const _StageRow(
      {required this.name, required this.state, required this.icon});

  final String name;
  final String state;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final hud = context.hud;
    return Semantics(
      container: true,
      label: '$name, $state',
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Icon(icon, color: hud.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: hud.textPrimary)),
            ),
            Text(state,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: hud.textSecondary)),
          ],
        ),
      ),
    );
  }
}
