// S04-17 (DT-17-5, DT-17-6, DT-17-13): the production PermissionService is
// driven through a mocked platform channel. Guards: never re-prompt a
// permanently denied / restricted permission, map platform states to the
// recorder's states, read the platform on every call.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fitness_app/features/recording/permissions/location_permission_status.dart';
import 'package:fitness_app/features/recording/permissions/permission_handler_permission_service.dart';

const _channel = MethodChannel('flutter.baseflow.com/permissions/methods');

class _Platform {
  final Map<int, PermissionStatus> status = {};
  final Map<int, PermissionStatus> afterRequest = {};
  final List<String> calls = [];
  bool openResult = true;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case 'checkPermissionStatus':
        return (status[call.arguments as int] ?? PermissionStatus.denied).index;
      case 'requestPermissions':
        final ids = (call.arguments as List).cast<int>();
        final out = <int, int>{};
        for (final id in ids) {
          final next = afterRequest[id] ?? status[id] ?? PermissionStatus.denied;
          status[id] = next;
          out[id] = next.index;
        }
        return out;
      case 'openAppSettings':
        return openResult;
    }
    return null;
  }

  int count(String m) => calls.where((c) => c == m).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  final loc = Permission.location.value;
  final notif = Permission.notification.value;

  setUp(() {
    platform = _Platform();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, platform.handle);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('location status mapping', () {
    const svc = PermissionHandlerPermissionService();
    final table = <PermissionStatus, LocationPermissionStatus>{
      PermissionStatus.granted: LocationPermissionStatus.grantedPrecise,
      PermissionStatus.denied: LocationPermissionStatus.denied,
      PermissionStatus.permanentlyDenied:
          LocationPermissionStatus.permanentlyDenied,
      PermissionStatus.restricted: LocationPermissionStatus.restricted,
      PermissionStatus.limited: LocationPermissionStatus.grantedApproximate,
    };
    for (final e in table.entries) {
      test('${e.key.name} -> ${e.value.name}', () async {
        platform.status[loc] = e.key;
        expect(await svc.locationStatus(), e.value);
        expect(platform.count('requestPermissions'), 0,
            reason: 'a status read must never prompt');
      });
    }

    test('granted with a precise probe false is approximate (DT-17-6)',
        () async {
      platform.status[loc] = PermissionStatus.granted;
      final s = PermissionHandlerPermissionService(
          isPreciseGranted: () async => false);
      expect(await s.locationStatus(), LocationPermissionStatus.grantedApproximate);
    });

    test('granted with a precise probe true is precise', () async {
      platform.status[loc] = PermissionStatus.granted;
      final s = PermissionHandlerPermissionService(
          isPreciseGranted: () async => true);
      expect(await s.locationStatus(), LocationPermissionStatus.grantedPrecise);
    });

    test('the probe is not consulted for a non-granted status', () async {
      platform.status[loc] = PermissionStatus.denied;
      var probed = false;
      final s = PermissionHandlerPermissionService(
          isPreciseGranted: () async => probed = true);
      expect(await s.locationStatus(), LocationPermissionStatus.denied);
      expect(probed, isFalse);
    });

    test('nothing is cached: a platform change shows on the next read '
        '(DT-17-13)', () async {
      platform.status[loc] = PermissionStatus.granted;
      expect(await svc.locationStatus(), LocationPermissionStatus.grantedPrecise);
      platform.status[loc] = PermissionStatus.denied;
      expect(await svc.locationStatus(), LocationPermissionStatus.denied);
      expect(platform.count('checkPermissionStatus'), 2);
    });
  });

  group('requestLocation', () {
    const svc = PermissionHandlerPermissionService();

    test('prompts once for a denied permission and returns the result',
        () async {
      platform.status[loc] = PermissionStatus.denied;
      platform.afterRequest[loc] = PermissionStatus.granted;
      expect(await svc.requestLocation(), LocationPermissionStatus.grantedPrecise);
      expect(platform.count('requestPermissions'), 1);
    });

    test('permanently denied is never re-prompted (DT-17-5)', () async {
      platform.status[loc] = PermissionStatus.permanentlyDenied;
      platform.afterRequest[loc] = PermissionStatus.granted;
      for (var i = 0; i < 5; i++) {
        expect(await svc.requestLocation(),
            LocationPermissionStatus.permanentlyDenied);
      }
      expect(platform.count('requestPermissions'), 0);
    });

    test('restricted is never prompted', () async {
      platform.status[loc] = PermissionStatus.restricted;
      expect(await svc.requestLocation(), LocationPermissionStatus.restricted);
      expect(platform.count('requestPermissions'), 0);
    });

    test('a user answer of denied-forever is reported as such', () async {
      platform.status[loc] = PermissionStatus.denied;
      platform.afterRequest[loc] = PermissionStatus.permanentlyDenied;
      expect(await svc.requestLocation(),
          LocationPermissionStatus.permanentlyDenied);
    });
  });

  group('notification', () {
    const svc = PermissionHandlerPermissionService();
    final table = <PermissionStatus, NotificationPermissionStatus>{
      PermissionStatus.granted: NotificationPermissionStatus.granted,
      PermissionStatus.provisional: NotificationPermissionStatus.granted,
      PermissionStatus.denied: NotificationPermissionStatus.denied,
      PermissionStatus.permanentlyDenied:
          NotificationPermissionStatus.permanentlyDenied,
      PermissionStatus.restricted: NotificationPermissionStatus.permanentlyDenied,
    };
    for (final e in table.entries) {
      test('${e.key.name} -> ${e.value.name}', () async {
        platform.status[notif] = e.key;
        expect(await svc.notificationStatus(), e.value);
      });
    }

    test('permanently denied is not re-prompted', () async {
      platform.status[notif] = PermissionStatus.permanentlyDenied;
      platform.afterRequest[notif] = PermissionStatus.granted;
      expect(await svc.requestNotification(),
          NotificationPermissionStatus.permanentlyDenied);
      expect(platform.count('requestPermissions'), 0);
    });

    test('denied is prompted once', () async {
      platform.status[notif] = PermissionStatus.denied;
      platform.afterRequest[notif] = PermissionStatus.granted;
      expect(await svc.requestNotification(),
          NotificationPermissionStatus.granted);
      expect(platform.count('requestPermissions'), 1);
    });
  });

  test('openSettings delegates to the platform and returns its answer',
      () async {
    const svc = PermissionHandlerPermissionService();
    expect(await svc.openSettings(), isTrue);
    platform.openResult = false;
    expect(await svc.openSettings(), isFalse);
    expect(platform.count('openAppSettings'), 2);
    expect(platform.count('requestPermissions'), 0);
  });
}
