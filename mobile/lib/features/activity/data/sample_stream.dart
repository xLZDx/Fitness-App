/// Time-series samples of one kind from one source (design s31.1). Pure Dart,
/// no Flutter imports.
///
/// Canonical SI units only; km/miles, min/km and feet are presentation
/// concerns and are never converted in the data layer.
library;

enum StreamKind {
  heartRate('bpm'),
  speed('m/s'),
  cadence('rpm'),
  power('W'),
  altitude('m'),

  /// WGS84 degrees in the parallel `lats` / `lons` lists.
  gps('deg'),
  strokeRate('strokes/min'),
  temperature('degC');

  const StreamKind(this.unit);

  /// The canonical unit of the values.
  final String unit;

  static StreamKind? byName(Object? name) {
    if (name is! String) return null;
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

class SampleStream {
  /// Prefer [SampleStream.checked] / [SampleStream.tryFromJson], which
  /// validate. This constructor trusts its inputs.
  const SampleStream._({
    required this.kind,
    required this.sourceId,
    required this.offsetsMs,
    required this.values,
    required this.lats,
    required this.lons,
    required this.accuracies,
  });

  final StreamKind kind;
  final String sourceId;

  /// Milliseconds from the session's `startUtc`, STRICTLY increasing.
  final List<int> offsetsMs;

  /// One value per offset (empty for [StreamKind.gps]).
  final List<double> values;

  /// GPS only: parallel to [offsetsMs].
  final List<double> lats;
  final List<double> lons;
  final List<double> accuracies;

  int get length => offsetsMs.length;
  bool get isEmpty => offsetsMs.isEmpty;

  /// The first problem with the given data, or null when valid.
  static String? validate({
    required StreamKind kind,
    required List<int> offsetsMs,
    List<double> values = const [],
    List<double> lats = const [],
    List<double> lons = const [],
    List<double> accuracies = const [],
  }) {
    for (var i = 1; i < offsetsMs.length; i++) {
      if (offsetsMs[i] <= offsetsMs[i - 1]) {
        return 'offsets are not strictly increasing';
      }
    }
    if (kind == StreamKind.gps) {
      if (lats.length != offsetsMs.length || lons.length != offsetsMs.length) {
        return 'gps lists differ in length from offsets';
      }
      if (accuracies.isNotEmpty && accuracies.length != offsetsMs.length) {
        return 'gps accuracy list differs in length from offsets';
      }
      if (values.isNotEmpty) return 'gps carries values';
    } else {
      if (values.length != offsetsMs.length) {
        return 'values differ in length from offsets';
      }
      if (lats.isNotEmpty || lons.isNotEmpty) return 'non-gps carries lat/lon';
    }
    return null;
  }

  /// Throws [ArgumentError] for invalid data (non-increasing or duplicate
  /// offsets, length mismatch).
  factory SampleStream.checked({
    required StreamKind kind,
    required String sourceId,
    required List<int> offsetsMs,
    List<double> values = const [],
    List<double> lats = const [],
    List<double> lons = const [],
    List<double> accuracies = const [],
  }) {
    final problem = validate(
      kind: kind,
      offsetsMs: offsetsMs,
      values: values,
      lats: lats,
      lons: lons,
      accuracies: accuracies,
    );
    if (problem != null) throw ArgumentError(problem);
    return SampleStream._(
      kind: kind,
      sourceId: sourceId,
      offsetsMs: List.unmodifiable(offsetsMs),
      values: List.unmodifiable(values),
      lats: List.unmodifiable(lats),
      lons: List.unmodifiable(lons),
      accuracies: List.unmodifiable(accuracies),
    );
  }

  /// Fraction of [sessionDurationMs] covered between the first and last
  /// sample, in 0..1.
  double coverage(int sessionDurationMs) {
    if (offsetsMs.length < 2 || sessionDurationMs <= 0) return 0;
    final c = (offsetsMs.last - offsetsMs.first) / sessionDurationMs;
    return c < 0 ? 0 : (c > 1 ? 1 : c);
  }

  /// A copy with every offset shifted by [deltaMs]; samples that would land
  /// before the session start are dropped. Order stays strictly increasing.
  SampleStream shifted(int deltaMs) {
    final keep = <int>[
      for (var i = 0; i < offsetsMs.length; i++)
        if (offsetsMs[i] + deltaMs >= 0) i,
    ];
    return SampleStream._(
      kind: kind,
      sourceId: sourceId,
      offsetsMs: List.unmodifiable([for (final i in keep) offsetsMs[i] + deltaMs]),
      values: List.unmodifiable(
          [for (final i in keep) if (values.isNotEmpty) values[i]]),
      lats: List.unmodifiable([for (final i in keep) if (lats.isNotEmpty) lats[i]]),
      lons: List.unmodifiable([for (final i in keep) if (lons.isNotEmpty) lons[i]]),
      accuracies: List.unmodifiable(
          [for (final i in keep) if (accuracies.isNotEmpty) accuracies[i]]),
    );
  }

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'unit': kind.unit,
        'sourceId': sourceId,
        'offsetsMs': offsetsMs,
        if (values.isNotEmpty) 'values': values,
        if (lats.isNotEmpty) 'lats': lats,
        if (lons.isNotEmpty) 'lons': lons,
        if (accuracies.isNotEmpty) 'accuracies': accuracies,
      };

  /// Tolerant read; null when the stream is unusable or invalid.
  static SampleStream? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = StreamKind.byName(raw['kind']);
    final source = raw['sourceId'];
    final offsets = _ints(raw['offsetsMs']);
    if (kind == null || source is! String || offsets == null) return null;
    final values = _doubles(raw['values']) ?? const <double>[];
    final lats = _doubles(raw['lats']) ?? const <double>[];
    final lons = _doubles(raw['lons']) ?? const <double>[];
    final acc = _doubles(raw['accuracies']) ?? const <double>[];
    if (validate(
          kind: kind,
          offsetsMs: offsets,
          values: values,
          lats: lats,
          lons: lons,
          accuracies: acc,
        ) !=
        null) {
      return null;
    }
    return SampleStream._(
      kind: kind,
      sourceId: source,
      offsetsMs: List.unmodifiable(offsets),
      values: List.unmodifiable(values),
      lats: List.unmodifiable(lats),
      lons: List.unmodifiable(lons),
      accuracies: List.unmodifiable(acc),
    );
  }

  static List<int>? _ints(Object? v) {
    if (v is! List) return null;
    final out = <int>[];
    for (final e in v) {
      if (e is! num || !e.isFinite) return null;
      out.add(e.toInt());
    }
    return out;
  }

  static List<double>? _doubles(Object? v) {
    if (v == null) return null;
    if (v is! List) return null;
    final out = <double>[];
    for (final e in v) {
      if (e is! num) return null;
      out.add(e.toDouble());
    }
    return out;
  }
}
