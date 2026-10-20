// S04-27 (DT-27-2 /to-string-content-free): the value classes that hold a
// coordinate must not print it. Regression for PipelineSample.toString, which
// printed lat and lon.
import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/recording/location/fix.dart';
import 'package:fitness_app/features/recording/pipeline/pipeline_types.dart';

const _lat = 12.3456789;
const _lon = -98.7654321;

void _expectClean(String text) {
  for (final s in [
    '12.3456789',
    '98.7654321',
    '12,3456789',
    '98,7654321',
    '12.3457',
    '98.7654',
    'lat',
    'lon',
  ]) {
    expect(text.contains(s), isFalse, reason: '"$s" leaked in: $text');
  }
}

void main() {
  test('Fix.toString shows no coordinate', () {
    const f = Fix(
        timeUtcMs: 1700000000000,
        latitude: _lat,
        longitude: _lon,
        accuracyMeters: 5,
        altitudeMeters: 100,
        speedMps: 2);
    _expectClean(f.toString());
  });

  test('PipelineSample.toString shows no coordinate (regression)', () {
    const s = PipelineSample(
        offsetMs: 1500,
        lat: _lat,
        lon: _lon,
        accuracyM: 4,
        altitudeM: 101,
        speedMps: 2);
    _expectClean(s.toString());
    _expectClean(s.copyWith(lat: _lat + 1, lon: _lon - 1).toString());
  });

  test('a list of samples prints content-free too', () {
    const a = PipelineSample(offsetMs: 0, lat: _lat, lon: _lon, accuracyM: 4);
    _expectClean([a, a].toString());
    _expectClean({'k': a}.toString());
  });

  test('string interpolation of a sample or fix is content-free', () {
    const f = Fix(
        timeUtcMs: 1, latitude: _lat, longitude: _lon, accuracyMeters: 5);
    const s = PipelineSample(offsetMs: 0, lat: _lat, lon: _lon, accuracyM: 4);
    _expectClean('failed on $f and $s');
  });
}
