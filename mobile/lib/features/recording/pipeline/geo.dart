/// Great-circle geometry for the recording pipeline (design 3.7). Pure Dart,
/// no Flutter imports.
library;

import 'dart:math' as math;

import 'recording_constants.dart';

const double _degToRad = math.pi / 180.0;

/// Metres per degree of latitude on the sphere of [kMeanEarthRadiusM].
const double kMetresPerDegree = kMeanEarthRadiusM * _degToRad;

/// Haversine distance in metres between two WGS84 points on a sphere of
/// [kMeanEarthRadiusM].
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  final p1 = lat1 * _degToRad;
  final p2 = lat2 * _degToRad;
  final dp = (lat2 - lat1) * _degToRad;
  final dl = (lon2 - lon1) * _degToRad;
  final sdp = math.sin(dp / 2);
  final sdl = math.sin(dl / 2);
  final a = sdp * sdp + math.cos(p1) * math.cos(p2) * sdl * sdl;
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return kMeanEarthRadiusM * c;
}

/// Whether [lat] and [lon] are finite and inside the WGS84 ranges.
bool isValidCoordinate(double lat, double lon) =>
    lat.isFinite &&
    lon.isFinite &&
    lat >= -90.0 &&
    lat <= 90.0 &&
    lon >= -180.0 &&
    lon <= 180.0;

/// Square root of [x*x + y*y] without a dependency on the caller importing
/// `dart:math`.
double hypotM(double x, double y) => math.sqrt(x * x + y * y);

/// Cosine of a latitude in degrees.
double cosLatDeg(double latDeg) => math.cos(latDeg * _degToRad);
