/// Sources panel S-8 (design 2.5, 6.8; contract S-8, AC-SRC-1 to AC-SRC-7).
///
/// An honest, read-only answer to "where does my data come from". Information
/// rows only: no device adapter is called and no permission is requested. The
/// app row follows the journal availability; every other fixed row says
/// "Not connected" because no adapter exists in S03. Sources found in the
/// journal that have no fixed row (file import, service, unknown) are listed
/// below the fixed rows with the label of contract 8.1.
///
/// Keys: `sources.row.<id>`, `sources.dedupNote`, `sources.app.retry`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../core/wiring/activity_wiring.dart';
import '../../../shared/widgets/hud/hud_scaffold.dart';
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../../shared/widgets/shell_back_button.dart';
import '../../activity/data/activity_aggregates.dart';
import '../../activity/data/device_source.dart';
import '../../activity/state/activity_dashboard_providers.dart';
import '../../activity/state/journal_availability.dart';

/// Content width above which the dedup note moves to a side pane (contract
/// AC-LS-6: one column at 700 dp and below, two columns at 1100 dp).
const double _kTwoPaneMinWidth = 880;

/// The widest the page content grows (contract AC-LS-6).
const double _kContentMaxWidth = 880;

/// Width of the side pane that holds the dedup note.
const double _kSidePaneWidth = 280;

