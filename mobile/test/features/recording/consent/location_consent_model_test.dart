// S04-21 (DT-21-1, DT-21-5, DT-21-7, DT-21-8): the pure consent model.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/core/config/recording_defaults.dart';
import 'package:fitness_app/features/recording/consent/location_consent.dart';

ConsentRecord _rec({
  LocationConsentPurpose purpose = LocationConsentPurpose.locationWhileRecording,
  ConsentState state = ConsentState.granted,
  String version = 'draft-1',
  int ts = 1000,
  int? grantedAt,
}) =>
    ConsentRecord(
      purpose: purpose,
      state: state,
      textVersion: version,
      timestampUtcMs: ts,
      grantedAtUtcMs: grantedAt,
    );

void main() {
  group('ConsentRecord (DT-21-1 record fields)', () {
    test('json has exactly purpose, state, textVersion, timestamp', () {
      final j = _rec().toJson();
      expect(j.keys.toSet(), {'purpose', 'state', 'textVersion', 'timestamp'});
      expect(j['purpose'], 'location_while_recording');
      expect(j['state'], 'granted');
      expect(j['textVersion'], 'draft-1');
      expect(j['timestamp'], 1000);
    });

    test('grantedAt is written only when present', () {
      expect(_rec(grantedAt: 5).toJson()['grantedAt'], 5);
      expect(_rec().toJson().containsKey('grantedAt'), isFalse);
    });

    test('round trip keeps every field', () {
      final r = _rec(state: ConsentState.withdrawn, ts: 9, grantedAt: 3);
      final back = ConsentRecord.fromJson(jsonDecode(jsonEncode(r.toJson())))!;
      expect(back.purpose, r.purpose);
      expect(back.state, ConsentState.withdrawn);
      expect(back.textVersion, 'draft-1');
      expect(back.timestampUtcMs, 9);
      expect(back.grantedAtUtcMs, 3);
    });

    test('malformed records decode to null', () {
      expect(ConsentRecord.fromJson(null), isNull);
      expect(ConsentRecord.fromJson('x'), isNull);
      expect(ConsentRecord.fromJson({}), isNull);
      expect(
          ConsentRecord.fromJson({
            'purpose': 'nope',
            'state': 'granted',
            'textVersion': 'v',
            'timestamp': 1
          }),
          isNull,
          reason: 'unknown purpose');
      expect(
          ConsentRecord.fromJson({
            'purpose': 'location_while_recording',
            'state': 'granted',
            'textVersion': 3,
            'timestamp': 1
          }),
          isNull,
          reason: 'version not a string');
      expect(
          ConsentRecord.fromJson({
            'purpose': 'location_while_recording',
            'state': 'granted',
            'textVersion': 'v',
            'timestamp': '1'
          }),
          isNull,
          reason: 'timestamp not an int');
    });

    test('an unknown state token reads as none (fail closed)', () {
      final r = ConsentRecord.fromJson({
        'purpose': 'location_while_recording',
        'state': 'maybe',
        'textVersion': 'v',
        'timestamp': 1
      })!;
      expect(r.state, ConsentState.none);
    });

    test('toString carries no timestamp or version text', () {
      expect(_rec().toString(), 'ConsentRecord(location_while_recording, granted)');
    });
  });

  group('purposes and states', () {
    test('wire names are stable', () {
      expect(LocationConsentPurpose.locationWhileRecording.wireName,
          'location_while_recording');
      expect(LocationConsentPurpose.backgroundLocation.wireName,
          'background_location');
      expect(LocationConsentPurpose.fromWire('background_location'),
          LocationConsentPurpose.backgroundLocation);
      expect(LocationConsentPurpose.fromWire('x'), isNull);
      expect(LocationConsentPurpose.fromWire(null), isNull);
    });

    test('ConsentState.fromWire defaults to none', () {
      expect(ConsentState.fromWire('granted'), ConsentState.granted);
      expect(ConsentState.fromWire('withdrawn'), ConsentState.withdrawn);
      expect(ConsentState.fromWire(null), ConsentState.none);
      expect(ConsentState.fromWire(7), ConsentState.none);
    });
  });

  group('LocationConsent', () {
    test('none grants nothing', () {
      expect(LocationConsent.none.recordingGranted, isFalse);
      expect(LocationConsent.none.recordingState, ConsentState.none);
      expect(
          LocationConsent.none.stateOf(LocationConsentPurpose.backgroundLocation),
          ConsentState.none);
    });

    test('recordingGranted needs granted, not withdrawn, not none', () {
      expect(LocationConsent.none.withRecord(_rec()).recordingGranted, isTrue);
      expect(
          LocationConsent.none
              .withRecord(_rec(state: ConsentState.withdrawn))
              .recordingGranted,
          isFalse);
      expect(
          LocationConsent.none
              .withRecord(_rec(state: ConsentState.none))
              .recordingGranted,
          isFalse);
    });

    test('a background grant does not satisfy Start (DT-21-1 premature row)',
        () {
      final c = LocationConsent.none.withRecord(
          _rec(purpose: LocationConsentPurpose.backgroundLocation));
      expect(c.recordingGranted, isFalse);
      expect(c.stateOf(LocationConsentPurpose.backgroundLocation),
          ConsentState.granted);
    });

    test('withRecord is immutable and replaces the same purpose', () {
      final a = LocationConsent.none.withRecord(_rec(ts: 1));
      final b = a.withRecord(_rec(ts: 2, state: ConsentState.withdrawn));
      expect(a.recordOf(LocationConsentPurpose.locationWhileRecording)!.timestampUtcMs, 1);
      expect(b.records.length, 1);
      expect(b.recordingState, ConsentState.withdrawn);
    });

    test('encode/decode round trip with version 1 envelope', () {
      final c = LocationConsent.none
          .withRecord(_rec(ts: 5, grantedAt: 5))
          .withRecord(_rec(
              purpose: LocationConsentPurpose.backgroundLocation,
              state: ConsentState.withdrawn,
              ts: 6));
      final raw = c.encode();
      expect((jsonDecode(raw) as Map)['v'], 1);
      final back = LocationConsent.decode(raw);
      expect(back.records.length, 2);
      expect(back.recordingGranted, isTrue);
      expect(back.stateOf(LocationConsentPurpose.backgroundLocation),
          ConsentState.withdrawn);
    });

    group('fail closed on unusable stored values (DT-21-8)', () {
      final bad = <String, String?>{
        'null': null,
        'empty': '',
        'not json': 'granted',
        'truncated': '{"v":1,"records":[{"purpose":"location_while_rec',
        'json list': '[]',
        'json string': '"granted"',
        'records not a list': '{"v":1,"records":{}}',
        'no records': '{"v":1}',
      };
      for (final e in bad.entries) {
        test(e.key, () {
          final c = LocationConsent.decode(e.value);
          expect(c.recordingGranted, isFalse);
          expect(c.records, isEmpty);
        });
      }

      test('malformed items are skipped, a good sibling still decodes', () {
        final raw = jsonEncode({
          'v': 1,
          'records': [
            {'purpose': 'zzz'},
            _rec().toJson(),
            42,
          ]
        });
        final c = LocationConsent.decode(raw);
        expect(c.records.length, 1);
        expect(c.recordingGranted, isTrue);
      });

      test('an unknown state token inside a valid record is not a grant', () {
        final raw = jsonEncode({
          'v': 1,
          'records': [
            {
              'purpose': 'location_while_recording',
              'state': 'GRANTED',
              'textVersion': 'draft-1',
              'timestamp': 1
            }
          ]
        });
        expect(LocationConsent.decode(raw).recordingGranted, isFalse);
      });
    });

    test('toString does not leak record contents', () {
      expect(LocationConsent.none.withRecord(_rec()).toString(),
          'LocationConsent(1 records)');
    });
  });

  group('storage key (DT-21-5)', () {
    test('shape is activity.locationConsent.v1.<uid>', () {
      expect(locationConsentKeyFor('u1'), 'activity.locationConsent.v1.u1');
      expect(kLocationConsentKeyPrefix, 'activity.locationConsent.v1.');
    });

    test('does not collide with the cloud-streams consent key', () {
      expect(locationConsentKeyFor('u1'),
          isNot(startsWith('activity.cloudStreamsConsent.')));
      expect('activity.cloudStreamsConsent.u1',
          isNot(locationConsentKeyFor('u1')));
    });

    test('is account scoped and wipe-compatible (activity. prefix, .uid tail)',
        () {
      expect(locationConsentKeyFor('a'), isNot(locationConsentKeyFor('b')));
      final k = locationConsentKeyFor('uid-9');
      expect(k.startsWith('activity.'), isTrue);
      expect(k.endsWith('.uid-9'), isTrue);
    });
  });
}
