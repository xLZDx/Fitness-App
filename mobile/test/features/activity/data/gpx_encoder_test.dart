// S02 test epic 3, U17 (GPX structural round trip), U18 (indoor session ->
// typed `no_geometry`, FIT and summary export still work) and U20 (owner export
// is the full series, shared export trims the first and last 200 m and carries
// no heart rate).
//
// The XML is parsed with package:xml (a transitive dependency of the app, used
// here only as an independent well-formedness oracle).
import 'dart:convert';
import 'dart:math' as math;

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/fit_encoder.dart';
import 'package:fitness_app/features/activity/data/gpx_encoder.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:fitness_app/features/activity/data/sport_type.dart';
import 'package:fitness_app/features/activity/repository/activity_local_export.dart';
import 'package:fitness_app/features/activity/repository/journal_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import '../../../support/fit_test_decoder.dart';
import '../../../support/journal_harness.dart';
import '../../../support/s02_fixtures.dart';
import '../../../support/synthetic_activity_corpus.dart';

/// Own haversine (the production one is not the oracle).
double _hav(double la1, double lo1, double la2, double lo2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final a = math.pow(math.sin(rad(la2 - la1) / 2), 2) +
      math.cos(rad(la1)) * math.cos(rad(la2)) * math.pow(math.sin(rad(lo2 - lo1) / 2), 2);
  return 2 * r * math.asin(math.sqrt(a.toDouble()));
}

XmlDocument _parse(GpxResult r) {
  expect(r, isA<GpxDocument>());
  return XmlDocument.parse((r as GpxDocument).xml);
}

List<XmlElement> _pts(XmlDocument d) => d.findAllElements('trkpt').toList();

double _ele(ActivitySession s, int offMs) {
  final a = s.streams[StreamKind.altitude]!;
  var best = 0;
  for (var i = 1; i < a.length; i++) {
    if ((a.offsetsMs[i] - offMs).abs() < (a.offsetsMs[best] - offMs).abs()) best = i;
  }
  return a.values[best];
}

bool _hasAltNear(ActivitySession s, int offMs) {
  final a = s.streams[StreamKind.altitude];
  return a != null && a.offsetsMs.any((o) => (o - offMs).abs() <= 5000);
}

/// Indexes kept by the shared export, from an independent along-route sum.
List<int> _sharedKeep(SampleStream g, double trim) {
  final along = List<double>.filled(g.length, 0);
  for (var i = 1; i < g.length; i++) {
    along[i] = along[i - 1] + _hav(g.lats[i - 1], g.lons[i - 1], g.lats[i], g.lons[i]);
  }
  final total = along.last;
  return [
    for (var i = 0; i < g.length; i++)
      if (along[i] >= trim && total - along[i] >= trim) i,
  ];
}

