/// A-1: the quarantine stage in front of the merger (S02 design 1, 3.4).
/// Pure Dart, no Flutter imports, no file access. It checks the RAW text of an
/// untrusted activity record against hard limits and returns either the decoded
/// value or a reason code; the caller stores a rejected input under
/// `quarantine/` and never passes it to the merger. No importer exists in S02.
library;

import 'dart:convert';

enum QuarantineReason {
  tooLarge,
  malformedJson,
  tooDeep,
  stringTooLong,
  duplicateKey,
  tooManySamples,
  invalidNumber,
  notAnObject,
}

class QuarantineLimits {
  const QuarantineLimits({
    this.maxChars = 16 * 1024 * 1024,
    this.maxDepth = 32,
    this.maxStringChars = 1024 * 1024,
    this.maxSamplesPerStream = 200000,
  });

  final int maxChars;
  final int maxDepth;
  final int maxStringChars;
  final int maxSamplesPerStream;
}

class QuarantineResult {
  const QuarantineResult.accepted(this.value) : reason = null;
  const QuarantineResult.rejected(QuarantineReason this.reason) : value = null;

  /// The decoded top-level object when accepted.
  final Map<String, dynamic>? value;
  final QuarantineReason? reason;

  bool get accepted => reason == null;
}

class _Frame {
  _Frame(this.isObject);
  final bool isObject;
  final Set<String> keys = {};
  bool expectKey = true;
}

/// Validates [raw]; never throws.
QuarantineResult quarantineCheck(
  String raw, {
  QuarantineLimits limits = const QuarantineLimits(),
}) {
  if (raw.length > limits.maxChars) {
    return const QuarantineResult.rejected(QuarantineReason.tooLarge);
  }
  final scan = _scan(raw, limits);
  if (scan != null) return QuarantineResult.rejected(scan);

  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const QuarantineResult.rejected(QuarantineReason.malformedJson);
  }
  if (decoded is! Map<String, dynamic>) {
    return const QuarantineResult.rejected(QuarantineReason.notAnObject);
  }
  final streams = decoded['streams'];
  if (streams is List) {
    for (final s in streams) {
      if (s is! Map) continue;
      for (final key in const ['offsetsMs', 'values', 'lats', 'lons', 'accuracies']) {
        final list = s[key];
        if (list is! List) continue;
        if (list.length > limits.maxSamplesPerStream) {
          return const QuarantineResult.rejected(QuarantineReason.tooManySamples);
        }
        for (final v in list) {
          if (v is num && !v.isFinite) {
            return const QuarantineResult.rejected(QuarantineReason.invalidNumber);
          }
        }
      }
    }
  }
  return QuarantineResult.accepted(decoded);
}

/// Structural scan of the raw text: depth, string length, duplicate keys.
QuarantineReason? _scan(String raw, QuarantineLimits limits) {
  final stack = <_Frame>[];
  var i = 0;
  final n = raw.length;
  while (i < n) {
    final c = raw.codeUnitAt(i);
    if (c == 0x22) {
      var j = i + 1;
      while (j < n) {
        final d = raw.codeUnitAt(j);
        if (d == 0x5C) {
          j += 2;
          continue;
        }
        if (d == 0x22) break;
        j++;
      }
      if (j >= n) return QuarantineReason.malformedJson;
      if (j - i - 1 > limits.maxStringChars) return QuarantineReason.stringTooLong;
      if (stack.isNotEmpty && stack.last.isObject && stack.last.expectKey) {
        if (!stack.last.keys.add(raw.substring(i + 1, j))) {
          return QuarantineReason.duplicateKey;
        }
        stack.last.expectKey = false;
      }
      i = j + 1;
      continue;
    }
    if (c == 0x7B || c == 0x5B) {
      stack.add(_Frame(c == 0x7B));
      if (stack.length > limits.maxDepth) return QuarantineReason.tooDeep;
    } else if (c == 0x7D || c == 0x5D) {
      if (stack.isEmpty) return QuarantineReason.malformedJson;
      stack.removeLast();
    } else if (c == 0x2C) {
      if (stack.isNotEmpty && stack.last.isObject) stack.last.expectKey = true;
    }
    i++;
  }
  return null;
}
