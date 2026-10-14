// Loader and strict validator for `assets/data/coach_exercises.json`
// (schema `coach_exercises/v1`).
//
// Contract: any invalid entry throws [CoachRegistryException] naming the
// offending path (`exercises[2].rules[0].phase`). Nothing is skipped or
// defaulted -- a half-valid registry would silently coach with wrong numbers.
// An empty `exercises` list is valid.

import 'dart:convert';

import 'package:flutter/services.dart';

import 'coach_spec.dart';

class CoachRegistryException implements Exception {
  CoachRegistryException(this.path, this.message);
  final String path;
  final String message;

  @override
  String toString() => 'CoachRegistryException at $path: $message';
}

class CoachRegistry {
  CoachRegistry._(this.exercises)
      : _byId = {for (final e in exercises) e.id: e},
        _byAlias = {
          for (final e in exercises)
            for (final a in e.aliases) a: e,
        };

  static const assetPath = 'assets/data/coach_exercises.json';
  static const schema = 'coach_exercises/v1';

  final List<CoachSpec> exercises;
  final Map<String, CoachSpec> _byId;
  final Map<String, CoachSpec> _byAlias;

  CoachSpec? byId(String id) => _byId[id];

  /// Resolves an exercise id or a catalog pose alias.
  CoachSpec? lookup(String idOrAlias) =>
      _byId[idOrAlias] ?? _byAlias[idOrAlias];

  /// Loads and validates the bundled asset. Throws on any invalid entry.
  static Future<CoachRegistry> load({AssetBundle? bundle, String? key}) async {
    final text = await (bundle ?? rootBundle).loadString(key ?? assetPath);
    return parse(text);
  }

  static CoachRegistry parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (e) {
      throw CoachRegistryException(r'$', 'not valid JSON: ${e.message}');
    }
    return fromJson(decoded);
  }

  static CoachRegistry fromJson(Object? decoded) {
    final root = _map(decoded, r'$');
    _noExtraKeys(root, const {'schema', 'exercises'}, r'$');
    if (root['schema'] != schema) {
      throw CoachRegistryException(
          r'$.schema', 'expected "$schema", got ${root['schema']}');
    }
    final list = _list(root['exercises'], r'$.exercises');
    final specs = <CoachSpec>[];
    final ids = <String>{};
    final aliases = <String, String>{};
    for (var i = 0; i < list.length; i++) {
      final p = 'exercises[$i]';
      final spec = _parseSpec(_map(list[i], p), p);
      if (!ids.add(spec.id)) {
        throw CoachRegistryException('$p.id', 'duplicate id "${spec.id}"');
      }
      for (final a in spec.aliases) {
        final prev = aliases[a];
        if (prev != null) {
          throw CoachRegistryException(
              '$p.aliases', 'alias "$a" already claimed by "$prev"');
        }
        aliases[a] = spec.id;
      }
      specs.add(spec);
    }
    // An alias that shadows another exercise's id would be ambiguous.
    for (final e in aliases.entries) {
      if (ids.contains(e.key) && e.key != e.value) {
        throw CoachRegistryException('aliases',
            'alias "${e.key}" of "${e.value}" collides with an exercise id');
      }
    }
    return CoachRegistry._(List.unmodifiable(specs));
  }
}

/// Cross-check hook (used by the cue-text package): every rule `cueId` must be
/// a member of [knownCueIds]. Throws listing ALL unknown ids.
void validateCueIds(CoachRegistry registry, Set<String> knownCueIds) {
  final problems = <String>[];
  for (final e in registry.exercises) {
    for (final r in e.rules) {
      if (!knownCueIds.contains(r.cueId)) {
        problems.add('${e.id}.${r.id} -> "${r.cueId}"');
      }
    }
  }
  if (problems.isNotEmpty) {
    throw CoachRegistryException(
        'rules.cueId', 'unknown cue ids: ${problems.join('; ')}');
  }
}

// ---------------------------------------------------------------------------

