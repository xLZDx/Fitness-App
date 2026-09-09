import 'dart:convert';

import 'package:flutter/services.dart';

/// Where a measurement sits relative to a typical range. Advisory only: this
/// is never a diagnosis and never a rep-counting decision.
enum RomAdvisory { belowTypical, withinTypical, aboveTypical }

/// One typed range-of-motion row.
///
/// The type is the point. [joint] alone would not be enough — a hip has a
/// flexion range and a rotation range about different axes, and they are not
/// interchangeable — so a row is addressed by joint AND motion, and carries
/// the method and population that make a number comparable at all.
class JointRomRow {
  const JointRomRow({
    required this.id,
    required this.joint,
    required this.motion,
    required this.plane,
    required this.unit,
    required this.measurementMethod,
    required this.population,
    required this.typicalMinDeg,
    required this.typicalMaxDeg,
    required this.provenance,
  });

  final String id;
  final String joint;
  final String motion;
  final String plane;
  final String unit;
  final String measurementMethod;
  final String population;
  final double typicalMinDeg;
  final double typicalMaxDeg;
  final String provenance;

  RomAdvisory classify(double degrees) {
    if (degrees < typicalMinDeg) return RomAdvisory.belowTypical;
    if (degrees > typicalMaxDeg) return RomAdvisory.aboveTypical;
    return RomAdvisory.withinTypical;
  }

  factory JointRomRow.fromJson(Map<String, dynamic> j) {
    const required = [
      'id', 'joint', 'motion', 'plane', 'unit', 'measurementMethod',
      'population', 'typicalMinDeg', 'typicalMaxDeg', 'provenance',
    ];
    final missing = required.where((k) => !j.containsKey(k)).toList();
    if (missing.isNotEmpty) {
      throw FormatException('joint ROM row ${j['id']} is missing $missing');
    }
    return JointRomRow(
      id: j['id'] as String,
      joint: j['joint'] as String,
      motion: j['motion'] as String,
      plane: j['plane'] as String,
      unit: j['unit'] as String,
      measurementMethod: j['measurementMethod'] as String,
      population: j['population'] as String,
      typicalMinDeg: (j['typicalMinDeg'] as num).toDouble(),
      typicalMaxDeg: (j['typicalMaxDeg'] as num).toDouble(),
      provenance: j['provenance'] as String,
    );
  }
}

/// The joint range-of-motion reference: plausibility bounds, nothing more.
///
/// Deliberately independent of `measuredRepConfigs`. Those drive every
/// movement from a three-landmark SAGITTAL angle; every row here is a
/// TRANSVERSE-plane rotation. Both are degrees, which is not a relationship —
/// applying one to the other would produce validation that reads as rigorous
/// and means nothing. [advise] therefore refuses to answer unless the caller
/// names the same joint AND motion a row actually describes, so a rep angle
/// cannot be scored against a rotation range even by accident.
class JointRomReference {
  const JointRomReference({required this.clinicalUse, required this.rows});

  static const String assetPath = 'assets/data/joint_rom_reference.json';

  /// Always false in the shipped asset, and a test holds it there: the
  /// provenance is a poster photograph and an article, which is enough for an
  /// internal plausibility bound and not enough for a medical claim.
  final bool clinicalUse;
  final List<JointRomRow> rows;

  JointRomRow? row({required String joint, required String motion}) {
    for (final r in rows) {
      if (r.joint == joint && r.motion == motion) return r;
    }
    return null;
  }

  /// `null` when nothing describes this metric — never a guess.
  RomAdvisory? advise({
    required String joint,
    required String motion,
    required double degrees,
  }) =>
      row(joint: joint, motion: motion)?.classify(degrees);

  factory JointRomReference.parse(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    return JointRomReference(
      clinicalUse: j['clinical_use'] as bool? ?? false,
      rows: [
        for (final r in (j['rows'] as List<dynamic>))
          JointRomRow.fromJson(r as Map<String, dynamic>),
      ],
    );
  }

  static Future<JointRomReference> load({AssetBundle? bundle}) async =>
      JointRomReference.parse(
          await (bundle ?? rootBundle).loadString(assetPath));
}
