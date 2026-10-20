import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fitness_app/features/recording/location/fix.dart';
import 'package:fitness_app/features/recording/location/location_source.dart';
import 'package:fitness_app/features/recording/location/stream_location_source.dart';

class _Plugin {
  int live = 0;
  int created = 0;
  final List<StreamController<Fix>> controllers = [];
  Duration cancelDelay = Duration.zero;

  Stream<Fix> make(LocationRequest r, int interval) {
    created++;
    late StreamController<Fix> c;
    c = StreamController<Fix>(
      onListen: () => live++,
      onCancel: () async {
        await Future<void>.delayed(cancelDelay);
        live--;
      },
    );
    controllers.add(c);
    return c.stream;
  }
}

void main() {
  test('U1: cancelling the outward subscription stops without deadlock',
      () async {
    final plugin = _Plugin();
    final src = StreamLocationSource(plugin.make);
    final sub = src.start(const LocationRequest()).listen((_) {});
    expect(src.activeSubscriptions, 1);
    await sub.cancel().timeout(const Duration(seconds: 2));
    await src.stop().timeout(const Duration(seconds: 2));
    expect(src.activeSubscriptions, 0);
    expect(plugin.live, 0);
  });

  test('U1: stop is idempotent and completes with a live listener', () async {
    final plugin = _Plugin();
    final src = StreamLocationSource(plugin.make);
    src.start(const LocationRequest()).listen((_) {});
    await src.stop().timeout(const Duration(seconds: 2));
    await src.stop().timeout(const Duration(seconds: 2));
    expect(plugin.live, 0);
  });

  test('U2: overlapping setInterval then stop leaves no live stream',
      () async {
    final plugin = _Plugin()..cancelDelay = const Duration(milliseconds: 20);
    final src = StreamLocationSource(plugin.make);
    src.start(const LocationRequest()).listen((_) {});
    final a = src.setInterval(10);
    final b = src.setInterval(1);
    final s = src.stop();
    await Future.wait([a, b, s]).timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(plugin.live, 0);
    expect(src.activeSubscriptions, 0);
  });

  test('U2: back-to-back setInterval keeps exactly one live stream', () async {
    final plugin = _Plugin()..cancelDelay = const Duration(milliseconds: 10);
    final src = StreamLocationSource(plugin.make);
    src.start(const LocationRequest()).listen((_) {});
    await Future.wait([src.setInterval(10), src.setInterval(1)]);
    expect(plugin.live, 1);
    await src.stop();
    expect(plugin.live, 0);
  });
}
