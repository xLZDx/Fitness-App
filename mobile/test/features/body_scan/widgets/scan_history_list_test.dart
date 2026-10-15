// C16 functional tests: the body-scan history list widget (SCAN-23, PLAN-26,
// I18N-11; design s17, D-54, D-73, D-85). Rows are built directly so every
// marker is driven by a field of the row, and navigation is observed through a
// real GoRouter.
import 'package:fitness_app/features/body_scan/data/body_fat_estimate.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_entry.dart';
import 'package:fitness_app/features/body_scan/data/body_scan_job.dart';
import 'package:fitness_app/features/body_scan/data/scan_trend.dart';
import 'package:fitness_app/features/body_scan/state/scan_history_rows.dart';
import 'package:fitness_app/features/body_scan/widgets/scan_history_list.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../helpers/test_app.dart';

BodyFatEstimate _est(double v, {bool provisional = false}) => BodyFatEstimate(
      value: v,
      low: v - 2,
      high: v + 2,
      confidence: EstimateConfidence.medium,
      modelId: provisional ? 'provisional-anthropometric' : 'photo-model',
      modelVersion: '1',
      provisional: provisional,
    );

ScanRecord _rec(String id, {bool shots = true, bool pending = false}) =>
    ScanRecord(
      id: id,
      createdAt: DateTime(2026, 10, 1),
      shots: shots
          ? {ScanPose.front: ScanShot(photoId: '$id-f', landmarks: const [])}
          : const {},
      analysis: const ScanAnalysis(status: JobStatus.done),
      pendingRemoteDelete: pending,
    );

ScanHistoryRow _row(
  String id, {
  DateTime? at,
  double? weight = 80,
  double? fat = 20,
  bool provisional = false,
  bool baseline = false,
  bool newEstimator = false,
  ChangeLabel? change,
  bool photos = true,
  bool pending = false,
  BodyScanEntry? entry,
}) =>
    ScanHistoryRow(
      id: id,
      takenAt: at ?? DateTime(2026, 10, 1, 9),
      weightKg: weight,
      estimate: fat == null ? null : _est(fat, provisional: provisional),
      record: _rec(id, shots: photos, pending: pending),
      entry: entry,
      isBaseline: baseline,
      startsNewEstimator: newEstimator,
      change: change,
    );

class _Nav {
  final locations = <String>[];
}

Future<_Nav> _pump(
  WidgetTester t,
  List<ScanHistoryRow> rows, {
  Locale locale = kTestLocale,
}) async {
  t.view.physicalSize = const Size(900, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final nav = _Nav();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(body: ScanHistoryList(rows: rows)),
      ),
      GoRoute(
        path: '/photos/compare',
        builder: (_, s) {
          nav.locations.add(s.uri.toString());
          return const Scaffold(body: Text('COMPARE'));
        },
      ),
      GoRoute(
        path: '/body-scan/result/:id',
        builder: (_, s) {
          nav.locations.add(s.uri.toString());
          return Scaffold(body: Text('RESULT ${s.pathParameters['id']}'));
        },
      ),
    ],
  );
  await t.pumpWidget(ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      locale: locale,
      localizationsDelegates: kTestLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await t.pumpAndSettle();
  return nav;
}

AppLocalizations _l10n(WidgetTester t) =>
    AppLocalizations.of(t.element(find.byType(ScanHistoryList)));

Finder _card(String id) => find.byKey(Key('bodyScan.history.card.$id'));

Finder _in(String id, Finder f) =>
    find.descendant(of: _card(id), matching: f);

