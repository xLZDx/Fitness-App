/// The first-run mode chooser S-1 (design 2.3, contract S-1 and S-9; S03-08).
///
/// ONE responsive screen outside the shell (no rail, no bar):
///  * Compact: title, 2x2 grid, description under the grid, footer buttons;
///  * Medium: the same, content centred at 640 dp; a short window with a grid of
///    at least 580 dp becomes 4x1;
///  * Expanded (window width 840 and up): the 2x2 grid on the left and a 320 dp
///    detail panel on the right that holds the description and the buttons.
///
/// Selection is local widget state until Continue ([ModeNotifier.resolveChooser]).
/// System Back while the status is `pending` behaves exactly like "Decide later"
/// ([ModeNotifier.decideLater], AC-CH-4, F-39). No permission is requested and no
/// network call is made (AC-CH-7).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/background/hud_sky.dart';
import '../../../core/theme/hud_tokens.dart';
import '../../../core/theme/hud_typography.dart';
import '../../../shared/widgets/hud/hud_scaffold.dart' show HudScreenTitle;
import '../../../shared/widgets/hud/hud_surface.dart';
import '../../../shared/widgets/shell_back_button.dart';
import '../../../shared/widgets/window_size.dart';
import '../../auth/data/auth_user.dart';
import '../../auth/state/auth_providers.dart';
import '../../training_context/data/training_context.dart';
import '../../training_context/state/training_context_providers.dart';
import '../data/mode_models.dart';
import '../state/mode_providers.dart';
import '../widgets/coming_later_sheet.dart';
import '../widgets/mode_card.dart';
import '../widgets/mode_chooser_offer.dart';
import '../widgets/mode_grid_layout.dart';
import '../widgets/mode_question_plan.dart';
import '../widgets/mode_text.dart';

/// Test seam: replaces the real Coming-later sheet opener of the page.
typedef ComingLaterOpener = Future<void> Function(
    BuildContext context, AppMode mode);

/// The order of the cards (contract S-1): train, ride / explore, body.
const List<AppMode> kChooserCardOrder = <AppMode>[
  AppMode.train,
  AppMode.ride,
  AppMode.explore,
  AppMode.body,
];

class ModeChooserPage extends ConsumerStatefulWidget {
  const ModeChooserPage({super.key, this.comingLaterOpener});

  /// Test and run-2 seam; null uses the Coming-later sheet opener.
  final ComingLaterOpener? comingLaterOpener;

  @override
  ConsumerState<ModeChooserPage> createState() => _ModeChooserPageState();
}

class _ModeChooserPageState extends ConsumerState<ModeChooserPage> {
  /// One GlobalKey per card so a live resize between layouts moves the card
  /// elements instead of rebuilding them: selection and focus survive (AC-CH-14).
  final Map<AppMode, GlobalKey> _slots = <AppMode, GlobalKey>{
    for (final AppMode m in AppMode.values)
      m: GlobalKey(debugLabel: 'modeChooser.slot.${m.name}'),
  };

  AppMode? _selected;
  bool _touched = false;
  AppMode? _preview;
  bool _busy = false;
  bool _leaving = false;

  /// True once the saved mode took longer than 300 ms to load: only then the
  /// four outlines show (before that the screen is blank, no flash).
  bool _patient = false;
  Timer? _patienceTimer;

