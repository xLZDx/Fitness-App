/// A-2: the sync cursor of one source (S02 design 1, 3.4: file
/// `sources/<sourceId>.cursor.json`). Pure Dart, no Flutter imports, no file
/// access: the journal layer stores the string, this class only owns the
/// shape and the tolerant read.
library;

import 'dart:convert';

class SourceCursor {
  const SourceCursor({
    required this.sourceId,
    required this.cursor,
    this.windowInclusive = true,
  });

  final String sourceId;

  /// Opaque position in the source's history (a token or an ISO timestamp);
  /// the adapter defines its meaning.
  final String cursor;

  /// True when the next fetch window includes the cursor position itself, so
  /// a record exactly at the boundary is read again (and deduplicated by the
  /// idempotent id) instead of being missed.
  final bool windowInclusive;

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'cursor': cursor,
        'windowInclusive': windowInclusive,
      };

  String toJsonString() => jsonEncode(toJson());

  /// Tolerant read of a decoded value; null when it is not a usable cursor.
  static SourceCursor? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['sourceId'];
    final cursor = raw['cursor'];
    final inclusive = raw['windowInclusive'];
    if (id is! String || id.isEmpty) return null;
    if (cursor is! String) return null;
    if (inclusive != null && inclusive is! bool) return null;
    return SourceCursor(
      sourceId: id,
      cursor: cursor,
      windowInclusive: (inclusive as bool?) ?? true,
    );
  }

  /// Parses a stored file body. A missing, corrupt or wrong-shape body is
  /// "no cursor" (null): the caller then starts from the beginning of the
  /// source window instead of failing. Never throws.
  static SourceCursor? tryParse(String? body) {
    if (body == null || body.isEmpty) return null;
    try {
      return tryFromJson(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  /// Like [tryParse] but also requires the cursor to belong to [expectedSourceId];
  /// a cursor file of another source is "no cursor".
  static SourceCursor? tryParseFor(String expectedSourceId, String? body) {
    final c = tryParse(body);
    return c != null && c.sourceId == expectedSourceId ? c : null;
  }

  @override
  bool operator ==(Object other) =>
      other is SourceCursor &&
      other.sourceId == sourceId &&
      other.cursor == cursor &&
      other.windowInclusive == windowInclusive;

  @override
  int get hashCode => Object.hash(sourceId, cursor, windowInclusive);
}