CoachSpec _parseSpec(Map<String, Object?> m, String p) {
  _noExtraKeys(
      m,
      const {
        'id',
        'aliases',
        'version',
        'view',
        'sidePolicy',
        'tracked',
        'unscored',
        'phases',
        'signal',
        'counting',
        'rules',
        'safetyWording',
        'provenance',
      },
      p);
  final id = _str(m, 'id', p);
  final version = _int(m, 'version', p);
  if (version < 1) {
    throw CoachRegistryException('$p.version', 'must be >= 1, got $version');
  }
  final view = _enum(CoachView.values, _str(m, 'view', p), '$p.view',
      const {'side': CoachView.side, 'front': CoachView.front});
  final sidePolicy = _enum(
      CoachSidePolicy.values, _str(m, 'sidePolicy', p), '$p.sidePolicy', const {
    'bestVisible': CoachSidePolicy.bestVisible,
    'both': CoachSidePolicy.both,
    'fixed:left': CoachSidePolicy.fixedLeft,
  });

  final aliases = _strList(m, 'aliases', p);
  final tracked = _strList(m, 'tracked', p);
  if (tracked.isEmpty) {
    throw CoachRegistryException('$p.tracked', 'must not be empty');
  }
  final unscored = _strList(m, 'unscored', p);
  for (final entry in {'tracked': tracked, 'unscored': unscored}.entries) {
    for (var i = 0; i < entry.value.length; i++) {
      _landmark(entry.value[i], '$p.${entry.key}[$i]');
    }
  }

  final phaseList = _list(m['phases'], '$p.phases');
  if (phaseList.isEmpty) {
    throw CoachRegistryException('$p.phases', 'must not be empty');
  }
  final phases = <CoachPhase>[];
  final phaseNames = <String>{};
  for (var i = 0; i < phaseList.length; i++) {
    final pp = '$p.phases[$i]';
    final pm = _map(phaseList[i], pp);
    _noExtraKeys(pm, const {'name', 'entry'}, pp);
    final name = _str(pm, 'name', pp);
    if (!phaseNames.add(name)) {
      throw CoachRegistryException('$pp.name', 'duplicate phase "$name"');
    }
    phases.add(CoachPhase(name: name, entry: _str(pm, 'entry', pp)));
  }

  final signal = _parseSignal(_map(m['signal'], '$p.signal'), '$p.signal');
  final counting =
      _parseCounting(_map(m['counting'], '$p.counting'), '$p.counting');
  final provenance = _parseProvenance(
      _map(m['provenance'], '$p.provenance'), '$p.provenance');

  final ruleList = _list(m['rules'], '$p.rules');
  final rules = <CoachRule>[];
  final ruleIds = <String>{};
  for (var i = 0; i < ruleList.length; i++) {
    final rp = '$p.rules[$i]';
    final rule = _parseRule(_map(ruleList[i], rp), rp);
    if (!ruleIds.add(rule.id)) {
      throw CoachRegistryException('$rp.id', 'duplicate rule id "${rule.id}"');
    }
    if (!phaseNames.contains(rule.phase)) {
      throw CoachRegistryException('$rp.phase',
          'unknown phase "${rule.phase}" (declared: ${phaseNames.join(', ')})');
    }
    if (provenance.kind == CoachProvenanceKind.authored && !rule.advisory) {
      throw CoachRegistryException(
          '$rp.advisory', 'authored rows must have advisory=true');
    }
    rules.add(rule);
  }

  return CoachSpec(
    id: id,
    aliases: List.unmodifiable(aliases),
    version: version,
    view: view,
    sidePolicy: sidePolicy,
    tracked: List.unmodifiable(tracked),
    unscored: List.unmodifiable(unscored),
    phases: List.unmodifiable(phases),
    signal: signal,
    counting: counting,
    rules: List.unmodifiable(rules),
    safetyWording: _bool(m, 'safetyWording', p),
    provenance: provenance,
  );
}