void main() {
  final corpus = SyntheticCorpus.build();
  final gpsSessions = [
    for (final s in corpus.valid)
      if ((s.streams[StreamKind.gps]?.length ?? 0) > 0) s,
  ];
  final noGps = [
    for (final s in corpus.valid)
      if ((s.streams[StreamKind.gps]?.length ?? 0) == 0) s,
  ];

  test('guard: the corpus has GPS and non-GPS sessions', () {
    expect(gpsSessions.length, 38);
    expect(noGps.length, 62);
  });

  group('U17 GPX structural round trip (owner export)', () {
    test('every GPS session: well formed, point count, lat/lon, time, ele', () {
      for (final s in gpsSessions) {
        final g = s.streams[StreamKind.gps]!;
        final r = GpxEncoder.encode(s);
        final doc = _parse(r); // throws on malformed XML
        final pts = _pts(doc);
        expect(pts, hasLength(g.length), reason: '${s.id} trkpt count');
        expect((r as GpxDocument).pointCount, g.length);
        expect(doc.rootElement.getAttribute('version'), '1.1');
        DateTime? prev;
        for (var i = 0; i < pts.length; i++) {
          final p = pts[i];
          expect(double.parse(p.getAttribute('lat')!), closeTo(g.lats[i], 1e-6),
              reason: '${s.id} lat $i');
          expect(double.parse(p.getAttribute('lon')!), closeTo(g.lons[i], 1e-6),
              reason: '${s.id} lon $i');
          final t = DateTime.parse(p.getElement('time')!.innerText);
          expect(t, s.startUtc.add(Duration(milliseconds: g.offsetsMs[i])),
              reason: '${s.id} time $i');
          if (prev != null) expect(t.isAfter(prev), isTrue, reason: '${s.id} strictly increasing $i');
          prev = t;
          final ele = p.getElement('ele');
          if (_hasAltNear(s, g.offsetsMs[i])) {
            expect(ele, isNotNull, reason: '${s.id} ele missing at $i');
            expect(double.parse(ele!.innerText), closeTo(_ele(s, g.offsetsMs[i]), 0.006),
                reason: '${s.id} ele $i');
          } else {
            expect(ele, isNull, reason: '${s.id} invented ele at $i');
          }
        }
      }
    });

    test('at least one corpus session really carries altitude (ele oracle is live)',
        () {
      expect(gpsSessions.where((s) => s.streams.containsKey(StreamKind.altitude)),
          isNotEmpty);
    });

    test('the parser can fail: a broken document is rejected', () {
      final good = (GpxEncoder.encode(gpsSessions.first) as GpxDocument).xml;
      expect(() => XmlDocument.parse(good.replaceFirst('</trkseg>', '')),
          throwsA(isA<XmlException>()));
    });

    test('owner export carries heart rate when present locally', () {
      final s = gpsSessions.firstWhere((s) => s.streams.containsKey(StreamKind.heartRate));
      final doc = _parse(GpxEncoder.encode(s));
      expect(doc.findAllElements('gpxtpx:hr'), isNotEmpty);
    });
  });

  group('U18 sessions without GPS', () {
    test('every non-GPS corpus session yields no_geometry (owner and shared)', () {
      for (final s in noGps) {
        expect(GpxEncoder.encode(s), isA<GpxNoGeometry>(), reason: s.id);
        expect(GpxEncoder.encode(s, audience: GpxAudience.shared), isA<GpxNoGeometry>(),
            reason: s.id);
      }
    });

    test('no file, no invented points and no empty track', () {
      final r = GpxEncoder.encode(noGps.first);
      expect(r, isNot(isA<GpxDocument>()));
    });

    test('the same sessions still encode to FIT and to the JSON summary export',
        () {
      for (final s in noGps) {
        expect(decodeFit(FitEncoder.encode(s)).ok, isTrue, reason: s.id);
        final entry = JournalEntry(
            session: s, state: const JournalState(), generation: 1, streamsLoaded: true);
        final fit = JournalActivityLocalExport.encodeEntry(entry, ActivityExportFormat.fit);
        final json = JournalActivityLocalExport.encodeEntry(entry, ActivityExportFormat.json);
        final gpx = JournalActivityLocalExport.encodeEntry(entry, ActivityExportFormat.gpx);
        expect(fit, isA<ActivityExportFile>(), reason: s.id);
        expect(json, isA<ActivityExportFile>(), reason: s.id);
        expect(gpx, isA<ActivityExportNoGeometry>(), reason: s.id);
        expect(jsonDecode(utf8.decode((json as ActivityExportFile).bytes)),
            isA<Map>());
      }
    });

    test('a GPS session never returns no_geometry (owner)', () {
      for (final s in gpsSessions) {
        expect(GpxEncoder.encode(s), isA<GpxDocument>(), reason: s.id);
      }
    });

    test('an empty GPS stream and an indoor sport without a stream are no_geometry',
        () {
      expect(GpxEncoder.encode(miniSession(sport: SportType.indoorCycling)),
          isA<GpxNoGeometry>());
    });

    test('a stream-lost entry exports only JSON', () {
      final entry = JournalEntry(
          session: gpsSessions.first,
          state: const JournalState(streamLost: true),
          generation: 1,
          streamsLoaded: false);
      expect(JournalActivityLocalExport.encodeEntry(entry, ActivityExportFormat.gpx),
          isA<ActivityExportStreamLost>());
      expect(JournalActivityLocalExport.encodeEntry(entry, ActivityExportFormat.fit),
          isA<ActivityExportStreamLost>());
      expect(JournalActivityLocalExport.encodeEntry(entry, ActivityExportFormat.json),
          isA<ActivityExportFile>());
    });
  });

  group('local export hook over a real journal', () {
    test('GPX, FIT and JSON of stored sessions; unknown id; exportAll', () async {
      final h = JournalHarness.memory();
      await h.open();
      addTearDown(h.dispose);
      final gps = journalSession(idFor(1), seed: 1);
      final indoor = journalSession(idFor(2), seed: 2, withGps: false);
      await h.journal.put(gps);
      await h.journal.put(indoor);
      final export = JournalActivityLocalExport(h.journal);

      final g = await export.exportActivity(idFor(1), ActivityExportFormat.gpx);
      expect(g, isA<ActivityExportFile>());
      final doc = XmlDocument.parse(utf8.decode((g as ActivityExportFile).bytes));
      expect(doc.findAllElements('trkpt'), hasLength(20));
      expect(g.fileName, matches(RegExp(r'^running_20260501T070000Z_[0-9a-zA-Z]{1,8}\.gpx$')));

      final f = await export.exportActivity(idFor(1), ActivityExportFormat.fit) as ActivityExportFile;
      expect(decodeFit(f.bytes).byNum(20), hasLength(20));

      expect(await export.exportActivity(idFor(2), ActivityExportFormat.gpx),
          isA<ActivityExportNoGeometry>());
      expect(await export.exportActivity(idFor(2), ActivityExportFormat.fit),
          isA<ActivityExportFile>());
      expect(await export.exportActivity(idFor(9), ActivityExportFormat.json),
          isA<ActivityExportNotFound>());

      final all = await export.exportAll(ActivityExportFormat.gpx);
      expect(all, hasLength(2));
      expect(all.whereType<ActivityExportFile>(), hasLength(1));
      expect(all.whereType<ActivityExportNoGeometry>(), hasLength(1));
    });
  });

  group('U20 owner export is the full series, shared export is trimmed', () {
    test('owner has as many points as the stream, shared drops the first and last '
        '200 m along the route', () {
      var trimmedSomething = 0;
      for (final s in gpsSessions) {
        final g = s.streams[StreamKind.gps]!;
        final owner = _pts(_parse(GpxEncoder.encode(s)));
        expect(owner, hasLength(g.length), reason: '${s.id} owner');
        final keep = _sharedKeep(g, 200);
        final shared = GpxEncoder.encode(s, audience: GpxAudience.shared);
        if (keep.isEmpty) {
          expect(shared, isA<GpxNoGeometry>(), reason: '${s.id} trimmed to nothing');
          continue;
        }
        final pts = _pts(_parse(shared));
        expect(pts, hasLength(keep.length), reason: '${s.id} shared');
        expect(pts.length, lessThan(g.length), reason: '${s.id} something is trimmed');
        trimmedSomething++;
        expect(double.parse(pts.first.getAttribute('lat')!),
            closeTo(g.lats[keep.first], 1e-6), reason: '${s.id} first kept');
        expect(double.parse(pts.last.getAttribute('lat')!),
            closeTo(g.lats[keep.last], 1e-6), reason: '${s.id} last kept');
        // the point before the first kept one lies inside the 200 m trim
        expect(keep.first, greaterThan(0));
        expect(keep.last, lessThan(g.length - 1));
      }
      expect(trimmedSomething, greaterThan(20), reason: 'the oracle must be exercised');
    });

    test('the trim distance follows privacy.routeTrimMeters (0 keeps all, 500 '
        'trims more)', () {
      final s = gpsSessions.firstWhere((s) => s.streams[StreamKind.gps]!.length > 600);
      final g = s.streams[StreamKind.gps]!;
      final none = s.copyWith(privacy: const ActivityPrivacy(routeTrimMeters: 0));
      expect(_pts(_parse(GpxEncoder.encode(none, audience: GpxAudience.shared))),
          hasLength(g.length));
      final big = s.copyWith(privacy: const ActivityPrivacy(routeTrimMeters: 500));
      final keep500 = _sharedKeep(g, 500);
      final keep200 = _sharedKeep(g, 200);
      expect(keep500.length, lessThan(keep200.length));
      expect(_pts(_parse(GpxEncoder.encode(big, audience: GpxAudience.shared))),
          hasLength(keep500.length));
    });

    test('a route shorter than twice the trim gives no_geometry when shared, a '
        'full file for the owner', () {
      final g = SampleStream.checked(
        kind: StreamKind.gps,
        sourceId: 'x',
        offsetsMs: const [0, 1000, 2000, 3000],
        lats: const [1.0, 1.0009, 1.0018, 1.0027], // about 100 m apart
        lons: const [2.0, 2.0, 2.0, 2.0],
      );
      final s = miniSession(streams: {StreamKind.gps: g});
      expect(_pts(_parse(GpxEncoder.encode(s))), hasLength(4));
      expect(GpxEncoder.encode(s, audience: GpxAudience.shared), isA<GpxNoGeometry>());
    });

    test('shared export carries no heart rate, owner export does', () {
      final s = gpsSessions.firstWhere((s) =>
          s.streams.containsKey(StreamKind.heartRate) &&
          _sharedKeep(s.streams[StreamKind.gps]!, 200).isNotEmpty);
      final owner = (GpxEncoder.encode(s) as GpxDocument).xml;
      final shared = (GpxEncoder.encode(s, audience: GpxAudience.shared) as GpxDocument).xml;
      expect(owner, contains('gpxtpx:hr'));
      expect(shared, isNot(contains('gpxtpx')));
      expect(shared, isNot(contains('TrackPointExtension')));
      expect(shared, isNot(contains('<hr')));
      expect(XmlDocument.parse(shared).findAllElements('extensions'), isEmpty);
    });
  });
}