  @override
  void initState() {
    super.initState();
    _patienceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _patient = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _markOffered());
  }

  @override
  void dispose() {
    _patienceTimer?.cancel();
    super.dispose();
  }

  /// Sets the "offered this run" mark for the signed-in uid (F-39).
  void _markOffered() {
    if (!mounted) return;
    final String? uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) return;
    ref.read(offeredThisRunProvider.notifier).markOffered(uid);
  }

  bool _isAvailable(AppMode m, Map<AppMode, ModeAvailability> table) =>
      availabilityOfMode(m, table: table) == ModeAvailability.available;

  void _onCardTap(AppMode m, bool available) {
    if (_busy || _leaving) return;
    if (!available) {
      // Coming later: never selected, nothing written; the panel shows its text.
      setState(() => _preview = m);
      final ComingLaterOpener? custom = widget.comingLaterOpener;
      unawaited(custom != null ? custom(context, m) : _openComingLater(m));
      return;
    }
    setState(() {
      _selected = m;
      _touched = true;
      _preview = null;
    });
  }

  /// The real Coming-later sheet. It writes nothing; "Choose Train for now"
  /// only selects the Train card here (Continue still decides, nothing saved).
  Future<void> _openComingLater(AppMode m) async {
    final bool chose = await showComingLaterSheet(context, m);
    if (!mounted || !chose || _busy || _leaving) return;
    setState(() {
      _selected = AppMode.train;
      _touched = true;
      _preview = null;
    });
  }

  void _onHighlight(AppMode m, bool on) {
    if (!mounted) return;
    setState(() {
      if (on) {
        _preview = m;
      } else if (_preview == m) {
        _preview = null;
      }
    });
  }

  void _showSaveError() {
    if (!mounted) return;
    final AppLocalizations l10n = AppLocalizations.of(context);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(l10n.modeSaveError, key: const Key('modeChooser.saveError')),
      ),
    );
  }

  /// Leaves the chooser: pop when it was pushed (switcher), else Home.
  void _leave() {
    final NavigatorState? nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      nav.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _continue(AppMode? mode) async {
    if (mode == null || _busy || _leaving) return;
    setState(() => _busy = true);
    ModeSaveResult result;
    try {
      result = await ref.read(modeStateProvider.notifier).resolveChooser(mode);
    } catch (e) {
      debugPrint('mode chooser: save threw (${e.runtimeType})');
      result = ModeSaveResult.saveFailed;
    }
    if (!mounted) return;
    if (result == ModeSaveResult.unavailable) {
      setState(() => _busy = false);
      return;
    }
    if (result == ModeSaveResult.saveFailed ||
        result == ModeSaveResult.notReady) {
      _showSaveError();
    }
    bool needsQuestions = false;
    try {
      final TrainingContextAnswer tc =
          await ref.read(trainingContextProvider.future);
      final ModeState ms =
          ref.read(modeStateProvider).valueOrNull ?? ModeState.initial();
      needsQuestions = unansweredQuestionsFor(mode,
              modeState: ms, trainingContext: tc)
          .isNotEmpty;
    } catch (e) {
      // Never block the user on the question check: go on without questions.
      debugPrint('mode chooser: question check failed (${e.runtimeType})');
    }
    if (!mounted) return;
    _leaving = true;
    if (needsQuestions) {
      // Same location as `modeQuestionsPath` in `s03_routes.dart`; built here so
      // this page does not import the router file that imports this page.
      final String path = '/mode-questions/${mode.name}';
      final NavigatorState? nav = Navigator.maybeOf(context);
      if (nav != null && nav.canPop()) {
        unawaited(context.pushReplacement<void>(path));
      } else {
        context.go(path);
      }
    } else {
      _leave();
    }
  }

  /// "Decide later" and system Back while `pending` (AC-CH-4, F-39): train and
  /// `resolved`. A failed write leaves `pending` and the user still leaves.
  Future<void> _decideLater() async {
    if (_busy || _leaving) return;
    setState(() => _busy = true);
    ModeSaveResult result;
    try {
      result = await ref.read(modeStateProvider.notifier).decideLater();
    } catch (e) {
      debugPrint('mode chooser: decide later threw (${e.runtimeType})');
      result = ModeSaveResult.saveFailed;
    }
    if (!mounted) return;
    if (result == ModeSaveResult.saveFailed ||
        result == ModeSaveResult.notReady) {
      _showSaveError();
    }
    _leaving = true;
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final HudTokens t = context.hud;

    // F-10: an account switch discards a pending (unsaved) selection.
    ref.listen<String?>(
      authUserProvider.select((AsyncValue<AuthUser?> a) => a.valueOrNull?.uid),
      (String? prev, String? next) {
        if (prev != next && mounted) {
          setState(() {
            _selected = null;
            _touched = false;
            _preview = null;
            _busy = false;
          });
        }
        if (next != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _markOffered());
        }
      },
    );

    final AsyncValue<ModeState> async = ref.watch(modeStateProvider);
    final bool loading = async.isLoading;
    final ModeState state = async.valueOrNull ?? ModeState.initial();
    final Map<AppMode, ModeAvailability> table =
        ref.watch(modeFlagsProvider).availabilityTable;
    final bool pending = !loading && state.chooserStatus == ChooserStatus.pending;

    final AppMode? selected = loading
        ? null
        : (_touched
            ? _selected
            : (pending || !_isAvailable(state.selectedMode, table)
                ? null
                : state.selectedMode));
    final AppMode? shown = _preview ?? selected;
    final bool canContinue = !loading && selected != null && !_busy && !_leaving;

    final WindowSizeInfo info = WindowSizeInfo.of(context);

    Widget body;
    if (loading && !_patient) {
      body = const SizedBox.expand();
    } else {
      body = LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints c) {
          return _buildContent(
            ctx,
            l10n: l10n,
            tokens: t,
            info: info,
            width: c.maxWidth,
            loading: loading,
            pending: pending,
            selected: selected,
            shown: shown,
            canContinue: canContinue,
            table: table,
          );
        },
      );
    }

    return PopScope(
      canPop: !pending,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) unawaited(_decideLater());
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: HudSkyBackground(
          selection:
              HudSkySelection(phase: HudSkyPhase.forTime(DateTime.now())),
          child: SafeArea(child: body),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required AppLocalizations l10n,
    required HudTokens tokens,
    required WindowSizeInfo info,
    required double width,
    required bool loading,
    required bool pending,
    required AppMode? selected,
    required AppMode? shown,
    required bool canContinue,
    required Map<AppMode, ModeAvailability> table,
  }) {
    final bool expanded = info.sizeClass == WindowSizeClass.expanded;

    int columns;
    double cardWidth;
    double minHeight;
    double maxContent;
    if (expanded) {
      columns = 2;
      maxContent = kChooserExpandedMaxWidth;
      final double gridPane = (width < maxContent ? width : maxContent) -
          2 * kChooserSidePadding -
          kChooserPaneGap -
          kChooserDetailPanelWidth;
      cardWidth = chooserCardWidth(gridPane, 2);
      minHeight = 150;
    } else {
      maxContent = info.sizeClass == WindowSizeClass.medium
          ? kChooserMediumMaxWidth
          : double.infinity;
      final double gridWidth = chooserGridWidth(width, info.sizeClass);
      columns = chooserGridColumns(gridWidth, info.isShort);
      cardWidth = chooserCardWidth(gridWidth, columns);
      minHeight = 120;
    }
    final bool showBlurb = chooserShowsBlurb(columns, cardWidth);

    Widget cardFor(AppMode m) {
      final bool available = _isAvailable(m, table);
      return KeyedSubtree(
        key: _slots[m],
        child: ModeCard(
          key: Key('modeChooser.card.${m.name}'),
          mode: m,
          name: modeNameOf(l10n, m),
          blurb: modeBlurbOf(l10n, m),
          description: modeDescOf(l10n, m),
          comingLaterWord: l10n.modeComingLater,
          selectedWord: l10n.modeSelected,
          selected: available && selected == m,
          comingLater: !available,
          showBlurb: showBlurb,
          minHeight: minHeight,
          loadingOutline: loading,
          onTap: loading ? null : () => _onCardTap(m, available),
          onHighlight: loading ? null : (bool on) => _onHighlight(m, on),
        ),
      );
    }

    // Rows of `columns` cards; the card order never changes (AC-CH-1).
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < kChooserCardOrder.length; i += columns) {
      final List<Widget> cells = <Widget>[];
      for (int j = i; j < i + columns && j < kChooserCardOrder.length; j++) {
        if (j > i) cells.add(const SizedBox(width: kChooserGap));
        cells.add(Expanded(child: cardFor(kChooserCardOrder[j])));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: kChooserGap));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cells,
        ),
      ));
    }
    final Widget grid = Column(
      key: const Key('modeChooser.grid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );

    final Widget description = _buildDescription(l10n, tokens, shown, selected, table);
    final Widget continueButton = HudButton(
      key: const Key('modeChooser.continue'),
      label: l10n.modeContinue,
      tone: HudButtonTone.accent,
      centered: true,
      enabled: canContinue,
      onPressed: canContinue ? () => unawaited(_continue(selected)) : null,
    );
    final Widget? decideLater = pending
        ? TextButton(
            key: const Key('modeChooser.decideLater'),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: tokens.textPrimary,
            ),
            onPressed: (_busy || _leaving) ? null : () => unawaited(_decideLater()),
            child: Text(l10n.modeDecideLater),
          )
        : null;

    final Widget header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Visible on Apple desktop only; takes no space elsewhere. While the
        // status is pending it is the same path as system Back.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kChooserSidePadding),
          child: ShellBackButton(
            onPressed: pending ? () => unawaited(_decideLater()) : null,
          ),
        ),
        HudScreenTitle(
          l10n.modeChooserTitle,
          subtitle: l10n.modeChooserSubtitle,
        ),
      ],
    );

    Widget content;
    if (expanded) {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(
            kChooserSidePadding, 0, kChooserSidePadding, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: grid),
            const SizedBox(width: kChooserPaneGap),
            SizedBox(
              width: kChooserDetailPanelWidth,
              child: HudPanel(
                key: const Key('modeChooser.detailPanel'),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    description,
                    const SizedBox(height: 24),
                    continueButton,
                    if (decideLater != null) ...<Widget>[
                      const SizedBox(height: 8),
                      decideLater,
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(
            kChooserSidePadding, 0, kChooserSidePadding, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            grid,
            const SizedBox(height: 16),
            description,
            const SizedBox(height: 20),
            // Footer buttons are the last items of the scroll content: they stay
            // reachable by scrolling and by focus on a short window.
            continueButton,
            if (decideLater != null) ...<Widget>[
              const SizedBox(height: 8),
              decideLater,
            ],
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[header, content],
          ),
        ),
      ),
    );
  }

  /// The description area (Compact, Medium) or the text part of the detail panel
  /// (Expanded). Not a live region (finding A7). Idle text until a card is
  /// focused, hovered or selected; a coming-later card shows its state word.
  Widget _buildDescription(
    AppLocalizations l10n,
    HudTokens t,
    AppMode? shown,
    AppMode? selected,
    Map<AppMode, ModeAvailability> table,
  ) {
    final String text =
        shown == null ? l10n.modeDetailIdle : modeDescOf(l10n, shown);
    String? stateWord;
    if (shown != null) {
      if (!_isAvailable(shown, table)) {
        stateWord = l10n.modeComingLater;
      } else if (shown == selected) {
        stateWord = l10n.modeSelected;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          text,
          key: const Key('modeChooser.description'),
          style: HudType.body(t, size: 13).overPhoto(t),
        ),
        if (stateWord != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            stateWord,
            key: const Key('modeChooser.descriptionState'),
            style: HudType.label(t, size: 11).overPhoto(t),
          ),
        ],
      ],
    );
  }
}