CoachSignal _parseSignal(Map<String, Object?> m, String p) {
  _noExtraKeys(
      m, const {'kind', 'joints', 'normalizeBy', 'direction', 'enter', 'exit'},
      p);
  final kind = _enum(CoachSignalKind.values, _str(m, 'kind', p), '$p.kind', const {
    'angle': CoachSignalKind.angle,
    'ratio': CoachSignalKind.ratio,
    'lineDeviation': CoachSignalKind.lineDeviation,
  });
  final joints = _strList(m, 'joints', p);
  for (var i = 0; i < joints.length; i++) {
    _landmark(joints[i], '$p.joints[$i]');
  }
  final want = kind == CoachSignalKind.ratio ? 2 : 3;
  if (joints.length != want) {
    throw CoachRegistryException(
        '$p.joints', '${kind.name} needs exactly $want joints, got ${joints.length}');
  }
  final norm = m['normalizeBy'];
  final bool normalized;
  if (kind == CoachSignalKind.angle) {
    if (norm != null) {
      throw CoachRegistryException(
          '$p.normalizeBy', 'an angle signal must not set normalizeBy');
    }
    normalized = false;
  } else {
    if (norm != 'torso') {
      throw CoachRegistryException('$p.normalizeBy',
          '${kind.name} must set normalizeBy: "torso" (never pixels), got $norm');
    }
    normalized = true;
  }
  final direction = _enum(CoachSignalDirection.values, _str(m, 'direction', p),
      '$p.direction', const {
    'falling': CoachSignalDirection.falling,
    'rising': CoachSignalDirection.rising,
  });
  final enter = _num(m, 'enter', p);
  final exit = _num(m, 'exit', p);
  final ok = direction == CoachSignalDirection.falling ? enter < exit : enter > exit;
  if (!ok) {
    throw CoachRegistryException(
        '$p.enter',
        '${direction.name} signal needs enter ${direction == CoachSignalDirection.falling ? '<' : '>'} exit, '
            'got enter=$enter exit=$exit');
  }
  return CoachSignal(
    kind: kind,
    joints: List.unmodifiable(joints),
    direction: direction,
    enter: enter,
    exit: exit,
    normalizeTorso: normalized,
  );
}

CoachCounting _parseCounting(Map<String, Object?> m, String p) {
  _noExtraKeys(m, const {'mode', 'minHoldMs'}, p);
  final mode = _enum(CoachCountingMode.values, _str(m, 'mode', p), '$p.mode', const {
    'reps': CoachCountingMode.reps,
    'hold': CoachCountingMode.hold,
    'off': CoachCountingMode.off,
  });
  final raw = m['minHoldMs'];
  if (mode == CoachCountingMode.hold) {
    if (raw is! int || raw <= 0) {
      throw CoachRegistryException(
          '$p.minHoldMs', 'hold exercises need an integer minHoldMs > 0, got $raw');
    }
    return CoachCounting(mode: mode, minHoldMs: raw);
  }
  if (raw != null) {
    throw CoachRegistryException(
        '$p.minHoldMs', 'only valid for mode "hold", got mode "${mode.name}"');
  }
  return CoachCounting(mode: mode);
}

CoachRule _parseRule(Map<String, Object?> m, String p) {
  _noExtraKeys(
      m,
      const {
        'id',
        'metric',
        'min',
        'max',
        'tolerance',
        'phase',
        'severity',
        'cueId',
        'advisory',
      },
      p);
  final min = m['min'] == null ? null : _num(m, 'min', p);
  final max = m['max'] == null ? null : _num(m, 'max', p);
  if (min == null && max == null) {
    throw CoachRegistryException(p, 'rule needs at least one of min/max');
  }
  if (min != null && max != null && min > max) {
    throw CoachRegistryException('$p.min', 'min $min > max $max');
  }
  final tolerance = _num(m, 'tolerance', p);
  if (tolerance < 0) {
    throw CoachRegistryException('$p.tolerance', 'must be >= 0, got $tolerance');
  }
  return CoachRule(
    id: _str(m, 'id', p),
    metric: _str(m, 'metric', p),
    min: min,
    max: max,
    tolerance: tolerance,
    phase: _str(m, 'phase', p),
    severity: _enum(CoachSeverity.values, _str(m, 'severity', p), '$p.severity', const {
      'minor': CoachSeverity.minor,
      'major': CoachSeverity.major,
      'safety': CoachSeverity.safety,
    }),
    cueId: _str(m, 'cueId', p),
    advisory: _bool(m, 'advisory', p),
  );
}

