// S02 test epic 3, U16: the A-3 DeviceSource surface. Compile-level checks
// (calls through the interface type) plus a source-text guard.
import 'dart:io';

import 'package:fitness_app/features/activity/data/activity_session.dart';
import 'package:fitness_app/features/activity/data/device_source.dart';
import 'package:fitness_app/features/activity/data/fake_device_source.dart';
import 'package:fitness_app/features/activity/data/sample_stream.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/s02_fixtures.dart';
import '../../../support/s02_paths.dart';

/// A source that implements every abstract member and nothing else. If a
/// member is added to the interface this class stops compiling.
class _MinimalSource implements DeviceSource {
  @override
  String get id => 'min';
  @override
  SourceKind get kind => SourceKind.fileImport;
  @override
  SourceCapabilities get capabilities => kCapabilityMatrix['vendor_cloud']!;
  @override
  Future<SourcePermission> permission(Set<StreamKind> kinds) async =>
      SourcePermission.denied;
  @override
  Future<SourcePermission> request(Set<StreamKind> kinds) async =>
      SourcePermission.denied;
  @override
  Future<List<ActivitySession>> fetchSessions(
          {required DateTime from, required DateTime to}) async =>
      const [];
  @override
  Stream<LiveSample> live(Set<StreamKind> kinds) => const Stream.empty();
  @override
  Future<void> disconnect({bool deleteImported = false}) async {}
  @override
  Future<SourceHealth> healthStatus() async => SourceHealth.unavailable;
  @override
  Future<void> deleteCached() async {}
  @override
  Stream<LiveSample> streamDuringWorkout(Set<StreamKind> kinds) =>
      const Stream.empty();
}

/// Inherits the default streamDuringWorkout.
class _Inheriting extends DeviceSource {
  @override
  String get id => 'inh';
  @override
  SourceKind get kind => SourceKind.fileImport;
  @override
  SourceCapabilities get capabilities => kCapabilityMatrix['vendor_cloud']!;
  @override
  Future<SourcePermission> permission(Set<StreamKind> kinds) async =>
      SourcePermission.denied;
  @override
  Future<SourcePermission> request(Set<StreamKind> kinds) async =>
      SourcePermission.denied;
  @override
  Future<List<ActivitySession>> fetchSessions(
          {required DateTime from, required DateTime to}) async =>
      const [];
  @override
  Stream<LiveSample> live(Set<StreamKind> kinds) => const Stream.empty();
  @override
  Future<void> disconnect({bool deleteImported = false}) async {}
  @override
  Future<SourceHealth> healthStatus() async => SourceHealth.ok;
  @override
  Future<void> deleteCached() async {}
}

/// Source files containing the forbidden write-back name.
List<String> filesWithWriteBack(Iterable<File> files) => [
      for (final f in files)
        if (f.readAsStringSync().contains('writeIfAuthorized')) f.path,
    ];

void main() {
  group('U16 A-3 interface surface', () {
    test('healthStatus() and deleteCached() exist on the DeviceSource type',
        () async {
      // Calls go through the interface type: removing a member breaks the build.
      final DeviceSource s = _MinimalSource();
      expect(await s.healthStatus(), SourceHealth.unavailable);
      await s.deleteCached();
      final DeviceSource f = FakeDeviceSource(id: 'f');
      expect(await f.healthStatus(), SourceHealth.ok);
    });

    test('the fake reports the configured health and counts deleteCached',
        () async {
      final f = FakeDeviceSource(id: 'f', sessions: [miniSession()]);
      for (final h in SourceHealth.values) {
        f.health = h;
        expect(await f.healthStatus(), h);
      }
      await f.deleteCached();
      await f.deleteCached();
      expect(f.deleteCachedCalls, 2, reason: 'idempotent, callable repeatedly');
      expect(f.imported, hasLength(1),
          reason: 'deleteCached must not touch imported activities');
    });

    test('streamDuringWorkout defaults to an empty, completing stream',
        () async {
      final s = _Inheriting();
      expect(await s.streamDuringWorkout({StreamKind.heartRate}).toList(),
          isEmpty);
      expect(SourceHealth.values, containsAll([SourceHealth.ok, SourceHealth.error]));
    });

    test('source text: no file under lib/ contains writeIfAuthorized', () {
      final lib = Directory('${repoRoot().path}/mobile/lib');
      final dart = lib
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(dart.length, greaterThan(100), reason: 'the scan must see the app');
      expect(filesWithWriteBack(dart), isEmpty);
    });

    test('the guard can fail: a temp file with the name is flagged', () {
      final d = Directory.systemTemp.createTempSync('u16_');
      addTearDown(() => d.deleteSync(recursive: true));
      final f = File('${d.path}/x.dart')
        ..writeAsStringSync('Future<void> writeIfAuthorized() async {}');
      expect(filesWithWriteBack([f]), [f.path]);
    });

    test('the abstract class has no write-style method (sources are read-only)',
        () {
      final text = supportFreeText(
          repoFile('mobile/lib/features/activity/data/device_source.dart')
              .readAsStringSync());
      final start = text.indexOf('abstract class DeviceSource');
      final end = text.indexOf('enum SourceHealth');
      expect(start, greaterThan(0));
      final body = text.substring(start, end);
      for (final bad in ['write', 'push', 'upload', 'save', r'delete\(']) {
        expect(RegExp(bad, caseSensitive: false).hasMatch(body.replaceAll('deleteCached', '').replaceAll('deleteImported', '')),
            isFalse,
            reason: bad);
      }
      expect(body, contains('healthStatus'));
      expect(body, contains('deleteCached'));
    });
  });
}

/// Source text without line comments.
String supportFreeText(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
