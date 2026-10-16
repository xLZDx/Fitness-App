// S02 E01 (gate): the 100-session round trip, whole flow.
//
//   155 raw corpus records -> merge -> 100 sessions -> on-disk journal ->
//   restart -> sync repository over a rules-enforcing fake Firestore ->
//   restart -> GPX / FIT export.
//
// Fails when any session is lost or altered on the way, when a cloud-bound
// payload carries geometry or heart rate, or when an export does not match the
// stored streams. Oracles are literals of the plan (sport quotas, FIT epoch,
// counts) and the constructed merged objects, never a second run of the code
// under test on its own output.
import 'dart:convert';
import 'dart:io';

import 'package:fitness_app/features/activity/data/activity_merger.dart';
import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/merge_policy.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/activity_local_export.dart';
import 'package:fitness_app/features/activity/repository/activity_sync_repository.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:fitness_app/features/activity/repository/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import '../../../support/firestore_rules_parser.dart';
import '../../../support/fit_test_decoder.dart';
import '../../../support/journal_harness.dart';
import '../../../support/synthetic_activity_corpus.dart';
import '../../../support/two_device_world.dart';

/// Plan section 2.2 quotas, kept as an own literal (the generator's constant is
/// not the oracle).
const Map<SportType, int> _quota = {
  SportType.running: 12,
  SportType.cycling: 10,
  SportType.walking: 8,
  SportType.hiking: 6,
  SportType.trailRunning: 6,
  SportType.mountainBiking: 6,
  SportType.indoorCycling: 8,
  SportType.swimmingPool: 10,
  SportType.swimmingOpenWater: 6,
  SportType.rowing: 6,
  SportType.strength: 12,
  SportType.other: 10,
};

const int _fitEpoch = 631065600;