enum _Status { inUse, ready, notConnected, notActive, problem, checking }

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key});

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage> {
  @override
  void initState() {
    super.initState();
    // Once on entry, never from build (design 3.7).
    ref.read(activityDigestsProvider.notifier).refreshIfStale();
  }

  String _statusText(AppLocalizations l10n, _Status s) => switch (s) {
        _Status.inUse => l10n.sourceStatusInUse,
        _Status.ready => l10n.sourceStatusReady,
        _Status.notConnected => l10n.sourceStatusNotConnected,
        _Status.notActive => l10n.sourceStatusNotActive,
        _Status.problem => l10n.sourceStatusError,
        _Status.checking => l10n.sourceStatusChecking,
      };

  IconData _statusIcon(_Status s) => switch (s) {
        _Status.inUse => Icons.check_circle_outline,
        _Status.ready => Icons.circle_outlined,
        _Status.notConnected => Icons.link_off,
        _Status.notActive => Icons.pause_circle_outline,
        _Status.problem => Icons.error_outline,
        _Status.checking => Icons.hourglass_empty,
      };

  String _labelText(AppLocalizations l10n, SourceLabelKey key) => switch (key) {
        SourceLabelKey.app => l10n.sourceLabelApp,
        SourceLabelKey.healthConnect => l10n.sourceHealthConnect,
        // No Apple Health row exists in S03; a stored record is still named.
        SourceLabelKey.healthKit => l10n.sourceLabelHealthPlatform,
        SourceLabelKey.watch => l10n.sourceWatch,
        SourceLabelKey.sensor => l10n.sourceLabelSensor,
        SourceLabelKey.healthPlatform => l10n.sourceLabelHealthPlatform,
        SourceLabelKey.service => l10n.sourceLabelService,
        SourceLabelKey.companionApp => l10n.sourceLabelCompanionApp,
        SourceLabelKey.fileImport => l10n.sourceLabelFileImport,
        SourceLabelKey.unknown => l10n.sourceLabelUnknown,
      };

  String _capName(AppLocalizations l10n, CapabilityColumn c) => switch (c) {
        CapabilityColumn.sessionList => l10n.sourceCapSessionList,
        CapabilityColumn.heartRate => l10n.sourceCapHeartRate,
        CapabilityColumn.speedPace => l10n.sourceCapSpeedPace,
        CapabilityColumn.cadence => l10n.sourceCapCadence,
        CapabilityColumn.power => l10n.sourceCapPower,
        CapabilityColumn.gpsRoute => l10n.sourceCapGpsRoute,
        CapabilityColumn.strokesLaps => l10n.sourceCapStrokesLaps,
        CapabilityColumn.steps => l10n.sourceCapSteps,
        CapabilityColumn.sleep => l10n.sourceCapSleep,
        CapabilityColumn.liveStream => l10n.sourceCapLiveStream,
      };

  /// "May provide ..." from the yes/partial levels of the matrix rows
  /// [matrixIds]; "Unknown" when no level is yes or partial.
  String _mayProvide(AppLocalizations l10n, List<String> matrixIds) {
    final List<String> names = <String>[];
    for (final CapabilityColumn col in CapabilityColumn.values) {
      for (final String id in matrixIds) {
        final SourceCapabilities? caps = kCapabilityMatrix[id];
        if (caps == null) continue;
        final CapabilityLevel level = caps.levelOf(col);
        if (level == CapabilityLevel.yes || level == CapabilityLevel.partial) {
          names.add(_capName(l10n, col));
          break;
        }
      }
    }
    if (names.isEmpty) return l10n.sourceCapUnknown;
    return l10n.sourceMayProvide(names.join(', '));
  }

  /// The app row state: availability first, then the loaded digests.
  ({_Status status, bool retry, VoidCallback? onRetry, String? line}) _appRow(
    AppLocalizations l10n,
    JournalAvailability availability,
  ) {
    switch (availability) {
      case JournalNotEnabled():
        return (
          status: _Status.notActive,
          retry: false,
          onRetry: null,
          line: l10n.sourcesNotActiveLine,
        );
      case JournalBinding():
        return (
          status: _Status.checking,
          retry: false,
          onRetry: null,
          line: null,
        );
      case JournalGaveUp():
        // A manual attempt is running: the button stays disabled meanwhile.
        final bool bindBusy = ref
            .watch(activityBindStatusProvider.select((s) => s.bindBusy));
        return (
          status: _Status.problem,
          retry: true,
          onRetry: bindBusy
              ? null
              : () {
                  ref.read(activityBindStatusProvider.notifier).retryNow();
                },
          line: l10n.activityJournalFailed,
        );
      case JournalFailedToOpen():
        // Not retriable (retryNow is notApplicable): no Try again button.
        return (
          status: _Status.problem,
          retry: false,
          onRetry: null,
          line: l10n.activityJournalFailed,
        );
      case JournalOpen():
        final DigestSnapshot? snap = ref.watch(activityDigestSnapshotProvider);
        if (snap != null && snap.lastLoadFailedAt != null) {
          final String time = DateFormat.Hm(l10n.localeName)
              .format(snap.lastLoadFailedAt!.toLocal());
          return (
            status: _Status.problem,
            retry: true,
            onRetry: () {
              ref.read(activityDigestsProvider.notifier).refresh();
            },
            line: l10n.activityStaleNotice(time),
          );
        }
        if (snap != null) {
          return (
            status: snap.digests.isEmpty ? _Status.ready : _Status.inUse,
            retry: false,
            onRetry: null,
            line: null,
          );
        }
        if (ref.watch(activityDigestsProvider).hasError) {
          return (
            status: _Status.problem,
            retry: true,
            onRetry: () {
              ref.read(activityDigestsProvider.notifier).refresh();
            },
            line: l10n.activityJournalFailed,
          );
        }
        return (
          status: _Status.checking,
          retry: false,
          onRetry: null,
          line: null,
        );
    }
  }

  /// Label keys of journal sessions that no fixed row represents.
  List<SourceLabelKey> _extraSources() {
    final DigestSnapshot? snap = ref.watch(activityDigestSnapshotProvider);
    if (snap == null) return const <SourceLabelKey>[];
    const Set<SourceLabelKey> covered = <SourceLabelKey>{
      SourceLabelKey.app,
      SourceLabelKey.healthConnect,
      SourceLabelKey.watch,
      SourceLabelKey.sensor,
    };
    final Set<SourceLabelKey> found = <SourceLabelKey>{};
    for (final SessionDigest d in snap.digests) {
      final SourceLabelKey key = sourceLabelOf(d).key;
      if (!covered.contains(key)) found.add(key);
    }
    return found.toList()..sort((a, b) => a.index.compareTo(b.index));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;
    final JournalAvailability availability =
        ref.watch(journalAvailabilityProvider);
    final app = _appRow(l10n, availability);
    final List<SourceLabelKey> extras = _extraSources();
    // Activities dropped or route-less after the last recovery (RV-10); the
    // counts belong to the bound journal, so only an open journal shows them.
    final int lostCount = availability is JournalOpen
        ? ref.watch(activityBindStatusProvider.select(
            (ActivityBindStatus s) =>
                s.recoveredAbsentCount + s.streamLostCount))
        : 0;

    final List<Widget> rows = <Widget>[
      _SourceRow(
        rowKey: const Key('sources.row.app'),
        name: l10n.sourceApp,
        statusText: _statusText(l10n, app.status),
        statusIcon: _statusIcon(app.status),
        line: app.line,
        retryLabel: app.retry ? l10n.activityJournalRetry : null,
        onRetry: app.onRetry,
      ),
      for (final (String id, String name, List<String> matrixIds)
          in <(String, String, List<String>)>[
        ('health_connect', l10n.sourceHealthConnect, <String>['health_connect']),
        (
          'ble',
          l10n.sourceBle,
          kCapabilityMatrix.keys
              .where((String k) => k.startsWith('ble_'))
              .toList(),
        ),
        ('wear_os', l10n.sourceWatch, <String>['wear_os']),
        ('vendor_cloud', l10n.sourceOther, <String>['vendor_cloud']),
      ])
        _SourceRow(
          rowKey: Key('sources.row.$id'),
          name: name,
          statusText: _statusText(l10n, _Status.notConnected),
          statusIcon: _statusIcon(_Status.notConnected),
          line: _mayProvide(l10n, matrixIds),
        ),
      for (final SourceLabelKey key in extras)
        _SourceRow(
          rowKey: Key('sources.row.${key.name}'),
          name: _labelText(l10n, key),
          statusText: _statusText(l10n, _Status.inUse),
          statusIcon: _statusIcon(_Status.inUse),
        ),
    ];

    final Widget dedupNote = HudPanel(
      key: const Key('sources.dedupNote'),
      secondary: true,
      child: Text(l10n.sourcesDedupNote, style: HudType.body(t, size: 12.5)),
    );

    final Widget content = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool twoPane = constraints.maxWidth >= _kTwoPaneMinWidth;
        final Widget column = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (lostCount > 0) ...<Widget>[
              HudPanel(
                key: const Key('sources.recoveryNotice'),
                secondary: true,
                child: Text(
                  l10n.activityRecoveryNotice(lostCount),
                  style: HudType.body(t, size: 12.5),
                ),
              ),
              const SizedBox(height: 10),
            ],
            for (final Widget r in rows) ...<Widget>[
              r,
              const SizedBox(height: 10),
            ],
          ],
        );
        return Align(
          alignment: AlignmentDirectional.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kContentMaxWidth),
            child: twoPane
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: column),
                      const SizedBox(width: 16),
                      SizedBox(width: _kSidePaneWidth, child: dedupNote),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[column, dedupNote],
                  ),
          ),
        );
      },
    );

    return Scaffold(
      key: const Key('sources.page'),
      backgroundColor: Colors.transparent,
      body: HudScreenBody(
        reserveNavBar: false,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: ShellBackButton(),
          ),
          Semantics(
            header: true,
            child: HudScreenTitle(
              l10n.sourcesTitle,
              subtitle: l10n.sourcesIntro,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: content,
          ),
        ],
      ),
    );
  }
}