CoachProvenance _parseProvenance(Map<String, Object?> m, String p) {
  _noExtraKeys(m, const {'kind', 'source', 'status'}, p);
  final kind = _enum(CoachProvenanceKind.values, _str(m, 'kind', p), '$p.kind', const {
    'measured': CoachProvenanceKind.measured,
    'authored': CoachProvenanceKind.authored,
    'literature': CoachProvenanceKind.literature,
  });
  final status = _enum(
      CoachProvenanceStatus.values, _str(m, 'status', p), '$p.status', const {
    'beta': CoachProvenanceStatus.beta,
    'stable': CoachProvenanceStatus.stable,
  });
  if (kind == CoachProvenanceKind.authored && status != CoachProvenanceStatus.beta) {
    throw CoachRegistryException(
        '$p.status', 'authored rows must have status "beta", got "${status.name}"');
  }
  return CoachProvenance(kind: kind, source: _str(m, 'source', p), status: status);
}

// --- primitives ------------------------------------------------------------

void _landmark(String name, String p) {
  if (resolveCoachLandmark(name) == null) {
    throw CoachRegistryException(p, 'unknown landmark name "$name"');
  }
}

Map<String, Object?> _map(Object? v, String p) {
  if (v is Map<String, Object?>) return v;
  if (v is Map) return v.cast<String, Object?>();
  throw CoachRegistryException(p, 'expected an object, got ${_t(v)}');
}

List<Object?> _list(Object? v, String p) {
  if (v is List) return v.cast<Object?>();
  throw CoachRegistryException(p, 'expected an array, got ${_t(v)}');
}

String _t(Object? v) => v == null ? 'missing/null' : v.runtimeType.toString();

String _str(Map<String, Object?> m, String k, String p) {
  final v = m[k];
  if (v is String && v.trim().isNotEmpty) return v;
  throw CoachRegistryException('$p.$k', 'expected a non-empty string, got ${_t(v)}');
}

int _int(Map<String, Object?> m, String k, String p) {
  final v = m[k];
  if (v is int) return v;
  throw CoachRegistryException('$p.$k', 'expected an integer, got ${_t(v)}');
}

double _num(Map<String, Object?> m, String k, String p) {
  final v = m[k];
  if (v is num && v.isFinite) return v.toDouble();
  throw CoachRegistryException('$p.$k', 'expected a finite number, got ${_t(v)}');
}

bool _bool(Map<String, Object?> m, String k, String p) {
  final v = m[k];
  if (v is bool) return v;
  throw CoachRegistryException('$p.$k', 'expected a boolean, got ${_t(v)}');
}

List<String> _strList(Map<String, Object?> m, String k, String p) {
  final raw = _list(m[k], '$p.$k');
  final out = <String>[];
  for (var i = 0; i < raw.length; i++) {
    final v = raw[i];
    if (v is! String || v.trim().isEmpty) {
      throw CoachRegistryException('$p.$k[$i]', 'expected a non-empty string, got ${_t(v)}');
    }
    out.add(v);
  }
  if (out.toSet().length != out.length) {
    throw CoachRegistryException('$p.$k', 'contains duplicate entries');
  }
  return out;
}

T _enum<T>(List<T> _, String raw, String p, Map<String, T> table) {
  final v = table[raw];
  if (v == null) {
    throw CoachRegistryException(
        p, 'unknown value "$raw" (allowed: ${table.keys.join(', ')})');
  }
  return v;
}

void _noExtraKeys(Map<String, Object?> m, Set<String> allowed, String p) {
  for (final k in m.keys) {
    if (!allowed.contains(k)) {
      throw CoachRegistryException('$p.$k', 'unknown field');
    }
  }
}
