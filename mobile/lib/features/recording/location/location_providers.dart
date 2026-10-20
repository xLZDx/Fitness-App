import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_source.dart';

/// The location seam for the app.
///
/// Intentionally has no default implementation: the real adapter is wired by
/// the app-root provider overrides (lane R9) once the adapter file exists, and
/// tests override it with `FakeLocationSource`. Reading it unwired fails loudly
/// instead of silently recording nothing.
final locationSourceProvider = Provider<LocationSource>(
  (ref) => throw UnimplementedError(
    'locationSourceProvider must be overridden with a LocationSource',
  ),
);