/// One row: name, status chip (word plus icon), an optional line and an
/// optional "Try again". The name and status are one semantics node; the retry
/// button stays a separate, focusable node.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.rowKey,
    required this.name,
    required this.statusText,
    required this.statusIcon,
    this.line,
    this.retryLabel,
    this.onRetry,
  });

  final Key rowKey;
  final String name;
  final String statusText;
  final IconData statusIcon;
  final String? line;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    final String? lineText = line;
    final String? retryText = retryLabel;
    return HudPanel(
      key: rowKey,
      secondary: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            container: true,
            liveRegion: true,
            excludeSemantics: true,
            label: lineText == null
                ? '$name, $statusText'
                : '$name, $statusText. $lineText',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(name, style: HudType.panelTitle(t)),
                    _StatusChip(icon: statusIcon, label: statusText),
                  ],
                ),
                if (lineText != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(lineText, style: HudType.body(t, size: 12.5)),
                ],
              ],
            ),
          ),
          if (retryText != null) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: HudButton(
                key: const Key('sources.app.retry'),
                label: retryText,
                onPressed: onRetry,
                showFocusRing: true,
                hoverStyle: true,
                cursor: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A status word with an icon. Never truncated: the label wraps.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final HudTokens t = context.hud;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: t.textSecondary),
        borderRadius: BorderRadius.circular(HudTokens.radiusChip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: t.textSecondary),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: HudType.bodyStrong(t, size: 11.5))),
          ],
        ),
      ),
    );
  }
}