int _fitSec(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000 - _fitEpoch;

bool _hasGps(ActivitySession s) => (s.streams[StreamKind.gps]?.length ?? 0) > 0;

void main() {
  late Directory tmp;
  late JournalHarness h;
  late FakeFirestoreServer server;
  late DeviceBackend backend;
  ActivitySyncRepository? repo;
  late List<ActivitySession> merged;
  final rules = parseActivityRules();

  ActivitySyncRepository newRepo() => ActivitySyncRepository(
      journal: h.journal, backend: backend, clock: h.clock.call);

  setUpAll(() {
    final raw = SyntheticCorpus.build().rawCandidates;
    merged = merge(raw, const MergePolicy()).sessions;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('s02_e01_');
    h = JournalHarness.onDisk(tmp);
    await h.open();
    server = FakeFirestoreServer();
    backend = DeviceBackend('A', server);
  });

  tearDown(() async {
    await repo?.dispose();
    repo = null;
    await h.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('step 0, the corpus is not vacuous: 155 raw records merge into 100 '
      'distinct sessions with the plan quotas, GPS, HR and no-stream cases', () {
    final raw = SyntheticCorpus.build().rawCandidates;
    expect(raw, hasLength(155));
    expect(merged, hasLength(100));
    expect({for (final s in merged) s.id}, hasLength(100));
    final bySport = <SportType, int>{};
    for (final s in merged) {
      bySport[s.sport] = (bySport[s.sport] ?? 0) + 1;
    }
    expect(bySport, _quota);
    expect(merged.where(_hasGps), isNotEmpty);
    expect(merged.where((s) => s.streams.containsKey(StreamKind.heartRate)),
        isNotEmpty);
    expect(merged.where((s) => s.streams.isEmpty), isNotEmpty);
    expect(merged.where((s) => !_hasGps(s)), isNotEmpty);
  });

  test('the whole flow: journal, restart, cloud sync, restart, export', () async {
    // ---- journal ----------------------------------------------------------
    for (final s in merged) {
      final e = await h.journal.put(s);
      expect(e.streamsLoaded, isTrue, reason: s.id);
    }
    expect((await h.journal.list()), hasLength(100));

    // After the sync the repository stamps the calculation versions in force
    // on the record (design: a version change is a local change); nothing else
    // may differ, so the three version keys are neutralised on both sides.
    String norm(ActivitySession s, bool stamped) {
      final m = jsonDecode(sessionJson(s)) as Map<String, dynamic>;
      if (stamped) {
        for (final k in ['formulaVersion', 'metricDefinitionVersion',
          'thresholdPolicyVersion']) {
          m.remove(k);
        }
      }
      return jsonEncode(m);
    }

    Future<void> verifyJournal(String when, {bool stamped = false}) async {
      final listed = await h.journal.list();
      expect([for (final e in listed) e.id], [for (final s in merged) s.id],
          reason: '$when: all 100 present, in write order');
      for (final s in merged) {
        final back = await h.journal.read(s.id);
        expect(back, isNotNull, reason: '$when ${s.id} lost');
        expect(back!.streamLost, isFalse, reason: '$when ${s.id}');
        expect(norm(back.session, stamped), norm(s, stamped),
            reason: '$when ${s.id} altered');
        expect(streamsOf(back.session), streamsOf(s),
            reason: '$when ${s.id} streams altered');
      }
    }

    await verifyJournal('before restart');
    await h.restart();
    await verifyJournal('after restart 1');

    // ---- repository over the rules-enforcing fake --------------------------
    repo = newRepo();
    final out = await repo!.syncAll();
    expect(out, hasLength(100));
    expect(out.values, everyElement(SyncOutcome.synced));
    expect(server.refused, isEmpty,
        reason: 'the rules gate refused a summary the client wrote');
    expect(server.docs.keys.toSet(), {for (final s in merged) s.id});
    expect(server.accepted, hasLength(100));

    final geometry = <double>{};
    final heartRate = <double>{};
    for (final s in merged) {
      final g = s.streams[StreamKind.gps];
      if (g != null) {
        geometry
          ..addAll(g.lats)
          ..addAll(g.lons);
      }
      final hr = s.streams[StreamKind.heartRate];
      if (hr != null) heartRate.addAll(hr.values);
    }
    for (final w in server.accepted) {
      final doc = w.summary;
      final s = merged.firstWhere((m) => m.id == w.id);
      expect(rulesViolations(rules, doc.cast<String, Object?>()), isEmpty,
          reason: '${w.id} would be refused by firestore.rules');
      for (final e in doc.entries) {
        expect(e.value is num || e.value is bool || e.value is String ||
            e.value is DateTime, isTrue,
            reason: '${w.id}.${e.key} is not a scalar: ${e.value.runtimeType}');
      }
      for (final k in ['lats', 'lons', 'streams', 'laps', 'provenance',
        'heartRate', 'avgHrBpm', 'maxHrBpm', 'hr']) {
        expect(doc.containsKey(k), isFalse, reason: '${w.id} carries $k');
      }
      expect(doc['rev'], 1, reason: w.id);
      expect(doc['sport'], s.sport.name, reason: w.id);
      expect(doc['startUtc'], s.startUtc, reason: w.id);
      expect(doc['endUtc'], s.endUtc, reason: w.id);
      expect(doc['hasRoute'], _hasGps(s), reason: '${w.id} hasRoute');
      final d = s.summary.distanceM;
      // The cloud value is the EFFECTIVE projection (streams, explicit values
      // and overrides), so it must stay within 10 % of the stored summary
      // value. Exact preservation of the session is asserted by the journal
      // comparison.
      if (d != null && d > 0 && d <= 10000000) {
        final sent = doc['distanceM'] as num?;
        expect(sent, isNotNull, reason: '${w.id} distance lost');
        expect((sent! - d).abs() / d, lessThan(0.10),
            reason: '${w.id} distance $sent vs stored $d');
      }
    }
    // The latitude sentinel tail `7351` cannot appear as a coordinate: no summary
    // number equals any GPS sample value of any session.
    for (final w in server.accepted) {
      for (final e in w.summary.entries) {
        final v = e.value;
        if (v is double && v != v.roundToDouble()) {
          expect(geometry.contains(v), isFalse,
              reason: '${w.id}.${e.key}=$v equals a GPS sample');
        }
      }
    }
    expect(heartRate, isNotEmpty);

    // Idempotent: a second pass writes nothing, a restart does not either.
    await repo!.dispose();
    await h.restart();
    repo = newRepo();
    expect(await repo!.syncAll(), isEmpty);
    expect(server.accepted, hasLength(100));
    for (final e in await h.journal.list()) {
      expect(e.state.syncState, JournalSyncState.synced, reason: e.id);
    }
    await verifyJournal('after restart 2 and sync', stamped: true);

    // ---- export -------------------------------------------------------------
    final export = JournalActivityLocalExport(h.journal);
    var gpsFiles = 0;
    var fitRecords = 0;
    for (final s in merged) {
      final g = s.streams[StreamKind.gps];
      final gpx = await export.exportActivity(s.id, ActivityExportFormat.gpx);
      if (_hasGps(s)) {
        expect(gpx, isA<ActivityExportFile>(), reason: s.id);
        final doc = XmlDocument.parse(
            utf8.decode((gpx as ActivityExportFile).bytes));
        final pts = doc.findAllElements('trkpt').toList();
        expect(pts, hasLength(g!.length), reason: '${s.id} gpx points');
        expect(double.parse(pts.first.getAttribute('lat')!),
            closeTo(g.lats.first, 1e-6), reason: s.id);
        expect(double.parse(pts.last.getAttribute('lon')!),
            closeTo(g.lons.last, 1e-6), reason: s.id);
        gpsFiles++;
      } else {
        expect(gpx, isA<ActivityExportNoGeometry>(), reason: s.id);
      }

      final fit = await export.exportActivity(s.id, ActivityExportFormat.fit);
      expect(fit, isA<ActivityExportFile>(), reason: s.id);
      final d = decodeFit((fit as ActivityExportFile).bytes);
      expect(d.ok, isTrue, reason: '${s.id}: ${d.errors}');
      expect(d.byNum(0).single.intField(4), _fitSec(s.startUtc),
          reason: '${s.id} FIT start time');
      expect(d.byNum(18), hasLength(1), reason: s.id);
      if (_hasGps(s)) {
        expect(d.byNum(20), hasLength(g!.length), reason: '${s.id} fit records');
        fitRecords += g.length;
      }
    }
    expect(gpsFiles, merged.where(_hasGps).length);
    expect(gpsFiles, greaterThan(0));
    expect(fitRecords, greaterThan(1000), reason: 'the FIT oracle is exercised');

    final all = await export.exportAll(ActivityExportFormat.json);
    expect(all, hasLength(100));
    expect(all.whereType<ActivityExportFile>(), hasLength(100));
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('negative control: a lost or altered session is detected by the same '
      'comparison', () async {
    for (final s in merged.take(3)) {
      await h.journal.put(s);
    }
    final listed = await h.journal.list();
    expect(listed, hasLength(3));
    // the comparison used above fails for a different session
    final other = merged[3];
    final back = (await h.journal.read(merged[0].id))!;
    expect(sessionJson(back.session), isNot(sessionJson(other)));
    await h.journal.delete(merged[1].id);
    expect(await h.journal.read(merged[1].id), isNull);
    expect(await h.journal.list(), hasLength(2));
  });
}