void main() {
  group('empty and count', () {
    testWidgets('no rows: the empty text with the baseline hint, no list',
        (t) async {
      await _pump(t, const []);
      expect(find.byKey(const Key('bodyScan.history.empty')), findsOneWidget);
      expect(find.text(_l10n(t).bodyScanHistoryEmpty), findsOneWidget);
      expect(find.byKey(const Key('bodyScan.history.count')), findsNothing);
    });

    testWidgets('count header is pluralised (1 scan / 3 scans)', (t) async {
      await _pump(t, [_row('a')]);
      expect(find.text('1 scan'), findsOneWidget);
      await _pump(t, [_row('a'), _row('b'), _row('c')]);
      expect(find.text('3 scans'), findsOneWidget);
    });

    testWidgets('Russian count header uses the matching plural form',
        (t) async {
      await _pump(t, [for (final i in [1, 2, 3, 4, 5]) _row('r$i')],
          locale: const Locale('ru'));
      final l10n = _l10n(t);
      expect(find.text(l10n.bodyScanHistoryCount(5)), findsOneWidget);
      expect(l10n.bodyScanHistoryCount(5), isNot(l10n.bodyScanHistoryCount(2)),
          reason: 'many vs few forms differ');
      expect(l10n.bodyScanHistoryCount(5), contains('5'));
    });
  });

  group('row content', () {
    testWidgets('date, body fat and weight with the English formats',
        (t) async {
      await _pump(t, [_row('a', at: DateTime(2026, 10, 1, 9), fat: 20, weight: 80)]);
      expect(_in('a', find.text(DateFormat.yMMMd('en').format(DateTime(2026, 10, 1)))),
          findsOneWidget);
      expect(_in('a', find.text('Body fat 20.0% · 80.0 kg')), findsOneWidget);
    });

    testWidgets('Russian: decimal comma and localised date, no dot decimals',
        (t) async {
      await _pump(t, [_row('a', fat: 20.5, weight: 80.5)],
          locale: const Locale('ru'));
      final text = t
          .widgetList<Text>(_in('a', find.byType(Text)))
          .map((w) => w.data ?? '')
          .join('|');
      expect(text, contains('20,5'));
      expect(text, contains('80,5'));
      expect(text, isNot(contains('20.5')));
      expect(text, contains(DateFormat.yMMMd('ru').format(DateTime(2026, 10, 1))));
    });

    testWidgets('missing weight is omitted, not shown as zero', (t) async {
      await _pump(t, [_row('a', weight: null)]);
      expect(_in('a', find.text('Body fat 20.0%')), findsOneWidget);
      expect(_in('a', find.textContaining(' kg')), findsNothing);
    });

    testWidgets('baseline marker appears only on the baseline row', (t) async {
      await _pump(t, [_row('new'), _row('old', baseline: true)]);
      final base = _l10n(t).bodyScanHistoryBaseline;
      expect(_in('old', find.text(base)), findsOneWidget);
      expect(_in('new', find.text(base)), findsNothing);
      expect(find.text(base), findsOneWidget);
    });

    testWidgets('trend label per row: none / down / up, none when null',
        (t) async {
      await _pump(t, [
        _row('n', change: ChangeLabel.noMeaningfulChange),
        _row('d', change: ChangeLabel.down),
        _row('u', change: ChangeLabel.up),
        _row('x'),
      ]);
      final l10n = _l10n(t);
      expect(_in('n', find.text(l10n.bodyScanHistoryChangeNone)), findsOneWidget);
      expect(_in('d', find.text(l10n.bodyScanHistoryChangeDown)), findsOneWidget);
      expect(_in('u', find.text(l10n.bodyScanHistoryChangeUp)), findsOneWidget);
      for (final s in [
        l10n.bodyScanHistoryChangeNone,
        l10n.bodyScanHistoryChangeDown,
        l10n.bodyScanHistoryChangeUp,
      ]) {
        expect(_in('x', find.text(s)), findsNothing);
      }
    });

    testWidgets('new-estimator marker and no change label together: nothing '
        'implies a cross-model comparison', (t) async {
      await _pump(t, [_row('a', newEstimator: true, baseline: true)]);
      final l10n = _l10n(t);
      expect(_in('a', find.text(l10n.bodyScanHistoryNewEstimator)),
          findsOneWidget);
      expect(_in('a', find.text(l10n.bodyScanHistoryChangeUp)), findsNothing);
      expect(_in('a', find.text(l10n.bodyScanHistoryChangeDown)), findsNothing);
      expect(_in('a', find.text(l10n.bodyScanHistoryChangeNone)), findsNothing);
    });

    testWidgets('provisional rows carry the rough-estimate label (PLAN-26)',
        (t) async {
      await _pump(t, [_row('p', provisional: true), _row('q')]);
      final rough = _l10n(t).bodyScanRoughLabel;
      expect(_in('p', find.text(rough)), findsOneWidget);
      expect(_in('q', find.text(rough)), findsNothing);
    });

    testWidgets('an owed delete is announced on the row', (t) async {
      await _pump(t, [_row('a', pending: true), _row('b')]);
      final s = _l10n(t).bodyScanHistoryDeletePending;
      expect(_in('a', find.text(s)), findsOneWidget);
      expect(_in('b', find.text(s)), findsNothing);
    });

    testWidgets('photo-only (legacy) row says so and has no result link',
        (t) async {
      final nav = await _pump(t, [_row('old', fat: null, weight: null)]);
      expect(_in('old', find.text(_l10n(t).bodyScanHistoryPhotosOnly)),
          findsOneWidget);
      await t.tap(_card('old'));
      await t.pumpAndSettle();
      expect(nav.locations, isEmpty);
      expect(find.textContaining('RESULT'), findsNothing);
    });

    testWidgets('the row is one semantics label with every fact', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, [
        _row('a', baseline: true, provisional: true, change: null),
      ]);
      final all = t
          .widgetList<Semantics>(_in('a', find.byType(Semantics)))
          .map((s) => s.properties.label ?? '')
          .where((l) => l.contains('Body fat'))
          .toList();
      expect(all, hasLength(1));
      expect(all.single, contains('Baseline'));
      expect(all.single, contains('20.0'));
      h.dispose();
    });
  });

  group('navigation', () {
    testWidgets('tapping a row opens its result by id', (t) async {
      final nav = await _pump(t, [_row('abc')]);
      await t.tap(_card('abc'));
      await t.pumpAndSettle();
      expect(nav.locations, ['/body-scan/result/abc']);
      expect(find.text('RESULT abc'), findsOneWidget);
    });
  });

  group('compare entry points (SCAN-23)', () {
    testWidgets('two scans with photos: baseline and previous entries',
        (t) async {
      final nav = await _pump(t, [_row('b'), _row('a', baseline: true)]);
      expect(find.byKey(const Key('bodyScan.history.compareBaseline')),
          findsOneWidget);
      expect(find.byKey(const Key('bodyScan.history.comparePrevious')),
          findsOneWidget);
      expect(find.byKey(const Key('bodyScan.history.secondScan')), findsNothing);

      await t.tap(find.byKey(const Key('bodyScan.history.compareBaseline')));
      await t.pumpAndSettle();
      expect(nav.locations.last, '/photos/compare?mode=baseline');
    });

    testWidgets('previous entry carries mode=previous', (t) async {
      final nav = await _pump(t, [_row('b'), _row('a', baseline: true)]);
      await t.tap(find.byKey(const Key('bodyScan.history.comparePrevious')));
      await t.pumpAndSettle();
      expect(nav.locations.last, '/photos/compare?mode=previous');
    });

    testWidgets('only the baseline: second-scan prompt, no compare buttons',
        (t) async {
      await _pump(t, [_row('a', baseline: true)]);
      expect(find.byKey(const Key('bodyScan.history.secondScan')),
          findsOneWidget);
      expect(find.text(_l10n(t).bodyScanCompareBaselineOnly), findsOneWidget);
      expect(find.byKey(const Key('bodyScan.history.compareBaseline')),
          findsNothing);
      expect(find.byKey(const Key('bodyScan.history.comparePrevious')),
          findsNothing);
    });

    testWidgets('rows without local photos do not count toward comparing',
        (t) async {
      await _pump(t, [
        _row('b', photos: false),
        _row('a', baseline: true),
      ]);
      expect(find.byKey(const Key('bodyScan.history.secondScan')),
          findsOneWidget);
      expect(find.byKey(const Key('bodyScan.history.compareBaseline')),
          findsNothing);
    });

    testWidgets('no scan has photos: neither prompt nor buttons', (t) async {
      await _pump(t, [_row('a', photos: false)]);
      expect(find.byKey(const Key('bodyScan.history.secondScan')), findsNothing);
      expect(find.byKey(const Key('bodyScan.history.compareBaseline')),
          findsNothing);
    });
  });

  group('row menu', () {
    Future<void> openMenu(WidgetTester t, String id) async {
      await t.tap(find.byKey(Key('bodyScan.history.menu.$id')));
      await t.pumpAndSettle();
    }

    testWidgets('a full row offers open, edit weight and delete photos',
        (t) async {
      await _pump(t, [_row('a')]);
      await openMenu(t, 'a');
      final l10n = _l10n(t);
      expect(find.text(l10n.bodyScanHistoryActionOpen), findsOneWidget);
      expect(find.text(l10n.bodyScanHistoryActionEditWeight), findsOneWidget);
      expect(find.text(l10n.bodyScanHistoryActionDeletePhotos), findsOneWidget);
    });

    testWidgets('a photo-only row offers only delete photos', (t) async {
      await _pump(t, [_row('a', fat: null)]);
      await openMenu(t, 'a');
      final l10n = _l10n(t);
      expect(find.text(l10n.bodyScanHistoryActionOpen), findsNothing);
      expect(find.text(l10n.bodyScanHistoryActionEditWeight), findsNothing);
      expect(find.text(l10n.bodyScanHistoryActionDeletePhotos), findsOneWidget);
    });

    testWidgets('a result with no photos anywhere has no delete-photos item',
        (t) async {
      final entry = BodyScanEntry(
        scanId: 'a',
        takenAt: DateTime(2026, 10, 1),
        status: ScanDocStatus.done,
        photosState: PhotosState.deleted,
        estimate: _est(20),
      );
      await _pump(t, [
        ScanHistoryRow(
            id: 'a',
            takenAt: entry.takenAt,
            weightKg: 80,
            estimate: entry.estimate,
            entry: entry),
      ]);
      await openMenu(t, 'a');
      expect(find.text(_l10n(t).bodyScanHistoryActionDeletePhotos), findsNothing);
      expect(find.text(_l10n(t).bodyScanHistoryActionEditWeight), findsOneWidget);
    });

    testWidgets('choosing Open navigates to the result', (t) async {
      final nav = await _pump(t, [_row('a')]);
      await openMenu(t, 'a');
      await t.tap(find.text(_l10n(t).bodyScanHistoryActionOpen));
      await t.pumpAndSettle();
      expect(nav.locations, ['/body-scan/result/a']);
    });

    testWidgets('Edit weight opens the dialog prefilled with the weight',
        (t) async {
      await _pump(t, [_row('a', weight: 80.5)]);
      await openMenu(t, 'a');
      await t.tap(find.text(_l10n(t).bodyScanHistoryActionEditWeight));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bodyScan.editWeight.dialog')), findsOneWidget);
      final field = t.widget<TextField>(
          find.byKey(const Key('bodyScan.editWeight.field')));
      expect(field.controller!.text, '80.5');
    });

    testWidgets('Delete photos asks for confirmation and cancel keeps '
        'everything', (t) async {
      await _pump(t, [_row('a')]);
      await openMenu(t, 'a');
      await t.tap(find.text(_l10n(t).bodyScanHistoryActionDeletePhotos));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bodyScan.deletePhotos.dialog')),
          findsOneWidget);
      await t.tap(find.byKey(const Key('bodyScan.deletePhotos.cancel')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('bodyScan.deletePhotos.dialog')), findsNothing);
      expect(_card('a'), findsOneWidget);
    });
  });
}
