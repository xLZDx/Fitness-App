/// The kind of place a piece of activity data came from (design s31.1). Pure
/// Dart, no Flutter imports. Lives in its own file so `source_record.dart` does
/// not have to import `device_source.dart`, which imports the activity session
/// that holds source records (an import cycle). `device_source.dart` re-exports
/// it, so existing imports keep working.
library;

enum SourceKind {
  platformHealth,
  bleSensor,
  vendorCloud,
  companionApp,
  fileImport;

  static SourceKind parse(Object? name) {
    if (name is String) {
      for (final k in values) {
        if (k.name == name) return k;
      }
    }
    return SourceKind.fileImport;
  }
}
